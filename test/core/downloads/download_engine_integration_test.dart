@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/downloads/download_dao.dart';
import 'package:specta/core/downloads/download_manager.dart';
import 'package:specta/core/downloads/device_environment.dart';
import 'package:specta/core/downloads/download_models.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/contract/extension_source.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/sources/source_models.dart';
import 'package:specta/core/sources/source_pool.dart';

import '../../support/fake_download_engine.dart';

/// Phase 2G-C engine-integration tests: the behaviors the REAL engine seam
/// adds on top of the 2G-B manager — restart ADOPTION of surviving
/// transfers, the manager-owned completion GATE (`.part` → final rename,
/// file verification) and the source-expiry → fresh-resolution flow.
///
/// All deterministic: the fake engine + fake clock + real temp files. No
/// network. (The adapter's own translation is covered in
/// `background_downloader_engine_test.dart` via the plugin's mock channels.)
void main() {
  late Directory tempDir;
  late String dbPath;
  late String mediaDir;
  late SpectaDatabase db;
  late FakeDownloadEngine engine;
  late FakeDownloadClock clock;
  late DownloadManager manager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('specta_2gc');
    dbPath = '${tempDir.path}${Platform.pathSeparator}downloads_2gc.db';
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

  // The EXACT paths the manager derives (same stem function + part rule —
  // never a test-side guess of the filename format).
  String finalPathFor(String id) => p.join(
        mediaDir,
        '${downloadFileStem(id, 'Title $id')}.mp4',
      );

  String partPathFor(String id) => downloadPartPathFor(finalPathFor(id));

  /// Creates the engine's part file for [id] with [bytes] bytes, mimicking a
  /// real (or adopted) transfer having written data.
  void writePart(String id, int bytes, {String? content}) {
    final File part = File(partPathFor(id));
    part.parent.createSync(recursive: true);
    part.writeAsBytesSync(List<int>.filled(bytes, content?.codeUnitAt(0) ?? 120));
  }

  group('restart adoption (2G-C §32)', () {
    test('a surviving engine transfer is ADOPTED — not failed, not '
        'duplicated — and its completion lands in SPECTA state', () async {
      // Simulate the previous session: a download was transferring, the
      // process died, the ENGINE still holds the transfer.
      await manager.enqueue(request('adopt1'));
      await manager.debugIdle;
      // Kill the in-memory attempt WITHOUT engine or persistence changes:
      // the record stays `downloading`, the engine keeps the transfer.
      final DownloadRecord downloading = await recordOf('adopt1');
      expect(downloading.status, DownloadStatus.downloading);

      // Recreate the manager the way a process restart would (same store,
      // same engine bookkeeping, fresh in-memory state).
      final FakeDownloadEngine engine2 = FakeDownloadEngine();
      final FakeDownloadClock clock2 = FakeDownloadClock();
      // The surviving transfer: engine2 reports the id active, and the
      // adopted attempt completes (bytes grew, the engine renamed nothing —
      // the GATE owns that).
      engine2.adoptable.add('adopt1');
      writePart('adopt1', 500);
      final DownloadManager manager2 = DownloadManager(
        store: DownloadDao(db),
        engine: engine2,
        environment: _WifiDeviceEnvironment(),
        clock: clock2,
        mediaDirectory: () async => mediaDir,
      );
      addTearDown(() async {
        await manager2.dispose();
        engine2.dispose();
      });

      await manager2.initialize();
      await manager2.debugIdle;

      // The engine was asked to ATTACH, never to start a second transfer.
      expect(engine2.startedCount, 0,
          reason: 'adoption re-attaches to the surviving native task; the '
              'plugin has no re-enqueue guard, so starting would duplicate');
      expect(engine2.adoptable, contains('adopt1'));

      // Now the adopted transfer completes (as the real engine would):
      engine2.settle(
        'adopt1',
        DownloadAttemptResult.completed(500, totalBytes: 500),
      );
      await manager2.debugIdle;

      final DownloadRecord completed = await recordOf('adopt1');
      expect(completed.status, DownloadStatus.completed,
          reason: 'the surviving transfer finished; SPECTA adopted and '
              'finalized it');
      expect(completed.bytesDownloaded, 500);
      expect(completed.attempt, 1,
          reason: 'adoption does not spend a new attempt — the transfer is '
              'the SAME attempt that was already running');
    });

    test('an adopted transfer that actually died is failed honestly under '
        'the retry budget (no resurrection, no blind trust)', () async {
      await manager.enqueue(request('adopt2'));
      await manager.debugIdle;

      final FakeDownloadEngine engine2 = FakeDownloadEngine();
      final FakeDownloadClock clock2 = FakeDownloadClock();
      engine2.adoptable.add('adopt2');
      final DownloadManager manager2 = DownloadManager(
        store: DownloadDao(db),
        engine: engine2,
        environment: _WifiDeviceEnvironment(),
        clock: clock2,
        mediaDirectory: () async => mediaDir,
      );
      addTearDown(() async {
        await manager2.dispose();
        engine2.dispose();
      });
      await manager2.initialize();
      await manager2.debugIdle;

      // The adopted transfer reports a failure (it died after all):
      engine2.settle(
        'adopt2',
        DownloadAttemptResult.failed(
          DownloadFailure(
            type: DownloadFailureType.networkError,
            message: DownloadFailureType.networkError.message,
          ),
          0,
        ),
      );
      await manager2.debugIdle;

      final DownloadRecord failed = await recordOf('adopt2');
      expect(failed.status, DownloadStatus.failed);
      expect(failed.failure!.type, DownloadFailureType.networkError);
      // The bounded auto-retry is scheduled (2s base backoff):
      expect(clock2.pendingDelayCount, 1,
          reason: 'retry policy stays manager-owned for adopted attempts too');
    });

    test('a surviving transfer for a PAUSED record is not resumed behind '
        'the user’s back', () async {
      await manager.enqueue(request('adopt3'));
      await manager.debugIdle;
      await manager.pause('adopt3');
      await manager.debugIdle;
      expect((await recordOf('adopt3')).status, DownloadStatus.paused);

      // Restart with the engine still holding the (now stale) transfer:
      final FakeDownloadEngine engine2 = FakeDownloadEngine();
      final FakeDownloadClock clock2 = FakeDownloadClock();
      engine2.adoptable.add('adopt3');
      final DownloadManager manager2 = DownloadManager(
        store: DownloadDao(db),
        engine: engine2,
        environment: _WifiDeviceEnvironment(),
        clock: clock2,
        mediaDirectory: () async => mediaDir,
      );
      addTearDown(() async {
        await manager2.dispose();
        engine2.dispose();
      });
      await manager2.initialize();
      await manager2.debugIdle;

      // paused ≠ downloading: reconciliation only touches `downloading`
      // records. The engine's stale transfer must not resurrect anything.
      final DownloadRecord record = await recordOf('adopt3');
      expect(record.status, DownloadStatus.paused,
          reason: 'the user paused this download; a stale engine transfer '
              'cannot override SPECTA state');
      expect(engine2.startedCount, 0);
      // The stale native transfer is cleaned up:
      expect(engine2.cancelCalls, contains('adopt3'));
    });
  });

  group('completion gate (2G-C §40 — file lifecycle)', () {
    test('a completed attempt with NO file on disk is an honest failure, '
        'never a completed record', () async {
      engine.completeWith(1 << 20);
      await manager.enqueue(request('gate1'));
      await manager.debugIdle;

      final DownloadRecord record = await recordOf('gate1');
      expect(record.status, DownloadStatus.failed,
          reason: 'the engine SAID complete but produced no file — the gate '
              'refuses to mark media that does not exist');
      expect(record.failure!.type, DownloadFailureType.engineFailure);
    });

    test('an EMPTY final file is refused by the gate', () async {
      engine.completeWith(0);
      await manager.enqueue(request('gate2'));
      await manager.debugIdle;

      final DownloadRecord record = await recordOf('gate2');
      expect(record.status, DownloadStatus.failed);
      expect(
        record.failure!.type,
        anyOf(
          DownloadFailureType.engineFailure,
          DownloadFailureType.storageFailure,
        ),
        reason: 'a zero-byte file is not playable media',
      );
    });

    test('the gate performs the final rename: .part disappears, the final '
        'file appears, and the record completes', () async {
      // The scripted completion settles the attempt immediately, so the
      // part file — the bytes a real engine would have written — must be
      // on disk BEFORE the attempt runs. The gate then does exactly what it
      // does in production: verify the part, rename onto the final path.
      writePart('gate3', 2048);
      engine.completeWith(2048, totalBytes: 2048);
      await manager.enqueue(request('gate3'));
      await manager.debugIdle;

      final DownloadRecord record = await recordOf('gate3');
      expect(record.status, DownloadStatus.completed);
      expect(record.bytesDownloaded, 2048);
      expect(File(finalPathFor('gate3')).existsSync(), isTrue,
          reason: 'the gate renamed the verified part into the final path');
      expect(File(partPathFor('gate3')).existsSync(), isFalse,
          reason: 'no .part file survives a completed download');
    });

    test('a TRUNCATED transfer is REFUSED: the gate verifies the declared '
        'total before the final rename', () async {
      // The exact real-device shape: the source declares 2 MiB in one
      // size-bearing progress update, the plugin then ends the transfer
      // early and reports `complete` anyway. The incomplete bytes must never
      // take the final media path.
      engine.emitProgress('gate4', 8028, totalBytes: 2097176);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      engine.emitProgress('gate4', 8028);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      writePart('gate4', 8028);
      // The engine's own numbers agree with each other (8028/8028) — that
      // self-consistency is exactly what used to hide the shortfall.
      engine.completeWith(8028, totalBytes: 8028);
      await manager.enqueue(request('gate4'));
      await manager.debugIdle;

      final DownloadRecord record = await recordOf('gate4');
      expect(record.status, DownloadStatus.failed,
          reason: '8028 of the 2097176 DECLARED bytes is not completed media, '
              'however firmly the engine says complete');
      expect(record.failure!.type, DownloadFailureType.interrupted,
          reason: 'a short transfer is an interruption, and it is retryable '
              'under the bounded budget');
      expect(File(finalPathFor('gate4')).existsSync(), isFalse,
          reason: 'partial bytes must never be renamed into the final path');
      expect(File(partPathFor('gate4')).existsSync(), isTrue,
          reason: 'the bytes already transferred are kept for a resume');
    });

    test('a COMPLETE transfer is persisted with the file\'s verified byte '
        'count, never the engine\'s stale claim', () async {
      // The real-device shape of a SUCCESSFUL download: the plugin delivers
      // the whole file but its last byte count is mid-flight accounting.
      engine.emitProgress('gate5', 5792, totalBytes: 2097176);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      engine.emitProgress('gate5', 5792);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      writePart('gate5', 2097176);
      engine.completeWith(5792, totalBytes: 5792);
      await manager.enqueue(request('gate5'));
      await manager.debugIdle;

      final DownloadRecord record = await recordOf('gate5');
      expect(record.status, DownloadStatus.completed);
      expect(record.bytesDownloaded, 2097176,
          reason: 'the record must agree with the file that is on disk');
      expect(record.totalBytes, 2097176,
          reason: 'the declared total survives completion');
    });

    test('the gate never leaks a raw filesystem error: an unreadable final '
        'artifact is an honest failed record, never a crashed reconcile', () async {
      // Real-device shape (D-3 device run 4): two reconcilers may finalize
      // the same transfer, and only one rename can win — the loser's probe
      // found the file gone BETWEEN an existence check and a read, and the
      // raw dart:io exception escaped the gate and crashed the reconcile.
      // A directory on the final path makes File.length() throw the same
      // class of raw OS error, deterministically, on every platform.
      Directory(finalPathFor('gate6')).createSync(recursive: true);
      engine.completeWith(2048, totalBytes: 2048);
      await manager.enqueue(request('gate6'));
      await manager.debugIdle;

      final DownloadRecord record = await recordOf('gate6');
      expect(record.status, DownloadStatus.failed,
          reason: 'the gate reports what it can VERIFY — an unverifiable '
              'artifact is an honest failure, not a crash');
      // The deterministic trigger lands in the gate's no-file branch; the
      // vanished-between-probes window that produced the raw
      // PathNotFoundException on device is a TOCTOU race and cannot be
      // reproduced deterministically offline — the gate now classifies BOTH
      // as honest DownloadFailures (raw OS exceptions never escape).
      expect(record.failure, isA<DownloadFailure>());
      expect(
        record.failure!.type,
        anyOf(
          DownloadFailureType.engineFailure,
          DownloadFailureType.storageFailure,
        ),
      );
    });

    test('the source-DECLARED total outranks an engine total derived from '
        'its own byte count', () async {
      engine.emitProgress('gate6', 100, totalBytes: 4096);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      writePart('gate6', 4096);
      // The engine reports its own byte count as the total (the pre-fix
      // adapter behavior: 100 bytes transferred, so it claims 100). A
      // self-consistent wrong total must not outrank the declared 4096.
      engine.completeWith(4096, totalBytes: 100);
      await manager.enqueue(request('gate6'));
      await manager.debugIdle;

      final DownloadRecord record = await recordOf('gate6');
      expect(record.status, DownloadStatus.completed);
      expect(record.bytesDownloaded, 4096);
      expect(record.totalBytes, 4096);
    });
  });

  group('source expiry → fresh resolution (2G-C §23/§24/§25)', () {
    test('an expired source (httpError) is NOT trusted: the resolver is '
        'asked with the failure and recovery supplies a fresh pool', () async {
      final SourcePool freshPool = _mp4Pool(url: 'https://fresh.example/v.mp4');
      final _RecordingResolver resolver =
          _RecordingResolver(initialPool: _mp4Pool());
      final DownloadManager recovery = DownloadManager(
        store: DownloadDao(db),
        engine: engine,
        environment: _WifiDeviceEnvironment(),
        clock: clock,
        mediaDirectory: () async => mediaDir,
        sourceResolver: resolver,
      );
      addTearDown(() async {
        await recovery.dispose();
      });
      await recovery.initialize();

      // First attempt: the captured pool's URL has EXPIRED — the engine
      // reports the honest 4xx-style failure.
      engine.failWith(
        DownloadFailure(
          type: DownloadFailureType.httpError,
          message: DownloadFailureType.httpError.message,
          detail: '410 gone',
        ),
        0,
      );
      await recovery.enqueue(request('exp1'));
      await recovery.debugIdle;
      expect((await recordOf('exp1')).status, DownloadStatus.failed);
      expect(engine.startedCount, 1);

      // Recovery path: the user retries the failed download (an httpError
      // is non-retryable automatically — the URL is unusable — so the
      // user's explicit retry is the recovery trigger). The manager keeps
      // the failure in memory, so the resolver re-resolves FRESHLY instead
      // of serving the stale captured pool with the expired URL.
      resolver.nextPool = freshPool;
      // The bytes the fresh transfer will have written when it completes
      // (the fake engine writes no files; the REAL completion gate checks).
      writePart('exp1', 4096);
      engine.completeWith(4096, totalBytes: 4096);
      expect(await recovery.retry('exp1'), isTrue);
      await recovery.debugIdle;

      final DownloadRecord record = await recordOf('exp1');
      expect(record.status, DownloadStatus.completed,
          reason: 'fresh source → retried → success');
      expect(record.attempt, 1,
          reason: 'a manual retry is a NEW run — the budget resets '
              'deliberately (user-initiated)');
      // The resolver saw the source-invalidating failure:
      expect(resolver.lastFailureFor('exp1')?.type,
          DownloadFailureType.httpError);
      expect(resolver.stalePoolRequests, contains('exp1'),
          reason: 'a captured pool must not be silently reused after the '
              'source itself failed — the resolver is told why');
      expect(engine.startedInputs.last.url, 'https://fresh.example/v.mp4',
          reason: 'the FRESH url drove the retry, never the expired one');
    });

    test('the bounded budget survives transient-failure recovery: a '
        'retryable failure auto-retries up to maxAttempts, then fails '
        'permanently (captured pool stays valid — the source did not)',
        () async {
      final _RecordingResolver resolver =
          _RecordingResolver(initialPool: _mp4Pool());
      final DownloadManager recovery = DownloadManager(
        store: DownloadDao(db),
        engine: engine,
        environment: _WifiDeviceEnvironment(),
        clock: clock,
        mediaDirectory: () async => mediaDir,
        sourceResolver: resolver,
      );
      addTearDown(() async {
        await recovery.dispose();
      });
      await recovery.initialize();

      // A 5xx is retryable (plausibly transient) but NOT source-
      // invalidating: the captured pool must keep being served.
      for (int i = 0; i < 3; i++) {
        engine.failWith(
          DownloadFailure(
            type: DownloadFailureType.serverError,
            message: DownloadFailureType.serverError.message,
          ),
          0,
        );
      }
      await recovery.enqueue(request('exp2'));
      await recovery.debugIdle;

      // Attempt 1 failed → auto-retry 2 scheduled:
      expect((await recordOf('exp2')).attempt, 1);
      expect(clock.pendingDelayCount, 1);
      clock.advance(const Duration(seconds: 3));
      await recovery.debugIdle;
      expect((await recordOf('exp2')).attempt, 2);
      expect(clock.pendingDelayCount, 1);
      clock.advance(const Duration(seconds: 5));
      await recovery.debugIdle;

      // The budget is absolute: 3 attempts → permanent failure.
      final DownloadRecord record = await recordOf('exp2');
      expect(record.status, DownloadStatus.failed);
      expect(record.attempt, 3);
      expect(clock.pendingDelayCount, 0,
          reason: 'exhausted budget → no further auto-retries');
      expect(engine.startedCount, 3);
      // The resolver was consulted for every attempt and the pool stayed
      // the captured one (serverError does not invalidate the source):
      expect(resolver.resolveCallsFor('exp2'), 3);
      expect(resolver.stalePoolRequests, isNot(contains('exp2')));
    });
  });
}

class _WifiDeviceEnvironment implements DeviceEnvironment {
  @override
  Future<NetworkAccess?> networkAccess() async => NetworkAccess.wifi;

  @override
  Future<int?> freeBytes(String path) async => null;
}

SourcePool _mp4Pool({String url = 'https://cdn.example/video.mp4'}) =>
    SourcePool(
      ranked: <RankedSource>[
        RankedSource(
          extensionId: 'extA',
          reference: 'ref-a',
          source: ExtensionSource(
            url: url,
            type: SourceType.mp4,
            quality: '1080p',
            label: 'Server 1',
          ),
          score: 100,
        ),
      ],
      outcomes: const <ExtensionSourceOutcome>[],
      reference: 'ref-a',
    );

/// A resolver that records what the manager asked it — the observable seam
/// for recovery behavior. Holds an initial pool; [nextPool] overrides the
/// answer for subsequent calls (the "fresh resolution" scenario).
class _RecordingResolver implements DownloadSourceResolver {
  _RecordingResolver({required this.initialPool});

  final SourcePool initialPool;
  SourcePool? nextPool;
  final Map<String, DownloadFailure> failures = <String, DownloadFailure>{};
  final Set<String> stalePoolRequests = <String>{};
  final Map<String, int> _resolveCalls = <String, int>{};

  DownloadFailure? lastFailureFor(String id) => failures[id];

  int resolveCallsFor(String id) => _resolveCalls[id] ?? 0;

  @override
  Future<SourcePool?> resolveSource(
    DownloadRecord record, {
    DownloadFailure? lastFailure,
  }) async {
    _resolveCalls[record.id] = (_resolveCalls[record.id] ?? 0) + 1;
    if (lastFailure != null) {
      failures[record.id] = lastFailure;
      // Mirror the REAL resolver's decision: only source-INVALIDATING
      // failure types forbid reusing the captured pool. The manager passes
      // the previous failure for every attempt; classification is the
      // resolver's job.
      const Set<DownloadFailureType> invalidating = <DownloadFailureType>{
        DownloadFailureType.httpError,
        DownloadFailureType.invalidResponse,
        DownloadFailureType.unsupportedSource,
        DownloadFailureType.sourcesExhausted,
      };
      if (invalidating.contains(lastFailure.type)) {
        stalePoolRequests.add(record.id);
      }
    }
    return nextPool ?? initialPool;
  }

  @override
  void rememberPool(String id, SourcePool pool) {}

  @override
  void forgetPool(String id) {}
}
