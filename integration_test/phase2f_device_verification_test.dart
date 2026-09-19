// SPECTA — Phase 2F device verification (test-only; no lib/ product change).
//
// Exercises the REAL on-device SQLite database inside the real app process on
// a physical device:
//
//   1. The application database opens and reports schema v4, proving the
//      registered v2 -> v3 -> v4 migrations run on a real installed database.
//   2. The persistent progress sink writes real watch progress through the
//      same LibraryStore/Dao the player uses, and reads it back.
//   3. Episode identity is preserved on device (s1e2 is its own row).
//   4. Durable resume provenance (discovery references) round-trips on device
//      — without ever storing a source URL.
//   5. Test rows are removed afterwards — the user's library is never left
//      polluted by a verification run.
//
// A failure here is reported as a test failure, never hidden.

import 'package:drift/drift.dart' show QueryRow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:specta/core/database/database_providers.dart';
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/library/library_providers.dart';
import 'package:specta/core/library/library_store.dart';
import 'package:specta/core/library/watch_progress.dart';
import 'package:specta/core/playback/playback_progress_sink.dart';

// ignore: avoid_print
void marker(String m) => print('[SPECTA-P2F] $m');

/// Test rows are namespaced so they can never be mistaken for real content and
/// are always removed at the end.
const String testMovieKey = '__p2f_test__|movie|2026';
const String testEpisodeKey = '__p2f_test__|series|2026|s1e2';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('P2F-1: the on-device database is at schema v4 (migrations ran)',
      () async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    final SpectaDatabase db = container.read(spectaDatabaseProvider);

    // Force a real open; the registered migration runs before this returns.
    final List<QueryRow> rows =
        await db.customSelect('PRAGMA user_version').get();
    final int version = rows.single.read<int>('user_version');
    marker('on-device PRAGMA user_version = $version');
    expect(version, 4, reason: 'the v2 -> v4 migrations did not complete');

    // The pre-existing v1 settings table is still reachable.
    await db.customSelect('SELECT key FROM settings_entries LIMIT 1').get();
    marker('settings_entries reachable after upgrade');

    // The v3 progress table is queryable.
    await db.customSelect('SELECT id FROM watch_progress LIMIT 1').get();
    marker('watch_progress reachable after upgrade');

    // The v4 resume-provenance table is queryable.
    await db.customSelect('SELECT media_key FROM media_references LIMIT 1').get();
    marker('media_references reachable after upgrade');
  });

  test('P2F-2: the persistent sink writes real progress to the device database',
      () async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    final LibraryStore store = container.read(libraryStoreProvider);
    final PersistentPlaybackProgressSink sink =
        PersistentPlaybackProgressSink(store);

    sink.report(
      targetKey: testMovieKey,
      elapsed: const Duration(minutes: 1),
      position: const Duration(seconds: 30),
      duration: const Duration(minutes: 2),
      completed: false,
      mediaKey: testMovieKey,
      mediaType: 'movie',
      title: 'P2F Test Movie',
    );
    sink.report(
      targetKey: testEpisodeKey,
      elapsed: const Duration(minutes: 2),
      position: const Duration(seconds: 45),
      duration: const Duration(minutes: 3),
      completed: false,
      mediaKey: '__p2f_test__|series|2026',
      mediaType: 'series',
      title: 'P2F Test Show',
      subtitleLine: 'Season 1 · Episode 2',
      seasonNumber: 1,
      episodeNumber: 2,
    );
    await sink.idle;

    final WatchProgress? movie = await store.progressFor(testMovieKey);
    final WatchProgress? episode = await store.progressFor(testEpisodeKey);

    expect(movie, isNotNull);
    expect(movie!.mediaType, MediaType.movie);
    expect(movie.position, const Duration(seconds: 30));
    expect(movie.fraction, closeTo(0.25, 0.001));

    expect(episode, isNotNull);
    expect(episode!.mediaType, MediaType.series);
    expect(episode.seasonNumber, 1);
    expect(episode.episodeNumber, 2);
    expect(episode.subtitleLine, 'Season 1 · Episode 2');

    final List<WatchProgress> continueWatching = await store.continueWatching();
    expect(
      continueWatching.any((WatchProgress p) => p.id == testMovieKey),
      isTrue,
    );
    expect(
      continueWatching.any((WatchProgress p) => p.id == testEpisodeKey),
      isTrue,
    );
    marker('continue watching rows present on device: '
        '${continueWatching.map((WatchProgress p) => p.id).toList()}');

    // Cleanup: never leave verification rows in the user's library.
    await store.remove(testMovieKey);
    await store.remove(testEpisodeKey);
    expect(await store.progressFor(testMovieKey), isNull);
    expect(await store.progressFor(testEpisodeKey), isNull);
    marker('verification rows removed');
  });

  test('P2F-3: durable resume provenance is stored on the device database',
      () async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    final LibraryStore store = container.read(libraryStoreProvider);

    const String mediaKey = '__p2f_test__|series|2026';
    await store.saveReferences(
      mediaKey,
      const <DiscoveryReference>[
        DiscoveryReference(
          extensionId: '__p2f_ext_a__',
          url: 'https://a/__p2f_test__',
        ),
        DiscoveryReference(
          extensionId: '__p2f_ext_b__',
          url: 'https://b/__p2f_test__',
        ),
      ],
    );

    final List<DiscoveryReference> refs = await store.referencesFor(mediaKey);
    expect(refs.length, 2);
    expect(refs[0].extensionId, '__p2f_ext_a__');
    expect(refs[1].extensionId, '__p2f_ext_b__');
    marker('durable provenance on device: '
        '${refs.map((DiscoveryReference r) => r.extensionId).toList()}');

    // Cleanup: replace with nothing, then confirm empty.
    await store.saveReferences(mediaKey, const <DiscoveryReference>[]);
    expect(await store.referencesFor(mediaKey), isEmpty);
    marker('provenance verification rows removed');
  });
}
