import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/identity/extension_health.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manifest.dart';

import 'extension_manager.dart';
import 'extension_record.dart';

/// One installed extension as the application layer sees it.
///
/// [ExtensionRecord] is the persisted installation state; [health] is the
/// descriptive classification SPECTA derives from facts it already holds
/// (enabled flag, API compatibility, recent failures). Bundling them in one
/// value keeps the UI and any future orchestration layer reading a single,
/// authoritative view instead of re-deriving health ad hoc.
final class ManagedExtension {
  const ManagedExtension({required this.record, required this.health});

  /// The validated, persisted installation record.
  final ExtensionRecord record;

  /// Descriptive health. Never a controller — see [ExtensionHealthRules].
  final ExtensionHealthState health;

  String get id => record.id;
  String get name => record.name;
  String get version => record.version;
  String get author => record.author;
  int get apiVersion => record.apiVersion;
  String get contentType => record.contentType;
  String get filePath => record.filePath;
  TrustLevel get trustLevel => record.trustLevel;
  bool get enabled => record.enabled;
  ExtensionHealth get healthState => health.health;
}

/// The application-facing boundary for extension installation and lifecycle.
///
/// This is deliberately a thin wrapper over [ExtensionManager]: the manager
/// remains the single owner of manifest validation, trust classification,
/// runtime creation and persistence. The service exists so that UI state and
/// future orchestration code depend on an application-level contract
/// (install / list / enable / disable / uninstall / shutdown) rather than
/// re-implementing those steps — and so nothing outside the manager can
/// bypass manifest validation or signature verification.
///
/// It never touches files itself: [installFromFile] hands the path to the
/// manager, which reads, parses, validates, verifies the signature, checks API
/// compatibility and only then persists. A malformed or untrusted file never
/// reaches the registry (a malformed one is rejected outright; an unsigned or
/// badly signed one is installed as [TrustLevel.unverified], never Official).
final class ExtensionLifecycleService {
  const ExtensionLifecycleService({required this.manager});

  final ExtensionManager manager;

  /// Installs (or replaces) an extension from a local `.js` file.
  ///
  /// Returns the installed record, or a structured failure describing exactly
  /// why the file was rejected. Failure is safe: the registry is left
  /// untouched unless the file passed every gate.
  Future<SpectaResult<ExtensionRecord>> installFromFile(String filePath) =>
      manager.importExtension(filePath: filePath);

  /// Returns every installed extension (enabled and disabled), each with its
  /// derived health, in a deterministic order (name, then id).
  Future<List<ManagedExtension>> installed() async {
    final List<ExtensionRecord> records = await manager.getAllExtensions();
    final List<ManagedExtension> managed = <ManagedExtension>[];
    for (final ExtensionRecord record in records) {
      final SpectaResult<ExtensionHealthState> health = await manager.healthOf(
        record.id,
      );
      managed.add(
        ManagedExtension(
          record: record,
          health: health.valueOrNull ?? _fallbackHealth(record),
        ),
      );
    }
    managed.sort((ManagedExtension a, ManagedExtension b) {
      final int byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    return managed;
  }

  /// Enables or disables an extension. Persisted, and enforced by the manager.
  Future<void> setEnabled(String id, bool enabled) =>
      manager.setEnabled(id, enabled);

  /// Permanently removes an extension and retires its runtime.
  Future<void> uninstall(String id) => manager.uninstall(id);

  /// Shuts down every live runtime. Used when the application is torn down.
  Future<void> shutdownAll() => manager.shutdownAll();

  /// Health classification used only if the manager cannot answer for a record
  /// it just returned. Pure fallback; it must never mask a real failure.
  static ExtensionHealthState _fallbackHealth(ExtensionRecord record) {
    return ExtensionHealthState(
      health: ExtensionHealthRules.evaluate(
        enabled: record.enabled,
        apiCompatible: SpectaApiVersion.isCompatible(record.apiVersion),
        recentFailureCount: 0,
      ),
      recentFailureCount: 0,
      apiVersion: record.apiVersion,
    );
  }
}
