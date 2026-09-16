/// Controlled network request abstraction exposed to extensions via `request()`.
///
/// Extensions never touch the native networking stack directly — every request
/// is described with this model and dispatched by the host through
/// [ExtensionRuntimeApi.request].
///
/// Scope note (Phase 1): this type *transports* what the extension asked for.
/// The runtime does not yet restrict the URL scheme, HTTP method or headers a
/// request may use; that policy belongs to the concrete
/// [ExtensionRuntimeApi] implementation, which is not part of Phase 1.
final class ExtensionRequest {
  const ExtensionRequest({
    required this.url,
    required this.method,
    this.headers = const <String, String>{},
    this.queryParameters = const <String, String>{},
    this.body,
    this.timeout = const Duration(seconds: 15),
  });

  final String url;
  final String method;
  final Map<String, String> headers;
  final Map<String, String> queryParameters;
  final String? body;
  final Duration timeout;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'url': url,
    'method': method,
    'headers': headers,
    'query': queryParameters,
    'body': body,
    'timeout': timeout.inMilliseconds,
  };
}

/// Structured response returned by the controlled `request()` API.
///
/// Extensions receive structured data — never raw socket or file access.
final class ExtensionResponse {
  const ExtensionResponse({
    required this.status,
    required this.ok,
    this.headers = const <String, String>{},
    this.body,
    this.json,
    this.latency = 0,
    this.error,
    this.errorType,
  });

  /// HTTP status code, or null if no response was received.
  final int? status;

  /// Whether the request completed successfully (2xx range).
  final bool ok;

  /// Response headers.
  final Map<String, String> headers;

  /// Raw response body as a string.
  final String? body;

  /// Parsed JSON body, or null when the response is not JSON.
  final dynamic json;

  /// Request latency in milliseconds.
  final int latency;

  /// Developer-facing explanation when [ok] is false. Null on success.
  final String? error;

  /// Canonical [ExtensionFailureType.code] when [ok] is false, so a caller can
  /// branch on the failure category without parsing [error]. Null on success.
  final String? errorType;

  /// Whether this response represents a failure rather than a payload.
  bool get isFailure => !ok;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'status': status,
    'ok': ok,
    'headers': headers,
    'body': body,
    'json': json,
    'latency': latency,
    if (error != null) 'error': error,
    if (errorType != null) 'errorType': errorType,
  };
}

/// Log levels available to extensions through `log()`.
enum ExtensionLogLevel {
  debug('debug'),
  info('info'),
  warning('warning'),
  error('error');

  const ExtensionLogLevel(this.code);
  final String code;
}

/// Abstraction over the runtime APIs injected into the JS sandbox.
///
/// These are the only capabilities SPECTA *exposes* to extension code: the
/// sandbox registers no filesystem, contacts, SMS, device-identifier, SQLite,
/// native or Flutter bindings, so extension JavaScript has no route to them.
///
/// That is a deliberately restricted API surface, not an OS-level sandbox.
/// Extension code still executes inside the SPECTA process, and no CPU-time or
/// memory ceiling is currently applied to it — see
/// `lib/core/extensions/runtime/flutter_js_sandbox.dart` for the precise
/// boundary.
abstract interface class ExtensionRuntimeApi {
  /// Controlled network request.  Extensions use this instead of `fetch()`
  /// or `XMLHttpRequest`.
  Future<ExtensionResponse> request(ExtensionRequest request);

  /// Controlled logging.  Extensions can only write through this channel.
  void log(ExtensionLogLevel level, String message);
}

/// Handler invoked when JavaScript calls `sendMessage(channel, message)`.
typedef JsMessageHandler = dynamic Function(dynamic args);

/// Thrown when a JavaScript evaluation fails inside the sandbox.
final class JsEvalException implements Exception {
  JsEvalException(this.message, {this.detail});

  final String message;

  /// Developer-only diagnostics.  Never rendered on a user screen.
  final String? detail;

  @override
  String toString() => 'JsEvalException: $message';
}

/// Abstract contract for a JavaScript execution sandbox.
///
/// This interface decouples the extension runtime from any specific JS engine
/// implementation.  Tests provide a fake so lifecycle, error isolation and
/// contract logic can be exercised without a native JS engine.
abstract class ExtensionJsSandbox {
  bool get isReady;

  /// Whether [dispose] has run. Exposed so resource cleanup is observable —
  /// a runtime whose load failed must still release its engine.
  bool get isDisposed;

  Future<void> init();

  void onMessage(String channel, JsMessageHandler handler);

  Future<String> evaluate(String code);

  Future<String> evaluateAsync(String expression);

  Future<void> dispose();
}
