import '../settings_store.dart';
import '../specta_database.dart';

/// Drift-backed implementation of [SettingsStore].
class SettingsDao implements SettingsStore {
  SettingsDao(this._db);

  final SpectaDatabase _db;

  @override
  Future<String?> read(String key) async {
    final SettingEntry? row =
        await (_db.select(_db.settingsEntries)
              ..where(($SettingsEntriesTable table) => table.key.equals(key)))
            .getSingleOrNull();
    return row?.value;
  }

  @override
  Future<Map<String, String>> readAll() async {
    final List<SettingEntry> rows = await _db.select(_db.settingsEntries).get();
    return <String, String>{
      for (final SettingEntry row in rows) row.key: row.value,
    };
  }

  @override
  Future<void> write(String key, String value) async {
    await _db
        .into(_db.settingsEntries)
        .insertOnConflictUpdate(
          SettingsEntriesCompanion.insert(key: key, value: value),
        );
  }

  @override
  Future<void> remove(String key) async {
    await (_db.delete(
      _db.settingsEntries,
    )..where(($SettingsEntriesTable table) => table.key.equals(key))).go();
  }
}
