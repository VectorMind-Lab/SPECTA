@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/downloads/download_dao.dart';
import 'package:specta/core/downloads/download_models.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/contract/result_models.dart';

// PERSISTENCE CONTRACT TESTS (Phase 2G foundation).
//
// The SPECTA downloads table is the AUTHORITATIVE persistent source of truth;
// the future DownloadEngine's internal storage is non-authoritative and does
// not even exist yet. Every test here exercises the real DownloadStore/DAO
// persistence path against a real SQLite FILE (not memory): records are
// written in one session, the database is CLOSED, REOPENED, and the state is
// reconstructed from SPECTA persistence ALONE.
//
// "Manager recreation" from the contract maps to store recreation for this
// phase: no DownloadManager exists yet (2G-B will add it), and the contract's
// own §7 assigns the reconciliation policy to 2G-C. What must hold NOW is
// that the persistence layer can carry every fact the future manager needs.
void main() {
  group('Persistence contract — SPECTA database is authoritative', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('specta_dl_contract');
      dbPath = '${tempDir.path}${Platform.pathSeparator}specta.db';
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    SpectaDatabase openDatabase() => SpectaDatabase(NativeDatabase(File(dbPath)));

    DownloadRecord record(
      String id, {
      String mediaKey = 'Movie|movie|2024',
      MediaType mediaType = MediaType.movie,
      String title = 'Movie',
      String? subtitleLine,
      int? seasonNumber,
      int? episodeNumber,
      DownloadStatus status = DownloadStatus.queued,
      int bytesDownloaded = 0,
      int? totalBytes,
      DownloadFailure? failure,
      int attempt = 0,
      DateTime? createdAt,
      DateTime? updatedAt,
      DateTime? completedAt,
    }) =>
        DownloadRecord(
          id: id,
          mediaKey: mediaKey,
          mediaType: mediaType,
          title: title,
          subtitleLine: subtitleLine,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
          status: status,
          bytesDownloaded: bytesDownloaded,
          totalBytes: totalBytes,
          filePath: '/data/media/Movie (x).mp4',
          attempt: attempt,
          failure: failure,
          createdAt: createdAt ?? DateTime(2026, 1, 1),
          updatedAt: updatedAt ?? DateTime(2026, 1, 2),
          completedAt: completedAt,
        );

    test('every state survives store recreation (queued, downloading, paused,'
        ' failed, completed, cancelled)', () async {
      // Session 1: write one record per state.
      final SpectaDatabase first = openDatabase();
      final DownloadDao writer = DownloadDao(first);
      await writer.upsert(record('queued|movie|2024',
          status: DownloadStatus.queued));
      await writer.upsert(record('downloading|movie|2024',
          status: DownloadStatus.downloading,
          bytesDownloaded: 512,
          totalBytes: 2048,
          attempt: 1));
      await writer.upsert(record('paused|movie|2024',
          status: DownloadStatus.paused, bytesDownloaded: 1024));
      await writer.upsert(
        record(
          'failed|movie|2024',
          status: DownloadStatus.failed,
          failure: DownloadFailure(
            type: DownloadFailureType.httpError,
            message: 'The server refused this download (source unavailable).',
          ),
          attempt: 2,
        ),
      );
      await writer.upsert(record('completed|movie|2024',
          status: DownloadStatus.completed,
          bytesDownloaded: 2048,
          totalBytes: 2048,
          completedAt: DateTime(2026, 1, 3)));
      await writer.upsert(record('cancelled|movie|2024',
          status: DownloadStatus.cancelled));
      await first.close();

      // Session 2: a fresh manager/store over the same file reconstructs
      // SPECTA state from SPECTA persistence ALONE.
      final SpectaDatabase second = openDatabase();
      addTearDown(second.close);
      final DownloadDao reader = DownloadDao(second);
      final Map<String, DownloadRecord> byId = <String, DownloadRecord>{
        for (final DownloadRecord r in await reader.all()) r.id: r,
      };

      expect(byId.length, 6);

      final DownloadRecord queued = byId['queued|movie|2024']!;
      expect(queued.status, DownloadStatus.queued);

      final DownloadRecord downloading = byId['downloading|movie|2024']!;
      expect(downloading.status, DownloadStatus.downloading);
      expect(downloading.bytesDownloaded, 512);
      expect(downloading.totalBytes, 2048);
      expect(downloading.attempt, 1);

      final DownloadRecord paused = byId['paused|movie|2024']!;
      expect(paused.status, DownloadStatus.paused);
      expect(paused.bytesDownloaded, 1024);

      final DownloadRecord failed = byId['failed|movie|2024']!;
      expect(failed.status, DownloadStatus.failed);
      expect(failed.attempt, 2);
      expect(failed.failure, isNotNull);
      expect(failed.failure!.type, DownloadFailureType.httpError);
      expect(failed.failure!.isRetryable, isFalse,
          reason: 'retry eligibility is reconstructed from the stored type');
      expect(failed.failure!.message,
          'The server refused this download (source unavailable).');

      final DownloadRecord completed = byId['completed|movie|2024']!;
      expect(completed.status, DownloadStatus.completed);
      expect(completed.bytesDownloaded, 2048);
      expect(completed.completedAt, DateTime(2026, 1, 3));

      final DownloadRecord cancelled = byId['cancelled|movie|2024']!;
      expect(cancelled.status, DownloadStatus.cancelled);
    });

    test('identity, display metadata, provenance and paths survive '
        'recreation without any engine artifact', () async {
      final SpectaDatabase first = openDatabase();
      await DownloadDao(first).upsert(
        record(
          'Show|series|2024|s1e2',
          mediaKey: 'Show|series|2024',
          mediaType: MediaType.series,
          title: 'Show',
          subtitleLine: 'Season 1 · Episode 2',
          seasonNumber: 1,
          episodeNumber: 2,
          status: DownloadStatus.downloading,
          bytesDownloaded: 4096,
          totalBytes: 16384,
        ),
      );
      await first.close();

      // The engine's internal task database does not exist in this phase —
      // and must never be needed to reconstruct SPECTA domain state.
      final SpectaDatabase second = openDatabase();
      addTearDown(second.close);
      final DownloadRecord r =
          (await DownloadDao(second).recordFor('Show|series|2024|s1e2'))!;

      // §2 of the contract: every product-relevant fact is present.
      expect(r.id, 'Show|series|2024|s1e2'); // download identity
      expect(r.mediaKey, 'Show|series|2024'); // media identity
      expect(r.mediaType, MediaType.series); // movie/episode identity
      expect(r.title, 'Show'); // title metadata
      expect(r.subtitleLine, 'Season 1 · Episode 2');
      expect(r.status, DownloadStatus.downloading); // state
      expect(r.bytesDownloaded, 4096); // byte progress
      expect(r.totalBytes, 16384); // expected total
      expect(r.filePath, '/data/media/Movie (x).mp4'); // final path
      expect(
        downloadPartPathFor(r.filePath),
        '/data/media/Movie (x).mp4.part',
      ); // .part derivation, from the persisted path alone
      expect(r.createdAt, DateTime(2026, 1, 1)); // timestamps
      expect(r.updatedAt, DateTime(2026, 1, 2));
      expect(r.completedAt, isNull);
      expect(r.failure, isNull); // no failure was stored
    });

    test('queue ordering survives recreation (FIFO replay after restart)',
        () async {
      final SpectaDatabase first = openDatabase();
      final DownloadDao writer = DownloadDao(first);
      await writer.upsert(record('b|movie|2024', createdAt: DateTime(2026, 1, 2)));
      await writer.upsert(record('a|movie|2024', createdAt: DateTime(2026, 1, 1)));
      await writer.upsert(record('c|movie|2024', createdAt: DateTime(2026, 1, 3)));
      await first.close();

      final SpectaDatabase second = openDatabase();
      addTearDown(second.close);
      final List<String> ids =
          (await DownloadDao(second).all()).map((DownloadRecord r) => r.id).toList();

      expect(ids, <String>['a|movie|2024', 'b|movie|2024', 'c|movie|2024']);
    });

    test('duplicate identity remains one record across recreation (§8)',
        () async {
      final SpectaDatabase first = openDatabase();
      final DownloadDao writer = DownloadDao(first);
      await writer.upsert(record('dup|movie|2024', status: DownloadStatus.queued));
      // Enqueue the same identity again (user retry / duplicate request).
      await writer.upsert(
        record('dup|movie|2024', status: DownloadStatus.downloading, attempt: 1),
      );
      await first.close();

      final SpectaDatabase second = openDatabase();
      addTearDown(second.close);
      final List<DownloadRecord> all = await DownloadDao(second).all();

      expect(all.length, 1);
      expect(all.single.status, DownloadStatus.downloading);
      expect(all.single.attempt, 1,
          reason: 'the second enqueue replaced the first, atomically');
    });

    test('a single upsert lands state, attempt and timestamps together (§9)',
        () async {
      final SpectaDatabase db = openDatabase();
      addTearDown(db.close);
      final DownloadDao dao = DownloadDao(db);

      final DateTime updated = DateTime(2026, 1, 5);
      await dao.upsert(record('atomic|movie|2024',
          status: DownloadStatus.downloading,
          bytesDownloaded: 128,
          attempt: 1,
          updatedAt: updated));

      final DownloadRecord r = (await dao.all()).single;
      // One INSERT OR REPLACE wrote every field of the logical state change;
      // the row cannot show a mixed old/new state.
      expect(r.status, DownloadStatus.downloading);
      expect(r.attempt, 1);
      expect(r.bytesDownloaded, 128);
      expect(r.updatedAt, updated);
    });

    test('terminal records cannot be resurrected — the state machine the '
        'manager must consult refuses it (§11)', () {
      // The manager-level guard arrives in 2G-B; the invariant it must
      // enforce already lives in the machine: completed and cancelled have
      // NO outgoing transitions, so a stale engine callback can never turn
      // completed/cancelled into downloading.
      expect(
        DownloadStateMachine.canTransition(
            DownloadStatus.completed, DownloadStatus.downloading),
        isFalse,
      );
      expect(
        DownloadStateMachine.canTransition(
            DownloadStatus.cancelled, DownloadStatus.downloading),
        isFalse,
      );
      for (final DownloadStatus to in DownloadStatus.values) {
        expect(
          DownloadStateMachine.canTransition(DownloadStatus.completed, to),
          isFalse,
          reason: 'completed → $to must be refused',
        );
        expect(
          DownloadStateMachine.canTransition(DownloadStatus.cancelled, to),
          to == DownloadStatus.queued,
          reason: 'cancelled → $to: only an explicit user retry may re-queue',
        );
      }
    });

    test('recreation is repeatable: initializing the store twice is safe (§8)',
        () async {
      // Manager initialization must be idempotent; the store it reads must
      // tolerate being opened any number of times over the same file.
      for (int i = 0; i < 3; i++) {
        final SpectaDatabase session = openDatabase();
        final DownloadDao dao = DownloadDao(session);
        if (i == 0) {
          await dao.upsert(record('steady|movie|2024'));
        }
        expect((await dao.all()).length, 1);
        await session.close();
      }
    });
  });
}
