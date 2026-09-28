import 'package:drift/drift.dart';

/// Durable discovery provenance for a work — Phase 2F resume follow-up.
///
/// `watch_progress` deliberately stays lightweight (identity + position). To
/// resume a persisted item, the metadata layer must be re-run, and
/// `MetadataManager.metadataFor` needs a [DiscoveryItem] with its references.
/// This table stores exactly those references — the same values discovery
/// produced — so resume reconstructs the item deterministically instead of
/// searching by title (which could resolve the wrong media).
///
/// These are discovery/details reference URLs, NOT playback source URLs:
/// sources are always re-resolved through the current SourceManager.
/// Extensions never read or write this table.
@DataClassName('MediaReferenceRow')
class MediaReferences extends Table {
  @override
  String get tableName => 'media_references';

  /// Canonical work identity when identity_version = 2, otherwise null.
  TextColumn get canonicalId => text().nullable()();

  /// Identity scheme: 1 = legacy title key, 2 = provider canonical key.
  IntColumn get identityVersion => integer().withDefault(const Constant(1))();

  /// The work's canonical metadata key (the same identity watch progress uses).
  TextColumn get mediaKey => text()();

  /// First-seen order, preserved so resume re-queries references in the same
  /// order discovery observed them.
  IntColumn get ordinal => integer()();

  /// The contributing extension's registry id.
  TextColumn get extensionId => text()();

  /// The extension-internal reference the extension expects back through
  /// `details(url)`. Never a playback URL.
  TextColumn get referenceUrl => text()();

  @override
  Set<Column> get primaryKey => {mediaKey, ordinal};
}
