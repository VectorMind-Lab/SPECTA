import 'package:specta/core/library/library_store.dart';
import 'package:specta/core/library/watch_progress.dart';

/// In-memory [LibraryStore] for tests that need the library contract without a
/// database. Mirrors the DAO's ordering and filtering rules so UI tests observe
/// the same semantics as production.
class InMemoryLibraryStore implements LibraryStore {
  final Map<String, WatchProgress> _rows = <String, WatchProgress>{};

  @override
  Future<void> upsert(WatchProgress progress) async {
    _rows[progress.id] = progress;
  }

  @override
  Future<WatchProgress?> progressFor(String id) async => _rows[id];

  @override
  Future<List<WatchProgress>> continueWatching({int limit = 20}) async {
    final List<WatchProgress> rows = _rows.values
        .where((WatchProgress p) => !p.completed && p.position > Duration.zero)
        .toList()
      ..sort((WatchProgress a, WatchProgress b) =>
          b.updatedAt.compareTo(a.updatedAt));
    return rows.take(limit).toList(growable: false);
  }

  @override
  Future<List<WatchProgress>> history({int limit = 50}) async {
    final List<WatchProgress> rows = _rows.values.toList()
      ..sort((WatchProgress a, WatchProgress b) =>
          b.updatedAt.compareTo(a.updatedAt));
    return rows.take(limit).toList(growable: false);
  }

  @override
  Future<void> remove(String id) async {
    _rows.remove(id);
  }

  @override
  Future<void> clear() async => _rows.clear();
}
