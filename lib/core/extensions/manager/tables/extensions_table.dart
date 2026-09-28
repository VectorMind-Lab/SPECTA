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

  /// Contract revision declared by the manifest.
  TextColumn get contractVersion =>
      text().withDefault(const Constant('2.0.0'))();

  /// ExtensionContentType.code, e.g. `movies_series` or `anime`.
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

  // ---------------------------------------------------------------------------
  // Source node identity (schema v9).
  //
  // These four columns carry the installed source's NODE, not its name. They
  // are separate from everything above on purpose:
  //
  // * `nodeLabel`/`nodeSpace` are IDENTITY and are stable. Deleting Node 2 must
  //   not renumber Node 3, which is only guaranteed if the label is stored
  //   rather than recomputed from a list position.
  // * `nodeLocked` is the OWNER'S undeletable flag. It is deliberately NOT
  //   derived from `trustLevel`: a user who imports a SPECTA-signed file keeps
  //   their green dot but must not inherit the undeletable Node 0.
  // * `nodeOrder` is DISPLAY position only, and is the user's to rearrange.
  // ---------------------------------------------------------------------------

  /// The node's index WITHIN its space, or null when it has not been assigned
  /// yet (a row that predates v9).
  ///
  /// The INDEX is stored, not the display label, because the label is a pure
  /// function of `(nodeSpace, nodeIndex)` — see `SourceNode.label`. Storing the
  /// label instead would force every read to parse "Node AA" back into a number,
  /// which is lossy and would let a formatting change silently renumber a node.
  IntColumn get nodeIndex => integer().nullable()();

  /// Which numbering space the node belongs to: 'official' | 'user' | NULL.
  /// Decided by the install ROUTE, never by the signature.
  TextColumn get nodeSpace => text().nullable()();

  /// The owner's undeletable flag. Only the designated Node 0 ever has it.
  IntColumn get nodeLocked => integer().withDefault(const Constant(0))();

  /// Display position. The user may reorder freely, including moving Node 0.
  IntColumn get nodeOrder => integer().withDefault(const Constant(0))();

  // ---------------------------------------------------------------------------
  // Real activity (schema v10).
  //
  // `last_success_at` is written ONLY when a source actually completes an
  // operation. It is never set at install time, and never inferred.
  //
  // It exists so the Source Health screen can say "No data yet" HONESTLY. A
  // source that has never completed anything is a genuinely different thing
  // from one that succeeded twice and then broke, and the difference cannot be
  // reconstructed from the failure count alone - zero failures reads the same
  // for "never tried" and "working perfectly". NULL means "never recorded".
  // ---------------------------------------------------------------------------

  /// When this source last completed an operation, or null if it never has.
  DateTimeColumn get lastSuccessAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
