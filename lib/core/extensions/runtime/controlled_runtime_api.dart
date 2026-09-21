import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
///
/// 2G-C pre-flight corrections (§36.3, §37):
/// - ONE wall-clock deadline covers the whole exchange (connect + send +
///   receive). Previously `Stream.timeout` reset on every chunk, so a server
///   drip-feeding one byte every few seconds could hold a request open far
///   beyond the intended timeout.
/// - Response bytes accumulate in a `BytesBuilder(copy: false)` instead of a
///   growable `List<int>` (which cost ~8 heap bytes per received byte).
/// - Redirects are followed MANUALLY, one hop at a time, with the policy's
///   scheme/host rules re-evaluated on every hop; `dart:io`'s automatic
///   following never re-checked anything. 303 rewrites POST→GET; 307/308
///   preserve method and body; credentials-bearing headers are not forwarded
///   to a different host.
/// - A timed-out or aborted request is closed, so no connection keeps
///   running in the background after the failure is reported.
final class DartIoHttpTransport implements ExtensionHttpTransport {
  DartIoHttpTransport({HttpClient? client, this.policy})
      : _client = client ?? HttpClient();

  final HttpClient _client;

  /// When non-null, redirect hops and every pre-connect target are
  /// re-evaluated through this policy. Null (the standalone-test default)
  /// means redirects are followed by hop count only, with no re-evaluation —
  /// production wiring always supplies the policy.
  final ExtensionRequestPolicy? policy;

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
    final Deadline deadline = Deadline(timeout);
    try {
      Uri current = uri;
      String currentMethod = method.toUpperCase();
      String? currentBody = body;
      Map<String, String> currentHeaders = headers;

      for (int hop = 0; hop <= maxRedirects; hop++) {
        deadline.check();
        final HttpClientRequest request = await _client
            .openUrl(currentMethod, current)
            .timeout(deadline.remaining());
        request.followRedirects = false;
        request.maxRedirects = 0;
        request.headers.set(HttpHeaders.acceptHeader, '*/*');
        currentHeaders.forEach((String name, String value) {
          if (_reservedRequestHeaders.contains(name.toLowerCase())) return;
          try {
            request.headers.set(name, value);
          } on Object {
            // A malformed header name or value must not fail the whole
            // request; it is simply not sent.
          }
        });

        if (currentBody != null) request.write(currentBody);

        final HttpClientResponse response =
            await request.close().timeout(deadline.remaining());

        final int status = response.statusCode;
        if (_isRedirect(status)) {
          final String? location = response.headers.value(
            HttpHeaders.locationHeader,
          );
          if (location == null || location.isEmpty) {
            // A redirect without a target cannot be followed; surface it.
            return ExtensionHttpResult(
              statusCode: status,
              headers: _flattenHeaders(response.headers),
              body: null,
            );
          }
          if (hop == maxRedirects) {
            return ExtensionHttpResult(
              failureType: ExtensionFailureType.unsupported,
              error: 'Redirect limit exceeded (more than $maxRedirects).',
            );
          }
          final ExtensionRequestPolicy? activePolicy = policy;
          if (activePolicy != null) {
            final RequestPolicyDecision? hopDecision =
                activePolicy.evaluateRedirect(
              current: current,
              locationHeader: location,
            );
            if (hopDecision != null) {
              return ExtensionHttpResult(
                failureType: hopDecision.failureType,
                error: '${hopDecision.reason!.code}: ${hopDecision.detail}',
              );
            }
            final Uri target = current.resolveUri(
              Uri.parse(location.trim()),
            );
            final RequestPolicyDecision targetDecision =
                await activePolicy.evaluateTarget(target);
            if (targetDecision.isDenied) {
              return ExtensionHttpResult(
                failureType: targetDecision.failureType,
                error:
                    '${targetDecision.reason!.code}: ${targetDecision.detail}',
              );
            }
          }
          // 303 always becomes GET without a body; 301/302 are followed in
          // practice the way every browser does it (POST → GET); 307/308
          // preserve method and body exactly.
          if (status == 303 ||
              ((status == 301 || status == 302) && currentMethod == 'POST')) {
            currentMethod = 'GET';
            currentBody = null;
          }
          // Sensitive headers must not leak to a different origin.
          final String currentOrigin =
              '${current.scheme}://${current.host}:${current.port}'
                  .toLowerCase();
          final Uri next = current.resolveUri(Uri.parse(location.trim()));
          final String nextOrigin =
              '${next.scheme}://${next.host}:${next.port}'.toLowerCase();
          if (nextOrigin != currentOrigin) {
            currentHeaders = Map<String, String>.from(currentHeaders)
              ..removeWhere(
                (String name, _) =>
                    _sensitiveRedirectHeaders.contains(name.toLowerCase()),
              );
          }
          current = next;
          // Abandon the redirect response's socket without reading it.
          try {
            await response.listen(null).cancel();
          } on Object {
            // Best-effort; the next hop does not depend on this socket.
          }
          continue;
        }

        return await _readBody(
          response,
          deadline: deadline,
          maxBytes: maxBytes,
        );
      }
      // Unreachable: the loop returns on every path (redirect cap denies
      // at hop == maxRedirects).
      return const ExtensionHttpResult(
        failureType: ExtensionFailureType.runtimeError,
        error: 'Request loop ended unexpectedly.',
      );
    } on DeadlineExceeded {
      return const ExtensionHttpResult(
        failureType: ExtensionFailureType.timeout,
        error: 'Request exceeded its overall deadline.',
      );
    } on TimeoutException {
      return const ExtensionHttpResult(
        failureType: ExtensionFailureType.timeout,
        error: 'Request timed out.',
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

  /// Reads one response under the overall deadline, enforcing the size cap.
  Future<ExtensionHttpResult> _readBody(
    HttpClientResponse response, {
    required Deadline deadline,
    required int maxBytes,
  }) async {
    final BytesBuilder builder = BytesBuilder(copy: false);
    try {
      await for (final List<int> chunk in response.timeout(
        deadline.remaining(),
        onTimeout: (EventSink<List<int>> sink) {
          sink.addError(DeadlineExceeded());
          sink.close();
        },
      )) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          await _detach(response);
          return const ExtensionHttpResult(
            failureType: ExtensionFailureType.invalidResult,
            error: 'Response exceeded the configured size limit.',
          );
        }
        deadline.check();
      }
    } on DeadlineExceeded {
      await _detach(response);
      rethrow;
    } on Object {
      await _detach(response);
      rethrow;
    }

    return ExtensionHttpResult(
      statusCode: response.statusCode,
      headers: _flattenHeaders(response.headers),
      body: _decodeBody(builder.takeBytes()),
    );
  }

  /// Closes the response so its socket cannot outlive a failed read.
  static Future<void> _detach(HttpClientResponse response) async {
    try {
      await response.listen(null).cancel();
    } on Object {
      // Detach is best-effort; the deadline failure is what matters.
    }
  }

  static bool _isRedirect(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  /// Headers that could carry credentials and are never re-sent to a
  /// different host on a redirect.
  static const Set<String> _sensitiveRedirectHeaders = <String>{
    'authorization',
    'cookie',
    'proxy-authorization',
  };

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

/// One overall wall-clock budget for a whole exchange (2G-C pre-flight
/// §36.3). Connection setup, sending, redirects and body reads all share it —
/// a slow-drip server can no longer reset the clock per chunk.
final class Deadline {
  Deadline(Duration budget)
      : _end = DateTime.now().add(budget),
        _budget = budget;

  final DateTime _end;
  final Duration _budget;

  /// Remaining wall-clock time, clamped to a small positive floor so a
  /// nearly-expired deadline still gets a chance to fail cleanly instead of
  /// throwing `Duration` argument errors.
  Duration remaining() {
    final Duration left = _end.difference(DateTime.now());
    if (left <= Duration.zero) throw DeadlineExceeded();
    return left;
  }

  /// Throws [DeadlineExceeded] when the budget is spent.
  void check() {
    if (DateTime.now().isAfter(_end)) throw DeadlineExceeded();
  }

  /// The original budget (for tests and diagnostics).
  Duration get budget => _budget;
}

/// The overall exchange deadline was exceeded.
final class DeadlineExceeded implements Exception {
  const DeadlineExceeded();

  @override
  String toString() => 'DeadlineExceeded: the request exceeded its deadline';
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
/// Note on redirects: redirects are followed MANUALLY (one hop at a time) and
/// the policy is re-evaluated on every hop — scheme allow-list, https→http
/// downgrade rule, URL length, and the private-host rules, including fresh
/// resolution of each new hostname. A blocked hop returns the structured
/// refusal with a stable denial code instead of following it. This is stated
/// rather than implied.
final class ControlledExtensionRuntimeApi implements ExtensionRuntimeApi {
  ControlledExtensionRuntimeApi({
    ExtensionRequestPolicy policy = const ExtensionRequestPolicy(),
    ExtensionHttpTransport? transport,
    this.logSink,
  })  : policy = policy,
        transport = transport ?? DartIoHttpTransport(policy: policy),
        _ownsTransport = transport == null;

  final ExtensionRequestPolicy policy;
  final ExtensionHttpTransport transport;
  final bool _ownsTransport;

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
    // 2G-C pre-flight §36.2: the contract's `query` field is part of the
    // request; it is merged into the URL BEFORE the policy runs, so the
    // length limit and every other check apply to what is really sent.
    // Explicit query entries override same-named URL entries (last one wins).
    final String url = _mergeQuery(request.url, request.queryParameters);
    final ExtensionRequest effective = url == request.url
        ? request
        : ExtensionRequest(
            url: url,
            method: request.method,
            headers: request.headers,
            queryParameters: const <String, String>{},
            body: request.body,
            timeout: request.timeout,
          );

    final RequestPolicyDecision decision = await policy.evaluate(effective);
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

    final Uri uri = Uri.parse(url.trim());
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

  /// Merges the contract's `query` map into [rawUrl] (2G-C pre-flight
  /// §36.2). Query entries already present in the URL are preserved
  /// (including duplicate names); an explicit query value overrides a
  /// same-named URL entry because it is appended after it and servers take
  /// the last occurrence. Values are percent-encoded here, including
  /// non-ASCII characters. An unparseable URL is returned as-is so the
  /// policy (not this helper) produces the structured INVALID_URL refusal.
  static String _mergeQuery(String rawUrl, Map<String, String> extra) {
    if (extra.isEmpty) return rawUrl;
    final Uri? parsed = Uri.tryParse(rawUrl.trim());
    if (parsed == null) return rawUrl;
    final List<String> pairs = <String>[
      for (final MapEntry<String, List<String>> entry
          in parsed.queryParametersAll.entries)
        for (final String value in entry.value)
          '${Uri.encodeQueryComponent(entry.key)}='
              '${Uri.encodeQueryComponent(value)}',
      for (final MapEntry<String, String> entry in extra.entries)
        '${Uri.encodeQueryComponent(entry.key)}='
            '${Uri.encodeQueryComponent(entry.value)}',
    ];
    return parsed
        .replace(query: pairs.isEmpty ? null : pairs.join('&'))
        .toString();
  }

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

  /// Releases transport resources when the API created its own transport.
  /// A caller-supplied transport stays the caller's to dispose.
  void dispose() {
    if (!_ownsTransport) return;
    final ExtensionHttpTransport current = transport;
    if (current is DartIoHttpTransport) current.close();
  }
}
