import 'dart:convert';
import 'dart:io';

import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/metadata/metadata_manager.dart';
import 'package:specta/core/metadata/metadata_models.dart';
import 'package:flutter_test/flutter_test.dart' as t;

import '../../support/discovery_test_harness.dart';

/// A movie [DiscoveryItem] with a single reference.
DiscoveryItem movieItem(String extensionId, String url) => DiscoveryItem(
      key: 'test|movie|2020',
      title: 'Test Movie',
      type: MediaType.movie,
      year: 2020,
      references: <DiscoveryReference>[
        DiscoveryReference(extensionId: extensionId, url: url),
      ],
    );

/// A series [DiscoveryItem] with a single reference.
DiscoveryItem seriesItem(String extensionId, String url) => DiscoveryItem(
      key: 'test|series|2021',
      title: 'Test Series',
      type: MediaType.series,
      year: 2021,
      references: <DiscoveryReference>[
        DiscoveryReference(extensionId: extensionId, url: url),
      ],
    );

/// A valid movie details payload.
Map<String, Object?> moviePayload(String url) => <String, Object?>{
      'id': 'm1',
      'title': 'Test Movie',
      'type': 'movie',
      'url': url,
      'year': 2020,
      'description': 'A test movie.',
      'genres': <String>['action', 'sci-fi'],
      'rating': 7.9,
      'duration': 7200,
      'cover': 'https://example.com/cover.jpg',
      'backdrop': 'https://example.com/backdrop.jpg',
    };

/// A valid series details payload with one season and two episodes.
Map<String, Object?> seriesPayload(String url) => <String, Object?>{
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
              'episodeNumber': 2,
              'url': '$url/e2',
              'title': 'Second',
            },
            <String, Object?>{
              'episodeNumber': 1,
              'url': '$url/e1',
              'title': 'Pilot',
              'duration': 2700,
            },
          ],
        },
      ],
    };

void main() {
  late Directory tempDir;

  t.setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('specta_metadata_mgr');
    t.addTearDown(() => tempDir.delete(recursive: true));
  });

  t.group('MetadataManager — movie metadata', () {
    t.test('builds a canonical item from a valid payload', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,details');
      const String url = 'https://example.com/movie/1';
      h.sandbox.setAsyncResult(detailsExpression(url), jsonEncode(moviePayload(url)));

      final MetadataResult result = await MetadataManager.metadataFor(
        item: movieItem('extA', url),
        manager: h.manager,
      );

      t.expect(result.hasItem, t.isTrue);
      final MetadataItem item = result.item!;
      t.expect(item.title, 'Test Movie');
      t.expect(item.type, MediaType.movie);
      t.expect(item.year, 2020);
      t.expect(item.cover, 'https://example.com/cover.jpg');
      t.expect(item.backdrop, 'https://example.com/backdrop.jpg');
      t.expect(item.details, t.hasLength(1));
      t.expect(item.details.single.extensionId, 'extA');
      t.expect(item.details.single.referenceUrl, url);
      t.expect(item.details.single.rating, 7.9);
      t.expect(item.details.single.genres, <String>['action', 'sci-fi']);
      t.expect(item.seasons, t.isEmpty);
    });

    t.test('a timeout on the only reference produces failure data, not a throw',
        () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,details');
      const String url = 'https://example.com/movie/1';
      h.sandbox.setAsyncResult(
        detailsExpression(url),
        jsonEncode(moviePayload(url)),
      );
      h.sandbox.delay = const Duration(seconds: 2);

      final MetadataResult result = await MetadataManager.metadataFor(
        item: movieItem('extA', url),
        manager: h.manager,
        perReferenceTimeoutOverride: const Duration(milliseconds: 50),
      );

      t.expect(result.hasItem, t.isFalse);
      t.expect(result.outcomes.single.isFailed, t.isTrue);
    });

    t.test('a runtime error on the only reference is isolated as data',
        () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,details');
      const String url = 'https://example.com/movie/1';
      h.sandbox.setAsyncError(detailsExpression(url), 'extension exploded');

      final MetadataResult result = await MetadataManager.metadataFor(
        item: movieItem('extA', url),
        manager: h.manager,
      );

      t.expect(result.hasItem, t.isFalse);
      t.expect(result.outcomes.single.isFailed, t.isTrue);
    });

    t.test('an extension without the details capability is skipped, not failed',
        () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,latest');
      const String url = 'https://example.com/movie/1';

      final MetadataResult result = await MetadataManager.metadataFor(
        item: movieItem('extA', url),
        manager: h.manager,
      );

      t.expect(result.hasItem, t.isFalse);
      t.expect(result.outcomes.single.isSuccess, t.isFalse);
      t.expect(result.outcomes.single.isFailed, t.isFalse);
    });

    t.test('an invalid payload (type mismatch) is reported as invalid data',
        () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,details');
      const String url = 'https://example.com/movie/1';
      // A movie request answered by a series payload.
      h.sandbox.setAsyncResult(
        detailsExpression(url),
        jsonEncode(seriesPayload(url)),
      );

      final MetadataResult result = await MetadataManager.metadataFor(
        item: movieItem('extA', url),
        manager: h.manager,
      );

      t.expect(result.hasItem, t.isFalse);
      t.expect(result.outcomes.single.isInvalid, t.isTrue);
      t.expect(result.outcomes.single.dropReason, t.contains('type'));
    });
  });

  t.group('MetadataManager — series, seasons, episodes', () {
    t.test('seasons and episodes are canonicalized, sorted, and complete',
        () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,details');
      const String url = 'https://example.com/series/1';
      h.sandbox.setAsyncResult(
        detailsExpression(url),
        jsonEncode(seriesPayload(url)),
      );

      final MetadataResult result = await MetadataManager.metadataFor(
        item: seriesItem('extA', url),
        manager: h.manager,
      );

      t.expect(result.hasItem, t.isTrue);
      final List<SeriesSeason> seasons = result.item!.seasons;
      t.expect(seasons, t.hasLength(1));
      t.expect(seasons.single.seasonNumber, 1);
      // Episodes arrive 2,1 from the payload; SPECTA canonically sorts.
      t.expect(seasons.single.episodes.map((SeriesEpisode e) => e.episodeNumber),
          <int>[1, 2]);
      t.expect(seasons.single.episodes.first.referenceUrl, '$url/e1');
      t.expect(seasons.single.episodes.first.durationSeconds, 2700);
    });

    t.test('an empty season list is a partial-success series, not a failure',
        () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,details');
      const String url = 'https://example.com/series/1';
      final Map<String, Object?> payload = seriesPayload(url)
        ..['seasons'] = <Object?>[];

      h.sandbox.setAsyncResult(detailsExpression(url), jsonEncode(payload));

      final MetadataResult result = await MetadataManager.metadataFor(
        item: seriesItem('extA', url),
        manager: h.manager,
      );

      t.expect(result.hasItem, t.isTrue);
      t.expect(result.item!.seasons, t.isEmpty);
    });
  });

  t.group('MetadataManager — multi-reference provenance', () {
    t.test('two references both contribute; provenance is preserved', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,details');
      await h.installExtension(tempDir, 'extB', capabilities: 'search,details');

      const String urlA = 'https://example.com/a/movie/1';
      const String urlB = 'https://example.com/b/movie/1';

      // Both extensions answer for the same work.
      final Map<String, Object?> payloadA = moviePayload(urlA)
        ..['title'] = 'Test Movie';
      final Map<String, Object?> payloadB = moviePayload(urlB)
        ..['title'] = 'Test Movie'
        ..['rating'] = 8.5;

      h.sandbox.setAsyncResult(detailsExpression(urlA), jsonEncode(payloadA));
      h.sandbox.setAsyncResult(detailsExpression(urlB), jsonEncode(payloadB));

      final DiscoveryItem item = DiscoveryItem(
        key: 'test movie|movie|2020',
        title: 'Test Movie',
        type: MediaType.movie,
        year: 2020,
        references: <DiscoveryReference>[
          const DiscoveryReference(extensionId: 'extA', url: urlA),
          const DiscoveryReference(extensionId: 'extB', url: urlB),
        ],
      );

      final MetadataResult result = await MetadataManager.metadataFor(
        item: item,
        manager: h.manager,
      );

      t.expect(result.hasItem, t.isTrue);
      t.expect(result.item!.details, t.hasLength(2));
      t.expect(result.item!.isCrossReference, t.isTrue);
      t.expect(
        result.item!.details.map((ReferenceMetadata r) => r.extensionId),
        t.containsAllInOrder(<String>['extA', 'extB']),
      );
      t.expect(result.outcomes.every((ReferenceOutcome o) => o.isSuccess),
          t.isTrue);
    });

    t.test('one reference failing does not stop the healthy reference',
        () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,details');
      await h.installExtension(tempDir, 'extB', capabilities: 'search,details');

      const String urlA = 'https://example.com/a/movie/1';
      const String urlB = 'https://example.com/b/movie/1';

      h.sandbox.setAsyncError(detailsExpression(urlA), 'extA is down');
      h.sandbox.setAsyncResult(
        detailsExpression(urlB),
        jsonEncode(moviePayload(urlB)),
      );

      final DiscoveryItem item = DiscoveryItem(
        key: 'test movie|movie|2020',
        title: 'Test Movie',
        type: MediaType.movie,
        year: 2020,
        references: <DiscoveryReference>[
          const DiscoveryReference(extensionId: 'extA', url: urlA),
          const DiscoveryReference(extensionId: 'extB', url: urlB),
        ],
      );

      final MetadataResult result = await MetadataManager.metadataFor(
        item: item,
        manager: h.manager,
      );

      t.expect(result.hasItem, t.isTrue);
      t.expect(result.item!.details, t.hasLength(1));
      t.expect(result.item!.details.single.extensionId, 'extB');
      t.expect(result.outcomes, t.hasLength(2));
      t.expect(
        result.outcomes.where((ReferenceOutcome o) => o.isFailed).length,
        1,
      );
    });

    t.test('when every reference fails there is no canonical item', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,details');
      await h.installExtension(tempDir, 'extB', capabilities: 'search,details');

      h.sandbox.setAsyncError(
        detailsExpression('https://example.com/a/movie/1'),
        'down',
      );
      h.sandbox.setAsyncError(
        detailsExpression('https://example.com/b/movie/1'),
        'down',
      );

      final DiscoveryItem item = DiscoveryItem(
        key: 'test movie|movie|2020',
        title: 'Test Movie',
        type: MediaType.movie,
        year: 2020,
        references: <DiscoveryReference>[
          const DiscoveryReference(
            extensionId: 'extA',
            url: 'https://example.com/a/movie/1',
          ),
          const DiscoveryReference(
            extensionId: 'extB',
            url: 'https://example.com/b/movie/1',
          ),
        ],
      );

      final MetadataResult result = await MetadataManager.metadataFor(
        item: item,
        manager: h.manager,
      );

      t.expect(result.hasItem, t.isFalse);
      t.expect(result.outcomes.every((ReferenceOutcome o) => o.isFailed),
          t.isTrue);
    });
  });

  t.group('MetadataManager — identity key', () {
    t.test('identity agrees with the discovery evidence key', () {
      t.expect(
        MetadataManager.identityKey(
          normalizedTitle: 'the batman',
          type: MediaType.movie,
          year: 2022,
        ),
        'the batman|movie|2022',
      );
      t.expect(
        MetadataManager.identityKey(
          normalizedTitle: 'the batman',
          type: MediaType.movie,
          year: null,
        ),
        'the batman|movie|none',
      );
    });
  });
}

/// The exact JS expression the runtime issues for a details call.
String detailsExpression(String url) =>
    'JSON.stringify(await _spectaInstance.details("$url"))';
