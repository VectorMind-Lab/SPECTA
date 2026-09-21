import 'dart:async';

import 'package:specta/core/downloads/download_engine.dart';
import 'package:specta/core/downloads/download_models.dart';
import 'package:specta/core/downloads/download_retry_policy.dart';
import 'package:specta/core/errors/specta_failure.dart';

/// Deterministic [DownloadEngine] for 2G-B tests.
///
/// Simulates the ENGINE side only: scripted completions, retryable and
/// non-retryable failures, pause/cancel acknowledgement, progress emission,
/// contract-violating throws, and a FIFO in-flight model that lets tests
/// deliver LATE results for superseded attempts (stale-callback coverage).
/// It never touches a filesystem — a "completed" result means *the engine
/// simulated completion*, not that a real media file exists (2G-B §9).
final class FakeDownloadEngine implements DownloadEngine {
  final StreamController<DownloadEngineEvent> _events =
      StreamController<DownloadEngineEvent>.broadcast();

  /// Outcome factories for the NEXT start() calls, in order. When the script
  /// is empty the attempt stays in flight until settled/released.
  final List<DownloadAttemptResult Function(DownloadAttemptInput)> script =
      <DownloadAttemptResult Function(DownloadAttemptInput)>[];

  /// In-flight attempts per download, OLDEST FIRST. Every unresolved start()
  /// appends here; settle completes the oldest incomplete entry — matching a
  /// real engine where control calls target the current transfer and late
  /// results arrive for superseded ones.
  final Map<String, List<Completer<DownloadAttemptResult>>> _inFlight =
      <String, List<Completer<DownloadAttemptResult>>>{};

  /// How many attempts were actually started (for concurrency assertions).
  int startedCount = 0;
  final List<DownloadAttemptInput> startedInputs = <DownloadAttemptInput>[];
  final List<String> pauseCalls = <String>[];
  final List<String> cancelCalls = <String>[];

  /// When true, start() throws — a deliberate engine contract violation the
  /// manager must convert into honest `engineFailure` data.
  bool throwOnStart = false;

  /// 2G-C restart adoption: ids for which [isTransferActive] answers TRUE
  /// (a transfer that survived process death under the engine), even with
  /// no in-flight attempt in this fake. The manager must then ADOPT via
  /// [attach] instead of failing the record.
  final Set<String> adoptable = <String>{};

  /// When true (default), pause()/cancel() settle the oldest in-flight
  /// attempt for the download — a real engine acknowledges control calls by
  /// settling the transfer. Tests set this false to hold the settlement and
  /// deliver it manually at a deterministic point.
  bool settleOnControl = true;

  @override
  Stream<DownloadEngineEvent> get events => _events.stream;

  int get activeCount => _inFlight.values
      .map<int>((List<Completer<DownloadAttemptResult>> l) => l.length)
      .fold(0, (int a, int b) => a + b);

  bool isActive(String downloadId) =>
      (_inFlight[downloadId] ?? const <Completer<DownloadAttemptResult>>[])
          .any((Completer<DownloadAttemptResult> c) => !c.isCompleted);

  void emitProgress(String downloadId, int bytes, {int? totalBytes}) {
    _events.add(DownloadEngineProgress(
      downloadId: downloadId,
      bytesOnDisk: bytes,
      totalBytes: totalBytes,
    ));
  }

  void completeWith(int bytes, {int? totalBytes}) {
    script.add((DownloadAttemptInput input) =>
        DownloadAttemptResult.completed(bytes, totalBytes: totalBytes));
  }

  void failWith(DownloadFailure failure, int bytes) {
    script.add(
        (DownloadAttemptInput input) => DownloadAttemptResult.failed(
            failure, bytes));
  }

  /// Settles the OLDEST in-flight attempt for [downloadId]. No-op when
  /// nothing is in flight.
  void settle(String downloadId, DownloadAttemptResult result) {
    final List<Completer<DownloadAttemptResult>>? queue = _inFlight[downloadId];
    if (queue == null) return;
    for (final Completer<DownloadAttemptResult> completer in queue) {
      if (!completer.isCompleted) {
        completer.complete(result);
        return;
      }
    }
  }

  @override
  Future<DownloadAttemptResult> start(DownloadAttemptInput input) async {
    if (throwOnStart) {
      startedCount++;
      startedInputs.add(input);
      throw StateError('engine exploded (simulated contract violation)');
    }
    startedCount++;
    startedInputs.add(input);

    if (script.isNotEmpty) {
      return script.removeAt(0)(input);
    }
    final Completer<DownloadAttemptResult> completer =
        Completer<DownloadAttemptResult>();
    (_inFlight[input.downloadId] ??= <Completer<DownloadAttemptResult>>[])
        .add(completer);
    try {
      return await completer.future;
    } finally {
      _inFlight[input.downloadId]?.remove(completer);
    }
  }

  @override
  Future<void> pause(String downloadId) async {
    pauseCalls.add(downloadId);
    if (settleOnControl) {
      settle(downloadId, const DownloadAttemptResult.paused(0));
    }
  }

  @override
  Future<void> cancel(String downloadId) async {
    cancelCalls.add(downloadId);
    if (settleOnControl) {
      settle(downloadId, const DownloadAttemptResult.cancelled(0));
    }
  }

  @override
  Future<bool> isTransferActive(String downloadId) async =>
      isActive(downloadId) || adoptable.contains(downloadId);

  /// 2G-C adoption seam: scripts or settles the adopted attempt like
  /// [start] — the fake holds no real engine bookkeeping, so "adopting" a
  /// surviving transfer behaves exactly like a scripted/in-flight start.
  /// Tests can either script an outcome beforehand or let the attempt sit
  /// in flight and settle it manually.
  @override
  Future<DownloadAttemptResult> attach(String downloadId) async {
    if (script.isNotEmpty) {
      final DownloadAttemptInput probe = DownloadAttemptInput(
        downloadId: downloadId,
        url: 'adopted://$downloadId',
        partPath: '/adopted/$downloadId.part',
        resumeFrom: 0,
      );
      return script.removeAt(0)(probe);
    }
    final Completer<DownloadAttemptResult> completer =
        Completer<DownloadAttemptResult>();
    (_inFlight[downloadId] ??= <Completer<DownloadAttemptResult>>[])
        .add(completer);
    try {
      return await completer.future;
    } finally {
      _inFlight[downloadId]?.remove(completer);
    }
  }

  void dispose() {
    unawaited(_events.close());
  }
}

/// Deterministic [DownloadClock]: controllable virtual time, no real waiting.
final class FakeDownloadClock implements DownloadClock {
  DateTime _now = DateTime(2026, 9, 20, 12);

  /// Pending delayed callbacks, in schedule order.
  final List<(DateTime, Completer<void>)> _pendingDelays =
      <(DateTime, Completer<void>)>[];

  DateTime get nowValue => _now;

  int get pendingDelayCount => _pendingDelays.length;

  @override
  DateTime now() => _now;

  @override
  Future<void> delay(Duration duration) {
    final Completer<void> completer = Completer<void>();
    _pendingDelays.add((_now.add(duration), completer));
    return completer.future;
  }

  /// Advances virtual time; every delay whose deadline has passed completes.
  void advance(Duration duration) {
    _now = _now.add(duration);
    for (int i = _pendingDelays.length - 1; i >= 0; i--) {
      final (DateTime deadline, Completer<void> completer) =
          _pendingDelays[i];
      if (deadline.isAfter(_now)) continue;
      _pendingDelays.removeAt(i);
      if (!completer.isCompleted) completer.complete();
    }
  }
}
