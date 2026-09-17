import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/discovery/discovery_coordinator.dart';
import '../../core/discovery/discovery_models.dart';

/// User-facing search status. Distinguishes the states the brief requires —
/// idle, loading, results, honest empty, partial failure, total failure —
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
  });

  final SearchStatus status;

  /// Monotonic round counter. A response from an older generation is
  /// discarded — "bat" → "batm" → "batman" can never interleave.
  final int generation;

  /// Unified, deduplicated discovery items (Phase 2B output). The UI renders
  /// these — never per-extension raw results, which would re-duplicate what
  /// deduplication merged.
  final List<DiscoveryItem> items;

  /// Extensions that failed in the latest round (ids only — no raw errors in
  /// the UI layer).
  final List<String> failedExtensions;

  /// Observations dropped by normalization in the latest round.
  final int droppedCount;

  /// The page the latest round requested.
  final int page;

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
  }) {
    return SearchState(
      status: status ?? this.status,
      generation: generation ?? this.generation,
      items: items ?? this.items,
      failedExtensions: failedExtensions ?? this.failedExtensions,
      droppedCount: droppedCount ?? this.droppedCount,
      page: page ?? this.page,
    );
  }
}

/// Drives discovery rounds over the existing query provider from 2A.
///
/// Race handling: a monotonically increasing generation stamps every round.
/// [submit] captures its generation at entry; when the round completes it is
/// applied ONLY if no newer round has started. Rapid query changes therefore
/// resolve to the newest query's results, in order, with no interleaving.
///
/// Pagination: page-based rounds are supported at the service boundary
/// ([SearchRequest.page]); the load-more UI is deliberately deferred — the
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
  }

  /// Applies a completed round only if it is still the newest one.
  void _applyIfCurrent(int gen, SearchState next) {
    if (_disposed) return;
    if (gen != _generation) return; // stale round — reject
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
searchSessionProvider =
    NotifierProvider<SearchSessionNotifier, SearchState>(
      SearchSessionNotifier.new,
    );
