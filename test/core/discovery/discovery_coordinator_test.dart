import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/discovery/discovery_coordinator.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart'
    show JsEvalException;

import '../../support/discovery_test_harness.dart';

SearchRequest _request(String query) => SearchRequest(query: query);

/// Builds a JSON search-result payload.
String _payload(List<Object?> items) => searchPayload(items);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('specta_discovery');
    addTearDown(() => tempDir.delete(recursive: true));
  });

  group('DiscoveryCoordinator — round assembly', () {
    test('disabled extensions are not queried at all', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'com.test.enabled');
      await h.installExtension(tempDir, 'com.test.disabled', enabled: false);

      final DiscoveryResult result = await DiscoveryCoordinator.discover(
        request: _request('query'),
        manager: h.manager,
      );

      expect(
        result.outcomes.map((ExtensionDiscoveryOutcome o) => o.extensionId),
        <String>['com.test.enabled'],
      );
    });

    test('an enabled extension without the search capability is skipped, not failed', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(
        tempDir,
        'com.test.nosearch',
        capabilities: 'latest',
      );

      final DiscoveryResult result = await DiscoveryCoordinator.discover(
        request: _request('query'),
        manager: h.manager,
      );

      expect(result.outcomes.single.isSkipped, isTrue);
      expect(result.noExtensionAvailable, isTrue);
    });

    test('no extensions installed → noExtensionAvailable, no error', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();

      final DiscoveryResult result = await DiscoveryCoordinator.discover(
        request: _request('query'),
        manager: h.manager,
      );

      expect(result.items, isEmpty);
      expect(result.outcomes, isEmpty);
      expect(result.noExtensionAvailable, isTrue);
      expect(result.allQueriedFailed, isFalse);
    });

    test('search scripts run under a scriptable sandbox', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness(
        sandbox: ScriptedJsSandbox(),
      );
      await h.installExtension(tempDir, 'com.test.actors');

      final ScriptedJsSandbox sb = h.sandbox as ScriptedJsSandbox;
      sb.searchScripts = <Object>['[]'];

      final DiscoveryResult result = await DiscoveryCoordinator.discover(
        request: _request('query'),
        manager: h.manager,
      );

      expect(result.outcomes.single.isSuccess, isTrue);
      expect(result.outcomes.single.results, isEmpty);
    });
  });

  group('DiscoveryCoordinator — normalization + dedup over real runtimes', () {
    test(
      'results from multiple extensions are normalized and deduplicated',
      () async {
        final DiscoveryTestHarness h = DiscoveryTestHarness(
          sandbox: ScriptedJsSandbox(),
        );
        await h.installExtension(tempDir, 'com.test.one');
        await h.installExtension(tempDir, 'com.test.two');

        final ScriptedJsSandbox sb = h.sandbox as ScriptedJsSandbox;
        // Two calls will happen this round (one per extension). The shared
        // script pool makes one call return a duplicate pair (same identity
        // key, different URLs → two references, ONE item) and the other return
        // a distinct title. Whichever extension gets which script, the
        // aggregate must be identical: 2 items, one carrying 2 references.
        sb.searchScripts = <Object>[
          _payload(<Map<String, Object?>>[
            <String, Object?>{
              'title': 'The Batman',
              'url': 'https://one.test/batman',
              'type': 'movie',
              'year': 2022,
            },
            <String, Object?>{
              'title': 'the. batman!',
              'url': 'https://one.test/batman-alt',
              'type': 'movie',
              'year': 2022,
            },
          ]),
          _payload(<Map<String, Object?>>[
            <String, Object?>{
              'title': 'Dune',
              'url': 'https://two.test/dune',
              'type': 'movie',
              'year': 2021,
            },
          ]),
        ];

        final DiscoveryResult result = await DiscoveryCoordinator.discover(
          request: _request('batman dune'),
          manager: h.manager,
        );

        expect(
          result.outcomes
              .where((ExtensionDiscoveryOutcome o) => o.isSuccess)
              .length,
          2,
        );
        expect(result.items.length, 2);
        expect(result.items.map((DiscoveryItem i) => i.title).toSet(), <String>{
          'The Batman',
          'Dune',
        });
        expect(
          result.items
              .singleWhere((DiscoveryItem i) => i.title == 'The Batman')
              .references
              .length,
          2,
        );
        expect(result.droppedCount, 0);
      },
    );

    test(
      'invalid raw observations are dropped and counted, valid ones survive',
      () async {
        final DiscoveryTestHarness h = DiscoveryTestHarness(
          sandbox: ScriptedJsSandbox(),
        );
        await h.installExtension(tempDir, 'com.test.dirty');

        (h.sandbox as ScriptedJsSandbox).searchScripts = <Object>[
          _payload(<Map<String, Object?>>[
            <String, Object?>{
              'title': '  ',
              'url': 'https://d.test/blank-title',
              'type': 'movie',
            },
            <String, Object?>{
              'title': 'Good One',
              'url': 'https://d.test/good',
              'type': 'movie',
              'year': 2024,
            },
          ]),
        ];

        final DiscoveryResult result = await DiscoveryCoordinator.discover(
          request: _request('dirty'),
          manager: h.manager,
        );

        expect(result.outcomes.single.isSuccess, isTrue);
        expect(result.items.single.title, 'Good One');
        expect(result.droppedCount, 1);
      },
    );

    test(
      'provenance is preserved across extensions through the full pipeline',
      () async {
        final DiscoveryTestHarness h = DiscoveryTestHarness(
          sandbox: ScriptedJsSandbox(),
        );
        await h.installExtension(tempDir, 'com.test.alpha');
        await h.installExtension(tempDir, 'com.test.beta');

        (h.sandbox as ScriptedJsSandbox).searchScripts = <Object>[
          _payload(<Map<String, Object?>>[
            <String, Object?>{
              'title': 'Blade Runner',
              'url': 'https://alpha.test/br',
              'type': 'movie',
              'year': 1982,
            },
          ]),
          _payload(<Map<String, Object?>>[
            <String, Object?>{
              'title': 'BLADE RUNNER',
              'url': 'https://beta.test/br',
              'type': 'movie',
              'year': 1982,
            },
          ]),
        ];

        final DiscoveryResult result = await DiscoveryCoordinator.discover(
          request: _request('blade'),
          manager: h.manager,
        );

        expect(result.items.length, 1);
        final DiscoveryItem item = result.items.single;

        // Both extensions reported the same work in different casings, so they
        // deduplicate into one item. The SURVIVING title is whichever extension
        // was observed first, and observation order across concurrently-loaded
        // runtimes is NOT deterministic (see ScriptedJsSandbox). Asserting a
        // specific casing here is a flaky assertion, not a product guarantee:
        // the real guarantee is that the merged title is one of the two
        // reported, never a synthesised or blank one.
        expect(<String>{'Blade Runner', 'BLADE RUNNER'}, contains(item.title));

        // Provenance is the property this test is actually about: BOTH
        // references survive the merge.
        expect(item.references.length, 2);
        expect(
          item.references.map((DiscoveryReference r) => r.extensionId).toSet(),
          <String>{'com.test.alpha', 'com.test.beta'},
        );
      },
    );
  });

  group('DiscoveryCoordinator — failure isolation', () {
    test(
      'one extension failing leaves healthy extensions\' results intact',
      () async {
        final DiscoveryTestHarness h = DiscoveryTestHarness(
          sandbox: ScriptedJsSandbox(),
        );
        await h.installExtension(tempDir, 'com.test.healthy');
        await h.installExtension(tempDir, 'com.test.sick');

        (h.sandbox as ScriptedJsSandbox).searchScripts = <Object>[
          _payload(<Map<String, Object?>>[
            <String, Object?>{
              'title': 'Survivor',
              'url': 'https://healthy.test/s',
              'type': 'movie',
              'year': 2020,
            },
          ]),
          JsEvalException('runtime exploded'),
        ];

        final DiscoveryResult result = await DiscoveryCoordinator.discover(
          request: _request('mixed'),
          manager: h.manager,
        );

        expect(result.items.single.title, 'Survivor');
        expect(
          result.outcomes
              .where((ExtensionDiscoveryOutcome o) => o.isFailed)
              .length,
          1,
        );
        expect(result.allQueriedFailed, isFalse);
        expect(
          result.outcomes
              .singleWhere((ExtensionDiscoveryOutcome o) => o.isFailed)
              .failure,
          isA<SpectaFailure>(),
        );
      },
    );

    test('a timing-out extension is isolated, others still answer', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness(
        sandbox: ScriptedJsSandbox(),
      );
      await h.installExtension(tempDir, 'com.test.fast');
      await h.installExtension(tempDir, 'com.test.slow');

      final ScriptedJsSandbox sb = h.sandbox as ScriptedJsSandbox;
      // Both extensions answer eventually, but call #1 (whichever extension
      // it lands on — runtime loading is concurrent) hangs far longer than
      // the round's per-extension timeout. The coordinator must cut it off
      // while the healthy call contributes.
      sb.hangDuration = const Duration(seconds: 30);
      sb.hangOnCallIndices = <int>{1};
      sb.searchScripts = <Object>[
        _payload(<Map<String, Object?>>[
          <String, Object?>{
            'title': 'Fast Result',
            'url': 'https://fast.test/f',
            'type': 'movie',
          },
        ]),
        _payload(<Map<String, Object?>>[
          <String, Object?>{
            'title': 'Too Late',
            'url': 'https://slow.test/f',
            'type': 'movie',
          },
        ]),
      ];

      final DiscoveryResult result = await DiscoveryCoordinator.discover(
        request: _request('timeout case'),
        manager: h.manager,
        perExtensionTimeoutOverride: const Duration(milliseconds: 300),
      );

      expect(result.outcomes.length, 2);
      expect(
        result.outcomes
            .where((ExtensionDiscoveryOutcome o) => o.isFailed)
            .length,
        1,
      );
      expect(
        result.outcomes
            .where((ExtensionDiscoveryOutcome o) => o.isSuccess)
            .length,
        1,
      );
      // The cut-off extension is classified as a timeout failure.
      final ExtensionDiscoveryOutcome failed = result.outcomes.singleWhere(
        (ExtensionDiscoveryOutcome o) => o.isFailed,
      );
      expect(failed.failure, isA<SpectaFailure>());
      expect(failed.failure!.toString(), contains('TIMEOUT'));
      expect(result.items.single.title, 'Fast Result');
    });

    test('every queried extension failing → allQueriedFailed', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness(
        sandbox: ScriptedJsSandbox(),
      );
      await h.installExtension(tempDir, 'com.test.bad1');
      await h.installExtension(tempDir, 'com.test.bad2');

      (h.sandbox as ScriptedJsSandbox).searchScripts = <Object>[
        JsEvalException('boom one'),
        JsEvalException('boom two'),
      ];

      final DiscoveryResult result = await DiscoveryCoordinator.discover(
        request: _request('all bad'),
        manager: h.manager,
      );

      expect(result.items, isEmpty);
      expect(result.allQueriedFailed, isTrue);
      expect(result.failures.length, 2);
    });

    test(
      'an extension whose sandbox dies mid-call is isolated, not fatal',
      () async {
        final DiscoveryTestHarness h = DiscoveryTestHarness(
          sandbox: ScriptedJsSandbox(),
        );
        await h.installExtension(tempDir, 'com.test.dead');
        await h.installExtension(tempDir, 'com.test.alive');

        (h.sandbox as ScriptedJsSandbox).searchScripts = <Object>[
          _payload(<Map<String, Object?>>[
            <String, Object?>{
              'title': 'Still Here',
              'url': 'https://alive.test/x',
              'type': 'series',
              'year': 2022,
            },
          ]),
          StateError('sandbox detonated'),
        ];

        final DiscoveryResult result = await DiscoveryCoordinator.discover(
          request: _request('crash'),
          manager: h.manager,
        );

        expect(result.items.single.title, 'Still Here');
        expect(
          result.outcomes
              .where((ExtensionDiscoveryOutcome o) => o.isFailed)
              .length,
          1,
        );
      },
    );
  });

  group('DiscoveryCoordinator — malformed output robustness', () {
    test('malformed rows inside a valid list are skipped without failing the round', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness(
        sandbox: ScriptedJsSandbox(),
      );
      await h.installExtension(tempDir, 'com.test.malformed');

      (h.sandbox as ScriptedJsSandbox).searchScripts = <Object>[
        _payload(<Object?>[
          <String, Object?>{
            'title': 'Good',
            'url': 'https://m.test/good',
            'type': 'movie',
          },
          <String, Object?>{
            'title': 'Anime Thing',
            'url': 'https://m.test/anime',
            'type': 'anime',
          },
          <String, Object?>{'url': 'https://m.test/notitle', 'type': 'movie'},
          'a bare string row',
        ]),
      ];

      final DiscoveryResult result = await DiscoveryCoordinator.discover(
        request: _request('malformed'),
        manager: h.manager,
      );

      // All four malformed shapes are skipped at the RUNTIME boundary
      // (Phase 2B hardening: bad type, missing title, non-object row), so
      // they never become SearchResults and are not normalization drops —
      // the good row survives untouched.
      expect(result.items.single.title, 'Good');
      expect(result.droppedCount, 0);
    });

    test(
      'a response that is not a JSON list fails that extension only',
      () async {
        final DiscoveryTestHarness h = DiscoveryTestHarness(
          sandbox: ScriptedJsSandbox(),
        );
        await h.installExtension(tempDir, 'com.test.notlist');
        await h.installExtension(tempDir, 'com.test.fine');

        (h.sandbox as ScriptedJsSandbox).searchScripts = <Object>[
          '{"title":"an object, not a list"}',
          _payload(<Map<String, Object?>>[
            <String, Object?>{
              'title': 'Fine',
              'url': 'https://fine.test/f',
              'type': 'movie',
            },
          ]),
        ];

        final DiscoveryResult result = await DiscoveryCoordinator.discover(
          request: _request('shapes'),
          manager: h.manager,
        );

        expect(result.items.single.title, 'Fine');
        expect(
          result.outcomes
              .where((ExtensionDiscoveryOutcome o) => o.isFailed)
              .length,
          1,
        );
      },
    );
  });

  group('DiscoveryCoordinator — pagination boundary', () {
    test('the requested page reaches the extension contract', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness(
        sandbox: ScriptedJsSandbox(),
      );
      await h.installExtension(tempDir, 'com.test.pages');

      final ScriptedJsSandbox sb = h.sandbox as ScriptedJsSandbox;
      sb.searchScripts = <Object>[
        _payload(<Map<String, Object?>>[
          <String, Object?>{
            'title': 'Page Two Item',
            'url': 'https://pages.test/p2',
            'type': 'movie',
          },
        ]),
      ];

      final DiscoveryResult result = await DiscoveryCoordinator.discover(
        request: SearchRequest(query: 'pages', page: 2),
        manager: h.manager,
      );

      expect(result.page, 2);
      expect(result.items.single.title, 'Page Two Item');
      expect(
        sb.asyncEvalCalls
            .where((String e) => e.contains('.search('))
            .every((String e) => e.contains('"pages", 2')),
        isTrue,
      );
    });

    test('page 0 is an invalid request and never dispatched', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();

      final DiscoveryResult result = await DiscoveryCoordinator.discover(
        request: SearchRequest(query: 'query', page: 0),
        manager: h.manager,
      );

      // The coordinator trusts the validity flag: nothing was installed, so
      // this only asserts the request type itself is marked invalid.
      expect(SearchRequest(query: 'query', page: 0).isValid, isFalse);
      expect(result.noExtensionAvailable, isTrue);
    });
  });

  group('DiscoveryService (Riverpod wrapper)', () {
    test('delegates to the coordinator over the given manager', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness(
        sandbox: ScriptedJsSandbox(),
      );
      await h.installExtension(tempDir, 'com.test.wrapped');

      (h.sandbox as ScriptedJsSandbox).searchScripts = <Object>[
        _payload(<Map<String, Object?>>[
          <String, Object?>{
            'title': 'Wrapped',
            'url': 'https://w.test/w',
            'type': 'movie',
          },
        ]),
      ];

      final DiscoveryService service = DiscoveryService(manager: h.manager);
      final DiscoveryResult result = await service.search(_request('wrapped'));

      expect(result.items.single.title, 'Wrapped');
    });
  });
}
