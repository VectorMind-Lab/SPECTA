/// Pure presentation helpers for the Downloads surface (Phase 2J/2K).
///
/// Deliberately free of Flutter and of any provider: everything the Downloads
/// screen decides about a *record* is a pure function of that record, so the
/// rules that matter — which actions a state permits, what the row says, how
/// the list is ordered — are unit-testable without a widget tree.
///
/// No claim here is invented. A total size the server never declared stays
/// unknown, and a progress bar is only rendered when a real fraction exists.
library;

import '../../core/downloads/download_models.dart';
import '../../core/errors/specta_failure.dart';

/// An action a download row can offer.
enum DownloadAction {
  /// Stop an active transfer, keeping the bytes already on disk.
  pause,

  /// Continue a paused transfer.
  resume,

  /// Re-queue a failed or cancelled transfer.
  retry,

  /// Abandon the transfer and drop the partial file.
  cancel,

  /// Delete the record (and, for a completed download, its file).
  remove,

  /// Play the completed file from disk, offline.
  play,
}

/// Which actions [status] permits.
///
/// Mirrors the manager's state machine exactly (see [DownloadStateMachine]):
/// an action is offered only where the manager will accept it, so the UI can
/// never present a control that silently does nothing.
List<DownloadAction> downloadActionsFor(DownloadStatus status) =>
    switch (status) {
      DownloadStatus.queued ||
      DownloadStatus.downloading => const <DownloadAction>[
        DownloadAction.pause,
        DownloadAction.cancel,
      ],
      DownloadStatus.paused => const <DownloadAction>[
        DownloadAction.resume,
        DownloadAction.cancel,
      ],
      DownloadStatus.failed ||
      DownloadStatus.cancelled => const <DownloadAction>[
        DownloadAction.retry,
        DownloadAction.remove,
      ],
      DownloadStatus.completed => const <DownloadAction>[
        DownloadAction.play,
        DownloadAction.remove,
      ],
    };

/// Short, non-technical state label for a row.
String downloadStateLabel(DownloadStatus status) => switch (status) {
  DownloadStatus.queued => 'Queued',
  DownloadStatus.downloading => 'Downloading',
  DownloadStatus.paused => 'Paused',
  DownloadStatus.completed => 'Downloaded',
  DownloadStatus.failed => 'Failed',
  DownloadStatus.cancelled => 'Cancelled',
};

/// Whether the row offers playback.
bool isPlayable(DownloadStatus status) => status == DownloadStatus.completed;

/// The secondary line under the title: why it is waiting, or why it failed.
///
/// Null when there is nothing honest to add. A wait reason is shown only while
/// the record is actually waiting; a failure message only while it is failed.
String? downloadSecondaryLine(DownloadRecord record) {
  final DownloadWaitReason? waitReason = record.waitReason;
  if (waitReason != null &&
      (record.status == DownloadStatus.queued ||
          record.status == DownloadStatus.paused)) {
    return waitReason.message;
  }

  final DownloadFailure? failure = record.failure;
  if (record.status == DownloadStatus.failed && failure != null) {
    return failure.message;
  }
  return null;
}

/// Progress text: `12.3 MB of 45.6 MB`, or just the downloaded amount when the
/// server never declared a total.
String downloadProgressText(DownloadRecord record) {
  final int? total = record.totalBytes;
  if (total == null || total <= 0) {
    return formatBytes(record.bytesDownloaded);
  }
  return '${formatBytes(record.bytesDownloaded)} of ${formatBytes(total)}';
}

/// A real progress fraction, or null when the total is unknown.
double? downloadFraction(DownloadRecord record) => record.fraction;

/// Human byte count. Decimal units (matching how platforms report file sizes),
/// one fractional digit above kilobytes, never a fabricated precision.
String formatBytes(int bytes) {
  if (bytes < 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  const List<String> units = <String>['KB', 'MB', 'GB', 'TB'];
  double value = bytes / 1024;
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final String rendered = value >= 100
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$rendered ${units[unit]}';
}

/// Display order for the Downloads list.
///
/// Things the user may need to act on come first; finished work comes last.
/// Within a group the order is DETERMINISTIC (creation time, then identity) so
/// the list cannot reshuffle between rebuilds — the same discipline the source
/// ranker uses for its tie-breaks.
List<DownloadRecord> orderDownloadsForDisplay(List<DownloadRecord> records) {
  int priority(DownloadStatus status) => switch (status) {
    DownloadStatus.downloading => 0,
    DownloadStatus.queued => 1,
    DownloadStatus.paused => 2,
    DownloadStatus.failed => 3,
    DownloadStatus.cancelled => 4,
    DownloadStatus.completed => 5,
  };

  final List<DownloadRecord> ordered = List<DownloadRecord>.of(records);
  ordered.sort((DownloadRecord a, DownloadRecord b) {
    final int byPriority =
        priority(a.status).compareTo(priority(b.status));
    if (byPriority != 0) return byPriority;
    final int byCreated = a.createdAt.compareTo(b.createdAt);
    if (byCreated != 0) return byCreated;
    return a.id.compareTo(b.id);
  });
  return ordered;
}

/// The user-facing label for an action, so every surface names it identically.
String downloadActionLabel(DownloadAction action) => switch (action) {
  DownloadAction.pause => 'Pause',
  DownloadAction.resume => 'Resume',
  DownloadAction.retry => 'Retry',
  DownloadAction.cancel => 'Cancel',
  DownloadAction.remove => 'Remove',
  DownloadAction.play => 'Play',
};
