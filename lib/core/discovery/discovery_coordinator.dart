import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/specta_failure.dart';
import '../errors/specta_result.dart';
import '../extensions/contract/extension_capability.dart';
import '../extensions/contract/result_models.dart';
import '../extensions/manager/extension_manager.dart';
import '../extensions/manager/extension_providers.dart';
import '../extensions/manager/extension_record.dart';
import '../extensions/runtime/extension_runtime.dart';
import 'discovery_deduplicator.dart';
import 'discovery_models.dart';
import 'discovery_normalizer.dart';

/// The Phase 2B discovery pipeline: user query → enabled search-capable
/// extensions → parallel discovery → normalization → deduplication → unified
/// SPECTA results.
///
/// Boundary discipline:
/// - UI never speaks to an [ExtensionRuntime] directly; everything goes
///   through the Phase 1 [ExtensionManager] and its capability gates.
/// - Only enabled extensions are candidates; only extensions whose loaded
///   runtime actually grants the `search` capability participate. An enabled
///   extension without search is [DiscoveryOutcomeKind.skipped], not an error.
/// - One extension failing must not fail the round: outcomes are isolated and
///   valid results from healthy extensions are returned.
/// - Stale-result rejection: every round carries a monotonically increasing
///   generation; an older round never overwrites a newer one (see the search
///   state notifier).
/// - No metadata, no source resolution, no ranking: DISCOVERY FINDS.
abstract final class DiscoveryCoordinator {
  /// Per-extension search timeout. Bounded so one slow extension cannot hang
  /// the round; the runtime's own operation timeout stays in force beneath it.
  static const Duration perExtensionTimeout = Duration(seconds: 20);

  /// Maximum extensions queried in parallel in one round. Extensions in
  /// practice are few (single digits); the cap exists so a large install set
  /// cannot produce unbounded concurrency.
  static const int maxConcurrency = 6;

  /// Maximum observations accepted from ONE extension in one round. A
  /// pathologically large or malformed response cannot balloon the merge.
  static const int maxResultsPerExtension = 100;

  /// Runs one discovery round.
  ///
  /// [request] must be [SearchRequest.isValid]. Candidates are the enabled
  /// extensions; each is loaded (or reused) and queried in parallel. Returns
  /// a [DiscoveryResult] whose outcomes describe exactly what happened per
  /// extension.
  static Future<DiscoveryResult> discover({
    required SearchRequest request,
    required ExtensionManager manager,

    /// Test seam: shortens the per-extension timeout so timeout isolation is
    /// deterministically testable. Production callers never pass it.
    Duration? perExtensionTimeoutOverride,
  }) => _run(
    manager: manager,
    page: request.page,
    operation: 'search',
    capability: ExtensionCapability.search,
    call: (ExtensionRuntime r) =>
        r.search(query: request.normalizedQuery, page: request.page),
    perExtensionTimeoutOverride: perExtensionTimeoutOverride,
  );

  /// Runs one `latest(page)` round across the enabled LATEST-capable
  /// extensions (the Home feed).
  ///
  /// Exactly the same pipeline as [discover] — the same isolation, capping,
  /// normalization and deduplication — because "what is new" is discovery of
  /// a different question, not a different mechanism. An extension without
  /// the `latest` capability is [DiscoveryOutcomeKind.skipped].
  static Future<DiscoveryResult> latest({
    required int page,
    required ExtensionManager manager,
    Duration? perExtensionTimeoutOverride,
  }) => _run(
    manager: manager,
    page: page,
    operation: 'latest',
    capability: ExtensionCapability.latest,
    call: (ExtensionRuntime r) => r.latest(page: page),
    perExtensionTimeoutOverride: perExtensionTimeoutOverride,
  );

  /// The shared round: one capability-gated operation across every enabled
  /// extension, aggregated identically for both `search` and `latest`.
  static Future<DiscoveryResult> _run({
    required ExtensionManager manager,
    required int page,
    required String operation,
    required ExtensionCapability capability,
    required Future<SpectaResult<List<SearchResult>>> Function(ExtensionRuntime)
    call,
    required Duration? perExtensionTimeoutOverride,
  }) async {
    final List<ExtensionRecord> candidates =
        (await manager.getEnabledExtensions()).toList(growable: false);

    if (candidates.isEmpty) {
      return DiscoveryResult(
        items: const <DiscoveryItem>[],
        outcomes: const <ExtensionDiscoveryOutcome>[],
        droppedCount: 0,
        page: page,
      );
    }

    final List<ExtensionDiscoveryOutcome> outcomes = await Future.wait(
      candidates
          .take(maxConcurrency)
          .map(
            (ExtensionRecord record) => _queryOne(
              manager: manager,
              record: record,
              operation: operation,
              capability: capability,
              page: page,
              call: call,
              timeout: perExtensionTimeoutOverride ?? perExtensionTimeout,
            ),
          ),
    );

    return _aggregate(outcomes, page);
  }

  /// One extension's participation in the round. Never throws.
  static Future<ExtensionDiscoveryOutcome> _queryOne({
    required ExtensionManager manager,
    required ExtensionRecord record,
    required String operation,
    required ExtensionCapability capability,
    required int page,
    required Future<SpectaResult<List<SearchResult>>> Function(ExtensionRuntime)
    call,
    required Duration timeout,
  }) async {
    // Load (or reuse) the runtime. A failed load is a failed outcome, not a
    // crash — and not a permanent disable (the record stays enabled).
    final SpectaResult<ExtensionRuntime> runtime = await manager.loadRuntime(
      record.id,
    );
    if (runtime.isErr) {
      return ExtensionDiscoveryOutcome.failed(
        record.id,
        runtime.failureOrNull!,
      );
    }

    // The authoritative capability check: the runtime re-read the manifest at
    // load and grants exactly what it declares. An extension without the
    // capability is skipped, not failed — it is out of scope for this round,
    // and the runtime would refuse the call anyway.
    if (!runtime.valueOrNull!.isGranted(capability)) {
      return ExtensionDiscoveryOutcome.skipped(record.id);
    }

    try {
      final SpectaResult<List<SearchResult>> response = await manager
          .callOperation<List<SearchResult>>(record.id, call)
          .timeout(timeout);

      if (response.isErr) {
        return ExtensionDiscoveryOutcome.failed(
          record.id,
          response.failureOrNull!,
        );
      }

      final List<SearchResult> raw =
          (response.valueOrNull ?? const <SearchResult>[])
              .take(maxResultsPerExtension)
              .toList(growable: false);

      return ExtensionDiscoveryOutcome.success(record.id, raw);
    } on TimeoutException {
      return ExtensionDiscoveryOutcome.failed(
        record.id,
        ExtensionFailure(
          extensionId: record.id,
          operation: operation,
          type: ExtensionFailureType.timeout,
          message: 'Discovery round timed out for this source',
          timestamp: DateTime.now().toUtc(),
        ),
      );
    } on Object catch (e) {
      // Absolute containment: nothing from one extension escapes the round.
      return ExtensionDiscoveryOutcome.failed(
        record.id,
        ExtensionFailure(
          extensionId: record.id,
          operation: operation,
          type: ExtensionFailureType.runtimeError,
          message: 'Discovery participation failed',
          timestamp: DateTime.now().toUtc(),
          detail: e.toString(),
        ),
      );
    }
  }

  /// Normalizes every successful outcome's observations and dedupes them into
  /// unified items, preserving first-seen order.
  static DiscoveryResult _aggregate(
    List<ExtensionDiscoveryOutcome> outcomes,
    int page,
  ) {
    final List<DiscoveryObservation> observations = <DiscoveryObservation>[];
    int dropped = 0;

    for (final ExtensionDiscoveryOutcome outcome in outcomes) {
      if (!outcome.isSuccess) continue;
      for (final SearchResult raw in outcome.results) {
        final DiscoveryObservation? normalized = DiscoveryNormalizer.normalize(
          raw,
          outcome.extensionId,
        );
        if (normalized == null) {
          dropped++;
        } else {
          observations.add(normalized);
        }
      }
    }

    return DiscoveryResult(
      items: DiscoveryDeduplicator.dedupe(observations),
      outcomes: outcomes,
      droppedCount: dropped,
      page: page,
    );
  }
}

/// Riverpod wiring for the discovery layer.
///
/// The manager comes from the Phase 1 provider graph — no second instance.
final Provider<DiscoveryService> discoveryServiceProvider =
    Provider<DiscoveryService>((Ref ref) {
      return DiscoveryService(manager: ref.watch(extensionManagerProvider));
    });

/// Stateless service wrapper so UI state notifiers can run discovery rounds
/// without depending on the coordinator's static shape.
final class DiscoveryService {
  const DiscoveryService({required this.manager});

  final ExtensionManager manager;

  Future<DiscoveryResult> search(SearchRequest request) =>
      DiscoveryCoordinator.discover(request: request, manager: manager);

  /// One `latest(page)` round (the Home feed).
  Future<DiscoveryResult> latest(int page) =>
      DiscoveryCoordinator.latest(page: page, manager: manager);
}
