import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_providers.dart';
import 'library_dao.dart';
import 'library_store.dart';
import 'watch_progress.dart';

/// The library store binding (Phase 2F).
///
/// Overridden with an in-memory-backed store in tests, exactly like
/// [settingsStoreProvider].
final Provider<LibraryStore> libraryStoreProvider = Provider<LibraryStore>((
  Ref ref,
) {
  return LibraryDao(ref.watch(spectaDatabaseProvider));
});

/// Bumped after every persisted progress write so read providers refresh.
///
/// The player writes progress while a film plays and the Library/Home surfaces
/// are not on screen, so a plain revision counter is enough — no polling.
final class LibraryRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final NotifierProvider<LibraryRevision, int> libraryRevisionProvider =
    NotifierProvider<LibraryRevision, int>(LibraryRevision.new);

/// Continue Watching: in-progress items, most recently watched first.
final FutureProvider<List<WatchProgress>> continueWatchingProvider =
    FutureProvider<List<WatchProgress>>((Ref ref) {
      ref.watch(libraryRevisionProvider);
      return ref.watch(libraryStoreProvider).continueWatching();
    });

/// History: every known item, most recently updated first.
final FutureProvider<List<WatchProgress>> watchHistoryProvider =
    FutureProvider<List<WatchProgress>>((Ref ref) {
      ref.watch(libraryRevisionProvider);
      return ref.watch(libraryStoreProvider).history();
    });
