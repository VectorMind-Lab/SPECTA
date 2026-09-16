import '../../errors/specta_failure.dart';
import 'runtime_api.dart';

/// Why a request was refused by [ExtensionRequestPolicy].
enum RequestDenialReason {
  /// The URL could not be parsed, or has no host.
  invalidUrl('INVALID_URL'),

  /// The URL scheme is not on the allow-list.
  schemeNotAllowed('SCHEME_NOT_ALLOWED'),

  /// The HTTP method is not on the allow-list.
  methodNotAllowed('METHOD_NOT_ALLOWED'),

  /// The URL is longer than the policy allows.
  urlTooLong('URL_TOO_LONG'),

  /// The URL carries `user:password@` credentials.
  credentialsInUrl('CREDENTIALS_IN_URL'),

  /// The request body is larger than the policy allows.
  bodyTooLarge('BODY_TOO_LARGE'),

  /// The URL is not absolute (no scheme, or a relative path).
  notAbsolute('NOT_ABSOLUTE');

  const RequestDenialReason(this.code);

  /// Stable, machine-readable identifier.
  final String code;
}

/// The outcome of evaluating a request against a policy.
final class RequestPolicyDecision {
  const RequestPolicyDecision.allow()
    : isDenied = false,
      reason = null,
      failureType = null,
      detail = null;

  const RequestPolicyDecision.deny({
    required RequestDenialReason this.reason,
    required ExtensionFailureType this.failureType,
    required String this.detail,
  }) : isDenied = true;

  final bool isDenied;

  /// Null when allowed.
  final RequestDenialReason? reason;

  /// Canonical failure category reported to the caller and to diagnostics.
  final ExtensionFailureType? failureType;

  /// Developer-facing explanation. Never a user-facing string.
  final String? detail;
}

/// The Phase 1 policy applied to every request an extension makes.
///
/// This is the boundary the audit found missing: the runtime previously
/// forwarded whatever an extension asked for (any scheme, any method, any
/// headers) to the host API. The policy is a plain value object with no
/// dependencies, so it is directly testable and its rules are readable in one
/// place.
///
/// Scope, stated plainly: this is a *transport* policy. It decides what SPECTA
/// is willing to fetch. It deliberately does not attempt to detect or defeat
/// anti-bot systems, authenticate on a user's behalf, bypass paywalls or DRM, or
/// know anything about any particular content provider. It carries no
/// provider-specific logic.
final class ExtensionRequestPolicy {
  const ExtensionRequestPolicy({
    this.allowedSchemes = const <String>{'https', 'http'},
    this.allowedMethods = const <String>{'GET', 'POST', 'HEAD'},
    this.maxResponseBytes = 8 * 1024 * 1024,
    this.maxRequestBodyBytes = 64 * 1024,
    this.maxUrlLength = 2048,
    this.maxRedirects = 5,
    this.defaultTimeout = const Duration(seconds: 15),
    this.maxTimeout = const Duration(seconds: 60),
  });

  /// Schemes SPECTA will fetch.
  ///
  /// `https` and `http` only: both are ordinary web transports that extensions
  /// legitimately need. Everything else — `file`, `ftp`, `data`, `javascript`,
  /// `content`, `blob`, `ws`, `wss` — is refused. `file` in particular would
  /// hand an extension the filesystem through the URL parser.
  final Set<String> allowedSchemes;

  /// Methods SPECTA will send. Read-oriented verbs plus POST, which some
  /// sources require for search. Everything else is refused.
  final Set<String> allowedMethods;

  /// Hard cap on the response body. Overflow aborts the transfer rather than
  /// buffering it.
  final int maxResponseBytes;

  /// Hard cap on the request body an extension may send.
  final int maxRequestBodyBytes;

  final int maxUrlLength;

  /// Redirects followed before the response is returned. The policy is applied
  /// to the URL the extension supplied; see the note in
  /// `ControlledExtensionRuntimeApi`.
  final int maxRedirects;

  /// Applied when an extension does not ask for a timeout.
  final Duration defaultTimeout;

  /// A requested timeout is clamped to this value, not refused.
  final Duration maxTimeout;

  /// Evaluates [request]. Pure and side-effect free.
  ///
  /// The scheme is checked before the host, deliberately. A `file:` URL with no
  /// host (`file:///etc/passwd`) is a scheme violation, not a malformed URL, and
  /// reporting it as the latter would understate what was refused.
  RequestPolicyDecision evaluate(ExtensionRequest request) {
    final String rawUrl = request.url.trim();
    if (rawUrl.isEmpty) {
      return const RequestPolicyDecision.deny(
        reason: RequestDenialReason.invalidUrl,
        failureType: ExtensionFailureType.invalidResult,
        detail: 'URL is empty.',
      );
    }

    final Uri? uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      return RequestPolicyDecision.deny(
        reason: RequestDenialReason.invalidUrl,
        failureType: ExtensionFailureType.invalidResult,
        detail: 'URL could not be parsed: ${request.url}',
      );
    }

    if (uri.scheme.isEmpty) {
      return RequestPolicyDecision.deny(
        reason: RequestDenialReason.notAbsolute,
        failureType: ExtensionFailureType.invalidResult,
        detail: 'URL must be absolute and include a scheme: ${request.url}',
      );
    }

    if (!allowedSchemes.contains(uri.scheme.toLowerCase())) {
      return RequestPolicyDecision.deny(
        reason: RequestDenialReason.schemeNotAllowed,
        failureType: ExtensionFailureType.unsupported,
        detail:
            'Scheme "${uri.scheme}" is not allowed. Allowed: '
            '${_sorted(allowedSchemes).join(', ')}',
      );
    }

    if (uri.host.isEmpty) {
      return RequestPolicyDecision.deny(
        reason: RequestDenialReason.invalidUrl,
        failureType: ExtensionFailureType.invalidResult,
        detail: 'URL has no host: ${request.url}',
      );
    }

    if (uri.userInfo.isNotEmpty) {
      return RequestPolicyDecision.deny(
        reason: RequestDenialReason.credentialsInUrl,
        failureType: ExtensionFailureType.unsupported,
        detail: 'URLs carrying embedded credentials are not allowed.',
      );
    }

    if (request.url.length > maxUrlLength) {
      return RequestPolicyDecision.deny(
        reason: RequestDenialReason.urlTooLong,
        failureType: ExtensionFailureType.invalidResult,
        detail:
            'URL is ${request.url.length} characters; the limit is '
            '$maxUrlLength.',
      );
    }

    if (!allowedMethods.contains(request.method.toUpperCase())) {
      return RequestPolicyDecision.deny(
        reason: RequestDenialReason.methodNotAllowed,
        failureType: ExtensionFailureType.unsupported,
        detail:
            'Method "${request.method}" is not allowed. Allowed: '
            '${_sorted(allowedMethods).join(', ')}',
      );
    }

    final int bodyLength = request.body?.length ?? 0;
    if (bodyLength > maxRequestBodyBytes) {
      return RequestPolicyDecision.deny(
        reason: RequestDenialReason.bodyTooLarge,
        failureType: ExtensionFailureType.invalidResult,
        detail:
            'Request body is $bodyLength bytes; the limit is '
            '$maxRequestBodyBytes.',
      );
    }

    return const RequestPolicyDecision.allow();
  }

  /// The effective timeout: the default when unset, clamped to [maxTimeout].
  Duration effectiveTimeout(Duration requested) {
    if (requested <= Duration.zero) return defaultTimeout;
    return requested > maxTimeout ? maxTimeout : requested;
  }

  static List<String> _sorted(Set<String> values) => values.toList()..sort();
}
