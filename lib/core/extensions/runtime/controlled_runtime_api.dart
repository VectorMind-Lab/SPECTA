import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../errors/specta_failure.dart';
import 'request_policy.dart';
import 'runtime_api.dart';

/// Sink for extension log output.
///
/// The extension layer stays free of Flutter imports, so the default is a
/// no-op and the application wires a real sink (see
/// `extension_providers.dart`).
typedef ExtensionLogSink = void Function(
  ExtensionLogLevel level,
  String message,
);

/// The transport result of a single HTTP exchange, before SPECTA decides what
/// to tell the extension.
final class ExtensionHttpResult {
  const ExtensionHttpResult({
    this.statusCode,
    this.headers = const <String, String>{},
    this.body,
    this.failureType,
    this.error,
  });

  /// Null when no response was received (transport failure).
  final int? statusCode;
  final Map<String, String> headers;
  final String? body;

  /// Set on transport failure. Transport failures never throw past the API.
  final ExtensionFailureType? failureType;
  final String? error;
}

/// Performs one HTTP exchange. Separated from the policy so the policy and the
/// API's error handling are testable without a network.
abstract interface class ExtensionHttpTransport {
  Future<ExtensionHttpResult> send({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
    required int maxBytes,
    required int maxRedirects,
  });
}

/// [ExtensionHttpTransport] built on `dart:io`'s `HttpClient`.
///
/// No extra package is introduced: `dart:io` is already available on every
/// target SPECTA builds for, and it exposes the timeouts, redirect cap and
/// streaming read the policy needs.
final class DartIoHttpTransport implements ExtensionHttpTransport {
  DartIoHttpTransport({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<ExtensionHttpResult> send({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
    required int maxBytes,
    required int maxRedirects,
  }) async {
    try {
      final HttpClientRequest request = await _client
          .openUrl(method, uri)
          .timeout(timeout);

      request.followRedirects = maxRedirects > 0;
      request.maxRedirects = maxRedirects;
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      headers.forEach((String name, String value) {
        if (_reservedRequestHeaders.contains(name.toLowerCase())) return;
        try {
          request.headers.set(name, value);
        } on Object {
          // A malformed header name or value must not fail the whole request;
          // it is simply not sent.
        }
      });

      if (body != null) request.write(body);

      final HttpClientResponse response = await request.close().timeout(
        timeout,
      );

      final List<int> bytes = <int>[];
      await for (final List<int> chunk in response.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) {
          return const ExtensionHttpResult(
            failureType: ExtensionFailureType.invalidResult,
            error: 'Response exceeded the configured size limit.',
          );
        }
      }

      return ExtensionHttpResult(
        statusCode: response.statusCode,
        headers: _flattenHeaders(response.headers),
        body: _decodeBody(bytes),
      );
    } on TimeoutException catch (e) {
      return ExtensionHttpResult(
        failureType: ExtensionFailureType.timeout,
        error: 'Request timed out: $e',
      );
    } on SocketException catch (e) {
      return ExtensionHttpResult(
        failureType: ExtensionFailureType.networkError,
        error: 'Socket failure: ${e.message}',
      );
    } on HandshakeException catch (e) {
      return ExtensionHttpResult(
        failureType: ExtensionFailureType.networkError,
        error: 'TLS handshake failed: ${e.message}',
      );
    } on HttpException catch (e) {
      return ExtensionHttpResult(
        failureType: ExtensionFailureType.networkError,
        error: 'HTTP failure: ${e.message}',
      );
    } on FormatException catch (e) {
      return ExtensionHttpResult(
        failureType: ExtensionFailureType.invalidResult,
        error: 'Malformed URL: ${e.message}',
      );
    }
  }

  /// Headers the client owns. An extension may not override them.
  static const Set<String> _reservedRequestHeaders = <String>{
    'host',
    'content-length',
    'connection',
    'transfer-encoding',
    'upgrade',
  };

  static Map<String, String> _flattenHeaders(HttpHeaders headers) {
    final Map<String, String> flat = <String, String>{};
    headers.forEach((String name, List<String> values) {
      flat[name.toLowerCase()] = values.join(', ');
    });
    return flat;
  }

  static String _decodeBody(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      // Not UTF-8. Extensions that need raw bytes cannot currently be served;
      // returning the Latin-1 projection keeps the response usable and marks
      // it as lossy rather than throwing.
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  /// Frees the underlying client. Called when the owning API is disposed.
  void close() => _client.close(force: true);
}

/// The Phase 1 controlled request boundary.
///
/// Every extension network call passes through here. The sequence is:
///
/// 1. evaluate the request against [policy];
/// 2. refuse it with a structured result if the policy denies it;
/// 3. otherwise dispatch it through [transport] with the clamped timeout and
///    the response-size cap;
/// 4. map transport outcomes onto canonical [ExtensionFailureType] values;
/// 5. log a redacted summary.
///
/// It never throws: a failure is always an [ExtensionResponse] with `ok: false`
/// and a populated [ExtensionResponse.errorType].
///
/// Log lines carry the method, scheme and host only. The full URL is
/// deliberately not logged, because extension URLs routinely embed tokens and
/// signing parameters.
///
/// Note on redirects: the policy is evaluated against the URL the extension
/// supplied. Redirects are followed up to [ExtensionRequestPolicy.maxRedirects]
/// and are not re-evaluated against the scheme allow-list — `dart:io` only
/// follows HTTP(S) redirects, and the initial URL was already checked. This is
/// stated rather than implied.
final class ControlledExtensionRuntimeApi implements ExtensionRuntimeApi {
  ControlledExtensionRuntimeApi({
    this.policy = const ExtensionRequestPolicy(),
    ExtensionHttpTransport? transport,
    this.logSink,
  }) : transport = transport ?? DartIoHttpTransport();

  final ExtensionRequestPolicy policy;
  final ExtensionHttpTransport transport;

  /// Where extension log output goes. Null means logs are discarded.
  final ExtensionLogSink? logSink;

  int _requestCount = 0;
  int _deniedCount = 0;

  /// Requests dispatched through the transport (excluding denied ones).
  int get requestCount => _requestCount;

  /// Requests refused by the policy before any network activity.
  int get deniedCount => _deniedCount;

  @override
  Future<ExtensionResponse> request(ExtensionRequest request) async {
    final RequestPolicyDecision decision = policy.evaluate(request);
    if (decision.isDenied) {
      _deniedCount++;
      final RequestDenialReason reason = decision.reason!;
      _log(
        ExtensionLogLevel.warning,
        'request refused: ${reason.code} '
        '(${request.method.toUpperCase()} ${_safeEndpoint(request.url)})',
      );
      return ExtensionResponse(
        status: null,
        ok: false,
        errorType: decision.failureType!.code,
        error: '${reason.code}: ${decision.detail}',
      );
    }

    final Uri uri = Uri.parse(request.url.trim());
    final Duration timeout = policy.effectiveTimeout(request.timeout);
    final Stopwatch watch = Stopwatch()..start();

    _requestCount++;
    final ExtensionHttpResult result = await transport.send(
      uri: uri,
      method: request.method.toUpperCase(),
      headers: request.headers,
      body: request.body,
      timeout: timeout,
      maxBytes: policy.maxResponseBytes,
      maxRedirects: policy.maxRedirects,
    );
    watch.stop();

    if (result.statusCode == null) {
      _log(
        ExtensionLogLevel.error,
        'request failed: ${request.method.toUpperCase()} '
        '${_safeEndpoint(request.url)} '
        '(${result.failureType?.code ?? 'RUNTIME_ERROR'})',
      );
      return ExtensionResponse(
        status: null,
        ok: false,
        latency: watch.elapsedMilliseconds,
        errorType:
            (result.failureType ?? ExtensionFailureType.runtimeError).code,
        error: result.error ?? 'Request failed.',
      );
    }

    final int status = result.statusCode!;
    final bool ok = status >= 200 && status < 300;
    _log(
      ok ? ExtensionLogLevel.debug : ExtensionLogLevel.warning,
      'request ${request.method.toUpperCase()} ${_safeEndpoint(request.url)} '
      '-> $status in ${watch.elapsedMilliseconds}ms',
    );

    return ExtensionResponse(
      status: status,
      ok: ok,
      headers: result.headers,
      body: result.body,
      json: _tryDecodeJson(result.body),
      latency: watch.elapsedMilliseconds,
      errorType: ok ? null : ExtensionFailureType.httpError.code,
      error: ok ? null : 'HTTP $status',
    );
  }

  @override
  void log(ExtensionLogLevel level, String message) => _log(level, message);

  void _log(ExtensionLogLevel level, String message) {
    logSink?.call(level, message);
  }

  /// Method, scheme and host only — never the path or query string.
  static String _safeEndpoint(String rawUrl) {
    final Uri? uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.host.isEmpty) return '<unparseable-url>';
    return '${uri.scheme}://${uri.host}';
  }

  static dynamic _tryDecodeJson(String? body) {
    if (body == null) return null;
    final String trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
    try {
      return jsonDecode(trimmed);
    } on FormatException {
      return null;
    }
  }

  /// Releases transport resources where the transport holds any.
  void dispose() {
    final ExtensionHttpTransport current = transport;
    if (current is DartIoHttpTransport) current.close();
  }
}
