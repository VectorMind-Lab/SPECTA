/// Narrow persistence contract for SPECTA settings.
///
/// Application code depends on this interface rather than on Drift directly,
/// so settings behaviour can be exercised without opening a database, and so
/// the storage engine stays an implementation detail.
abstract interface class SettingsStore {
  /// Value stored under [key], or null when absent.
  Future<String?> read(String key);

  /// Every stored setting.
  Future<Map<String, String>> readAll();

  /// Inserts or replaces the value stored under [key].
  Future<void> write(String key, String value);

  /// Removes [key] if present.
  Future<void> remove(String key);
}
