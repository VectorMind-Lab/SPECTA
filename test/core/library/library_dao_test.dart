@TestOn('vm')
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/database/specta_database.dart';
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
  }) =>
      WatchProgress(
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

  test('a second write updates in place — one row per identity', () async {
    await dao.upsert(
      progress(id: 'm', position: const Duration(seconds: 10)),
    );
    await dao.upsert(
      progress(id: 'm', position: const Duration(seconds: 40)),
    );

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

  test('continue watching excludes completed and zero-position rows, newest first',
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
  });

  test('history includes completed rows, newest first', () async {
    await dao.upsert(
      progress(id: 'a', position: const Duration(seconds: 5), updatedAt: DateTime(2026, 1, 1)),
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

  test('a duration-free row reports no fraction rather than a fake one', () async {
    await dao.upsert(progress(id: 'n', duration: null));

    final WatchProgress row = (await dao.progressFor('n'))!;
    expect(row.duration, isNull);
    expect(row.fraction, isNull);
    expect(row.remaining, isNull);
  });
}
