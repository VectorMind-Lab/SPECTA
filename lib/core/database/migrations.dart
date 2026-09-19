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
  static const int schemaVersion = 3;

  /// Migration step applied when moving *to* the keyed version.
  static final Map<int, Future<void> Function(Migrator m)> _steps =
      <int, Future<void> Function(Migrator m)>{
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
