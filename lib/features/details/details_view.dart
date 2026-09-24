import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/specta_colors.dart';
import '../../core/discovery/discovery_models.dart';
import '../../core/extensions/contract/result_models.dart';
import '../../core/metadata/metadata_models.dart';
import '../../ui/widgets/specta_empty_state.dart';
import '../../ui/widgets/specta_focus_wrapper.dart';
import '../downloads/download_entry.dart';
import '../playback/playback_entry.dart';
import 'details_state.dart';

/// Minimal Phase 2C details surface.
///
/// Shows canonical metadata for one discovery item: title, year, type,
/// overview, genres, rating, runtime for movies; seasons and episodes for
/// series. Every state is honest — no fabricated metadata, no source/playback
/// affordances (2D/2E own those).
///
/// TV-safe: the back action and the content are D-reachable; lists are
/// focusable; nothing is touch-only.
class DetailsView extends ConsumerWidget {
  const DetailsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DetailsState state = ref.watch(detailsSessionProvider);

    return Scaffold(
      backgroundColor: SpectaColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: BackButton(
          onPressed: () {
            ref.read(detailsSessionProvider.notifier).reset();
            Navigator.of(context).maybePop();
          },
        ),
        title: Text(
          state.item?.title ?? 'Details',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: switch (state.status) {
        DetailsStatus.idle => const SpectaEmptyState(
            icon: Icons.info_outline_rounded,
            message: 'Nothing selected',
          ),
        DetailsStatus.loading => const Center(
            child: CircularProgressIndicator(),
          ),
        DetailsStatus.failure => SpectaEmptyState(
            icon: Icons.cloud_off_rounded,
            message: _failureMessage(state),
            actionLabel: 'Retry',
            action: () => _retry(context, ref, state),
          ),
        DetailsStatus.success => _DetailsContent(
            state: state,
            onPlayEpisode: (SeriesEpisode episode) => startPlayback(
              context,
              ref: ref,
              metadata: state.metadata!,
              item: state.item!,
              episode: episode,
            ),
            onDownloadEpisode: (SeriesEpisode episode) => startEpisodeDownload(
              context,
              ref: ref,
              metadata: state.metadata!,
              item: state.item!,
              episode: episode,
            ),
          ),
      },
    );
  }

  static String _failureMessage(DetailsState state) {
    if (state.invalidReferences.isNotEmpty) {
      return 'The extensions responded, but the details could not be trusted. '
          'Try again later.';
    }
    return 'Details could not be loaded — the extensions could not be '
        'reached. Check your connection and try again.';
  }

  static void _retry(BuildContext context, WidgetRef ref, DetailsState state) {
    final DiscoveryItem? item = state.item;
    if (item != null) {
      ref.read(detailsSessionProvider.notifier).open(item);
    }
  }
}

/// The metadata content: header block + (for series) seasons and episodes.
class _DetailsContent extends StatelessWidget {
  const _DetailsContent({
    required this.state,
    required this.onPlayEpisode,
    required this.onDownloadEpisode,
  });

  final DetailsState state;

  /// Called when the user activates one episode of one season.
  final void Function(SeriesEpisode episode) onPlayEpisode;

  /// Called when the user downloads one episode of one season.
  final void Function(SeriesEpisode episode) onDownloadEpisode;

  @override
  Widget build(BuildContext context) {
    final MetadataItem? metadata = state.metadata;
    if (metadata == null) {
      return const SpectaEmptyState(
        icon: Icons.info_outline_rounded,
        message: 'Nothing selected',
      );
    }

    final Color accent = Theme.of(context).colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        _Header(metadata: metadata, accent: accent),
        if (state.isPartial) ...<Widget>[
          const SizedBox(height: 8),
          _PartialNotice(state: state),
        ],
        if ((metadata.details.first.description ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Text(
            metadata.details.first.description!,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: SpectaColors.textSecondary,
            ),
          ),
        ],
        if (metadata.type == MediaType.movie && state.item != null) ...<Widget>[
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              _PlayMovieButton(item: state.item!, metadata: metadata),
              const SizedBox(width: 12),
              _DownloadMovieButton(item: state.item!, metadata: metadata),
            ],
          ),
        ],
        if (metadata.type == MediaType.series)
          ..._seasonsSection(metadata, accent),
      ],
    );
  }

  List<Widget> _seasonsSection(MetadataItem metadata, Color accent) {
    final List<SeriesSeason> seasons = metadata.seasons;
    if (seasons.isEmpty) {
      return <Widget>[
        const SizedBox(height: 24),
        const Text(
          'Seasons',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: SpectaColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'This extension has not reported episode information yet.',
          style: TextStyle(fontSize: 12, color: SpectaColors.textMuted),
        ),
      ];
    }

    return <Widget>[
      const SizedBox(height: 24),
      Text(
        'Seasons (${seasons.length})',
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: SpectaColors.textPrimary,
        ),
      ),
      const SizedBox(height: 8),
      for (final SeriesSeason season in seasons)
        _SeasonCard(
          season: season,
          accent: accent,
          onPlayEpisode: onPlayEpisode,
          onDownloadEpisode: onDownloadEpisode,
        ),
    ];
  }
}

/// Poster/title/year/type/genres/rating/runtime header.
class _Header extends StatelessWidget {
  const _Header({required this.metadata, required this.accent});

  final MetadataItem metadata;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ReferenceMetadata first = metadata.details.first;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 110,
            height: 165,
            color: SpectaColors.surfaceElevated,
            child: metadata.cover != null
                ? Image.network(
                    metadata.cover!,
                    fit: BoxFit.cover,
                    errorBuilder: (
                      BuildContext context,
                      Object error,
                      StackTrace? stackTrace,
                    ) =>
                        Icon(
                          metadata.type == MediaType.movie
                              ? Icons.movie_rounded
                              : Icons.tv_rounded,
                          size: 40,
                          color: accent.withValues(alpha: 0.35),
                        ),
                  )
                : Icon(
                    metadata.type == MediaType.movie
                        ? Icons.movie_rounded
                        : Icons.tv_rounded,
                    size: 40,
                    color: accent.withValues(alpha: 0.35),
                  ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                metadata.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: SpectaColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                <String>[
                  metadata.type == MediaType.movie ? 'Movie' : 'Series',
                  if (metadata.year != null) '${metadata.year}',
                  if (first.rating != null) '★ ${first.rating!.toStringAsFixed(1)}',
                  if (first.durationSeconds != null)
                    _formatRuntime(first.durationSeconds!),
                ].join('  ·  '),
                style: const TextStyle(
                  fontSize: 12,
                  color: SpectaColors.textSecondary,
                ),
              ),
              if (first.genres.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final String genre in first.genres.take(6))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          genre,
                          style: TextStyle(
                            fontSize: 11,
                            color: accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _formatRuntime(int seconds) {
    final int minutes = seconds ~/ 60;
    if (minutes < 60) return '${minutes}m';
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }
}

/// Play affordance for movies: resolves the 2D pool from the item's
/// provenance and opens the player with SPECTA's ordered candidates.
class _PlayMovieButton extends ConsumerWidget {
  const _PlayMovieButton({required this.item, required this.metadata});

  final DiscoveryItem item;

  /// The canonical metadata this item's details session resolved. Passed in
  /// by the content block (never re-read with a null assertion).
  final MetadataItem metadata;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Color accent = Theme.of(context).colorScheme.primary;

    return SpectaFocusWrapper(
      borderRadius: SpectaMetrics.buttonRadius,
      onTap: () => startPlayback(
        context,
        ref: ref,
        metadata: metadata,
        item: item,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(SpectaMetrics.buttonRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.play_arrow_rounded,
                size: 22, color: SpectaColors.background),
            const SizedBox(width: 8),
            Text(
              'Play',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                color: SpectaColors.background,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Download affordance for movies: resolves the same 2D pool the player would
/// and hands it to the download manager.
class _DownloadMovieButton extends ConsumerWidget {
  const _DownloadMovieButton({required this.item, required this.metadata});

  final DiscoveryItem item;
  final MetadataItem metadata;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SpectaFocusWrapper(
      borderRadius: SpectaMetrics.buttonRadius,
      onTap: () => startMovieDownload(
        context,
        ref: ref,
        metadata: metadata,
        item: item,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SpectaMetrics.buttonRadius),
          border: Border.all(color: SpectaColors.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const <Widget>[
            Icon(Icons.download_outlined,
                size: 20, color: SpectaColors.textPrimary),
            SizedBox(width: 8),
            Text(
              'Download',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: SpectaColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small per-episode play affordance (the row itself is the tap target).
class _EpisodePlayIcon extends StatelessWidget {
  const _EpisodePlayIcon();

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    return Icon(Icons.play_circle_outline_rounded,
        size: 20, color: accent.withValues(alpha: 0.8));
  }
}

/// Small per-episode download affordance — a separate focus target so a TV
/// D-pad can reach it without also triggering playback.
class _EpisodeDownloadButton extends StatelessWidget {
  const _EpisodeDownloadButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SpectaFocusWrapper(
      borderRadius: 6,
      onTap: onTap,
      child: const Padding(
        padding: EdgeInsets.all(2),
        child: Icon(
          Icons.download_outlined,
          size: 18,
          color: SpectaColors.textMuted,
        ),
      ),
    );
  }
}

/// Honest partial-failure notice (ids are NOT shown — counts only).
class _PartialNotice extends StatelessWidget {
  const _PartialNotice({required this.state});

  final DetailsState state;

  @override
  Widget build(BuildContext context) {
    final int failed =
        state.failedReferences.length + state.invalidReferences.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: SpectaColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.warning_amber_rounded,
              size: 16, color: SpectaColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Details come from $failed of ${state.item!.references.length} '
              'sources — some could not be reached.',
              style: TextStyle(
                fontSize: 11,
                color: SpectaColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One season with its episodes (expandable; first season expanded).
/// Episodes are individually tappable/focusable play targets (2E).
class _SeasonCard extends StatefulWidget {
  const _SeasonCard({
    required this.season,
    required this.accent,
    required this.onPlayEpisode,
    required this.onDownloadEpisode,
  });

  final SeriesSeason season;
  final Color accent;
  final void Function(SeriesEpisode episode) onPlayEpisode;
  final void Function(SeriesEpisode episode) onDownloadEpisode;

  @override
  State<_SeasonCard> createState() => _SeasonCardState();
}

class _SeasonCardState extends State<_SeasonCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final SeriesSeason season = widget.season;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SpectaFocusWrapper(
        borderRadius: SpectaMetrics.cardRadius,
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SpectaColors.surface,
            borderRadius: BorderRadius.circular(SpectaMetrics.cardRadius),
            border: Border.all(color: SpectaColors.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      season.title?.isNotEmpty == true
                          ? season.title!
                          : 'Season ${season.seasonNumber}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: SpectaColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '${season.episodes.length} episodes',
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.accent.withValues(alpha: 0.8),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: SpectaColors.textMuted,
                    ),
                  ),
                ],
              ),
              if (_expanded) ...<Widget>[
                const SizedBox(height: 8),
                for (final SeriesEpisode episode in season.episodes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SpectaFocusWrapper(
                      borderRadius: 8,
                      onTap: () => widget.onPlayEpisode(episode),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SizedBox(
                              width: 28,
                              child: Text(
                                '${episode.episodeNumber}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: widget.accent,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                episode.title?.isNotEmpty == true
                                    ? episode.title!
                                    : 'Episode ${episode.episodeNumber}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: SpectaColors.textSecondary,
                                ),
                              ),
                            ),
                            if (episode.durationSeconds != null)
                              Text(
                                '${episode.durationSeconds! ~/ 60}m',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: SpectaColors.textMuted,
                                ),
                              ),
                            const SizedBox(width: 8),
                            const _EpisodePlayIcon(),
                            const SizedBox(width: 10),
                            _EpisodeDownloadButton(
                              onTap: () =>
                                  widget.onDownloadEpisode(episode),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
