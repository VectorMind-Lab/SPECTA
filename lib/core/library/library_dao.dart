import 'package:drift/drift.dart';

import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/extensions/contract/result_models.dart';

import 'library_store.dart';
import 'watch_progress.dart';

/// Drift-backed implementation of [LibraryStore].
///
/// All reads are bounded by a limit and ordered deterministically, so a large
/// library can never make a query unbounded. Writes are single-row upserts on
/// the playback identity.
class LibraryDao implements LibraryStore {
  LibraryDao(this._db);

  final SpectaDatabase _db;

  @override
  Future<void> upsert(WatchProgress progress) async {
    await _db
        .into(_db.watchProgressEntries)
        .insertOnConflictUpdate(
          WatchProgressEntriesCompanion.insert(
            id: progress.id,
            mediaKey: progress.mediaKey,
            mediaType: progress.mediaType.code,
            title: progress.title,
            subtitleLine: Value<String?>(progress.subtitleLine),
            seasonNumber: Value<int?>(progress.seasonNumber),
            episodeNumber: Value<int?>(progress.episodeNumber),
            positionMs: Value<int>(progress.position.inMilliseconds),
            durationMs: Value<int?>(progress.duration?.inMilliseconds),
            elapsedMs: Value<int>(progress.elapsed.inMilliseconds),
            completed: Value<int>(progress.completed ? 1 : 0),
            updatedAt: progress.updatedAt,
          ),
        );
  }

  @override
  Future<WatchProgress?> progressFor(String id) async {
    final WatchProgressRow? row =
        await (_db.select(_db.watchProgressEntries)
              ..where(($WatchProgressEntriesTable t) => t.id.equals(id)))
            .getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  @override
  Future<List<WatchProgress>> continueWatching({int limit = 20}) async {
    final List<WatchProgressRow> rows =
        await (_db.select(_db.watchProgressEntries)
              ..where(
                ($WatchProgressEntriesTable t) =>
                    t.completed.equals(0) &
                    t.positionMs.isBiggerThanValue(0),
              )
              ..orderBy(<OrderingTerm Function($WatchProgressEntriesTable)>[
                ($WatchProgressEntriesTable t) =>
                    OrderingTerm.desc(t.updatedAt),
              ])
              ..limit(limit))
            .get();
    return rows.map(_toModel).toList(growable: false);
  }

  @override
  Future<List<WatchProgress>> history({int limit = 50}) async {
    final List<WatchProgressRow> rows =
        await (_db.select(_db.watchProgressEntries)
              ..orderBy(<OrderingTerm Function($WatchProgressEntriesTable)>[
                ($WatchProgressEntriesTable t) =>
                    OrderingTerm.desc(t.updatedAt),
              ])
              ..limit(limit))
            .get();
    return rows.map(_toModel).toList(growable: false);
  }

  @override
  Future<void> remove(String id) async {
    await (_db.delete(_db.watchProgressEntries)
          ..where(($WatchProgressEntriesTable t) => t.id.equals(id)))
        .go();
  }

  @override
  Future<void> clear() async {
    await _db.delete(_db.watchProgressEntries).go();
  }

  WatchProgress _toModel(WatchProgressRow row) => WatchProgress(
        id: row.id,
        mediaKey: row.mediaKey,
        // Rows are only ever written by SPECTA with a valid code; an
        // unrecognised value is treated as a movie rather than crashing a
        // library screen for one bad row.
        mediaType: MediaType.fromCode(row.mediaType) ?? MediaType.movie,
        title: row.title,
        subtitleLine: row.subtitleLine,
        seasonNumber: row.seasonNumber,
        episodeNumber: row.episodeNumber,
        position: Duration(milliseconds: row.positionMs),
        duration: row.durationMs == null
            ? null
            : Duration(milliseconds: row.durationMs!),
        elapsed: Duration(milliseconds: row.elapsedMs),
        completed: row.completed != 0,
        updatedAt: row.updatedAt,
      );
}
