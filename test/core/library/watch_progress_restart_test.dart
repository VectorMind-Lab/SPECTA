@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/library/library_dao.dart';
import 'package:specta/core/library/watch_progress.dart';
import 'package:specta/core/playback/playback_progress_sink.dart';

/// Phase 2J §10.3 — watch progress is only genuinely "persistent" if it
/// survives the process that wrote it.
///
/// The sink's mapping rules and the resume orchestration are covered by their
/// own suites; both use an in-memory store, so neither can fail when the
/// WRITE never reaches disk. This test drives the real restart: a file-backed
/// database written through the production sink, closed, then reopened by a
/// session shaped exactly like the next app launch, which must read the same
/// position (and must still be able to re-open the item, i.e. the durable
/// provenance is there too).
void main() {
  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('specta_progress_restart');
    dbPath = '${tempDir.path}${Platform.pathSeparator}app.db';
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// One app session: a database opened over the same on-disk file, and the
  /// real production store the playback pipeline writes through.
  SpectaDatabase openSession({required List<SpectaDatabase> track}) {
    final SpectaDatabase db = SpectaDatabase(NativeDatabase(File(dbPath)));
    track.add(db);
    return db;
  }

  test(
    'a movie position written before the app closed resumes after it',
    () async {
      final List<SpectaDatabase> sessions = <SpectaDatabase>[];
      addTearDown(() async {
        for (final SpectaDatabase db in sessions) {
          await db.close();
        }
      });

      // ---- Session 1: the player reports progress, then the app dies. ----
      final LibraryDao library1 = LibraryDao(openSession(track: sessions));
      final PersistentPlaybackProgressSink sink =
          PersistentPlaybackProgressSink(library1);

      sink.report(
        targetKey: 'the matrix|movie|1999',
        elapsed: const Duration(minutes: 41),
        position: const Duration(minutes: 40),
        duration: const Duration(minutes: 136),
        completed: false,
        mediaKey: 'the matrix|movie|1999',
        mediaType: 'movie',
        title: 'The Matrix',
      );
      await sink.idle;

      // Durable provenance, so the item can actually be re-opened rather than
      // merely displayed: Continue Watching without a reference cannot resume.
      await library1.saveReferences(
        'the matrix|movie|1999',
        const <DiscoveryReference>[
          DiscoveryReference(extensionId: 'extA', url: 'https://a/matrix'),
        ],
      );

      // The app is closed (the file must be fully flushed, not merely written).
      await sessions.single.close();

      // ---- Session 2: a fresh process opens the same file. ----
      final LibraryDao library2 = LibraryDao(openSession(track: sessions));

      final WatchProgress? restored = await library2.progressFor(
        'the matrix|movie|1999',
      );
      expect(
        restored,
        isNotNull,
        reason: 'the reported position never reached disk',
      );
      expect(restored!.position, const Duration(minutes: 40));
      expect(restored.duration, const Duration(minutes: 136));
      expect(restored.elapsed, const Duration(minutes: 41));
      expect(restored.completed, isFalse);
      expect(restored.mediaType, MediaType.movie);
      expect(restored.mediaKey, 'the matrix|movie|1999');
      expect(restored.title, 'The Matrix');

      // The next launch offers it as Continue Watching, with the provenance the
      // resume path needs.
      final List<WatchProgress> continueWatching = await library2
          .continueWatching();
      expect(
        continueWatching.map((WatchProgress w) => w.id),
        contains('the matrix|movie|1999'),
      );
      expect((await library2.referencesFor('the matrix|movie|1999')).length, 1);
    },
  );

  test(
    'episode progress survives restart without collapsing onto its sibling',
    () async {
      final List<SpectaDatabase> sessions = <SpectaDatabase>[];
      addTearDown(() async {
        for (final SpectaDatabase db in sessions) {
          await db.close();
        }
      });

      final LibraryDao library1 = LibraryDao(openSession(track: sessions));

      // Two episodes of ONE series, reported out of order and at different
      // positions — the identity must be per episode, not per series.
      final PersistentPlaybackProgressSink sink =
          PersistentPlaybackProgressSink(library1);
      sink.report(
        targetKey: 'show|series|2020|s1e1',
        elapsed: const Duration(minutes: 48),
        position: const Duration(minutes: 47),
        duration: const Duration(minutes: 48),
        completed: false,
        mediaKey: 'show|series|2020',
        mediaType: 'series',
        title: 'Show',
        subtitleLine: 'Season 1 · Episode 1',
        seasonNumber: 1,
        episodeNumber: 1,
      );
      await sink.idle;
      sink.report(
        targetKey: 'show|series|2020|s1e2',
        elapsed: const Duration(minutes: 5),
        position: const Duration(minutes: 4),
        duration: const Duration(minutes: 48),
        completed: false,
        mediaKey: 'show|series|2020',
        mediaType: 'series',
        title: 'Show',
        subtitleLine: 'Season 1 · Episode 2',
        seasonNumber: 1,
        episodeNumber: 2,
      );
      await sink.idle;

      await sessions.single.close();

      final LibraryDao library2 = LibraryDao(openSession(track: sessions));
      final WatchProgress? episode1 = await library2.progressFor(
        'show|series|2020|s1e1',
      );
      final WatchProgress? episode2 = await library2.progressFor(
        'show|series|2020|s1e2',
      );

      expect(
        episode1!.position,
        const Duration(minutes: 47),
        reason: 'episode 2 overwrote episode 1 across the restart',
      );
      expect(episode2!.position, const Duration(minutes: 4));
      expect(episode1.episodeNumber, 1);
      expect(episode2.episodeNumber, 2);
      expect(episode1.mediaKey, episode2.mediaKey);
    },
  );

  test('a finished item stays finished after restart rather than resuming mid-way', () async {
    final List<SpectaDatabase> sessions = <SpectaDatabase>[];
    addTearDown(() async {
      for (final SpectaDatabase db in sessions) {
        await db.close();
      }
    });

    final LibraryDao library1 = LibraryDao(openSession(track: sessions));
    final PersistentPlaybackProgressSink sink = PersistentPlaybackProgressSink(
      library1,
    );
    sink.report(
      targetKey: 'the matrix|movie|1999',
      elapsed: const Duration(minutes: 136),
      position: const Duration(minutes: 136),
      duration: const Duration(minutes: 136),
      completed: true,
      mediaKey: 'the matrix|movie|1999',
      mediaType: 'movie',
      title: 'The Matrix',
    );
    await sink.idle;
    await sessions.single.close();

    final LibraryDao library2 = LibraryDao(openSession(track: sessions));
    final WatchProgress? restored = await library2.progressFor(
      'the matrix|movie|1999',
    );

    expect(restored!.completed, isTrue);
    // A completed item is not Continue Watching — the resume decision reads
    // this persisted flag, so losing it would silently restart a finished film
    // at its final minute.
    final List<WatchProgress> continueWatching = await library2
        .continueWatching();
    expect(
      continueWatching.map((WatchProgress w) => w.id),
      isNot(contains('the matrix|movie|1999')),
    );
  });
}
