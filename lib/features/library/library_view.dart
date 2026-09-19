import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/specta_colors.dart';
import '../../core/discovery/discovery_models.dart';
import '../../core/extensions/contract/result_models.dart';
import '../../core/library/library_providers.dart';
import '../../core/library/watch_progress.dart';
import '../../core/metadata/metadata_models.dart';
import '../../ui/widgets/specta_empty_state.dart';
import '../../ui/widgets/specta_focus_wrapper.dart';
import '../playback/playback_entry.dart';
import '../playback/resume_entry.dart';

/// Library view: Continue Watching and watch history.
///
/// Phase 2F reads both from the persisted progress store — nothing here is a
/// fixture. Continue Watching is the in-progress subset; History is every item
/// the player has reported on, most recent first. Both are focusable so the
/// surface stays usable from a TV D-pad.
///
/// Tapping an item resumes it: the persisted identity + discovery provenance
/// are rebuilt into the existing details/metadata/source/player pipeline. No
/// source URL is stored or reused, and nothing is fabricated on failure.
class LibraryView extends ConsumerWidget {
  const LibraryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<WatchProgress>> continueWatching =
        ref.watch(continueWatchingProvider);
    final AsyncValue<List<WatchProgress>> history =
        ref.watch(watchHistoryProvider);

    if (continueWatching.isLoading || history.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (continueWatching.hasError || history.hasError) {
      return const SpectaEmptyState(
        icon: Icons.error_outline,
        message: 'Your library could not be read right now.',
      );
    }

    final List<WatchProgress> inProgress =
        continueWatching.value ?? const <WatchProgress>[];
    final List<WatchProgress> all = history.value ?? const <WatchProgress>[];

    if (all.isEmpty) {
      return const SpectaEmptyState(
        icon: Icons.video_library_outlined,
        message:
            'Nothing here yet. Play something and your progress, Continue '
            'Watching row and history will appear here.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (inProgress.isNotEmpty) ...<Widget>[
          const _SectionHeader(title: 'Continue Watching'),
          for (final WatchProgress p in inProgress)
            _ProgressTile(progress: p, onTap: () => _resume(context, ref, p)),
          const SizedBox(height: 16),
        ],
        const _SectionHeader(title: 'History'),
        for (final WatchProgress p in all)
          _ProgressTile(
            progress: p,
            showCompleted: true,
            onTap: () => _resume(context, ref, p),
          ),
      ],
    );
  }

  /// Re-opens [progress] through the existing pipeline; failures are honest
  /// and non-throwing.
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: SpectaColors.textPrimary,
        ),
      ),
    );
  }
}

/// One persisted progress item, rendered with the SPECTA card language.
class _ProgressTile extends StatelessWidget {
  const _ProgressTile({
    required this.progress,
    required this.onTap,
    this.showCompleted = false,
  });

  final WatchProgress progress;

  /// Opens the item through the resume pipeline (D-pad/TV safe).
  final VoidCallback onTap;

  /// History rows show a "Watched" marker for finished items.
  final bool showCompleted;

  String get _typeLabel =>
      progress.mediaType == MediaType.series ? 'SERIES' : 'MOVIE';

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    final double? fraction = progress.fraction;
    final String trailing = _trailingLabel();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SpectaFocusWrapper(
        borderRadius: SpectaMetrics.cardRadius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SpectaColors.surfaceElevated,
            borderRadius: BorderRadius.circular(SpectaMetrics.cardRadius),
            border: Border.all(color: SpectaColors.outline),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                progress.mediaType == MediaType.series
                    ? Icons.tv_rounded
                    : Icons.movie_rounded,
                size: 28,
                color: accent.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      progress.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: SpectaColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        _typeLabel,
                        if (progress.subtitleLine != null)
                          progress.subtitleLine!,
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: SpectaColors.textSecondary,
                      ),
                    ),
                    if (fraction != null && !progress.completed) ...<Widget>[
                      const SizedBox(height: 8),
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
                  ],
                ),
              ),
              if (trailing.isNotEmpty) ...<Widget>[
                const SizedBox(width: 12),
                Text(
                  trailing,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: SpectaColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _trailingLabel() {
    if (showCompleted && progress.completed) return 'Watched';
    final Duration? remaining = progress.remaining;
    if (remaining == null || remaining == Duration.zero) return '';
    return '${_formatDuration(remaining)} left';
  }
}

/// `1h 05m` / `42m` / `30s` — compact, no invented precision.
String _formatDuration(Duration d) {
  final int hours = d.inHours;
  final int minutes = d.inMinutes.remainder(60);
  if (hours > 0) {
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }
  if (minutes > 0) return '${minutes}m';
  return '${d.inSeconds}s';
}
