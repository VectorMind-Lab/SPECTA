import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/specta_colors.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/downloads/download_models.dart';
import '../../core/downloads/download_providers.dart';
import '../../core/extensions/contract/result_models.dart';
import '../../ui/widgets/specta_empty_state.dart';
import '../../ui/widgets/specta_focus_wrapper.dart';
import 'download_presentation.dart';
import 'local_playback.dart';

/// Downloads view: the persisted queue and the offline library (Phase 2K).
///
/// This is not a new subsystem — it is the missing SURFACE over the Phase 2G
/// download system. Every row reads a persisted [DownloadRecord]; every action
/// calls the existing [DownloadManager] (which owns the state machine,
/// concurrency, retry and recovery). The screen decides presentation only, and
/// those decisions live in [download_presentation] so they are unit-testable
/// without a widget tree.
///
/// Honesty rules kept here:
/// - a progress bar is rendered only from a real fraction (never invented);
/// - a control is offered only where the manager will accept it
///   ([downloadActionsFor] mirrors the manager's transitions);
/// - a completed file that is gone from disk is refused with an explanation
///   rather than opening a player that would fail obscurely.
class DownloadsView extends ConsumerWidget {
  const DownloadsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<DownloadRecord>> downloads = ref.watch(
      allDownloadsProvider,
    );

    if (downloads.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (downloads.hasError) {
      return const SpectaEmptyState(
        icon: Icons.error_outline,
        message: 'Your downloads could not be read right now.',
      );
    }

    final List<DownloadRecord> records =
        downloads.value ?? const <DownloadRecord>[];
    if (records.isEmpty) {
      return const SpectaEmptyState(
        icon: Icons.download_outlined,
        message:
            'Nothing downloaded yet. Downloads you start will queue here and '
            'stay playable offline.',
      );
    }

    final List<DownloadRecord> ordered = orderDownloadsForDisplay(records);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const _SectionHeader(title: 'Downloads'),
        const _QueueSummary(),
        const SizedBox(height: 8),
        for (final DownloadRecord record in ordered)
          _DownloadTile(record: record),
      ],
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

/// A one-line, honest description of what the queue is doing right now —
/// active attempts vs. the concurrency limit, and how many are waiting.
class _QueueSummary extends ConsumerWidget {
  const _QueueSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DownloadQueueStatus status = ref.watch(downloadQueueStatusProvider);
    final String text = status.queuedCount == 0
        ? '${status.activeCount} of ${status.concurrency} downloading'
        : '${status.activeCount} of ${status.concurrency} downloading · '
              '${status.queuedCount} waiting';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: SpectaColors.textSecondary),
      ),
    );
  }
}

/// One persisted download, rendered in the SPECTA card language and focusable
/// from a TV D-pad.
class _DownloadTile extends ConsumerWidget {
  const _DownloadTile({required this.record});

  final DownloadRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Color accent = Theme.of(context).colorScheme.primary;
    final String? secondary = downloadSecondaryLine(record);
    final double? fraction = downloadFraction(record);
    final List<DownloadAction> actions = downloadActionsFor(record.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
            Row(
              children: <Widget>[
                Icon(
                  record.mediaType == MediaType.series
                      ? Icons.tv_rounded
                      : Icons.movie_rounded,
                  size: 26,
                  color: accent.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        record.title,
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
                          downloadStateLabel(record.status),
                          if (record.subtitleLine != null) record.subtitleLine!,
                        ].join('  ·  '),
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
                const SizedBox(width: 12),
                Text(
                  downloadProgressText(record),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: SpectaColors.textMuted,
                  ),
                ),
              ],
            ),

            // A progress bar only from a real fraction — never a fabricated
            // percentage when the server declared no total.
            if (fraction != null && !isPlayable(record.status)) ...<Widget>[
              const SizedBox(height: 10),
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

            // Waiting/failure explanation, shown only while it is true.
            if (secondary != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                secondary,
                style: TextStyle(
                  fontSize: 11,
                  color: record.status == DownloadStatus.failed
                      ? SpectaColors.warning
                      : SpectaColors.textSecondary,
                ),
              ),
            ],

            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final DownloadAction action in actions)
                  _ActionButton(
                    label: downloadActionLabel(action),
                    icon: _iconFor(action),
                    primary:
                        action == DownloadAction.play ||
                        action == DownloadAction.retry,
                    onPressed: () => _run(context, ref, action),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(DownloadAction action) => switch (action) {
    DownloadAction.pause => Icons.pause_rounded,
    DownloadAction.resume => Icons.play_arrow_rounded,
    DownloadAction.retry => Icons.refresh_rounded,
    DownloadAction.cancel => Icons.close_rounded,
    DownloadAction.remove => Icons.delete_outline_rounded,
    DownloadAction.play => Icons.play_circle_outline_rounded,
  };

  /// Executes one action through the existing manager. A refusal (`false`)
  /// means the state moved between the paint and the tap; it is reported
  /// honestly rather than silently swallowed.
  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    DownloadAction action,
  ) async {
    if (action == DownloadAction.play) {
      await startLocalPlayback(context, ref: ref, record: record);
      return;
    }

    final DownloadManager manager = ref.read(downloadManagerProvider);
    final bool ok = switch (action) {
      DownloadAction.pause => await manager.pause(record.id),
      DownloadAction.resume => await manager.resume(record.id),
      DownloadAction.retry => await manager.retry(record.id),
      DownloadAction.cancel => await manager.cancel(record.id),
      DownloadAction.remove => await manager.remove(record.id),
      DownloadAction.play => true,
    };

    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('That download could not be changed right now.'),
        ),
      );
    }
  }
}

/// A focusable action button (D-pad reachable, like every other SPECTA
/// surface control).
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    return SpectaFocusWrapper(
      borderRadius: SpectaMetrics.buttonRadius,
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: primary ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(SpectaMetrics.buttonRadius),
          border: Border.all(color: primary ? accent : SpectaColors.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 17,
              color: primary
                  ? SpectaColors.background
                  : SpectaColors.textPrimary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: primary
                    ? SpectaColors.background
                    : SpectaColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
