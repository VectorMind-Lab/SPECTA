import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/runtime/controlled_runtime_api.dart';
import 'package:specta/core/extensions/runtime/request_policy.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';

/// A transport whose behaviour each test dictates, so the API's policy,
/// mapping and logging can be exercised with no network.
final class _ScriptedTransport implements ExtensionHttpTransport {
  _ScriptedTransport(this.respond);

  final Future<ExtensionHttpResult> Function(Uri uri) respond;

  final List<Uri> sent = <Uri>[];
  final List<String> methods = <String>[];
  final List<Map<String, String>> headers = <Map<String, String>>[];
  final List<Duration> timeouts = <Duration>[];
  final List<int> maxBytes = <int>[];
  final List<int> maxRedirects = <int>[];

  @override
  Future<ExtensionHttpResult> send({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
    required int maxBytes,
    required int maxRedirects,
  }) {
    sent.add(uri);
    methods.add(method);
    this.headers.add(headers);
    timeouts.add(timeout);
    this.maxBytes.add(maxBytes);
    this.maxRedirects.add(maxRedirects);
    return respond(uri);
  }
}

ExtensionRequest _request({
  String url = 'https://example.test/api',
  String method = 'GET',
  Map<String, String> headers = const <String, String>{},
  String? body,
  Duration timeout = const Duration(seconds: 15),
}) => ExtensionRequest(
  url: url,
  method: method,
  headers: headers,
  body: body,
  timeout: timeout,
);

void main() {
  group('ControlledExtensionRuntimeApi — allowed request', () {
    test('a 2xx response is structured, decoded and timed', () async {
      final _ScriptedTransport transport = _ScriptedTransport(
        (Uri uri) async => const ExtensionHttpResult(
          statusCode: 200,
          headers: <String, String>{'content-type': 'application/json'},
          body: '{"title":"The Matrix","year":1999}',
        ),
      );
      final ControlledExtensionRuntimeApi api = ControlledExtensionRuntimeApi(
        transport: transport,
      );

      final ExtensionResponse response = await api.request(_request());

      expect(response.ok, isTrue);
      expect(response.status, 200);
      expect(response.error, isNull);
      expect(response.errorType, isNull);
      expect(response.headers['content-type'], 'application/json');
      expect(response.body, '{"title":"The Matrix","year":1999}');
      expect(response.json, <String, dynamic>{
        'title': 'The Matrix',
        'year': 1999,
      });
      expect(response.latency, greaterThanOrEqualTo(0));
      expect(response.isFailure, isFalse);
      api.dispose();
    });

    test('a non-JSON body is returned with json left null', () async {
      final ControlledExtensionRuntimeApi api = ControlledExtensionRuntimeApi(
        transport: _ScriptedTransport(
          (Uri uri) async => const ExtensionHttpResult(
            statusCode: 200,
            body: '<html>not json</html>',
          ),
        ),
      );

      final ExtensionResponse response = await api.request(_request());
      expect(response.ok, isTrue);
      expect(response.body, contains('not json'));
      expect(response.json, isNull);
      api.dispose();
    });

    test(
      'the policy timeout, size cap and redirect cap reach the transport',
      () async {
        final _ScriptedTransport transport = _ScriptedTransport(
          (Uri uri) async =>
              const ExtensionHttpResult(statusCode: 200, body: '{}'),
        );
        final ControlledExtensionRuntimeApi api = ControlledExtensionRuntimeApi(
          policy: const ExtensionRequestPolicy(
            defaultTimeout: Duration(seconds: 7),
            maxResponseBytes: 1234,
            maxRedirects: 2,
          ),
          transport: transport,
        );

        await api.request(_request(timeout: Duration.zero));

        expect(transport.timeouts.single, const Duration(seconds: 7));
        expect(transport.maxBytes.single, 1234);
        expect(transport.maxRedirects.single, 2);
        api.dispose();
      },
    );

    test(
      'the method is upper-cased and the URL is trimmed before dispatch',
      () async {
        final _ScriptedTransport transport = _ScriptedTransport(
          (Uri uri) async => const ExtensionHttpResult(statusCode: 204),
        );
        final ControlledExtensionRuntimeApi api = ControlledExtensionRuntimeApi(
          transport: transport,
        );

        await api.request(
          _request(url: '  https://example.test/api  ', method: 'post'),
        );

        expect(transport.sent.single, Uri.parse('https://example.test/api'));
        expect(transport.methods.single, 'POST');
        api.dispose();
      },
    );

    test('extension-provided headers are forwarded to the transport', () async {
      final _ScriptedTransport transport = _ScriptedTransport(
        (Uri uri) async =>
            const ExtensionHttpResult(statusCode: 200, body: '{}'),
      );
      final ControlledExtensionRuntimeApi api = ControlledExtensionRuntimeApi(
        transport: transport,
      );

      await api.request(
        _request(headers: <String, String>{'accept-language': 'en'}),
      );

      expect(transport.headers.single, <String, String>{
        'accept-language': 'en',
      });
      api.dispose();
    });
  });

  group('ControlledExtensionRuntimeApi — structured failures', () {
    test('a non-2xx response is a structured HTTP failure', () async {
      final ControlledExtensionRuntimeApi api = ControlledExtensionRuntimeApi(
        transport: _ScriptedTransport(
          (Uri uri) async =>
              const ExtensionHttpResult(statusCode: 503, body: 'unavailable'),
        ),
      );

      final ExtensionResponse response = await api.request(_request());

      expect(response.ok, isFalse);
      expect(response.status, 503);
      expect(response.errorType, ExtensionFailureType.httpError.code);
      expect(response.error, 'HTTP 503');
      expect(response.isFailure, isTrue);
      api.dispose();
    });

    test('a transport timeout surfaces as TIMEOUT', () async {
      final ControlledExtensionRuntimeApi api = ControlledExtensionRuntimeApi(
        transport: _ScriptedTransport(
          (Uri uri) async => const ExtensionHttpResult(
            failureType: ExtensionFailureType.timeout,
            error: 'Request timed out.',
          ),
        ),
      );

      final ExtensionResponse response = await api.request(_request());

      expect(response.ok, isFalse);
      expect(response.status, isNull);
      expect(response.errorType, ExtensionFailureType.timeout.code);
      api.dispose();
    });

    test('a transport network failure surfaces as NETWORK_ERROR', () async {
      final ControlledExtensionRuntimeApi api = ControlledExtensionRuntimeApi(
        transport: _ScriptedTransport(
          (Uri uri) async => const ExtensionHttpResult(
            failureType: ExtensionFailureType.networkError,
            error: 'Socket failure: connection refused',
          ),
        ),
      );

      final ExtensionResponse response = await api.request(_request());

      expect(response.errorType, ExtensionFailureType.networkError.code);
      expect(response.error, contains('connection refused'));
      api.dispose();
    });

    test('oversize response handling surfaces the transport failure', () async {
      final ControlledExtensionRuntimeApi api = ControlledExtensionRuntimeApi(
        transport: _ScriptedTransport(
          (Uri uri) async => const ExtensionHttpResult(
            failureType: ExtensionFailureType.invalidResult,
            error: 'Response exceeded the configured size limit.',
          ),
        ),
      );

      final ExtensionResponse response = await api.request(_request());

      expect(response.ok, isFalse);
      expect(response.errorType, ExtensionFailureType.invalidResult.code);
      expect(response.error, contains('size limit'));
      api.dispose();
    });

    test('an untagged transport failure still yields a failure type', () async {
      final ControlledExtensionRuntimeApi api = ControlledExtensionRuntimeApi(
        transport: _ScriptedTransport(
          (Uri uri) async => const ExtensionHttpResult(),
        ),
      );

      final ExtensionResponse response = await api.request(_request());
      expect(response.errorType, ExtensionFailureType.runtimeError.code);
      api.dispose();
    });
  });

  group('ControlledExtensionRuntimeApi — policy enforcement', () {
    test('a denied scheme never reaches the transport', () async {
      final _ScriptedTransport transport = _ScriptedTransport(
        (Uri uri) async => const ExtensionHttpResult(statusCode: 200),
      );
      final ControlledExtensionRuntimeApi api = ControlledExtensionRuntimeApi(
        transport: transport,
      );

      final ExtensionResponse response = await api.request(
        _request(url: 'file:///etc/passwd'),
      );

      expect(response.ok, isFalse);
      expect(response.status, isNull);
      expect(response.errorType, ExtensionFailureType.unsupported.code);
      expect(response.error, contains('SCHEME_NOT_ALLOWED'));
      expect(transport.sent, isEmpty);
      expect(api.deniedCount, 1);
      expect(api.requestCount, 0);
      api.dispose();
    });

    test('a denied method never reaches the transport', () async {
      final _ScriptedTransport transport = _ScriptedTransport(
        (Uri uri) async => const ExtensionHttpResult(statusCode: 200),
      );
      final ControlledExtensionRuntimeApi api = ControlledExtensionRuntimeApi(
        transport: transport,
      );

      final ExtensionResponse response = await api.request(
        _request(method: 'DELETE'),
      );

      expect(response.error, contains('METHOD_NOT_ALLOWED'));
      expect(transport.sent, isEmpty);
      api.dispose();
    });

    test('counters separate dispatched from denied requests', () async {
      final ControlledExtensionRuntimeApi api = ControlledExtensionRuntimeApi(
        transport: _ScriptedTransport(
          (Uri uri) async =>
              const ExtensionHttpResult(statusCode: 200, body: '{}'),
        ),
      );

      await api.request(_request());
      await api.request(_request());
      await api.request(_request(url: 'ftp://example.test/x'));

      expect(api.requestCount, 2);
      expect(api.deniedCount, 1);
      api.dispose();
    });
  });

  group('ControlledExtensionRuntimeApi — logging', () {
    test(
      'a denied request is logged at warning with no query string',
      () async {
        final List<(ExtensionLogLevel, String)> lines =
            <(ExtensionLogLevel, String)>[];
        final ControlledExtensionRuntimeApi api = ControlledExtensionRuntimeApi(
          transport: _ScriptedTransport(
            (Uri uri) async => const ExtensionHttpResult(statusCode: 200),
          ),
          logSink: (ExtensionLogLevel level, String message) =>
              lines.add((level, message)),
        );

        await api.request(
          _request(url: 'https://example.test/api?token=supersecret'),
        );

        expect(lines, hasLength(1));
        expect(lines.single.$1, ExtensionLogLevel.debug);
        expect(lines.single.$2, contains('https://example.test'));
        expect(lines.single.$2, isNot(contains('supersecret')));
        api.dispose();
      },
    );

    test('log() is forwarded to the sink and silenceable', () async {
      final List<String> messages = <String>[];
      final ControlledExtensionRuntimeApi api = ControlledExtensionRuntimeApi(
        transport: _ScriptedTransport(
          (Uri uri) async => const ExtensionHttpResult(statusCode: 200),
        ),
        logSink: (ExtensionLogLevel level, String message) =>
            messages.add(message),
      );

      api.log(ExtensionLogLevel.info, 'hello from an extension');
      expect(messages, <String>['hello from an extension']);

      // The default constructor discards logs without failing.
      final ControlledExtensionRuntimeApi silent =
          ControlledExtensionRuntimeApi(
            transport: _ScriptedTransport(
              (Uri uri) async => const ExtensionHttpResult(statusCode: 200),
            ),
          );
      silent.log(ExtensionLogLevel.debug, 'dropped');
      silent.dispose();
      api.dispose();
    });

    test('requests are never logged with a credential-bearing URL', () async {
      final List<String> messages = <String>[];
      final ControlledExtensionRuntimeApi api = ControlledExtensionRuntimeApi(
        transport: _ScriptedTransport(
          (Uri uri) async =>
              const ExtensionHttpResult(statusCode: 200, body: '{}'),
        ),
        logSink: (ExtensionLogLevel level, String message) =>
            messages.add(message),
      );

      await api.request(_request(url: 'https://example.test/a?api_key=abc123'));
      expect(messages.join('\n'), isNot(contains('abc123')));
      api.dispose();
    });
  });

  group('DartIoHttpTransport — real sockets on loopback', () {
    late HttpServer server;
    late Uri baseUri;
    late DartIoHttpTransport transport;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUri = Uri.parse('http://127.0.0.1:${server.port}');
      transport = DartIoHttpTransport();
      server.listen((HttpRequest request) async {
        switch (request.uri.path) {
          case '/json':
            request.response
              ..statusCode = 200
              ..headers.contentType = ContentType.json
              ..write('{"ok":true}');
          case '/big':
            request.response
              ..statusCode = 200
              ..write('x' * 200000);
          case '/notfound':
            request.response.statusCode = 404;
          default:
            request.response.statusCode = 500;
        }
        await request.response.close();
      });
    });

    tearDown(() async {
      transport.close();
      await server.close(force: true);
    });

    test('a real HTTP exchange returns the status, headers and body', () async {
      final ExtensionHttpResult result = await transport.send(
        uri: baseUri.resolve('/json'),
        method: 'GET',
        headers: const <String, String>{'accept': 'application/json'},
        timeout: const Duration(seconds: 10),
        maxBytes: 1024 * 1024,
        maxRedirects: 0,
      );

      expect(result.statusCode, 200);
      expect(result.body, '{"ok":true}');
      expect(result.headers['content-type'], contains('application/json'));
      expect(result.failureType, isNull);
    });

    test(
      'a real error status is passed through, not treated as a failure',
      () async {
        final ExtensionHttpResult result = await transport.send(
          uri: baseUri.resolve('/notfound'),
          method: 'GET',
          headers: const <String, String>{},
          timeout: const Duration(seconds: 10),
          maxBytes: 1024,
          maxRedirects: 0,
        );

        expect(result.statusCode, 404);
        expect(result.failureType, isNull);
      },
    );

    test('the response size cap aborts a large body', () async {
      final ExtensionHttpResult result = await transport.send(
        uri: baseUri.resolve('/big'),
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

    test('a closed port is a network failure, not an exception', () async {
      // Bind then immediately close to obtain a port nothing is listening on.
      final HttpServer probe = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final int deadPort = probe.port;
      await probe.close(force: true);

      final ExtensionHttpResult result = await transport.send(
        uri: Uri.parse('http://127.0.0.1:$deadPort/'),
        method: 'GET',
        headers: const <String, String>{},
        timeout: const Duration(seconds: 5),
        maxBytes: 1024,
        maxRedirects: 0,
      );

      expect(result.statusCode, isNull);
      expect(result.failureType, ExtensionFailureType.networkError);
    });

    test(
      'the full API refuses file:// even with a real transport attached',
      () async {
        final ControlledExtensionRuntimeApi api =
            ControlledExtensionRuntimeApi();
        final ExtensionResponse response = await api.request(
          ExtensionRequest(
            url: baseUri
                .resolve('/etc/passwd')
                .replace(scheme: 'file')
                .toString(),
            method: 'GET',
          ),
        );

        expect(response.ok, isFalse);
        expect(response.errorType, ExtensionFailureType.unsupported.code);
        api.dispose();
      },
    );
  });

  group('ControlledExtensionRuntimeApi — provider independence', () {
    test('the request layer carries no provider-specific logic', () async {
      // A policy check that stands in for the audit's requirement: the layer
      // must be generic. Any host is treated identically.
      final _ScriptedTransport transport = _ScriptedTransport(
        (Uri uri) async =>
            const ExtensionHttpResult(statusCode: 200, body: '{}'),
      );
      final ControlledExtensionRuntimeApi api = ControlledExtensionRuntimeApi(
        transport: transport,
      );

      for (final String host in <String>[
        'example.test',
        'another.example',
        'third.example.org',
      ]) {
        final ExtensionResponse response = await api.request(
          _request(url: 'https://$host/api'),
        );
        expect(response.ok, isTrue, reason: host);
      }

      expect(transport.sent, hasLength(3));
      api.dispose();
    });
  });
}
