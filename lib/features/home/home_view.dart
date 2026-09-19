import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/platform/form_factor.dart';
import '../../app/theme/specta_colors.dart';
import '../../core/extensions/contract/result_models.dart' as contract;
import '../../core/library/library_providers.dart';
import '../../core/library/watch_progress.dart';
import '../../ui/widgets/specta_badge.dart';
import '../../ui/widgets/specta_focus_wrapper.dart';
import 'models/media_item.dart';
import 'state/home_state.dart';
import 'widgets/hero_spotlight_banner.dart';

/// The SPECTA home experience.
///
/// Renders the designed visual home: hero spotlight carousel, continue
/// watching, trending and latest releases rails, using the app's [HomeState].
///
/// Content is currently the supplied design fixture ([HomeState.initial]):
/// the Phase 2B search/discovery pipeline will replace the fixture with real
/// extension-driven results. Nothing here pretends to be live data.
class HomeView extends ConsumerWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HomeState state = ref.watch(homeStateProvider);
    final SpectaFormFactor formFactor = ref.watch(formFactorProvider);

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

              // Hero spotlight carousel.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SpotlightCarousel(item: state.spotlightItem),
              ),

              const SizedBox(height: 20),
              _ContinueWatchingRail(
                fixtureItems: state.continueWatching,
                itemWidth: railPosterWidth,
              ),
              _MediaRail(
                title: 'Trending Now',
                items: state.trending,
                itemWidth: railPosterWidth,
              ),
              _MediaRail(
                title: 'Latest Releases',
                items: state.latestReleases,
                itemWidth: railPosterWidth,
              ),

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

/// Auto-advancing hero carousel with the supplied navigation affordances.
class _SpotlightCarousel extends StatefulWidget {
  const _SpotlightCarousel({required this.item});

  final MediaItem item;

  @override
  State<_SpotlightCarousel> createState() => _SpotlightCarouselState();
}

class _SpotlightCarouselState extends State<_SpotlightCarousel> {
  static const int _itemCount = 5;
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return HeroSpotlightBanner(
      item: widget.item,
      currentIndex: _index,
      itemCount: _itemCount,
      onPrevious: () => setState(() {
        _index = (_index - 1) % _itemCount;
      }),
      onNext: () => setState(() {
        _index = (_index + 1) % _itemCount;
      }),
    );
  }
}

/// Continue Watching, driven by the persisted Phase 2F progress store.
///
/// Real data when the viewer has any; the design fixture otherwise (still
/// fixture content, exactly like the other rails).
class _ContinueWatchingRail extends ConsumerWidget {
  const _ContinueWatchingRail({
    required this.fixtureItems,
    required this.itemWidth,
  });

  final List<MediaItem> fixtureItems;
  final double itemWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<WatchProgress> real =
        ref.watch(continueWatchingProvider).value ?? const <WatchProgress>[];

    if (real.isEmpty) {
      return _MediaRail(
        title: 'Continue Watching',
        items: fixtureItems,
        itemWidth: itemWidth,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Text(
            'Continue Watching',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: SpectaColors.textPrimary,
            ),
          ),
        ),
        SizedBox(
          height: 230,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: real.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: 12),
            itemBuilder: (BuildContext context, int index) =>
                _ProgressCard(progress: real[index], width: itemWidth),
          ),
        ),
      ],
    );
  }
}

/// One real persisted Continue Watching card.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress, required this.width});

  final WatchProgress progress;
  final double width;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    final double? fraction = progress.fraction;

    return SpectaFocusWrapper(
      borderRadius: SpectaMetrics.cardRadius,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(SpectaMetrics.cardRadius),
              child: Container(
                height: 160,
                width: double.infinity,
                color: SpectaColors.surfaceElevated,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Center(
                      child: Icon(
                        progress.mediaType == contract.MediaType.series
                            ? Icons.tv_rounded
                            : Icons.movie_rounded,
                        size: 40,
                        color: accent.withValues(alpha: 0.35),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: SpectaBadge(
                        label: progress.mediaType == contract.MediaType.series
                            ? 'SERIES'
                            : 'MOVIE',
                      ),
                    ),
                    if (fraction != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 3,
                          backgroundColor: Colors.black26,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              progress.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: SpectaColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              progress.subtitleLine ?? 'Watched recently',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: SpectaColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled horizontal media rail.
class _MediaRail extends StatelessWidget {
  const _MediaRail({
    required this.title,
    required this.items,
    required this.itemWidth,
  });

  final String title;
  final List<MediaItem> items;
  final double itemWidth;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: SpectaColors.textPrimary,
            ),
          ),
        ),
        SizedBox(
          height: 230,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: 12),
            itemBuilder: (BuildContext context, int index) {
              return _MediaCard(item: items[index], width: itemWidth);
            },
          ),
        ),
      ],
    );
  }
}

/// A single media card with the supplied poster-fallback presentation.
class _MediaCard extends StatelessWidget {
  const _MediaCard({required this.item, required this.width});

  final MediaItem item;
  final double width;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;

    return SpectaFocusWrapper(
      borderRadius: SpectaMetrics.cardRadius,
      onTap: () {
        // Detail navigation arrives with the Phase 2B/2C pipeline; cards are
        // focusable now so TV navigation behaviour is real from the start.
      },
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Poster block with type badge and optional progress bar.
            ClipRRect(
              borderRadius: BorderRadius.circular(SpectaMetrics.cardRadius),
              child: Container(
                height: 160,
                width: double.infinity,
                color: SpectaColors.surfaceElevated,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (item.backdropUrl != null)
                      Image.network(
                        item.backdropUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (
                          BuildContext context,
                          Object error,
                          StackTrace? stackTrace,
                        ) {
                          return _posterFallback(context);
                        },
                      )
                    else
                      _posterFallback(context),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: SpectaBadge(
                        label: item.type == MediaType.movie ? 'MOVIE' : 'SERIES',
                      ),
                    ),
                    if (item.progressPercentage != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: item.progressPercentage,
                          minHeight: 3,
                          backgroundColor: Colors.black26,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            Text(
              item.title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: SpectaColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              item.subtitleLine,
              style: const TextStyle(
                fontSize: 11,
                color: SpectaColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (item.rating != null) ...<Widget>[
              const SizedBox(height: 2),
              Row(
                children: <Widget>[
                  Icon(Icons.star_rounded, size: 13, color: accent),
                  const SizedBox(width: 3),
                  Text(
                    item.rating!.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: SpectaColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _posterFallback(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            SpectaColors.surfaceElevated,
            SpectaColors.surface.withValues(alpha: 0.6),
          ],
        ),
      ),
      child: Icon(
        item.type == MediaType.movie
            ? Icons.movie_rounded
            : Icons.tv_rounded,
        size: 40,
        color: accent.withValues(alpha: 0.35),
      ),
    );
  }
}
