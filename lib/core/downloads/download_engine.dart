import 'dart:async';

import 'download_models.dart';

/// What the engine wants the manager to know while an attempt is running.
///
/// Kept deliberately small and mirroring the 2E playback engine's discipline:
/// the engine only reports facts; the manager decides scheduling, retries and
/// reconciliation. Terminal attempt outcomes do NOT travel through this
/// stream — [DownloadEngine.start] completes with exactly one
/// [DownloadAttemptResult] per attempt.
sealed class DownloadEngineEvent {
  const DownloadEngineEvent();
}

/// A progress tick for the attempt currently running for a download.
///
/// Bytes only — the UI never receives an invented percentage (the size is
/// null when the server did not declare one). High-frequency by nature; the
/// manager coalesces persistence (see the 2G-A persistence contract §10).
final class DownloadEngineProgress extends DownloadEngineEvent {
  const DownloadEngineProgress({
    required this.downloadId,
    required this.bytesOnDisk,
    this.totalBytes,
  });

  /// The SPECTA download identity the attempt belongs to.
  final String downloadId;

  /// Bytes safely written so far.
  final int bytesOnDisk;

  /// The declared total, when the server provided one.
  final int? totalBytes;
}

/// SPECTA-owned download engine abstraction.
///
/// This is the ONLY seam between SPECTA's download manager and whatever
/// performs byte transfers (a future `background_downloader` adapter in 2G-C,
/// a native engine, or a deterministic fake in tests). The manager never
/// imports a downloader package, a plugin type, or a platform API, so the
/// engine stays replaceable by construction.
///
/// Contract:
/// - [start] begins one attempt for [DownloadAttemptInput.downloadId] and
///   must complete with exactly one terminal [DownloadAttemptResult]:
///   completed, paused, cancelled or failed. Pause/cancel are REQUESTED via
///   [pause]/[cancel]; the engine acknowledges them by settling the attempt
///   with the corresponding result (the manager persists the user-visible
///   state itself and treats a late result idempotently).
/// - [events] carries progress ticks while attempts run. It must never carry
///   terminal outcomes.
/// - [isTransferActive] answers, for one SPECTA download identity, whether
///   the engine still holds a live transfer for it — the process-death
///   reconciliation seam (persistence contract §7). It must answer from the
///   engine's own bookkeeping, never from SPECTA's database.
/// - Every method must be safe to call after a failed attempt; engines
///   report problems as [DownloadFailure] data, they do not throw.
abstract interface class DownloadEngine {
  /// Progress events emitted by this engine, in order.
  Stream<DownloadEngineEvent> get events;

  /// Starts one download attempt. The returned future completes exactly once
  /// with the attempt's terminal result.
  Future<DownloadAttemptResult> start(DownloadAttemptInput input);

  /// Requests a pause of the attempt running for [downloadId], if any.
  Future<void> pause(String downloadId);

  /// Requests cancellation of the attempt running for [downloadId], if any.
  Future<void> cancel(String downloadId);

  /// Whether the engine still holds a live transfer for [downloadId].
  ///
  /// The manager consults this at startup for persisted `downloading`
  /// records — process death must never be assumed to mean "still active",
  /// and must never be assumed to mean "dead" either.
  Future<bool> isTransferActive(String downloadId);
}
