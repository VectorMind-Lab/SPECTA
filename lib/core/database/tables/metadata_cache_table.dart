import 'package:drift/drift.dart';

/// Aggressively cached catalogue metadata shared by TMDB and TVMaze.
///
/// One row per (source, media key). `payload` is the already-normalized
/// SPECTA metadata JSON (title/overview/cast/image URLs/etc.), so a cache hit
/// never touches TMDB or TVMaze. Image *bytes* stay on the standard Flutter
/// image cache + CDN path: we cache the stable image URLs inside `payload`,
/// not duplicate binary files. Refetch only on miss or when `expiresAt` is
/// past (stale).
@DataClassName('MetadataCacheRow')
class MetadataCache extends Table {
  @override
  String get tableName => 'metadata_cache';

  /// 'tmdb' or 'tvmaze'. Part of the primary key.
  TextColumn get source => text()();

  /// Canonical SPECTA identity key (e.g. normalized title|type|year or
  /// `tmdb:movie:123` / `tvmaze:show:42`). Part of the primary key.
  TextColumn get mediaKey => text()();

  /// Normalized metadata JSON including title, overview, cast, image URLs.
  TextColumn get payload => text()();

  /// When this row goes stale. Hits before this time avoid all network I/O.
  DateTimeColumn get expiresAt => dateTime()();

  /// Last write time (insert or refresh).
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {source, mediaKey};
}
