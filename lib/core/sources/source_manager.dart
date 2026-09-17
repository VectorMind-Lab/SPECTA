import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/specta_failure.dart';
import '../errors/specta_result.dart';
import '../extensions/contract/extension_capability.dart';
import '../extensions/contract/extension_source.dart';
import '../extensions/manager/extension_manager.dart';
import '../extensions/manager/extension_providers.dart';
import '../extensions/runtime/extension_runtime.dart';
import 'source_models.dart';
import 'source_pool.dart';
import 'source_ranker.dart';
import 'source_validator.dart';

/// The Phase 2D Source Manager.
///
/// Pipeline: references with provenance (from 2C's `ReferenceMetadata` /
/// discovery references) → `getSources(reference)` through the Phase 1
/// [ExtensionManager] → SPECTA validation → deduplication → ranking →
/// [SourcePool] with a deterministic selection and fallback order.
///
/// Boundary discipline:
/// - EXTENSIONS DISCOVER. SPECTA DECIDES: extensions only report candidates;
///   validity, order, and selection are SPECTA's alone.
/// - No second extension contract: the existing runtime operations
///   (`getSources`, `refreshSource`) and the `sources` capability are used
///   exactly as Phase 1 established them.
/// - No playback, no player controls, no downloads, no progress (2E/2F/2G).
/// - No network probing here: structural validation only (see
///   [SourceValidator]); reachability is playback's failure path.
/// - No persistence: pools are in-memory (2F/2G will decide what durable
///   source data they need). No database change in 2D.
/// - No GitHub/catalogue dependency: resolution works against extensions
///   already installed locally (2H owns distribution).
abstract final class SourceManager {
  /// Per-extension resolution timeout. Bounded like 2B/2C; the runtime's own
  /// operation timeout stays in force beneath it.
  static const Duration perExtensionTimeout = Duration(seconds: 20);

  /// Maximum candidates accepted from ONE extension in one round. A
  /// pathologically large or repeated-response cannot balloon the pool
  /// (brief §29). 100 is far above any legitimate catalogue page.
  static const int maxSourcesPerExtension = 100;

  /// Maximum extensions queried in parallel in one round (same cap as
  /// discovery).
  static const int maxConcurrency = DiscoveryConcurrency.max;

  /// Resolves the source pool for [reference] across [extensions].
  ///
  /// [extensions] are the extension ids + references to ask — SPECTA's
  /// callers pass the provenance they already hold (e.g. every
  /// `ReferenceMetadata` of a metadata item, or one specific reference for
  /// an episode). Each entry is queried in parallel; failures are isolated;
  /// the surviving candidates are deduplicated, ranked, and returned.
  static Future<SourcePool> resolve({
    required String reference,
    required Map<String, String> extensions,
    required ExtensionManager manager,
    QualityPreference preference = QualityPreference.auto,

    /// Test seam: shortens the per-extension timeout for deterministic
    /// timeout tests. Production callers never pass it.
    Duration? perExtensionTimeoutOverride,
  }) async {
    final List<ExtensionSourceOutcome> outcomes = await Future.wait(
      extensions.entries
          .take(maxConcurrency)
          .map(
            (MapEntry<String, String> entry) => _queryExtension(
              extensionId: entry.key,
              reference: entry.value,
              manager: manager,
              timeout: perExtensionTimeoutOverride ?? perExtensionTimeout,
            ),
          ),
    );

    return _aggregate(reference, outcomes, preference);
  }

  /// One extension's participation. Never throws.
  static Future<ExtensionSourceOutcome> _queryExtension({
    required String extensionId,
    required String reference,
    required ExtensionManager manager,
    required Duration timeout,
  }) async {
    final SpectaResult<ExtensionRuntime> runtime = await manager.loadRuntime(
      extensionId,
    );
    if (runtime.isErr) {
      return ExtensionSourceOutcome.skipped(extensionId, reference);
    }

    if (!runtime.valueOrNull!.isGranted(ExtensionCapability.sources)) {
      return ExtensionSourceOutcome.skipped(extensionId, reference);
    }

    try {
      final SpectaResult<List<ExtensionSource>> response = await manager
          .callOperation<List<ExtensionSource>>(
        extensionId,
        (ExtensionRuntime r) => r.getSources(reference: reference),
      ).timeout(timeout);

      if (response.isErr) {
        return ExtensionSourceOutcome.failed(
          extensionId,
          reference,
          response.failureOrNull!,
        );
      }

      // Defensive limit: take only the first N candidates before validation
      // so a hostile/buggy response cannot waste unbounded work.
      final List<ExtensionSource> raw = (response.valueOrNull ??
              const <ExtensionSource>[])
          .take(maxSourcesPerExtension)
          .toList(growable: false);

      final List<ExtensionSource> valid = <ExtensionSource>[];
      int dropped = 0;
      for (final ExtensionSource candidate in raw) {
        final ValidatedSource verdict = SourceValidator.validate(candidate);
        if (verdict.isDropped) {
          dropped++;
        } else {
          valid.add(verdict.source!);
        }
      }

      if (valid.isEmpty) {
        return ExtensionSourceOutcome.invalid(
          extensionId,
          reference,
          droppedCount: dropped,
        );
      }
      return ExtensionSourceOutcome.success(
        extensionId,
        reference,
        valid,
        droppedCount: dropped,
      );
    } on TimeoutException {
      return ExtensionSourceOutcome.failed(
        extensionId,
        reference,
        ExtensionFailure(
          extensionId: extensionId,
          operation: 'getSources',
          type: ExtensionFailureType.timeout,
          message: 'Source resolution timed out for this extension',
          timestamp: DateTime.now().toUtc(),
        ),
      );
    } on Object catch (e) {
      // Absolute containment: nothing from one extension escapes the round.
      return ExtensionSourceOutcome.failed(
        extensionId,
        reference,
        ExtensionFailure(
          extensionId: extensionId,
          operation: 'getSources',
          type: ExtensionFailureType.runtimeError,
          message: 'Source resolution failed',
          timestamp: DateTime.now().toUtc(),
          detail: e.toString(),
        ),
      );
    }
  }

  /// Deduplicates, tags provenance, ranks, and assembles the pool.
  ///
  /// Dedup policy (tested, documented):
  /// - The same URL reported by the SAME extension twice is one candidate
  ///   (a repeated observation).
  /// - The same URL from two DIFFERENT extensions is kept twice: both are
  ///   genuine alternatives with their own provenance, and neither
  ///   extension can answer for the other's CDN.
  static SourcePool _aggregate(
    String reference,
    List<ExtensionSourceOutcome> outcomes,
    QualityPreference preference,
  ) {
    final Set<String> seen = <String>{};
    final List<RankedSource> candidates = <RankedSource>[];

    for (final ExtensionSourceOutcome outcome in outcomes) {
      if (!outcome.isSuccess) continue;
      for (final ExtensionSource candidate in outcome.candidates) {
        final String key = '${outcome.extensionId}|${candidate.url}';
        if (!seen.add(key)) continue;
        candidates.add(
          RankedSource(
            source: candidate,
            extensionId: outcome.extensionId,
            reference: outcome.reference,
            score: 0,
          ),
        );
      }
    }

    return SourcePool(
      reference: reference,
      outcomes: outcomes,
      ranked: SourceRanker.rank(candidates, preference),
    );
  }

  /// Refreshes one candidate through the existing `refreshSource(reference)`
  /// contract operation (Phase 1). No second refresh mechanism is invented.
  ///
  /// Returns the refreshed, validated candidate, or null when the extension
  /// failed, was skipped, or returned a payload that failed validation —
  /// the caller (2E's future retry flow) then falls back to
  /// [SourcePool.fallbacks]. Honest representation: absence of a refreshed
  /// source is a normal, handled outcome.
  static Future<ExtensionSource?> refresh({
    required String extensionId,
    required String reference,
    required ExtensionManager manager,
  }) async {
    final SpectaResult<ExtensionRuntime> runtime = await manager.loadRuntime(
      extensionId,
    );
    if (runtime.isErr) return null;
    if (!runtime.valueOrNull!.isGranted(ExtensionCapability.sources)) {
      return null;
    }

    try {
      final SpectaResult<ExtensionSource> response = await manager
          .callOperation<ExtensionSource>(
        extensionId,
        (ExtensionRuntime r) => r.refreshSource(reference: reference),
      ).timeout(perExtensionTimeout);

      if (response.isErr) return null;
      final ValidatedSource verdict =
          SourceValidator.validate(response.valueOrNull!);
      return verdict.isDropped ? null : verdict.source;
    } on Object {
      return null;
    }
  }
}

/// Shared concurrency cap (kept in one place with discovery's).
abstract final class DiscoveryConcurrency {
  static const int max = 6;
}

/// Riverpod wiring. The manager comes from the Phase 1 provider graph — no
/// second instance.
final Provider<SourceService> sourceServiceProvider = Provider<SourceService>(
  (Ref ref) => SourceService(manager: ref.watch(extensionManagerProvider)),
);

/// Stateless service wrapper so UI state notifiers can resolve sources
/// without depending on the manager's static shape.
final class SourceService {
  const SourceService({required this.manager});

  final ExtensionManager manager;

  /// Resolves a pool for one work/episode across the given extension
  /// references. [extensions] maps extension id → that extension's internal
  /// reference for the same logical target.
  Future<SourcePool> resolve({
    required String reference,
    required Map<String, String> extensions,
    QualityPreference preference = QualityPreference.auto,
  }) =>
      SourceManager.resolve(
        reference: reference,
        extensions: extensions,
        manager: manager,
        preference: preference,
      );

  /// Requests a refreshed candidate through the existing contract operation.
  Future<ExtensionSource?> refresh({
    required String extensionId,
    required String reference,
  }) =>
      SourceManager.refresh(
        extensionId: extensionId,
        reference: reference,
        manager: manager,
      );
}
