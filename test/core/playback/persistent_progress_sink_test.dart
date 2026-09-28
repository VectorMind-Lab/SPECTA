@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/library/library_store.dart';
import 'package:specta/core/library/watch_progress.dart';
import 'package:specta/core/playback/playback_progress_sink.dart';

import '../../support/in_memory_library_store.dart';

void main() {
  group('PersistentPlaybackProgressSink', () {
    test('maps a report onto one persisted episode row', () async {
      final InMemoryLibraryStore store = InMemoryLibraryStore();
      final PersistentPlaybackProgressSink sink =
          PersistentPlaybackProgressSink(store);

      sink.report(
        targetKey: 'Show|series|2024|s1e2',
        elapsed: const Duration(minutes: 3),
        position: const Duration(seconds: 20),
        duration: const Duration(minutes: 2),
        completed: false,
        mediaKey: 'Show|series|2024',
        mediaType: 'series',
        title: 'Show',
        subtitleLine: 'Season 1 · Episode 2',
        seasonNumber: 1,
        episodeNumber: 2,
      );
      await sink.idle;

      final WatchProgress? row = await store.progressFor(
        'Show|series|2024|s1e2',
      );
      expect(row, isNotNull);
      expect(row!.mediaKey, 'Show|series|2024');
      expect(row.mediaType, MediaType.series);
      expect(row.title, 'Show');
      expect(row.seasonNumber, 1);
      expect(row.episodeNumber, 2);
      expect(row.position, const Duration(seconds: 20));
      expect(row.duration, const Duration(minutes: 2));
      expect(row.completed, isFalse);
    });

    test('serialises rapid reports — the last write wins', () async {
      final InMemoryLibraryStore store = InMemoryLibraryStore();
      final PersistentPlaybackProgressSink sink =
          PersistentPlaybackProgressSink(store);

      for (int i = 1; i <= 25; i++) {
        sink.report(
          targetKey: 'm',
          elapsed: Duration(seconds: i),
          position: Duration(seconds: i),
          completed: false,
          title: 'Movie',
          mediaType: 'movie',
        );
      }
      await sink.idle;

      final WatchProgress row = (await store.progressFor('m'))!;
      expect(row.position, const Duration(seconds: 25));
      expect((await store.history()).length, 1);
    });

    test(
      'an empty target key is ignored — identity is never guessed',
      () async {
        final InMemoryLibraryStore store = InMemoryLibraryStore();
        final PersistentPlaybackProgressSink sink =
            PersistentPlaybackProgressSink(store);

        sink.report(
          targetKey: '',
          elapsed: const Duration(seconds: 5),
          completed: false,
        );
        await sink.idle;

        expect(await store.history(), isEmpty);
      },
    );

    test(
      'a storage failure never escapes and never blocks later writes',
      () async {
        final _FlakyStore store = _FlakyStore();
        final PersistentPlaybackProgressSink sink =
            PersistentPlaybackProgressSink(store);

        sink.report(targetKey: 'a', elapsed: Duration.zero, completed: false);
        sink.report(targetKey: 'b', elapsed: Duration.zero, completed: false);
        await sink.idle; // must complete, not throw

        expect(store.attempts, 2);
        expect(store.written, <String>['b']);
      },
    );

    test('a report without a title still persists the key', () async {
      final InMemoryLibraryStore store = InMemoryLibraryStore();
      final PersistentPlaybackProgressSink sink =
          PersistentPlaybackProgressSink(store);

      sink.report(
        targetKey: 'Untitled|movie|2024',
        elapsed: const Duration(seconds: 1),
        position: const Duration(seconds: 1),
        completed: false,
        mediaType: 'movie',
      );
      await sink.idle;

      final WatchProgress row = (await store.progressFor(
        'Untitled|movie|2024',
      ))!;
      expect(row.title, 'Untitled|movie|2024');
    });

    test('onChanged fires after a successful write', () async {
      final InMemoryLibraryStore store = InMemoryLibraryStore();
      int changes = 0;
      final PersistentPlaybackProgressSink sink =
          PersistentPlaybackProgressSink(store, onChanged: () => changes++);

      sink.report(targetKey: 'a', elapsed: Duration.zero, completed: false);
      await sink.idle;

      expect(changes, 1);
    });
  });
}

/// A store whose first write throws — verifies containment and serialisation.
class _FlakyStore implements LibraryStore {
  int attempts = 0;
  final List<String> written = <String>[];

  @override
  Future<void> upsert(WatchProgress progress) async {
    attempts++;
    if (attempts == 1) throw StateError('disk full');
    written.add(progress.id);
  }

  @override
  Future<WatchProgress?> progressFor(String id) async => null;

  @override
  Future<List<WatchProgress>> continueWatching({int limit = 20}) async =>
      const <WatchProgress>[];

  @override
  Future<List<WatchProgress>> history({int limit = 50}) async =>
      const <WatchProgress>[];

  @override
  Future<void> remove(String id) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> saveReferences(
    String mediaKey,
    List<DiscoveryReference> references, {
    String? canonicalId,
    int identityVersion = 1,
  }) async {}

  @override
  Future<List<DiscoveryReference>> referencesFor(String mediaKey) async =>
      const <DiscoveryReference>[];
}
