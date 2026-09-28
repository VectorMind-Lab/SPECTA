import 'package:drift/drift.dart';

/// Persisted watch progress — the Phase 2F library table.
///
/// One row per playback identity. The identity is exactly the one the playback
/// session already reports through `PlaybackProgressSink.targetKey`:
///
/// * a movie    → `<mediaKey>`            (the 2C evidence-based metadata key)
/// * an episode → `<mediaKey>|s<S>e<E>`   (season + episode preserved)
///
/// Storing the season/episode-qualified identity as the primary key is what
/// makes it impossible for a completed Episode 2 to overwrite Episode 1.
///
/// Extensions never read or write this table: SPECTA owns persistence. See
/// docs/PHASE_2F_REPORT.md for why history and Continue Watching are both
/// queries over this one table rather than a duplicated second table.
@DataClassName('WatchProgressRow')
class WatchProgressEntries extends Table {
  @override
  String get tableName => 'watch_progress';

  /// Stable playback identity (see the class comment). Primary key.
  TextColumn get id => text()();

  /// Canonical work identity when identity_version = 2, otherwise null.
  TextColumn get canonicalId => text().nullable()();

  /// Identity scheme: 1 = legacy title key, 2 = provider canonical key.
  IntColumn get identityVersion => integer().withDefault(const Constant(1))();

  /// The parent work's canonical 2C metadata key (normalized title|type|year).
  TextColumn get mediaKey => text()();

  /// `MediaType.code` from the extension contract: `movie` or `series`.
  TextColumn get mediaType => text()();

  /// Display title as the player knew it. Never a provider URL or extension id.
  TextColumn get title => text()();

  /// Optional second display line, e.g. `Season 1 · Episode 2`.
  TextColumn get subtitleLine => text().nullable()();

  /// Season / episode numbers for a series episode; null for a movie.
  IntColumn get seasonNumber => integer().nullable()();
  IntColumn get episodeNumber => integer().nullable()();

  /// Last observed playback position.
  IntColumn get positionMs => integer().withDefault(const Constant(0))();

  /// Total media duration when the engine reported one.
  IntColumn get durationMs => integer().nullable()();

  /// Accumulated watch time the player measured this session.
  IntColumn get elapsedMs => integer().withDefault(const Constant(0))();

  /// 0/1 — the player reported playback reached the end.
  IntColumn get completed => integer().withDefault(const Constant(0))();

  /// Last time the player reported progress for this identity.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
