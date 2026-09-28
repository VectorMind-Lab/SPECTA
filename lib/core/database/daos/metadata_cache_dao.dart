import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:specta/core/database/specta_database.dart';

/// Persistent TTL cache for catalogue metadata (TMDB + TVMaze).
///
/// Read-through contract: callers check [read] first; only a miss or stale
/// row triggers a network fetch, whose JSON result is stored with [write].
/// Payloads already contain title/overview/cast and stable image URLs, so a
/// fresh hit performs zero source API calls and zero image-endpoint calls.
final class MetadataCacheDao {
  MetadataCacheDao(this._db);

  final SpectaDatabase _db;

  /// Cache lifetime. Long enough to avoid re-fetching a title every open;
  /// short enough that catalogue corrections surface within a month.
  static const Duration timeToLive = Duration(days: 30);

  /// Returns the cached payload when the row exists and is not stale.
  Future<String?> read({
    required String source,
    required String mediaKey,
    DateTime? now,
  }) async {
    final DateTime at = (now ?? DateTime.now()).toUtc();
    final MetadataCacheRow? row =
        await (_db.select(_db.metadataCache)..where(
              (t) => t.source.equals(source) & t.mediaKey.equals(mediaKey),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    if (!row.expiresAt.isAfter(at)) return null;
    return row.payload;
  }

  /// Stores [payloadJson] under (source, mediaKey) with a fresh TTL.
  Future<void> write({
    required String source,
    required String mediaKey,
    required String payloadJson,
    DateTime? now,
  }) async {
    // Validate JSON shape early so corrupt payloads never enter the cache.
    jsonDecode(payloadJson);
    final DateTime at = (now ?? DateTime.now()).toUtc();
    await _db
        .into(_db.metadataCache)
        .insertOnConflictUpdate(
          MetadataCacheCompanion.insert(
            source: source,
            mediaKey: mediaKey,
            payload: payloadJson,
            expiresAt: at.add(timeToLive),
            updatedAt: at,
          ),
        );
  }

  /// Removes one cached entry (e.g. user-triggered refresh of a title).
  Future<void> remove({required String source, required String mediaKey}) {
    return (_db.delete(_db.metadataCache)
          ..where((t) => t.source.equals(source) & t.mediaKey.equals(mediaKey)))
        .go();
  }
}
