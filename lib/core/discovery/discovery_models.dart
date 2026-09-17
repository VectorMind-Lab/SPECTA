import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/contract/result_models.dart';

/// A page-scoped search request as defined by the extension contract
/// (`search(query, page)`).
///
/// This is SPECTA's own request value object: the coordinator turns it into
/// per-extension runtime calls, so UI code never speaks to a runtime directly.
final class SearchRequest {
  const SearchRequest({required this.query, this.page = 1});

  /// The user's query. The coordinator normalizes it before dispatching;
  /// an effectively blank query never reaches extensions.
  final String query;

  /// 1-based page number, matching the extension contract.
  final int page;

  /// Normalized query: trimmed and whitespace-collapsed. A blank normalized
  /// query marks the request invalid — SPECTA must not dispatch it.
  String get normalizedQuery =>
      query.trim().replaceAll(RegExp(r'\s+'), ' ');

  bool get isValid => normalizedQuery.isNotEmpty && page >= 1;

  @override
  String toString() => 'SearchRequest(query: $normalizedQuery, page: $page)';
}

/// One extension's contribution to a unified discovery item.
///
/// Provenance is a mandatory Phase 2B requirement: when two extensions
/// discover the same work, SPECTA keeps ONE unified item and BOTH references,
/// so later phases (details in 2C, source resolution in 2D) can resolve
/// through any contributing extension. Provenance is never discarded during
/// deduplication.
final class DiscoveryReference {
  const DiscoveryReference({
    required this.extensionId,
    required this.url,
    this.cover,
  });

  /// The contributing extension's registry id.
  final String extensionId;

  /// The extension-internal reference (the `SearchResult.url` the extension
  /// expects back through `details(url)` in a later phase). SPECTA never
  /// renders this; it is identity and future-resolution data.
  final String url;

  /// The cover URL the extension reported, if any. Kept per-reference so a
  /// merge can prefer a reference that actually carries artwork.
  final String? cover;

  @override
  String toString() => 'DiscoveryReference($extensionId)';
}

/// A unified SPECTA discovery item.
///
/// One logical work (movie or series) as SPECTA sees it — normalized, merged
/// across extensions, with every contributing reference preserved. This is a
/// DISCOVERY-layer model: it deliberately carries no metadata beyond what
/// discovery observed, and no source/playback information at all.
final class DiscoveryItem {
  const DiscoveryItem({
    required this.key,
    required this.title,
    required this.type,
    required this.references,
    this.year,
    this.cover,
  });

  /// Stable discovery identity (the deduplication key). Deterministic for a
  /// given set of observations, so tests and later phases can rely on it.
  final String key;

  /// Best display title observed (first-seen, normalized).
  final String title;

  /// Media type. Phase 2B scope: movie and series only — the contract's
  /// [MediaType] has exactly these values.
  final MediaType type;

  /// Release year when at least one reference observed one. When references
  /// disagree, the lowest year wins: remakes and re-releases make higher
  /// years lossy, and the earliest observation is the least inventive choice.
  /// Never guessed when no reference provided one.
  final int? year;

  /// First available cover URL among the references, if any.
  final String? cover;

  /// Every extension that discovered this work, with their references.
  /// Ordered by first observation. Deduplication appends; it never drops.
  final List<DiscoveryReference> references;

  /// Whether more than one extension discovered this work.
  bool get isCrossExtension => references.length > 1;

  @override
  String toString() =>
      'DiscoveryItem($key, type: ${type.code}, refs: ${references.length})';
}

/// The outcome of one extension's participation in a discovery round.
///
/// Every terminal state is represented as data — an extension timing out or
/// failing must never throw into the coordinator or prevent healthy
/// extensions from contributing.
enum DiscoveryOutcomeKind {
  /// The extension returned results (possibly zero).
  success,

  /// The extension was not queried at all (disabled, no runtime, no declared
  /// search capability, or wrong content scope for the query round).
  skipped,

  /// The extension was queried and failed (timeout, network, runtime,
  /// malformed output — whatever the runtime classified).
  failed,
}

final class ExtensionDiscoveryOutcome {
  const ExtensionDiscoveryOutcome._({
    required this.kind,
    required this.extensionId,
    this.results = const <SearchResult>[],
    this.failure,
  });

  factory ExtensionDiscoveryOutcome.success(
    String extensionId,
    List<SearchResult> results,
  ) => ExtensionDiscoveryOutcome._(
    kind: DiscoveryOutcomeKind.success,
    extensionId: extensionId,
    results: results,
  );

  factory ExtensionDiscoveryOutcome.skipped(String extensionId) =>
      ExtensionDiscoveryOutcome._(
        kind: DiscoveryOutcomeKind.skipped,
        extensionId: extensionId,
      );

  factory ExtensionDiscoveryOutcome.failed(
    String extensionId,
    SpectaFailure failure,
  ) => ExtensionDiscoveryOutcome._(
    kind: DiscoveryOutcomeKind.failed,
    extensionId: extensionId,
    failure: failure,
  );

  final DiscoveryOutcomeKind kind;
  final String extensionId;

  /// Raw (pre-normalization) results — only for [DiscoveryOutcomeKind.success].
  final List<SearchResult> results;

  /// The controlled failure — only for [DiscoveryOutcomeKind.failed].
  final SpectaFailure? failure;

  bool get isSuccess => kind == DiscoveryOutcomeKind.success;
  bool get isSkipped => kind == DiscoveryOutcomeKind.skipped;
  bool get isFailed => kind == DiscoveryOutcomeKind.failed;
}

/// The aggregated result of one discovery round: unified items plus the
/// per-extension outcomes, so the UI can show valid results AND report
/// partial failure honestly.
final class DiscoveryResult {
  const DiscoveryResult({
    required this.items,
    required this.outcomes,
    required this.droppedCount,
    required this.page,
  });

  /// Unified, deduplicated items in stable first-seen order.
  final List<DiscoveryItem> items;

  /// One outcome per candidate extension.
  final List<ExtensionDiscoveryOutcome> outcomes;

  /// Raw observations dropped by normalization (invalid or off-scope entries),
  /// counted so nothing disappears silently.
  final int droppedCount;

  /// The page this round requested (1-based), matching [SearchRequest.page].
  final int page;

  Iterable<ExtensionDiscoveryOutcome> get failures =>
      outcomes.where((ExtensionDiscoveryOutcome o) => o.isFailed);

  Iterable<ExtensionDiscoveryOutcome> get successes =>
      outcomes.where((ExtensionDiscoveryOutcome o) => o.isSuccess);

  /// True when at least one extension was queried and every queried extension
  /// failed — distinct from an honest empty result.
  bool get allQueriedFailed =>
      outcomes.isNotEmpty &&
      successes.isEmpty &&
      failures.isNotEmpty;

  /// True when no extension could be queried at all (nothing enabled with the
  /// search capability).
  bool get noExtensionAvailable =>
      outcomes.isEmpty || outcomes.every((ExtensionDiscoveryOutcome o) => o.isSkipped);

  @override
  String toString() =>
      'DiscoveryResult(page: $page, items: ${items.length}, '
      'successes: ${successes.length}, failures: ${failures.length}, '
      'dropped: $droppedCount)';
}
