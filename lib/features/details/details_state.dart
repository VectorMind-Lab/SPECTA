import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/discovery/discovery_models.dart';
import '../../core/metadata/catalogue_enricher.dart';
import '../../core/metadata/metadata_manager.dart';
import '../../core/metadata/metadata_models.dart';

/// User-facing details status. Every state the brief requires, with no raw
/// internal exceptions exposed to the UI.
enum DetailsStatus {
  /// No item opened yet.
  idle,

  /// A metadata request is in flight.
  loading,

  /// Canonical metadata loaded (possibly from fewer references than asked —
  /// see [failedReferences] for the honest partial-failure picture).
  success,

  /// Every reference failed or was invalid — no metadata could be loaded.
  failure,
}

/// Immutable snapshot of one details session for one discovery item.
final class DetailsState {
  const DetailsState({
    required this.status,
    required this.generation,
    this.item,
    this.metadata,
    this.failedReferences = const <String>[],
    this.invalidReferences = const <String>[],
    this.providerReports = const <ProviderReport>[],
  });

  final DetailsStatus status;

  /// Monotonic request counter. A response from an older request is
  /// discarded — rapid navigation (A → B → A → C) can never let a slow
  /// older response overwrite a newer one.
  final int generation;

  /// The discovery item this session is about (set on open, so the UI can
  /// render title/poster immediately from discovery data while details load).
  final DiscoveryItem? item;

  /// Canonical metadata — only for [DetailsStatus.success].
  final MetadataItem? metadata;

  /// References whose extension failed (ids only — no raw errors in UI).
  final List<String> failedReferences;

  /// References whose payload failed validation (ids only).
  final List<String> invalidReferences;

  /// What the catalogue providers did during enrichment. Surfaced as state so
  /// the UI can be honest about a provider outage, but it never changes the
  /// status: a provider failure is not a details failure.
  final List<ProviderReport> providerReports;

  /// True when a provider answered but contributed nothing (no match,
  /// unavailable, malformed). Used for a quiet, non-blocking notice.
  bool get hasProviderGap => providerReports.any(
    (ProviderReport r) => r.outcome != ProviderOutcome.matched,
  );

  /// Whether any extension reference backs this item at all.
  ///
  /// This is the distinction the failure message needs: a catalogue-only title
  /// (Home "Popular", or an AniList search result) has NO reference, so nothing
  /// was ever unreachable and telling the user to check their connection is
  /// actively misleading — it sends them to fix something that is not broken.
  bool get hasExtensionReference => item != null && item!.references.isNotEmpty;

  /// True when at least one reference failed or was invalid but metadata
  /// still loaded — the honest partial-failure state.
  bool get isPartial =>
      status == DetailsStatus.success &&
      (failedReferences.isNotEmpty || invalidReferences.isNotEmpty);

  static const DetailsState initial = DetailsState(
    status: DetailsStatus.idle,
    generation: 0,
  );

  DetailsState copyWith({
    DetailsStatus? status,
    int? generation,
    DiscoveryItem? item,
    MetadataItem? metadata,
    List<String>? failedReferences,
    List<String>? invalidReferences,
    List<ProviderReport>? providerReports,
  }) {
    return DetailsState(
      status: status ?? this.status,
      generation: generation ?? this.generation,
      item: item ?? this.item,
      metadata: metadata ?? this.metadata,
      failedReferences: failedReferences ?? this.failedReferences,
      invalidReferences: invalidReferences ?? this.invalidReferences,
      providerReports: providerReports ?? this.providerReports,
    );
  }
}

/// Drives details requests over the metadata service.
///
/// Race handling mirrors the search session: a monotonically increasing
/// generation stamps every request; when it completes it is applied only if
/// no newer request has started. Repeated opens of the same item are safe —
/// each open is a fresh request.
class DetailsSessionNotifier extends Notifier<DetailsState> {
  int _generation = 0;
  bool _disposed = false;

  @override
  DetailsState build() {
    ref.onDispose(() {
      _disposed = true;
      _generation++; // invalidate any in-flight request
    });
    return DetailsState.initial;
  }

  /// Opens details for [item]: shows discovery data immediately, then loads
  /// canonical metadata through the metadata service.
  ///
  /// [refresh] is what pull-to-refresh and the Details refresh action pass. It
  /// keeps the already-resolved metadata on screen for the duration of the new
  /// round instead of dropping back to a spinner, so refreshing never makes the
  /// screen emptier than it already was.
  Future<void> open(DiscoveryItem item, {bool refresh = false}) async {
    final int gen = ++_generation;

    // Immediate discovery-level render: title/type/year/cover from the item
    // while the details round is in flight. Never fabricated — this is
    // exactly what discovery observed.
    //
    // On a refresh, hold on to whatever already resolved. The title and cover
    // are identical either way (both come from the same item), so blanking them
    // would only cost the user their place.
    final bool refreshing = refresh && _isSameItem(state.item, item);
    state = refreshing && state.metadata != null
        ? state.copyWith(
            status: DetailsStatus.loading,
            generation: gen,
            item: item,
          )
        : DetailsState(
            status: DetailsStatus.loading,
            generation: gen,
            item: item,
          );

    final MetadataResult result;
    try {
      result = await ref.read(metadataServiceProvider).metadataFor(item);
    } on Object {
      // Absolute containment: the UI layer never sees an exception. A failed
      // refresh must also not destroy metadata that is already on screen.
      _applyIfCurrent(
        gen,
        state.copyWith(
          status: state.metadata != null
              ? DetailsStatus.success
              : DetailsStatus.failure,
        ),
      );
      return;
    }
    if (_disposed) return;

    _applyIfCurrent(
      gen,
      _merge(state, _stateFrom(result, item, gen), refreshing: refreshing),
    );

    // Catalogue enrichment (TMDB/TVMaze for movie/series, AniList for anime)
    // runs AFTER the extension round and is applied to the same identity. It
    // is additive: a provider outage must never turn a working details screen
    // into a failure, so a null/absent enrichment is simply ignored.
    //
    // `result` is passed as `knownResult` so the extension round is NOT run a
    // second time for the same item.
    final EnrichmentResult enrichment;
    try {
      enrichment = await ref
          .read(metadataServiceProvider)
          .enrichedMetadataFor(item, knownResult: result);
    } on Object {
      return; // enrichment is best-effort; the base result already stands
    }
    if (_disposed) return;
    if (gen != _generation) return; // a newer open won

    final MetadataItem? enriched = enrichment.item;
    if (enriched == null) {
      // Nothing could complete the work. If the screen is still waiting on
      // enrichment (a catalogue-only item, which deliberately stays `loading`
      // rather than flashing a failure), it has to land SOMEWHERE — otherwise it
      // would spin forever with no way forward except a manual retry.
      if (state.status == DetailsStatus.loading) {
        state = state.copyWith(
          status: DetailsStatus.failure,
          providerReports: enrichment.reports,
        );
      }
      return;
    }
    if (identical(enriched, state.metadata)) return;

    // A catalogue-only item (a title the catalogue itself discovered, with no
    // extension reference behind it) has no base metadata at all. The provider
    // legitimately COMPLETES the work, so the screen must become `success`
    // rather than stay a failure — found on a real device twice: first for an
    // anime title AniList already knew everything about, then for a Home
    // "Popular" (TMDB) movie that no extension backed at all.
    final bool isFirstMetadata = state.metadata == null;
    state = state.copyWith(
      metadata: enriched,
      providerReports: enrichment.reports,
      status: isFirstMetadata ? DetailsStatus.success : null,
    );
  }

  /// Returns the session to idle (details surface left).
  void reset() {
    _generation++; // reject any in-flight request
    state = DetailsState.initial;
  }

  void _applyIfCurrent(int gen, DetailsState next) {
    if (_disposed) return;
    if (gen != _generation) return; // stale request — reject
    state = next;
  }

  /// Whether two items are the same work.
  ///
  /// Identity, not object equality: re-tapping the same card, or pulling to
  /// refresh the one already open, must be recognised as the SAME work even
  /// though a freshly normalised `DiscoveryItem` is a different instance.
  static bool _isSameItem(DiscoveryItem? a, DiscoveryItem b) =>
      a != null && a.key == b.key;

  /// Folds a finished extension round into what is already on screen.
  ///
  /// A refresh must never take content AWAY. [round] is a complete, correct
  /// state built from the new round alone — applying it verbatim would blank
  /// the record the user is currently reading every time they pull to refresh,
  /// and would also show them a spinner-shaped flicker mid-gesture.
  ///
  /// Rules, in order:
  /// 1. Nothing on screen, or a DIFFERENT work on screen -> the round is the
  ///    whole truth. Without the same-item guard this would show one title's
  ///    metadata under another's.
  /// 2. Same work, and the round produced metadata -> take it; it is fresher.
  /// 3. Same work, and the round produced nothing -> keep what is on screen and
  ///    stay `success`, but carry the round's failed/invalid reference ids so
  ///    the partial-failure notice still tells the truth.
  static DetailsState _merge(
    DetailsState current,
    DetailsState round, {
    required bool refreshing,
  }) {
    if (!refreshing || current.metadata == null) return round;
    if (round.metadata != null) return round;
    return current.copyWith(
      status: DetailsStatus.success,
      failedReferences: round.failedReferences,
      invalidReferences: round.invalidReferences,
    );
  }

  DetailsState _stateFrom(MetadataResult result, DiscoveryItem item, int gen) {
    if (!result.hasItem) {
      // Zero references means the extension round had nothing to ask, which
      // is NOT a failure — it is a catalogue-only title, and the enrichment
      // step immediately after is what fills it in. Reporting `failure` here
      // would flash the error screen on the way to a screen that works. It is
      // still resolved to `failure` if enrichment cannot complete it either
      // (see the null-enrichment branch in [open]), so nothing is left hanging
      // on `loading` forever.
      if (result.outcomes.isEmpty) {
        return DetailsState(
          status: DetailsStatus.loading,
          generation: gen,
          item: item,
        );
      }
      return DetailsState(
        status: DetailsStatus.failure,
        generation: gen,
        item: item,
        failedReferences: _idsOf(result, invalid: false),
        invalidReferences: _idsOf(result, invalid: true),
      );
    }

    return DetailsState(
      status: DetailsStatus.success,
      generation: gen,
      item: item,
      metadata: result.item,
      failedReferences: _idsOf(result, invalid: false),
      invalidReferences: _idsOf(result, invalid: true),
    );
  }

  static List<String> _idsOf(MetadataResult result, {required bool invalid}) =>
      result.outcomes
          .where(
            (ReferenceOutcome o) => invalid
                ? o.isInvalid
                : (o.isFailed || o.kind == ReferenceOutcomeKind.skipped),
          )
          .map((ReferenceOutcome o) => o.reference.extensionId)
          .toList(growable: false);
}

/// The current details session state.
final NotifierProvider<DetailsSessionNotifier, DetailsState>
detailsSessionProvider = NotifierProvider<DetailsSessionNotifier, DetailsState>(
  DetailsSessionNotifier.new,
);
