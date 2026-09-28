import '../discovery/discovery_models.dart';
import 'watch_progress.dart';

/// Narrow persistence contract for the SPECTA library (Phase 2F).
///
/// Application code depends on this interface, not on Drift, so library
/// behaviour can be exercised against an in-memory database and so the storage
/// engine stays an implementation detail — the same discipline as
/// [SettingsStore].
///
/// Continue Watching and History are two ORDERED QUERIES over the single
/// progress table, not two duplicated stores. See docs/PHASE_2F_REPORT.md.
abstract interface class LibraryStore {
  /// Inserts or replaces the record for [progress]'s identity.
  ///
  /// The identity is the primary key, so a write can never create a second row
  /// for the same movie/episode.
  Future<void> upsert(WatchProgress progress);

  /// The stored record for [id], or null when nothing was reported yet.
  Future<WatchProgress?> progressFor(String id);

  /// In-progress items (not completed, position > 0), most recent first.
  Future<List<WatchProgress>> continueWatching({int limit = 20});

  /// Every known item, most recently updated first.
  Future<List<WatchProgress>> history({int limit = 50});

  /// Removes one record. Idempotent.
  Future<void> remove(String id);

  /// Removes every record. Used by tests and by an explicit user clear.
  Future<void> clear();

  /// Replaces the durable discovery provenance for [mediaKey].
  ///
  /// Reuses the discovery layer's [DiscoveryReference] — no second reference
  /// model. The set is REPLACED (not appended) so a work always resolves
  /// through the references its most recent playback actually used.
  Future<void> saveReferences(
    String mediaKey,
    List<DiscoveryReference> references, {
    String? canonicalId,
    int identityVersion = 1,
  });

  /// The stored provenance for [mediaKey], in first-seen order. Empty when
  /// none was recorded (e.g. progress written before this feature).
  Future<List<DiscoveryReference>> referencesFor(String mediaKey);
}
