@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/downloads/background_downloader_engine.dart';
import 'package:specta/core/downloads/download_engine.dart';
import 'package:specta/core/downloads/download_models.dart';
import 'package:specta/core/errors/specta_failure.dart';

/// 2G-C deterministic adapter tests.
///
/// The adapter is driven through the plugin's own testing seams (the same
/// pattern background_downloader's `issue_727_test.dart` uses):
/// - an in-memory [PersistentStorage] replaces the plugin's tracking DB;
/// - the plugin's method channels are mocked;
/// - native → Dart updates are pushed via
///   `downloaderForTesting.processStatusUpdate/processProgressUpdate`.
///
/// Every test is fully deterministic — no network, no real transfer. What is
/// under test is TRANSLATION and LIFECYCLE at the SPECTA boundary: plugin
/// facts in, SPECTA-owned facts out, plugin types never crossing back.
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

  /// The plugin FileDownloader is an app-lifetime singleton: it is created
  /// exactly once (setUpAll) with the in-memory storage; every engine under
  /// test wraps that same instance. Tests never call destroy() — engine
  /// teardown is disposeForTesting(), which only closes SPECTA-owned
  /// streams and never the shared plugin state.
  BackgroundDownloaderEngine engine() =>
      BackgroundDownloaderEngine(downloader: FileDownloader());

  DownloadAttemptInput input(String id, {int resumeFrom = 0}) =>
      DownloadAttemptInput(
        downloadId: id,
        url: 'https://cdn.example/video.mp4',
        partPath: '/media/Title.mp4.part',
        resumeFrom: resumeFrom,
      );

  DownloadTask pluginTask(String id) => DownloadTask(
    taskId: id,
    url: 'https://cdn.example/video.mp4',
    filename: 'Title.mp4.part',
    directory: '/media',
    baseDirectory: BaseDirectory.root,
    updates: Updates.statusAndProgress,
    allowPause: true,
  );

  group('start / enqueue', () {
    test(
      'enqueue carries the SPECTA download id as the deterministic task id',
      () async {
        final BackgroundDownloaderEngine e = engine();
        final Future<DownloadAttemptResult> attempt = e.start(input('dl|1'));
        await Future<void>.delayed(Duration.zero);

        expect(enqueuedTaskJson, hasLength(1));
        final Map<String, Object?> task = enqueuedTaskJson.single;
        expect(
          task['taskId'],
          'dl|1',
          reason:
              '2G-C §38: SPECTA download identity IS the engine task id — '
              'reversible without persisting engine metadata',
        );
        expect(task['allowPause'], isTrue);
        expect(
          jsonEncode(task),
          isNot(contains('"retries":1')),
          reason: 'no second retry budget inside the plugin',
        );
        // The engine must not hold SPECTA state; settle to keep the test clean.
        FileDownloader().downloaderForTesting.processStatusUpdate(
          TaskStatusUpdate(pluginTask('dl|1'), TaskStatus.canceled),
        );
        await attempt;
        e.disposeForTesting();
      },
    );

    test(
      'progress translation uses WHOLE-FILE math (no resume double-count)',
      () async {
        final BackgroundDownloaderEngine e = engine();
        final List<DownloadEngineEvent> events = <DownloadEngineEvent>[];
        final StreamSubscription<DownloadEngineEvent> sub = e.events.listen(
          events.add,
        );

        // resumeFrom is the bytes the PREVIOUS attempt wrote; the plugin's
        // fraction is already whole-file (TaskRunner.kt), so a 0.5 fraction at
        // expected 1000 must report 500 bytes — NOT resumeFrom + 500.
        final Future<DownloadAttemptResult> attempt = e.start(
          input('dl|2', resumeFrom: 400),
        );
        await Future<void>.delayed(Duration.zero);

        final DownloadTask task = pluginTask('dl|2');
        FileDownloader().downloaderForTesting.processProgressUpdate(
          TaskProgressUpdate(task, 0.5, 1000),
        );
        FileDownloader().downloaderForTesting.processStatusUpdate(
          TaskStatusUpdate(task, TaskStatus.canceled),
        );
        final DownloadAttemptResult result = await attempt;
        await sub.cancel();

        final DownloadEngineProgress progress = events
            .whereType<DownloadEngineProgress>()
            .single;
        expect(
          progress.bytesOnDisk,
          500,
          reason:
              'progress * expected, whole-file — the resumed prefix is '
              'already inside the plugin fraction',
        );
        expect(progress.totalBytes, 1000);
        expect(result.kind, DownloadAttemptOutcomeKind.cancelled);
        e.disposeForTesting();
      },
    );

    test('a size-less stream never fabricates bytes or totals', () async {
      final BackgroundDownloaderEngine e = engine();
      final List<DownloadEngineEvent> events = <DownloadEngineEvent>[];
      final StreamSubscription<DownloadEngineEvent> sub = e.events.listen(
        events.add,
      );

      final Future<DownloadAttemptResult> attempt = e.start(
        input('dl|3', resumeFrom: 250),
      );
      await Future<void>.delayed(Duration.zero);

      final DownloadTask task = pluginTask('dl|3');
      // expectedFileSize -1 (server declared no length).
      FileDownloader().downloaderForTesting.processProgressUpdate(
        TaskProgressUpdate(task, 0.7, -1),
      );
      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(task, TaskStatus.canceled),
      );
      await attempt;
      await sub.cancel();

      expect(
        events,
        isEmpty,
        reason: 'no total → hold the last known bytes; no fabricated data',
      );
      e.disposeForTesting();
    });
  });

  group('status translation', () {
    test(
      'complete settles the attempt completed with the transferred bytes',
      () async {
        final BackgroundDownloaderEngine e = engine();
        final Future<DownloadAttemptResult> attempt = e.start(input('dl|4'));
        await Future<void>.delayed(Duration.zero);

        final DownloadTask task = pluginTask('dl|4');
        FileDownloader().downloaderForTesting.processProgressUpdate(
          TaskProgressUpdate(task, 1.0, 4096),
        );
        FileDownloader().downloaderForTesting.processStatusUpdate(
          TaskStatusUpdate(task, TaskStatus.complete),
        );
        final DownloadAttemptResult result = await attempt;

        expect(result.kind, DownloadAttemptOutcomeKind.completed);
        expect(result.bytesOnDisk, 4096);
        expect(result.totalBytes, 4096);
        e.disposeForTesting();
      },
    );

    test('complete reports the DECLARED total, never a total derived from its '
        'own byte count (the truncated-transfer disguise)', () async {
      // The real-device shape: one size-bearing update, then a FINAL update
      // with no size (the plugin does not always emit one for a fast
      // transfer), then `complete` whose byte count is stale mid-flight
      // accounting. Reporting `bytes` as the total would make a short
      // transfer look self-consistent.
      final BackgroundDownloaderEngine e = engine();
      final Future<DownloadAttemptResult> attempt = e.start(input('dl|30'));
      await Future<void>.delayed(Duration.zero);

      final DownloadTask task = pluginTask('dl|30');
      FileDownloader().downloaderForTesting.processProgressUpdate(
        TaskProgressUpdate(task, 0.25, 8000),
      );
      FileDownloader().downloaderForTesting.processProgressUpdate(
        TaskProgressUpdate(task, 0.25, 0),
      );
      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(task, TaskStatus.complete),
      );
      final DownloadAttemptResult result = await attempt;

      expect(result.kind, DownloadAttemptOutcomeKind.completed);
      expect(result.bytesOnDisk, 2000);
      expect(
        result.totalBytes,
        8000,
        reason:
            'the source declared 8000 — the engine must not restate its '
            'own 2000 as the total',
      );
      e.disposeForTesting();
    });

    test('complete with no declared size reports totalBytes null — never the '
        'byte count', () async {
      final BackgroundDownloaderEngine e = engine();
      final Future<DownloadAttemptResult> attempt = e.start(input('dl|31'));
      await Future<void>.delayed(Duration.zero);

      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(pluginTask('dl|31'), TaskStatus.complete),
      );
      final DownloadAttemptResult result = await attempt;

      expect(result.kind, DownloadAttemptOutcomeKind.completed);
      expect(
        result.totalBytes,
        isNull,
        reason: 'no source-declared size means unknown, never invented',
      );
      e.disposeForTesting();
    });

    test('paused settles the attempt even though the plugin treats it as '
        'non-final (the pause-hang hazard)', () async {
      final BackgroundDownloaderEngine e = engine();
      final Future<DownloadAttemptResult> attempt = e.start(input('dl|5'));
      await Future<void>.delayed(Duration.zero);

      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(pluginTask('dl|5'), TaskStatus.paused),
      );
      final DownloadAttemptResult result = await attempt.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException(
          'paused must settle the SPECTA attempt — the manager persisted '
          'paused BEFORE asking and must never wait forever',
        ),
      );

      expect(result.kind, DownloadAttemptOutcomeKind.paused);
      e.disposeForTesting();
    });

    test(
      'notFound maps to the source-recovery classification (httpError)',
      () async {
        final BackgroundDownloaderEngine e = engine();
        final Future<DownloadAttemptResult> attempt = e.start(input('dl|6'));
        await Future<void>.delayed(Duration.zero);

        FileDownloader().downloaderForTesting.processStatusUpdate(
          TaskStatusUpdate(pluginTask('dl|6'), TaskStatus.notFound),
        );
        final DownloadAttemptResult result = await attempt;

        expect(result.kind, DownloadAttemptOutcomeKind.failed);
        expect(
          result.failure!.type,
          DownloadFailureType.httpError,
          reason:
              'the source is gone — exactly the case the manager’s '
              'fresh-source recovery exists for',
        );
        e.disposeForTesting();
      },
    );

    test('typed plugin failures map onto SPECTA failures without leaking '
        'plugin types', () async {
      final BackgroundDownloaderEngine e = engine();
      final Future<DownloadAttemptResult> attempt = e.start(input('dl|7'));
      await Future<void>.delayed(Duration.zero);

      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(
          pluginTask('dl|7'),
          TaskStatus.failed,
          TaskHttpException('gone', 404),
        ),
      );
      final DownloadAttemptResult result = await attempt;

      expect(result.failure!.type, DownloadFailureType.httpError);
      expect(result.failure!.detail, isNotNull);
      // The failure itself is SPECTA-owned data:
      expect(result.failure, isA<DownloadFailure>());
      e.disposeForTesting();
    });

    test(
      '5xx maps to serverError (plausibly transient), 4xx to httpError',
      () async {
        final BackgroundDownloaderEngine e = engine();
        final Future<DownloadAttemptResult> attempt = e.start(input('dl|8'));
        await Future<void>.delayed(Duration.zero);

        FileDownloader().downloaderForTesting.processStatusUpdate(
          TaskStatusUpdate(
            pluginTask('dl|8'),
            TaskStatus.failed,
            TaskHttpException('overloaded', 503),
          ),
        );
        final DownloadAttemptResult result = await attempt;
        expect(result.failure!.type, DownloadFailureType.serverError);
        e.disposeForTesting();
      },
    );

    test('filesystem/resume/connection/url exceptions map honestly', () async {
      final BackgroundDownloaderEngine e = engine();

      Future<DownloadFailureType> classify(TaskException exception) async {
        final String id = 'dl|${exception.runtimeType.hashCode}';
        final Future<DownloadAttemptResult> attempt = e.start(input(id));
        await Future<void>.delayed(Duration.zero);
        FileDownloader().downloaderForTesting.processStatusUpdate(
          TaskStatusUpdate(pluginTask(id), TaskStatus.failed, exception),
        );
        final DownloadAttemptResult result = await attempt;
        return result.failure!.type;
      }

      expect(
        await classify(TaskFileSystemException('disk full')),
        DownloadFailureType.storageFailure,
      );
      expect(
        await classify(TaskConnectionException('reset by peer')),
        DownloadFailureType.networkError,
      );
      expect(
        await classify(TaskResumeException('etag changed')),
        DownloadFailureType.interrupted,
      );
      expect(
        await classify(TaskUrlException('bad redirect')),
        DownloadFailureType.invalidResponse,
      );
      e.disposeForTesting();
    });

    test('stale terminal updates after settlement are harmless', () async {
      final BackgroundDownloaderEngine e = engine();
      final Future<DownloadAttemptResult> attempt = e.start(input('dl|9'));
      await Future<void>.delayed(Duration.zero);

      final DownloadTask task = pluginTask('dl|9');
      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(task, TaskStatus.complete),
      );
      final DownloadAttemptResult first = await attempt;
      // A late duplicate/contradicting status for the settled attempt:
      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(task, TaskStatus.failed),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        first.kind,
        DownloadAttemptOutcomeKind.completed,
        reason:
            'the first terminal result stands; late noise cannot '
            'rewrite a settled attempt',
      );
      e.disposeForTesting();
    });

    test(
      'updates for non-download tasks are ignored, not mis-translated',
      () async {
        final BackgroundDownloaderEngine e = engine();
        final List<DownloadEngineEvent> events = <DownloadEngineEvent>[];
        final StreamSubscription<DownloadEngineEvent> sub = e.events.listen(
          events.add,
        );

        final Future<DownloadAttemptResult> attempt = e.start(input('dl|10'));
        await Future<void>.delayed(Duration.zero);

        // An UploadTask update (another plugin user's task) must not settle or
        // report anything for SPECTA's attempt.
        final UploadTask foreign = UploadTask(
          taskId: 'dl|10',
          url: 'https://cdn.example/upload',
          filename: 'x.bin',
          directory: '/media',
          baseDirectory: BaseDirectory.root,
        );
        FileDownloader().downloaderForTesting.processStatusUpdate(
          TaskStatusUpdate(foreign, TaskStatus.complete),
        );
        await Future<void>.delayed(Duration.zero);

        expect(events, isEmpty);
        // The SPECTA attempt is still waiting; settle it honestly.
        FileDownloader().downloaderForTesting.processStatusUpdate(
          TaskStatusUpdate(pluginTask('dl|10'), TaskStatus.canceled),
        );
        await attempt;
        await sub.cancel();
        e.disposeForTesting();
      },
    );
  });

  group('attach (restart adoption)', () {
    test(
      'a completed plugin record settles immediately — no new transfer',
      () async {
        final BackgroundDownloaderEngine e = engine();
        final DownloadTask task = pluginTask('dl|11');
        await storage.storeTaskRecord(
          TaskRecord(task, TaskStatus.complete, 1.0, 8192),
        );

        final DownloadAttemptResult result = await e.attach('dl|11');
        expect(result.kind, DownloadAttemptOutcomeKind.completed);
        expect(result.bytesOnDisk, 8192);
        expect(result.totalBytes, 8192);
        expect(
          enqueuedTaskJson,
          isEmpty,
          reason:
              'adoption must NOT re-enqueue — the plugin has no existing-'
              'task guard, and a second native task would duplicate work',
        );
        e.disposeForTesting();
      },
    );

    test(
      'a live plugin record is adopted and settled by its updates',
      () async {
        final BackgroundDownloaderEngine e = engine();
        final DownloadTask task = pluginTask('dl|12');
        await storage.storeTaskRecord(
          TaskRecord(task, TaskStatus.running, 0.25, 4000),
        );

        final Future<DownloadAttemptResult> attempt = e.attach('dl|12');
        await Future<void>.delayed(Duration.zero);

        FileDownloader().downloaderForTesting.processProgressUpdate(
          TaskProgressUpdate(task, 0.5, 4000),
        );
        FileDownloader().downloaderForTesting.processStatusUpdate(
          TaskStatusUpdate(task, TaskStatus.complete),
        );
        final DownloadAttemptResult result = await attempt;

        expect(result.kind, DownloadAttemptOutcomeKind.completed);
        expect(result.bytesOnDisk, 2000);
        expect(enqueuedTaskJson, isEmpty);
        e.disposeForTesting();
      },
    );

    test('an unknown record (probe said active, engine lost it meanwhile) '
        'stays waitable — cancel() resolves it instead of hanging', () async {
      final BackgroundDownloaderEngine e = engine();
      final Future<DownloadAttemptResult> attempt = e.attach('dl|13');
      await Future<void>.delayed(Duration.zero);

      await e.cancel('dl|13');
      final DownloadAttemptResult result = await attempt.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException(
          'cancel must settle an adopted attempt whose record vanished',
        ),
      );
      expect(result.kind, DownloadAttemptOutcomeKind.cancelled);
      e.disposeForTesting();
    });
  });

  group('isTransferActive (restart seam)', () {
    test(
      'answers false when the engine holds nothing (mocked allTasks)',
      () async {
        final BackgroundDownloaderEngine e = engine();
        expect(await e.isTransferActive('nope|1'), isFalse);
        e.disposeForTesting();
      },
    );
  });

  group('cancellation (2G-C §13/§17)', () {
    test('cancel settles the running attempt cancelled and cancels the '
        'native task by the SPECTA id', () async {
      final BackgroundDownloaderEngine e = engine();
      final Future<DownloadAttemptResult> attempt = e.start(input('dl|20'));
      await Future<void>.delayed(Duration.zero);

      await e.cancel('dl|20');
      final DownloadAttemptResult result = await attempt;

      expect(
        result.kind,
        DownloadAttemptOutcomeKind.cancelled,
        reason:
            'the manager\'s cancellation must settle the attempt — it '
            'cannot wait on a native callback that may never come',
      );
      e.disposeForTesting();
    });

    test('a late plugin `canceled` status after engine settlement is '
        'harmless (no crash, no resurrection)', () async {
      final BackgroundDownloaderEngine e = engine();
      final Future<DownloadAttemptResult> attempt = e.start(input('dl|21'));
      await Future<void>.delayed(Duration.zero);
      await e.cancel('dl|21');
      await attempt;

      // The plugin's own `canceled` status arrives late, after the engine
      // already settled the attempt: a duplicate settle must be a no-op.
      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(pluginTask('dl|21'), TaskStatus.canceled),
      );
      // And a contradicting late status after deregistration:
      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(pluginTask('dl|21'), TaskStatus.complete),
      );
      await Future<void>.delayed(Duration.zero);

      // No crash is the assertion — the attempt settled exactly once.
      e.disposeForTesting();
    });

    test('cancel of an unknown/finished id is idempotent', () async {
      final BackgroundDownloaderEngine e = engine();
      // Nothing was ever started for this id.
      await e.cancel('dl|22');
      await e.cancel('dl|22');
      e.disposeForTesting();
    });
  });
}

/// The plugin's InMemoryPersistentStorage (from its issue_727 test), plus a
/// records map the tests can seed directly for `attach` scenarios.
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
