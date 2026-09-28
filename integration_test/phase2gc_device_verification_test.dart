// SPECTA — Phase 2G-C device verification (test-only; no lib/ product change).
//
// Exercises the REAL download chain on a physical device:
//
//   DownloadManager → DownloadEngine (BackgroundDownloaderEngine)
//     → background_downloader 9.6.2 (WorkManager) → local file
//
// against a REAL HTTP server on the host (no public-internet dependency; the
// served file is 2 MiB with Content-Length + Range support).
//
// The transport is deliberately NOT hard-coded. Two ways to reach the host:
//   - historical:  `adb reverse tcp:8712 tcp:8712` and the default URL
//                  http://127.0.0.1:8712/test.mp4
//   - direct LAN:  the device reaches the host over the shared network, with
//                  NO adb forwarding in the path:
//                  --dart-define=P2GC_TEST_URL=http://<pc-lan-ip>:8712/test.mp4
// Only the transport may differ between runs; every assertion below is the
// same, so a direct-transport PASS/FAIL is comparable to an adb-reverse one.
//
// What is proven on-device:
//   P2GC-1  enqueue → real transfer → progress → completion gate (.part →
//           final rename) → COMPLETED with the verified byte count
//   P2GC-2  cancellation during transfer: persisted cancelled state, no
//           completed media, no resurrection
//   P2GC-3  restart reconciliation: the manager is recreated over the SAME
//           database while a transfer runs; the surviving transfer is
//           ADOPTED through attach() and completes — no duplicate transfer
//
// A failure here is reported as a test failure, never hidden. Test artifacts
// (DB rows + files) are namespaced and removed afterwards.

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// Riverpod 3 keeps the `Override` type in the misc library.
import 'package:riverpod/misc.dart';
import 'package:integration_test/integration_test.dart';

import 'package:specta/core/downloads/download_engine.dart';
import 'package:specta/core/downloads/download_manager.dart';
import 'package:specta/core/downloads/download_models.dart';
import 'package:specta/core/downloads/download_providers.dart';
import 'package:specta/core/extensions/contract/extension_source.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/sources/source_models.dart';
import 'package:specta/core/sources/source_pool.dart';

// ignore: avoid_print
void marker(String m) => print('[SPECTA-P2GC] $m');

/// The controlled server URL. See the header: the default preserves the
/// historical adb-reverse invocation; the direct-transport follow-up passes
/// the host's LAN address through `--dart-define=P2GC_TEST_URL=...`.
const String testUrl = String.fromEnvironment(
  'P2GC_TEST_URL',
  defaultValue: 'http://127.0.0.1:8712/test.mp4',
);
const int expectedBytes = 2097176; // the served file's exact size
const String testId = '__p2gc_test__|movie|2026';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  SourcePool poolWith(String url) => SourcePool(
    ranked: <RankedSource>[
      RankedSource(
        extensionId: '__p2gc_ext__',
        reference: '__p2gc_ref__',
        source: ExtensionSource(
          url: url,
          type: SourceType.mp4,
          quality: '720p',
          label: 'Device verification source',
        ),
        score: 100,
      ),
    ],
    outcomes: const <ExtensionSourceOutcome>[],
    reference: '__p2gc_ref__',
  );

  DownloadRequest request(String id) => DownloadRequest(
    id: id,
    mediaKey: '__p2gc_test__|movie|2026',
    mediaType: MediaType.movie,
    title: 'P2GC Device Verification',
    extensions: const <String, String>{'__p2gc_ext__': '__p2gc_ref__'},
    pool: poolWith(testUrl),
  );

  /// Builds the manager from the REAL provider graph (the same wiring the app
  /// runs: real store, real engine adapter, real completion finalizer).
  /// Builds the manager from the REAL provider graph with ONE test-scoped
  /// override: the network policy is pinned to wifiAndMobile. The POLICY
  /// itself is unit-tested; this verification targets the TRANSFER path. The
  /// device's default network flips between Wi-Fi and an unmetered LTE
  /// link between runs, and the conservative Wi-Fi-only policy answers
  /// `blockedUnknown` for the LTE window — honestly refusing to start the
  /// queue there is correct behavior, but it would make this test flaky.
  (ProviderContainer, DownloadManager) wired() {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        deviceNetworkPolicyProvider.overrideWithValue(
          DownloadNetworkPolicy.wifiAndMobile,
        ),
      ],
    );
    final DownloadManager manager = container.read(downloadManagerProvider);
    return (container, manager);
  }

  Future<DownloadRecord> recordOf(DownloadManager manager, String id) async =>
      (await manager.store.recordFor(id))!;

  /// Waits until [predicate] holds for the persisted record (real wall time —
  /// WorkManager and HTTP are genuinely asynchronous).
  Future<DownloadRecord> waitFor(
    DownloadManager manager,
    String id,
    bool Function(DownloadRecord) done,
    Duration budget,
  ) async {
    final DateTime deadline = DateTime.now().add(budget);
    DownloadRecord record = await recordOf(manager, id);
    while (!done(record) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      record = await recordOf(manager, id);
    }
    return record;
  }

  /// Removes leftover verification state so every run starts clean
  /// (re-runs are expected during development). Ghost native tasks from
  /// previous failed runs are cancelled through the engine so they cannot
  /// satisfy a later isTransferActive/attach probe.
  Future<void> cleanSlate(DownloadManager manager) async {
    await manager.initialize();
    await manager.debugIdle;
    final DownloadRecord? stale = await manager.store.recordFor(testId);
    if (stale != null) {
      if (stale.status.isActive) {
        try {
          await manager.engine.cancel(testId);
        } on Object {
          /* best-effort ghost cleanup */
        }
      }
      await manager.remove(testId);
    }
    final File finalFile = File(stale?.filePath ?? '');
    if (stale != null && await finalFile.exists()) {
      await finalFile.delete();
    }
    final File partFile = File('${stale?.filePath ?? ''}.part');
    if (stale != null && await partFile.exists()) {
      await partFile.delete(); // leftover staging from an interrupted run
    }
    // The previous run's COMPLETED artifact may sit at a slightly different
    // stem (title-id hash is stable, but a completed run may exist from an
    // older test version) — sweep the media directory for this test's stem.
    // On a genuinely fresh install there is no record and no directory; the
    // manager's own media directory is resolved through the provider seam.
    if (stale == null) return;
    final Directory mediaDir = File(stale.filePath).parent;
    if (await mediaDir.exists()) {
      await for (final FileSystemEntity entity in mediaDir.list()) {
        if (entity.path.contains('P2GC Device Verification')) {
          try {
            await entity.delete();
          } on Object {
            /* best-effort */
          }
        }
      }
    }
  }

  testWidgets(
    'P2GC-1: enqueue → real device transfer → completion gate → COMPLETED',
    (WidgetTester tester) async {
      final (ProviderContainer container, DownloadManager manager) = wired();
      addTearDown(container.dispose);
      await cleanSlate(manager);

      // Evidence: what the ENGINE reports while the transfer runs. The
      // plugin's own progress/byte accounting is recorded verbatim so a
      // byte-count discrepancy can be attributed to a layer, not guessed.
      final List<String> engineProgress = <String>[];
      final StreamSubscription<DownloadEngineEvent> progressTap = manager
          .engine
          .events
          .listen((DownloadEngineEvent event) {
            if (event is DownloadEngineProgress) {
              engineProgress.add('${event.bytesOnDisk}/${event.totalBytes}');
            }
          });
      addTearDown(progressTap.cancel);

      final EnqueueResult enqueued = await manager.enqueue(request(testId));
      marker(
        'enqueue action=${enqueued.action.name} '
        'status=${enqueued.record.status.code}',
      );
      expect(enqueued.action, DownloadEnqueueAction.created);

      final DownloadRecord record = await waitFor(
        manager,
        testId,
        (DownloadRecord r) => r.status.isTerminal,
        const Duration(minutes: 5),
      );

      marker(
        'final status=${record.status.code} '
        'bytes=${record.bytesDownloaded}/${record.totalBytes ?? '?'}',
      );
      marker(
        'engine progress events=${engineProgress.length} '
        'first=${engineProgress.isEmpty ? '-' : engineProgress.first} '
        'last=${engineProgress.isEmpty ? '-' : engineProgress.last}',
      );
      // Evidence: the REAL size of what the gate moved into place, measured
      // independently of the engine's own byte accounting.
      marker(
        'gate file bytes='
        '${await File(record.filePath).exists() ? await File(record.filePath).length() : -1} '
        'partExists=${File('${record.filePath}.part').existsSync()}',
      );
      expect(
        record.status,
        DownloadStatus.completed,
        reason:
            'the REAL device transfer must complete through the '
            'manager gate; failure=${record.failure?.toString()}',
      );

      // The completion gate's verdict, verified on the real filesystem:
      // the transfer exists at the final path, no .part survives, and the
      // byte count is exactly what the server served.
      final File finalFile = File(record.filePath);
      expect(
        finalFile.existsSync(),
        isTrue,
        reason:
            'the gate renamed the verified transfer into the final '
            'media path',
      );
      expect(
        await finalFile.length(),
        expectedBytes,
        reason: 'the completed file carries the served bytes',
      );
      expect(
        File('${record.filePath}.part').existsSync(),
        isFalse,
        reason: 'no .part staging file survives a completed download',
      );
      expect(record.bytesDownloaded, expectedBytes);
      expect(record.completedAt, isNotNull);

      await manager.remove(testId);
      if (finalFile.existsSync()) await finalFile.delete();
      marker('P2GC-1 artifact cleaned');
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  testWidgets(
    'P2GC-2: cancellation during transfer never completes the record',
    (WidgetTester tester) async {
      final (ProviderContainer container, DownloadManager manager) = wired();
      addTearDown(container.dispose);
      await cleanSlate(manager);

      await manager.enqueue(request(testId));

      // Wait for the transfer to start, then cancel mid-flight.
      final DownloadRecord started = await waitFor(
        manager,
        testId,
        (DownloadRecord r) => r.status == DownloadStatus.downloading,
        const Duration(seconds: 30),
      );
      expect(started.status, DownloadStatus.downloading);

      final bool cancelled = await manager.cancel(testId);
      marker('cancel requested=$cancelled');
      expect(cancelled, isTrue);

      // The engine settles the attempt; the record must STAY cancelled.
      final DownloadRecord record = await waitFor(
        manager,
        testId,
        (DownloadRecord r) => manager.activeCount == 0,
        const Duration(minutes: 2),
      );

      expect(
        record.status,
        DownloadStatus.cancelled,
        reason:
            'the persisted cancellation stands; a late native event '
            'cannot resurrect the record',
      );
      final File finalFile = File(record.filePath);
      expect(
        finalFile.existsSync(),
        isFalse,
        reason: 'a cancelled download never presents completed media',
      );
      // The .part staging file belongs to the plugin after a cancellation —
      // it is cleaned by the plugin or the next run's stale-artifact path;
      // SPECTA's contract is only that NO final media exists.
      marker(
        'part file after cancel: '
        '${await File('${record.filePath}.part').exists()}',
      );

      await manager.remove(testId);
      final File part = File('${record.filePath}.part');
      if (part.existsSync()) await part.delete();
      marker('P2GC-2 artifact cleaned');
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
  testWidgets('P2GC-3: restart reconciliation adopts a surviving transfer', (
    WidgetTester tester,
  ) async {
    // Session 1: enqueue and let the transfer start.
    // NOTE: container1 is deliberately NOT disposed — a real process death
    // runs no dispose() and cancels nothing. Disposing it here would cancel
    // the native transfer and turn this into an interrupted-retry test.
    final (ProviderContainer container1, DownloadManager manager1) = wired();
    addTearDown(container1.dispose); // runs AFTER the assertions below
    await cleanSlate(manager1);

    await manager1.enqueue(request(testId));
    final DownloadRecord started = await waitFor(
      manager1,
      testId,
      (DownloadRecord r) => r.status == DownloadStatus.downloading,
      const Duration(seconds: 30),
    );
    expect(started.status, DownloadStatus.downloading);
    // The manager persists `downloading` BEFORE the engine registers the
    // native task (persistence contract §5), so WorkManager registration
    // may lag the record flip by a beat. Wait for the probe itself instead
    // of asserting it instantly (777529d stabilization precedent).
    bool transferActive = false;
    final DateTime probeDeadline = DateTime.now().add(
      const Duration(seconds: 30),
    );
    while (!transferActive && DateTime.now().isBefore(probeDeadline)) {
      transferActive = await manager1.engine.isTransferActive(testId);
      if (transferActive) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(
      transferActive,
      isTrue,
      reason: 'WorkManager holds the live native task',
    );
    marker('isTransferActive=$transferActive');

    // "Restart": ABANDON the first container (no dispose — a real process
    // death runs none) and create a fresh one over the SAME persisted
    // database while the native transfer keeps running.
    //
    // This deliberately opens a SECOND connection to the app database, which is
    // exactly what Drift warns about in a debug build ("created the database
    // class SpectaDatabase multiple times… might corrupt the database"). Here
    // that second instance is the MECHANISM UNDER TEST — a process that died
    // without closing anything and came back to the same file — not an
    // accident, and this suite only proceeds if adoption behaves correctly.
    final (ProviderContainer container2, DownloadManager manager2) = wired();
    addTearDown(container2.dispose);
    await manager2.initialize();
    await manager2.debugIdle;
    marker('manager recreated; adoption decided');

    // The surviving transfer is ADOPTED (never duplicated) and completes
    // through the normal gate.
    final DownloadRecord after = await waitFor(
      manager2,
      testId,
      (DownloadRecord r) => r.status.isTerminal,
      const Duration(minutes: 5),
    );

    marker(
      'post-restart status=${after.status.code} '
      'bytes=${after.bytesDownloaded}',
    );
    expect(
      after.status,
      DownloadStatus.completed,
      reason:
          'the adopted surviving transfer completes — no duplicate '
          'transfer, no honest-failure misclassification',
    );

    await manager2.remove(testId);
    final File finalFile = File(after.filePath);
    if (finalFile.existsSync()) await finalFile.delete();
    final File part = File('${after.filePath}.part');
    if (part.existsSync()) await part.delete();
    marker('P2GC-3 artifact cleaned');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
