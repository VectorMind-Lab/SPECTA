@TestOn('vm')
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/library/library_dao.dart';
import 'package:specta/core/library/watch_progress.dart';

void main() {
  late SpectaDatabase database;
  late LibraryDao dao;

  setUp(() {
    database = SpectaDatabase(NativeDatabase.memory());
    dao = LibraryDao(database);
  });

  tearDown(() => database.close());

  WatchProgress progress({
    required String id,
    String mediaKey = 'movie|movie|2024',
    MediaType type = MediaType.movie,
    String title = 'A Movie',
    String? subtitleLine,
    int? season,
    int? episode,
    Duration position = const Duration(seconds: 10),
    Duration? duration = const Duration(minutes: 2),
    Duration elapsed = const Duration(seconds: 12),
    bool completed = false,
    DateTime? updatedAt,
  }) => WatchProgress(
    id: id,
    mediaKey: mediaKey,
    mediaType: type,
    title: title,
    subtitleLine: subtitleLine,
    seasonNumber: season,
    episodeNumber: episode,
    position: position,
    duration: duration,
    elapsed: elapsed,
    completed: completed,
    updatedAt: updatedAt ?? DateTime(2026, 1, 1),
  );

  test('stores and reads one identity back', () async {
    await dao.upsert(progress(id: 'Movie|movie|2024', title: 'Movie'));

    final WatchProgress? row = await dao.progressFor('Movie|movie|2024');
    expect(row, isNotNull);
    expect(row!.title, 'Movie');
    expect(row.mediaType, MediaType.movie);
    expect(row.position, const Duration(seconds: 10));
    expect(row.duration, const Duration(minutes: 2));
    expect(row.completed, isFalse);
    expect(row.fraction, closeTo(10 / 120, 0.0001));
  });

  test('anime progress round-trips canonical identity', () async {
    await dao.upsert(
      WatchProgress(
        id: 'anilist:16498',
        mediaKey: 'anilist:16498',
        mediaType: MediaType.anime,
        title: 'Spirited Away',
        canonicalId: 'anilist:16498',
        identityVersion: 2,
        position: const Duration(seconds: 12),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );

    final WatchProgress? read = await dao.progressFor('anilist:16498');
    expect(read!.canonicalId, 'anilist:16498');
    expect(read.identityVersion, 2);
    expect(read.mediaType, MediaType.anime);
  });

  test('a second write updates in place — one row per identity', () async {
    await dao.upsert(progress(id: 'm', position: const Duration(seconds: 10)));
    await dao.upsert(progress(id: 'm', position: const Duration(seconds: 40)));

    final List<WatchProgress> all = await dao.history();
    expect(all.length, 1);
    expect(all.single.position, const Duration(seconds: 40));
  });

  test('episode identities never collide (s1e1 vs s1e2)', () async {
    await dao.upsert(
      progress(
        id: 'Show|series|2024|s1e1',
        title: 'Show',
        type: MediaType.series,
        subtitleLine: 'Season 1 · Episode 1',
        season: 1,
        episode: 1,
        position: const Duration(seconds: 5),
      ),
    );
    await dao.upsert(
      progress(
        id: 'Show|series|2024|s1e2',
        title: 'Show',
        type: MediaType.series,
        subtitleLine: 'Season 1 · Episode 2',
        season: 1,
        episode: 2,
        position: const Duration(seconds: 90),
        completed: true,
      ),
    );

    final WatchProgress? ep1 = await dao.progressFor('Show|series|2024|s1e1');
    final WatchProgress? ep2 = await dao.progressFor('Show|series|2024|s1e2');

    expect(ep1!.position, const Duration(seconds: 5));
    expect(ep1.completed, isFalse);
    expect(ep2!.position, const Duration(seconds: 90));
    expect(ep2.completed, isTrue);
    expect(ep1.episodeNumber, 1);
    expect(ep2.episodeNumber, 2);
  });

  test(
    'continue watching excludes completed and zero-position rows, newest first',
    () async {
      await dao.upsert(
        progress(
          id: 'old',
          position: const Duration(seconds: 30),
          updatedAt: DateTime(2026, 1, 1),
        ),
      );
      await dao.upsert(
        progress(
          id: 'fresh',
          position: const Duration(seconds: 40),
          updatedAt: DateTime(2026, 2, 1),
        ),
      );
      await dao.upsert(
        progress(
          id: 'done',
          position: const Duration(seconds: 120),
          completed: true,
          updatedAt: DateTime(2026, 3, 1),
        ),
      );
      await dao.upsert(
        progress(
          id: 'opened-but-not-started',
          position: Duration.zero,
          updatedAt: DateTime(2026, 4, 1),
        ),
      );

      final List<WatchProgress> cw = await dao.continueWatching();
      expect(cw.map((WatchProgress p) => p.id), <String>['fresh', 'old']);
    },
  );

  test('history includes completed rows, newest first', () async {
    await dao.upsert(
      progress(
        id: 'a',
        position: const Duration(seconds: 5),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    await dao.upsert(
      progress(
        id: 'b',
        position: const Duration(seconds: 120),
        completed: true,
        updatedAt: DateTime(2026, 2, 1),
      ),
    );

    final List<WatchProgress> all = await dao.history();
    expect(all.map((WatchProgress p) => p.id), <String>['b', 'a']);
    expect(all.first.completed, isTrue);
  });

  test('remove deletes one identity; clear empties the table', () async {
    await dao.upsert(progress(id: 'a'));
    await dao.upsert(progress(id: 'b'));

    await dao.remove('a');
    expect(await dao.progressFor('a'), isNull);
    expect(await dao.progressFor('b'), isNotNull);

    await dao.clear();
    expect(await dao.history(), isEmpty);
  });

  test(
    'a duration-free row reports no fraction rather than a fake one',
    () async {
      await dao.upsert(progress(id: 'n', duration: null));

      final WatchProgress row = (await dao.progressFor('n'))!;
      expect(row.duration, isNull);
      expect(row.fraction, isNull);
      expect(row.remaining, isNull);
    },
  );

  group('durable resume provenance (media_references)', () {
    test('stores references in first-seen order', () async {
      await dao.saveReferences('show|series|2020', const <DiscoveryReference>[
        DiscoveryReference(extensionId: 'extA', url: 'https://a/show'),
        DiscoveryReference(extensionId: 'extB', url: 'https://b/show'),
      ]);

      final List<DiscoveryReference> refs = await dao.referencesFor(
        'show|series|2020',
      );
      expect(refs.length, 2);
      expect(refs[0].extensionId, 'extA');
      expect(refs[0].url, 'https://a/show');
      expect(refs[1].extensionId, 'extB');
    });

    test('saving again REPLACES rather than appends', () async {
      await dao.saveReferences('m|movie|2020', const <DiscoveryReference>[
        DiscoveryReference(extensionId: 'extA', url: 'https://a/one'),
        DiscoveryReference(extensionId: 'extB', url: 'https://b/one'),
      ]);
      await dao.saveReferences('m|movie|2020', const <DiscoveryReference>[
        DiscoveryReference(extensionId: 'extC', url: 'https://c/two'),
      ]);

      final List<DiscoveryReference> refs = await dao.referencesFor(
        'm|movie|2020',
      );
      expect(refs.length, 1);
      expect(refs.single.extensionId, 'extC');
    });

    test('references are kept per media key', () async {
      await dao.saveReferences('a|movie|2020', const <DiscoveryReference>[
        DiscoveryReference(extensionId: 'extA', url: 'https://a/x'),
      ]);
      await dao.saveReferences('b|movie|2021', const <DiscoveryReference>[
        DiscoveryReference(extensionId: 'extB', url: 'https://b/y'),
      ]);

      expect(
        (await dao.referencesFor('a|movie|2020')).single.url,
        'https://a/x',
      );
      expect(
        (await dao.referencesFor('b|movie|2021')).single.url,
        'https://b/y',
      );
    });

    test('an unknown key has no references', () async {
      expect(await dao.referencesFor('never|movie|2020'), isEmpty);
    });
  });
}
