import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/platform/form_factor.dart';
import '../../app/theme/specta_colors.dart';
import '../../core/discovery/discovery_models.dart';
import '../../core/extensions/contract/result_models.dart';
import '../../core/library/library_providers.dart';
import '../../core/library/watch_progress.dart';
import '../../core/metadata/metadata_models.dart';
import '../../ui/widgets/specta_empty_state.dart';
import '../../ui/widgets/specta_focus_wrapper.dart';
import '../details/details_state.dart';
import '../details/details_view.dart';
import '../playback/playback_entry.dart';
import '../playback/resume_entry.dart';
import 'home_feed.dart';
import 'widgets/hero_spotlight_banner.dart';

/// The Home surface (Phase 2K).
///
/// Every pixel of content here is real and derived from the running system:
///
/// * the hero and the rail are one `latest(page)` discovery round across the
///   user's enabled extensions ([homeFeedProvider]) — no hard-coded titles, no
///   bundled stock artwork, and no "Trending" ranking SPECTA does not compute;
/// * Continue Watching is the persisted progress the player actually reported.
///
/// When there is nothing to show, Home says WHY (no extensions installed,
/// extensions without a Home feed, nothing new, or providers unreachable)
/// instead of rendering an empty screen — or invented content.
class HomeView extends ConsumerWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SpectaFormFactor formFactor = ref.watch(formFactorProvider);
    final AsyncValue<HomeFeed> feed = ref.watch(homeFeedProvider);
    final AsyncValue<TrendingFeed> trendingAsync = ref.watch(
      trendingFeedProvider,
    );
    final AsyncValue<List<WatchProgress>> continueWatching = ref.watch(
      continueWatchingProvider,
    );

    // A catalogue outage must never blank or block the real extension feed, so
    // an unresolved or failed trending round simply contributes no rail.
    final TrendingFeed trending =
        trendingAsync.value ??
        const TrendingFeed(status: TrendingStatus.failure);

    if (feed.isLoading && !feed.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    final HomeFeed? data = feed.value;
    final List<WatchProgress> inProgress =
        continueWatching.value ?? const <WatchProgress>[];

    // The empty-extension-feed case is NOT an empty screen. A configured
    // catalogue (TMDB) can still supply real content, so the layout below is
    // rendered whenever ANY section has something to show. Previously the
    // `!data.hasItems` branch returned early, which hid the "Popular" rail even
    // though its request had succeeded — the rail was simply never built.
    final bool extensionFeedIsEmpty = data == null || !data.hasItems;
    final bool nothingToShow =
        extensionFeedIsEmpty && !trending.isVisible && inProgress.isEmpty;

    if (nothingToShow) {
      final bool unreachable =
          feed.hasError || data?.status == HomeFeedStatus.failure;
      // Retry only where retrying could actually change the answer.
      final bool retryable =
          unreachable || data?.status == HomeFeedStatus.empty;
      return SpectaEmptyState(
        icon: unreachable ? Icons.cloud_off_rounded : Icons.explore_outlined,
        message: unreachable
            ? 'Your extensions could not be reached. Check your connection and '
                  'try again.'
            : data?.message ?? 'Nothing to show yet.',
        actionLabel: retryable ? 'Retry' : null,
        action: retryable ? () => ref.invalidate(homeFeedProvider) : null,
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int crossAxisCount = formFactor.isLargeScreen ? 6 : 3;
        final double railPosterWidth =
            (constraints.maxWidth - (crossAxisCount - 1) * 12) / crossAxisCount;
        // With no extensions the feed cannot be re-read into anything, but the
        // surface must still say WHY the discovery rails are missing, so the
        // explanation becomes an inline notice instead of a whole-screen state.
        final bool unreachable =
            feed.hasError || data?.status == HomeFeedStatus.failure;
        final bool extensionNoticeRetryable =
            unreachable || data?.status == HomeFeedStatus.empty;

        return RefreshIndicator(
          onRefresh: () => _refresh(context, ref),
          color: Theme.of(context).colorScheme.primary,
          backgroundColor: SpectaColors.surfaceElevated,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 16),
                // The hero and the discovery rail both come from the extension
                // round, so they only exist when that round produced something.
                if (data != null && data.hasItems) ...<Widget>[
                  _Hero(
                    items: data.items,
                    onPlay: (DiscoveryItem item) => _play(context, ref, item),
                    onMoreInfo: (DiscoveryItem item) =>
                        _openDetails(context, ref, item),
                  ),
                  if (data.isPartial) ...<Widget>[
                    const SizedBox(height: 12),
                    _PartialNotice(failedCount: data.failedCount),
                  ],
                ],
                if (extensionFeedIsEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  _ExtensionNotice(
                    unreachable: unreachable,
                    message: data?.message ?? 'Nothing to show yet.',
                    retryable: extensionNoticeRetryable,
                    onRetry: () => ref.invalidate(homeFeedProvider),
                  ),
                ],
                if (inProgress.isNotEmpty)
                  _Rail(
                    title: 'Continue Watching',
                    height: 150,
                    itemWidth: railPosterWidth,
                    itemCount: inProgress.length,
                    itemBuilder: (int index) => _ContinueCard(
                      progress: inProgress[index],
                      onTap: () => _resume(context, ref, inProgress[index]),
                    ),
                  ),
                if (data != null && data.hasItems)
                  _Rail(
                    title: 'New on SPECTA',
                    height: 210,
                    itemWidth: railPosterWidth,
                    itemCount: data.items.length,
                    itemBuilder: (int index) => _DiscoveryCard(
                      item: data.items[index],
                      width: railPosterWidth,
                      onTap: () =>
                          _openDetails(context, ref, data.items[index]),
                    ),
                  ),
                // Catalogue rail (C4.1). Rendered only when a provider actually
                // returned real items, so an unconfigured or unreachable
                // provider simply omits it instead of showing an error block.
                if (trending.isVisible)
                  _Rail(
                    title: 'Popular',
                    height: 210,
                    itemWidth: railPosterWidth,
                    itemCount: trending.items.length,
                    itemBuilder: (int index) => _DiscoveryCard(
                      item: trending.items[index],
                      width: railPosterWidth,
                      onTap: () =>
                          _openDetails(context, ref, trending.items[index]),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Pull-to-refresh: re-runs BOTH Home rounds.
  ///
  /// The extension round and the catalogue round are separate requests with
  /// separate lifetimes, so invalidating only one leaves the screen showing a
  /// mixture of old and new content. The invalidations are fired together and
  /// then awaited, so the indicator stays up until the slower of the two has
  /// actually answered rather than snapping shut early.
  ///
  /// The catalogue round reads through the shared TTL cache, so a refresh
  /// inside the TTL re-serves warm data — cheap, and still correct: a pull is a
  /// request, not a cache purge.
  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    ref.invalidate(homeFeedProvider);
    ref.invalidate(trendingFeedProvider);
    await Future.wait(<Future<void>>[
      ref.read(homeFeedProvider.future),
      ref.read(trendingFeedProvider.future),
    ]);
  }

  /// Opens the canonical details surface for [item] (which owns metadata and
  /// offers Play/Download). The details session, not this surface, performs
  /// the metadata request — so a stale tap can never render old data.
  void _openDetails(BuildContext context, WidgetRef ref, DiscoveryItem item) {
    ref.read(detailsSessionProvider.notifier).open(item);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext _) => const DetailsView()),
    );
  }

  /// Plays [item] straight from Home through the UNCHANGED pipeline: canonical
  /// metadata first (via the same lookup resume uses), then SPECTA's ordered
  /// source resolution and the player. A provider that cannot answer is stated
  /// plainly rather than papered over.
  Future<void> _play(
    BuildContext context,
    WidgetRef ref,
    DiscoveryItem item,
  ) async {
    MetadataItem? metadata;
    try {
      metadata = await ref.read(metadataLookupProvider)(item);
    } on Object {
      metadata = null; // absolute containment — never a throw into the UI
    }
    if (!context.mounted) return;
    if (metadata == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Its provider could not supply details right now. Try again later.',
          ),
        ),
      );
      return;
    }
    await startPlayback(context, ref: ref, metadata: metadata, item: item);
  }

  /// Re-opens a persisted item through the existing resume pipeline.
  Future<void> _resume(
    BuildContext context,
    WidgetRef ref,
    WatchProgress progress,
  ) async {
    if (!context.mounted) return;
    final ResumeResult result = await resumeWatchProgress(
      ref: ref,
      progress: progress,
      starter:
          ({
            required MetadataItem metadata,
            required DiscoveryItem item,
            SeriesEpisode? episode,
            Duration? startPosition,
          }) => startPlayback(
            context,
            ref: ref,
            metadata: metadata,
            item: item,
            episode: episode,
            startPosition: startPosition,
          ),
    );
    if (!context.mounted || result.started) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(result.message),
      ),
    );
  }
}

/// The hero, cycling only through items the feed actually returned.
class _Hero extends StatefulWidget {
  const _Hero({
    required this.items,
    required this.onPlay,
    required this.onMoreInfo,
  });

  final List<DiscoveryItem> items;
  final void Function(DiscoveryItem item) onPlay;
  final void Function(DiscoveryItem item) onMoreInfo;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final List<DiscoveryItem> items = widget.items;
    final int index = _index.clamp(0, items.length - 1);
    final DiscoveryItem item = items[index];
    final bool multiple = items.length > 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: HeroSpotlightBanner(
        title: item.title,
        typeLabel: item.type == MediaType.movie ? 'MOVIE' : 'SERIES',
        subtitle: item.year?.toString() ?? '',
        coverUrl: item.cover,
        onPrimary: () => widget.onPlay(item),
        onMoreInfo: () => widget.onMoreInfo(item),
        onPrevious: multiple
            ? () => setState(
                () => _index = (index - 1 + items.length) % items.length,
              )
            : null,
        onNext: multiple
            ? () => setState(() => _index = (index + 1) % items.length)
            : null,
        currentIndex: index,
        itemCount: items.length,
      ),
    );
  }
}

/// Honest partial-failure notice: some extensions answered, some did not.
class _PartialNotice extends StatelessWidget {
  const _PartialNotice({required this.failedCount});

  final int failedCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: SpectaColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.warning_amber_rounded,
              size: 16,
              color: SpectaColors.warning,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                failedCount == 1
                    ? 'One of your extensions could not be reached.'
                    : '$failedCount of your extensions could not be reached.',
                style: const TextStyle(
                  fontSize: 11,
                  color: SpectaColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explains, inline, why the extension-driven rails are missing.
///
/// This is the same information the full-screen `SpectaEmptyState` used to
/// carry, but scoped to the section it applies to. It appears beside — not
/// instead of — catalogue content, so a configured TMDB rail stays visible
/// while the user is still told their extensions are the reason nothing is
/// playable. Styled like [_PartialNotice] so Home keeps one notice language.
class _ExtensionNotice extends StatelessWidget {
  const _ExtensionNotice({
    required this.unreachable,
    required this.message,
    required this.retryable,
    required this.onRetry,
  });

  /// Whether extensions failed to be reached, as opposed to simply having
  /// nothing to show.
  final bool unreachable;

  /// The feed's own honest explanation.
  final String message;

  /// Whether retrying could actually change the answer.
  final bool retryable;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final Color accent = unreachable
        ? SpectaColors.warning
        : SpectaColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: unreachable
              ? SpectaColors.warning.withValues(alpha: 0.12)
              : SpectaColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: SpectaColors.outline),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              unreachable
                  ? Icons.cloud_off_rounded
                  : Icons.extension_off_rounded,
              size: 16,
              color: accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 12,
                  color: SpectaColors.textSecondary,
                ),
              ),
            ),
            if (retryable)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// A titled, horizontally scrolling rail.
class _Rail extends StatelessWidget {
  const _Rail({
    required this.title,
    required this.height,
    required this.itemWidth,
    required this.itemCount,
    required this.itemBuilder,
  });

  final String title;
  final double height;
  final double itemWidth;
  final int itemCount;
  final Widget Function(int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: SpectaColors.textPrimary,
            ),
          ),
        ),
        SizedBox(
          height: height,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: itemCount,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: 12),
            itemBuilder: (BuildContext context, int index) =>
                itemBuilder(index),
          ),
        ),
      ],
    );
  }
}

/// A real discovery item as a focusable card.
class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({
    required this.item,
    required this.width,
    required this.onTap,
  });

  final DiscoveryItem item;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;

    return SpectaFocusWrapper(
      borderRadius: SpectaMetrics.cardRadius,
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // The poster takes whatever height is left after the title, so a
            // two-line title can never overflow the rail.
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(SpectaMetrics.cardRadius),
                child: Container(
                  width: double.infinity,
                  color: SpectaColors.surfaceElevated,
                  child: item.cover != null
                      ? Image.network(
                          item.cover!,
                          fit: BoxFit.cover,
                          errorBuilder: (
                            BuildContext context,
                            Object error,
                            StackTrace? stackTrace,
                          ) => _PosterFallback(accent: accent),
                        )
                      : _PosterFallback(accent: accent),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: SpectaColors.textPrimary,
              ),
            ),
            if (item.year != null)
              Text(
                '${item.year}',
                style: const TextStyle(
                  fontSize: 11,
                  color: SpectaColors.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.movie_outlined,
        size: 32,
        color: accent.withValues(alpha: 0.5),
      ),
    );
  }
}

/// A persisted Continue Watching item; tapping resumes it.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.progress, required this.onTap});

  final WatchProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    final double? fraction = progress.fraction;

    return SpectaFocusWrapper(
      borderRadius: SpectaMetrics.cardRadius,
      onTap: onTap,
      child: SizedBox(
        width: 200,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SpectaColors.surfaceElevated,
            borderRadius: BorderRadius.circular(SpectaMetrics.cardRadius),
            border: Border.all(color: SpectaColors.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                progress.mediaType == MediaType.series
                    ? Icons.tv_rounded
                    : Icons.movie_rounded,
                size: 24,
                color: accent.withValues(alpha: 0.8),
              ),
              const SizedBox(height: 8),
              Text(
                progress.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: SpectaColors.textPrimary,
                ),
              ),
              if (progress.subtitleLine != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  progress.subtitleLine!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: SpectaColors.textSecondary,
                  ),
                ),
              ],
              const Spacer(),
              if (fraction != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 4,
                    backgroundColor: SpectaColors.surfaceHighlight,
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
