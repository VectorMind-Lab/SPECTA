import 'package:drift/drift.dart';

/// Minimal Phase 0 table: SPECTA settings are structured key/value state.
///
/// The schema stays deliberately small. Feature tables (library,
/// watch_progress, watch_history, downloads, extensions, extension_versions)
/// are added by the phases that introduce those features, one version bump at
/// a time — see [SpectaMigrations] and docs/PROJECT_STATE.txt.
@DataClassName('SettingEntry')
class SettingsEntries extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {key};
}
