import 'extension_record.dart';

/// Abstract interface for the local extension registry.
///
/// Tracks installed extensions, their versions (for rollback), and failure
/// history (for health tracking).  All persistence goes through the existing
/// Drift/SQLite database — no second database system is introduced.
abstract class ExtensionRegistry {
  /// Stores or replaces an extension's metadata.
  Future<void> install(ExtensionRecord record);

  /// Removes an extension and its version history.
  Future<void> uninstall(String id);

  /// Fetches a single extension by ID.
  Future<ExtensionRecord?> getById(String id);

  /// Returns all installed extensions (enabled and disabled).
  Future<List<ExtensionRecord>> getAll();

  /// Returns only enabled extensions.
  Future<List<ExtensionRecord>> getEnabled();

  /// Toggles the enabled flag for an extension.
  Future<void> setEnabled(String id, bool enabled);

  /// Saves a version snapshot for rollback support.
  Future<void> saveVersion(ExtensionVersionRecord record);

  /// Returns the most recent known-good previous version for rollback.
  Future<ExtensionVersionRecord?> getRollbackVersion(String extensionId);

  /// Records a failure for health tracking.
  Future<void> recordFailure(ExtensionFailureRecord record);

  /// Returns recent failures for an extension.
  Future<List<ExtensionFailureRecord>> getFailures(
    String extensionId, {
    int limit = 50,
  });

  /// Returns the count of failures within [since] (default: 24 hours).
  Future<int> getFailureCount(
    String extensionId, {
    Duration since = const Duration(hours: 24),
  });

  /// Removes all failure records for an extension (e.g. after a rollback).
  Future<void> clearFailures(String extensionId);
}
