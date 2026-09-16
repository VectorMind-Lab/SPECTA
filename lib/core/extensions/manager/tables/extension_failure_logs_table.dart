import 'package:drift/drift.dart';

import 'extensions_table.dart';

/// Records of extension failures, used for health tracking and source ranking.
///
/// Each row is one observed failure.  Repeated failures allow SPECTA to
/// downgrade or disable an extension before the user notices.
///
/// The data class is generated as `ExtensionFailureLog` to avoid colliding
/// with [specta_failure.dart]'s [ExtensionFailure] error model.
class ExtensionFailureLogs extends Table {
  TextColumn get id => text()();

  /// References [Extensions.id].
  TextColumn get extensionId => text().references(Extensions, #id)();

  /// The ExtensionFailureType.code that was recorded.
  TextColumn get failureType => text()();

  /// The contract operation that failed (search, getSources, ...).
  TextColumn get operation => text()();

  /// Human-readable, non-technical summary.
  TextColumn get message => text()();

  /// Developer-only diagnostics.  Never rendered on user screens.
  TextColumn get detail => text().nullable()();

  DateTimeColumn get timestamp =>
      dateTime().clientDefault(() => DateTime.now())();

  /// Whether retrying the same operation can plausibly succeed.
  IntColumn get retryable => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
