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
    final AsyncValue<List<WatchProgress>> continueWatching =
        ref.watch(continueWatchingProvider);

    if (feed.isLoading && !feed.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    final HomeFeed? data = feed.value;
    final List<WatchProgress> inProgress =
        continueWatching.value ?? const <WatchProgress>[];

    if (data == null || !data.hasItems) {
      final bool unreachable =
          feed.hasError || data?.status == HomeFeedStatus.failure;
      // Retry only where retrying could actually change the answer.
      final bool retryable = unreachable || data?.status == HomeFeedStatus.empty;
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

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 16),
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
              _Rail(
                title: 'New on SPECTA',
                height: 210,
                itemWidth: railPosterWidth,
                itemCount: data.items.length,
                itemBuilder: (int index) => _DiscoveryCard(
                  item: data.items[index],
                  width: railPosterWidth,
                  onTap: () => _openDetails(context, ref, data.items[index]),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
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
    await startPlayback(
      context,
      ref: ref,
      metadata: metadata,
      item: item,
    );
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
      starter: ({
        required MetadataItem metadata,
        required DiscoveryItem item,
        SeriesEpisode? episode,
        Duration? startPosition,
      }) =>
          startPlayback(
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
                          ) =>
                              _PosterFallback(accent: accent),
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
