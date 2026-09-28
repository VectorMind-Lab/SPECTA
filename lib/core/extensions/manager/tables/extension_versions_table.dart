import 'package:drift/drift.dart';

import 'extensions_table.dart';

/// Version history for extensions, supporting rollback.
///
/// When an extension is updated, the previous known-good version's metadata is
/// copied here so it can be restored if the update proves broken.
class ExtensionVersions extends Table {
  TextColumn get id => text()();

  /// References [Extensions.id].
  TextColumn get extensionId => text().references(Extensions, #id)();

  TextColumn get version => text()();

  /// File path of this version's extension `.js` file.
  TextColumn get filePath => text()();

  /// Contract revision active for this saved extension version.
  TextColumn get contractVersion =>
      text().withDefault(const Constant('2.0.0'))();

  /// Whether this is the currently active version.
  IntColumn get isCurrent => integer().withDefault(const Constant(0))();

  /// Whether this version passed health checks (known-good).
  IntColumn get isRollbackPoint => integer().withDefault(const Constant(1))();

  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}
