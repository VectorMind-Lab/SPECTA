import 'dart:io';

import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';

import 'package:specta/core/extensions/identity/extension_health.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manifest.dart';
import 'package:specta/core/extensions/runtime/extension_runtime.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';
import 'package:specta/core/extensions/verification/signature_verifier.dart';

import 'extension_record.dart';
import 'extension_registry.dart';

/// High-level coordinator for extension lifecycle management.
///
/// Orchestrates:
///   Catalogue discovery → Manifest validation → Signature verification →
///   API compatibility check → Installation → Enable/Disable →
///   Runtime loading → Operations → Health monitoring → Failure tracking →
///   Update / Rollback
///
/// The manager is the SINGLE entry point consumers use.  It hides the
/// details of manifest parsing, signature verification, the JS runtime, and
/// the registry behind a clean Dart API.
class ExtensionManager {
  ExtensionManager({
    required this._registry,
    this._runtimeApi,
    this._sandboxFactory,
    SignatureVerifier? verifier,
  }) : _verifier = verifier ?? SignatureVerifier.instance;

  final ExtensionRegistry _registry;
  final ExtensionRuntimeApi? _runtimeApi;
  final ExtensionJsSandbox Function()? _sandboxFactory;

  /// Verifies extension signatures. Defaults to the verifier bound to SPECTA's
  /// published public key; tests inject one bound to a throwaway key, because
  /// the production private key is intentionally not in this repository.
  final SignatureVerifier _verifier;

  /// Identity used for failures raised before an extension's own id is known
  /// (while the source file is being read or its manifest parsed). It is a
  /// sentinel, never a real extension id.
  static const String unidentifiedExtension = '<unidentified>';

  /// Runtime instances keyed by extension ID.
  final Map<String, ExtensionRuntime> _runtimes = <String, ExtensionRuntime>{};

  /// Import a `.js` extension from local storage.
  ///
  /// Flow: Parse manifest → Validate → Verify signature → Classify trust →
  /// Check API compatibility → Store metadata.
  Future<SpectaResult<ExtensionRecord>> importExtension({
    required String filePath,
  }) async {
    late final String jsCode;
    try {
      jsCode = await File(filePath).readAsString();
    } catch (e) {
      return Err<ExtensionRecord>(
        _buildFailure(
          type: ExtensionFailureType.parseError,
          message: 'Cannot read extension file: $filePath',
          extensionId: unidentifiedExtension,
          detail: e.toString(),
          operation: 'import',
        ),
      );
    }

    return _processManifest(
      jsCode: jsCode,
      targetPath: filePath,
      recordId: null,
    );
  }

  /// Import a `.js` extension from raw source code (for tests / catalogue).
  Future<SpectaResult<ExtensionRecord>> importFromSource({
    required String extensionId,
    required String jsCode,
    required String targetPath,
  }) async {
    return _processManifest(
      jsCode: jsCode,
      targetPath: targetPath,
      recordId: extensionId,
    );
  }

  Future<SpectaResult<ExtensionRecord>> _processManifest({
    required String jsCode,
    required String targetPath,
    required String? recordId,
  }) async {
    late final ExtensionManifest manifest;
    try {
      manifest = ManifestParser.parse(jsCode);
    } on ManifestParseException catch (e) {
      return Err<ExtensionRecord>(
        _buildFailure(
          type: ExtensionFailureType.invalidResult,
          message: 'Manifest parsing failed: ${e.message}',
          extensionId: recordId ?? unidentifiedExtension,
          operation: 'import',
        ),
      );
    }

    if (!manifest.isApiCompatible) {
      return Err<ExtensionRecord>(
        _buildFailure(
          type: ExtensionFailureType.unsupported,
          message:
              'Extension API version ${manifest.apiVersion} is not supported. '
              'SPECTA requires API version ${SpectaApiVersion.current}.',
          extensionId: manifest.id,
          operation: 'import',
        ),
      );
    }

    final TrustLevel trustLevel = await _classifyTrust(
      manifest,
      ManifestParser.extractBody(jsCode),
    );

    final DateTime now = DateTime.now().toUtc();
    final ExtensionRecord record = ExtensionRecord(
      id: recordId ?? manifest.id,
      name: manifest.name,
      version: manifest.version,
      author: manifest.author,
      apiVersion: manifest.apiVersion,
      contentType: manifest.type.code,
      signature: manifest.signature,
      trustLevel: trustLevel,
      enabled: true,
      filePath: targetPath,
      installedAt: now,
      updatedAt: now,
    );

    await _registry.install(record);
    return Ok<ExtensionRecord>(record);
  }

  /// Classifies trust by verifying the manifest signature.
  ///
  /// The signed payload covers both the canonical manifest metadata AND the
  /// extension's JavaScript body (see [SpectaSigningProtocol]), so replacing the
  /// executable code while keeping the manifest invalidates the signature.
  /// Classification never rejects an import: an extension with a missing or
  /// invalid signature is [TrustLevel.unverified], which is data a later policy
  /// layer can act on.
  Future<TrustLevel> _classifyTrust(
    ExtensionManifest manifest,
    String extensionBody,
  ) async {
    if (!manifest.hasSignature) return TrustLevel.unverified;

    final bool valid = await _verifier.verify(
      message: manifest.buildSignedPayload(extensionBody: extensionBody),
      signature: manifest.signature,
    );
    return valid ? TrustLevel.official : TrustLevel.unverified;
  }

  /// Permanently removes an extension.
  Future<void> uninstall(String id) async {
    final ExtensionRuntime? existing = _runtimes.remove(id);
    if (existing != null) {
      await existing.shutdown();
    }
    await _registry.uninstall(id);
  }

  /// Enables or disables an extension.
  ///
  /// Disabled extensions do not participate in execution.
  Future<void> setEnabled(String id, bool enabled) async {
    await _registry.setEnabled(id, enabled);
    if (!enabled && _runtimes.containsKey(id)) {
      await _runtimes.remove(id)!.shutdown();
    }
  }

  /// Returns all installed extensions.
  Future<List<ExtensionRecord>> getAllExtensions() => _registry.getAll();

  /// Returns only enabled extensions.
  Future<List<ExtensionRecord>> getEnabledExtensions() =>
      _registry.getEnabled();

  /// Returns an extension by ID.
  Future<ExtensionRecord?> getExtension(String id) => _registry.getById(id);

  /// Loads an extension into a JS runtime.
  ///
  /// The runtime is kept alive until [shutdown], [uninstall], or the
  /// extension is disabled.
  Future<SpectaResult<ExtensionRuntime>> loadRuntime(String id) async {
    final ExtensionRecord? record = await _registry.getById(id);
    if (record == null) {
      return Err<ExtensionRuntime>(
        _buildFailure(
          type: ExtensionFailureType.invalidResult,
          message: 'Extension not found: $id',
          extensionId: id,
          operation: 'load',
        ),
      );
    }

    if (!record.enabled) {
      return Err<ExtensionRuntime>(
        _buildFailure(
          type: ExtensionFailureType.capabilityError,
          message: 'Extension is disabled: $id',
          extensionId: id,
          operation: 'load',
        ),
      );
    }

    if (_runtimeApi == null) {
      return Err<ExtensionRuntime>(
        _buildFailure(
          type: ExtensionFailureType.capabilityError,
          message: 'No runtime API handler provided',
          extensionId: id,
          operation: 'load',
        ),
      );
    }

    if (_sandboxFactory == null) {
      return Err<ExtensionRuntime>(
        _buildFailure(
          type: ExtensionFailureType.capabilityError,
          message: 'No sandbox factory provided',
          extensionId: id,
          operation: 'load',
        ),
      );
    }

    late final String jsCode;
    try {
      jsCode = await File(record.filePath).readAsString();
    } catch (e) {
      return Err<ExtensionRuntime>(
        _buildFailure(
          type: ExtensionFailureType.runtimeError,
          message: 'Cannot read extension file: ${record.filePath}',
          extensionId: id,
          detail: e.toString(),
          operation: 'load',
        ),
      );
    }

    // The granted capability set is re-read from the file being loaded rather
    // than taken from the stored record, so what is granted always matches the
    // code that is about to run. A manifest that no longer parses fails the
    // load instead of silently granting nothing.
    final ExtensionManifest manifest;
    try {
      manifest = ManifestParser.parse(jsCode);
    } on ManifestParseException catch (e) {
      return Err<ExtensionRuntime>(
        _buildFailure(
          type: ExtensionFailureType.invalidResult,
          message: 'Extension manifest is no longer valid: ${e.message}',
          extensionId: id,
          operation: 'load',
        ),
      );
    }

    final ExtensionRuntime runtime = ExtensionRuntime(
      sandbox: _sandboxFactory(),
      api: _runtimeApi,
      capabilities: manifest.capabilities,
    );

    final SpectaResult<void> loadResult = await runtime.loadExtension(
      extensionId: id,
      jsCode: jsCode,
    );

    if (loadResult.isErr) {
      // Failure isolation: a runtime that failed to load is never published to
      // _runtimes, so nothing else will ever shut it down. Its sandbox owns a
      // live JS engine, so it has to be disposed here or the engine leaks for
      // the rest of the process lifetime.
      await runtime.shutdown();

      final SpectaFailure failure = loadResult.failureOrNull!;
      await _registry.recordFailure(
        ExtensionFailureRecord(
          id: '${id}_${DateTime.now().toUtc().toIso8601String()}',
          extensionId: id,
          failureType: failure is ExtensionFailure
              ? failure.type.code
              : 'RUNTIME_ERROR',
          operation: failure is ExtensionFailure ? failure.operation : 'load',
          message: failure.message,
          detail: failure is ExtensionFailure
              ? failure.detail
              : failure.toString(),
          timestamp: DateTime.now().toUtc(),
          retryable: failure.isRetryable,
        ),
      );
      return Err<ExtensionRuntime>(
        failure is ExtensionFailure
            ? failure
            : ExtensionFailure(
                extensionId: id,
                operation: 'load',
                type: ExtensionFailureType.runtimeError,
                message: failure.message,
                timestamp: DateTime.now().toUtc(),
                detail: failure.toString(),
              ),
      );
    }

    _runtimes[id] = runtime;
    return Ok<ExtensionRuntime>(runtime);
  }

  /// Calls an operation on a loaded runtime.
  Future<SpectaResult<T>> callOperation<T>(
    String id,
    Future<SpectaResult<T>> Function(ExtensionRuntime runtime) operation,
  ) async {
    final ExtensionRuntime? runtime = _runtimes[id];
    if (runtime == null) {
      return Err<T>(
        _buildFailure(
          type: ExtensionFailureType.runtimeError,
          message: 'Extension runtime not loaded: $id',
          extensionId: id,
          operation: 'operation',
        ),
      );
    }
    return operation(runtime);
  }

  /// Runs a health check on a loaded extension and records the result.
  Future<bool> healthCheck(String id) async {
    final ExtensionRuntime? runtime = _runtimes[id];
    if (runtime == null) return false;

    final SpectaResult<bool> result = await runtime.healthCheck();
    if (result.isErr) {
      final SpectaFailure failure = result.failureOrNull!;
      await _registry.recordFailure(
        ExtensionFailureRecord(
          id: '${id}_health_${DateTime.now().toUtc().toIso8601String()}',
          extensionId: id,
          failureType: failure is ExtensionFailure
              ? failure.type.code
              : 'RUNTIME_ERROR',
          operation: failure is ExtensionFailure
              ? failure.operation
              : 'healthCheck',
          message: failure.message,
          timestamp: DateTime.now().toUtc(),
          retryable: failure.isRetryable,
        ),
      );
      return false;
    }
    return result.valueOrNull ?? false;
  }

  /// Shuts down a single extension's runtime.
  Future<void> shutdown(String id) async {
    final ExtensionRuntime? runtime = _runtimes.remove(id);
    if (runtime == null) return;
    await runtime.shutdown();
  }

  /// Shuts down ALL loaded runtimes.
  Future<void> shutdownAll() async {
    for (final String id in _runtimes.keys.toList()) {
      await shutdown(id);
    }
  }

  /// Rolls back an extension to its previous known-good version.
  ///
  /// Returns true if a rollback version was found and restored.
  Future<bool> rollback(String id) async {
    final ExtensionVersionRecord? previous = await _registry.getRollbackVersion(
      id,
    );
    if (previous == null) return false;

    final ExtensionRecord? current = await _registry.getById(id);
    if (current == null) return false;

    final DateTime now = DateTime.now().toUtc();
    await _registry.install(
      current.copyWith(
        filePath: previous.filePath,
        version: previous.version,
        updatedAt: now,
        previousVersionPath: () => null,
        previousVersion: () => null,
      ),
    );

    final ExtensionRuntime? removed = _runtimes.remove(id);
    if (removed != null) {
      await removed.shutdown();
    }
    return true;
  }

  /// Classifies an extension's health from the facts SPECTA already holds.
  ///
  /// Descriptive only — it changes nothing. In particular it never disables an
  /// extension: [ExtensionHealth.temporarilyUnavailable] reports a high recent
  /// failure count so a caller can prefer another source, but the extension
  /// stays enabled and loadable. See [ExtensionHealthRules].
  Future<SpectaResult<ExtensionHealthState>> healthOf(String id) async {
    final ExtensionRecord? record = await _registry.getById(id);
    if (record == null) {
      return Err<ExtensionHealthState>(
        _buildFailure(
          type: ExtensionFailureType.invalidResult,
          message: 'Extension not found: $id',
          extensionId: id,
          operation: 'health',
        ),
      );
    }

    final int recentFailures = await _registry.getFailureCount(
      id,
      since: ExtensionHealthRules.failureWindow,
    );

    return Ok<ExtensionHealthState>(
      ExtensionHealthState(
        health: ExtensionHealthRules.evaluate(
          enabled: record.enabled,
          apiCompatible: SpectaApiVersion.isCompatible(record.apiVersion),
          recentFailureCount: recentFailures,
        ),
        recentFailureCount: recentFailures,
        apiVersion: record.apiVersion,
      ),
    );
  }

  /// Records a failure for health tracking.
  Future<void> recordFailure(ExtensionFailureRecord record) async {
    await _registry.recordFailure(record);
  }

  /// Returns recent failures for an extension.
  Future<List<ExtensionFailureRecord>> getFailures(String id) =>
      _registry.getFailures(id);

  /// Returns the failure count within [since] (default 24h).
  Future<int> getFailureCount(
    String id, {
    Duration since = const Duration(hours: 24),
  }) => _registry.getFailureCount(id, since: since);

  ExtensionFailure _buildFailure({
    required ExtensionFailureType type,
    required String message,
    required String extensionId,
    String? detail,
    required String operation,
  }) {
    return ExtensionFailure(
      extensionId: extensionId,
      operation: operation,
      type: type,
      message: message,
      timestamp: DateTime.now().toUtc(),
      detail: detail,
    );
  }
}
