import 'download_models.dart';

/// Narrow persistence contract for the download queue (Phase 2G).
///
/// Application code depends on this interface, not on Drift, so queue
/// behaviour can be exercised against an in-memory store and the storage
/// engine stays an implementation detail — the same discipline as
/// [SettingsStore] and the library store.
abstract interface class DownloadStore {
  /// Every stored record, oldest-queued first (creation order), so the queue
  /// replays FIFO order after a restart.
  Future<List<DownloadRecord>> all();

  /// The stored record for [id], or null when never enqueued.
  Future<DownloadRecord?> recordFor(String id);

  /// Inserts or replaces the record for [id]. The identity is the primary
  /// key, so a write can never create a second row for the same media.
  Future<void> upsert(DownloadRecord record);

  /// Removes the record. Idempotent.
  Future<void> remove(String id);

  /// Removes every record. Used by tests and an explicit user clear.
  Future<void> clear();
}
