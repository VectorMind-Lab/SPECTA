@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/downloads/download_dao.dart';
import 'package:specta/core/downloads/download_manager.dart';
import 'package:specta/core/downloads/download_models.dart';
import 'package:specta/core/downloads/download_retry_policy.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/downloads/device_environment.dart';
import 'package:specta/core/extensions/contract/extension_source.dart';
import 'package:specta/core/sources/source_models.dart';
import 'package:specta/core/sources/source_pool.dart';

import '../../support/fake_download_engine.dart';

// PHASE 2G-B orchestration tests.
//
// Persistence is the REAL SQLite path (a file database per test), the engine
// is the deterministic fake, the clock is virtual — every assertion below is
// deterministic, with no real waiting anywhere.
//
// Fake-engine note: an attempt with no scripted outcome stays IN FLIGHT until
// settle()d — that is how tests hold slots deterministically. settle()
// completes the OLDEST in-flight attempt for a download, so a test can hold
// an old attempt unresolved, start a newer one, and settle the old one LATE:
// that is the genuine stale-callback scenario the manager must survive.

/// A provably-unmetered network: the permissive case the queue tests need.
class _WifiDeviceEnvironment implements DeviceEnvironment {
  @override
  Future<NetworkAccess?> networkAccess() async => NetworkAccess.wifi;

  @override
  Future<int?> freeBytes(String path) async => null;
}

/// Answers null for the first N calls, then the given pool — the honest
/// source-recovery scenario (resolution fails, then recovers).
class _RecoveringResolver implements DownloadSourceResolver {
  _RecoveringResolver(this._failuresBeforeRecovery, this._pool);

  final int _failuresBeforeRecovery;
  final SourcePool _pool;
  int _calls = 0;

  @override
  Future<SourcePool?> resolveSource(DownloadRecord record) async {
    final int call = _calls++;
    return call < _failuresBeforeRecovery ? null : _pool;
  }
}

void main() {
  late Directory tempDir;
  late String dbPath;
  late String mediaDir;
  late SpectaDatabase db;
  late FakeDownloadEngine engine;
  late FakeDownloadClock clock;
  late DownloadManager manager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('specta_2gb');
    dbPath = '${tempDir.path}${Platform.pathSeparator}downloads_manager.db';
    mediaDir = '${tempDir.path}${Platform.pathSeparator}media';
    await Directory(mediaDir).create(recursive: true);
    db = SpectaDatabase(NativeDatabase(File(dbPath)));
    engine = FakeDownloadEngine();
    clock = FakeDownloadClock();
    manager = DownloadManager(
      store: DownloadDao(db),
      engine: engine,
      environment: _WifiDeviceEnvironment(),
      clock: clock,
      mediaDirectory: () async => mediaDir,
    );
    await manager.initialize();
  });

  tearDown(() async {
    await manager.dispose();
    engine.dispose();
    await db.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  DownloadRequest request(String id, {SourcePool? pool}) => DownloadRequest(
        id: id,
        mediaKey: id,
        mediaType: MediaType.movie,
        title: 'Title $id',
        extensions: const <String, String>{'extA': 'ref-a'},
        pool: pool ?? _mp4Pool(),
      );

  Future<DownloadRecord> recordOf(String id) async =>
      (await manager.store.recordFor(id))!;

  group('queue + concurrency', () {
    test('default concurrency is the agreed 3 and clamping never disables it',
        () async {
      expect(DownloadManager.defaultConcurrency, 3);
      expect(DownloadManager.maxConcurrency, 9);
      expect(manager.concurrency, 3);

      await manager.updateConcurrency(0);
      expect(manager.concurrency, 3,
          reason: '0 clamps to the default, never to unlimited');
      await manager.updateConcurrency(-5);
      expect(manager.concurrency, 3);
      await manager.updateConcurrency(99);
      expect(manager.concurrency, 9, reason: 'the 9 ceiling is enforced');
      await manager.updateConcurrency(5);
      expect(manager.concurrency, 5);
      await manager.updateConcurrency(3);
    });

    test('FIFO: the queue starts oldest-first up to the concurrency limit',
        () async {
      // Nothing settles until told: a, b, c occupy all 3 slots.
      await manager.enqueue(request('a|movie|1'));
      await manager.enqueue(request('b|movie|1'));
      await manager.enqueue(request('c|movie|1'));
      await manager.enqueue(request('d|movie|1'));
      await manager.enqueue(request('e|movie|1'));
      await manager.debugIdle;

      expect(engine.startedCount, 3,
          reason: 'concurrency=3 → exactly 3 attempts, never 5');
      expect(
        engine.startedInputs.map((DownloadAttemptInput i) => i.downloadId),
        <String>['a|movie|1', 'b|movie|1', 'c|movie|1'],
      );
      expect(manager.activeCount, 3);

      final DownloadRecord d = await recordOf('d|movie|1');
      expect(d.status, DownloadStatus.queued);
      expect(d.waitReason, DownloadWaitReason.waitingForSlot);
      final DownloadRecord e = await recordOf('e|movie|1');
      expect(e.status, DownloadStatus.queued);
      expect(e.waitReason, DownloadWaitReason.waitingForSlot);
    });

    test('a freed slot advances the queue exactly one job', () async {
      for (final String id in <String>['a|movie|1', 'b|movie|1', 'c|movie|1', 'd|movie|1']) {
        await manager.enqueue(request(id));
      }
      await manager.debugIdle;
      expect(engine.startedCount, 3);

      // A completes → D starts; B and C stay running.
      engine.settle('a|movie|1',
          const DownloadAttemptResult.completed(1000, totalBytes: 1000));
      await manager.debugIdle;

      expect(engine.startedCount, 4);
      expect(engine.startedInputs.last.downloadId, 'd|movie|1');
      expect((await recordOf('a|movie|1')).status, DownloadStatus.completed);
      expect((await recordOf('d|movie|1')).status, DownloadStatus.downloading);
      expect(manager.activeCount, 3);
    });

    test('simultaneous duplicate enqueues produce exactly ONE attempt',
        () async {
      // Three overlapping triggers for the same identity — the §16 scenario.
      final List<EnqueueResult> results = await Future.wait(<Future<EnqueueResult>>[
        manager.enqueue(request('a|movie|1')),
        manager.enqueue(request('a|movie|1')),
        manager.enqueue(request('a|movie|1')),
      ]);
      await manager.debugIdle;

      expect(
        results
            .where((EnqueueResult r) => r.action == DownloadEnqueueAction.created)
            .length,
        1,
        reason: 'serialized scheduling: one creation, the rest are duplicates',
      );
      expect(engine.startedCount, 1);
      expect(engine.startedInputs.single.downloadId, 'a|movie|1');
      expect((await manager.store.all()).length, 1);
    });
  });

  group('duplicate requests (§28 semantics)', () {
    test('queued duplicate → no second record', () async {
      // Fill all 3 slots so the next enqueue stays genuinely QUEUED.
      for (final String id in <String>['x|movie|1', 'y|movie|1', 'z|movie|1']) {
        await manager.enqueue(request(id));
      }
      await manager.debugIdle;
      expect(manager.activeCount, 3);

      final EnqueueResult first = await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;
      expect((await recordOf('a|movie|1')).status, DownloadStatus.queued);

      final EnqueueResult second = await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;

      expect(first.action, DownloadEnqueueAction.created);
      expect(second.action, DownloadEnqueueAction.alreadyQueued);
      expect(second.record.id, first.record.id);
      expect(engine.startedCount, 3);
      expect((await manager.store.all()).length, 4);
    });

    test('active duplicate → no second attempt', () async {
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;
      final EnqueueResult again = await manager.enqueue(request('a|movie|1'));

      expect(again.action, DownloadEnqueueAction.alreadyDownloading);
      expect(engine.startedCount, 1);
    });

    test('paused duplicate → untouched', () async {
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;
      await manager.pause('a|movie|1');
      await manager.debugIdle;

      final EnqueueResult again = await manager.enqueue(request('a|movie|1'));
      expect(again.action, DownloadEnqueueAction.alreadyPaused);
      expect((await recordOf('a|movie|1')).status, DownloadStatus.paused);
      expect(engine.startedCount, 1);
    });

    test('completed duplicate → no new download', () async {
      engine.completeWith(500, totalBytes: 500);
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;

      final EnqueueResult again = await manager.enqueue(request('a|movie|1'));
      expect(again.action, DownloadEnqueueAction.alreadyCompleted);
      expect(engine.startedCount, 1);
      expect((await manager.store.all()).length, 1);
    });

    test('failed duplicate → explicit re-queue as a NEW run (budget reset)',
        () async {
      engine.failWith(
        DownloadFailure(
            type: DownloadFailureType.httpError,
            message: 'The server refused this download (source unavailable).'),
        100,
      );
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;
      expect((await recordOf('a|movie|1')).attempt, 1);

      final EnqueueResult again = await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;

      expect(again.action, DownloadEnqueueAction.requeuedFailed);
      expect(again.record.attempt, 0,
          reason: 'the requeue snapshot starts a fresh budget');
      // The pump immediately starts the new run: attempt becomes 1 again —
      // of the NEW run, not the old one.
      expect((await recordOf('a|movie|1')).status, DownloadStatus.downloading);
      expect((await recordOf('a|movie|1')).attempt, 1);
      expect(engine.startedCount, 2);
    });

    test('cancelled duplicate → explicit re-request re-queues as a new run',
        () async {
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;
      await manager.cancel('a|movie|1');
      await manager.debugIdle;

      final EnqueueResult again = await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;

      expect(again.action, DownloadEnqueueAction.requeuedCancelled);
      expect((await recordOf('a|movie|1')).status, DownloadStatus.downloading);
      expect(engine.startedCount, 2);
    });
  });

  group('state machine enforcement through the manager', () {
    test('invalid operations are refused honestly', () async {
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle; // downloading

      expect(await manager.pause('absent|movie|1'), isFalse);
      expect(await manager.cancel('absent|movie|1'), isFalse);
      expect(await manager.retry('a|movie|1'), isFalse,
          reason: 'downloading is not a retryable state');
      expect(await manager.resume('a|movie|1'), isFalse,
          reason: 'downloading is not paused');
      expect(
          (await recordOf('a|movie|1')).status, DownloadStatus.downloading);
      expect(engine.startedCount, 1);
    });

    test('manager operations cannot move a completed record (terminal)',
        () async {
      engine.completeWith(100, totalBytes: 100);
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;
      expect((await recordOf('a|movie|1')).status, DownloadStatus.completed);

      // Any leftover engine event is structurally a no-op (nothing is in
      // flight any more), and manager operations are refused by the machine.
      expect(await manager.pause('a|movie|1'), isFalse);
      expect(await manager.retry('a|movie|1'), isFalse,
          reason: 'completed is terminal; removal is the explicit path');
      expect(await manager.cancel('a|movie|1'), isFalse);
      expect((await recordOf('a|movie|1')).status, DownloadStatus.completed);
      expect(engine.startedCount, 1);
    });

    test('a LATE result from a superseded attempt cannot resurrect or mutate '
        'the current state (genuine stale-callback race)', () async {
      // 1. Attempt 1 starts and stays in flight.
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;
      expect(manager.activeCount, 1);

      // 2. The user pauses; the engine does NOT settle (settleOnControl off)
      //    so attempt 1 remains in flight — exactly like a real engine whose
      //    transfer is winding down while the user has moved on.
      engine.settleOnControl = false;
      expect(await manager.pause('a|movie|1'), isTrue);
      await manager.debugIdle;
      expect((await recordOf('a|movie|1')).status, DownloadStatus.paused);

      // 3. The user resumes → attempt 2 starts. Two attempts are now in
      //    flight for the same download: [attempt1, attempt2].
      engine.settleOnControl = true;
      expect(await manager.resume('a|movie|1'), isTrue);
      await manager.debugIdle;
      expect((await recordOf('a|movie|1')).status, DownloadStatus.downloading);

      // 4. Attempt 1's OLD result finally arrives: completed(999).
      engine.settle('a|movie|1',
          const DownloadAttemptResult.completed(999, totalBytes: 999));
      await manager.debugIdle;

      // The stale result belongs to a dead generation: ignored entirely.
      final DownloadRecord record = await recordOf('a|movie|1');
      expect(record.status, DownloadStatus.downloading,
          reason: '§18: a stale completion must not complete the new attempt');
      expect(record.bytesDownloaded, 0, reason: 'no bytes leak from the dead '
          'attempt into the live one');

      // 5. The LIVE attempt completes properly.
      engine.settle('a|movie|1',
          const DownloadAttemptResult.completed(500, totalBytes: 500));
      await manager.debugIdle;
      final DownloadRecord finished = await recordOf('a|movie|1');
      expect(finished.status, DownloadStatus.completed);
      expect(finished.bytesDownloaded, 500);
      expect(finished.completedAt, isNotNull);
    });

    test('a cancelled record stays cancelled against a late engine result',
        () async {
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;

      engine.settleOnControl = false; // hold the attempt in flight
      expect(await manager.cancel('a|movie|1'), isTrue);
      expect((await recordOf('a|movie|1')).status, DownloadStatus.cancelled);

      // The old attempt settles LATE with a completion — must be ignored.
      engine.settle('a|movie|1',
          const DownloadAttemptResult.completed(999, totalBytes: 999));
      await manager.debugIdle;

      final DownloadRecord record = await recordOf('a|movie|1');
      expect(record.status, DownloadStatus.cancelled);
      expect(record.bytesDownloaded, isNot(999));
      expect(manager.activeCount, 0, reason: 'no slot leaked by the late '
          'settlement');
    });
  });

  group('pause / resume', () {
    test('pause persists before the engine is asked (§24 ordering)',
        () async {
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;

      engine.settleOnControl = false; // hold the engine acknowledgement
      final bool ok = await manager.pause('a|movie|1');
      expect(ok, isTrue);
      expect((await recordOf('a|movie|1')).status, DownloadStatus.paused,
          reason: 'the user-visible state is SPECTA-persisted immediately, '
              'whatever the engine does next');
      expect(engine.pauseCalls, <String>['a|movie|1']);

      // The engine settles late; reconciliation only settles bytes.
      engine.settle('a|movie|1', const DownloadAttemptResult.paused(400));
      await manager.debugIdle;
      expect((await recordOf('a|movie|1')).bytesDownloaded, 400);
      expect((await recordOf('a|movie|1')).status, DownloadStatus.paused);
      expect(manager.activeCount, 0, reason: 'no slot leak after pause');
    });

    test('resume with a free slot goes straight back to downloading, '
        'without spending retry budget', () async {
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;
      await manager.pause('a|movie|1');
      await manager.debugIdle;
      final int attemptsBefore = engine.startedCount;

      expect(await manager.resume('a|movie|1'), isTrue);
      await manager.debugIdle;

      final DownloadRecord record = await recordOf('a|movie|1');
      expect(record.status, DownloadStatus.downloading);
      expect(engine.startedCount, attemptsBefore + 1,
          reason: 'resume starts a fresh attempt');
      expect(record.attempt, 1,
          reason: '§21: resume is NOT a failure retry — budget unchanged');
      expect(record.waitReason, isNull);
    });

    test('resume at capacity routes through the queue (paused→queued, the '
        'documented machine transition)', () async {
      for (final String id in <String>['a|movie|1', 'b|movie|1', 'c|movie|1']) {
        await manager.enqueue(request(id));
      }
      await manager.debugIdle;
      expect(manager.activeCount, 3);

      // Pause A (slot freed) and refill the slot with D before resuming.
      await manager.pause('a|movie|1');
      await manager.debugIdle;
      await manager.enqueue(request('d|movie|1'));
      await manager.debugIdle;
      expect(manager.activeCount, 3, reason: 'D took the freed slot');

      expect(await manager.resume('a|movie|1'), isTrue);
      await manager.debugIdle;
      final DownloadRecord record = await recordOf('a|movie|1');
      expect(record.status, DownloadStatus.queued,
          reason: 'no free slot → fair FIFO queue, never exceeding the limit');
      expect(record.waitReason, DownloadWaitReason.waitingForSlot);
      expect(manager.activeCount, 3);
      expect(engine.startedCount, 4, reason: 'a, b, c, d — A was NOT started '
          'again');
    });
  });

  group('cancellation (§26)', () {
    test('queued cancellation prevents the start entirely', () async {
      // Occupy all 3 slots so 'b' stays QUEUED rather than starting.
      for (final String id in <String>[
        'x|movie|1',
        'y|movie|1',
        'f|movie|1',
        'b|movie|1',
      ]) {
        await manager.enqueue(request(id));
      }
      await manager.debugIdle;
      expect(engine.startedCount, 3);
      expect((await recordOf('b|movie|1')).status, DownloadStatus.queued);

      expect(await manager.cancel('b|movie|1'), isTrue);
      await manager.debugIdle;
      expect((await recordOf('b|movie|1')).status, DownloadStatus.cancelled);
      expect(engine.cancelCalls, isNot(contains('b|movie|1')),
          reason: 'a queued job has no transfer to cancel');
      expect(engine.startedCount, 3,
          reason: 'the cancelled job never started');
      expect((await recordOf('x|movie|1')).status, DownloadStatus.downloading,
          reason: 'unrelated active downloads are untouched');
    });

    test('active cancellation: persisted state first, then the engine',
        () async {
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;

      engine.settleOnControl = false;
      expect(await manager.cancel('a|movie|1'), isTrue);
      expect((await recordOf('a|movie|1')).status, DownloadStatus.cancelled);
      expect(engine.cancelCalls, <String>['a|movie|1']);
      expect(manager.activeCount, 0);

      // Late engine acknowledgement is a no-op against the terminal state.
      engine.settle('a|movie|1', const DownloadAttemptResult.cancelled(250));
      await manager.debugIdle;
      expect((await recordOf('a|movie|1')).status, DownloadStatus.cancelled);
    });

    test('cancellation is idempotent', () async {
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;
      expect(await manager.cancel('a|movie|1'), isTrue);
      expect(await manager.cancel('a|movie|1'), isFalse,
          reason: 'the second call is an honest no-op');
      expect(engine.cancelCalls.length, 1);
      expect((await recordOf('a|movie|1')).status, DownloadStatus.cancelled);
    });

    test('cancel-vs-completion race serializes to one consistent outcome',
        () async {
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;

      engine.settleOnControl = false;
      // Interleaved without awaiting: both enter the serialized section in
      // call order — cancel first.
      final Future<bool> cancelled = manager.cancel('a|movie|1');
      engine.settle('a|movie|1',
          const DownloadAttemptResult.completed(800, totalBytes: 800));
      final bool result = await cancelled;
      await manager.debugIdle;

      final DownloadRecord record = await recordOf('a|movie|1');
      expect(result, isTrue);
      expect(record.status, DownloadStatus.cancelled,
          reason: 'the manager serialized cancel first; the completion was '
              'stale by definition');
      expect(record.bytesDownloaded, isNot(800));
    });

    test('cancelled records never automatically retry', () async {
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;
      await manager.cancel('a|movie|1');
      await manager.debugIdle;

      clock.advance(const Duration(hours: 1));
      await manager.debugIdle;

      expect((await recordOf('a|movie|1')).status, DownloadStatus.cancelled);
      expect(engine.startedCount, 1);
      expect(clock.pendingDelayCount, 0);
    });
  });

  group('retry policy + backoff (§19/§20/§21)', () {
    test('a retryable failure auto-retries after backoff, keeping the budget',
        () async {
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;

      // The attempt is already in flight — settle it with the failure.
      engine.settle(
        'a|movie|1',
        DownloadAttemptResult.failed(
          DownloadFailure(
              type: DownloadFailureType.networkError,
              message: 'The network dropped during the download.'),
          300,
        ),
      );
      await manager.debugIdle;

      DownloadRecord record = await recordOf('a|movie|1');
      expect(record.status, DownloadStatus.failed);
      expect(record.attempt, 1);
      expect(record.failure!.type, DownloadFailureType.networkError);
      expect(record.failure!.isRetryable, isTrue);
      expect(record.bytesDownloaded, 300, reason: 'partial progress is kept');
      expect(clock.pendingDelayCount, 1, reason: 'backoff scheduled');

      clock.advance(const Duration(seconds: 2)); // the base delay
      await manager.debugIdle;

      record = await recordOf('a|movie|1');
      expect(record.status, DownloadStatus.downloading,
          reason: 'the auto-retry re-queued and started');
      expect(record.attempt, 2,
          reason: '§21: the budget is NOT reset by the automatic path');
      expect(record.failure, isNull);
      expect(engine.startedCount, 2);
    });

    test('backoff grows exponentially and is hard-capped', () {
      const DownloadRetryPolicy policy = DownloadRetryPolicy();
      expect(policy.backoffAfter(0), const Duration(seconds: 2));
      expect(policy.backoffAfter(1), const Duration(seconds: 2));
      expect(policy.backoffAfter(2), const Duration(seconds: 4));
      expect(policy.backoffAfter(3), const Duration(seconds: 8));
      expect(policy.backoffAfter(10), const Duration(minutes: 1),
          reason: 'capped at maxDelay');
      expect(policy.backoffAfter(1000), const Duration(minutes: 1),
          reason: 'no overflow, no unbounded delay');
      expect(
        policy.backoffAfter(15),
        lessThanOrEqualTo(const Duration(minutes: 1)),
      );
      expect(
        policy.shouldAutoRetry(
          DownloadFailure(
              type: DownloadFailureType.networkError,
              message: 'The network dropped during the download.'),
          2,
        ),
        isTrue,
      );
      expect(
        policy.shouldAutoRetry(
          DownloadFailure(
              type: DownloadFailureType.networkError,
              message: 'The network dropped during the download.'),
          3,
        ),
        isFalse,
        reason: 'the budget is absolute',
      );
      expect(
        policy.shouldAutoRetry(
          DownloadFailure(
              type: DownloadFailureType.httpError,
              message: 'The server refused this download (source unavailable).'),
          0,
        ),
        isFalse,
        reason: 'non-retryable types never retry regardless of budget',
      );
    });

    test('the retry budget is respected and never exceeded', () async {
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;

      // Initial attempt + 2 auto-retries = the budget of 3. Each iteration
      // settles the in-flight attempt with a failure, then clears backoff.
      for (int i = 0; i < 3; i++) {
        engine.settle(
          'a|movie|1',
          DownloadAttemptResult.failed(
            DownloadFailure(
                type: DownloadFailureType.serverError,
                message: 'The server had a problem while serving the file.'),
            100 * (i + 1),
          ),
        );
        await manager.debugIdle;
        clock.advance(const Duration(minutes: 1)); // clear any backoff
        await manager.debugIdle;
      }

      final DownloadRecord record = await recordOf('a|movie|1');
      expect(record.status, DownloadStatus.failed);
      expect(record.attempt, 3);
      expect(clock.pendingDelayCount, 0,
          reason: 'budget exhausted → no more automatic retries');
      expect(engine.startedCount, 3);
    });

    test('non-retryable failures never schedule a retry', () async {
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;

      engine.settle(
        'a|movie|1',
        DownloadAttemptResult.failed(
          DownloadFailure(
              type: DownloadFailureType.httpError,
              message: 'The server refused this download (source unavailable).'),
          0,
        ),
      );
      await manager.debugIdle;

      expect((await recordOf('a|movie|1')).status, DownloadStatus.failed);
      expect((await recordOf('a|movie|1')).attempt, 1);
      expect(clock.pendingDelayCount, 0);
      expect(engine.startedCount, 1);
    });

    test('a contract-violating engine throw becomes honest engineFailure data',
        () async {
      engine.throwOnStart = true;
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;

      final DownloadRecord record = await recordOf('a|movie|1');
      expect(record.status, DownloadStatus.failed);
      expect(record.failure!.type, DownloadFailureType.engineFailure);
      expect(record.failure!.isRetryable, isFalse);
      expect(manager.activeCount, 0, reason: 'no slot leak on a throw');
      expect(clock.pendingDelayCount, 0);
    });

    test('an auto-retry is cancelled by an explicit user cancel meanwhile',
        () async {
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;
      engine.settle(
        'a|movie|1',
        DownloadAttemptResult.failed(
          DownloadFailure(
              type: DownloadFailureType.timeout,
              message: 'The download stalled for too long.'),
          10,
        ),
      );
      await manager.debugIdle;
      expect(clock.pendingDelayCount, 1);

      await manager.cancel('a|movie|1');
      await manager.debugIdle;
      clock.advance(const Duration(minutes: 5));
      await manager.debugIdle;

      expect((await recordOf('a|movie|1')).status, DownloadStatus.cancelled,
          reason: 'backoff expiry must not resurrect a cancelled record');
      expect(engine.startedCount, 1);
    });
  });

  group('source recovery seam (§23)', () {
    test('no resolvable pool at attempt time → honest sourcesExhausted, '
        'no automatic retry loop', () async {
      final DownloadManager isolated = DownloadManager(
        store: DownloadDao(db),
        engine: engine,
        environment: _WifiDeviceEnvironment(),
        clock: clock,
        mediaDirectory: () async => mediaDir,
        sourceResolver: _RecoveringResolver(9999, _mp4Pool()),
      );
      await isolated.initialize();

      await isolated.enqueue(request('a|movie|1'));
      await isolated.debugIdle;

      final DownloadRecord record =
          (await isolated.store.recordFor('a|movie|1'))!;
      expect(record.status, DownloadStatus.failed);
      expect(record.failure!.type, DownloadFailureType.sourcesExhausted);
      expect(record.failure!.isRetryable, isFalse,
          reason: 're-resolution is not retried blindly — 2G-C adds the '
              'real recovery policy');
      expect(engine.startedCount, 0,
          reason: 'the engine was never asked without a source');
      expect(clock.pendingDelayCount, 0);
      await isolated.dispose();
    });

    test('recovery succeeds through a fresh resolution WITHOUT changing the '
        'download identity', () async {
      final DownloadManager recovering = DownloadManager(
        store: DownloadDao(db),
        engine: engine,
        environment: _WifiDeviceEnvironment(),
        clock: clock,
        mediaDirectory: () async => mediaDir,
        sourceResolver: _RecoveringResolver(1, _mp4Pool()),
      );
      await recovering.initialize();

      await recovering.enqueue(request('a|movie|1'));
      await recovering.debugIdle;
      DownloadRecord record =
          (await recovering.store.recordFor('a|movie|1'))!;
      expect(record.status, DownloadStatus.failed);
      expect(record.failure!.type, DownloadFailureType.sourcesExhausted);

      // Explicit user retry (the supported path while auto-retry is off for
      // sourcesExhausted): resolution now succeeds.
      engine.completeWith(500, totalBytes: 500);
      expect(await recovering.retry('a|movie|1'), isTrue);
      await recovering.debugIdle;

      record = (await recovering.store.recordFor('a|movie|1'))!;
      expect(record.status, DownloadStatus.completed);
      expect(record.id, 'a|movie|1',
          reason: 'recovery never changes the download identity');
      expect(record.mediaKey, 'a|movie|1');
      await recovering.dispose();
    });
  });

  group('process restart / manager recreation (§31/§39.8)', () {
    test('state survives dispose + recreation; a dead downloading record is '
        'reclassified as interrupted and auto-retried — not assumed alive, '
        'not blindly marked permanently failed', () async {
      // Session 1: one completed, one paused, one left "downloading".
      engine.completeWith(400, totalBytes: 400);
      await manager.enqueue(request('done|movie|1'));
      await manager.enqueue(request('live|movie|1'));
      await manager.debugIdle;
      await manager.pause('live|movie|1');
      await manager.debugIdle;
      await manager.enqueue(request('dying|movie|1'));
      await manager.debugIdle;

      expect((await recordOf('dying|movie|1')).status,
          DownloadStatus.downloading);
      await manager.dispose();
      await db.close();

      // Session 2: a brand-new manager + a brand-new fake engine over the
      // SAME database file. The new engine holds nothing — the persisted
      // `dying` record has no live transfer.
      final SpectaDatabase db2 = SpectaDatabase(NativeDatabase(File(dbPath)));
      final FakeDownloadEngine engine2 = FakeDownloadEngine();
      final FakeDownloadClock clock2 = FakeDownloadClock();
      final DownloadManager manager2 = DownloadManager(
        store: DownloadDao(db2),
        engine: engine2,
        environment: _WifiDeviceEnvironment(),
        clock: clock2,
        mediaDirectory: () async => mediaDir,
      );
      addTearDown(() async {
        await manager2.dispose();
        engine2.dispose();
        await db2.close();
      });

      await manager2.initialize();
      await manager2.debugIdle;

      expect((await manager2.store.recordFor('done|movie|1'))!.status,
          DownloadStatus.completed,
          reason: 'terminal state untouched by reconciliation');
      expect((await manager2.store.recordFor('live|movie|1'))!.status,
          DownloadStatus.paused,
          reason: 'paused state untouched by reconciliation');

      // `dying` was classified interrupted (failed, retryable) and the
      // bounded auto-retry re-queued + re-attempted it. The re-attempt then
      // fails honestly as sourcesExhausted BEFORE any engine work: the 2G-B
      // session resolver holds no pool after a restart — real source recovery
      // is 2G-C.
      clock2.advance(const Duration(seconds: 2));
      await manager2.debugIdle;

      final DownloadRecord dying =
          (await manager2.store.recordFor('dying|movie|1'))!;
      expect(dying.status, DownloadStatus.failed,
          reason: 'the re-attempt fails honestly: no resolvable source yet');
      expect(dying.failure!.type, DownloadFailureType.sourcesExhausted);
      expect(dying.attempt, 2,
          reason: 'the attempt count survived restart AND the re-attempt '
              'spent exactly one budget unit');
      expect(engine2.startedCount, 0,
          reason: 'the re-attempt never reached the engine: resolution fails '
              'before any transfer because the 2G-B resolver holds no pool '
              'after restart — the engine seam is untouched');
      expect(clock2.pendingDelayCount, 0,
          reason: 'sourcesExhausted is not retryable: the chain stops honestly');
    });

    test('queue order, identity and provenance survive recreation', () async {
      await manager.enqueue(request('z|movie|1'));
      await manager.enqueue(request('y|movie|1'));
      await manager.debugIdle;
      await manager.dispose();
      await db.close();

      final SpectaDatabase db2 = SpectaDatabase(NativeDatabase(File(dbPath)));
      final DownloadDao dao = DownloadDao(db2);
      addTearDown(db2.close);

      final List<String> ids =
          (await dao.all()).map((DownloadRecord r) => r.id).toList();
      expect(ids, <String>['z|movie|1', 'y|movie|1'],
          reason: 'FIFO creation order is the persisted queue order');
      final DownloadRecord z = (await dao.recordFor('z|movie|1'))!;
      expect(z.sourceExtensionId, 'extA');
      expect(z.sourceReference, 'ref-a');
      expect(z.sourceLabel, 'Server 2');
      expect(z.filePath, isNotNull);
      expect(z.filePath.endsWith('.mp4'), isTrue);
      expect(z.filePath.contains(Platform.pathSeparator), isTrue);
    });
  });

  group('progress (§33)', () {
    test('progress events coalesce: transient ticks are held, meaningful '
        'progress is persisted', () async {
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;

      // Small rapid ticks inside the byte/interval window are coalesced —
      // the attempt-start write is the last persisted byte count.
      engine.emitProgress('a|movie|1', 100, totalBytes: 10000);
      engine.emitProgress('a|movie|1', 200, totalBytes: 10000);
      await manager.debugIdle;
      expect((await recordOf('a|movie|1')).bytesDownloaded, 0,
          reason: 'below 256 KiB delta and inside the 2 s window');

      // The interval path persists meaningful progress.
      clock.advance(const Duration(seconds: 3));
      engine.emitProgress('a|movie|1', 300, totalBytes: 10000);
      await manager.debugIdle;
      expect((await recordOf('a|movie|1')).bytesDownloaded, 300);

      // The byte-delta path persists without waiting for the interval.
      engine.emitProgress('a|movie|1', 300 + 256 * 1024, totalBytes: 10000);
      await manager.debugIdle;
      expect((await recordOf('a|movie|1')).bytesDownloaded, 300 + 256 * 1024);
    });

    test('progress never mutates a non-downloading record', () async {
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;
      await manager.pause('a|movie|1');
      await manager.debugIdle;
      final int pausedBytes = (await recordOf('a|movie|1')).bytesDownloaded;

      engine.emitProgress('a|movie|1', 999999);
      await manager.debugIdle;

      expect((await recordOf('a|movie|1')).bytesDownloaded, pausedBytes,
          reason: 'a transient tick cannot mutate a paused record');
      expect((await recordOf('a|movie|1')).status, DownloadStatus.paused);
    });
  });

  group('remove (§27)', () {
    test('remove deletes the record only, is idempotent, and never touches '
        'the filesystem', () async {
      engine.completeWith(10, totalBytes: 10);
      await manager.enqueue(request('a|movie|1'));
      await manager.debugIdle;

      expect(await manager.remove('a|movie|1'), isTrue);
      expect(await manager.remove('a|movie|1'), isFalse,
          reason: 'removal of an absent record is an honest no-op');
      expect(await manager.store.recordFor('a|movie|1'), isNull);
      expect(await manager.store.all(), isEmpty);
      expect(Directory(mediaDir).listSync().whereType<File>().length, 0,
          reason: '2G-B never deletes files — the storage layer owns that');
    });

    test('removing an active download cancels the attempt and frees the slot',
        () async {
      for (final String id in <String>['a|movie|1', 'b|movie|1', 'c|movie|1', 'd|movie|1']) {
        await manager.enqueue(request(id));
      }
      await manager.debugIdle;
      expect(engine.startedCount, 3);

      await manager.remove('a|movie|1');
      await manager.debugIdle;

      expect(engine.startedCount, 4);
      expect(engine.startedInputs.last.downloadId, 'd|movie|1');
      expect(await manager.store.recordFor('a|movie|1'), isNull);
      expect(manager.activeCount, 3);
    });
  });

  group('pool classification (§38 boundary)', () {
    test('an HLS-only pool fails honestly as unsupportedSource — no attempt, '
        'no budget spent, no retry loop', () async {
      final EnqueueResult result =
          await manager.enqueue(request('a|movie|1', pool: _hlsPool()));
      await manager.debugIdle;

      expect(result.action, DownloadEnqueueAction.createdFailed);
      final DownloadRecord record = await recordOf('a|movie|1');
      expect(record.status, DownloadStatus.failed);
      expect(record.failure!.type, DownloadFailureType.unsupportedSource);
      expect(record.attempt, 0, reason: 'no attempt was ever started');
      expect(engine.startedCount, 0);
      expect(clock.pendingDelayCount, 0,
          reason: 'an unsupported source is not retryable');
    });

    test('the first direct-file candidate in SPECTA ranking order is consumed '
        '— never re-ranked', () async {
      await manager.enqueue(request('a|movie|1', pool: _mixedPool()));
      await manager.debugIdle;

      // The ranked pool puts the 4K HLS entry first, then the 1080p MP4:
      // the download takes the FIRST DIRECT-FILE candidate in SPECTA's own
      // order and leaves ranking decisions to the 2D layer.
      expect(engine.startedInputs.single.url, 'https://cdn.example/video.mp4');
      expect((await recordOf('a|movie|1')).sourceLabel, 'Server 2');
      expect((await recordOf('a|movie|1')).sourceExtensionId, 'extA');
    });
  });
}

SourcePool _mp4Pool() => SourcePool(
      ranked: <RankedSource>[
        RankedSource(
          extensionId: 'extA',
          reference: 'ref-a',
          source: const ExtensionSource(
            url: 'https://cdn.example/video.mp4',
            type: SourceType.mp4,
            quality: '1080p',
            label: 'Server 2',
          ),
          score: 100,
        ),
      ],
      outcomes: const <ExtensionSourceOutcome>[],
      reference: 'ref-a',
    );

SourcePool _hlsPool() => SourcePool(
      ranked: <RankedSource>[
        RankedSource(
          extensionId: 'extA',
          reference: 'ref-a',
          source: const ExtensionSource(
            url: 'https://cdn.example/playlist.m3u8',
            type: SourceType.hls,
            quality: '1080p',
            label: 'Server 1',
          ),
          score: 100,
        ),
      ],
      outcomes: const <ExtensionSourceOutcome>[],
      reference: 'ref-a',
    );

SourcePool _mixedPool() => SourcePool(
      ranked: <RankedSource>[
        RankedSource(
          extensionId: 'extA',
          reference: 'ref-a',
          source: const ExtensionSource(
            url: 'https://cdn.example/playlist.m3u8',
            type: SourceType.hls,
            quality: '4K',
            label: 'Server 1',
          ),
          score: 200,
        ),
        RankedSource(
          extensionId: 'extA',
          reference: 'ref-a',
          source: const ExtensionSource(
            url: 'https://cdn.example/video.mp4',
            type: SourceType.mp4,
            quality: '1080p',
            label: 'Server 2',
          ),
          score: 150,
        ),
      ],
      outcomes: const <ExtensionSourceOutcome>[],
      reference: 'ref-a',
    );
