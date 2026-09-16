import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'migrations.dart';
import 'tables/settings_entries.dart';

import 'package:specta/core/extensions/manager/tables/extensions_table.dart';
import 'package:specta/core/extensions/manager/tables/extension_versions_table.dart';
import 'package:specta/core/extensions/manager/tables/extension_failure_logs_table.dart';

part 'specta_database.g.dart';

/// SPECTA's structured local database.
///
/// Drift over SQLite, owned entirely by the application. Extensions never get
/// database access: they discover content, SPECTA persists it.
///
/// The executable opens with no argument; tests inject an in-memory executor.
@DriftDatabase(
  tables: <Type>[
    SettingsEntries,
    Extensions,
    ExtensionVersions,
    ExtensionFailureLogs,
  ],
)
class SpectaDatabase extends _$SpectaDatabase {
  SpectaDatabase([QueryExecutor? executor])
    : super(executor ?? _openDefaultExecutor());

  @override
  int get schemaVersion => SpectaMigrations.schemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      await SpectaMigrations.apply(m, from: from, to: to);
    },
    beforeOpen: (OpeningDetails details) async {
      // Foreign keys are enforced by SPECTA itself, never assumed.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static QueryExecutor _openDefaultExecutor() => driftDatabase(name: 'specta');
}
