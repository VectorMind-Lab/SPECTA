import 'dart:async';
import 'dart:io';

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
  notAbsolute('NOT_ABSOLUTE'),

  /// The target host resolves to (or literally names) a loopback, private,
  /// link-local, unique-local or unspecified address that the policy blocks
  /// (2G-C pre-flight §37). Covers IPv4, IPv6 and IPv4-mapped IPv6 forms.
  privateHostBlocked('PRIVATE_HOST_BLOCKED'),

  /// The hostname could not be resolved before connecting.
  hostLookupFailed('HOST_LOOKUP_FAILED'),

  /// A redirect was refused: the target host is blocked, the scheme is not
  /// allowed (including an https→http downgrade when disallowed), or the
  /// redirect cap was exhausted.
  redirectBlocked('REDIRECT_BLOCKED');

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
///
/// Local-network boundary (2G-C pre-flight §37): when [blockPrivateHosts] is
/// on (the default in every production wiring), a request whose host is a
/// loopback, private (RFC1918), link-local, unique-local, unspecified or
/// IPv4-mapped form of those addresses is refused, by IP literal AND by
/// resolving the hostname first. This is a best-effort boundary against
/// extensions reaching the user's router admin page or cloud metadata
/// endpoints — it does NOT fully defeat DNS rebinding (a re-resolving DNS
/// server can still answer differently at connect time) and it is not an
/// OS-level sandbox. Stated rather than implied.
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
    this.blockPrivateHosts = true,
    this.allowHttpsToHttpRedirect = false,
    this.hostResolver,
  });

  /// Wall-clock budget for the pre-connect hostname resolution. A resolution
  /// that cannot answer in time denies the request (conservative).
  static const Duration resolveTimeout = Duration(seconds: 5);

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

  /// Redirects followed before the response is returned. The policy is
  /// re-evaluated on every redirect hop (scheme, host rules, method, URL
  /// length); see `ControlledExtensionRuntimeApi`.
  final int maxRedirects;

  /// Applied when an extension does not ask for a timeout.
  final Duration defaultTimeout;

  /// A requested timeout is clamped to this value, not refused.
  final Duration maxTimeout;

  /// Whether loopback/private/link-local/unique-local/unspecified target
  /// hosts are refused. Production wiring leaves this at the safe default
  /// (true); the flag exists so deterministic tests can reach loopback
  /// servers without weakening any release path.
  final bool blockPrivateHosts;

  /// Whether an https→http redirect may be followed. Off by default: a
  /// redirect must not silently downgrade transport security.
  final bool allowHttpsToHttpRedirect;

  /// Injected hostname resolver (test seam). Null means resolve directly
  /// through `InternetAddress.lookup`, which real network tests may use.
  final HostResolver? hostResolver;

  /// Evaluates [request]. Pure and side-effect free EXCEPT for the hostname
  /// resolution performed when [blockPrivateHosts] is on and the host is not
  /// an IP literal (bounded by [resolveTimeout]; a resolution failure denies
  /// rather than allowing).
  Future<RequestPolicyDecision> evaluate(ExtensionRequest request) async {
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

    if (blockPrivateHosts) {
      return _evaluateHost(uri);
    }
    return const RequestPolicyDecision.allow();
  }

  /// The effective timeout: the default when unset, clamped to [maxTimeout].
  Duration effectiveTimeout(Duration requested) {
    if (requested <= Duration.zero) return defaultTimeout;
    return requested > maxTimeout ? maxTimeout : requested;
  }

  /// Host rules for one URL (2G-C pre-flight §37). Denies IP literals in the
  /// blocked ranges by name and by address, and otherwise resolves the
  /// hostname and denies when ANY resolved address is blocked. A resolution
  /// failure denies: SPECTA does not send an extension request to a host it
  /// could not check.
  Future<RequestPolicyDecision> _evaluateHost(Uri uri) async {
    final String host = uri.host;

    // Name-based refusals first (cheap, deterministic).
    final String normalizedHost = host.toLowerCase();
    if (normalizedHost == 'localhost' ||
        normalizedHost.endsWith('.localhost')) {
      return RequestPolicyDecision.deny(
        reason: RequestDenialReason.privateHostBlocked,
        failureType: ExtensionFailureType.unsupported,
        detail: 'Host "$host" is blocked (loopback by name).',
      );
    }

    // Dart's Uri STRIPS the brackets of an IPv6 literal: for
    // 'http://[::1]/x' the host is '::1'. The address parser consumes that
    // form directly; a bare '::1' can never be a reg-name (Uri.tryParse
    // rejects it), so classifying here is safe.
    final IpBlockKind? literal = _classifyIpLiteral(host);
    if (literal != null) {
      return _denyBlockedHost(host, literal);
    }

    final List<InternetAddress> addresses;
    try {
      final HostResolver resolver =
          hostResolver ?? _defaultHostResolver;
      addresses = await resolver(host).timeout(resolveTimeout);
    } on TimeoutException {
      return RequestPolicyDecision.deny(
        reason: RequestDenialReason.hostLookupFailed,
        failureType: ExtensionFailureType.networkError,
        detail: 'Resolving host "$host" timed out; request refused.',
      );
    } on Object catch (e) {
      return RequestPolicyDecision.deny(
        reason: RequestDenialReason.hostLookupFailed,
        failureType: ExtensionFailureType.networkError,
        detail: 'Resolving host "$host" failed: $e',
      );
    }

    for (final InternetAddress address in addresses) {
      final IpBlockKind? blocked = _classifyAddress(
        address: address,
        parsedFromLiteral: false,
      );
      if (blocked != null) {
        return _denyBlockedHost(address.address, blocked);
      }
    }

    return const RequestPolicyDecision.allow();
  }

  RequestPolicyDecision _denyBlockedHost(String host, IpBlockKind kind) {
    return RequestPolicyDecision.deny(
      reason: RequestDenialReason.privateHostBlocked,
      failureType: ExtensionFailureType.unsupported,
      detail: 'Host "$host" is blocked ($kind).',
    );
  }

  /// Resolves a hostname before connecting (2G-C pre-flight §37.2).
  /// Best-effort by design: it does not fully defeat DNS rebinding, because
  /// the resolver can answer differently at connect time.
  static Future<List<InternetAddress>> _defaultHostResolver(String host) =>
      InternetAddress.lookup(host);

  /// Whether [host] is an IP literal in a blocked range, and which.
  static IpBlockKind? _classifyIpLiteral(String host) {
    // Only a parseable address literal qualifies; a bare IPv6 textual form
    // like '::1' contains ':' and cannot be a reg-name host, so parsing it is
    // safe here (the URL parser never hands this method a reg-name).
    final InternetAddress? address = InternetAddress.tryParse(host);
    if (address == null) return null;
    return _classifyAddress(address: address, parsedFromLiteral: true);
  }

  /// Classifies one address. [parsedFromLiteral] marks addresses the policy
  /// did NOT resolve itself (URL literals). IPv4-mapped IPv6 addresses
  /// (`::ffff:a.b.c.d`, dotted or hex textual form) are really IPv4 targets
  /// and are classified against the IPv4 rules in both cases.
  static IpBlockKind? _classifyAddress({
    required InternetAddress address,
    required bool parsedFromLiteral,
  }) {
    if (address.type == InternetAddressType.IPv4) {
      final int kind = _ipv4BlockKind(address.address);
      return kind == _none ? null : IpBlockKind.values[kind];
    }
    final String lower = address.address.toLowerCase();
    if (lower.startsWith('::ffff:')) {
      final IpBlockKind? mapped = _classifyMapped(lower);
      if (mapped != null) return mapped;
    }
    if (parsedFromLiteral) {
      final int kind = _ipv6BlockKind(lower);
      return kind == _none ? null : IpBlockKind.values[kind];
    }
    // A resolved non-IPv4, non-mapped address: apply the IPv6 textual rules.
    final int kind = _ipv6BlockKind(lower);
    return kind == _none ? null : IpBlockKind.values[kind];
  }

  /// Classifies the IPv4 target inside a `::ffff:`-prefixed address.
  /// The tail is either dotted (`1.2.3.4`) or two hex groups (`102:304`).
  /// Best-effort, canonical compressed form only.
  static IpBlockKind? _classifyMapped(String lower) {
    final String tail = lower.substring('::ffff:'.length);
    if (tail.contains('.')) {
      final int kind = _ipv4BlockKind(tail);
      return kind == _none ? null : IpBlockKind.values[kind];
    }
    final List<String> groups =
        lower.split(':').where((String g) => g.isNotEmpty).toList();
    if (groups.length != 3 || groups[0] != 'ffff') return null;
    final int? hi = int.tryParse(groups[1], radix: 16);
    final int? lo = int.tryParse(groups[2], radix: 16);
    if (hi == null || lo == null) return null;
    final int kind = _ipv4BlockKind(
      '${hi >> 8}.${hi & 255}.${lo >> 8}.${lo & 255}',
    );
    return kind == _none ? null : IpBlockKind.values[kind];
  }

  static const int _none = -1;

  static int _ipv4BlockKind(String dotted) {
    final List<String> parts = dotted.split('.');
    if (parts.length != 4) return _none;
    final List<int> octets = <int>[];
    for (final String part in parts) {
      final int? value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return _none;
      octets.add(value);
    }
    final int a = octets[0];
    final int b = octets[1];
    if (a == 127) return IpBlockKind.loopback.index;
    if (a == 10) return IpBlockKind.private.index;
    if (a == 172 && b >= 16 && b <= 31) return IpBlockKind.private.index;
    if (a == 192 && b == 168) return IpBlockKind.private.index;
    if (a == 169 && b == 254) return IpBlockKind.linkLocal.index;
    if (a == 0) return IpBlockKind.unspecified.index;
    return _none;
  }

  static int _ipv6BlockKind(String textual) {
    // The address comes from InternetAddress.tryParse / a resolved lookup,
    // so the textual form is canonical (e.g. '::1', '::', 'fe80::1').
    final String lower = textual.toLowerCase();
    if (lower == '::1') return IpBlockKind.loopback.index;
    if (lower == '::' || lower.isEmpty) {
      return IpBlockKind.unspecified.index;
    }
    final int? first = int.tryParse(lower.split(':').first, radix: 16);
    if (first == null) return _none;
    if (first >= 0xfe80 && first <= 0xfebf) {
      return IpBlockKind.linkLocal.index; // fe80::/10
    }
    if (first >= 0xfc00 && first <= 0xfdff) {
      return IpBlockKind.uniqueLocal.index; // fc00::/7
    }
    return _none;
  }

  /// Redirect mechanics shared with the transport (2G-C pre-flight §37.3):
  /// one redirect hop evaluated BEFORE it is followed.
  ///
  /// Returns the hop to send, or null when the redirect is refused with
  /// [redirectBlocked]. Enforces the scheme allow-list on the target, the
  /// https→http downgrade rule, the URL length cap, and that POST/PUT bodies
  /// are never replayed across a 303 (the caller rewrote the method to GET).
  RequestPolicyDecision? evaluateRedirect({
    required Uri current,
    required String locationHeader,
  }) {
    final Uri? target = Uri.tryParse(locationHeader.trim());
    if (target == null) {
      return RequestPolicyDecision.deny(
        reason: RequestDenialReason.redirectBlocked,
        failureType: ExtensionFailureType.unsupported,
        detail: 'Redirect Location could not be parsed.',
      );
    }
    final Uri resolved = current.resolveUri(target);
    if (!resolved.hasScheme || resolved.host.isEmpty) {
      return RequestPolicyDecision.deny(
        reason: RequestDenialReason.redirectBlocked,
        failureType: ExtensionFailureType.unsupported,
        detail: 'Redirect target is not an absolute URL.',
      );
    }
    final String scheme = resolved.scheme.toLowerCase();
    if (!allowedSchemes.contains(scheme)) {
      return RequestPolicyDecision.deny(
        reason: RequestDenialReason.redirectBlocked,
        failureType: ExtensionFailureType.unsupported,
        detail: 'Redirect to "$scheme" URL is not allowed.',
      );
    }
    if (!allowHttpsToHttpRedirect &&
        current.scheme.toLowerCase() == 'https' &&
        scheme == 'http') {
      return RequestPolicyDecision.deny(
        reason: RequestDenialReason.redirectBlocked,
        failureType: ExtensionFailureType.unsupported,
        detail: 'Redirect would downgrade https to http; refused.',
      );
    }
    if (resolved.toString().length > maxUrlLength) {
      return RequestPolicyDecision.deny(
        reason: RequestDenialReason.redirectBlocked,
        failureType: ExtensionFailureType.invalidResult,
        detail: 'Redirect URL exceeds the URL length limit.',
      );
    }
    // Full rules on the target (host rules included) run through the normal
    // evaluate() in the transport; this method only owns the hop itself.
    return null;
  }

  /// The effective host decision for one already-parsed URL — used by the
  /// transport between redirect hops, where evaluate()'s per-request checks
  /// (method, body, credentials) were already applied to the original.
  Future<RequestPolicyDecision> evaluateTarget(Uri resolved) async {
    if (resolved.toString().length > maxUrlLength) {
      return RequestPolicyDecision.deny(
        reason: RequestDenialReason.urlTooLong,
        failureType: ExtensionFailureType.invalidResult,
        detail:
            'URL is ${resolved.toString().length} characters; the limit is '
            '$maxUrlLength.',
      );
    }
    if (!allowedSchemes.contains(resolved.scheme.toLowerCase())) {
      return RequestPolicyDecision.deny(
        reason: RequestDenialReason.schemeNotAllowed,
        failureType: ExtensionFailureType.unsupported,
        detail: 'Scheme "${resolved.scheme}" is not allowed. Allowed: '
            '${_sorted(allowedSchemes).join(", ")}',
      );
    }
    if (blockPrivateHosts) {
      return _evaluateHost(resolved);
    }
    return const RequestPolicyDecision.allow();
  }

  static List<String> _sorted(Set<String> values) => values.toList()..sort();
}

/// Which blocked address family matched (for diagnostics only).
enum IpBlockKind {
  loopback,
  private,
  linkLocal,
  uniqueLocal,
  unspecified;

  @override
  String toString() => switch (this) {
        loopback => 'loopback',
        private => 'private',
        linkLocal => 'link-local',
        uniqueLocal => 'unique-local',
        unspecified => 'unspecified',
      };
}

/// Resolves a hostname to its addresses before a request is dispatched.
typedef HostResolver = Future<List<InternetAddress>> Function(String host);
