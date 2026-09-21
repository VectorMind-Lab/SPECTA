import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../errors/specta_failure.dart';
import 'download_engine.dart';
import 'download_models.dart';

/// Phase 2G-C: the real [DownloadEngine] — a translation layer over the
/// `background_downloader` plugin (WorkManager on Android).
///
/// Boundary discipline (2G-C prompt §17/§18):
/// - This is the ONLY SPECTA file that may know the plugin's types
///   (`FileDownloader`, `DownloadTask`, `TaskStatus`, `TaskException`, …).
///   Everything crossing back into SPECTA does so as a
///   [DownloadEngineEvent] / [DownloadAttemptResult] / [DownloadFailure].
/// - The engine owns TRANSFER MECHANICS ONLY. It never retries on its own
///   (`retries: 0` — the manager owns the budget), never schedules its own
///   concurrency (the manager starts at most 9 attempts; the plugin executes
///   exactly the tasks it is given), never re-resolves sources and never
///   persists SPECTA state.
///
/// Engine task identity (2G-C §38): the plugin `taskId` IS the SPECTA
/// download id. That makes the mapping deterministic and reversible without
/// persisting any engine identifier: after process death the plugin task for
/// a persisted record is looked up from SPECTA's identity alone. No plugin
/// task id ever becomes product identity, and the SPECTA database remains the
/// only authoritative state. If a future plugin version removed this
/// guarantee, the fix would be an explicit engine-reconciliation field — not
/// an identity change.
///
/// Transfer lifecycle per attempt (verified against the installed 9.6.2
/// source, not from documentation):
/// - `enqueue` starts the task; status and progress updates arrive on the
///   `updates` stream. The attempt future settles on the FIRST terminal
///   status: complete / notFound / failed / canceled — and, crucially for
///   SPECTA's pause flow, `paused` (which the plugin treats as non-final: it
///   must settle the SPECTA attempt anyway, because the manager persisted
///   `paused` before asking and must not wait on a transfer that may never
///   end by itself). This is why the adapter is built on
///   `enqueue` + `updates` + a per-attempt completer rather than the plugin's
///   `download()` convenience future, which does not settle on pause.
/// - Progress updates carry the plugin's `expectedFileSize`, which — on
///   Android (TaskRunner.kt) — is the WHOLE-FILE size and the progress
///   fraction is WHOLE-FILE based (`(bytesTotal + startByte) /
///   (contentLength + startByte)`), i.e. already resume-aware. Bytes on disk
///   are therefore `progress * expectedFileSize` directly; no resume prefix
///   is added here (adding one would double-count the resumed bytes).
/// - `complete` means the plugin has moved the file to the task's `filename`
///   under the task's directory. SPECTA points that path at the manager's
///   derived `.part` path; the MANAGER's completion gate owns the final
///   rename — an incomplete transfer can never be mistaken for completed
///   media.
///
/// Failure translation (2G-C §41): the plugin's typed `TaskException`
/// subtypes map onto SPECTA failure types without over-claiming specificity;
/// unmatched exceptions degrade to `networkError` with the detail preserved
/// for diagnostics. Raw plugin exceptions never escape into SPECTA layers.
final class BackgroundDownloaderEngine implements DownloadEngine {
  BackgroundDownloaderEngine({@visibleForTesting FileDownloader? downloader})
      : _downloader = downloader ?? FileDownloader();

  final FileDownloader _downloader;

  /// One completer per live SPECTA attempt, keyed by download id (= taskId).
  /// In-memory only; after process death this is empty and rebuilt by
  /// [attach] from the plugin's own task bookkeeping.
  final Map<String, Completer<DownloadAttemptResult>> _attempts =
      <String, Completer<DownloadAttemptResult>>{};

  /// The task of the CURRENT attempt of each download id (for pause).
  final Map<String, DownloadTask> _activeTasks = <String, DownloadTask>{};

  /// Last known byte count per download id, used only when the server did
  /// not declare a size (no fabrication of either bytes or totals).
  final Map<String, int> _lastBytes = <String, int>{};

  StreamController<DownloadEngineEvent>? _events;
  StreamSubscription<TaskUpdate>? _updatesSubscription;

  /// The plugin's `updates` stream is SINGLE-SUBSCRIPTION
  /// (BaseDownloader.updates is a plain StreamController). A second adapter
  /// instance over the same FileDownloader — a provider rebuild, or tests
  /// constructing several engines — would otherwise throw "already listened"
  /// and silently lose every event. This per-downloader tap subscribes once
  /// and rebroadcasts to all adapter instances.
  static final Map<FileDownloader, StreamController<TaskUpdate>> _taps =
      <FileDownloader, StreamController<TaskUpdate>>{};

  static Stream<TaskUpdate> _tappedUpdates(FileDownloader downloader) {
    return _taps
        .putIfAbsent(downloader, () {
          final StreamController<TaskUpdate> controller =
              StreamController<TaskUpdate>.broadcast();
          downloader.updates.listen(
            controller.add,
            onError: controller.addError,
            cancelOnError: false,
          );
          return controller;
        })
        .stream;
  }

  /// Whether [start]/[attach]/[cancel]/[isTransferActive] has initialized the
  /// plugin. SPECTA must not spin up WorkManager machinery merely because
  /// the provider graph was built.
  bool _initialized = false;

  @override
  Stream<DownloadEngineEvent> get events {
    _ensureUpdateListener();
    return (_events ??= StreamController<DownloadEngineEvent>.broadcast())
        .stream;
  }

  /// Initializes the plugin: activates its persistent task database (required
  /// for restart reconciliation) WITHOUT rescheduling killed tasks behind
  /// SPECTA's back and WITHOUT auto-cleaning records
  /// (`doRescheduleKilledTasks: false` — the manager reconciles through
  /// [isTransferActive] and re-attempts under its own bounded budget;
  /// `autoCleanDatabase: false` — SPECTA's database decides what still
  /// matters; the plugin's own record retention is its internal bookkeeping
  /// and never SPECTA state).
  Future<void> _ensureInitialized() {
    if (_initialized) return Future<void>.value();
    _initialized = true;
    return _downloader.start(
      doTrackTasks: true,
      markDownloadedComplete: false,
      doRescheduleKilledTasks: false,
      autoCleanDatabase: false,
    );
  }

  void _ensureUpdateListener() {
    if (_updatesSubscription != null) return;
    _updatesSubscription = _tappedUpdates(_downloader).listen(
      _onPluginUpdate,
      onError: (Object _) {/* the plugin stream never carries SPECTA state;
        an update-stream error cannot settle attempts — those reconcile via
        their own terminal status or the manager's epochs. */},
      cancelOnError: false,
    );
  }

  // ---------------------------------------------------------------------------
  // DownloadEngine contract
  // ---------------------------------------------------------------------------

  @override
  Future<DownloadAttemptResult> start(DownloadAttemptInput input) async {
    await _ensureInitialized();
    _ensureUpdateListener();

    // One attempt = one plugin task, addressed by the SPECTA download id.
    // `retries: 0` keeps retry ownership in the manager. `allowPause: true`
    // lets the plugin pause/resume byte-accurately where the server supports
    // ranges. `requiresWiFi` is NOT set: the network policy decision belongs
    // to the manager (it only starts attempts when its policy allows) — a
    // second, contradicting policy here would fight SPECTA's own (2G-C §35:
    // no competing network policy system).
    final DownloadTask task = DownloadTask(
      taskId: input.downloadId,
      url: input.url,
      filename: p.basename(input.partPath),
      directory: _taskDirectory(input.partPath),
      baseDirectory: BaseDirectory.root,
      headers: input.headers,
      retries: 0,
      allowPause: true,
      updates: Updates.statusAndProgress,
      // Transfer infrastructure, not user-facing content: no notification
      // architecture in this phase (2G-C §42).
      displayName: input.downloadId,
    );
    _activeTasks[input.downloadId] = task;
    _lastBytes[input.downloadId] = input.resumeFrom;

    final Completer<DownloadAttemptResult> completer =
        Completer<DownloadAttemptResult>();
    _attempts[input.downloadId] = completer;

    final bool enqueued = await _downloader.enqueue(task);
    if (!enqueued) {
      _attempts.remove(input.downloadId);
      _activeTasks.remove(input.downloadId);
      return DownloadAttemptResult.failed(
        DownloadFailure(
          type: DownloadFailureType.engineFailure,
          message: DownloadFailureType.engineFailure.message,
          detail: 'The transfer engine refused to enqueue the task.',
        ),
        input.resumeFrom,
      );
    }

    try {
      return await completer.future;
    } finally {
      _attempts.remove(input.downloadId);
      _activeTasks.remove(input.downloadId);
      _lastBytes.remove(input.downloadId);
    }
  }

  @override
  Future<DownloadAttemptResult> attach(String downloadId) async {
    await _ensureInitialized();
    _ensureUpdateListener();

    // Probe the plugin's persistent task record. This is the engine's own
    // bookkeeping — never SPECTA state — and it is the only way to learn
    // what happened to a transfer while the Dart process was dead.
    TaskRecord? record;
    try {
      record = await _downloader.database.recordForId(downloadId);
    } on Object {
      record = null; // an unreadable record means "unknown"; treat as live
    }

    // Register the completer BEFORE consulting the record so a status update
    // racing between the probe and the switch settles the attempt instead of
    // being dropped.
    final Completer<DownloadAttemptResult> completer =
        Completer<DownloadAttemptResult>();
    _attempts[downloadId] = completer;
    if (record?.task case final DownloadTask task) {
      _activeTasks[downloadId] = task;
    }
    _lastBytes[downloadId] = _bytesFromRecord(record);

    try {
      if (record != null) {
        switch (record.status) {
          case TaskStatus.complete:
            return DownloadAttemptResult.completed(
              _bytesFromRecord(record),
              totalBytes:
                  record.expectedFileSize > 0 ? record.expectedFileSize : null,
            );
          case TaskStatus.notFound:
            // The source is gone — precisely the expired/unusable-source
            // case the manager's source-recovery path exists for.
            return DownloadAttemptResult.failed(
              DownloadFailure(
                type: DownloadFailureType.httpError,
                message: DownloadFailureType.httpError.message,
                detail: 'The engine reported the source was not found (404).',
              ),
              _bytesFromRecord(record),
            );
          case TaskStatus.failed:
            return DownloadAttemptResult.failed(
              _failureFor(record.exception),
              _bytesFromRecord(record),
            );
          case TaskStatus.canceled:
            return DownloadAttemptResult.cancelled(_bytesFromRecord(record));
          case TaskStatus.paused:
            // The previous session's pause took effect on the engine side
            // but the SPECTA record may still say `downloading` (process
            // died between persist and acknowledgement). The manager
            // reconciles this honestly as paused — the bytes are safe.
            return DownloadAttemptResult.paused(_bytesFromRecord(record));
          case TaskStatus.enqueued:
          case TaskStatus.running:
          case TaskStatus.waitingToRetry:
            break; // still live under WorkManager — updates will settle us
        }
      }
      // No terminal record (or no record at all): the transfer is (or was,
      // between the manager's probe and now) live in the native layer. Wait
      // for its updates like any other attempt. If it never settles, the
      // manager's pause/cancel remain available — cancelTaskWithId always
      // terminates the wait with a `canceled` status.
      return await completer.future;
    } finally {
      _attempts.remove(downloadId);
      _activeTasks.remove(downloadId);
      _lastBytes.remove(downloadId);
    }
  }

  @override
  Future<void> pause(String downloadId) async {
    final DownloadTask? task = _activeTasks[downloadId];
    if (task == null) return; // nothing running; the manager has already
    // persisted its paused state (persist-before-engine discipline).
    try {
      await _downloader.pause(task);
    } on Object {
      // The persisted paused state stands. A plugin that cannot pause keeps
      // transferring; its eventual terminal status reconciles idempotently
      // against the manager's epoch protection (a `complete` against a
      // paused record only updates the byte count, never resurrects state).
    }
  }

  @override
  Future<void> cancel(String downloadId) async {
    _activeTasks.remove(downloadId);
    final Completer<DownloadAttemptResult>? completer = _attempts[downloadId];
    try {
      await _ensureInitialized();
      await _downloader.cancelTaskWithId(downloadId);
    } on Object {
      // Idempotent: SPECTA's record is already cancelled.
    }
    // The plugin's `canceled` status normally settles the attempt; settle
    // here too so cancel() is meaningful even when the status update is
    // lost (e.g. the task was already gone). A later duplicate `canceled`
    // update is a no-op (the completer is already done or deregistered).
    if (completer != null && !completer.isCompleted) {
      completer.complete(DownloadAttemptResult.cancelled(0));
    }
  }

  @override
  Future<bool> isTransferActive(String downloadId) async {
    try {
      await _ensureInitialized();
      // The plugin's own bookkeeping: waiting-to-retry set, paused-task
      // store, and the platform's live task list (WorkManager on Android).
      final List<Task> active = await _downloader.allTasks(allGroups: true);
      return active.any((Task task) => task.taskId == downloadId);
    } on Object {
      // An engine that cannot answer is treated as holding nothing — the
      // manager then classifies `interrupted` and re-attempts under its own
      // budget (never a blind failure, never a blind trust).
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Plugin → SPECTA translation
  // ---------------------------------------------------------------------------

  /// The sealed [TaskUpdate] hierarchy has exactly two subtypes. Matching
  /// them on the base [Task] keeps the switch exhaustive (an update may in
  /// principle carry any [Task] subtype); SPECTA only ever enqueues
  /// [DownloadTask]s, so anything else (e.g. an [UploadTask] from other
  /// plugin users) is ignored rather than mis-translated.
  void _onPluginUpdate(TaskUpdate update) {
    switch (update) {
      case TaskProgressUpdate(
            task: final Task task,
            progress: final double progress,
            expectedFileSize: final int expected,
          ):
        if (task case final DownloadTask downloadTask) {
          _handleProgress(downloadTask, progress, expected);
        }
      case TaskStatusUpdate(
          task: final Task task,
          status: final TaskStatus status,
          exception: final TaskException? exception,
        ):
        if (task case final DownloadTask downloadTask) {
          _handleStatus(downloadTask, status, exception);
        }
    }
  }

  void _handleProgress(DownloadTask task, double progress, int expected) {
    // Whole-file math: the plugin's fraction and expected size already
    // include the resumed prefix (TaskRunner.kt computes
    // `(bytesTotal + startByte) / (contentLength + startByte)`), so bytes on
    // disk = progress * expected. Never add `resumeFrom` here — that would
    // double-count bytes the previous attempt already wrote.
    int bytes;
    if (expected > 0) {
      bytes = (progress * expected).round().clamp(0, expected);
    } else {
      // Without a declared total the fraction cannot produce a byte count;
      // hold the last known value (never fabricate either bytes or totals).
      bytes = _lastBytes[task.taskId] ?? 0;
    }
    final int previous = _lastBytes[task.taskId] ?? 0;
    if (bytes <= previous && progress < 1.0) return; // no regressions
    _lastBytes[task.taskId] = bytes;
    (_events ??= StreamController<DownloadEngineEvent>.broadcast()).add(
      DownloadEngineProgress(
        downloadId: task.taskId,
        bytesOnDisk: bytes,
        totalBytes: expected > 0 ? expected : null,
      ),
    );
  }

  void _handleStatus(
    DownloadTask task,
    TaskStatus status,
    TaskException? exception,
  ) {
    final int bytes = _lastBytes[task.taskId] ?? 0;
    switch (status) {
      case TaskStatus.enqueued:
      case TaskStatus.running:
      case TaskStatus.waitingToRetry:
        break; // transient — the attempt future only settles on terminal
      case TaskStatus.paused:
        // Non-final for the plugin, terminal for the SPECTA attempt: the
        // manager asked to pause (persist-before-engine) and must not wait
        // on a transfer the plugin may hold indefinitely.
        _settle(task.taskId, DownloadAttemptResult.paused(bytes));
      case TaskStatus.complete:
        // A completed file's size IS its total — the only total the engine
        // can state without inventing data (the plugin's progress updates
        // already carried the declared size while running).
        _settle(
          task.taskId,
          DownloadAttemptResult.completed(
            bytes,
            totalBytes: bytes > 0 ? bytes : null,
          ),
        );
      case TaskStatus.canceled:
        _settle(task.taskId, DownloadAttemptResult.cancelled(bytes));
      case TaskStatus.notFound:
        // The source is gone — precisely the expired/unusable-source case
        // the manager's source-recovery path exists for.
        _settle(
          task.taskId,
          DownloadAttemptResult.failed(
            DownloadFailure(
              type: DownloadFailureType.httpError,
              message: DownloadFailureType.httpError.message,
              detail: 'The engine reported the source was not found (404).',
            ),
            bytes,
          ),
        );
      case TaskStatus.failed:
        _settle(
          task.taskId,
          DownloadAttemptResult.failed(_failureFor(exception), bytes),
        );
    }
  }

  /// Bytes on disk implied by a plugin tracking record (same whole-file
  /// math as progress updates; 0 when the size was never declared).
  static int _bytesFromRecord(TaskRecord? record) {
    if (record == null || record.expectedFileSize <= 0) return 0;
    return (record.progress.clamp(0.0, 1.0) * record.expectedFileSize)
        .round();
  }

  void _settle(String downloadId, DownloadAttemptResult result) {
    final Completer<DownloadAttemptResult>? completer = _attempts[downloadId];
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  /// Maps a plugin failure onto the SPECTA failure model using the typed
  /// exception hierarchy — no more specificity than the evidence supports
  /// (2G-C §41). Raw plugin exceptions never escape into SPECTA layers.
  DownloadFailure _failureFor(TaskException? exception) {
    final String detail = exception?.toString() ?? 'Unknown engine failure';
    switch (exception) {
      case null:
        return _networkish(detail);
      case final TaskHttpException http:
        // A typed HTTP failure: 4xx means the source/attempt is unusable
        // (the URL itself may be expired), 5xx is plausibly transient.
        return http.httpResponseCode >= 400 && http.httpResponseCode < 500
            ? DownloadFailure(
                type: DownloadFailureType.httpError,
                message: DownloadFailureType.httpError.message,
                detail: detail,
              )
            : DownloadFailure(
                type: DownloadFailureType.serverError,
                message: DownloadFailureType.serverError.message,
                detail: detail,
              );
      case final TaskConnectionException _:
        return _networkish(detail);
      case final TaskFileSystemException _:
        // Filesystem-level failure (space, path): the storage pre-flight may
        // have been right, or the volume filled mid-transfer. Distinguishing
        // further would over-claim; the plugin's own words are kept in the
        // detail.
        return DownloadFailure(
          type: DownloadFailureType.storageFailure,
          message: DownloadFailureType.storageFailure.message,
          detail: detail,
        );
      case final TaskResumeException _:
        // Resume became impossible (e.g. the OS removed the partial file).
        // The manager treats this under its normal retry semantics; a
        // restart-from-scratch happens naturally on the next attempt.
        return DownloadFailure(
          type: DownloadFailureType.interrupted,
          message: DownloadFailureType.interrupted.message,
          detail: detail,
        );
      case final TaskUrlException _:
        return DownloadFailure(
          type: DownloadFailureType.invalidResponse,
          message: DownloadFailureType.invalidResponse.message,
          detail: detail,
        );
      case final TaskException _:
        return _networkish(detail);
    }
  }

  DownloadFailure _networkish(String detail) => DownloadFailure(
        type: DownloadFailureType.networkError,
        message: DownloadFailureType.networkError.message,
        detail: detail,
      );

  /// Test-only teardown: closes the event controller and the update
  /// subscription. Production engines live for the app's lifetime and are
  /// never disposed; tests create several engines and must not leak
  /// broadcast controllers between them.
  @visibleForTesting
  void disposeForTesting() {
    _updatesSubscription?.cancel();
    _updatesSubscription = null;
    _events?.close();
    _events = null;
    _attempts.clear();
    _activeTasks.clear();
    _lastBytes.clear();
    // The per-downloader tap survives: the plugin singleton and its
    // controller live for the whole test process, and the next engine must
    // keep receiving its events.
  }

  // ---------------------------------------------------------------------------
  // Path layout
  // ---------------------------------------------------------------------------

  /// The plugin writes into an absolute directory (BaseDirectory.root +
  /// directory — root resolves to the filesystem root on Android, so the
  /// joined path is SPECTA's absolute, app-private media directory).
  /// `directory` is the parent of the part file; `filename` (set in
  /// [start]) is the part file's basename.
  static String _taskDirectory(String partPath) => p.dirname(partPath);
}
