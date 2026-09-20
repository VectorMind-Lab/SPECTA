import 'package:drift/drift.dart';

import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/contract/result_models.dart';

import 'download_models.dart';
import 'download_store.dart';

/// Drift-backed implementation of [DownloadStore].
///
/// All writes are single-row upserts on the download identity; the read list
/// is deterministically ordered by creation time so a restarted app replays
/// the queue FIFO. Every order in this file is a pure SQL order — no
/// re-sorting happens in Dart on top of the database.
class DownloadDao implements DownloadStore {
  DownloadDao(this._db);

  final SpectaDatabase _db;

  @override
  Future<List<DownloadRecord>> all() async {
    final List<DownloadRow> rows = await (_db.select(_db.downloads)
          ..orderBy(<OrderingTerm Function($DownloadsTable)>[
            ($DownloadsTable t) => OrderingTerm.asc(t.createdAt),
          ]))
        .get();
    return rows.map(_toModel).toList(growable: false);
  }

  @override
  Future<DownloadRecord?> recordFor(String id) async {
    final DownloadRow? row = await (_db.select(_db.downloads)
          ..where(($DownloadsTable t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  @override
  Future<void> upsert(DownloadRecord record) async {
    await _db
        .into(_db.downloads)
        .insertOnConflictUpdate(
          DownloadsCompanion.insert(
            id: record.id,
            mediaKey: record.mediaKey,
            mediaType: record.mediaType.code,
            title: record.title,
            subtitleLine: Value<String?>(record.subtitleLine),
            seasonNumber: Value<int?>(record.seasonNumber),
            episodeNumber: Value<int?>(record.episodeNumber),
            state: record.status.code,
            waitReason: Value<String?>(record.waitReason?.code),
            bytesDownloaded: Value<int>(record.bytesDownloaded),
            totalBytes: Value<int?>(record.totalBytes),
            filePath: record.filePath,
            sourceExtensionId: Value<String?>(record.sourceExtensionId),
            sourceReference: Value<String?>(record.sourceReference),
            sourceLabel: Value<String?>(record.sourceLabel),
            attempt: Value<int>(record.attempt),
            errorCode: Value<String?>(record.failure?.type.code),
            errorMessage: Value<String?>(record.failure?.message),
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            completedAt: Value<DateTime?>(record.completedAt),
          ),
        );
  }

  @override
  Future<void> remove(String id) async {
    await (_db.delete(_db.downloads)
          ..where(($DownloadsTable t) => t.id.equals(id)))
        .go();
  }

  @override
  Future<void> clear() async {
    await _db.delete(_db.downloads).go();
  }

  DownloadRecord _toModel(DownloadRow row) => DownloadRecord(
        id: row.id,
        mediaKey: row.mediaKey,
        // Rows are only ever written by SPECTA with a valid code; an
        // unrecognised value degrades to a movie rather than crashing a
        // screen for one bad row (same rule as the library DAO).
        mediaType: MediaType.fromCode(row.mediaType) ?? MediaType.movie,
        title: row.title,
        subtitleLine: row.subtitleLine,
        seasonNumber: row.seasonNumber,
        episodeNumber: row.episodeNumber,
        status: DownloadStatus.fromCode(row.state) ?? DownloadStatus.failed,
        waitReason: DownloadWaitReason.fromCode(row.waitReason),
        bytesDownloaded: row.bytesDownloaded,
        totalBytes: row.totalBytes,
        filePath: row.filePath,
        sourceExtensionId: row.sourceExtensionId,
        sourceReference: row.sourceReference,
        sourceLabel: row.sourceLabel,
        attempt: row.attempt,
        failure: row.errorCode == null
            ? null
            : DownloadFailure(
                type: DownloadFailureType.fromCode(row.errorCode) ??
                    DownloadFailureType.sourcesExhausted,
                message: row.errorMessage ?? '',
              ),
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        completedAt: row.completedAt,
      );
}
