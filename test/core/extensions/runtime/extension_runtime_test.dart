import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/contract/extension_capability.dart';
import 'package:specta/core/extensions/contract/extension_capabilities.dart';
import 'package:specta/core/extensions/contract/extension_source.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/extensions/runtime/extension_runtime.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';

import '../../../support/fake_js_sandbox.dart';

/// Every capability, so tests that are about dispatch and parsing are not also
/// testing the capability gate. Capability gating has its own tests, which pass
/// an explicit set.
final Set<ExtensionCapability> allCapabilities = ExtensionCapability.values
    .toSet();

void main() {
  late FakeJsSandbox sandbox;
  late FakeRuntimeApi api;

  setUp(() {
    sandbox = FakeJsSandbox();
    api = FakeRuntimeApi();
  });

  Future<ExtensionRuntime> loadRuntime(
    FakeJsSandbox sandbox,
    FakeRuntimeApi api, {
    required String jsCode,
    Set<ExtensionCapability>? capabilities,
  }) async {
    sandbox.setEvalResult(sandboxBootstrap, '');
    final ExtensionRuntime runtime = ExtensionRuntime(
      sandbox: sandbox,
      api: api,
      // Defaults to a fully-declared extension; pass a set explicitly to test
      // the capability gate.
      capabilities: capabilities ?? allCapabilities,
    );
    final SpectaResult<void> result = await runtime.loadExtension(
      extensionId: 'test',
      jsCode: jsCode,
    );
    expect(result.isOk, isTrue, reason: result.failureOrNull.toString());
    return runtime;
  }

  group('ExtensionRuntime', () {
    test('loadExtension injects bootstrap and loads extension code', () async {
      sandbox.setEvalResult(sandboxBootstrap, '');
      final ExtensionRuntime runtime = ExtensionRuntime(
        sandbox: sandbox,
        api: api,
      );

      final SpectaResult<void> result = await runtime.loadExtension(
        extensionId: 'test-extension',
        jsCode: 'class Extension extends SpectaExtension {}',
      );

      expect(result.isOk, isTrue);
      expect(runtime.isLoaded, isTrue);
      expect(sandbox.evalCalls, contains(sandboxBootstrap));
      expect(
        sandbox.evalCalls,
        contains('class Extension extends SpectaExtension {}'),
      );
    });

    test('loadExtension returns error when sandbox init fails', () async {
      sandbox.isReady = false;
      sandbox.shouldFailInit = true;
      final ExtensionRuntime runtime = ExtensionRuntime(
        sandbox: sandbox,
        api: api,
      );

      final SpectaResult<void> result = await runtime.loadExtension(
        extensionId: 'test',
        jsCode: '',
      );

      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<ExtensionFailure>());
      expect(
        (result.failureOrNull as ExtensionFailure).type,
        ExtensionFailureType.runtimeError,
      );
    });

    test(
      'loadExtension returns error when bootstrap injection fails',
      () async {
        sandbox.setEvalError(sandboxBootstrap, 'Bootstrap error');
        final ExtensionRuntime runtime = ExtensionRuntime(
          sandbox: sandbox,
          api: api,
        );

        final SpectaResult<void> result = await runtime.loadExtension(
          extensionId: 'test',
          jsCode: '',
        );

        expect(result.isErr, isTrue);
        expect(
          (result.failureOrNull as ExtensionFailure).message,
          contains('bootstrap'),
        );
      },
    );

    test(
      'loadExtension returns error when extension JS fails to parse',
      () async {
        sandbox.setEvalResult(sandboxBootstrap, '');
        const String jsCode = 'invalid js {{{';
        sandbox.setEvalError(jsCode, 'Syntax error');
        final ExtensionRuntime runtime = ExtensionRuntime(
          sandbox: sandbox,
          api: api,
        );

        final SpectaResult<void> result = await runtime.loadExtension(
          extensionId: 'test',
          jsCode: jsCode,
        );

        expect(result.isErr, isTrue);
        expect(
          (result.failureOrNull as ExtensionFailure).message,
          contains('failed to load'),
        );
      },
    );

    test('loadExtension returns error when load() fails', () async {
      sandbox.setEvalResult(sandboxBootstrap, '');
      // The runtime instantiates the extension (sync evaluate) and then awaits
      // load() (async evaluate); this test makes the awaited call fail.
      sandbox.setEvalResult('var _spectaInstance = new Extension();', '');
      sandbox.setAsyncError(
        'await _spectaInstance.load();',
        'Extension load() failed',
      );
      final ExtensionRuntime runtime = ExtensionRuntime(
        sandbox: sandbox,
        api: api,
      );

      final SpectaResult<void> result = await runtime.loadExtension(
        extensionId: 'test',
        jsCode: 'class Extension extends SpectaExtension {}',
      );

      expect(result.isErr, isTrue);
      expect(
        (result.failureOrNull as ExtensionFailure).message,
        contains('load() failed'),
      );
    });

    test('capabilities dispatches to JS and parses result', () async {
      final ExtensionRuntime runtime = await loadRuntime(
        sandbox,
        api,
        jsCode: 'class Extension extends SpectaExtension {}',
      );

      sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.capabilities())',
        FakeJsSandbox.textCapabilities(),
      );

      final SpectaResult<ExtensionCapabilities> result = await runtime
          .capabilities();

      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.search, isTrue);
      expect(result.valueOrNull!.latest, isTrue);
      expect(result.valueOrNull!.details, isTrue);
      expect(result.valueOrNull!.mp4Sources, isTrue);
      expect(result.valueOrNull!.hlsSources, isTrue);
    });

    test('search dispatches to JS and parses results', () async {
      final ExtensionRuntime runtime = await loadRuntime(
        sandbox,
        api,
        jsCode: 'class Extension extends SpectaExtension {}',
      );

      sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.search("query", 1))',
        FakeJsSandbox.searchTextResults(3),
      );

      final SpectaResult<List<SearchResult>> result = await runtime.search(
        query: 'query',
        page: 1,
      );

      expect(result.isOk, isTrue);
      expect(result.valueOrNull, isNotNull);
      expect(result.valueOrNull!.length, 3);
      expect(result.valueOrNull![0].title, 'Test Movie 0');
      expect(result.valueOrNull![0].type, MediaType.movie);
    });

    test('details parses a series with seasons and episodes', () async {
      final ExtensionRuntime runtime = await loadRuntime(
        sandbox,
        api,
        jsCode: 'class Extension extends SpectaExtension {}',
      );

      const String url = 'https://example.com/series/1';
      sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.details("$url"))',
        jsonEncode(<String, dynamic>{
          'id': 's1',
          'title': 'Test Series',
          'type': 'series',
          'url': url,
          'year': 2024,
          'rating': 7.5,
          'status': 'ongoing',
          'genres': <String>['drama'],
          'seasons': <Map<String, dynamic>>[
            <String, dynamic>{
              'seasonNumber': 1,
              'title': 'Season One',
              'episodes': <Map<String, dynamic>>[
                <String, dynamic>{
                  'episodeNumber': 1,
                  'title': 'Pilot',
                  'url': '$url/e1',
                  'duration': 2700,
                },
              ],
            },
          ],
        }),
      );

      final SpectaResult<MediaDetails> result = await runtime.details(url: url);

      expect(result.isOk, isTrue);
      final MediaDetails details = result.valueOrNull!;
      expect(details.title, 'Test Series');
      expect(details.type, MediaType.series);
      expect(details.status, SeriesStatus.ongoing);
      expect(details.rating, 7.5);
      expect(details.genres, <String>['drama']);
      expect(details.seasons.length, 1);
      expect(details.seasons.single.episodes.single.episodeNumber, 1);
      expect(details.seasons.single.episodes.single.durationSeconds, 2700);
    });

    test(
      'details applied to a malformed payload stays a controlled failure',
      () async {
        final ExtensionRuntime runtime = await loadRuntime(
          sandbox,
          api,
          jsCode: 'class Extension extends SpectaExtension {}',
        );

        const String url = 'https://example.com/movie/1';
        // Missing the required title/type/url fields.
        sandbox.setAsyncResult(
          'JSON.stringify(await _spectaInstance.details("$url"))',
          jsonEncode(<String, dynamic>{'id': 'm1'}),
        );

        final SpectaResult<MediaDetails> result = await runtime.details(
          url: url,
        );

        expect(result.isErr, isTrue);
        expect(
          (result.failureOrNull! as ExtensionFailure).type,
          ExtensionFailureType.runtimeError,
        );
      },
    );

    group('details payload robustness (Phase 2C)', () {
      Future<SpectaResult<MediaDetails>> parse(Object? payload) async {
        final ExtensionRuntime runtime = await loadRuntime(
          sandbox,
          api,
          jsCode: 'class Extension extends SpectaExtension {}',
        );
        const String url = 'https://example.com/title/1';
        sandbox.setAsyncResult(
          'JSON.stringify(await _spectaInstance.details("$url"))',
          payload is String ? payload : jsonEncode(payload),
        );
        return runtime.details(url: url);
      }

      test(
        'a missing type is a controlled failure, not a silent movie',
        () async {
          final SpectaResult<MediaDetails> result = await parse(
            <String, dynamic>{
              'id': 'x1',
              'title': 'No Type',
              'url': 'https://example.com/title/1',
            },
          );

          expect(result.isErr, isTrue);
        },
      );

      test(
        'an unsupported type is a controlled failure, not a silent movie',
        () async {
          final SpectaResult<MediaDetails> result = await parse(
            <String, dynamic>{
              'id': 'x1',
              'title': 'Documentary Thing',
              'type': 'documentary',
              'url': 'https://example.com/title/1',
            },
          );

          expect(result.isErr, isTrue);
        },
      );

      test('a blank title is a controlled failure', () async {
        final SpectaResult<MediaDetails> result = await parse(<String, dynamic>{
          'id': 'x1',
          'title': '   ',
          'type': 'movie',
          'url': 'https://example.com/title/1',
        });

        expect(result.isErr, isTrue);
      });

      test('an out-of-range rating is dropped to null, not clamped', () async {
        final SpectaResult<MediaDetails> result = await parse(<String, dynamic>{
          'id': 'x1',
          'title': 'Rated Movie',
          'type': 'movie',
          'url': 'https://example.com/title/1',
          'rating': 11.5,
        });

        expect(result.isOk, isTrue);
        expect(result.valueOrNull!.rating, isNull);
      });

      test(
        'malformed season and episode rows are skipped individually',
        () async {
          final SpectaResult<MediaDetails> result = await parse(
            <String, dynamic>{
              'id': 'x1',
              'title': 'Messy Series',
              'type': 'series',
              'url': 'https://example.com/title/1',
              'seasons': <dynamic>[
                'not-a-season',
                <String, dynamic>{
                  'seasonNumber': 1,
                  'episodes': <dynamic>[
                    'not-an-episode',
                    <String, dynamic>{
                      'episodeNumber': 1,
                      'url': 'https://example.com/title/1/e1',
                    },
                    <String, dynamic>{'episodeNumber': 2}, // no url — skipped
                  ],
                },
                <String, dynamic>{
                  'seasonNumber': 'two',
                }, // no int number — skipped
              ],
            },
          );

          expect(result.isOk, isTrue);
          final MediaDetails details = result.valueOrNull!;
          expect(details.seasons.length, 1);
          expect(details.seasons.single.episodes.length, 1);
          expect(details.seasons.single.episodes.single.episodeNumber, 1);
        },
      );

      test('a non-object payload is a controlled failure', () async {
        final SpectaResult<MediaDetails> result = await parse('[1, 2, 3]');

        expect(result.isErr, isTrue);
      });
    });

    test('getSources parses MP4 and HLS sources with headers', () async {
      final ExtensionRuntime runtime = await loadRuntime(
        sandbox,
        api,
        jsCode: 'class Extension extends SpectaExtension {}',
      );

      const String reference = 'https://example.com/movie/1';
      sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.getSources("$reference"))',
        jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{
            'url': 'https://cdn.example.com/a.mp4',
            'type': 'mp4',
            'quality': '1080p',
            'label': 'Server 1',
            'headers': <String, String>{'referer': 'https://example.com'},
          },
          <String, dynamic>{
            'url': 'https://cdn.example.com/b.m3u8',
            'type': 'hls',
            'quality': '720p',
            'isAdaptive': true,
          },
        ]),
      );

      final SpectaResult<List<ExtensionSource>> result = await runtime
          .getSources(reference: reference);

      expect(result.isOk, isTrue);
      final List<ExtensionSource> sources = result.valueOrNull!;
      expect(sources.length, 2);
      expect(sources[0].type, SourceType.mp4);
      expect(sources[0].quality, '1080p');
      expect(sources[0].label, 'Server 1');
      expect(sources[0].headers!['referer'], 'https://example.com');
      expect(sources[1].type, SourceType.hls);
      expect(sources[1].isAdaptive, isTrue);
    });

    // 2G-C pre-flight §36.4: this test previously pinned the all-or-nothing
    // failure (the bug — one unsupported row lost every valid source with
    // it); it now pins the corrected skip-the-bad-row behavior.
    test('a DASH source among valid ones is SKIPPED, not fatal', () async {
      final ExtensionRuntime runtime = await loadRuntime(
        sandbox,
        api,
        jsCode: 'class Extension extends SpectaExtension {}',
      );

      const String reference = 'https://example.com/movie/2';
      // DASH is deliberately outside the V1 source scope. A mixed list is the
      // realistic case: one unsupported row must not lose the mp4 sources.
      sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.getSources("$reference"))',
        jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{
            'url': 'https://cdn.example.com/a.mp4',
            'type': 'mp4',
            'quality': '1080p',
          },
          <String, dynamic>{
            'url': 'https://cdn.example.com/c.mpd',
            'type': 'dash',
          },
          <String, dynamic>{
            'url': 'https://cdn.example.com/b.mp4',
            'type': 'mp4',
          },
        ]),
      );

      final SpectaResult<List<ExtensionSource>> result = await runtime
          .getSources(reference: reference);

      expect(result.isOk, isTrue);
      final List<ExtensionSource> sources = result.valueOrNull!;
      expect(sources, hasLength(2));
      expect(sources[0].url, 'https://cdn.example.com/a.mp4');
      expect(sources[1].url, 'https://cdn.example.com/b.mp4');
    });

    test('a getSources list that is entirely unusable parses to an empty success, not a failure', () async {
      final ExtensionRuntime runtime = await loadRuntime(
        sandbox,
        api,
        jsCode: 'class Extension extends SpectaExtension {}',
      );

      const String reference = 'https://example.com/movie/2';
      sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.getSources("$reference"))',
        jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{
            'url': 'https://cdn.example.com/c.mpd',
            'type': 'dash',
          },
        ]),
      );

      final SpectaResult<List<ExtensionSource>> result = await runtime
          .getSources(reference: reference);

      expect(result.isOk, isTrue);
      expect(result.valueOrNull, isEmpty);
    });

    test('healthCheck dispatches to JS and returns result', () async {
      final ExtensionRuntime runtime = await loadRuntime(
        sandbox,
        api,
        jsCode: 'class Extension extends SpectaExtension {}',
      );

      sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.healthCheck())',
        'true',
      );

      final SpectaResult<bool> result = await runtime.healthCheck();

      expect(result.isOk, isTrue);
      expect(result.valueOrNull, isTrue);
    });

    test('operation on unloaded runtime returns error', () async {
      final ExtensionRuntime runtime = ExtensionRuntime(
        sandbox: sandbox,
        api: api,
      );

      final SpectaResult<bool> result = await runtime.healthCheck();
      expect(result.isErr, isTrue);
      final ExtensionFailure failure =
          result.failureOrNull! as ExtensionFailure;
      expect(failure.type, ExtensionFailureType.runtimeError);
      expect(failure.message, contains('not loaded'));
    });

    test('shutdown calls shutdown() and disposes sandbox', () async {
      final ExtensionRuntime runtime = await loadRuntime(
        sandbox,
        api,
        jsCode: 'class Extension extends SpectaExtension {}',
      );

      sandbox.setAsyncResult('await _spectaInstance.shutdown();', '');

      await runtime.shutdown();
      expect(runtime.isLoaded, isFalse);
      expect(sandbox.isDisposed, isTrue);
    });

    test('shutdown on unloaded runtime returns without error', () async {
      final ExtensionRuntime runtime = ExtensionRuntime(
        sandbox: sandbox,
        api: api,
      );
      await runtime.shutdown();
      expect(runtime.isLoaded, isFalse);
    });

    test('JS evaluation error in operation returns RUNTIME_ERROR', () async {
      final ExtensionRuntime runtime = await loadRuntime(
        sandbox,
        api,
        jsCode: 'class Extension extends SpectaExtension {}',
      );

      sandbox.setAsyncError(
        'JSON.stringify(await _spectaInstance.healthCheck())',
        'JS runtime error',
        detail: 'stack trace here',
      );

      final SpectaResult<bool> result = await runtime.healthCheck();
      expect(result.isErr, isTrue);
      final ExtensionFailure failure =
          result.failureOrNull! as ExtensionFailure;
      expect(failure.type, ExtensionFailureType.runtimeError);
      expect(failure.message, contains('JS evaluation failed'));
      expect(failure.detail, contains('stack trace here'));
    });

    test('timeout on operation returns TIMEOUT failure', () async {
      final ExtensionRuntime runtime = await loadRuntime(
        sandbox,
        api,
        jsCode: 'class Extension extends SpectaExtension {}',
      );

      sandbox.forceTimeout = true;
      sandbox.delay = const Duration(seconds: 35);

      final SpectaResult<bool> result = await runtime.healthCheck();
      expect(result.isErr, isTrue);
      final ExtensionFailure failure =
          result.failureOrNull! as ExtensionFailure;
      expect(failure.type, ExtensionFailureType.timeout);
    }, timeout: const Timeout(Duration(seconds: 45)));

    test('request API routes through controlled ExtensionRuntimeApi', () async {
      final ExtensionRuntime runtime = await loadRuntime(
        sandbox,
        api,
        jsCode: 'class Extension extends SpectaExtension {}',
      );

      sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.healthCheck())',
        'true',
      );

      await runtime.healthCheck();
      expect(api.requestCount, 0);
      expect(api.logCount, 0);

      sandbox.triggerMessage(
        'specta_log',
        jsonEncode(<String, dynamic>{'level': 'info', 'message': 'test log'}),
      );
      expect(api.logCount, 1);
      expect(api.messages, contains('test log'));
    });

    test('only the two controlled channels are registered', () async {
      await loadRuntime(
        sandbox,
        api,
        jsCode: 'class Extension extends SpectaExtension {}',
      );

      expect(
        sandbox.handlers.keys,
        containsAll(<String>['specta_request', 'specta_log']),
      );
      expect(sandbox.handlers.length, 2);

      // A channel the runtime never registered has no handler, so an extension
      // cannot use sendMessage to reach anything else in the host.
      expect(sandbox.triggerMessage('specta_filesystem', '{}'), isNull);
    });

    test('specta_request is dispatched to the host request API', () async {
      await loadRuntime(
        sandbox,
        api,
        jsCode: 'class Extension extends SpectaExtension {}',
      );

      final dynamic raw = sandbox.triggerMessage(
        'specta_request',
        jsonEncode(<String, dynamic>{
          'url': 'https://example.com/api',
          'method': 'post',
          'headers': <String, String>{'accept': 'application/json'},
          'query': <String, String>{'q': 'test'},
          'timeout': 5000,
        }),
      );
      final String encoded = await raw as String;

      expect(api.requestCount, 1);
      expect(api.lastRequest!.url, 'https://example.com/api');
      // The host upper-cases the method before it reaches the API.
      expect(api.lastRequest!.method, 'POST');
      expect(api.lastRequest!.headers['accept'], 'application/json');
      expect(api.lastRequest!.queryParameters['q'], 'test');
      expect(api.lastRequest!.timeout, const Duration(milliseconds: 5000));

      final Map<String, dynamic> decoded =
          jsonDecode(encoded) as Map<String, dynamic>;
      expect(decoded['status'], 200);
      expect(decoded['ok'], isTrue);
    });

    test(
      'a host request failure degrades to a structured error payload',
      () async {
        await loadRuntime(
          sandbox,
          api,
          jsCode: 'class Extension extends SpectaExtension {}',
        );
        api.requestThrows = StateError('socket closed');

        final dynamic raw = sandbox.triggerMessage(
          'specta_request',
          jsonEncode(<String, dynamic>{'url': 'https://example.com/api'}),
        );
        final Map<String, dynamic> decoded =
            jsonDecode(await raw as String) as Map<String, dynamic>;

        expect(decoded['ok'], isFalse);
        expect(decoded['status'], isNull);
        expect(decoded['error'], contains('socket closed'));
      },
    );

    test(
      'a malformed request payload degrades to a structured error',
      () async {
        await loadRuntime(
          sandbox,
          api,
          jsCode: 'class Extension extends SpectaExtension {}',
        );

        final dynamic raw = sandbox.triggerMessage(
          'specta_request',
          'not json',
        );
        final Map<String, dynamic> decoded =
            jsonDecode(await raw as String) as Map<String, dynamic>;

        expect(decoded['ok'], isFalse);
        expect(api.requestCount, 0);
      },
    );

    test(
      'loadExtension isolates a sandbox failure that is not a JsEvalException',
      () async {
        const String jsCode = 'class Extension extends SpectaExtension {}';
        // The bootstrap succeeds; evaluating the extension itself raises a
        // failure the sandbox contract does not require to be a
        // JsEvalException. Nothing may escape to the caller.
        sandbox.setEvalResult(sandboxBootstrap, '');
        sandbox.setEvalThrow(jsCode, StateError('native engine failure'));
        final ExtensionRuntime runtime = ExtensionRuntime(
          sandbox: sandbox,
          api: api,
        );

        final SpectaResult<void> result = await runtime.loadExtension(
          extensionId: 'test',
          jsCode: jsCode,
        );

        expect(result.isErr, isTrue);
        final ExtensionFailure failure =
            result.failureOrNull! as ExtensionFailure;
        expect(failure.type, ExtensionFailureType.runtimeError);
        expect(failure.message, contains('failed to load'));
        expect(failure.detail, contains('native engine failure'));
        expect(runtime.isLoaded, isFalse);
      },
    );

    test('load() timing out becomes a controlled TIMEOUT failure', () async {
      sandbox.setEvalResult(sandboxBootstrap, '');
      sandbox.forceTimeout = true;
      sandbox.delay = const Duration(milliseconds: 50);
      final ExtensionRuntime runtime = ExtensionRuntime(
        sandbox: sandbox,
        api: api,
      );

      final SpectaResult<void> result = await runtime.loadExtension(
        extensionId: 'test',
        jsCode: 'class Extension extends SpectaExtension {}',
      );

      expect(result.isErr, isTrue);
      final ExtensionFailure failure =
          result.failureOrNull! as ExtensionFailure;
      expect(failure.type, ExtensionFailureType.timeout);
      expect(runtime.isLoaded, isFalse);
    });

    test(
      'shutdown disposes the sandbox even when nothing was loaded',
      () async {
        final ExtensionRuntime runtime = ExtensionRuntime(
          sandbox: sandbox,
          api: api,
        );

        await runtime.shutdown();

        expect(sandbox.isDisposed, isTrue);
      },
    );
  });

  group('ExtensionRuntime — capability enforcement', () {
    const String jsCode = 'class Extension extends SpectaExtension {}';

    test('the default runtime grants nothing but load still works', () async {
      sandbox.setEvalResult(sandboxBootstrap, '');
      final ExtensionRuntime runtime = ExtensionRuntime(
        sandbox: sandbox,
        api: api,
      );

      expect(runtime.grantedCapabilities, isEmpty);
      expect(
        (await runtime.loadExtension(extensionId: 'test', jsCode: jsCode)).isOk,
        isTrue,
      );
      expect(runtime.isGranted(ExtensionCapability.search), isFalse);
    });

    test(
      'an undeclared capability is denied with a CapabilityFailure',
      () async {
        final ExtensionRuntime runtime = await loadRuntime(
          sandbox,
          api,
          jsCode: jsCode,
          capabilities: const <ExtensionCapability>{},
        );

        final SpectaResult<List<SearchResult>> result = await runtime.search(
          query: 'matrix',
          page: 1,
        );

        expect(result.isErr, isTrue);
        final CapabilityFailure failure =
            result.failureOrNull! as CapabilityFailure;
        expect(failure.capability, ExtensionCapability.search.code);
        expect(failure.extensionId, 'test');
        expect(failure.message, contains('search'));
        // The refusal happens before JavaScript is involved at all.
        expect(
          sandbox.asyncEvalCalls.where((String e) => e.contains('.search(')),
          isEmpty,
        );
      },
    );

    test('a declared capability allows the operation', () async {
      final ExtensionRuntime runtime = await loadRuntime(
        sandbox,
        api,
        jsCode: jsCode,
        capabilities: const <ExtensionCapability>{ExtensionCapability.search},
      );
      sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.search("matrix", 1))',
        FakeJsSandbox.searchTextResults(2),
      );

      final SpectaResult<List<SearchResult>> result = await runtime.search(
        query: 'matrix',
        page: 1,
      );

      expect(result.isOk, isTrue, reason: result.failureOrNull.toString());
      expect(result.valueOrNull, hasLength(2));
    });

    test('each gated operation names the capability it needs', () async {
      final ExtensionRuntime runtime = await loadRuntime(
        sandbox,
        api,
        jsCode: jsCode,
        capabilities: const <ExtensionCapability>{},
      );

      Future<void> expectDenied(
        String expectedCapability,
        SpectaResult<Object?> result,
      ) async {
        expect(result.isErr, isTrue);
        final CapabilityFailure failure =
            result.failureOrNull! as CapabilityFailure;
        expect(failure.capability, expectedCapability);
      }

      await expectDenied('search', await runtime.search(query: 'q', page: 1));
      await expectDenied('latest', await runtime.latest(page: 1));
      await expectDenied(
        'details',
        await runtime.details(url: 'https://example.test/a'),
      );
      await expectDenied('sources', await runtime.getSources(reference: 'ref'));
      await expectDenied(
        'sources',
        await runtime.refreshSource(reference: 'ref'),
      );
    });

    test(
      'capabilities() and healthCheck() are never capability-gated',
      () async {
        // Gating either would make the rest unreachable or make a failing
        // extension indistinguishable from a forbidden one.
        final ExtensionRuntime runtime = await loadRuntime(
          sandbox,
          api,
          jsCode: jsCode,
          capabilities: const <ExtensionCapability>{},
        );
        sandbox.setAsyncResult(
          'JSON.stringify(await _spectaInstance.capabilities())',
          FakeJsSandbox.textCapabilities(),
        );
        sandbox.setAsyncResult(
          'JSON.stringify(await _spectaInstance.healthCheck())',
          'true',
        );

        expect((await runtime.capabilities()).isOk, isTrue);
        expect((await runtime.healthCheck()).isOk, isTrue);
      },
    );

    test('one declared capability does not unlock another', () async {
      final ExtensionRuntime runtime = await loadRuntime(
        sandbox,
        api,
        jsCode: jsCode,
        capabilities: const <ExtensionCapability>{ExtensionCapability.sources},
      );

      expect(
        (await runtime.getSources(reference: 'r')).isOk,
        isFalse,
        reason:
            'getSources needs its JS response configured; a denial must '
            'not depend on that',
      );
      final SpectaResult<List<SearchResult>> search = await runtime.search(
        query: 'q',
        page: 1,
      );
      expect((search.failureOrNull! as CapabilityFailure).capability, 'search');
    });

    test(
      'grantedCapabilities is an unmodifiable view of the declaration',
      () async {
        final ExtensionRuntime runtime = await loadRuntime(
          sandbox,
          api,
          jsCode: jsCode,
          capabilities: const <ExtensionCapability>{
            ExtensionCapability.network,
          },
        );

        expect(runtime.grantedCapabilities, <ExtensionCapability>{
          ExtensionCapability.network,
        });
        expect(
          () => runtime.grantedCapabilities.clear(),
          throwsUnsupportedError,
        );
        expect(runtime.isGranted(ExtensionCapability.network), isTrue);
        expect(runtime.isGranted(ExtensionCapability.logging), isFalse);
      },
    );

    test('a denied operation reports the extension identity', () async {
      final ExtensionRuntime runtime = ExtensionRuntime(
        sandbox: sandbox,
        api: api,
        capabilities: const <ExtensionCapability>{},
      );
      sandbox.setEvalResult(sandboxBootstrap, '');
      await runtime.loadExtension(
        extensionId: 'com.example.denied',
        jsCode: jsCode,
      );

      final CapabilityFailure failure =
          (await runtime.search(query: 'q', page: 1)).failureOrNull!
              as CapabilityFailure;
      expect(failure.extensionId, 'com.example.denied');
      expect(failure.isRetryable, isFalse);
      expect(failure.capability, 'search');
      expect(failure.toString(), contains('com.example.denied'));
    });
  });

  group('ExtensionRuntime — host channels and capabilities', () {
    const String jsCode = 'class Extension extends SpectaExtension {}';

    test(
      'the request channel is refused without the network capability',
      () async {
        await loadRuntime(
          sandbox,
          api,
          jsCode: jsCode,
          capabilities: const <ExtensionCapability>{
            ExtensionCapability.logging,
          },
        );

        final String payload = await sandbox.triggerMessage(
          'specta_request',
          jsonEncode(<String, dynamic>{'url': 'https://example.test/a'}),
        );
        final Map<String, dynamic> response =
            jsonDecode(payload) as Map<String, dynamic>;

        expect(response['ok'], isFalse);
        expect(
          response['errorType'],
          ExtensionFailureType.capabilityError.code,
        );
        expect(response['error'], contains('network'));
        // The host API was never reached.
        expect(api.requestCount, 0);
      },
    );

    test('a refusal happens even when the payload is unparseable', () async {
      // Order matters: an undeclared capability must not be reachable by
      // sending something the parser chokes on.
      await loadRuntime(
        sandbox,
        api,
        jsCode: jsCode,
        capabilities: const <ExtensionCapability>{},
      );

      final String payload = await sandbox.triggerMessage(
        'specta_request',
        'not json at all',
      );
      final Map<String, dynamic> response =
          jsonDecode(payload) as Map<String, dynamic>;

      expect(response['errorType'], ExtensionFailureType.capabilityError.code);
      expect(api.requestCount, 0);
    });

    test('a declared network capability reaches the host API', () async {
      await loadRuntime(
        sandbox,
        api,
        jsCode: jsCode,
        capabilities: const <ExtensionCapability>{ExtensionCapability.network},
      );

      final String payload = await sandbox.triggerMessage(
        'specta_request',
        jsonEncode(<String, dynamic>{
          'url': 'https://example.test/a',
          'method': 'post',
          'headers': <String, String>{'x-a': 'b'},
        }),
      );
      final Map<String, dynamic> response =
          jsonDecode(payload) as Map<String, dynamic>;

      expect(response['ok'], isTrue);
      expect(response['status'], 200);
      expect(api.requestCount, 1);
      expect(api.lastRequest!.url, 'https://example.test/a');
      expect(api.lastRequest!.method, 'POST');
      expect(api.lastRequest!.headers, <String, String>{'x-a': 'b'});
    });

    test('a malformed request payload becomes a structured error', () async {
      await loadRuntime(
        sandbox,
        api,
        jsCode: jsCode,
        capabilities: const <ExtensionCapability>{ExtensionCapability.network},
      );

      final String payload = await sandbox.triggerMessage(
        'specta_request',
        'definitely not json',
      );
      final Map<String, dynamic> response =
          jsonDecode(payload) as Map<String, dynamic>;

      expect(response['ok'], isFalse);
      expect(response['errorType'], ExtensionFailureType.runtimeError.code);
      expect(api.requestCount, 0);
    });

    test(
      'a host request failure becomes a structured error, not a throw',
      () async {
        await loadRuntime(
          sandbox,
          api,
          jsCode: jsCode,
          capabilities: const <ExtensionCapability>{
            ExtensionCapability.network,
          },
        );
        api.requestThrows = Exception('host exploded');

        final String payload = await sandbox.triggerMessage(
          'specta_request',
          jsonEncode(<String, dynamic>{'url': 'https://example.test/a'}),
        );
        final Map<String, dynamic> response =
            jsonDecode(payload) as Map<String, dynamic>;

        expect(response['ok'], isFalse);
        expect(response['error'], contains('host exploded'));
      },
    );

    test(
      'the log channel drops messages without the logging capability',
      () async {
        await loadRuntime(
          sandbox,
          api,
          jsCode: jsCode,
          capabilities: const <ExtensionCapability>{
            ExtensionCapability.network,
          },
        );

        await sandbox.triggerMessage(
          'specta_log',
          jsonEncode(<String, dynamic>{'level': 'info', 'message': 'hi'}),
        );

        expect(api.logCount, 0);
      },
    );

    test('a declared logging capability forwards the message', () async {
      await loadRuntime(
        sandbox,
        api,
        jsCode: jsCode,
        capabilities: const <ExtensionCapability>{ExtensionCapability.logging},
      );

      await sandbox.triggerMessage(
        'specta_log',
        jsonEncode(<String, dynamic>{
          'level': 'warning',
          'message': 'watch out',
        }),
      );

      expect(api.logCount, 1);
      expect(api.messages.single, 'watch out');
    });

    test(
      'a malformed log payload is swallowed without touching the host',
      () async {
        await loadRuntime(
          sandbox,
          api,
          jsCode: jsCode,
          capabilities: const <ExtensionCapability>{
            ExtensionCapability.logging,
          },
        );

        await sandbox.triggerMessage('specta_log', 'not json');

        expect(api.logCount, 0);
      },
    );
  });

  group('search/latest result parsing robustness (Phase 2B)', () {
    test(
      'an unsupported media type is skipped, not converted to movie',
      () async {
        final ExtensionRuntime runtime = await loadRuntime(
          sandbox,
          api,
          jsCode: 'class Extension extends SpectaExtension {}',
        );
        sandbox.setAsyncResult(
          'JSON.stringify(await _spectaInstance.search("q", 1))',
          jsonEncode(<dynamic>[
            <String, dynamic>{
              'title': 'A Movie',
              'url': 'https://e.test/m',
              'type': 'movie',
            },
            <String, dynamic>{
              'title': 'Some Anime',
              'url': 'https://e.test/a',
              'type': 'anime',
            },
            <String, dynamic>{
              'title': 'Some Novel',
              'url': 'https://e.test/n',
              'type': 'novel',
            },
          ]),
        );

        final SpectaResult<List<SearchResult>> result = await runtime.search(
          query: 'q',
          page: 1,
        );

        expect(result.isOk, isTrue, reason: result.failureOrNull.toString());
        expect(result.valueOrNull!.map((SearchResult r) => r.title), <String>[
          'A Movie',
        ]);
      },
    );

    test(
      'entries missing title/url and non-object entries are skipped',
      () async {
        final ExtensionRuntime runtime = await loadRuntime(
          sandbox,
          api,
          jsCode: 'class Extension extends SpectaExtension {}',
        );
        sandbox.setAsyncResult(
          'JSON.stringify(await _spectaInstance.search("q", 1))',
          jsonEncode(<dynamic>[
            <String, dynamic>{
              'title': 'Good',
              'url': 'https://e.test/good',
              'type': 'movie',
              'year': 2024,
            },
            <String, dynamic>{'url': 'https://e.test/x', 'type': 'movie'},
            <String, dynamic>{'title': 'No URL', 'type': 'movie'},
            <String, dynamic>{'title': '', 'url': 'https://e.test/e'},
            'a bare string',
            <int>[1, 2],
          ]),
        );

        final SpectaResult<List<SearchResult>> result = await runtime.search(
          query: 'q',
          page: 1,
        );

        expect(result.isOk, isTrue);
        expect(result.valueOrNull!.length, 1);
        expect(result.valueOrNull!.single.title, 'Good');
        expect(result.valueOrNull!.single.year, 2024);
      },
    );

    test(
      'a list of all-invalid entries parses to an empty success, not an error',
      () async {
        final ExtensionRuntime runtime = await loadRuntime(
          sandbox,
          api,
          jsCode: 'class Extension extends SpectaExtension {}',
        );
        sandbox.setAsyncResult(
          'JSON.stringify(await _spectaInstance.search("q", 1))',
          jsonEncode(<dynamic>[
            <String, dynamic>{'title': 'Anime', 'url': 'u', 'type': 'anime'},
            <String, String?>{'title': null, 'url': 'u'},
          ]),
        );

        final SpectaResult<List<SearchResult>> result = await runtime.search(
          query: 'q',
          page: 1,
        );

        expect(result.isOk, isTrue);
        expect(result.valueOrNull, isEmpty);
      },
    );

    test('latest applies the same skip rules', () async {
      final ExtensionRuntime runtime = await loadRuntime(
        sandbox,
        api,
        jsCode: 'class Extension extends SpectaExtension {}',
      );
      sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.latest(1))',
        jsonEncode(<dynamic>[
          <String, dynamic>{
            'title': 'A Series',
            'url': 'https://e.test/s',
            'type': 'series',
          },
          <String, dynamic>{'title': 'A Comic', 'url': 'u', 'type': 'comic'},
        ]),
      );

      final SpectaResult<List<SearchResult>> result = await runtime.latest(
        page: 1,
      );

      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.single.type, MediaType.series);
    });
  });

  /// ES module evaluation (2E). The runtime must decide script-versus-module
  /// BEFORE evaluating, because QuickJS rejects `import`/`export` in script
  /// mode with a SyntaxError.
  ///
  /// These use the fake sandbox, so they always run and they assert the
  /// DECISION. Whether the engine then honours the flag is covered by the
  /// real-engine tests in `flutter_js_sandbox_test.dart`.
  group('ExtensionRuntime - ES module evaluation flags (2E)', () {
    /// The recorded flags for [source], or null when it was evaluated with none.
    int? flagsFor(FakeJsSandbox sandbox, String source) {
      final Iterable<(String, int)> matches = sandbox.evalCallsWithFlags.where(
        ((String, int) entry) => entry.$1 == source,
      );
      return matches.isEmpty ? null : matches.first.$2;
    }

    test('a plain script is evaluated without the module flag', () async {
      final FakeJsSandbox sandbox = FakeJsSandbox();
      const String script = 'class Extension extends SpectaExtension {}';

      await loadRuntime(sandbox, FakeRuntimeApi(), jsCode: script);

      expect(sandbox.evalCalls, contains(script));
      expect(flagsFor(sandbox, script), isNull);
    });

    test('a top-level export selects module mode', () async {
      final FakeJsSandbox sandbox = FakeJsSandbox();
      const String source = 'class Extension {}\nexport { Extension };';

      await loadRuntime(sandbox, FakeRuntimeApi(), jsCode: source);

      expect(flagsFor(sandbox, source), JSEvalFlag.MODULE);
    });

    test('a top-level import selects module mode', () async {
      final FakeJsSandbox sandbox = FakeJsSandbox();
      const String source = "import { helper } from './helper.js';";

      await loadRuntime(sandbox, FakeRuntimeApi(), jsCode: source);

      expect(flagsFor(sandbox, source), JSEvalFlag.MODULE);
    });

    test('export with no space before the brace is still detected', () async {
      final FakeJsSandbox sandbox = FakeJsSandbox();
      const String source = 'const a = 1;\nexport{a};';

      await loadRuntime(sandbox, FakeRuntimeApi(), jsCode: source);

      expect(flagsFor(sandbox, source), JSEvalFlag.MODULE);
    });

    test('leading whitespace does not hide the export', () async {
      final FakeJsSandbox sandbox = FakeJsSandbox();
      const String source = '\n\n    export const a = 1;';

      await loadRuntime(sandbox, FakeRuntimeApi(), jsCode: source);

      expect(flagsFor(sandbox, source), JSEvalFlag.MODULE);
    });

    test('the sandbox bootstrap is never evaluated as a module', () async {
      final FakeJsSandbox sandbox = FakeJsSandbox();

      await loadRuntime(
        sandbox,
        FakeRuntimeApi(),
        jsCode: 'class Extension extends SpectaExtension {}',
      );

      // The bootstrap is SPECTA's own script; treating it as a module would
      // put the SpectaExtension base class out of global scope and break every
      // extension at once.
      expect(sandbox.evalCalls, contains(sandboxBootstrap));
      expect(flagsFor(sandbox, sandboxBootstrap), isNull);
    });

    test('a keyword inside a string does not select module mode', () async {
      final FakeJsSandbox sandbox = FakeJsSandbox();
      const String source =
          "class Extension {}\nconst s = 'export const x = 1;';";

      await loadRuntime(sandbox, FakeRuntimeApi(), jsCode: source);

      // The check is anchored to line starts, so an embedded keyword that is
      // not at the start of a line is not treated as module syntax.
      expect(flagsFor(sandbox, source), isNull);
    });
  });
}

class FakeRuntimeApi implements ExtensionRuntimeApi {
  int logCount = 0;
  int requestCount = 0;
  final List<String> messages = <String>[];

  /// The most recent request handed to the host API.
  ExtensionRequest? lastRequest;

  /// When set, [request] throws it instead of answering.
  Object? requestThrows;

  @override
  Future<ExtensionResponse> request(ExtensionRequest request) async {
    requestCount++;
    lastRequest = request;
    if (requestThrows != null) {
      throw requestThrows!;
    }
    return ExtensionResponse(status: 200, ok: true, body: '{}');
  }

  @override
  void log(ExtensionLogLevel level, String message) {
    logCount++;
    messages.add(message);
  }
}
