@TestOn('vm')
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/downloads/download_dao.dart';
import 'package:specta/core/downloads/download_models.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/contract/result_models.dart';

// The DAO is exercised against the real generated Drift schema (in-memory
// executor), so the downloads table, its columns and its primary key are the
// ones the migration and the fresh-install paths actually produce.
void main() {
  group('DownloadDao', () {
    late SpectaDatabase db;
    late DownloadDao dao;

    setUp(() {
      db = SpectaDatabase(NativeDatabase.memory());
      dao = DownloadDao(db);
    });

    tearDown(() => db.close());

    DownloadRecord record(
      String id, {
      String mediaKey = 'Movie|movie|2024',
      MediaType mediaType = MediaType.movie,
      DownloadStatus status = DownloadStatus.queued,
      int bytesDownloaded = 0,
      int? totalBytes,
      DownloadFailure? failure,
      int attempt = 0,
      DateTime? createdAt,
      int? seasonNumber,
      int? episodeNumber,
    }) => DownloadRecord(
      id: id,
      mediaKey: mediaKey,
      mediaType: mediaType,
      title: 'Movie',
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      status: status,
      bytesDownloaded: bytesDownloaded,
      totalBytes: totalBytes,
      filePath: '/data/media/Movie (x).mp4',
      attempt: attempt,
      failure: failure,
      createdAt: createdAt ?? DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 2),
    );

    test('upsert then read back round-trips every persisted field', () async {
      final DownloadFailure failure = DownloadFailure(
        type: DownloadFailureType.serverError,
        message: 'The server had a problem while serving the file.',
        detail: '503 after 4 attempts',
      );
      final DownloadRecord original = record(
        'Movie|movie|2024',
        status: DownloadStatus.failed,
        bytesDownloaded: 2048,
        totalBytes: 8192,
        failure: failure,
        attempt: 3,
      );

      await dao.upsert(original);
      final DownloadRecord? read = await dao.recordFor(original.id);

      expect(read, isNotNull);
      expect(read!.id, original.id);
      expect(read.mediaKey, original.mediaKey);
      expect(read.mediaType, original.mediaType);
      expect(read.title, original.title);
      expect(read.status, DownloadStatus.failed);
      expect(read.bytesDownloaded, 2048);
      expect(read.totalBytes, 8192);
      expect(read.filePath, original.filePath);
      expect(read.attempt, 3);
      expect(read.failure, isNotNull);
      expect(read.failure!.type, DownloadFailureType.serverError);
      expect(read.failure!.message, failure.message);
      expect(read.failure!.isRetryable, isTrue);
      expect(read.createdAt, original.createdAt);
      expect(read.updatedAt, original.updatedAt);
      expect(read.completedAt, isNull);
    });

    test('anime download round-trips canonical identity', () async {
      final DownloadRecord anime = record(
        'anilist:16498',
        mediaKey: 'anilist:16498',
        mediaType: MediaType.anime,
      ).copyWith(canonicalId: 'anilist:16498', identityVersion: 2);

      await dao.upsert(anime);
      final DownloadRecord? read = await dao.recordFor(anime.id);
      expect(read!.mediaType, MediaType.anime);
      expect(read.canonicalId, 'anilist:16498');
      expect(read.identityVersion, 2);
    });

    test('episode records round-trip season and episode identity', () async {
      final DownloadRecord episode = record(
        'Show|series|2024|s1e2',
        mediaKey: 'Show|series|2024',
        mediaType: MediaType.series,
        seasonNumber: 1,
        episodeNumber: 2,
      );

      await dao.upsert(episode);

      final DownloadRecord? read = await dao.recordFor(episode.id);
      expect(read, isNotNull);
      expect(read!.mediaType, MediaType.series);
      expect(read.seasonNumber, 1);
      expect(read.episodeNumber, 2);
      expect(read.isEpisode, isTrue);
    });

    test(
      'a second upsert of one identity replaces the row, never duplicates',
      () async {
        final DownloadRecord original = record(
          'Movie|movie|2024',
          status: DownloadStatus.downloading,
        );
        await dao.upsert(original);

        await dao.upsert(
          original.copyWith(
            status: DownloadStatus.completed,
            bytesDownloaded: 8192,
            completedAt: DateTime(2026, 1, 3),
          ),
        );

        final List<DownloadRecord> all = await dao.all();
        expect(all.length, 1, reason: 'the identity is the primary key');
        expect(all.single.status, DownloadStatus.completed);
        expect(all.single.bytesDownloaded, 8192);
        expect(all.single.completedAt, DateTime(2026, 1, 3));
      },
    );

    test(
      'all() orders by creation time so a restart replays the queue FIFO',
      () async {
        await dao.upsert(
          record('b|movie|2024', createdAt: DateTime(2026, 1, 2)),
        );
        await dao.upsert(
          record('a|movie|2024', createdAt: DateTime(2026, 1, 1)),
        );
        await dao.upsert(
          record('c|movie|2024', createdAt: DateTime(2026, 1, 3)),
        );

        final List<String> ids = (await dao.all())
            .map((DownloadRecord r) => r.id)
            .toList();

        expect(ids, <String>['a|movie|2024', 'b|movie|2024', 'c|movie|2024']);
      },
    );

    test('recordFor returns null for a never-enqueued identity', () async {
      expect(await dao.recordFor('absent|movie|2024'), isNull);
    });

    test('remove deletes exactly its identity and is idempotent', () async {
      await dao.upsert(record('a|movie|2024'));
      await dao.upsert(record('b|movie|2024'));

      await dao.remove('a|movie|2024');
      await dao.remove('a|movie|2024'); // idempotent

      expect((await dao.all()).single.id, 'b|movie|2024');
    });

    test('clear removes every record', () async {
      await dao.upsert(record('a|movie|2024'));
      await dao.upsert(record('b|movie|2024'));

      await dao.clear();

      expect(await dao.all(), isEmpty);
    });

    test(
      'a corrupted state code degrades to failed instead of crashing',
      () async {
        // Simulate a row whose state column holds an unknown code (e.g. written
        // by a newer build): the DAO must degrade honestly, not throw.
        await db.customStatement(
          'INSERT INTO downloads (id, media_key, media_type, title, state, '
          'bytes_downloaded, file_path, attempt, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          <Object?>[
            'future|movie|2024',
            'future|movie|2024',
            'movie',
            'Future',
            'a-future-state',
            10,
            '/data/media/Future (x).mp4',
            0,
            1700000000,
            1700000001,
          ],
        );

        final DownloadRecord? read = await dao.recordFor('future|movie|2024');
        expect(read, isNotNull);
        expect(read!.status, DownloadStatus.failed);
        expect(
          read.failure,
          isNull,
          reason: 'no error code was stored, so no failure is invented',
        );
      },
    );
  });
}
