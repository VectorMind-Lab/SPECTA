import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/specta_colors.dart';
import '../../core/discovery/discovery_models.dart';
import '../../core/extensions/contract/result_models.dart';
import '../../core/metadata/metadata_models.dart';
import '../../ui/widgets/specta_artwork.dart';
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
        actions: <Widget>[
          if (state.item != null)
            IconButton(
              tooltip: 'Refresh details',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: state.status == DetailsStatus.loading
                  ? null
                  : () => _retry(context, ref, state),
            ),
        ],
      ),
      // A thin bar rather than a full-screen spinner: a refresh must never make
      // the screen emptier than it already was, so metadata that is already
      // resolved stays visible underneath it.
      body: Column(
        children: <Widget>[
          if (state.status == DetailsStatus.loading && state.metadata != null)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: switch (state.status) {
              DetailsStatus.idle => const SpectaEmptyState(
                icon: Icons.info_outline_rounded,
                message: 'Nothing selected',
              ),
              // Loading WITH metadata is a refresh in flight over content that is
              // already on screen. Rendering the spinner here would blank the
              // screen every time the user pulled to refresh.
              DetailsStatus.loading when state.metadata != null => _content(
                context,
                ref,
                state,
              ),
              DetailsStatus.loading => const Center(
                child: CircularProgressIndicator(),
              ),
              DetailsStatus.failure => SpectaEmptyState(
                icon: state.hasExtensionReference
                    ? Icons.cloud_off_rounded
                    : Icons.extension_off_rounded,
                message: _failureMessage(state),
                actionLabel: 'Retry',
                action: () => _retry(context, ref, state),
              ),
              DetailsStatus.success => _content(context, ref, state),
            },
          ),
        ],
      ),
    );
  }

  /// The metadata body, shared by the success and refresh-in-flight states so
  /// the two can never drift apart.
  Widget _content(BuildContext context, WidgetRef ref, DetailsState state) {
    final MetadataItem metadata = state.metadata!;
    final DiscoveryItem item = state.item!;
    return RefreshIndicator(
      onRefresh: () => _retry(context, ref, state),
      color: Theme.of(context).colorScheme.primary,
      backgroundColor: SpectaColors.surfaceElevated,
      child: _DetailsContent(
        state: state,
        onPlayEpisode: (SeriesEpisode episode) => startPlayback(
          context,
          ref: ref,
          metadata: metadata,
          item: item,
          episode: episode,
        ),
        onDownloadEpisode: (SeriesEpisode episode) => startEpisodeDownload(
          context,
          ref: ref,
          metadata: metadata,
          item: item,
          episode: episode,
        ),
      ),
    );
  }

  /// Why details could not be shown, in words that are actually true.
  ///
  /// These are four different situations and they used to collapse into one
  /// message that blamed the network for all of them:
  /// 1. the extensions answered with something untrustworthy;
  /// 2. extensions existed and every one of them failed (a real outage);
  /// 3. NO extension backs this title at all — it came from the metadata
  ///    catalogue, so there was nothing to reach and the connection was never
  ///    the problem;
  /// 4. the catalogue itself could not complete the record.
  static String _failureMessage(DetailsState state) {
    if (state.invalidReferences.isNotEmpty) {
      return 'The sources responded, but the details could not be trusted. '
          'Try again later.';
    }
    if (!state.hasExtensionReference) {
      return 'This title came from the metadata catalogue, and no source '
          'provides details for it. Install a source that covers it.';
    }
    if (state.hasProviderGap) {
      return 'The metadata catalogue could not complete this title. Check your '
          'connection and try again.';
    }
    return 'Details could not be loaded — the sources could not be '
        'reached. Check your connection and try again.';
  }

  /// Re-runs the details round for the current item.
  ///
  /// Returns the in-flight future so [RefreshIndicator] keeps spinning until the
  /// round actually finishes — an unawaited void here would snap the indicator
  /// shut the instant the user let go, before anything had been reloaded.
  static Future<void> _retry(
    BuildContext context,
    WidgetRef ref,
    DetailsState state,
  ) {
    final DiscoveryItem? item = state.item;
    if (item == null) return Future<void>.value();
    return ref
        .read(detailsSessionProvider.notifier)
        .open(item, refresh: state.metadata != null);
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
        if ((metadata.description ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Text(
            metadata.description!,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: SpectaColors.textSecondary,
            ),
          ),
        ],
        // A CATALOGUE-ONLY title has no extension behind it, so Play and
        // Download would both be buttons that cannot do anything. Offering them
        // anyway is a promise the app cannot keep, so the affordance is
        // replaced with the reason and the way out. Confirmed on a real device:
        // the details screen opened correctly for a Home "Popular" movie, and
        // then offered a Play button that had no source to play.
        if (!metadata.isEpisodic && state.item != null) ...<Widget>[
          const SizedBox(height: 16),
          if (metadata.hasExtensionContribution)
            Row(
              children: <Widget>[
                _PlayMovieButton(item: state.item!, metadata: metadata),
                const SizedBox(width: 12),
                _DownloadMovieButton(item: state.item!, metadata: metadata),
              ],
            )
          else
            const _NoSourceNotice(),
        ],
        // Anime is episodic too, so it gets the same season/episode surface as
        // series — but only when it really is episodic. An anime FILM (format
        // MOVIE) is a single title, found on a device run that showed a
        // "Seasons" panel for Spirited Away.
        if (metadata.isEpisodic) ..._seasonsSection(metadata, accent),
      ],
    );
  }

  List<Widget> _seasonsSection(MetadataItem metadata, Color accent) {
    // Seasons that carry NO episodes are not a season list, they are an empty
    // shell: the catalogue knows a show has three seasons but not what is in
    // them, and every episode row would be a play target with nothing behind it.
    // Treating that as "no episodes known" is the honest rendering.
    final List<SeriesSeason> seasons = <SeriesSeason>[
      for (final SeriesSeason season in metadata.seasons)
        if (season.episodes.isNotEmpty) season,
    ];
    if (seasons.isEmpty) {
      // Wording must match WHY there is nothing here. A catalogue-only item
      // (anime found through metadata, with no extension behind it) can never
      // report episodes, so blaming "this extension" would be a lie.
      final bool isCatalogueOnly = !metadata.hasExtensionContribution;
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
        Text(
          isCatalogueOnly
              ? 'No episode list yet — this title came from the metadata '
                    'catalogue. Install a source to discover streams.'
              : 'This source has not reported episode information yet.',
          style: const TextStyle(fontSize: 12, color: SpectaColors.textMuted),
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

/// Stands in for Play/Download when the title has no extension behind it.
///
/// SPECTA will not render an action it cannot honour. The catalogue can tell
/// us a film exists, what it is about and who made it, and it will never tell
/// us where to stream it — that is the extensions' job, exclusively. So when
/// only the catalogue answered, this says so and says what would fix it,
/// instead of presenting two buttons that lead nowhere.
class _NoSourceNotice extends StatelessWidget {
  const _NoSourceNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: SpectaColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SpectaColors.outline),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.extension_off_rounded,
            size: 20,
            color: SpectaColors.textSecondary,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'No streaming source for this title yet. It came from the '
              'metadata catalogue, which does not provide streams — install an '
              'source that covers it to play.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: SpectaColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Poster/title/year/type/genres/rating/runtime header.
class _Header extends StatelessWidget {
  const _Header({required this.metadata, required this.accent});

  final MetadataItem metadata;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    // Merged accessors: the extension's own data still wins, but catalogue
    // enrichment (TMDB/TVMaze/AniList) now actually reaches the screen
    // instead of being hidden behind `details.first`.
    final List<String> genres = metadata.genres;
    final double? rating = metadata.rating;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SpectaArtwork(
          url: metadata.cover,
          width: 110,
          height: 165,
          fallbackIcon: _iconFor(metadata.type),
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
                  _typeLabel(metadata.type),
                  if (metadata.year != null) '${metadata.year}',
                  if (rating != null) '★ ${rating.toStringAsFixed(1)}',
                  if (metadata.format != null) metadata.format!,
                ].join('  ·  '),
                style: const TextStyle(
                  fontSize: 12,
                  color: SpectaColors.textSecondary,
                ),
              ),
              if (metadata.type == MediaType.anime &&
                  metadata.episodeCount != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  '${metadata.episodeCount} episodes',
                  style: const TextStyle(
                    fontSize: 12,
                    color: SpectaColors.textMuted,
                  ),
                ),
              ],
              if (genres.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final String genre in genres.take(6))
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

  /// User-facing content-type label. Anime is its own label, not "Series".
  static String _typeLabel(MediaType type) => switch (type) {
    MediaType.movie => 'Movie',
    MediaType.series => 'Series',
    MediaType.anime => 'Anime',
  };

  static IconData _iconFor(MediaType type) => switch (type) {
    MediaType.movie => Icons.movie_rounded,
    MediaType.series => Icons.tv_rounded,
    MediaType.anime => Icons.animation_rounded,
  };
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
      onTap: () =>
          startPlayback(context, ref: ref, metadata: metadata, item: item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(SpectaMetrics.buttonRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.play_arrow_rounded,
              size: 22,
              color: SpectaColors.background,
            ),
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
      onTap: () =>
          startMovieDownload(context, ref: ref, metadata: metadata, item: item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SpectaMetrics.buttonRadius),
          border: Border.all(color: SpectaColors.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const <Widget>[
            Icon(
              Icons.download_outlined,
              size: 20,
              color: SpectaColors.textPrimary,
            ),
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
    return Icon(
      Icons.play_circle_outline_rounded,
      size: 20,
      color: accent.withValues(alpha: 0.8),
    );
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
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: SpectaColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Details come from $failed of ${state.item!.references.length} '
              'sources — some could not be reached.',
              style: TextStyle(fontSize: 11, color: SpectaColors.textSecondary),
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
                              onTap: () => widget.onDownloadEpisode(episode),
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
