// SPECTA — application launch-flow smoke test.
//
// Verifies the approved launch flow end to end at the widget level:
// Splash (branding, man facing the city) → Main App shell.
// Deeper widget coverage lives beside the features they exercise.

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod; it is
// exposed through the package's public `misc` surface instead.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:specta/app/specta_app.dart';
import 'package:specta/core/database/database_providers.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/library/library_providers.dart';
import 'package:specta/features/home/foundation_status.dart';
import 'package:specta/features/home/home_feed.dart';
import 'package:specta/features/splash/splash_state.dart';

import 'support/in_memory_library_store.dart';
import 'support/in_memory_settings_store.dart';

Future<void> _pumpThroughSplash(
  WidgetTester tester,
  InMemorySettingsStore store,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        settingsStoreProvider.overrideWith((Ref ref) => store),
        // Home's content and Continue Watching rail read real providers; keep
        // the launch smoke test hermetic and deterministic.
        libraryStoreProvider.overrideWith((Ref ref) => InMemoryLibraryStore()),
        homeFeedProvider.overrideWith(
          (Ref ref) async => HomeFeed(
            status: HomeFeedStatus.ready,
            items: <DiscoveryItem>[
              DiscoveryItem(
                key: 'launch-item',
                title: 'Launch Flow Title',
                type: MediaType.movie,
                year: 2026,
                references: const <DiscoveryReference>[
                  DiscoveryReference(
                    extensionId: 'com.test.a',
                    url: 'https://x/1',
                  ),
                ],
              ),
            ],
          ),
        ),
        foundationStatusProvider.overrideWith(
          (Ref ref) async => const <FoundationStatusItem>[
            FoundationStatusItem('SQLite schema', 'v1'),
            FoundationStatusItem('Settings round trip', 'OK'),
          ],
        ),
      ],
      child: const SpectaApp(),
    ),
  );

  // Fire the splash auto-transition timer (a Timer is not a frame producer,
  // so pumpAndSettle alone would stop before it fires), then settle the fade
  // into the main app shell.
  await tester.pump();
  await tester.pump(SplashState.autoTransitionDelay);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('splash branding renders first', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          settingsStoreProvider.overrideWith(
            (Ref ref) => InMemorySettingsStore(),
          ),
        ],
        child: const SpectaApp(),
      ),
    );
    await tester.pump();

    expect(find.text('SPECTA'), findsWidgets);
    expect(find.text('YOUR WORLD. YOUR CONTENT.'), findsOneWidget);
  });

  testWidgets('launch flow reaches the main app shell after the splash', (
    WidgetTester tester,
  ) async {
    final InMemorySettingsStore store = InMemorySettingsStore();
    await _pumpThroughSplash(tester, store);

    // The shell's home surface is showing, rendering the feed it was given
    // (the hero and the "New on SPECTA" rail both carry the item's title).
    expect(find.text('New on SPECTA'), findsOneWidget);
    expect(find.text('Launch Flow Title'), findsWidgets);

    // The splash recorded that the launch flow completed.
    expect(await store.read('app.hasSeenSplash'), 'true');
  });
}
