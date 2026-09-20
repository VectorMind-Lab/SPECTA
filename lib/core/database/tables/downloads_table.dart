import 'package:drift/drift.dart';

/// Durable download records — Phase 2G.
///
/// One row per download identity. The identity is exactly the SAME media
/// identity the player and the library already use (Phase 2C metadata key,
/// with `|s<S>e<E>` appended for an episode) — no second identity model:
///
/// * a movie    → `<mediaKey>`            (e.g. `dune|movie|2021`)
/// * an episode → `<mediaKey>|s<S>e<E>`   (e.g. `show|series|2024|s1e2`)
///
/// Storing the episode-qualified identity as the primary key is what makes
/// "Movie A" and "Movie A episode S1E1" two distinct downloads, and makes it
/// impossible for one to be mistaken for the other.
///
/// Recovery discipline (deliberate):
/// * The table stores the PROVENANCE of the last attempt (extension id +
///   extension-internal reference), never a playback URL. Source URLs expire;
///   on recovery the pool is re-resolved through the current SourceManager,
///   so no stale URL is ever trusted.
/// * `totalBytes` stays null when the server did not declare a size — an
///   unknown size is never fabricated.
/// * The in-progress `.part` path is derived from `filePath` in code and is
///   deliberately not stored (it cannot drift from the final path).
/// * Extensions never read or write this table; SPECTA owns persistence.
@DataClassName('DownloadRow')
class Downloads extends Table {
  @override
  String get tableName => 'downloads';

  /// Stable download identity (the playback identity). Primary key.
  TextColumn get id => text()();

  /// The parent work's canonical 2C metadata key (normalized title|type|year).
  TextColumn get mediaKey => text()();

  /// `MediaType.code` from the extension contract: `movie` or `series`.
  TextColumn get mediaType => text()();

  /// Display title as the user saw it in details. Never a provider URL.
  TextColumn get title => text()();

  /// Optional second display line, e.g. `Season 1 · Episode 2`.
  TextColumn get subtitleLine => text().nullable()();

  /// Season / episode numbers for a series episode; null for a movie.
  IntColumn get seasonNumber => integer().nullable()();
  IntColumn get episodeNumber => integer().nullable()();

  /// `queued` / `downloading` / `paused` / `completed` / `failed` /
  /// `cancelled` — the explicit, testable state machine (see
  /// `DownloadStatus`). Cancelled rows are kept so the user can retry them
  /// intentionally; removal is the user's explicit delete.
  TextColumn get state => text()();

  /// Why the queue is not starting this job right now (e.g. "waiting for
  /// Wi-Fi", "not enough free storage"). Descriptive data, not a state.
  TextColumn get waitReason => text().nullable()();

  /// Bytes safely written to the partial file so far (persisted in bounded
  /// steps, and always on every state transition).
  IntColumn get bytesDownloaded => integer().withDefault(const Constant(0))();

  /// Declared total size, or null when the server did not declare one.
  IntColumn get totalBytes => integer().nullable()();

  /// Final, completed-media path (planned at enqueue time). Only the
  /// completed download is ever found at this path; incomplete data lives in
  /// the derived `.part` file and is atomically moved here on completion.
  TextColumn get filePath => text()();

  /// Provenance of the last attempt: the contributing extension's registry
  /// id and the extension-internal reference it was asked about. Recovery
  /// re-resolves through these — never through a stored URL.
  TextColumn get sourceExtensionId => text().nullable()();
  TextColumn get sourceReference => text().nullable()();

  /// Neutral user-facing label of the last attempt (e.g. `Server 1`), kept
  /// for honest display. Provider domain names are never stored here.
  TextColumn get sourceLabel => text().nullable()();

  /// Completed auto-retry budget used so far for the current run.
  IntColumn get attempt => integer().withDefault(const Constant(0))();

  /// Structured failure code + message of the last failure. Only for
  /// `failed` (kept until the record is retried or removed).
  TextColumn get errorCode => text().nullable()();
  TextColumn get errorMessage => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// When the download reached `completed`. Null until then.
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
