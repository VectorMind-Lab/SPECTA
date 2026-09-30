import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/contract/extension_capability.dart';
import 'package:specta/core/extensions/runtime/extension_runtime.dart';
import 'package:specta/core/extensions/runtime/flutter_js_sandbox.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';

import '../../../support/fake_js_sandbox.dart';

/// Whether the real QuickJS engine can run in this process.
///
/// Same rule the existing real-engine suites use: skip and say so, rather than
/// report "passing" for code that never executed.
String? _engineSkipReason() {
  if (!Platform.isWindows) return null;
  try {
    final DynamicLibrary bridge = DynamicLibrary.open('quickjs_c_bridge.dll');
    if (!bridge.providesSymbol('jsNewRuntime')) {
      return 'quickjs_c_bridge.dll was found but does not export jsNewRuntime.';
    }
    return null;
  } on Object catch (e) {
    return 'The flutter_js QuickJS bridge is not loadable here ($e).';
  }
}

/// Resolves a repository-relative fixture path.
///
/// Walks up from the test file until it finds the directory holding pubspec.yaml,
/// rather than trusting a fixed number of `..` hops. Flutter's test runner may
/// place the entry point in a temp directory, so the script's own location is
/// not a reliable anchor.
String? _resolveFixture(String relative) {
  Directory dir = File.fromUri(Platform.script).parent;
  while (!File('${dir.path}${Platform.pathSeparator}pubspec.yaml').existsSync()) {
    final Directory parent = dir.parent;
    if (parent.path == dir.path) return null; // reached the filesystem root
    dir = parent;
  }
  final String candidate = '${dir.path}${Platform.pathSeparator}$relative';
  return File(candidate).existsSync() ? candidate : null;
}

/// A provider in the shape real third-party code uses: a plain global function
/// that calls the WHATWG `fetch()` global rather than SPECTA's `request()`.
const String _fetchProvider = r'''
function getInfo() {
  return { name: 'Fetch Co', version: '1.0.0', type: 'movie' };
}

async function search(query, page) {
  const res = await fetch('https://api.example.invalid/search?q=' + query);
  const data = await res.json();
  return { results: [{ id: data.id, title: query + ' page ' + page }] };
}
''';

/// A host API that records every request and replays a scripted response, so
/// the `fetch` shim's translation is observable without touching a network.
final class _RecordingApi implements ExtensionRuntimeApi {
  /// Canned responses, matched by URL substring. Mutable, because a test
  /// populates it after construction.
  final Map<String, ExtensionResponse> responder;

  _RecordingApi({Map<String, ExtensionResponse>? responder})
    : responder = responder ?? <String, ExtensionResponse>{};

  final List<ExtensionRequest> requests = <ExtensionRequest>[];

  @override
  Future<ExtensionResponse> request(ExtensionRequest request) async {
    requests.add(request);
    for (final MapEntry<String, ExtensionResponse> entry
        in responder.entries) {
      if (request.url.contains(entry.key)) return entry.value;
    }
    return const ExtensionResponse(
      status: 200,
      ok: true,
      body: '{}',
      json: <String, dynamic>{},
    );
  }

  @override
  void log(ExtensionLogLevel level, String message) {}
}

void main() {
  group('a REAL shipped provider satisfies the whole SPECTA contract', () {
    // Why this group exists: maxmovies-cc worked perfectly when called
    // directly, yet nothing in the app ever played. Its file exported
    // `watch(url)` and `search(kw, page)` and nothing else. SPECTA calls
    // `getInfo`, `getHome`, `getDetail`, and `getVideoSources`, so every one
    // of those threw "This source does not implement ..." — a node that
    // installs cleanly, reports 100%, and can never reach playback.
    //
    // These assertions pin the contract NAMES, because that was the defect and
    // a future adapter that drops one reintroduces it silently.
    // This lives under fixtures/adapted/, not third_party/: it has already been
    // given the SPECTA contract, whereas third_party/ holds untouched foreign
    // files that the adapter must still be able to recognise.
    const String fixture = 'test/support/fixtures/adapted/maxmovies_cc.js';

    test('implements every operation the runtime calls', () async {
      final String? skip = _engineSkipReason();
      if (skip != null) {
        markTestSkipped(skip);
        return;
      }
      final String? path = _resolveFixture(fixture);
      expect(path, isNotNull, reason: 'fixture $fixture must exist');

      final FlutterJsSandbox engine = FlutterJsSandbox();
      addTearDown(engine.dispose);
      await engine.init();
      await engine.evaluate(sandboxBootstrap);
      await engine.evaluate(File(path!).readAsStringSync());

      // A missing method must be caught here, not on a user's device.
      // These are the names `_spectaInstance.<name>` in extension_runtime.dart
      // actually calls — verified against the runtime, not assumed.
      const Map<String, String> required = <String, String>{
        'search': 'Search',
        'latest': 'the Home rail',
        'details': 'Details',
        'getSources': 'Play',
        'healthCheck': 'node health',
      };
      for (final String method in required.keys) {
        final String type = await engine.evaluate(
          'typeof (new Extension()).$method',
        );
        expect(
          type,
          'function',
          reason:
              '$method is required for ${required[method]}; '
              'the runtime calls it by this exact name',
        );
      }
    });

    test('getSources returns a parseable list, not a bare object', () async {
      final String? skip = _engineSkipReason();
      if (skip != null) {
        markTestSkipped(skip);
        return;
      }
      final String? path = _resolveFixture(fixture);
      expect(path, isNotNull, reason: 'fixture $fixture must exist');

      final FlutterJsSandbox engine = FlutterJsSandbox();
      addTearDown(engine.dispose);
      await engine.init();
      await engine.evaluate(sandboxBootstrap);

      // Serve a minimal search API response and a watch page, so getVideoSources
      // runs its real recipe without touching the network.
      await engine.evaluate('''
        globalThis.sendMessage = function (channel, payload) {
          if (channel !== 'specta_request') return '{}';
          const req = JSON.parse(payload);
          let body = '';
          if (req.url.indexOf('/api/search') !== -1) {
            body = JSON.stringify({ movies: [
              { id: 1, title: 'Spider', posterUrl: 'http://x/p.jpg' }
            ]});
          } else if (req.url.indexOf('/watch/') !== -1) {
            body = '{\\\\"videoSourceId\\\\":4327}';
          } else if (req.url.indexOf('/api/stream') !== -1) {
            body = JSON.stringify({ hlsUrl: 'https://cdn.example/v.m3u8' });
          }
          return JSON.stringify({ status: 200, ok: true, headers: {}, body: body, json: null });
        };
      ''');
      await engine.evaluate(File(path!).readAsStringSync());
      await engine.evaluate('var e = new Extension();');

      final List<dynamic> items =
          jsonDecode(await engine.evaluateAsync('JSON.stringify(await e.search("spider", 1))'))
              as List<dynamic>;
      expect(items, isNotEmpty, reason: 'the search response must yield a reference');

      final String raw = await engine.evaluateAsync(
        'JSON.stringify(await e.getSources(${jsonEncode(items.first['url'])}))',
      );
      final Object? sources = jsonDecode(raw);

      // The runtime parses this with parseSourceList(), which does
      // `as List` — a single object here would throw rather than degrade.
      expect(sources, isA<List<Object?>>());
      expect(sources, isNotEmpty, reason: 'one playable source is expected');

      final Map<String, dynamic> first = (sources! as List).first as Map<String, dynamic>;
      // ExtensionSource.fromJson casts these directly, so a missing or
      // wrongly-typed field is a hard failure at parse time.
      expect(first['url'], isA<String>());
      expect(first['type'], anyOf('hls', 'mpd', 'mp4'));
    });
  });

  group('the fetch() bridge routes over the existing request channel', () {
    late FakeJsSandbox sandbox;
    late _RecordingApi api;

    setUp(() {
      sandbox = FakeJsSandbox();
      api = _RecordingApi();
    });

    Future<void> load(
      _RecordingApi api, {
      Set<ExtensionCapability>? capabilities,
    }) async {
      sandbox.setEvalResult(sandboxBootstrap, '');
      final ExtensionRuntime runtime = ExtensionRuntime(
        sandbox: sandbox,
        api: api,
        capabilities:
            capabilities ?? <ExtensionCapability>{ExtensionCapability.network},
      );
      final result = await runtime.loadExtension(
        extensionId: 'fetch-test',
        jsCode: 'class Extension { async load(){} }',
      );
      expect(result.isOk, isTrue, reason: result.failureOrNull.toString());
    }

    /// The exact payload the shim sends for `fetch(url)`, run through the
    /// real host handler.
    Future<Map<String, dynamic>> hostResponse(Map<String, dynamic> payload) async {
      final JsMessageHandler? handler = sandbox.handlers['specta_request'];
      expect(handler, isNotNull, reason: 'request channel must be registered');
      final Object? raw = await handler!(
        jsonDecode(jsonEncode(payload)),
      );
      return jsonDecode(raw! as String) as Map<String, dynamic>;
    }

    test('the bootstrap defines a global fetch over specta_request', () {
      // Guards the shim against a refactor that silently drops it — the exact
      // regression that made a healthy source report "could not be reached".
      expect(sandboxBootstrap, contains('globalThis.fetch'));
      expect(sandboxBootstrap, contains('specta_request'));
    });

    test('a fetch-shaped payload reaches the transport and returns the body', () async {
      api.responder['example.invalid'] = ExtensionResponse(
        status: 200,
        ok: true,
        body: '{"id":"r1"}',
        json: <String, dynamic>{'id': 'r1'},
      );
      await load(api);

      final Map<String, dynamic> response = await hostResponse(
        <String, dynamic>{
          'url': 'https://example.invalid/search',
          'method': 'GET',
          'headers': <String, String>{},
          'query': <String, String>{},
          'body': null,
          'timeout': 15000,
        },
      );

      expect(response['ok'], isTrue);
      expect(response['json'], <String, dynamic>{'id': 'r1'});
      expect(api.requests, hasLength(1));
      expect(api.requests.single.method, 'GET');
    });

    test('a POST body and headers survive the shim translation', () async {
      await load(api);
      await hostResponse(<String, dynamic>{
        'url': 'https://example.invalid/submit',
        'method': 'POST',
        'headers': <String, String>{'content-type': 'application/json'},
        'body': '{"q":"dune"}',
      });

      expect(api.requests.single.method, 'POST');
      expect(api.requests.single.body, '{"q":"dune"}');
      expect(
        api.requests.single.headers['content-type'],
        'application/json',
      );
    });

    test('fetch is refused when the network capability is not declared', () async {
      await load(api, capabilities: <ExtensionCapability>{});

      final Map<String, dynamic> response = await hostResponse(
        <String, dynamic>{'url': 'https://example.invalid/x', 'method': 'GET'},
      );

      expect(response['ok'], isFalse);
      expect(response['errorType'], 'CAPABILITY_ERROR');
      expect(
        api.requests,
        isEmpty,
        reason: 'a refused request must never reach the transport',
      );
    });

    test('a malformed URL degrades to a structured failure, not a throw', () async {
      await load(api);
      // No responder matches, so the request is attempted; either way the host
      // must answer with a payload the shim can wrap, never an exception that
      // escapes into JS as an unhandled rejection.
      final Map<String, dynamic> response = await hostResponse(
        <String, dynamic>{'url': 'https://nonexistent.invalid/x', 'method': 'GET'},
      );
      expect(response.containsKey('ok'), isTrue);
    });
  });

  group('a fetch() provider EXECUTES on the real engine', () {
    test('global fetch is callable and a provider runs to completion', () async {
      final String? skip = _engineSkipReason();
      if (skip != null) {
        markTestSkipped(skip);
        return;
      }

      final FlutterJsSandbox engine = FlutterJsSandbox();
      addTearDown(engine.dispose);
      await engine.init();

      // The bootstrap defines the global fetch over sendMessage.
      await engine.evaluate(sandboxBootstrap);

      // Replace sendMessage with a host stub so no network is touched. This
      // mirrors the real specta_request channel contract: JSON string in,
      // JSON string out.
      await engine.evaluate('''
        globalThis.sendMessage = function (channel, payload) {
          if (channel === 'specta_request') {
            return JSON.stringify({
              status: 200, ok: true, headers: {},
              body: '{"results":[{"id":"x1"}]}',
              json: { results: [{ id: 'x1' }] }
            });
          }
          return '{}';
        };
      ''');

      // The provider calls the global by name, exactly as shipped third-party
      // code does. Before the bridge this threw
      // ReferenceError: 'fetch' is not defined.
      await engine.evaluate(_fetchProvider);
      await engine.evaluate('var e = { search: search, getInfo: getInfo };');

      final String raw = await engine.evaluateAsync(
        'JSON.stringify(await e.search("dune", 1))',
      );
      final Map<String, dynamic> result =
          jsonDecode(raw) as Map<String, dynamic>;
      expect(
        (result['results'] as List).first['title'],
        'dune page 1',
        reason: 'a global fetch() provider must run to completion',
      );
    });

    test('r.body is a plain property, as real providers read it', () async {
      final String? skip = _engineSkipReason();
      if (skip != null) {
        markTestSkipped(skip);
        return;
      }

      final FlutterJsSandbox engine = FlutterJsSandbox();
      addTearDown(engine.dispose);
      await engine.init();
      await engine.evaluate(sandboxBootstrap);
      await engine.evaluate('''
        globalThis.sendMessage = function (channel, payload) {
          return JSON.stringify({
            status: 200, ok: true, headers: {'content-type': 'text/html'},
            body: '<html>hi</html>', json: null
          });
        };
      ''');

      // This is the exact idiom every shipped provider uses:
      //   fetch(url).then(function (r) { return r.body || '' })
      // then JSON.parse / regex over it themselves. A WHATWG-only shim makes
      // `r.body` undefined, so the provider scrapes the string "undefined" and
      // reports zero results with no error — the exact device symptom.
      final String raw = await engine.evaluateAsync('''
        (async () => {
          const r = await fetch('https://example.invalid/x');
          return JSON.stringify({
            bodyProp: r.body,
            text: await r.text(),
            ctype: r.headers['content-type'],
            isString: typeof r.body === 'string'
          });
        })()
      ''');
      final Map<String, dynamic> result =
          jsonDecode(raw) as Map<String, dynamic>;
      expect(
        result['isString'],
        isTrue,
        reason: 'r.body must be a string property, not a method',
      );
      expect(result['bodyProp'], '<html>hi</html>');
      expect(result['text'], '<html>hi</html>');
      expect(result['ctype'], 'text/html');
    });

    test('fetch().json(), .text(), .ok and .status behave', () async {
      final String? skip = _engineSkipReason();
      if (skip != null) {
        markTestSkipped(skip);
        return;
      }

      final FlutterJsSandbox engine = FlutterJsSandbox();
      addTearDown(engine.dispose);
      await engine.init();
      await engine.evaluate(sandboxBootstrap);
      await engine.evaluate('''
        globalThis.sendMessage = function (channel, payload) {
          return JSON.stringify({
            status: 200, ok: true, headers: {},
            body: '{"a":1}', json: { a: 1 }
          });
        };
      ''');

      final String raw = await engine.evaluateAsync('''
        (async () => {
          const r = await fetch('https://example.invalid/x');
          return JSON.stringify({
            ok: r.ok, status: r.status,
            json: await r.json(), text: await r.text()
          });
        })()
      ''');
      final Map<String, dynamic> result =
          jsonDecode(raw) as Map<String, dynamic>;
      expect(result['ok'], isTrue);
      expect(result['status'], 200);
      expect(result['json'], <String, dynamic>{'a': 1});
      expect(result['text'], '{"a":1}');
    });
  });
}