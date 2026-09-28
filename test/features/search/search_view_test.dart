import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/discovery/discovery_coordinator.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart'
    show JsEvalException;
import 'package:specta/features/search/search_state.dart';
import 'package:specta/features/search/search_view.dart';

import '../../support/discovery_test_harness.dart';

/// Pumps the search view with the discovery service overridden to a REAL
/// pipeline over the harness manager. Returns the container so tests can wait
/// on real state transitions.
Future<ProviderContainer> _pumpSearch(
  WidgetTester tester,
  DiscoveryTestHarness h,
) async {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      discoveryServiceProvider.overrideWith(
        (Ref ref) => DiscoveryService(manager: h.manager),
      ),
      // The catalogue (anime) step needs SPECTA's local database, which cannot
      // be opened in a widget test: `path_provider` is unregistered here. These
      // tests are about the SEARCH SURFACE and extension results, so the step
      // is disabled explicitly rather than left to fail. The real catalogue path
      // is covered by search_anime_integration_test.dart, which stubs the client
      // instead of the database.
      catalogueDatabaseUsableProvider.overrideWith((Ref ref) => false),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SearchView())),
    ),
  );
  // One extra pump so the initial ConsumerStatefulWidget build is complete.
  await tester.pump();
  return container;
}

/// Lets the REAL file I/O of a discovery round finish (runtimes load from
/// disk), polling until the session leaves `loading` or the bound is hit,
/// then flushes the resulting state updates and UI frames.
Future<void> _settleRound(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final Stopwatch sw = Stopwatch()..start();
  while (sw.elapsed < const Duration(seconds: 8)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    if (container.read(searchSessionProvider).status != SearchStatus.loading) {
      break;
    }
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('specta_search_ui');
    addTearDown(() async {
      // Windows can still hold the file handle for a moment after a round;
      // a failed temp cleanup must never fail a passing test.
      try {
        await tempDir.delete(recursive: true);
      } on Object catch (_) {}
    });
  });

  testWidgets('idle state shows the discovery hint', (
    WidgetTester tester,
  ) async {
    final DiscoveryTestHarness h = DiscoveryTestHarness();
    final ProviderContainer container = await _pumpSearch(tester, h);

    expect(find.text('Search across your enabled extensions'), findsOneWidget);
    expect(container.read(searchSessionProvider).status, SearchStatus.idle);
  });

  testWidgets('typing runs a discovery round and renders the unified result', (
    WidgetTester tester,
  ) async {
    final DiscoveryTestHarness h = DiscoveryTestHarness(
      sandbox: ScriptedJsSandbox(),
    );
    await tester.runAsync(() => h.installExtension(tempDir, 'com.test.ui'));
    (h.sandbox as ScriptedJsSandbox).searchScripts = <Object>[
      searchPayload(<Map<String, Object?>>[
        <String, Object?>{
          'title': 'Found It',
          'url': 'https://ui.test/1',
          'type': 'movie',
          'year': 2021,
        },
      ]),
    ];

    final ProviderContainer container = await _pumpSearch(tester, h);

    // Typing is debounced by 400 ms; advance the fake clock past it.
    await tester.enterText(find.byType(TextField), 'found');
    await tester.pump(const Duration(milliseconds: 450));

    // The round performs real file I/O; give it real time, then flush.
    await _settleRound(tester, container);

    expect(find.text('Found It'), findsOneWidget);
    expect(find.text('Movie · 2021'), findsOneWidget);
    expect(find.textContaining('Found on'), findsOneWidget);

    // D-pad/touch safety: the text field KEEPS focus after results arrive,
    // so focus is never lost or trapped by the results list.
    final TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets(
    'a total failure shows the recovery message without raw internals',
    (WidgetTester tester) async {
      final DiscoveryTestHarness h = DiscoveryTestHarness(
        sandbox: ScriptedJsSandbox(),
      );
      await tester.runAsync(
        () => h.installExtension(tempDir, 'com.test.deadui'),
      );
      (h.sandbox as ScriptedJsSandbox).searchScripts = <Object>[
        JsEvalException('secret internal detail'),
      ];

      final ProviderContainer container = await _pumpSearch(tester, h);

      await tester.enterText(find.byType(TextField), 'broken');
      await tester.pump(const Duration(milliseconds: 450));
      await _settleRound(tester, container);

      expect(find.textContaining('Search failed'), findsOneWidget);
      expect(find.textContaining('secret internal detail'), findsNothing);
      expect(find.textContaining('JsEvalException'), findsNothing);
    },
  );

  testWidgets('clearing the query returns the surface to idle', (
    WidgetTester tester,
  ) async {
    final DiscoveryTestHarness h = DiscoveryTestHarness();
    final ProviderContainer container = await _pumpSearch(tester, h);

    await tester.enterText(find.byType(TextField), 'something');
    await tester.pump(const Duration(milliseconds: 450));
    await _settleRound(tester, container);

    // No extensions installed → the round ends in the noExtensions state,
    // then clearing resets to idle.
    expect(find.textContaining('No search-capable extensions'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(find.text('Search across your enabled extensions'), findsOneWidget);
    expect(container.read(searchSessionProvider).status, SearchStatus.idle);
  });

  // Regression, found on a REAL DEVICE (C4 gate run): with no extension
  // installed the round reports `noExtensions`, and the surface used to render
  // only the install prompt — hiding anime that AniList had already returned.
  // A catalogue result is real content the user asked for, so it must render.
  testWidgets('catalogue anime renders even when no extension is installed', (
    WidgetTester tester,
  ) async {
    final DiscoveryTestHarness h = DiscoveryTestHarness();
    final ProviderContainer container = await _pumpSearch(tester, h);

    // Drive the session directly to the state a no-extension round produces.
    container
        .read(searchSessionProvider.notifier)
        .debugSetResults(
          const SearchState(
            status: SearchStatus.noExtensions,
            generation: 1,
            catalogueItems: <DiscoveryItem>[
              DiscoveryItem(
                key: 'anilist:1',
                title: 'Cowboy Bebop',
                type: MediaType.anime,
                references: <DiscoveryReference>[],
                externalIds: ExternalIds(anilistId: 1),
              ),
            ],
          ),
        );
    await tester.pump();

    expect(find.text('Cowboy Bebop'), findsOneWidget);
    expect(find.text('Anime'), findsOneWidget);
    // The install prompt must not replace real results.
    expect(find.textContaining('No search-capable extensions'), findsNothing);
    // And the card must be honest that there is no source yet.
    expect(find.textContaining('no streaming source yet'), findsOneWidget);
  });
}
