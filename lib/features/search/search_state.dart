import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/anilist/anilist_client.dart';
import '../../core/anilist/anilist_dto.dart';
import '../../core/anilist/anilist_normalizer.dart';
import '../../core/anilist/anilist_providers.dart';
import '../../core/database/database_capabilities.dart';
import '../../core/discovery/discovery_coordinator.dart';
import '../../core/discovery/discovery_models.dart';
import '../../core/errors/specta_result.dart';

/// User-facing search status. Distinguishes the states the brief requires Ã¢â‚¬â€
/// idle, loading, results, honest empty, partial failure, total failure Ã¢â‚¬â€
/// without exposing raw internal exceptions.
enum SearchStatus {
  /// No search submitted yet.
  idle,

  /// A round is in flight.
  loading,

  /// At least one extension returned results.
  results,

  /// Extensions were queried; none returned results, and none failed.
  empty,

  /// Some extensions returned results, others failed.
  partialFailure,

  /// Every queried extension failed.
  allFailed,

  /// No search-capable extension was available to query.
  noExtensions,
}

/// Immutable snapshot of one search session.
final class SearchState {
  const SearchState({
    required this.status,
    required this.generation,
    this.items = const <DiscoveryItem>[],
    this.failedExtensions = const <String>[],
    this.droppedCount = 0,
    this.page = 1,
    this.catalogueItems = const <DiscoveryItem>[],
  });

  final SearchStatus status;

  /// Monotonic round counter. A response from an older generation is
  /// discarded Ã¢â‚¬â€ "bat" Ã¢â€ â€™ "batm" Ã¢â€ â€™ "batman" can never interleave.
  final int generation;

  /// Unified, deduplicated discovery items (Phase 2B output). The UI renders
  /// these Ã¢â‚¬â€ never per-extension raw results, which would re-duplicate what
  /// deduplication merged.
  final List<DiscoveryItem> items;

  /// Extensions that failed in the latest round (ids only Ã¢â‚¬â€ no raw errors in
  /// the UI layer).
  final List<String> failedExtensions;

  /// Observations dropped by normalization in the latest round.
  final int droppedCount;

  /// The page the latest round requested.
  final int page;

  /// Catalogue-originated results (C4.2) — currently AniList-backed ANIME,
  /// which no extension can discover because no extension serves anime yet.
  ///
  /// These are METADATA identities, not sources. They are kept separate from
  /// [items] on purpose: extension discovery remains the authority for what is
  /// playable, and a catalogue result never silently joins that list.
  final List<DiscoveryItem> catalogueItems;

  /// Everything the round found: extension results first, catalogue metadata
  /// after. The UI renders these in one list and labels each honestly.
  List<DiscoveryItem> get allItems => <DiscoveryItem>[
    ...items,
    ...catalogueItems,
  ];

  static const SearchState initial = SearchState(
    status: SearchStatus.idle,
    generation: 0,
  );

  SearchState copyWith({
    SearchStatus? status,
    int? generation,
    List<DiscoveryItem>? items,
    List<String>? failedExtensions,
    int? droppedCount,
    int? page,
    List<DiscoveryItem>? catalogueItems,
  }) {
    return SearchState(
      status: status ?? this.status,
      generation: generation ?? this.generation,
      items: items ?? this.items,
      failedExtensions: failedExtensions ?? this.failedExtensions,
      droppedCount: droppedCount ?? this.droppedCount,
      page: page ?? this.page,
      catalogueItems: catalogueItems ?? this.catalogueItems,
    );
  }
}

/// Overridable capability probe, so a test can declare that the database is
/// available and then exercise the real catalogue path.
final Provider<bool> catalogueDatabaseUsableProvider = Provider<bool>((
  Ref ref,
) {
  return catalogueDatabaseUsable();
});

/// Drives discovery rounds over the existing query provider from 2A.
///
/// Race handling: a monotonically increasing generation stamps every round.
/// [submit] captures its generation at entry; when the round completes it is
/// applied ONLY if no newer round has started. Rapid query changes therefore
/// resolve to the newest query's results, in order, with no interleaving.
///
/// Pagination: page-based rounds are supported at the service boundary
/// ([SearchRequest.page]); the load-more UI is deliberately deferred Ã¢â‚¬â€ the
/// extension contract's `searchPagination` capability is honoured by the
/// runtime, and page 1 covers the Phase 2B surface.
class SearchSessionNotifier extends Notifier<SearchState> {
  int _generation = 0;
  bool _disposed = false;

  @override
  SearchState build() {
    ref.onDispose(() {
      _disposed = true;
      _generation++; // invalidate any in-flight round
    });
    return SearchState.initial;
  }

  /// Runs a discovery round for [query] on [page].
  Future<void> submit(String query, {int page = 1}) async {
    final SearchRequest request = SearchRequest(query: query, page: page);
    if (!request.isValid) return;

    final int gen = ++_generation;
    state = state.copyWith(
      status: SearchStatus.loading,
      generation: gen,
      page: page,
    );

    final DiscoveryResult outcome;
    try {
      outcome = await ref.read(discoveryServiceProvider).search(request);
    } on Object {
      // Absolute containment: the coordinator is not expected to throw, but
      // the UI layer must never see an exception either.
      _applyIfCurrent(
        gen,
        SearchState(
          status: SearchStatus.allFailed,
          generation: gen,
          page: page,
        ),
      );
      return;
    }
    if (_disposed) return;

    _applyIfCurrent(gen, _stateFrom(outcome, gen, page));

    // Catalogue discovery (C4.2). AniList supplies ANIME metadata identities
    // that no extension can discover, because no extension serves anime yet.
    //
    // Strictly additive and strictly best-effort: an AniList outage must never
    // change the extension results or the round's status, and the results are
    // kept in a separate list so extension discovery stays the sole authority
    // on what is playable.
    final List<DiscoveryItem> anime = await _searchAnime(query);
    if (_disposed) return;
    if (gen != _generation) return; // a newer round won
    if (anime.isEmpty) return;

    final SearchState current = state;
    if (current.generation != gen) return;
    state = current.copyWith(catalogueItems: anime);
  }

  /// AniList-backed anime identities for [query]. Never throws.
  ///
  /// The catalogue client reads through the shared metadata cache, and that
  /// cache needs the local database, which needs platform services. Where those
  /// are unavailable (a headless unit test) the step is skipped rather than
  /// attempted, because the resulting failure would surface as an unhandled
  /// asynchronous error and could not be contained here.
  Future<List<DiscoveryItem>> _searchAnime(String query) async {
    // The catalogue client reads through the shared metadata cache, which needs
    // the local database. Where that cannot be opened — a headless unit test, or
    // a widget test with no storage plugin — the step is skipped rather than
    // attempted, because the resulting failure surfaces asynchronously and
    // could not be contained here.
    if (!ref.read(catalogueDatabaseUsableProvider)) {
      return const <DiscoveryItem>[];
    }
    try {
      final AniListClient client = ref.read(anilistClientProvider);
      final SpectaResult<List<AniListMedia>> result = await client.searchMedia(
        query,
      );
      if (result.isErr) return const <DiscoveryItem>[];
      return <DiscoveryItem>[
        for (final AniListMedia media in result.valueOrNull!)
          AniListNormalizer.toDiscoveryItem(media),
      ];
    } on Object {
      return const <DiscoveryItem>[];
    }
  }

  /// Applies a completed round only if it is still the newest one.
  void _applyIfCurrent(int gen, SearchState next) {
    if (_disposed) return;
    if (gen != _generation) return; // stale round, rejected
    state = next;
  }

  /// Test-only seam: installs [next] as the current state.
  ///
  /// Some presentation states a real round can produce are awkward to reach in
  /// a widget test — `noExtensions` together with catalogue results, for
  /// example. They still have to be renderable, so they must be testable.
  /// Production code never calls this.
  @visibleForTesting
  void debugSetResults(SearchState next) {
    state = next;
  }

  /// Returns the session to its idle state (query cleared / surface left).
  void reset() {
    _generation++; // reject any in-flight round
    state = SearchState.initial;
  }

  SearchState _stateFrom(DiscoveryResult outcome, int gen, int page) {
    final List<DiscoveryItem> items = outcome.items;

    SearchStatus status;
    if (outcome.noExtensionAvailable) {
      status = SearchStatus.noExtensions;
    } else if (outcome.allQueriedFailed) {
      status = SearchStatus.allFailed;
    } else if (items.isEmpty && outcome.failures.isNotEmpty) {
      status = SearchStatus.partialFailure;
    } else if (items.isEmpty) {
      status = SearchStatus.empty;
    } else if (outcome.failures.isNotEmpty) {
      status = SearchStatus.partialFailure;
    } else {
      status = SearchStatus.results;
    }

    return SearchState(
      status: status,
      generation: gen,
      items: items,
      failedExtensions: outcome.failures
          .map((ExtensionDiscoveryOutcome o) => o.extensionId)
          .toList(growable: false),
      droppedCount: outcome.droppedCount,
      page: page,
    );
  }
}

/// The current search session state.
final NotifierProvider<SearchSessionNotifier, SearchState>
searchSessionProvider = NotifierProvider<SearchSessionNotifier, SearchState>(
  SearchSessionNotifier.new,
);
