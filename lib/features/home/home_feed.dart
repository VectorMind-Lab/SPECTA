import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/discovery/discovery_coordinator.dart';
import '../../core/discovery/discovery_models.dart';
import '../../core/errors/specta_failure.dart';
import '../../core/errors/specta_result.dart';
import '../../core/tmdb/tmdb_client.dart';
import '../../core/tmdb/tmdb_config.dart';
import '../../core/tmdb/tmdb_dto.dart';
import '../../core/tmdb/tmdb_normalizer.dart';
import '../../core/tmdb/tmdb_providers.dart';

/// Phase 2K — the Home feed is REAL content, not a design fixture.
///
/// It is one `latest(page)` discovery round across the enabled extensions that
/// declare the `latest` capability — the same pipeline, isolation, capping,
/// normalization and deduplication as search (see [DiscoveryCoordinator]). No
/// provider is special-cased, no content is hard-coded, and nothing is invented
/// when there is nothing to show.
///
/// The classification below exists so the surface can explain itself honestly
/// instead of rendering an empty screen: "no extensions installed", "your
/// extensions do not provide a Home feed", "nothing new right now" and "your
/// extensions could not be reached" are four different facts.
enum HomeFeedStatus {
  /// At least one extension returned at least one item.
  ready,

  /// Extensions answered, but there is nothing to show right now.
  empty,

  /// No enabled extension is installed at all.
  noExtensions,

  /// Extensions are installed, but none of them declares `latest`.
  unsupported,

  /// Every participating extension failed.
  failure,
}

/// One resolved Home feed round.
final class HomeFeed {
  const HomeFeed({
    required this.status,
    this.items = const <DiscoveryItem>[],
    this.failedCount = 0,
    this.skippedCount = 0,
  });

  final HomeFeedStatus status;

  /// Unified, deduplicated discovery items, in first-seen order.
  final List<DiscoveryItem> items;

  /// How many extensions failed this round (isolation: the rest still showed).
  final int failedCount;

  /// How many enabled extensions lack the `latest` capability.
  final int skippedCount;

  bool get hasItems => items.isNotEmpty;

  /// True when content is shown but the round was partly degraded — worth
  /// saying out loud rather than hiding.
  bool get isPartial => hasItems && failedCount > 0;

  /// User-facing, non-technical explanation for every non-ready state.
  String get message => switch (status) {
    HomeFeedStatus.ready => '',
    HomeFeedStatus.empty => 'Nothing new right now.',
    HomeFeedStatus.noExtensions =>
      'No sources are installed yet. Add one to see movies and series '
          'here.',
    HomeFeedStatus.unsupported =>
      'Your installed sources do not provide a Home feed. Use Search to '
          'find something to watch.',
    HomeFeedStatus.failure =>
      'Your extensions could not be reached. Check your connection and '
          'try again.',
  };

  /// Classifies a completed round. Pure, so the four distinguishable states
  /// are testable without a widget tree or a live extension.
  static HomeFeed from(DiscoveryResult result) {
    final List<ExtensionDiscoveryOutcome> outcomes = result.outcomes;
    final int failed = outcomes
        .where((ExtensionDiscoveryOutcome o) => o.isFailed)
        .length;
    final int skipped = outcomes
        .where((ExtensionDiscoveryOutcome o) => o.isSkipped)
        .length;

    if (outcomes.isEmpty) {
      return const HomeFeed(status: HomeFeedStatus.noExtensions);
    }

    if (result.items.isNotEmpty) {
      return HomeFeed(
        status: HomeFeedStatus.ready,
        items: result.items,
        failedCount: failed,
        skippedCount: skipped,
      );
    }

    // Nothing to show. Why matters.
    final HomeFeedStatus status;
    if (skipped == outcomes.length) {
      status = HomeFeedStatus.unsupported;
    } else if (failed == outcomes.length) {
      status = HomeFeedStatus.failure;
    } else {
      status = HomeFeedStatus.empty;
    }

    return HomeFeed(status: status, failedCount: failed, skippedCount: skipped);
  }
}

/// The Home feed round. Watched by Home only; a discovery round is a request,
/// not a cache, so re-entering Home asks again (the same discipline as search).
final FutureProvider<HomeFeed> homeFeedProvider = FutureProvider<HomeFeed>((
  Ref ref,
) async {
  final DiscoveryResult result = await ref
      .watch(discoveryServiceProvider)
      .latest(1);
  return HomeFeed.from(result);
});

/// Catalogue-originated rail items (C4.1).
///
/// Home's primary feed is still the extension `latest()` round — extensions are
/// the authority for what is playable. This rail is a METADATA supplement drawn
/// from the catalogue providers, and it is deliberately separate so a provider
/// outage can never blank the real feed.
enum TrendingStatus {
  /// At least one provider answered.
  ready,

  /// No provider is configured in this build (e.g. no TMDB key). The rail is
  /// simply absent — not an error, and not a broken screen.
  notConfigured,

  /// Providers were consulted and none could be reached.
  failure,
}

/// One resolved trending round.
final class TrendingFeed {
  const TrendingFeed({
    required this.status,
    this.items = const <DiscoveryItem>[],
  });

  final TrendingStatus status;

  /// Catalogue metadata identities. These carry NO extension reference, so they
  /// are not playable yet; the card says so rather than promising a source.
  final List<DiscoveryItem> items;

  bool get hasItems => items.isNotEmpty;

  /// The rail is rendered only when it has real content.
  bool get isVisible => hasItems;
}

/// Trending rail, fed by the catalogue providers through the existing
/// read-through `metadata_cache` (so a warm cache serves it offline).
final FutureProvider<TrendingFeed> trendingFeedProvider =
    FutureProvider<TrendingFeed>((Ref ref) async {
      try {
        final TmdbClient tmdb = ref.watch(tmdbClientProvider);
        final SpectaResult<TmdbMediaPage> popular = await tmdb.getPopularMovies(
          page: 1,
        );

        if (popular.isErr) {
          final SpectaFailure? failure = popular.failureOrNull;
          final bool unconfigured =
              failure is TmdbFailure &&
              (failure.type == TmdbFailureType.notConfigured ||
                  failure.type == TmdbFailureType.invalidKey);
          return TrendingFeed(
            status: unconfigured
                ? TrendingStatus.notConfigured
                : TrendingStatus.failure,
          );
        }

        final TmdbConfig config = ref.watch(tmdbConfigProvider);
        return TrendingFeed(
          status: TrendingStatus.ready,
          items: <DiscoveryItem>[
            for (final TmdbMediaSummary summary in popular.valueOrNull!.results)
              TmdbNormalizer.toDiscoveryItem(
                summary,
                imageBaseUrl: config.imageBaseUrl,
              ),
          ],
        );
      } on Object {
        return const TrendingFeed(status: TrendingStatus.failure);
      }
    });
