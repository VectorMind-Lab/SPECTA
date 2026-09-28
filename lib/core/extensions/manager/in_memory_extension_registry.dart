import 'dart:async';

import 'package:specta/core/extensions/identity/source_node.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/extension_registry.dart';

/// In-memory implementation of [ExtensionRegistry] for unit tests.
///
/// Mirrors the persistence semantics of [DriftExtensionRegistry] but stores
/// data in plain Dart collections — no SQLite, no file I/O.
class InMemoryExtensionRegistry implements ExtensionRegistry {
  final Map<String, ExtensionRecord> _extensions = <String, ExtensionRecord>{};
  final List<ExtensionVersionRecord> _versions = <ExtensionVersionRecord>[];
  final List<ExtensionFailureRecord> _failures = <ExtensionFailureRecord>[];

  @override
  Future<void> install(ExtensionRecord record) async {
    _extensions[record.id] = record;
  }

  @override
  Future<void> uninstall(String id) async {
    _extensions.remove(id);
    _versions.removeWhere((ExtensionVersionRecord v) => v.extensionId == id);
    _failures.removeWhere((ExtensionFailureRecord f) => f.extensionId == id);
  }

  @override
  Future<ExtensionRecord?> getById(String id) async {
    return _extensions[id];
  }

  @override
  Future<List<ExtensionRecord>> getAll() async {
    return _extensions.values.toList();
  }

  @override
  Future<List<ExtensionRecord>> getEnabled() async {
    return _extensions.values.where((ExtensionRecord r) => r.enabled).toList();
  }

  @override
  Future<void> setEnabled(String id, bool enabled) async {
    final ExtensionRecord? existing = _extensions[id];
    if (existing == null) return;
    _extensions[id] = existing.copyWith(
      enabled: enabled,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> setNode(String id, SourceNode node) async {
    final ExtensionRecord? existing = _extensions[id];
    if (existing == null) return;
    // Re-assigning the node a record already holds is a no-op, so a repeated
    // backfill can never walk a node onto a different extension.
    if (existing.node == node) return;
    _extensions[id] = existing.copyWith(node: node);
  }

  @override
  Future<void> setNodeOrder(String id, int order) async {
    final ExtensionRecord? existing = _extensions[id];
    if (existing == null) return;
    if (existing.nodeOrder == order) return;
    _extensions[id] = existing.copyWith(nodeOrder: order);
  }

  @override
  Future<void> saveVersion(ExtensionVersionRecord record) async {
    _versions.add(record);
  }

  @override
  Future<ExtensionVersionRecord?> getRollbackVersion(String extensionId) async {
    final List<ExtensionVersionRecord> candidates =
        _versions
            .where(
              (ExtensionVersionRecord v) =>
                  v.extensionId == extensionId &&
                  v.isRollbackPoint &&
                  !v.isCurrent,
            )
            .toList()
          ..sort(
            (ExtensionVersionRecord a, ExtensionVersionRecord b) =>
                b.createdAt.compareTo(a.createdAt),
          );
    return candidates.isEmpty ? null : candidates.first;
  }

  @override
  Future<void> recordFailure(ExtensionFailureRecord record) async {
    _failures.add(record);
  }

  @override
  Future<List<ExtensionFailureRecord>> getFailures(
    String extensionId, {
    int limit = 50,
  }) async {
    // Most recent first. `limit` must be applied to the sorted list, not to a
    // cascade: `..take(limit)..toList()` is a no-op, because a cascade discards
    // the intermediate iterable and returns the receiver.
    final List<ExtensionFailureRecord> matching =
        _failures
            .where((ExtensionFailureRecord f) => f.extensionId == extensionId)
            .toList()
          ..sort(
            (ExtensionFailureRecord a, ExtensionFailureRecord b) =>
                b.timestamp.compareTo(a.timestamp),
          );
    return matching.take(limit).toList();
  }

  @override
  Future<int> getFailureCount(
    String extensionId, {
    Duration since = const Duration(hours: 24),
  }) async {
    final DateTime cutoff = DateTime.now().toUtc().subtract(since);
    return _failures
        .where((ExtensionFailureRecord f) => f.extensionId == extensionId)
        .where((ExtensionFailureRecord f) => f.timestamp.isAfter(cutoff))
        .length;
  }

  @override
  Future<void> clearFailures(String extensionId) async {
    _failures.removeWhere(
      (ExtensionFailureRecord f) => f.extensionId == extensionId,
    );
  }

  // Convenience helpers for tests
  Iterable<ExtensionFailureRecord> allFailuresFor(String extensionId) =>
      _failures.where(
        (ExtensionFailureRecord f) => f.extensionId == extensionId,
      );

  TrustLevel? trustLevelOf(String extensionId) {
    final ExtensionRecord? record = _extensions[extensionId];
    return record?.trustLevel;
  }
}
