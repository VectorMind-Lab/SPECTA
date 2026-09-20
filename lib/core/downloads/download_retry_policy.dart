import '../errors/specta_failure.dart';

/// Bounded SPECTA-owned retry policy for downloads (Phase 2G-B).
///
/// The manager never hard-codes delays or budgets: this class owns the
/// numbers, and tests exercise it deterministically through the injected
/// [DownloadClock] (no real waiting, ever).
///
/// Attempt semantics (persistence contract §21): an attempt is one engine
/// start for a download identity. The persisted `attempt` column counts the
/// auto-retry budget used in the current run; it survives restart, never
/// goes negative, and is only reset by an explicit user re-request (enqueue
/// on a failed/cancelled record, or manual retry) — never by the automatic
/// retry path.
final class DownloadRetryPolicy {
  /// All parameters are compile-time-constant friendly; `backoffAfter`
  /// clamps against [maxDelay] at runtime, and a misconfigured (negative)
  /// [baseDelay] is a programming error documented here rather than
  /// asserted away.
  const DownloadRetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 1),
  }) : assert(maxAttempts >= 1, 'a retry budget below 1 cannot start work');

  /// Automatic retries allowed per run (the first attempt included).
  final int maxAttempts;

  /// Backoff for the first automatic retry.
  final Duration baseDelay;

  /// Hard ceiling for any single backoff delay.
  final Duration maxDelay;

  /// Whether a failure with [attemptsUsed] attempts already spent may be
  /// retried automatically. Non-retryable failure types never retry, and the
  /// budget is absolute — no infinite retries.
  bool shouldAutoRetry(DownloadFailure failure, int attemptsUsed) =>
      failure.isRetryable && attemptsUsed < maxAttempts;

  /// The backoff to wait after [attemptsUsed] attempts have failed:
  /// exponential (2s, 4s, 8s, … with the default base) and hard-capped at
  /// [maxDelay]. Deterministic and pure.
  Duration backoffAfter(int attemptsUsed) {
    if (attemptsUsed < 1) return baseDelay;
    final int shift = (attemptsUsed - 1).clamp(0, 30);
    final int factor = 1 << shift;
    final Duration delayed = baseDelay * factor;
    return delayed > maxDelay ? maxDelay : delayed;
  }
}

/// Time source + delay scheduler for the download manager.
///
/// Production uses [SystemDownloadClock]. Tests inject a controllable fake so
/// backoff scheduling is deterministic without real waiting.
abstract interface class DownloadClock {
  DateTime now();

  /// Waits for [duration]. Implementations must be safe to abandon (the
  /// manager may be disposed while a backoff delay is pending).
  Future<void> delay(Duration duration);
}

/// The real clock: wall time and real (cancellable-by-disposal) delays.
final class SystemDownloadClock implements DownloadClock {
  const SystemDownloadClock();

  @override
  DateTime now() => DateTime.now();

  @override
  Future<void> delay(Duration duration) => Future<void>.delayed(duration);
}
