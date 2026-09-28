import 'package:drift/drift.dart';

/// Ordered, additive schema migrations.
///
/// Each future schema version adds exactly one entry to [_steps], so an
/// installed database is always upgraded along a known path. If the database
/// on disk is newer than this build knows about, the upgrade fails loudly
/// instead of running queries against a schema the code does not match.
abstract final class SpectaMigrations {
  /// Schema version created by this build.
  ///
  /// Phase 0 = v1 (settings_entries).
  /// Phase 1 = v2 (extensions, extension_versions, extension_failures).
  /// Phase 2F = v3 (watch_progress: library / history / watch progress).
  /// Phase 2F resume follow-up = v4 (media_references: durable provenance).
  /// Phase 2G = v5 (downloads: durable download records / queue).
  /// Metadata catalogue cache = v6 (persistent TMDB/TVMaze TTL payloads).
  /// Contract metadata = v7 (extension contract revision).
  /// Canonical identity metadata = v8 (provider identity columns).
  /// Source node identity = v9 (node label / space / locked / order).
  static const int schemaVersion = 10;

  /// Migration step applied when moving *to* the keyed version.
  static final Map<int, Future<void> Function(Migrator m)>
  _steps = <int, Future<void> Function(Migrator m)>{
    2: (Migrator m) async {
      await m.database.customStatement('''
        CREATE TABLE extensions (
          id TEXT NOT NULL,
          name TEXT NOT NULL,
          version TEXT NOT NULL,
          author TEXT NOT NULL,
          api_version INTEGER NOT NULL,
          content_type TEXT NOT NULL,
          signature TEXT,
          trust_level TEXT NOT NULL,
          enabled INTEGER NOT NULL DEFAULT 1,
          file_path TEXT NOT NULL,
          installed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          previous_version_path TEXT,
          previous_version TEXT,
          PRIMARY KEY (id)
        )
      ''');

      await m.database.customStatement('''
        CREATE TABLE extension_versions (
          id TEXT NOT NULL,
          extension_id TEXT NOT NULL,
          version TEXT NOT NULL,
          file_path TEXT NOT NULL,
          is_current INTEGER NOT NULL DEFAULT 0,
          is_rollback_point INTEGER NOT NULL DEFAULT 1,
          created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (id),
          FOREIGN KEY (extension_id) REFERENCES extensions (id)
        )
      ''');

      await m.database.customStatement('''
        CREATE TABLE extension_failure_logs (
          id TEXT NOT NULL,
          extension_id TEXT NOT NULL,
          failure_type TEXT NOT NULL,
          operation TEXT NOT NULL,
          message TEXT NOT NULL,
          detail TEXT,
          timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          retryable INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (id),
          FOREIGN KEY (extension_id) REFERENCES extensions (id)
        )
      ''');
    },
    3: (Migrator m) async {
      // Phase 2F — persistent watch progress. Additive only: no existing
      // table is touched, so an installed v2 database upgrades in place.
      // Column names match Drift's generated table exactly (snake_case of
      // the Dart getters) so both the migration path and the fresh
      // `createAll()` path produce the same schema.
      await m.database.customStatement('''
        CREATE TABLE watch_progress (
          id TEXT NOT NULL,
          media_key TEXT NOT NULL,
          media_type TEXT NOT NULL,
          title TEXT NOT NULL,
          subtitle_line TEXT,
          season_number INTEGER,
          episode_number INTEGER,
          position_ms INTEGER NOT NULL DEFAULT 0,
          duration_ms INTEGER,
          elapsed_ms INTEGER NOT NULL DEFAULT 0,
          completed INTEGER NOT NULL DEFAULT 0,
          updated_at DATETIME NOT NULL,
          PRIMARY KEY (id)
        )
      ''');
    },
    4: (Migrator m) async {
      // Phase 2F resume follow-up — durable discovery provenance so a
      // persisted Continue Watching item can be re-opened through the
      // metadata layer without a title search. Additive only.
      await m.database.customStatement('''
        CREATE TABLE media_references (
          media_key TEXT NOT NULL,
          ordinal INTEGER NOT NULL,
          extension_id TEXT NOT NULL,
          reference_url TEXT NOT NULL,
          PRIMARY KEY (media_key, ordinal)
        )
      ''');
    },
    5: (Migrator m) async {
      // Phase 2G — durable download records. Additive only: no existing
      // table is touched, so an installed v4 database upgrades in place.
      // Column names match Drift's generated table exactly (snake_case of
      // the Dart getters) so both the migration path and the fresh
      // `createAll()` path produce the same schema.
      //
      // Identity = the playback identity (media key, episode-qualified for
      // episodes). No source URL is stored: recovery re-resolves through
      // the current SourceManager using the stored provenance.
      await m.database.customStatement('''
        CREATE TABLE downloads (
          id TEXT NOT NULL,
          media_key TEXT NOT NULL,
          media_type TEXT NOT NULL,
          title TEXT NOT NULL,
          subtitle_line TEXT,
          season_number INTEGER,
          episode_number INTEGER,
          state TEXT NOT NULL,
          wait_reason TEXT,
          bytes_downloaded INTEGER NOT NULL DEFAULT 0,
          total_bytes INTEGER,
          file_path TEXT NOT NULL,
          source_extension_id TEXT,
          source_reference TEXT,
          source_label TEXT,
          attempt INTEGER NOT NULL DEFAULT 0,
          error_code TEXT,
          error_message TEXT,
          created_at DATETIME NOT NULL,
          updated_at DATETIME NOT NULL,
          completed_at DATETIME,
          PRIMARY KEY (id)
        )
      ''');
    },
    6: (Migrator m) async {
      await m.database.customStatement('''
        CREATE TABLE metadata_cache (
          source TEXT NOT NULL,
          media_key TEXT NOT NULL,
          payload TEXT NOT NULL,
          expires_at DATETIME NOT NULL,
          updated_at DATETIME NOT NULL,
          PRIMARY KEY (source, media_key)
        )
      ''');
    },
    7: (Migrator m) async {
      await m.database.customStatement(
        "ALTER TABLE extensions ADD COLUMN contract_version TEXT NOT NULL DEFAULT '2.0.0'",
      );
      await m.database.customStatement(
        "ALTER TABLE extension_versions ADD COLUMN contract_version TEXT NOT NULL DEFAULT '2.0.0'",
      );
    },
    8: (Migrator m) async {
      for (final String table in <String>[
        'watch_progress',
        'downloads',
        'media_references',
      ]) {
        await m.database.customStatement(
          'ALTER TABLE $table ADD COLUMN canonical_id TEXT',
        );
        await m.database.customStatement(
          'ALTER TABLE $table ADD COLUMN identity_version INTEGER NOT NULL DEFAULT 1',
        );
      }
    },
    9: (Migrator m) async {
      // Source node identity. Additive only: no existing column is dropped or
      // rewritten, so every installed extension, every rollback version and
      // every failure log survives the upgrade untouched.
      //
      // `node_label` and `node_space` are left NULL on purpose. A NULL label
      // means "not assigned yet"; the lifecycle service backfills it once, in a
      // deterministic order, and then it is stable forever. Backfilling inside
      // the migration would have to guess at a numbering policy, and would make
      // the numbering depend on upgrade timing.
      await m.database.customStatement(
        'ALTER TABLE extensions ADD COLUMN node_index INTEGER',
      );
      await m.database.customStatement(
        'ALTER TABLE extensions ADD COLUMN node_space TEXT',
      );
      // `node_locked` is the owner's undeletable flag and is NOT derived from
      // `trust_level`. Every pre-existing row defaults to 0, so nothing that was
      // already installed becomes unexpectedly undeletable just by upgrading.
      await m.database.customStatement(
        'ALTER TABLE extensions ADD COLUMN node_locked INTEGER NOT NULL DEFAULT 0',
      );
      await m.database.customStatement(
        'ALTER TABLE extensions ADD COLUMN node_order INTEGER NOT NULL DEFAULT 0',
      );
    },
    10: (Migrator m) async {
      // Real activity, used by the Source Health screen.
      //
      // Additive and NULLABLE on purpose. Every existing row lands as NULL,
      // which is the honest value: a source installed before this column
      // existed has no recorded success, and SPECTA will not invent one to make
      // the screen look better. Those sources honestly read "No data yet" until
      // they actually complete something.
      await m.database.customStatement(
        'ALTER TABLE extensions ADD COLUMN last_success_at INTEGER',
      );
    },
  };

  /// Applies every step needed to move from [from] to [to].
  static Future<void> apply(
    Migrator m, {
    required int from,
    required int to,
  }) async {
    if (to < from) {
      throw StateError(
        'Refusing to migrate backwards: database is at v$from but this build '
        'is at v$to. Upgrade SPECTA instead of downgrading it.',
      );
    }
    for (int version = from + 1; version <= to; version++) {
      final Future<void> Function(Migrator m)? step = _steps[version];
      if (step == null) {
        throw StateError(
          'No migration is registered for schema version $version. '
          'Register the step before shipping this version to users.',
        );
      }
      await step(m);
    }
  }
}
