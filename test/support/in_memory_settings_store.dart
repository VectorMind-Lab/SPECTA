import 'package:specta/core/database/settings_store.dart';

/// In-memory [SettingsStore] so settings behaviour is testable without opening
/// SQLite. It records how many writes happened, which lets tests assert that a
/// value was actually persisted rather than only held in memory.
class InMemorySettingsStore implements SettingsStore {
  final Map<String, String> _values = <String, String>{};

  int writeCount = 0;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<Map<String, String>> readAll() async =>
      Map<String, String>.of(_values);

  @override
  Future<void> write(String key, String value) async {
    writeCount++;
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}
