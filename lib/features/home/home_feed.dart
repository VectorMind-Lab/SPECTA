import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/discovery/discovery_coordinator.dart';
import '../../core/discovery/discovery_models.dart';

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
          'No extensions are installed yet. Add one to see movies and series '
              'here.',
        HomeFeedStatus.unsupported =>
          'Your installed extensions do not provide a Home feed. Use Search to '
              'find something to watch.',
        HomeFeedStatus.failure =>
          'Your extensions could not be reached. Check your connection and '
              'try again.',
      };

  /// Classifies a completed round. Pure, so the four distinguishable states
  /// are testable without a widget tree or a live extension.
  static HomeFeed from(DiscoveryResult result) {
    final List<ExtensionDiscoveryOutcome> outcomes = result.outcomes;
    final int failed =
        outcomes.where((ExtensionDiscoveryOutcome o) => o.isFailed).length;
    final int skipped =
        outcomes.where((ExtensionDiscoveryOutcome o) => o.isSkipped).length;

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

    return HomeFeed(
      status: status,
      failedCount: failed,
      skippedCount: skipped,
    );
  }
}

/// The Home feed round. Watched by Home only; a discovery round is a request,
/// not a cache, so re-entering Home asks again (the same discipline as search).
final FutureProvider<HomeFeed> homeFeedProvider =
    FutureProvider<HomeFeed>((Ref ref) async {
  final DiscoveryResult result = await ref.watch(discoveryServiceProvider).latest(1);
  return HomeFeed.from(result);
});
