import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/discovery/discovery_coordinator.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart'
    show JsEvalException;
import 'package:specta/features/search/search_state.dart';

import '../../support/discovery_test_harness.dart';

/// Builds a JSON search-result payload.
String _payload(String title, String url) =>
    searchPayload(<Map<String, Object?>>[
      <String, Object?>{
        'title': title,
        'url': url,
        'type': 'movie',
        'year': 2020,
      },
    ]);

/// Polls until [test] holds or [timeout] elapses (then fails the test).
Future<void> _waitFor(
  bool Function() test, {
  String reason = 'condition not met in time',
}) async {
  final Stopwatch sw = Stopwatch()..start();
  while (!test()) {
    if (sw.elapsed > const Duration(seconds: 5)) {
      fail(reason);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

ProviderContainer _container(DiscoveryTestHarness h) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      discoveryServiceProvider.overrideWith(
        (Ref ref) => DiscoveryService(manager: h.manager),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('specta_search_state');
    addTearDown(() => tempDir.delete(recursive: true));
  });

  group('SearchSessionNotifier — statuses', () {
    test('starts idle', () {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      final ProviderContainer container = _container(h);

      expect(container.read(searchSessionProvider).status, SearchStatus.idle);
    });

    test('a blank query never starts a round', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      final ProviderContainer container = _container(h);

      await container.read(searchSessionProvider.notifier).submit('   \t  ');

      expect(container.read(searchSessionProvider).status, SearchStatus.idle);
    });

    test('successful round with results → results status', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness(
        sandbox: ScriptedJsSandbox(),
      );
      await h.installExtension(tempDir, 'com.test.found');

      (h.sandbox as ScriptedJsSandbox).searchScripts = <Object>[
        _payload('Found It', 'https://f.test/1'),
      ];

      final ProviderContainer container = _container(h);
      await container.read(searchSessionProvider.notifier).submit('found');

      final SearchState state = container.read(searchSessionProvider);
      expect(state.status, SearchStatus.results);
      expect(state.items.single.title, 'Found It');
      expect(state.page, 1);
    });

    test(
      'queried extensions answering honestly empty → empty status',
      () async {
        final DiscoveryTestHarness h = DiscoveryTestHarness(
          sandbox: ScriptedJsSandbox(),
        );
        await h.installExtension(tempDir, 'com.test.nothing');

        (h.sandbox as ScriptedJsSandbox).searchScripts = <Object>['[]'];

        final ProviderContainer container = _container(h);
        await container.read(searchSessionProvider.notifier).submit('nothing');

        final SearchState state = container.read(searchSessionProvider);
        expect(state.status, SearchStatus.empty);
        expect(state.items, isEmpty);
        expect(state.failedExtensions, isEmpty);
      },
    );

    test('every queried extension failing → allFailed status', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness(
        sandbox: ScriptedJsSandbox(),
      );
      await h.installExtension(tempDir, 'com.test.bad1');
      await h.installExtension(tempDir, 'com.test.bad2');

      (h.sandbox as ScriptedJsSandbox).searchScripts = <Object>[
        JsEvalException('boom'),
        JsEvalException('bam'),
      ];

      final ProviderContainer container = _container(h);
      await container.read(searchSessionProvider.notifier).submit('broken');

      final SearchState state = container.read(searchSessionProvider);
      expect(state.status, SearchStatus.allFailed);
      expect(state.items, isEmpty);
      expect(state.failedExtensions.length, 2);
    });

    test('results plus a failing extension → partialFailure status', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness(
        sandbox: ScriptedJsSandbox(),
      );
      await h.installExtension(tempDir, 'com.test.ok');
      await h.installExtension(tempDir, 'com.test.err');

      (h.sandbox as ScriptedJsSandbox).searchScripts = <Object>[
        _payload('Partial Winner', 'https://ok.test/1'),
        JsEvalException('exploded'),
      ];

      final ProviderContainer container = _container(h);
      await container.read(searchSessionProvider.notifier).submit('partial');

      final SearchState state = container.read(searchSessionProvider);
      expect(state.status, SearchStatus.partialFailure);
      expect(state.items.single.title, 'Partial Winner');
      expect(state.failedExtensions.length, 1);
    });

    test('a success with zero items plus a failing extension is partialFailure too', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness(
        sandbox: ScriptedJsSandbox(),
      );
      await h.installExtension(tempDir, 'com.test.emptyok');
      await h.installExtension(tempDir, 'com.test.err2');

      (h.sandbox as ScriptedJsSandbox).searchScripts = <Object>[
        '[]',
        JsEvalException('exploded'),
      ];

      final ProviderContainer container = _container(h);
      await container.read(searchSessionProvider.notifier).submit('emptyfail');

      expect(
        container.read(searchSessionProvider).status,
        SearchStatus.partialFailure,
      );
    });

    test(
      'no search-capable extension installed → noExtensions status',
      () async {
        final DiscoveryTestHarness h = DiscoveryTestHarness();
        final ProviderContainer container = _container(h);

        await container.read(searchSessionProvider.notifier).submit('anything');

        expect(
          container.read(searchSessionProvider).status,
          SearchStatus.noExtensions,
        );
      },
    );

    test('loading is visible while a round is in flight', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness(
        sandbox: ScriptedJsSandbox(),
      );
      await h.installExtension(tempDir, 'com.test.slowish');

      final ScriptedJsSandbox sb = h.sandbox as ScriptedJsSandbox;
      sb.hangDuration = const Duration(milliseconds: 400);
      sb.hangOnCallIndices = <int>{0};
      sb.searchScripts = <Object>[_payload('Slow Winner', 'https://s.test/1')];

      final ProviderContainer container = _container(h);
      final Future<void> round = container
          .read(searchSessionProvider.notifier)
          .submit('slowish');

      await _waitFor(
        () =>
            container.read(searchSessionProvider).status ==
            SearchStatus.loading,
        reason: 'round never entered loading',
      );

      await round;
      expect(
        container.read(searchSessionProvider).status,
        SearchStatus.results,
      );
    });
  });

  group('SearchSessionNotifier — race protection', () {
    test('an older round completing after a newer one is rejected ("bat"→"batman")', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness(
        sandbox: ScriptedJsSandbox(),
      );
      await h.installExtension(tempDir, 'com.test.racy');

      final ScriptedJsSandbox sb = h.sandbox as ScriptedJsSandbox;
      // Call #0 (the first query) hangs, call #1 (the newer query) answers
      // immediately. The older round must NEVER overwrite the newer result.
      sb.hangDuration = const Duration(seconds: 2);
      sb.hangOnCallIndices = <int>{0};
      sb.searchScripts = <Object>[
        _payload('Stale Result', 'https://r.test/stale'),
        _payload('Fresh Result', 'https://r.test/fresh'),
      ];

      final ProviderContainer container = _container(h);
      final SearchSessionNotifier notifier = container.read(
        searchSessionProvider.notifier,
      );

      final Future<void> older = notifier.submit('bat');
      await _waitFor(
        () => sb.searchCallCount >= 1,
        reason: 'first round never reached the sandbox',
      );

      final Future<void> newer = notifier.submit('batman');
      await newer;
      expect(
        container.read(searchSessionProvider).items.single.title,
        'Fresh Result',
      );

      await older; // the stale round lands LAST
      expect(
        container.read(searchSessionProvider).items.single.title,
        'Fresh Result',
        reason: 'a stale round must not overwrite a newer one',
      );
      expect(
        container.read(searchSessionProvider).status,
        SearchStatus.results,
      );
    });

    test('reset rejects an in-flight round', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness(
        sandbox: ScriptedJsSandbox(),
      );
      await h.installExtension(tempDir, 'com.test.reset');

      final ScriptedJsSandbox sb = h.sandbox as ScriptedJsSandbox;
      sb.hangDuration = const Duration(milliseconds: 500);
      sb.hangOnCallIndices = <int>{0};
      sb.searchScripts = <Object>[
        _payload('Late Arrival', 'https://r.test/late'),
      ];

      final ProviderContainer container = _container(h);
      final Future<void> round = container
          .read(searchSessionProvider.notifier)
          .submit('reset-me');

      await _waitFor(
        () => sb.searchCallCount >= 1,
        reason: 'round never reached the sandbox',
      );
      container.read(searchSessionProvider.notifier).reset();
      expect(container.read(searchSessionProvider).status, SearchStatus.idle);

      await round;
      expect(
        container.read(searchSessionProvider).status,
        SearchStatus.idle,
        reason: 'the rejected round must not resurrect results after a reset',
      );
    });
  });

  group('SearchSessionNotifier — pagination boundary', () {
    test('a later page round reports its page', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness(
        sandbox: ScriptedJsSandbox(),
      );
      await h.installExtension(tempDir, 'com.test.page2');

      (h.sandbox as ScriptedJsSandbox).searchScripts = <Object>[
        _payload('Page Two', 'https://p.test/2'),
      ];

      final ProviderContainer container = _container(h);
      await container
          .read(searchSessionProvider.notifier)
          .submit('pages', page: 2);

      final SearchState state = container.read(searchSessionProvider);
      expect(state.page, 2);
      expect(state.items.single.title, 'Page Two');
    });
  });
}
