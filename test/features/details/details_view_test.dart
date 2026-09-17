import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/metadata/metadata_manager.dart';
import 'package:specta/features/details/details_state.dart';
import 'package:specta/features/details/details_view.dart';

import '../../support/discovery_test_harness.dart';

String _moviePayload(String url) => jsonEncode(<String, Object?>{
      'id': 'm1',
      'title': 'Test Movie',
      'type': 'movie',
      'url': url,
      'year': 2020,
      'description': 'A test movie description.',
      'genres': <String>['action', 'sci-fi'],
      'rating': 7.9,
      'duration': 7200,
    });

String _seriesPayload(String url) => jsonEncode(<String, Object?>{
      'id': 's1',
      'title': 'Test Series',
      'type': 'series',
      'url': url,
      'year': 2021,
      'seasons': <Map<String, Object?>>[
        <String, Object?>{
          'seasonNumber': 1,
          'title': 'Season One',
          'episodes': <Map<String, Object?>>[
            <String, Object?>{
              'episodeNumber': 1,
              'url': '$url/e1',
              'title': 'Pilot',
              'duration': 2700,
            },
            <String, Object?>{
              'episodeNumber': 2,
              'url': '$url/e2',
              'title': 'Second',
            },
          ],
        },
      ],
    });

DiscoveryItem _item(MediaType type, String extensionId, String url) =>
    DiscoveryItem(
      key: 'test|${type.code}|2020',
      title: type == MediaType.movie ? 'Test Movie' : 'Test Series',
      type: type,
      year: 2020,
      references: <DiscoveryReference>[
        DiscoveryReference(extensionId: extensionId, url: url),
      ],
    );

/// Installs the extension, scripts the details payload, opens the item
/// through the real session notifier, and pumps the details view — all real
/// I/O inside [WidgetTester.runAsync] (fake-async cannot drive file I/O).
Future<ProviderContainer> _openAndPump(
  WidgetTester tester,
  DiscoveryTestHarness h,
  MediaType type,
  String extensionId,
  String url,
  String payload,
) async {
  await tester.runAsync(
    () => h.installExtension(tempDirHolder!, extensionId,
        capabilities: 'search,details'),
  );
  h.sandbox.setAsyncResult(
    'JSON.stringify(await _spectaInstance.details("$url"))',
    payload,
  );

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      metadataServiceProvider.overrideWith(
        (Ref ref) => MetadataService(manager: h.manager),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.runAsync(
    () => container
        .read(detailsSessionProvider.notifier)
        .open(_item(type, extensionId, url)),
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DetailsView()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

/// Set by setUp; read by [_openAndPump] (test-scoped temp directory).
Directory? tempDirHolder;

void main() {
  setUp(() async {
    tempDirHolder = await Directory.systemTemp.createTemp('specta_details_ui');
    addTearDown(() async {
      // Windows can hold file handles briefly; cleanup must never fail a
      // passing test.
      try {
        await tempDirHolder!.delete(recursive: true);
      } on Object catch (_) {}
    });
  });

  group('DetailsView — movie', () {
    testWidgets('renders canonical metadata for a movie', (tester) async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      const String url = 'https://example.com/movie/1';

      await _openAndPump(tester, h, MediaType.movie, 'extA', url,
          _moviePayload(url));

      expect(find.text('Test Movie'), findsWidgets);
      expect(find.textContaining('Movie'), findsWidgets);
      expect(find.textContaining('2020'), findsWidgets);
      expect(
          find.textContaining('A test movie description.'), findsOneWidget);
      expect(find.text('action'), findsOneWidget);
      expect(find.text('sci-fi'), findsOneWidget);
    });

    testWidgets('renders seasons and episodes for a series', (tester) async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      const String url = 'https://example.com/series/1';

      await _openAndPump(tester, h, MediaType.series, 'extA', url,
          _seriesPayload(url));

      expect(find.text('Seasons (1)'), findsOneWidget);
      expect(find.text('Season One'), findsOneWidget);

      // Expand the season card to see episodes.
      await tester.tap(find.text('Season One'));
      await tester.pumpAndSettle();
      expect(find.text('Pilot'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
    });
  });

  group('DetailsView — failure and retry', () {
    testWidgets('shows an honest failure state and offers retry',
        (tester) async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      const String url = 'https://example.com/movie/1';

      final ProviderContainer container = await _openAndPump(
        tester,
        h,
        MediaType.movie,
        'extA',
        url,
        '', // empty payload string + error script below → failure path
      );
      // The helper scripted a payload; override with an error for this test.
      h.sandbox.setAsyncError(
        'JSON.stringify(await _spectaInstance.details("$url"))',
        'down',
      );

      // Re-open through the real notifier to hit the failure path.
      await tester.runAsync(
        () => container
            .read(detailsSessionProvider.notifier)
            .open(_item(MediaType.movie, 'extA', url)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('could not be loaded'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('retry succeeds once the extension is healthy again',
        (tester) async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      const String url = 'https://example.com/movie/1';

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          metadataServiceProvider.overrideWith(
            (Ref ref) => MetadataService(manager: h.manager),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.runAsync(
        () => h.installExtension(tempDirHolder!, 'extA',
            capabilities: 'search,details'),
      );
      h.sandbox.setAsyncError(
        'JSON.stringify(await _spectaInstance.details("$url"))',
        'down',
      );
      await tester.runAsync(
        () => container
            .read(detailsSessionProvider.notifier)
            .open(_item(MediaType.movie, 'extA', url)),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DetailsView()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('could not be loaded'), findsOneWidget);

      // Healthy again: script a valid payload and retry through the UI.
      h.sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.details("$url"))',
        _moviePayload(url),
      );
      await tester.tap(find.text('Retry'));
      await tester.pump(const Duration(milliseconds: 100));
      // Let the real I/O of the retried request finish.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Test Movie'), findsWidgets);
    });
  });

  group('DetailsView — TV focus', () {
    testWidgets('back button is present and season cards are tappable',
        (tester) async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      const String url = 'https://example.com/series/1';

      await _openAndPump(tester, h, MediaType.series, 'extA', url,
          _seriesPayload(url));

      expect(find.byType(BackButton), findsOneWidget);
      // The season card responds to activation (D-pad select routes to tap).
      await tester.tap(find.text('Season One'));
      await tester.pumpAndSettle();
      expect(find.text('Pilot'), findsOneWidget);
    });
  });
}
