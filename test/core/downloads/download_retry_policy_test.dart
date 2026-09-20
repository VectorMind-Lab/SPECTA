@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/downloads/download_retry_policy.dart';
import 'package:specta/core/errors/specta_failure.dart';

// PHASE 2G-B retry-policy unit tests (§19/§20/§21): pure, deterministic, no
// clock involved — the policy is a function of (failure, attemptsUsed) only.
// The manager-level integration (retry actually re-queueing, cancellation of
// a scheduled retry, budget across restart) is covered in
// download_manager_test.dart; this file pins the POLICY ITSELF.
void main() {
  group('retryability (§19/§22)', () {
    test('retryable failure types are marked retryable in the failure model',
        () {
      // The manager delegates classification to the failure model; these
      // assertions pin the documented classification contract.
      expect(DownloadFailureType.networkError.retryable, isTrue);
      expect(DownloadFailureType.timeout.retryable, isTrue);
      expect(DownloadFailureType.serverError.retryable, isTrue);
      expect(DownloadFailureType.storageFailure.retryable, isTrue);
      expect(DownloadFailureType.interrupted.retryable, isTrue);
    });

    test('non-retryable failure types never retry', () {
      expect(DownloadFailureType.httpError.retryable, isFalse);
      expect(DownloadFailureType.invalidResponse.retryable, isFalse);
      expect(DownloadFailureType.insufficientStorage.retryable, isFalse);
      expect(DownloadFailureType.unsupportedSource.retryable, isFalse);
      expect(DownloadFailureType.sourcesExhausted.retryable, isFalse);
      expect(DownloadFailureType.engineFailure.retryable, isFalse);
    });

    test('a retryable failure within budget is auto-retried', () {
      const DownloadRetryPolicy policy = DownloadRetryPolicy();
      final DownloadFailure failure = DownloadFailure(
        type: DownloadFailureType.networkError,
        message: 'connection reset',
      );

      expect(policy.shouldAutoRetry(failure, 0), isTrue);
      expect(policy.shouldAutoRetry(failure, 1), isTrue);
      expect(policy.shouldAutoRetry(failure, 2), isTrue);
    });

    test('the retry budget is absolute — no infinite retries', () {
      const DownloadRetryPolicy policy = DownloadRetryPolicy();
      final DownloadFailure failure = DownloadFailure(
        type: DownloadFailureType.timeout,
        message: 'stalled',
      );

      // Default budget is 3 attempts; the 3rd failure ends the chain.
      expect(policy.shouldAutoRetry(failure, 3), isFalse);
      expect(policy.shouldAutoRetry(failure, 4), isFalse);
      expect(policy.shouldAutoRetry(failure, 100), isFalse);
    });

    test('a non-retryable failure is refused regardless of budget', () {
      const DownloadRetryPolicy policy = DownloadRetryPolicy();
      final DownloadFailure failure = DownloadFailure(
        type: DownloadFailureType.unsupportedSource,
        message: 'HLS-only pool',
      );

      expect(policy.shouldAutoRetry(failure, 0), isFalse);
      expect(policy.shouldAutoRetry(failure, 1), isFalse);
    });

    test('a custom budget is respected', () {
      const DownloadRetryPolicy policy = DownloadRetryPolicy(maxAttempts: 5);
      final DownloadFailure failure = DownloadFailure(
        type: DownloadFailureType.networkError,
        message: 'flaky',
      );

      expect(policy.shouldAutoRetry(failure, 4), isTrue);
      expect(policy.shouldAutoRetry(failure, 5), isFalse);
    });
  });

  group('exponential backoff (§20)', () {
    test('delays double from the base: 2s, 4s, 8s, 16s', () {
      const DownloadRetryPolicy policy = DownloadRetryPolicy(
        baseDelay: Duration(seconds: 2),
        maxDelay: Duration(minutes: 10),
      );

      expect(policy.backoffAfter(0), const Duration(seconds: 2));
      expect(policy.backoffAfter(1), const Duration(seconds: 2));
      expect(policy.backoffAfter(2), const Duration(seconds: 4));
      expect(policy.backoffAfter(3), const Duration(seconds: 8));
      expect(policy.backoffAfter(4), const Duration(seconds: 16));
    });

    test('the delay is hard-capped at maxDelay', () {
      const DownloadRetryPolicy policy = DownloadRetryPolicy(
        baseDelay: Duration(seconds: 2),
        maxDelay: Duration(seconds: 5),
      );

      expect(policy.backoffAfter(1), const Duration(seconds: 2));
      expect(policy.backoffAfter(2), const Duration(seconds: 4));
      expect(policy.backoffAfter(3), const Duration(seconds: 5),
          reason: '8s would exceed the 5s cap');
      expect(policy.backoffAfter(10), const Duration(seconds: 5),
          reason: 'the cap holds forever — no unbounded growth');
    });

    test('the default policy caps at one minute', () {
      const DownloadRetryPolicy policy = DownloadRetryPolicy();

      expect(policy.backoffAfter(6), const Duration(minutes: 1),
          reason: '64s would exceed the 60s cap');
      expect(policy.backoffAfter(50), const Duration(minutes: 1));
    });

    test('attempts below 1 fall back to the base delay (defensive)', () {
      const DownloadRetryPolicy policy = DownloadRetryPolicy(
        baseDelay: Duration(seconds: 2),
      );

      // A caller should never ask about 0 attempts, but the policy must not
      // blow up (e.g. negative shift) if it does.
      expect(policy.backoffAfter(0), const Duration(seconds: 2));
    });

    test('very large attempt counts cannot overflow the shift', () {
      const DownloadRetryPolicy policy = DownloadRetryPolicy(
        baseDelay: Duration(seconds: 2),
        maxDelay: Duration(minutes: 1),
      );

      // The shift is clamped to 30 internally; this must stay bounded.
      expect(policy.backoffAfter(1000), const Duration(minutes: 1));
    });
  });

  group('attempt semantics (§21)', () {
    test('the default budget is 3 attempts', () {
      const DownloadRetryPolicy policy = DownloadRetryPolicy();
      expect(policy.maxAttempts, 3);
    });

    test('a budget below 1 is a compile-time programming error', () {
      // The const assert guards misconfiguration; verify it fires.
      expect(
        () => DownloadRetryPolicy(maxAttempts: 0),
        throwsA(anything),
      );
      expect(
        () => DownloadRetryPolicy(maxAttempts: -3),
        throwsA(anything),
      );
    });
  });
}
