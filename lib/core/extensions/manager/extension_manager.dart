import 'dart:io';

import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';

import 'package:specta/core/extensions/distribution/extension_storage.dart';
import 'package:specta/core/extensions/identity/extension_health.dart';
import 'package:specta/core/extensions/identity/source_node.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manifest.dart';
import 'package:specta/core/extensions/runtime/extension_runtime.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';
import 'package:specta/core/extensions/verification/signature_verifier.dart';

import 'extension_record.dart';
import 'extension_registry.dart';

/// What a completed delete actually did.
///
/// Returned so the caller can be honest: a row can be gone while the bytes
/// survive (an unreadable file, or one outside app-private storage that the
/// guard refused to touch). Collapsing both cases into `void` would let the UI
/// claim a clean delete it cannot prove.
final class UninstallOutcome {
  const UninstallOutcome({
    required this.id,
    required this.nodeLabel,
    required this.fileRemoved,
  });

  final String id;

  /// The node label this source held, for the confirmation message.
  final String? nodeLabel;

  /// True only when a file was actually deleted from disk.
  final bool fileRemoved;
}

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
    SourceFileRemover? fileRemover,
  })  : _verifier = verifier ?? SignatureVerifier.instance,
        // Defaults to the production remover so a real app never silently
        // leaves orphan files behind; tests inject a rooted double.
        _fileRemover = fileRemover ?? const AppPrivateSourceFileRemover();

  final ExtensionRegistry _registry;
  final ExtensionRuntimeApi? _runtimeApi;
  final ExtensionJsSandbox Function()? _sandboxFactory;

  /// Deletes the source file on uninstall, under an app-private containment
  /// guard. Never null: a missing remover would silently reintroduce the
  /// orphan-file bug this exists to close.
  final SourceFileRemover _fileRemover;

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
  ///
  /// The resulting node belongs to the USER space, whatever the file's
  /// signature says. A SPECTA-signed file the user picked is verified — and
  /// keeps its green dot — but it is the user's source, so it becomes Node 1,
  /// Node 2, … and is not the undeletable Node 0.
  Future<SpectaResult<ExtensionRecord>> importExtension({
    required String filePath,
    SourceNodeSpace space = SourceNodeSpace.user,
  }) async {
    late final String jsCode;
    try {
      jsCode = await File(filePath).readAsString();
    } catch (e) {
      return Err<ExtensionRecord>(
        _buildFailure(
          type: ExtensionFailureType.parseError,
          // PRE-F §15: the message reaches a SnackBar, so it must never carry
          // a filesystem path. The path stays in `detail` for diagnostics only.
          message: 'That source file could not be read.',
          extensionId: unidentifiedExtension,
          detail: 'Cannot read extension file: $filePath (${e.runtimeType})',
          operation: 'import',
        ),
      );
    }

    return _processManifest(
      jsCode: jsCode,
      targetPath: filePath,
      recordId: null,
      space: space,
    );
  }

  /// Import a `.js` extension from raw source code (for tests / catalogue).
  Future<SpectaResult<ExtensionRecord>> importFromSource({
    required String extensionId,
    required String jsCode,
    required String targetPath,
    SourceNodeSpace space = SourceNodeSpace.user,
  }) async {
    return _processManifest(
      jsCode: jsCode,
      targetPath: targetPath,
      recordId: extensionId,
      space: space,
    );
  }

  Future<SpectaResult<ExtensionRecord>> _processManifest({
    required String jsCode,
    required String targetPath,
    required String? recordId,
    required SourceNodeSpace space,
  }) async {
    late final ExtensionManifest manifest;
    try {
      manifest = ManifestParser.parse(jsCode);
    } on ManifestParseException catch (e) {
      return Err<ExtensionRecord>(
        _buildFailure(
          type: ExtensionFailureType.invalidResult,
          message: describeUnimportableSource(jsCode, e),
          extensionId: recordId ?? unidentifiedExtension,
          detail: e.message,
          operation: 'import',
        ),
      );
    }

    if (!manifest.isCompatible) {
      return Err<ExtensionRecord>(
        _buildFailure(
          type: ExtensionFailureType.unsupported,
          message:
              'Source API version ${manifest.apiVersion} / contract '
              '${manifest.effectiveContractVersion} is not supported by this '
              'SPECTA build.',
          extensionId: manifest.id,
          operation: 'import',
        ),
      );
    }

    final TrustLevel trustLevel = await _classifyTrust(
      manifest,
      ManifestParser.extractBody(jsCode),
    );

    final String id = recordId ?? manifest.id;

    // Deterministic duplicate-ID handling (Phase 2H §6). Installing under an
    // id that already exists REPLACES that extension; it never creates a
    // second identity beside it. Two consequences are enforced here:
    //   1. Any live runtime for the id is retired first, so a replacement can
    //      never leave an earlier version still executing under the new
    //      record (the registry and the running code would disagree).
    //   2. The user's enable/disable choice and original install time are
    //      carried forward. Re-importing a file is not an implicit re-enable:
    //      an extension the user switched off stays off until they turn it on.
    final DateTime now = DateTime.now().toUtc();
    final ExtensionRecord? existing = await _registry.getById(id);
    if (existing != null) {
      // Phase D (D7): snapshot the OUTGOING version before it is replaced.
      // `rollback()` reads `getRollbackVersion`, but nothing ever wrote one,
      // so rollback could never fire. The snapshot is taken only after every
      // gate above has passed, and it records the file that is about to stop
      // being current — so a rollback restores a file that still exists on
      // disk rather than one already overwritten.
      //
      // Nothing here overwrites the previous snapshot: each replacement adds a
      // row, and `getRollbackVersion` returns the most recent one. A failed
      // replacement never reaches this point at all, because the manifest,
      // compatibility and trust checks all run first.
      await _registry.saveVersion(
        ExtensionVersionRecord(
          id: '${id}_${now.millisecondsSinceEpoch}',
          extensionId: id,
          version: existing.version,
          filePath: existing.filePath,
          isCurrent: false,
          isRollbackPoint: true,
          createdAt: now,
          contractVersion: existing.contractVersion,
        ),
      );
      await _retireRuntime(id);
    }

    // A reinstall REPLACES an existing source; it does not create a second
    // identity beside it. The node therefore must be carried forward
    // untouched — a reinstall must not consume a new number, and it must not
    // move a source to a different node. Only a genuinely new id allocates one.
    final SourceNode node = existing?.node ?? await _allocateNode(space);
    final int nodeOrder = existing?.nodeOrder ?? await _nextNodeOrder();

    final ExtensionRecord record = ExtensionRecord(
      id: id,
      name: manifest.name,
      version: manifest.version,
      author: manifest.author,
      apiVersion: manifest.apiVersion,
      contractVersion: manifest.effectiveContractVersion,
      contentType: manifest.type.code,
      signature: manifest.signature,
      trustLevel: trustLevel,
      enabled: existing?.enabled ?? true,
      filePath: targetPath,
      installedAt: existing?.installedAt ?? now,
      updatedAt: now,
      node: node,
      // The undeletable flag belongs to Node 0 alone. A user-space node is
      // never locked, even when the file is SPECTA-signed and therefore shows a
      // green dot. An official node keeps whatever it already had; a brand new
      // official node at index 0 becomes the undeletable Node 0.
      nodeLocked: existing?.nodeLocked ?? (node.isOfficial && node.index == 0),
      nodeOrder: nodeOrder,
    );

    await _registry.install(record);
    return Ok<ExtensionRecord>(record);
  }

  /// Shuts down and forgets a live runtime for [id], if one exists.
  ///
  /// Used wherever an extension's identity is retired — replacement, disable,
  /// uninstall or explicit shutdown — so lifecycle transitions never leave a
  /// stale JS engine running in the background. A runtime that failed to load
  /// is never published to [_runtimes] and is disposed at its failure site.
  Future<void> _retireRuntime(String id) async {
    final ExtensionRuntime? runtime = _runtimes.remove(id);
    if (runtime != null) {
      await runtime.shutdown();
    }
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

  /// Allocates the lowest free node index in [space].
  ///
  /// Reads the indices already in use in that space and asks
  /// [SourceNodeAllocator] for the first gap. It is never `max + 1`, because a
  /// compacted list is exactly what renumbers survivors when a node is deleted.
  Future<SourceNode> _allocateNode(SourceNodeSpace space) async {
    final List<ExtensionRecord> all = await _registry.getAll();
    final Set<int> assigned = <int>{
      for (final ExtensionRecord r in all)
        if (r.node?.space == space) r.node!.index,
    };
    return SourceNode(
      space: space,
      index: SourceNodeAllocator.next(space, assigned),
    );
  }

  /// The next display position, placing a new node at the end of the list.
  Future<int> _nextNodeOrder() async {
    final List<ExtensionRecord> all = await _registry.getAll();
    int max = 0;
    for (final ExtensionRecord r in all) {
      if (r.nodeOrder > max) max = r.nodeOrder;
    }
    return max + 1;
  }

  /// Gives every pre-v9 row a node exactly once, in a deterministic order.
  ///
  /// Rows are ordered by `(installedAt, id)`, so the SAME database always
  /// produces the SAME assignment no matter when the app happens to start, or
  /// how many times this runs. Once assigned, a node is never recomputed —
  /// which is what makes "delete Node 2, Node 3 stays Node 3" true.
  ///
  /// Everything already carrying a node is skipped, so this is idempotent.
  Future<void> ensureNodesAssigned() async {
    final List<ExtensionRecord> all = await _registry.getAll();
    final List<ExtensionRecord> unassigned = all
        .where((ExtensionRecord r) => r.node == null)
        .toList();
    if (unassigned.isEmpty) return;

    unassigned.sort((ExtensionRecord a, ExtensionRecord b) {
      final int byTime = a.installedAt.compareTo(b.installedAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });

    for (final ExtensionRecord record in unassigned) {
      // A row that predates v9 arrived before nodes existed, so it belongs to
      // the USER space. Nothing that was already installed becomes an official,
      // undeletable Node 0 just by being upgraded.
      final SourceNode node = await _allocateNode(SourceNodeSpace.user);
      await _registry.setNode(record.id, node);
    }
  }

  /// Moves [id] to [index] in the user's display order.
  ///
  /// The supplied [index] is a POSITION IN THE CURRENT VISIBLE ORDER, not a
  /// node number, and is clamped rather than rejected — a stale list must never
  /// make an ordinary drag fail.
  ///
  /// Every other node is renumbered around it in one pass, so the result is a
  /// dense 0..n-1 ordering with no gaps and no duplicates. Doing it one write
  /// per node is what makes the order survive a restart: a partial write would
  /// otherwise leave two nodes claiming the same position.
  ///
  /// A node's IDENTITY is untouched. Moving Node 0 to the end moves the card,
  /// never the node, and never its locked flag. There is deliberately no
  /// "Node 0 cannot move" rule (A4/Q5).
  Future<void> reorder(String id, int index) async {
    // Sorted exactly as `installed()` sorts, so a position the user saw is a
    // position this method understands.
    final List<ExtensionRecord> all = await _registry.getAll();
    all.sort(_byDisplayOrder);
    final int from = all.indexWhere((ExtensionRecord r) => r.id == id);
    if (from < 0) return; // unknown id: nothing to move
    if (all.length < 2) return;

    final int to = index.clamp(0, all.length - 1);
    if (to == from) return;

    final ExtensionRecord moved = all.removeAt(from);
    all.insert(to, moved);
    for (int i = 0; i < all.length; i++) {
      await _registry.setNodeOrder(all[i].id, i);
    }
  }

  /// The single display ordering, used by both the list and [reorder].
  ///
  /// `nodeOrder` first — the user's arrangement — then the node label, then
  /// the id. It is never the source's name: the name is provider-chosen, so
  /// ordering by it would let a third party decide the order of the user's
  /// list, and would leak a site name into the sort key.
  ///
  /// The label/id tie-breakers exist so two nodes that somehow share an order
  /// still render in the same sequence on every run.
  static int _byDisplayOrder(ExtensionRecord a, ExtensionRecord b) {
    final int byOrder = a.nodeOrder.compareTo(b.nodeOrder);
    if (byOrder != 0) return byOrder;
    final int byLabel = (a.nodeLabel ?? '').compareTo(b.nodeLabel ?? '');
    if (byLabel != 0) return byLabel;
    return a.id.compareTo(b.id);
  }

  /// Permanently removes an extension, its rows and its file.
  ///
  /// Returns a controlled failure when the node is locked (Node 0) or unknown.
  /// It never throws and never silently no-ops: a refused delete must be
  /// distinguishable from a completed one by the caller that renders it.
  ///
  /// Order matters and is deliberate:
  ///   1. The guard runs FIRST, before anything is retired or removed, so a
  ///      refused Node 0 keeps its runtime alive and its row intact. A guard
  ///      that ran after `_retireRuntime` would kill the user's working source
  ///      and then refuse to delete it — the worst possible outcome.
  ///   2. The runtime is retired before the row goes, so a removed source is
  ///      never left executing.
  ///   3. `filePath` is read from the record BEFORE the row is deleted, because
  ///      afterwards it is gone — that is the orphan-file bug this closes.
  ///   4. The file is removed only through [SourceFileRemover], which refuses
  ///      any path outside app-private storage.
  Future<SpectaResult<UninstallOutcome>> uninstall(String id) async {
    final ExtensionRecord? record = await _registry.getById(id);
    if (record == null) {
      return Err<UninstallOutcome>(
        _buildFailure(
          type: ExtensionFailureType.invalidResult,
          message: 'That source is not installed.',
          extensionId: id,
          operation: 'uninstall',
        ),
      );
    }

    if (record.nodeLocked) {
      return Err<UninstallOutcome>(
        _buildFailure(
          type: ExtensionFailureType.capabilityError,
          // The owner of SPECTA always needs one working source. The refusal is
          // stated in the user's terms, and names the node — never the site.
          message:
              '${record.nodeLabel ?? 'This node'} is the core source and cannot '
              'be removed. You can turn it off instead.',
          extensionId: id,
          operation: 'uninstall',
          detail: 'Refused: node_locked = 1 for node ${record.nodeLabel}.',
        ),
      );
    }

    await _retireRuntime(id);
    // Read before the delete: after this line the path no longer exists anywhere.
    final String filePath = record.filePath;
    await _registry.uninstall(id);

    final bool fileRemoved = await _fileRemover.remove(filePath);
    return Ok<UninstallOutcome>(
      UninstallOutcome(
        id: id,
        nodeLabel: record.nodeLabel,
        fileRemoved: fileRemoved,
      ),
    );
  }

  /// Enables or disables an extension.
  ///
  /// Disabled extensions do not participate in execution. Disabling retires
  /// the runtime immediately and persists the flag, so the state is enforced
  /// by the manager (not by UI state), and cannot survive as a live engine.
  /// Enabling only persists the flag: the runtime is created lazily by the
  /// next [loadRuntime].
  Future<void> setEnabled(String id, bool enabled) async {
    if (!enabled) {
      await _retireRuntime(id);
    }
    await _registry.setEnabled(id, enabled);
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
          message: 'Source not found: $id',
          extensionId: id,
          operation: 'load',
        ),
      );
    }

    if (!record.enabled) {
      return Err<ExtensionRuntime>(
        _buildFailure(
          type: ExtensionFailureType.capabilityError,
          message: 'Source is disabled: $id',
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
          // PRE-F §15: no filesystem path in a user-facing message.
          message: 'That source could not be loaded.',
          extensionId: id,
          detail:
              'Cannot read extension file: ${record.filePath} '
              '(${e.runtimeType})',
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
          message: 'Source manifest is no longer valid: ${e.message}',
          extensionId: id,
          operation: 'load',
        ),
      );
    }

    // 2G-C pre-flight (§36.5): trust is re-classified from the FILE ACTUALLY
    // BEING LOADED, not trusted from the import-time record. The stored record
    // could say `official` while the file on disk has since changed (the
    // signature covers manifest + body, so any code change invalidates it).
    // The freshly derived trust and capabilities are what run; a divergence
    // from the stored level is persisted through the registry and recorded in
    // the failure log so the change is observable, never silent. The policy
    // that unverified extensions may still load stays unchanged: trust is
    // data, not enforcement.
    final TrustLevel fileTrust = await _classifyTrust(
      manifest,
      ManifestParser.extractBody(jsCode),
    );
    if (fileTrust != record.trustLevel) {
      await _registry.install(
        record.copyWith(
          trustLevel: fileTrust,
          signature: () => manifest.signature,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      await _registry.recordFailure(
        ExtensionFailureRecord(
          id: '${id}_trust_${DateTime.now().toUtc().toIso8601String()}',
          extensionId: id,
          failureType: ExtensionFailureType.invalidResult.code,
          operation: 'load',
          message:
              'Trust level re-classified at load: stored '
              '"${record.trustLevel.code}", file verifies as '
              '"${fileTrust.code}". The file changed after import.',
          timestamp: DateTime.now().toUtc(),
          retryable: false,
        ),
      );
    }

    // The enabled/configuration checks above deliberately come BEFORE the
    // file read and trust re-classification: their existing failure semantics
    // must not depend on the file being readable. In the real app the API and
    // sandbox are always configured, so every real load reaches the re-check.
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
          message: 'Source runtime not loaded: $id',
          extensionId: id,
          operation: 'operation',
        ),
      );
    }
    final SpectaResult<T> result = await operation(runtime);
    // Record REAL activity only. An operation that returned a controlled
    // failure has proven nothing, so it must not stamp a success — otherwise a
    // source that fails every single call would read as "working" on the health
    // screen. A recording failure here is deliberately swallowed: telemetry
    // must never turn a working operation into an error for the caller.
    if (result.isOk) {
      try {
        await _registry.setLastSuccess(id, DateTime.now().toUtc());
      } on Object {
        // Best-effort.
      }
    }
    return result;
  }

  /// Records a real success. Public so the paths that complete work outside
  /// [callOperation] (resolution, discovery) can stamp the same honest fact.
  Future<void> recordSuccess(String id) async {
    try {
      await _registry.setLastSuccess(id, DateTime.now().toUtc());
    } on Object {
      // Best-effort telemetry; never fail a user's request over it.
    }
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
  Future<void> shutdown(String id) => _retireRuntime(id);

  /// Shuts down ALL loaded runtimes.
  Future<void> shutdownAll() async {
    for (final String id in _runtimes.keys.toList()) {
      await shutdown(id);
    }
  }

  /// Whether a rollback point would actually CHANGE [id] right now.
  ///
  /// Exposed so the UI offers the control only when it can do something real.
  /// A snapshot that is identical to the current version is not an available
  /// rollback: after a restore, the snapshot becomes the current version, and
  /// offering "restore" again would be a no-op button.
  Future<bool> isRollbackAvailable(String id) async {
    final ExtensionVersionRecord? previous = await _registry.getRollbackVersion(
      id,
    );
    if (previous == null) return false;
    final ExtensionRecord? current = await _registry.getById(id);
    if (current == null) return false;
    return previous.version != current.version;
  }

  /// Rolls back an extension to its previous known-good version.
  ///
  /// Returns true only when a snapshot that would actually CHANGE the installed
  /// version was found and restored.
  ///
  /// The snapshot row is intentionally left in place — it is the historical
  /// record of what was replaced — so idempotence comes from refusing a
  /// rollback whose target is already the current version. Without that guard a
  /// second rollback would report success while reinstalling the same file.
  Future<bool> rollback(String id) async {
    final ExtensionVersionRecord? previous = await _registry.getRollbackVersion(
      id,
    );
    if (previous == null) return false;

    final ExtensionRecord? current = await _registry.getById(id);
    if (current == null) return false;
    if (previous.version == current.version) return false;

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
          message: 'Source not found: $id',
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

/// Explains, in plain user-facing terms, why a picked or downloaded file is not
/// a SPECTA source.
///
/// Three distinct real-world cases are separated, because they have three
/// different fixes and collapsing them into one message is what made this
/// confusing in the first place:
///
/// 1. A repository CATALOGUE — a JSON index of sources belonging to some other
///    provider ecosystem — pasted into "Install from a link".
/// 2. A `.js` file that carries NO `// ==SpectaExtension==` header at all. This
///    is the case that produced the least honest message. The parser reads an
///    EMPTY field map and then fails on whichever required field it happens to
///    check first, so an ordinary file from another ecosystem was told
///    "Missing required field: id" — literally true, and completely useless,
///    because the file's real problem is that SPECTA never recognised its
///    header in the first place. That exact message was observed on a real
///    device and is the reason this branch now exists.
/// 3. A file that DOES carry the header but is missing or has an invalid
///    required field. Here the field name is genuinely useful, so it is kept.
///
/// This changes only the EXPLANATION. Nothing here relaxes validation: a
/// catalogue is still not installable as a source, and the signature and trust
/// gates are untouched.
String describeUnimportableSource(String jsCode, ManifestParseException cause) {
  final String head = jsCode.trimLeft();
  final bool looksLikeJson =
      head.startsWith('{') || head.startsWith('[') || head.startsWith('{');
  if (looksLikeJson) {
    return 'That link is a repository catalogue — a JSON index of sources — '
        'not a single SPECTA source. Open the repository to install from it, '
        'or link the .js file of one source directly.';
  }

  // The decisive question is whether SPECTA found its own header. When the
  // header block is absent, `ManifestParser.parse` reads an empty field map and
  // fails on the first required field it looks for — a misleading symptom
  // rather than the real cause. Detecting the missing header directly is what
  // turns "Missing required field: id" into something the user can act on. The
  // header is still mandatory; this only names it.
  if (ManifestParser.extractHeader(jsCode).isEmpty) {
    return 'That file has no SPECTA source header. A SPECTA source is a .js '
        'file that begins with a // ==SpectaExtension== header block.';
  }

  if (!head.startsWith('//')) {
    return 'That file is not a SPECTA source. A SPECTA source is a '
        '.js file that starts with a // ==SpectaExtension== manifest header.';
  }
  return 'That file is not a valid SPECTA source: ${cause.message}';
}
