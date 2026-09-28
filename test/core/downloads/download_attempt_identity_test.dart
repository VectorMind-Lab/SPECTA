@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/downloads/background_downloader_engine.dart';
import 'package:specta/core/downloads/device_environment.dart';
import 'package:specta/core/downloads/download_dao.dart';
import 'package:specta/core/downloads/download_engine.dart';
import 'package:specta/core/downloads/download_manager.dart';
import 'package:specta/core/downloads/download_models.dart';
import 'package:specta/core/extensions/contract/extension_source.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/sources/source_models.dart';
import 'package:specta/core/sources/source_pool.dart';

import '../../support/fake_download_engine.dart';

/// Phase 2G-C D-3 — ATTEMPT IDENTITY / STALE EVENT ISOLATION.
///
/// The safety property under test:
///
///   NO EVENT FROM ATTEMPT N MAY MUTATE ATTEMPT N+1.
///
/// The plugin's only routing key is `taskId`, and SPECTA deliberately makes the
/// plugin taskId equal the download identity (§38) — so two sequential attempts
/// of the same download share one taskId. The plugin CAN deliver an earlier
/// attempt's update while a later attempt is live:
///   * `FileDownloader.start()` unconditionally calls `resumeFromBackground()`
///     → `retrieveLocallyStoredData()` → replays status updates it stored
///     locally (keyed by taskId) when a post failed (base_downloader.dart
///     275-296, file_downloader.dart 814-831);
///   * a late native cancellation acknowledgement carries the task object of
///     the attempt it belongs to.
/// The update carries the ORIGINAL task (its JSON is parsed back on the Dart
/// side), so the attempt it belongs to is recoverable — which is what these
/// tests pin down. Every task is built from the JSON the adapter ACTUALLY
/// enqueued, exactly as the plugin would carry it back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingStorage storage;
  final List<Map<String, Object?>> enqueuedTaskJson = <Map<String, Object?>>[];

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall call) async => '/tmp',
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (MethodCall call) async => <String>['wifi'],
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.bbflight.background_downloader'),
          (MethodCall call) async {
            switch (call.method) {
              case 'enqueue':
                enqueuedTaskJson.add(
                  jsonDecode(call.arguments[0] as String)
                      as Map<String, Object?>,
                );
                return true;
              case 'pause':
              case 'resume':
              case 'cancelTasksWithIds':
                return true;
              case 'enqueueAll':
                final List<dynamic> tasksJson =
                    jsonDecode(call.arguments[0] as String) as List<dynamic>;
                return tasksJson.map((_) => true).toList();
              case 'reset':
                return 0;
              case 'platformVersion':
                return '34';
              case 'allTasks':
                return <dynamic>[];
              case 'taskForId':
                return null;
              case 'popResumeData':
              case 'popStatusUpdates':
              case 'popProgressUpdates':
                return '{}';
              default:
                return null;
            }
          },
        );
    storage = _RecordingStorage();
    FileDownloader(persistentStorage: storage);
  });

  setUp(() {
    storage.records.clear();
    enqueuedTaskJson.clear();
  });

  BackgroundDownloaderEngine engine() =>
      BackgroundDownloaderEngine(downloader: FileDownloader());

  DownloadAttemptInput input(String id) => DownloadAttemptInput(
    downloadId: id,
    url: 'https://cdn.example/video.mp4',
    partPath: '/media/Title.mp4.part',
    resumeFrom: 0,
  );

  /// The task JSON the adapter enqueued for [id], attempt [attempt] (0-based) —
  /// i.e. the task the plugin itself would carry in an update for that
  /// attempt, task-creation identity included.
  DownloadTask pluginTask(String id, {int attempt = 0}) {
    final List<Map<String, Object?>> tasks = enqueuedTaskJson
        .where((Map<String, Object?> t) => t['taskId'] == id)
        .toList();
    if (tasks.length > attempt) {
      return DownloadTask.fromJson(Map<String, dynamic>.from(tasks[attempt]));
    }
    // No enqueue recorded (attach/adoption scenarios): a task constructed the
    // same way the plugin's own record would carry it.
    return DownloadTask(
      taskId: id,
      url: 'https://cdn.example/video.mp4',
      filename: 'Title.mp4.part',
      directory: '/media',
      baseDirectory: BaseDirectory.root,
      updates: Updates.statusAndProgress,
      allowPause: true,
    );
  }

  DownloadTask pluginTaskWithId(String taskId) => DownloadTask(
    taskId: taskId,
    url: 'https://cdn.example/video.mp4',
    filename: 'Title.mp4.part',
    directory: '/media',
    baseDirectory: BaseDirectory.root,
    updates: Updates.statusAndProgress,
    allowPause: true,
  );

  Future<void> tick([int times = 4]) async {
    for (int i = 0; i < times; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Starts an attempt and lets the adapter enqueue it.
  Future<(Future<DownloadAttemptResult>, _Probe)> startAttempt(
    BackgroundDownloaderEngine e,
    String id,
  ) async {
    final Future<DownloadAttemptResult> attempt = e.start(input(id));
    final _Probe probe = _Probe(attempt);
    await tick();
    return (attempt, probe);
  }

  group('stale terminal events from attempt N cannot mutate attempt N+1', () {
    test('a LATE CANCELED from the previous attempt does not settle the '
        'current attempt', () async {
      final BackgroundDownloaderEngine e = engine();
      const String id = 'dl|stale-cancel';

      // Attempt N runs, then SPECTA cancels it (the plugin's own attempt N
      // task is what a late cancellation acknowledgement carries back).
      final (Future<DownloadAttemptResult> attemptN, _Probe probeN) =
          await startAttempt(e, id);
      await e.cancel(id);
      expect((await attemptN).kind, DownloadAttemptOutcomeKind.cancelled);
      await tick();
      expect(probeN.settled, isNotNull);

      // Attempt N+1 for the SAME download (same taskId, new task).
      final (Future<DownloadAttemptResult> attemptN1, _Probe probeN1) =
          await startAttempt(e, id);

      // The plugin now delivers attempt N's terminal status (a stored/replayed
      // or late-acknowledged update, carrying attempt N's own task).
      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(pluginTask(id), TaskStatus.canceled),
      );
      await tick();

      expect(
        probeN1.settled,
        isNull,
        reason:
            'attempt N+1 must survive attempt N\'s cancellation — the '
            'stale event carries the SUPERSEDED task',
      );

      // ... and the current attempt still settles from its OWN event.
      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(pluginTask(id, attempt: 1), TaskStatus.complete),
      );
      expect((await attemptN1).kind, DownloadAttemptOutcomeKind.completed);
      e.disposeForTesting();
    });

    test('a LATE FAILED from the previous attempt does not fail the current '
        'attempt', () async {
      final BackgroundDownloaderEngine e = engine();
      const String id = 'dl|stale-failed';

      final (Future<DownloadAttemptResult> attemptN, _) = await startAttempt(
        e,
        id,
      );
      await e.cancel(id);
      await attemptN;
      await tick();

      final (Future<DownloadAttemptResult> attemptN1, _Probe probeN1) =
          await startAttempt(e, id);

      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(
          pluginTask(id),
          TaskStatus.failed,
          TaskConnectionException('the network dropped'),
        ),
      );
      await tick();

      expect(
        probeN1.settled,
        isNull,
        reason: 'the previous attempt\'s failure must not fail the new one',
      );

      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(pluginTask(id, attempt: 1), TaskStatus.complete),
      );
      expect((await attemptN1).kind, DownloadAttemptOutcomeKind.completed);
      e.disposeForTesting();
    });

    test('a LATE COMPLETE from the previous attempt does not complete the '
        'current attempt', () async {
      final BackgroundDownloaderEngine e = engine();
      const String id = 'dl|stale-complete';

      final (Future<DownloadAttemptResult> attemptN, _) = await startAttempt(
        e,
        id,
      );
      await e.cancel(id);
      await attemptN;
      await tick();

      final (Future<DownloadAttemptResult> attemptN1, _Probe probeN1) =
          await startAttempt(e, id);

      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(pluginTask(id), TaskStatus.complete),
      );
      await tick();

      expect(
        probeN1.settled,
        isNull,
        reason:
            'completing the new attempt from the old one would let a '
            'transfer that never ran produce "completed" media',
      );

      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(pluginTask(id, attempt: 1), TaskStatus.canceled),
      );
      expect((await attemptN1).kind, DownloadAttemptOutcomeKind.cancelled);
      e.disposeForTesting();
    });

    test('a LATE PROGRESS from the previous attempt neither reports nor '
        'corrupts the current attempt', () async {
      final BackgroundDownloaderEngine e = engine();
      const String id = 'dl|stale-progress';
      final List<DownloadEngineEvent> observed = <DownloadEngineEvent>[];
      final StreamSubscription<DownloadEngineEvent> sub = e.events.listen(
        observed.add,
      );

      final (Future<DownloadAttemptResult> attemptN, _) = await startAttempt(
        e,
        id,
      );
      // Attempt N got as far as 1 MiB before it was cancelled.
      FileDownloader().downloaderForTesting.processProgressUpdate(
        TaskProgressUpdate(pluginTask(id), 0.5, 2097152),
      );
      await tick();
      await e.cancel(id);
      await attemptN;
      await tick();
      observed.clear();

      final (Future<DownloadAttemptResult> attemptN1, _) = await startAttempt(
        e,
        id,
      );
      observed.clear();

      // Attempt N's buffered progress arrives during attempt N+1.
      FileDownloader().downloaderForTesting.processProgressUpdate(
        TaskProgressUpdate(pluginTask(id), 1.0, 2097152),
      );
      await tick();

      expect(
        observed.whereType<DownloadEngineProgress>(),
        isEmpty,
        reason:
            'attempt N\'s progress must not be reported as attempt N+1\'s '
            'bytes (it would inflate the persisted byte count)',
      );

      // The current attempt's own progress is still reported.
      FileDownloader().downloaderForTesting.processProgressUpdate(
        TaskProgressUpdate(pluginTask(id, attempt: 1), 0.25, 2097152),
      );
      await tick();
      final DownloadEngineProgress progress = observed
          .whereType<DownloadEngineProgress>()
          .single;
      expect(progress.bytesOnDisk, 524288);
      expect(progress.totalBytes, 2097152);

      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(pluginTask(id, attempt: 1), TaskStatus.canceled),
      );
      await attemptN1;
      await sub.cancel();
      e.disposeForTesting();
    });

    test('restart reconciliation: an ADOPTED transfer\'s own events are '
        'accepted, and once it is replaced the old task\'s events are refused', () async {
      // The reconciliation interaction: after a restart the surviving task is
      // OLDER than anything this process created, so identity cannot mean "the
      // newest task". An adopted attempt adopts the surviving task's own
      // creation time; a later attempt for the same download gets a newer one,
      // and the adopted task's updates then belong to the attempt it was.
      final BackgroundDownloaderEngine e = engine();
      const String id = 'dl|reconcile';
      final DownloadTask surviving = pluginTaskWithId(id);
      await storage.storeTaskRecord(
        TaskRecord(surviving, TaskStatus.running, 0.25, 4000),
      );

      // Session 1: adopt the surviving transfer and settle it from its events.
      final Future<DownloadAttemptResult> adopted = e.attach(id);
      await tick();
      FileDownloader().downloaderForTesting.processProgressUpdate(
        TaskProgressUpdate(surviving, 0.5, 4000),
      );
      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(surviving, TaskStatus.complete),
      );
      expect((await adopted).kind, DownloadAttemptOutcomeKind.completed);
      await tick();

      // Session 2: a fresh attempt for the same download (a retry after the
      // adopted transfer finished). The surviving task's events are now the
      // superseded attempt's and must not touch it.
      final (Future<DownloadAttemptResult> fresh, _Probe probeFresh) =
          await startAttempt(e, id);
      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(
          surviving,
          TaskStatus.failed,
          TaskConnectionException('the network dropped'),
        ),
      );
      await tick();
      expect(
        probeFresh.settled,
        isNull,
        reason:
            'the adopted transfer\'s updates must not fail the attempt '
            'that replaced it',
      );

      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(pluginTask(id), TaskStatus.complete),
      );
      expect((await fresh).kind, DownloadAttemptOutcomeKind.completed);
      e.disposeForTesting();
    });

    test('duplicate terminal events for the CURRENT attempt settle once, '
        'cleanly', () async {
      final BackgroundDownloaderEngine e = engine();
      const String id = 'dl|duplicate-terminal';

      final (Future<DownloadAttemptResult> attempt, _) = await startAttempt(
        e,
        id,
      );

      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(pluginTask(id), TaskStatus.canceled),
      );
      await tick();
      // A duplicate of the same terminal status (the plugin can re-deliver).
      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(pluginTask(id), TaskStatus.canceled),
      );
      await tick();
      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(pluginTask(id), TaskStatus.complete),
      );
      await tick();

      expect(
        (await attempt).kind,
        DownloadAttemptOutcomeKind.cancelled,
        reason: 'the first terminal event wins; later ones are no-ops',
      );
      e.disposeForTesting();
    });

    test('an event for a DIFFERENT task never settles this attempt', () async {
      final BackgroundDownloaderEngine e = engine();
      const String id = 'dl|not-mine';

      final (Future<DownloadAttemptResult> attempt, _Probe probe) =
          await startAttempt(e, id);

      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(pluginTaskWithId('dl|other'), TaskStatus.complete),
      );
      await tick();
      expect(probe.settled, isNull);

      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(pluginTask(id), TaskStatus.complete),
      );
      expect((await attempt).kind, DownloadAttemptOutcomeKind.completed);
      e.disposeForTesting();
    });

    test('an ADOPTED attempt (attach) still accepts the surviving transfer\'s '
        'own events', () async {
      final BackgroundDownloaderEngine e = engine();
      const String id = 'dl|adopted';
      final DownloadTask adopted = pluginTaskWithId(id);
      await storage.storeTaskRecord(
        TaskRecord(adopted, TaskStatus.running, 0.25, 4000),
      );

      final Future<DownloadAttemptResult> attempt = e.attach(id);
      await tick();

      FileDownloader().downloaderForTesting.processProgressUpdate(
        TaskProgressUpdate(adopted, 0.5, 4000),
      );
      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(adopted, TaskStatus.complete),
      );
      final DownloadAttemptResult result = await attempt;

      expect(result.kind, DownloadAttemptOutcomeKind.completed);
      expect(result.bytesOnDisk, 2000);
      e.disposeForTesting();
    });
  });

  group('authoritative SPECTA state survives the rapid cancel → re-request '
      'sequence (the device symptom)', () {
    late Directory tempDir;
    late String mediaDir;
    late SpectaDatabase db;
    late DownloadManager manager;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('specta_d3');
      mediaDir = '${tempDir.path}${Platform.pathSeparator}media';
      await Directory(mediaDir).create(recursive: true);
      db = SpectaDatabase(
        NativeDatabase(File('${tempDir.path}${Platform.pathSeparator}d.db')),
      );
      manager = DownloadManager(
        store: DownloadDao(db),
        engine: BackgroundDownloaderEngine(downloader: FileDownloader()),
        environment: _WifiEnvironment(),
        clock: FakeDownloadClock(),
        mediaDirectory: () async => mediaDir,
      );
      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
      await db.close();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    SourcePool pool() => SourcePool(
      ranked: <RankedSource>[
        RankedSource(
          extensionId: 'extA',
          reference: 'ref-a',
          source: ExtensionSource(
            url: 'https://cdn.example/video.mp4',
            type: SourceType.mp4,
          ),
          score: 100,
        ),
      ],
      outcomes: const <ExtensionSourceOutcome>[],
      reference: 'ref-a',
    );

    DownloadRequest request(String id) => DownloadRequest(
      id: id,
      mediaKey: id,
      mediaType: MediaType.movie,
      title: 'D3 Rapid Cancel',
      extensions: const <String, String>{'extA': 'ref-a'},
      pool: pool(),
    );

    test('a stale CANCELED from the cancelled attempt does not cancel the '
        're-requested download', () async {
      const String id = 'dl|rapid';
      await manager.enqueue(request(id));
      await manager.debugIdle;
      expect(
        (await manager.store.recordFor(id))!.status,
        DownloadStatus.downloading,
      );

      // The user cancels …
      expect(await manager.cancel(id), isTrue);
      await manager.debugIdle;
      expect(
        (await manager.store.recordFor(id))!.status,
        DownloadStatus.cancelled,
      );

      // … and immediately re-requests the same download.
      await manager.enqueue(request(id));
      await manager.debugIdle;
      expect(
        (await manager.store.recordFor(id))!.status,
        DownloadStatus.downloading,
        reason: 'the re-requested download is genuinely running',
      );

      // The cancelled attempt's own terminal event arrives late (replayed or
      // late-acknowledged) while the NEW attempt is live.
      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(pluginTask(id), TaskStatus.canceled),
      );
      await manager.debugIdle;

      final DownloadRecord record = (await manager.store.recordFor(id))!;
      expect(
        record.status,
        DownloadStatus.downloading,
        reason:
            'SPECTA\'s authoritative record must not be mutated by the '
            'superseded attempt\'s event (this is the observed device '
            'symptom: a live transfer reported as cancelled)',
      );

      // The live attempt is still the one that settles the record.
      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(pluginTask(id, attempt: 1), TaskStatus.canceled),
      );
      await manager.debugIdle;
      expect(
        (await manager.store.recordFor(id))!.status,
        DownloadStatus.cancelled,
      );
    });
  });
}

/// Observes whether a future has settled, without awaiting it.
final class _Probe {
  _Probe(Future<DownloadAttemptResult> future) {
    unawaited(
      future.then((DownloadAttemptResult result) {
        settled = result;
      }, onError: (Object _) {}),
    );
  }

  DownloadAttemptResult? settled;
}

final class _WifiEnvironment implements DeviceEnvironment {
  @override
  Future<NetworkAccess?> networkAccess() async => NetworkAccess.wifi;

  @override
  Future<int?> freeBytes(String path) async => null;
}

/// The plugin's InMemoryPersistentStorage plus a records map tests seed.
class _RecordingStorage implements PersistentStorage {
  final Map<String, TaskRecord> records = <String, TaskRecord>{};
  final Map<String, Task> pausedTasks = <String, Task>{};
  final Map<String, ResumeData> resumeData = <String, ResumeData>{};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> storeTaskRecord(TaskRecord record) async {
    records[record.taskId] = record;
  }

  @override
  Future<TaskRecord?> retrieveTaskRecord(String taskId) async =>
      records[taskId];

  @override
  Future<List<TaskRecord>> retrieveAllTaskRecords() async =>
      records.values.toList();

  @override
  Future<void> removeTaskRecord(String? taskId) async {
    if (taskId == null) {
      records.clear();
    } else {
      records.remove(taskId);
    }
  }

  @override
  (String, int) get currentDatabaseVersion => ('', 0);

  @override
  Future<(String, int)> get storedDatabaseVersion async => ('', 0);

  @override
  Future<void> removePausedTask(String? taskId) async {
    if (taskId == null) {
      pausedTasks.clear();
    } else {
      pausedTasks.remove(taskId);
    }
  }

  @override
  Future<void> removeResumeData(String? taskId) async {
    if (taskId == null) {
      resumeData.clear();
    } else {
      resumeData.remove(taskId);
    }
  }

  @override
  Future<List<Task>> retrieveAllPausedTasks() async =>
      pausedTasks.values.toList();

  @override
  Future<List<ResumeData>> retrieveAllResumeData() async =>
      resumeData.values.toList();

  @override
  Future<Task?> retrievePausedTask(String taskId) async => pausedTasks[taskId];

  @override
  Future<ResumeData?> retrieveResumeData(String taskId) async =>
      resumeData[taskId];

  @override
  Future<void> storePausedTask(Task task) async {
    pausedTasks[task.taskId] = task;
  }

  @override
  Future<void> storeResumeData(ResumeData resumeData) async {
    this.resumeData[resumeData.taskId] = resumeData;
  }
}
