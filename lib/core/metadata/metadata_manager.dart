import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../anilist/anilist_client.dart';
import '../anilist/anilist_providers.dart';
import '../discovery/discovery_coordinator.dart';
import '../discovery/discovery_models.dart';
import '../identity/title_key.dart';
import '../errors/specta_failure.dart';
import '../errors/specta_result.dart';
import '../extensions/contract/extension_capability.dart';
import '../extensions/contract/result_models.dart';
import '../extensions/manager/extension_manager.dart';
import '../extensions/manager/extension_providers.dart';
import '../extensions/runtime/extension_runtime.dart';
import '../tmdb/tmdb_client.dart';
import '../tmdb/tmdb_providers.dart';
import '../tvmaze/tvmaze_client.dart';
import '../tvmaze/tvmaze_providers.dart';
import 'catalogue_enricher.dart';
import 'metadata_models.dart';
import 'metadata_normalizer.dart';

/// How a metadata request for one reference ended.
enum ReferenceOutcomeKind {
  /// The reference supplied valid, normalized metadata.
  success,

  /// The reference could not be queried (no runtime, capability refused).
  skipped,

  /// The extension failed the operation (timeout, network, runtime error).
  failed,

  /// The extension answered but the payload failed SPECTA validation.
  invalid,
}

/// One reference's participation in a metadata request. Failures are data —
/// never exceptions — so one bad reference cannot break the item.
final class ReferenceOutcome {
  const ReferenceOutcome._({
    required this.kind,
    required this.reference,
    this.metadata,
    this.failure,
    this.dropReason,
  });

  final ReferenceOutcomeKind kind;
  final DiscoveryReference reference;

  /// Valid normalized metadata — only for [ReferenceOutcomeKind.success].
  final ReferenceMetadata? metadata;

  /// Controlled failure — only for [ReferenceOutcomeKind.failed].
  final SpectaFailure? failure;

  /// Validation reason — only for [ReferenceOutcomeKind.invalid].
  final String? dropReason;

  bool get isSuccess => kind == ReferenceOutcomeKind.success;
  bool get isFailed => kind == ReferenceOutcomeKind.failed;
  bool get isInvalid => kind == ReferenceOutcomeKind.invalid;
}

/// The result of one metadata request over one [DiscoveryItem].
final class MetadataResult {
  const MetadataResult({required this.item, required this.outcomes});

  /// The canonical metadata, or null when no reference could supply valid
  /// metadata. A partial result (some references failed) still produces an
  /// item — honest partial metadata beats a blank screen.
  final MetadataItem? item;

  /// One outcome per reference, in reference order.
  final List<ReferenceOutcome> outcomes;

  bool get hasItem => item != null;

  Iterable<ReferenceOutcome> get failures =>
      outcomes.where((ReferenceOutcome o) => o.isFailed || o.isInvalid);

  @override
  String toString() =>
      'MetadataResult(item: ${item != null}, outcomes: ${outcomes.length})';
}

/// The Phase 2C Metadata Manager.
///
/// Pipeline: [DiscoveryItem] (with provenance) → per-reference `details(url)`
/// through the Phase 1 [ExtensionManager] → SPECTA validation/normalization →
/// canonical [MetadataItem] with all contributions preserved.
///
/// Boundary discipline:
/// - Only `details()` is called. `getSources()` is Phase 2D and is never
///   touched here.
/// - Only references from the item's provenance are queried — SPECTA decides
///   which extensions participate, extensions never solicit.
/// - Only loaded, enabled runtimes whose granted capability set includes
///   `details` are asked; a reference without a queryable runtime is
///   [ReferenceOutcomeKind.skipped], not an error.
/// - One reference failing never fails the request: outcomes are isolated
///   and any valid contribution produces an item.
/// - No persistent caching here: Phase 2C keeps metadata as Riverpod state
///   (in-memory). Persistence is deferred until the library phase (2F)
///   actually requires it — documented, deliberate.
abstract final class MetadataManager {
  /// Per-reference details timeout. Bounded like discovery; the runtime's
  /// own operation timeout stays in force beneath it.
  static const Duration perReferenceTimeout = Duration(seconds: 20);

  /// Builds the stable metadata identity key for a work — the same evidence
  /// key discovery used, so metadata and discovery always agree on identity.
  ///
  /// [normalizedTitle] must already be a KEY title (see [TitleKey.normalize]);
  /// the key format `title|type|year` is unchanged.
  static String identityKey({
    required String normalizedTitle,
    required MediaType type,
    required int? year,
  }) {
    final String yearPart = year?.toString() ?? 'none';
    return '$normalizedTitle|${type.code}|$yearPart';
  }

  /// Requests metadata for [item].
  ///
  /// Queries every reference in parallel (bounded), validates and normalizes
  /// each payload, and merges the valid contributions into one canonical
  /// [MetadataItem]. Returns [MetadataResult] with per-reference outcomes.
  static Future<MetadataResult> metadataFor({
    required DiscoveryItem item,
    required ExtensionManager manager,

    /// Test seam: shortens the per-reference timeout so timeout isolation is
    /// deterministically testable. Production callers never pass it.
    Duration? perReferenceTimeoutOverride,
  }) async {
    final List<ReferenceOutcome> outcomes = await Future.wait(
      item.references
          .take(DiscoveryCoordinator.maxConcurrency)
          .map(
            (DiscoveryReference reference) => _queryReference(
              item: item,
              reference: reference,
              manager: manager,
              timeout: perReferenceTimeoutOverride ?? perReferenceTimeout,
            ),
          ),
    );

    final List<ReferenceMetadata> valid = outcomes
        .where((ReferenceOutcome o) => o.isSuccess)
        .map((ReferenceOutcome o) => o.metadata!)
        .toList(growable: false);

    final MetadataItem? canonical = _canonicalize(item, valid);

    return MetadataResult(item: canonical, outcomes: outcomes);
  }

  /// One reference's participation. Never throws.
  static Future<ReferenceOutcome> _queryReference({
    required DiscoveryItem item,
    required DiscoveryReference reference,
    required ExtensionManager manager,
    required Duration timeout,
  }) async {
    final SpectaResult<ExtensionRuntime> runtime = await manager.loadRuntime(
      reference.extensionId,
    );
    if (runtime.isErr) {
      return ReferenceOutcome._(
        kind: ReferenceOutcomeKind.skipped,
        reference: reference,
        failure: runtime.failureOrNull!,
      );
    }

    if (!runtime.valueOrNull!.isGranted(ExtensionCapability.details)) {
      return ReferenceOutcome._(
        kind: ReferenceOutcomeKind.skipped,
        reference: reference,
      );
    }

    try {
      final SpectaResult<MediaDetails> response = await manager
          .callOperation<MediaDetails>(
            reference.extensionId,
            (ExtensionRuntime r) => r.details(url: reference.url),
          )
          .timeout(timeout);

      if (response.isErr) {
        return ReferenceOutcome._(
          kind: ReferenceOutcomeKind.failed,
          reference: reference,
          failure: response.failureOrNull!,
        );
      }

      final NormalizedDetails normalized = MetadataNormalizer.normalize(
        raw: response.valueOrNull!,
        reference: reference,
        expectedType: item.type,
      );

      if (normalized.isDropped) {
        return ReferenceOutcome._(
          kind: ReferenceOutcomeKind.invalid,
          reference: reference,
          dropReason: normalized.dropReason,
        );
      }

      return ReferenceOutcome._(
        kind: ReferenceOutcomeKind.success,
        reference: reference,
        metadata: normalized.normalized,
      );
    } on TimeoutException {
      return ReferenceOutcome._(
        kind: ReferenceOutcomeKind.failed,
        reference: reference,
        failure: ExtensionFailure(
          extensionId: reference.extensionId,
          operation: 'details',
          type: ExtensionFailureType.timeout,
          message: 'Metadata request timed out for this source',
          timestamp: DateTime.now().toUtc(),
        ),
      );
    } on Object catch (e) {
      // Absolute containment: nothing from one reference escapes the request.
      return ReferenceOutcome._(
        kind: ReferenceOutcomeKind.failed,
        reference: reference,
        failure: ExtensionFailure(
          extensionId: reference.extensionId,
          operation: 'details',
          type: ExtensionFailureType.runtimeError,
          message: 'Metadata request failed',
          timestamp: DateTime.now().toUtc(),
          detail: e.toString(),
        ),
      );
    }
  }

  /// Merges valid contributions into one canonical item.
  ///
  /// Merge policy (deliberate, documented):
  /// - Canonical title/type/year come from the discovery item (first-seen
  ///   normalized evidence); the first reference's own title is preferred
  ///   for display only when present.
  /// - Cover/backdrop: first available among contributions (never overwrite).
  /// - Year: stays the discovery-established value — details years are NOT
  ///   merged in, because a conflicting details year would silently redefine
  ///   the identity the whole layer agreed on. Disagreement stays visible in
  ///   per-reference data.
  static MetadataItem? _canonicalize(
    DiscoveryItem item,
    List<ReferenceMetadata> valid,
  ) {
    if (valid.isEmpty) return null;

    final String key = item.type == MediaType.anime
        ? MediaIdentity.anilistKey(
            valid.first.externalIds?.anilistId ??
                (throw StateError('anime metadata requires an AniList ID')),
          )!
        : identityKey(
            normalizedTitle: _keyTitle(item.title),
            type: item.type,
            year: item.year,
          );

    return MetadataItem(
      key: key,
      title: valid.first.title,
      type: item.type,
      year: item.year,
      cover: valid
          .map((ReferenceMetadata r) => r.cover)
          .firstWhere((String? c) => c != null, orElse: () => item.cover),
      backdrop: valid
          .map((ReferenceMetadata r) => r.backdrop)
          .firstWhere((String? b) => b != null, orElse: () => null),
      details: valid,
      canonicalId: item.type == MediaType.anime ? key : null,
      identityVersion: item.type == MediaType.anime ? 2 : 1,
    );
  }

  /// Case/punctuation/whitespace-insensitive title key — the SHARED rule
  /// [TitleKey.normalize] (2G-C pre-flight §36.1), so metadata and discovery
  /// cannot drift and non-Latin titles keep their letters.
  static String _keyTitle(String title) => TitleKey.normalize(title);
}

/// Riverpod wiring for the metadata layer. The manager comes from the Phase 1
/// provider graph — no second instance.
final Provider<MetadataService> metadataServiceProvider =
    Provider<MetadataService>((Ref ref) {
      // The catalogue clients are resolved LAZILY inside `enrich`, not here.
      // Reading them eagerly would construct the metadata cache (and therefore
      // the Drift database) for every consumer of plain extension metadata,
      // which is a side effect the metadata layer must not impose on callers.
      return MetadataService(
        manager: ref.watch(extensionManagerProvider),
        resolveTmdb: () => ref.read(tmdbClientProvider),
        resolveTvmaze: () => ref.read(tvmazeClientProvider),
        resolveAnilist: () => ref.read(anilistClientProvider),
      );
    });

/// Stateless service wrapper so UI state notifiers can request metadata
/// without depending on the manager's static shape.
final class MetadataService {
  const MetadataService({
    required this.manager,
    this.tmdb,
    this.tvmaze,
    this.anilist,
    this.resolveTmdb,
    this.resolveTvmaze,
    this.resolveAnilist,
  });

  final ExtensionManager manager;

  /// Optional catalogue providers, supplied directly (tests).
  final TmdbClient? tmdb;
  final TvmazeClient? tvmaze;
  final AniListClient? anilist;

  /// Optional lazy resolvers, used by the app graph so that building the
  /// service never forces the local database open.
  final TmdbClient Function()? resolveTmdb;
  final TvmazeClient Function()? resolveTvmaze;
  final AniListClient Function()? resolveAnilist;

  /// TMDB client, or null when the build has none.
  TmdbClient? get effectiveTmdb => tmdb ?? resolveTmdb?.call();

  /// TVMaze client, or null when unavailable.
  TvmazeClient? get effectiveTvmaze => tvmaze ?? resolveTvmaze?.call();

  /// AniList client, or null when unavailable.
  AniListClient? get effectiveAnilist => anilist ?? resolveAnilist?.call();

  Future<MetadataResult> metadataFor(DiscoveryItem item) =>
      MetadataManager.metadataFor(item: item, manager: manager);

  /// Extension metadata enriched with TMDB/TVMaze catalogue data.
  ///
  /// The identity of [item] is never changed: `key`, `type`, `year`,
  /// `canonicalId` and `identityVersion` are carried through untouched, so a
  /// provider answer can never create a duplicate identity for a work.
  /// Provider states are reported as data in [EnrichmentResult.reports].
  ///
  /// Pass [knownResult] when the caller ALREADY ran the extension round for this
  /// item. Without it the round runs a second time, so every reference's
  /// `details()` executes twice — pure duplicated latency on the screen that is
  /// already the slowest, and it also made the two rounds disagree whenever an
  /// extension's answer was not stable.
  ///
  /// [item]'s own key/year/cover are forwarded so a CATALOGUE-ONLY item (one the
  /// catalogue discovered, with no extension behind it) can be COMPLETED under
  /// the identity it already has, rather than being refused — which is what left
  /// a real device showing "Details could not be loaded — the extensions could
  /// not be reached" for a title the app had just listed on its Home rail.
  Future<EnrichmentResult> enrichedMetadataFor(
    DiscoveryItem item, {
    MetadataResult? knownResult,
  }) async {
    final MetadataResult base = knownResult ?? await metadataFor(item);
    final TmdbClient? tmdb = effectiveTmdb;
    return CatalogueEnricher.enrich(
      base: base.item,
      type: item.type,
      title: item.title,
      year: item.year,
      tmdb: tmdb,
      tvmaze: effectiveTvmaze,
      anilist: effectiveAnilist,
      anilistId: item.externalIds?.anilistId,
      identityKey: item.key,
      cover: item.cover,
      imageBaseUrl: tmdb?.config.imageBaseUrl,
    );
  }
}
