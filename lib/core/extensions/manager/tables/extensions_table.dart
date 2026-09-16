import 'package:drift/drift.dart';

/// Installed extensions and their current state.
///
/// Extensions never get direct database access — SPECTA persists their
/// metadata and reads it back.  Each row is one installed extension.
class Extensions extends Table {
  TextColumn get id => text()();

  TextColumn get name => text()();

  TextColumn get version => text()();

  TextColumn get author => text()();

  IntColumn get apiVersion => integer()();

  /// ExtensionContentType.code, e.g. `movies_series`.
  TextColumn get contentType => text()();

  /// Raw signature string from the manifest, or null when unsigned.
  TextColumn get signature => text().nullable()();

  /// TrustLevel.code: `official` or `unverified`.
  TextColumn get trustLevel => text()();

  /// Whether the extension is enabled.  Disabled extensions do not execute.
  IntColumn get enabled => integer().withDefault(const Constant(1))();

  /// On-disk path to the extension `.js` file.
  TextColumn get filePath => text()();

  DateTimeColumn get installedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  /// File path of the previous known-good version, kept for rollback.
  TextColumn get previousVersionPath => text().nullable()();

  /// Version string of the previous known-good version.
  TextColumn get previousVersion => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
