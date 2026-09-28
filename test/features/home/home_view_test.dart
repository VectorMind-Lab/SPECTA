import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod; it is
// exposed through the package's public `misc` surface instead.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:specta/app/navigation/specta_app_shell.dart';
import 'package:specta/core/database/database_providers.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/library/library_providers.dart';
import 'package:specta/core/settings/specta_setting_keys.dart';
import 'package:specta/features/home/foundation_status.dart';
import 'package:specta/features/home/home_feed.dart';

import '../../support/in_memory_library_store.dart';
import '../../support/in_memory_settings_store.dart';

HomeFeed _feed({required String title, int? year}) => HomeFeed(
  status: HomeFeedStatus.ready,
  items: <DiscoveryItem>[
    DiscoveryItem(
      key: 'item-key',
      title: title,
      type: MediaType.movie,
      year: year,
      references: const <DiscoveryReference>[
        DiscoveryReference(extensionId: 'com.test.a', url: 'https://x/1'),
      ],
    ),
  ],
);

Future<void> _pumpShell(
  WidgetTester tester,
  InMemorySettingsStore store, {
  required HomeFeed feed,
  TrendingFeed? trending,
}) async {
  tester.view.physicalSize = const Size(1200, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        settingsStoreProvider.overrideWith((Ref ref) => store),
        // The Home Continue Watching rail reads the persisted library; keep
        // the test hermetic with an in-memory store.
        libraryStoreProvider.overrideWith((Ref ref) => InMemoryLibraryStore()),
        // Home content comes from the real feed provider in production; the
        // widget test supplies a deterministic feed instead of installing
        // extensions.
        homeFeedProvider.overrideWith((Ref ref) async => feed),
        // The catalogue rail has its own provider; supply it deterministically
        // so these tests never reach a live metadata provider.
        trendingFeedProvider.overrideWith(
          (Ref ref) async =>
              trending ??
              const TrendingFeed(status: TrendingStatus.notConfigured),
        ),
        foundationStatusProvider.overrideWith(
          (Ref ref) async => const <FoundationStatusItem>[
            FoundationStatusItem('SQLite schema', 'v1'),
            FoundationStatusItem('Settings round trip', 'OK'),
          ],
        ),
      ],
      // The shell is normally hosted inside MaterialApp; the test host
      // supplies the same Directionality/Theme ancestry.
      child: const MaterialApp(home: SpectaAppShell()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('home renders REAL feed content, never a design fixture', (
    WidgetTester tester,
  ) async {
    await _pumpShell(
      tester,
      InMemorySettingsStore(),
      feed: _feed(title: 'A Real Feed Title', year: 1997),
    );

    // The rail is named for what it actually is.
    expect(find.text('New on SPECTA'), findsOneWidget);
    // The hero and the rail both render the item the feed returned.
    expect(find.text('A Real Feed Title'), findsWidgets);
    expect(find.text('1997'), findsWidgets);

    // The retired fixture content is gone for good.
    expect(find.text('THE LAST HORIZON'), findsNothing);
    expect(find.text('Trending Now'), findsNothing);
  });

  testWidgets('home says WHY when there is nothing to show', (
    WidgetTester tester,
  ) async {
    await _pumpShell(
      tester,
      InMemorySettingsStore(),
      feed: const HomeFeed(status: HomeFeedStatus.noExtensions),
    );

    expect(
      find.textContaining('No sources are installed yet'),
      findsOneWidget,
    );
    expect(find.text('New on SPECTA'), findsNothing);
  });

  // Regression, found on a REAL DEVICE: with zero extensions installed the Home
  // layout returned early, so the metadata-backed "Popular" rail was never
  // reached and the screen showed only the install notice. The extension feed
  // being empty must not hide content the catalogue already supplied.
  testWidgets('catalogue content still renders with zero extensions', (
    WidgetTester tester,
  ) async {
    await _pumpShell(
      tester,
      InMemorySettingsStore(),
      // Exactly what a no-extension round produces, PLUS catalogue data.
      feed: const HomeFeed(status: HomeFeedStatus.noExtensions),
      trending: const TrendingFeed(
        status: TrendingStatus.ready,
        items: <DiscoveryItem>[
          DiscoveryItem(
            key: 'anilist:1',
            title: 'Cowboy Bebop',
            type: MediaType.anime,
            year: 1998,
            references: <DiscoveryReference>[],
          ),
        ],
      ),
    );

    // The catalogue result is visible.
    expect(find.text('Cowboy Bebop'), findsOneWidget);
    // And the reason the source rail is empty is still explained, not hidden.
    expect(
      find.textContaining('No sources are installed yet'),
      findsOneWidget,
    );
  });

  testWidgets('a degraded feed is shown with a partial notice', (
    WidgetTester tester,
  ) async {
    await _pumpShell(
      tester,
      InMemorySettingsStore(),
      feed: HomeFeed(
        status: HomeFeedStatus.ready,
        items: _feed(title: 'Partial Title').items,
        failedCount: 1,
      ),
    );

    expect(find.textContaining('could not be reached'), findsOneWidget);
    expect(find.text('Partial Title'), findsWidgets);
  });

  testWidgets('diagnostics live under Settings, not on the home surface', (
    WidgetTester tester,
  ) async {
    final InMemorySettingsStore store = InMemorySettingsStore();
    await _pumpShell(tester, store, feed: _feed(title: 'Whatever'));

    // At the shell's default test size the layout family is large-screen, so
    // destinations live in the TV sidebar.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('SQLite schema'), findsOneWidget);
    expect(find.text('v1'), findsOneWidget);
    expect(find.text('Settings round trip'), findsOneWidget);
  });

  testWidgets('download concurrency control persists through Settings', (
    WidgetTester tester,
  ) async {
    final InMemorySettingsStore store = InMemorySettingsStore();
    await _pumpShell(tester, store, feed: _feed(title: 'Whatever'));

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('4'), findsOneWidget);
    expect(await store.read(SpectaSettingKeys.downloadConcurrency), '4');
  });
}
