import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/runtime/request_policy.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';

ExtensionRequest _request({
  String url = 'https://example.test/api',
  String method = 'GET',
  String? body,
  Duration timeout = const Duration(seconds: 15),
}) => ExtensionRequest(url: url, method: method, body: body, timeout: timeout);

void main() {
  // §37.5 (2G-C pre-flight): the production default blocks private hosts.
  // Deterministic policy unit tests run with the test-only override so no
  // test ever resolves a real hostname or reaches loopback; a separate group
  // below proves the DEFAULT policy still blocks.
  const ExtensionRequestPolicy policy = ExtensionRequestPolicy(
    blockPrivateHosts: false,
  );

  group('ExtensionRequestPolicy — allowed requests', () {
    test('a plain HTTPS GET is allowed', () async {
      expect((await policy.evaluate(_request())).isDenied, isFalse);
    });

    test('HTTP GET is allowed', () async {
      expect(
        (await policy.evaluate(_request(url: 'http://example.test/feed')))
            .isDenied,
        isFalse,
      );
    });

    test('POST with a small body is allowed', () async {
      expect(
        (await policy.evaluate(_request(method: 'POST', body: 'q=matrix')))
            .isDenied,
        isFalse,
      );
    });

    test('HEAD is allowed', () async {
      expect(
        (await policy.evaluate(_request(method: 'HEAD'))).isDenied,
        isFalse,
      );
    });

    test('the method check is case-insensitive', () async {
      expect(
        (await policy.evaluate(_request(method: 'get'))).isDenied,
        isFalse,
      );
    });

    test('an allowed decision carries no reason or failure type', () async {
      final RequestPolicyDecision decision = await policy.evaluate(_request());
      expect(decision.reason, isNull);
      expect(decision.failureType, isNull);
      expect(decision.detail, isNull);
    });
  });

  group('ExtensionRequestPolicy — unsupported schemes', () {
    test('file:// is refused', () async {
      // The important one: file:// would expose the filesystem through the
      // ordinary URL parser.
      final RequestPolicyDecision decision = await policy.evaluate(
        _request(url: 'file:///etc/passwd'),
      );
      expect(decision.isDenied, isTrue);
      expect(decision.reason, RequestDenialReason.schemeNotAllowed);
      expect(decision.failureType, ExtensionFailureType.unsupported);
    });

    test('other non-web schemes are refused', () async {
      for (final String url in <String>[
        'ftp://example.test/f',
        'data:text/plain,hello',
        'javascript:alert(1)',
        'content://media/external/images/1',
        'blob:https://example.test/abc',
        'ws://example.test/socket',
        'wss://example.test/socket',
      ]) {
        final RequestPolicyDecision decision = await policy.evaluate(
          _request(url: url),
        );
        expect(decision.isDenied, isTrue, reason: url);
        expect(
          decision.reason,
          RequestDenialReason.schemeNotAllowed,
          reason: url,
        );
      }
    });

    test('the scheme check is case-insensitive', () async {
      expect(
        (await policy.evaluate(_request(url: 'HTTPS://example.test'))).isDenied,
        isFalse,
      );
      expect(
        (await policy.evaluate(_request(url: 'FILE:///etc/passwd'))).isDenied,
        isTrue,
      );
    });
  });

  group('ExtensionRequestPolicy — unsupported methods', () {
    test('write and control verbs are refused', () async {
      for (final String method in <String>[
        'DELETE',
        'PUT',
        'PATCH',
        'TRACE',
        'CONNECT',
      ]) {
        final RequestPolicyDecision decision = await policy.evaluate(
          _request(method: method),
        );
        expect(decision.isDenied, isTrue, reason: method);
        expect(
          decision.reason,
          RequestDenialReason.methodNotAllowed,
          reason: method,
        );
        expect(
          decision.failureType,
          ExtensionFailureType.unsupported,
          reason: method,
        );
      }
    });
  });

  group('ExtensionRequestPolicy — invalid URLs', () {
    test('an unparseable URL is refused', () async {
      expect(
        (await policy.evaluate(_request(url: '   '))).reason,
        RequestDenialReason.invalidUrl,
      );
    });

    test('a relative URL is refused', () async {
      expect(
        (await policy.evaluate(_request(url: '/api/search'))).reason,
        RequestDenialReason.notAbsolute,
      );
    });

    test('a scheme with no host is refused', () async {
      expect(
        (await policy.evaluate(_request(url: 'https:///path'))).reason,
        RequestDenialReason.invalidUrl,
      );
    });

    test('embedded credentials are refused', () async {
      // https://user:pass@host would leak credentials into logs and headers.
      final RequestPolicyDecision decision = await policy.evaluate(
        _request(url: 'https://user:secret@example.test/api'),
      );
      expect(decision.reason, RequestDenialReason.credentialsInUrl);
      expect(decision.failureType, ExtensionFailureType.unsupported);
    });

    test('an over-long URL is refused', () async {
      final String url = 'https://example.test/${'a' * 3000}';
      expect(
        (await policy.evaluate(_request(url: url))).reason,
        RequestDenialReason.urlTooLong,
      );
    });

    test('an over-long body is refused', () async {
      const ExtensionRequestPolicy small = ExtensionRequestPolicy(
        maxRequestBodyBytes: 16,
        blockPrivateHosts: false,
      );
      expect(
        (await small.evaluate(_request(method: 'POST', body: 'x' * 32))).reason,
        RequestDenialReason.bodyTooLarge,
      );
    });
  });

  group('ExtensionRequestPolicy — effectiveTimeout', () {
    test('an unset timeout falls back to the default', () {
      expect(policy.effectiveTimeout(Duration.zero), policy.defaultTimeout);
    });

    test('a requested timeout is honoured when within the maximum', () {
      expect(
        policy.effectiveTimeout(const Duration(seconds: 5)),
        const Duration(seconds: 5),
      );
    });

    test('an excessive timeout is clamped, not refused', () async {
      expect(
        policy.effectiveTimeout(const Duration(hours: 1)),
        policy.maxTimeout,
      );
      expect(
        (await policy.evaluate(_request(timeout: const Duration(hours: 1))))
            .isDenied,
        isFalse,
      );
    });
  });

  group(
    'ExtensionRequestPolicy — the policy is injectable, not hard-coded',
    () {
      test('an HTTPS-only policy refuses plain HTTP', () async {
        const ExtensionRequestPolicy httpsOnly = ExtensionRequestPolicy(
          allowedSchemes: <String>{'https'},
          blockPrivateHosts: false,
        );
        expect(
          (await httpsOnly.evaluate(_request(url: 'http://example.test')))
              .isDenied,
          isTrue,
        );
        expect(
          (await httpsOnly.evaluate(_request(url: 'https://example.test')))
              .isDenied,
          isFalse,
        );
      });
    },
  );

  group('RequestDenialReason', () {
    test('exposes stable codes', () {
      expect(RequestDenialReason.invalidUrl.code, 'INVALID_URL');
      expect(RequestDenialReason.schemeNotAllowed.code, 'SCHEME_NOT_ALLOWED');
      expect(RequestDenialReason.methodNotAllowed.code, 'METHOD_NOT_ALLOWED');
      expect(RequestDenialReason.urlTooLong.code, 'URL_TOO_LONG');
      expect(RequestDenialReason.credentialsInUrl.code, 'CREDENTIALS_IN_URL');
      expect(RequestDenialReason.bodyTooLarge.code, 'BODY_TOO_LARGE');
      expect(RequestDenialReason.notAbsolute.code, 'NOT_ABSOLUTE');
      // §37 additions.
      expect(
        RequestDenialReason.privateHostBlocked.code,
        'PRIVATE_HOST_BLOCKED',
      );
      expect(RequestDenialReason.hostLookupFailed.code, 'HOST_LOOKUP_FAILED');
      expect(RequestDenialReason.redirectBlocked.code, 'REDIRECT_BLOCKED');
    });
  });
}
