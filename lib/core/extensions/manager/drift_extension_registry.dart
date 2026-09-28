import 'package:drift/drift.dart';

import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/extensions/identity/source_node.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/extension_registry.dart';

/// Drift-backed implementation of [ExtensionRegistry].
///
/// All persistence goes through SPECTA's existing Drift/SQLite database.
/// No second database system is introduced.
class DriftExtensionRegistry implements ExtensionRegistry {
  DriftExtensionRegistry(this._db);

  final SpectaDatabase _db;

  @override
  Future<void> install(ExtensionRecord record) async {
    await _db
        .into(_db.extensions)
        .insertOnConflictUpdate(
          ExtensionsCompanion.insert(
            id: record.id,
            name: record.name,
            version: record.version,
            author: record.author,
            apiVersion: record.apiVersion,
            contractVersion: Value<String>(record.contractVersion),
            contentType: record.contentType,
            signature: Value<String?>(record.signature),
            trustLevel: record.trustLevel.code,
            enabled: Value<int>(record.enabled ? 1 : 0),
            filePath: record.filePath,
            installedAt: Value<DateTime>(record.installedAt),
            updatedAt: Value<DateTime>(record.updatedAt),
            previousVersionPath: Value<String?>(record.previousVersionPath),
            previousVersion: Value<String?>(record.previousVersion),
            nodeIndex: Value<int?>(record.node?.index),
            nodeSpace: Value<String?>(record.node?.spaceCode),
            nodeLocked: Value<int>(record.nodeLocked ? 1 : 0),
            nodeOrder: Value<int>(record.nodeOrder),
            lastSuccessAt: Value<DateTime?>(record.lastSuccessAt),
          ),
        );
  }

  @override
  Future<void> uninstall(String id) async {
    // Child rows go first.  The schema declares REFERENCES extensions(id) with
    // no ON DELETE action and specta_database.dart enables PRAGMA foreign_keys,
    // so deleting the extensions row while versions or failures still point at
    // it aborts with "FOREIGN KEY constraint failed".  One transaction keeps
    // the three deletes atomic, so a failure cannot leave a half-removed
    // extension behind.
    await _db.transaction(() async {
      await (_db.delete(
        _db.extensionVersions,
      )..where(($ExtensionVersionsTable t) => t.extensionId.equals(id))).go();
      await (_db.delete(_db.extensionFailureLogs)
            ..where(($ExtensionFailureLogsTable t) => t.extensionId.equals(id)))
          .go();
      await (_db.delete(
        _db.extensions,
      )..where(($ExtensionsTable t) => t.id.equals(id))).go();
    });
  }

  @override
  Future<ExtensionRecord?> getById(String id) async {
    final Extension? row = await (_db.select(
      _db.extensions,
    )..where(($ExtensionsTable t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toRecord(row);
  }

  @override
  Future<List<ExtensionRecord>> getAll() async {
    final List<Extension> rows = await _db.select(_db.extensions).get();
    return rows.map(_toRecord).toList();
  }

  @override
  Future<List<ExtensionRecord>> getEnabled() async {
    final List<Extension> rows = await (_db.select(
      _db.extensions,
    )..where(($ExtensionsTable t) => t.enabled.equals(1))).get();
    return rows.map(_toRecord).toList();
  }

  @override
  Future<void> setEnabled(String id, bool enabled) async {
    await (_db.update(
      _db.extensions,
    )..where(($ExtensionsTable t) => t.id.equals(id))).write(
      ExtensionsCompanion(
        enabled: Value<int>(enabled ? 1 : 0),
        updatedAt: Value<DateTime>(DateTime.now().toUtc()),
      ),
    );
  }

  @override
  Future<void> setNode(String id, SourceNode node) async {
    await (_db.update(
      _db.extensions,
    )..where(($ExtensionsTable t) => t.id.equals(id))).write(
      ExtensionsCompanion(
        nodeIndex: Value<int?>(node.index),
        nodeSpace: Value<String?>(node.spaceCode),
      ),
    );
  }

  @override
  Future<void> setNodeOrder(String id, int order) async {
    await (_db.update(
      _db.extensions,
    )..where(($ExtensionsTable t) => t.id.equals(id))).write(
      ExtensionsCompanion(nodeOrder: Value<int>(order)),
    );
  }

  @override
  Future<void> setLastSuccess(String id, DateTime at) async {
    // The monotonic guard lives HERE rather than relying on the write, because
    // the write below is unconditional: a column meaning "most recent success"
    // must never be moved backwards by an out-of-order clock. A test caught
    // this guard being missing on the Drift side while present in memory.
    final DateTime? previous = await _currentLastSuccess(id);
    if (previous != null && !at.isAfter(previous)) return;
    await (_db.update(
      _db.extensions,
    )..where(($ExtensionsTable t) => t.id.equals(id))).write(
      ExtensionsCompanion(
        lastSuccessAt: Value<DateTime?>(at),
        updatedAt: Value<DateTime>(at),
      ),
    );
  }

  /// Reads just the recorded success for [id], or null when there is none.
  Future<DateTime?> _currentLastSuccess(String id) async {
    final Extension? row = await (_db.select(
      _db.extensions,
    )..where(($ExtensionsTable t) => t.id.equals(id))).getSingleOrNull();
    return row?.lastSuccessAt;
  }

  @override
  Future<void> saveVersion(ExtensionVersionRecord record) async {
    await _db
        .into(_db.extensionVersions)
        .insert(
          ExtensionVersionsCompanion.insert(
            id: record.id,
            extensionId: record.extensionId,
            version: record.version,
            filePath: record.filePath,
            contractVersion: Value<String>(record.contractVersion),
            isCurrent: Value<int>(record.isCurrent ? 1 : 0),
            isRollbackPoint: Value<int>(record.isRollbackPoint ? 1 : 0),
            createdAt: Value<DateTime>(record.createdAt),
          ),
        );
  }

  @override
  Future<ExtensionVersionRecord?> getRollbackVersion(String extensionId) async {
    final ExtensionVersion? row =
        await (_db.select(_db.extensionVersions)
              ..where(
                ($ExtensionVersionsTable t) =>
                    t.extensionId.equals(extensionId) &
                    t.isRollbackPoint.equals(1) &
                    t.isCurrent.equals(0),
              )
              ..orderBy([(ref) => OrderingTerm.desc(ref.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _toVersionRecord(row);
  }

  @override
  Future<void> recordFailure(ExtensionFailureRecord record) async {
    await _db
        .into(_db.extensionFailureLogs)
        .insert(
          ExtensionFailureLogsCompanion.insert(
            id: record.id,
            extensionId: record.extensionId,
            failureType: record.failureType,
            operation: record.operation,
            message: record.message,
            detail: Value<String?>(record.detail),
            timestamp: Value<DateTime>(record.timestamp),
            retryable: Value<int>(record.retryable ? 1 : 0),
          ),
        );
  }

  @override
  Future<List<ExtensionFailureRecord>> getFailures(
    String extensionId, {
    int limit = 50,
  }) async {
    final List<ExtensionFailureLog> rows =
        await (_db.select(_db.extensionFailureLogs)
              ..where(
                ($ExtensionFailureLogsTable t) =>
                    t.extensionId.equals(extensionId),
              )
              ..orderBy([(ref) => OrderingTerm.desc(ref.timestamp)])
              ..limit(limit))
            .get();
    return rows.map(_toFailureRecord).toList();
  }

  @override
  Future<int> getFailureCount(
    String extensionId, {
    Duration since = const Duration(hours: 24),
  }) async {
    final List<ExtensionFailureLog> rows =
        await (_db.select(_db.extensionFailureLogs)..where(
              ($ExtensionFailureLogsTable t) =>
                  t.extensionId.equals(extensionId),
            ))
            .get();
    final DateTime cutoff = DateTime.now().toUtc().subtract(since);
    return rows
        .where((ExtensionFailureLog r) => r.timestamp.isAfter(cutoff))
        .length;
  }

  @override
  Future<void> clearFailures(String extensionId) async {
    await (_db.delete(_db.extensionFailureLogs)..where(
          ($ExtensionFailureLogsTable t) => t.extensionId.equals(extensionId),
        ))
        .go();
  }

  ExtensionRecord _toRecord(Extension row) {
    return ExtensionRecord(
      id: row.id,
      name: row.name,
      version: row.version,
      author: row.author,
      apiVersion: row.apiVersion,
      contractVersion: row.contractVersion,
      contentType: row.contentType,
      signature: row.signature,
      trustLevel: TrustLevel.fromCode(row.trustLevel) ?? TrustLevel.unverified,
      enabled: row.enabled == 1,
      filePath: row.filePath,
      installedAt: row.installedAt,
      updatedAt: row.updatedAt,
      previousVersionPath: row.previousVersionPath,
      previousVersion: row.previousVersion,
      node: SourceNode.fromCodes(row.nodeSpace, row.nodeIndex == null
          ? null
          : '${row.nodeIndex}'),
      nodeLocked: row.nodeLocked == 1,
      nodeOrder: row.nodeOrder,
      lastSuccessAt: row.lastSuccessAt,
    );
  }

  ExtensionVersionRecord _toVersionRecord(ExtensionVersion row) {
    return ExtensionVersionRecord(
      id: row.id,
      extensionId: row.extensionId,
      version: row.version,
      filePath: row.filePath,
      contractVersion: row.contractVersion,
      isCurrent: row.isCurrent == 1,
      isRollbackPoint: row.isRollbackPoint == 1,
      createdAt: row.createdAt,
    );
  }

  ExtensionFailureRecord _toFailureRecord(ExtensionFailureLog row) {
    return ExtensionFailureRecord(
      id: row.id,
      extensionId: row.extensionId,
      failureType: row.failureType,
      operation: row.operation,
      message: row.message,
      detail: row.detail,
      timestamp: row.timestamp,
      retryable: row.retryable == 1,
    );
  }
}
