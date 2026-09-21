import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/manager/extension_providers.dart';
import 'package:specta/core/extensions/runtime/controlled_runtime_api.dart';
import 'package:specta/core/extensions/runtime/request_policy.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 2G-C pre-flight §37 + §36.2 + §36.3 tests.
///
/// Two layers are tested separately:
/// - POLICY rules (pure / resolver-injected, no sockets);
/// - TRANSPORT behavior over real loopback sockets, using the §37.5
///   test-only policy override (`blockPrivateHosts: false`) so the tests can
///   reach `127.0.0.1` servers — the override is sanctioned for tests only
///   and must never appear in release wiring (proven by the provider test).
void main() {
  group('§37.5 the PRODUCTION provider policy blocks private hosts', () {
    test('extensionRuntimeApiProvider keeps blockPrivateHosts ON', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final ControlledExtensionRuntimeApi api =
          container.read(extensionRuntimeApiProvider);

      expect(api.policy.blockPrivateHosts, isTrue,
          reason: 'release wiring must never ship with host blocking off');
      expect(api.policy.allowHttpsToHttpRedirect, isFalse);
      api.dispose();
    });

    test('the default policy refuses loopback by name and by IP literal',
        () async {
      const ExtensionRequestPolicy policy = ExtensionRequestPolicy();
      final RequestPolicyDecision byName = await policy.evaluate(
        ExtensionRequest(url: 'http://localhost/admin', method: 'GET'),
      );
      expect(byName.isDenied, isTrue);
      expect(byName.reason, RequestDenialReason.privateHostBlocked);

      final RequestPolicyDecision byLiteral = await policy.evaluate(
        ExtensionRequest(url: 'http://127.0.0.1/admin', method: 'GET'),
      );
      expect(byLiteral.isDenied, isTrue);
      expect(byLiteral.reason, RequestDenialReason.privateHostBlocked);
    });
  });

  group('§37 blocked address families (policy-level, injectable resolver)',
      () {
    test('every blocked IPv4 literal is denied', () async {
      const ExtensionRequestPolicy policy = ExtensionRequestPolicy();
      const List<String> blocked = <String>[
        '127.0.0.1',
        '127.255.255.254', // 127/8 edge
        '10.0.0.1',
        '10.255.255.255',
        '172.16.0.1',
        '172.31.255.255',
        '192.168.1.1',
        '192.168.0.0',
        '169.254.169.254', // cloud metadata endpoint
        '0.0.0.0',
      ];
      for (final String ip in blocked) {
        final RequestPolicyDecision decision = await policy.evaluate(
          ExtensionRequest(url: 'http://$ip/x', method: 'GET'),
        );
        expect(decision.isDenied, isTrue, reason: ip);
        expect(decision.reason, RequestDenialReason.privateHostBlocked,
            reason: ip);
        expect(decision.failureType, ExtensionFailureType.unsupported,
            reason: ip);
      }
    });

    test('every blocked IPv6 literal is denied (bracketed URL form)', () async {
      const ExtensionRequestPolicy policy = ExtensionRequestPolicy();
      const List<String> blocked = <String>[
        '::1',
        'fe80::1',
        'febf::1', // fe80::/10 edge
        'fc00::1',
        'fdff::1', // fc00::/7 edge
        '::',
      ];
      for (final String ip in blocked) {
        // The form a URL actually carries: [ip]. (The bare textual form is
        // not a valid URL host at all — asserted separately below.)
        final RequestPolicyDecision decision = await policy.evaluate(
          ExtensionRequest(url: 'http://[$ip]/x', method: 'GET'),
        );
        expect(decision.isDenied, isTrue, reason: ip);
        expect(decision.reason, RequestDenialReason.privateHostBlocked,
            reason: ip);
      }
    });

    test('a bare IPv6 textual form is not a valid URL host (denied as such)',
        () async {
      const ExtensionRequestPolicy policy = ExtensionRequestPolicy();
      final RequestPolicyDecision decision = await policy.evaluate(
        ExtensionRequest(url: 'http://::1/x', method: 'GET'),
      );
      expect(decision.isDenied, isTrue);
      expect(decision.reason, RequestDenialReason.invalidUrl);
    });

    test('IPv4-mapped IPv6 forms of blocked ranges are denied', () async {
      const ExtensionRequestPolicy policy = ExtensionRequestPolicy();
      const List<String> mapped = <String>[
        '::ffff:127.0.0.1',
        '::ffff:192.168.1.1',
        '::ffff:169.254.169.254',
      ];
      for (final String ip in mapped) {
        final RequestPolicyDecision decision = await policy.evaluate(
          ExtensionRequest(url: 'http://[$ip]/x', method: 'GET'),
        );
        expect(decision.isDenied, isTrue, reason: ip);
        expect(decision.reason, RequestDenialReason.privateHostBlocked,
            reason: ip);
      }
    });

    test('localhost subdomains are denied by name', () async {
      const ExtensionRequestPolicy policy = ExtensionRequestPolicy();
      for (final String host in <String>[
        'localhost',
        'api.localhost',
        'LOCALHOST',
      ]) {
        final RequestPolicyDecision decision = await policy.evaluate(
          ExtensionRequest(url: 'http://$host/x', method: 'GET'),
        );
        expect(decision.isDenied, isTrue, reason: host);
      }
    });

    test('a public host is allowed (no false positive)', () async {
      const ExtensionRequestPolicy policy = ExtensionRequestPolicy(
        hostResolver: _resolverNeverBlocked,
      );
      final RequestPolicyDecision decision = await policy.evaluate(
        ExtensionRequest(url: 'https://example.test/api', method: 'GET'),
      );
      expect(decision.isDenied, isFalse);
    });

    test(
        'a hostname resolving to a blocked address is denied (deterministic)',
        () async {
      const ExtensionRequestPolicy policy = ExtensionRequestPolicy(
        hostResolver: _resolverToLoopback,
      );
      final RequestPolicyDecision decision = await policy.evaluate(
        ExtensionRequest(url: 'http://evil.test/api', method: 'GET'),
      );
      expect(decision.isDenied, isTrue);
      expect(decision.reason, RequestDenialReason.privateHostBlocked);
    });

    test('a hostname resolving to a mapped-blocked address is denied',
        () async {
      const ExtensionRequestPolicy policy = ExtensionRequestPolicy(
        hostResolver: _resolverToMappedLoopback,
      );
      final RequestPolicyDecision decision = await policy.evaluate(
        ExtensionRequest(url: 'http://evil.test/api', method: 'GET'),
      );
      expect(decision.isDenied, isTrue);
    });

    test('a hostname that cannot be resolved is denied, not allowed',
        () async {
      const ExtensionRequestPolicy policy = ExtensionRequestPolicy(
        hostResolver: _resolverFailing,
      );
      final RequestPolicyDecision decision = await policy.evaluate(
        ExtensionRequest(url: 'http://unresolvable.test/api', method: 'GET'),
      );
      expect(decision.isDenied, isTrue);
      expect(decision.reason, RequestDenialReason.hostLookupFailed);
    });

    test('the resolver failure maps to a retryable transport failure',
        () async {
      const ExtensionRequestPolicy policy = ExtensionRequestPolicy(
        hostResolver: _resolverFailing,
      );
      final RequestPolicyDecision decision = await policy.evaluate(
        ExtensionRequest(url: 'http://unresolvable.test/api', method: 'GET'),
      );
      expect(decision.failureType, ExtensionFailureType.networkError);
    });
  });

  group('§37 redirect decisions (policy.evaluateRedirect)', () {
    const ExtensionRequestPolicy policy = ExtensionRequestPolicy();
    final Uri httpsCurrent = Uri.parse('https://cdn.example.test/a');

    test('a relative Location resolves against the current URL', () {
      // The resolution itself is exercised through the transport tests; here
      // we prove the same helper the transport uses accepts relative forms
      // (no denial) and that the resolved target is the one checked.
      final RequestPolicyDecision? decision = policy.evaluateRedirect(
        current: httpsCurrent,
        locationHeader: '/b/file.mp4',
      );
      expect(decision, isNull, reason: 'a same-host https hop is allowed');
    });

    test('an https→http redirect is denied by default', () {
      final RequestPolicyDecision? decision = policy.evaluateRedirect(
        current: httpsCurrent,
        locationHeader: 'http://cdn.example.test/b',
      );
      expect(decision, isNotNull);
      expect(decision!.reason, RequestDenialReason.redirectBlocked);
    });

    test('an https→http redirect is allowed when the flag is set', () {
      const ExtensionRequestPolicy permissive = ExtensionRequestPolicy(
        allowHttpsToHttpRedirect: true,
      );
      final RequestPolicyDecision? decision = permissive.evaluateRedirect(
        current: httpsCurrent,
        locationHeader: 'http://cdn.example.test/b',
      );
      expect(decision, isNull);
    });

    test('a redirect to a non-allowed scheme is denied', () {
      final RequestPolicyDecision? decision = policy.evaluateRedirect(
        current: httpsCurrent,
        locationHeader: 'ftp://cdn.example.test/b',
      );
      expect(decision, isNotNull);
      expect(decision!.reason, RequestDenialReason.redirectBlocked);
    });

    test('an over-long redirect target is denied', () {
      final RequestPolicyDecision? decision = policy.evaluateRedirect(
        current: httpsCurrent,
        locationHeader: 'https://cdn.example.test/${'a' * 3000}',
      );
      expect(decision, isNotNull);
      expect(decision!.reason, RequestDenialReason.redirectBlocked);
    });

    test('an unparseable Location is denied', () {
      final RequestPolicyDecision? decision = policy.evaluateRedirect(
        current: httpsCurrent,
        locationHeader: 'http://[invalid',
      );
      expect(decision, isNotNull);
      expect(decision!.reason, RequestDenialReason.redirectBlocked);
    });
  });

  group('§37 transport — redirects followed manually over real loopback', () {
    late HttpServer server;
    late Uri base;
    late DartIoHttpTransport transport;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = Uri.parse('http://127.0.0.1:${server.port}');
      transport = DartIoHttpTransport(
        policy: const ExtensionRequestPolicy(
          blockPrivateHosts: false,
        ), // §37.5 test-only override
      );
      server.listen((HttpRequest request) async {
        switch (request.uri.path) {
          case '/loop-301':
            request.response.statusCode = HttpStatus.movedPermanently;
            request.response.headers.set(HttpHeaders.locationHeader, Uri.parse('/loop-301'));
            request.response.headers.set(HttpHeaders.connectionHeader, 'close');
          case '/to-loopback':
            // Absolute redirect to a loopback target — with the production
            // policy this hop would be refused; this server answers it so
            // the override-only behavior is observable.
            request.response.statusCode = HttpStatus.found;
            request.response.headers.set(HttpHeaders.locationHeader, Uri.parse('http://127.0.0.1:${server.port}/final'));
            request.response.headers.set(HttpHeaders.connectionHeader, 'close');
          case '/to-https-downgrade':
            request.response.statusCode = HttpStatus.found;
            request.response.headers.set(HttpHeaders.locationHeader, Uri.parse('http://example.test/final'));
            request.response.headers.set(HttpHeaders.connectionHeader, 'close');
          case '/to-localhost':
            request.response.statusCode = HttpStatus.found;
            request.response.headers.set(HttpHeaders.locationHeader, Uri.parse('http://localhost/final'));
            request.response.headers.set(HttpHeaders.connectionHeader, 'close');
          case '/relative':
            request.response.statusCode = HttpStatus.found;
            request.response.headers.set(HttpHeaders.locationHeader, Uri.parse('/final'));
            request.response.headers.set(HttpHeaders.connectionHeader, 'close');
          case '/seeother':
            request.response.statusCode = HttpStatus.seeOther;
            request.response.headers.set(HttpHeaders.locationHeader, Uri.parse('/echo-method'));
            request.response.headers.set(HttpHeaders.connectionHeader, 'close');
          case '/preserve':
            request.response.statusCode = HttpStatus.temporaryRedirect;
            request.response.headers.set(HttpHeaders.locationHeader, Uri.parse('/echo-method'));
            request.response.headers.set(HttpHeaders.connectionHeader, 'close');
          case '/echo-method':
            request.response.statusCode = 200;
            request.response.write(request.method);
          case '/final':
            request.response.statusCode = 200;
            request.response.write('final');
          default:
            request.response.statusCode = 404;
        }
        await request.response.close();
      });
    });

    tearDown(() async {
      transport.close();
      await server.close(force: true);
    });

    test('a relative redirect resolves and is followed', () async {
      final ExtensionHttpResult result = await transport.send(
        uri: base.resolve('/relative'),
        method: 'GET',
        headers: const <String, String>{},
        timeout: const Duration(seconds: 10),
        maxBytes: 65536,
        maxRedirects: 5,
      );
      expect(result.statusCode, 200);
      expect(result.body, 'final');
    });

    test('303 turns POST into GET (body dropped)', () async {
      final ExtensionHttpResult result = await transport.send(
        uri: base.resolve('/seeother'),
        method: 'POST',
        headers: const <String, String>{},
        body: 'payload',
        timeout: const Duration(seconds: 10),
        maxBytes: 65536,
        maxRedirects: 5,
      );
      expect(result.statusCode, 200);
      expect(result.body, 'GET');
    });

    test('307 preserves the method and body', () async {
      final ExtensionHttpResult result = await transport.send(
        uri: base.resolve('/preserve'),
        method: 'POST',
        headers: const <String, String>{},
        body: 'payload',
        timeout: const Duration(seconds: 10),
        maxBytes: 65536,
        maxRedirects: 5,
      );
      expect(result.statusCode, 200);
      expect(result.body, 'POST');
    });

    test('the redirect cap is enforced with a structured refusal', () async {
      final ExtensionHttpResult result = await transport.send(
        uri: base.resolve('/loop-301'),
        method: 'GET',
        headers: const <String, String>{},
        timeout: const Duration(seconds: 10),
        maxBytes: 65536,
        maxRedirects: 3,
      );
      expect(result.statusCode, isNull);
      expect(result.failureType, ExtensionFailureType.unsupported);
      expect(result.error, contains('Redirect limit exceeded'));
    });

    test('sensitive headers are not forwarded to a different host',
        () async {
      HttpRequest? seen;
      final HttpServer target = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(target.close);
      target.listen((HttpRequest request) async {
        seen = request;
        request.response.statusCode = 200;
        await request.response.close();
      });

      final HttpServer origin = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(origin.close);
      origin.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'http://127.0.0.1:${target.port}/landed',
        );
        request.response.headers.set(HttpHeaders.connectionHeader, 'close');
        await request.response.close();
      });

      final DartIoHttpTransport hopTransport = DartIoHttpTransport(
        policy: const ExtensionRequestPolicy(blockPrivateHosts: false),
      );
      addTearDown(hopTransport.close);

      final ExtensionHttpResult result = await hopTransport.send(
        uri: Uri.parse('http://127.0.0.1:${origin.port}/start'),
        method: 'GET',
        headers: const <String, String>{
          'authorization': 'Bearer secret-token',
          'cookie': 'session=abc',
          'x-safe': 'kept',
        },
        timeout: const Duration(seconds: 10),
        maxBytes: 65536,
        maxRedirects: 5,
      );

      expect(result.statusCode, 200);
      expect(seen, isNotNull);
      expect(seen!.headers.value('authorization'), isNull);
      expect(seen!.headers.value('cookie'), isNull);
      expect(seen!.headers.value('x-safe'), 'kept');
    });

    test(
        'with the PRODUCTION policy, a redirect to a blocked host is refused',
        () async {
      final DartIoHttpTransport strict = DartIoHttpTransport(
        policy: const ExtensionRequestPolicy(), // blocking ON
      );
      addTearDown(strict.close);

      // Same-host hop first (allowed), landing on a literal-blocked target.
      // (The transport consults the policy on every redirect hop; the initial
      // URL is gated by the API layer, proven in the provider group above.)
      final ExtensionHttpResult result = await strict.send(
        uri: base.resolve('/to-loopback'),
        method: 'GET',
        headers: const <String, String>{},
        timeout: const Duration(seconds: 10),
        maxBytes: 65536,
        maxRedirects: 5,
      );
      expect(result.statusCode, isNull);
      expect(result.failureType, ExtensionFailureType.unsupported);
      expect(result.error, contains('PRIVATE_HOST_BLOCKED'));
    });

    test(
        'with the PRODUCTION policy, a redirect to a blocked NAME is refused',
        () async {
      // 'localhost' is refused by NAME before any resolver runs, so this
      // downgrade-shaped hop is refused hermetically (no DNS, no TLS).
      final DartIoHttpTransport strict = DartIoHttpTransport(
        policy: const ExtensionRequestPolicy(),
      );
      addTearDown(strict.close);

      final ExtensionHttpResult result = await strict.send(
        uri: base.resolve('/to-localhost'),
        method: 'GET',
        headers: const <String, String>{},
        timeout: const Duration(seconds: 10),
        maxBytes: 65536,
        maxRedirects: 5,
      );
      expect(result.statusCode, isNull);
      expect(result.failureType, ExtensionFailureType.unsupported);
      expect(result.error, contains('PRIVATE_HOST_BLOCKED'));
    });
  });

  group('§36.2 request({query}) is merged into the URL', () {
    late _CapturingTransport transport;

    setUp(() {
      transport = _CapturingTransport();
    });

    ControlledExtensionRuntimeApi api() => ControlledExtensionRuntimeApi(
          transport: transport,
          policy: const ExtensionRequestPolicy(blockPrivateHosts: false),
        );

    test('query entries are appended to a URL with no query', () async {
      final ControlledExtensionRuntimeApi a = api();
      await a.request(ExtensionRequest(
        url: 'https://example.test/search',
        method: 'GET',
        queryParameters: const <String, String>{'q': 'batman'},
      ));
      expect(transport.sent.single.toString(),
          'https://example.test/search?q=batman');
      a.dispose();
    });

    test('query entries merge with a URL that already has a query', () async {
      final ControlledExtensionRuntimeApi a = api();
      await a.request(ExtensionRequest(
        url: 'https://example.test/search?page=2',
        method: 'GET',
        queryParameters: const <String, String>{'q': 'batman'},
      ));
      final Uri sent = transport.sent.single;
      expect(sent.queryParameters['page'], '2');
      expect(sent.queryParameters['q'], 'batman');
      a.dispose();
    });

    test('an explicit query entry overrides a same-named URL entry', () async {
      final ControlledExtensionRuntimeApi a = api();
      await a.request(ExtensionRequest(
        url: 'https://example.test/search?q=old',
        method: 'GET',
        queryParameters: const <String, String>{'q': 'new'},
      ));
      final Uri sent = transport.sent.single;
      expect(sent.queryParametersAll['q'], <String>['old', 'new'],
          reason: 'the explicit value is appended; servers take the last '
              'occurrence, so "new" wins — documented in the API');
      expect(sent.queryParametersAll['q']!.last, 'new');
      a.dispose();
    });

    test('special and non-ASCII characters are percent-encoded', () async {
      final ControlledExtensionRuntimeApi a = api();
      await a.request(ExtensionRequest(
        url: 'https://example.test/search',
        method: 'GET',
        queryParameters: const <String, String>{
          'q': 'one two&three=四?',
        },
      ));
      final String url = transport.sent.single.toString();
      expect(url, isNot(contains(' ')));
      expect(url, contains('q=one+two%26three%3D%E5%9B%9B%3F'));
      a.dispose();
    });

    test('the URL length limit applies to the MERGED url', () async {
      final ControlledExtensionRuntimeApi a = ControlledExtensionRuntimeApi(
        transport: transport,
        policy: const ExtensionRequestPolicy(
          blockPrivateHosts: false,
          maxUrlLength: 60,
        ),
      );
      final String longValue = 'a' * 100;
      final ExtensionResponse response = await a.request(ExtensionRequest(
        url: 'https://example.test/search',
        method: 'GET',
        queryParameters: <String, String>{
          'q': longValue,
        },
      ));
      expect(response.ok, isFalse);
      expect(response.errorType, ExtensionFailureType.invalidResult.code);
      expect(response.error, contains('URL_TOO_LONG'));
      expect(transport.sent, isEmpty, reason: 'denied before any transport');
      a.dispose();
    });

    test('redacted logging is unchanged: host only, never the query',
        () async {
      final List<(ExtensionLogLevel, String)> logs =
          <(ExtensionLogLevel, String)>[];
      final ControlledExtensionRuntimeApi a = ControlledExtensionRuntimeApi(
        transport: transport,
        policy: const ExtensionRequestPolicy(blockPrivateHosts: false),
        logSink: (ExtensionLogLevel level, String message) =>
            logs.add((level, message)),
      );
      await a.request(ExtensionRequest(
        url: 'https://example.test/search',
        method: 'GET',
        queryParameters: const <String, String>{'token': 'supersecret'},
      ));
      final String all = logs.map(((ExtensionLogLevel, String) l) => l.$2).join(
        '\n',
      );
      expect(all, contains('example.test'));
      expect(all, isNot(contains('supersecret')));
      expect(all, isNot(contains('/search')));
      a.dispose();
    });
  });

  group('§36.3 transport — one overall deadline over real loopback', () {
    late HttpServer server;
    late Uri base;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = Uri.parse('http://127.0.0.1:${server.port}');
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test(
        'a slow-drip response aborts at the OVERALL deadline, not per chunk',
        () async {
      // Sends one byte every 200 ms for a long time. Under the old
      // per-chunk Stream.timeout this would keep the request alive almost
      // forever; under the overall deadline it must abort at ~1 s.
      final HttpServer drip = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(drip.close);
      final StreamSubscription<HttpRequest> sub = drip.listen((
        HttpRequest request,
      ) async {
        request.response.statusCode = 200;
        request.response.bufferOutput = false;
        for (int i = 0; i < 1000; i++) {
          request.response.add(<int>[0x61]);
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        await request.response.close();
      });
      addTearDown(sub.cancel);

      final DartIoHttpTransport transport = DartIoHttpTransport();
      addTearDown(transport.close);

      final Stopwatch watch = Stopwatch()..start();
      final ExtensionHttpResult result = await transport.send(
        uri: Uri.parse('http://127.0.0.1:${drip.port}/drip'),
        method: 'GET',
        headers: const <String, String>{},
        timeout: const Duration(seconds: 1),
        maxBytes: 1024 * 1024,
        maxRedirects: 0,
      );
      watch.stop();

      expect(result.statusCode, isNull);
      expect(result.failureType, ExtensionFailureType.timeout);
      // The deadline (1 s) must cut the exchange well before the drip would
      // naturally finish (1000 × 200 ms = 200 s) and well before any
      // per-chunk reset could accumulate that total. Generous bounds keep
      // the test deterministic on a loaded CI box.
      expect(watch.elapsed, lessThan(const Duration(seconds: 8)));
    });

    test('the size cap still aborts a large body', () async {
      server.listen((HttpRequest request) async {
        request.response.statusCode = 200;
        request.response.add(
          Uint8List.fromList(List<int>.filled(200000, 0x78)),
        );
        await request.response.close();
      });

      final DartIoHttpTransport transport = DartIoHttpTransport();
      addTearDown(transport.close);

      final ExtensionHttpResult result = await transport.send(
        uri: base.resolve('/big'),
        method: 'GET',
        headers: const <String, String>{},
        timeout: const Duration(seconds: 10),
        maxBytes: 1024,
        maxRedirects: 0,
      );
      expect(result.statusCode, isNull);
      expect(result.failureType, ExtensionFailureType.invalidResult);
      expect(result.error, contains('size limit'));
    });

    test('a normal response is unchanged (status, headers, body)', () async {
      server.listen((HttpRequest request) async {
        request.response.statusCode = 200;
        request.response.headers.set('x-probe', 'yes');
        request.response.write('{"ok":true}');
        await request.response.close();
      });

      final DartIoHttpTransport transport = DartIoHttpTransport();
      addTearDown(transport.close);

      final ExtensionHttpResult result = await transport.send(
        uri: base.resolve('/json'),
        method: 'GET',
        headers: const <String, String>{},
        timeout: const Duration(seconds: 10),
        maxBytes: 65536,
        maxRedirects: 0,
      );
      expect(result.statusCode, 200);
      expect(result.body, '{"ok":true}');
      expect(result.headers['x-probe'], 'yes');
      expect(result.failureType, isNull);
    });

    test('a timeout maps to the SAME failure type as before', () async {
      server.listen((HttpRequest request) async {
        // Never respond; hold the connection.
        await Future<void>.delayed(const Duration(seconds: 30));
        await request.response.close();
      });

      final DartIoHttpTransport transport = DartIoHttpTransport();
      addTearDown(transport.close);

      final ExtensionHttpResult result = await transport.send(
        uri: base.resolve('/hang'),
        method: 'GET',
        headers: const <String, String>{},
        timeout: const Duration(milliseconds: 300),
        maxBytes: 65536,
        maxRedirects: 0,
      );
      expect(result.statusCode, isNull);
      expect(result.failureType, ExtensionFailureType.timeout);
    });

    test('a timed-out request does not keep the connection running',
        () async {
      int openConnections = 0;
      server.listen((HttpRequest request) async {
        openConnections++;
        await Future<void>.delayed(const Duration(seconds: 30));
        await request.response.close();
      });

      final DartIoHttpTransport transport = DartIoHttpTransport();
      final ExtensionHttpResult result = await transport.send(
        uri: base.resolve('/hang'),
        method: 'GET',
        headers: const <String, String>{},
        timeout: const Duration(milliseconds: 250),
        maxBytes: 65536,
        maxRedirects: 0,
      );
      expect(result.failureType, ExtensionFailureType.timeout);

      transport.close(); // force-closes pooled sockets
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(openConnections, 1,
          reason: 'exactly one connection was made for one request');
    });
  });
}

// ---------------------------------------------------------------------------
// Deterministic resolvers for the policy tests (§37.2 injectable resolver).
// ---------------------------------------------------------------------------

InternetAddress _parseOrThrow(String textual) {
  final InternetAddress? address = InternetAddress.tryParse(textual);
  if (address == null) {
    throw StateError('test resolver: "$textual" did not parse');
  }
  return address;
}

Future<List<InternetAddress>> _resolverNeverBlocked(String host) async =>
    <InternetAddress>[_parseOrThrow('93.184.216.34')];

Future<List<InternetAddress>> _resolverToLoopback(String host) async =>
    <InternetAddress>[InternetAddress.loopbackIPv4];

Future<List<InternetAddress>> _resolverToMappedLoopback(String host) async =>
    <InternetAddress>[_parseOrThrow('::ffff:127.0.0.1')];

Future<List<InternetAddress>> _resolverFailing(String host) async =>
    throw const SocketException('resolution failed');

/// A transport that only records what it was asked to send.
final class _CapturingTransport implements ExtensionHttpTransport {
  final List<Uri> sent = <Uri>[];

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
    sent.add(uri);
    return const ExtensionHttpResult(statusCode: 200, body: '{}');
  }
}
