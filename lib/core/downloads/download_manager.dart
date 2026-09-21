import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../extensions/contract/extension_source.dart';
import '../errors/specta_failure.dart';
import '../storage/specta_storage.dart';
import 'device_environment.dart';
import 'download_engine.dart';
import 'download_models.dart';
import 'download_retry_policy.dart';
import 'download_store.dart';
import '../sources/source_pool.dart';

/// What [DownloadManager.enqueue] decided for a request whose identity
/// already existed (or was newly created). Documented duplicate semantics —
/// a repeated request never silently creates a second independent download.
enum DownloadEnqueueAction {
  /// A new record was created and queued.
  created,

  /// The pool offered no direct-file (MP4) candidate, so the record was
  /// created directly in the honest `failed` state (`unsupportedSource`).
  /// No attempt was ever started and no attempt budget was spent.
  createdFailed,

  /// The identity is already queued — left untouched (FIFO order preserved).
  alreadyQueued,

  /// The identity is already actively downloading — no second attempt.
  alreadyDownloading,

  /// The identity is paused — left untouched for the user to resume.
  alreadyPaused,

  /// The identity already completed. Re-downloading requires an explicit
  /// remove first; a repeat request never recreates the download.
  alreadyCompleted,

  /// The identity had failed; the explicit re-request re-queued it as a new
  /// run (attempt budget reset — deliberate, user-initiated).
  requeuedFailed,

  /// The identity was cancelled; the explicit re-request re-queued it as a
  /// new run (attempt budget reset — deliberate, user-initiated).
  requeuedCancelled,
}

final class EnqueueResult {
  const EnqueueResult({required this.record, required this.action});

  final DownloadRecord record;
  final DownloadEnqueueAction action;
}

/// Where the manager obtains a source pool for a download's next attempt.
///
/// Recovery seam (2G-A §23): the resolved URL belongs to an individual
/// attempt and is never persisted; recovery re-resolves through SPECTA's
/// existing layers. Phase 2G-B shipped a session-only resolver; Phase 2G-C's
/// production resolver ([SourceManagerDownloadResolver]) re-resolves through
/// the real [SourceManager] using the persisted provenance whenever the
/// session holds no pool or the last attempt failed with a source-type
/// failure (the captured URL itself is not trusted after that).
abstract interface class DownloadSourceResolver {
  /// Failure types that mean "the SOURCE/URL itself became unusable" —
  /// after any of these, a captured pool must not be reused (the stale-pool
  /// requeue hazard): the captured URL is precisely the one that just failed.
  /// Engine/network/storage failures do NOT invalidate the source; the
  /// captured pool stays authoritative for the next attempt.
  ///
  /// Canonical definition, shared by every resolver implementation so the
  /// classifications can never drift apart.
  static const Set<DownloadFailureType> sourceInvalidatingFailures =
      <DownloadFailureType>{
    DownloadFailureType.httpError,
    DownloadFailureType.invalidResponse,
    DownloadFailureType.unsupportedSource,
    DownloadFailureType.sourcesExhausted,
  };

  /// The pool for [record]'s next attempt, or null when it cannot be
  /// resolved right now.
  ///
  /// [lastFailure] is the failure of the PREVIOUS attempt of this download
  /// when that attempt ended in a source-classified failure (the manager
  /// keeps it in memory for exactly one recovery decision). Resolvers that
  /// hold a captured pool MUST NOT reuse it when [lastFailure] indicates the
  /// source itself became unusable — that is the stale-pool requeue hazard.
  Future<SourcePool?> resolveSource(
    DownloadRecord record, {
    DownloadFailure? lastFailure,
  });

  /// Remembers the pool captured at enqueue/re-enqueue time for [id] (the
  /// user's freshest resolution inputs — a re-request must consume these,
  /// never a stale pool from a previous run).
  void rememberPool(String id, SourcePool pool);

  /// Forgets any pool held for [id] (record removed / run superseded).
  void forgetPool(String id);
}

/// 2G-B-style session resolver: returns the pool captured at enqueue time
/// within this manager session. Still the constructor default so plain unit
/// tests need no extension infrastructure; production wiring installs
/// [SourceManagerDownloadResolver] instead. After a restart no pool is held
/// and the honest answer is null (the attempt fails `sourcesExhausted`).
///
/// Source-invalidation discipline (2G-C §25, same rule the production
/// resolver implements): a captured pool is NEVER served for an attempt whose
/// predecessor failed with a source-classified failure — the captured URL is
/// precisely the one that just proved unusable, and re-serving it would be
/// the stale-pool requeue hazard. The session resolver has no re-resolution
/// path (that is the production resolver's job), so the honest answer after
/// such a failure is null — the manager classifies that as
/// `sourcesExhausted` under its bounded retry budget.
final class SessionDownloadSourceResolver implements DownloadSourceResolver {
  final Map<String, SourcePool> _pools = <String, SourcePool>{};

  @override
  void rememberPool(String id, SourcePool pool) => _pools[id] = pool;

  @override
  void forgetPool(String id) => _pools.remove(id);

  @override
  Future<SourcePool?> resolveSource(
    DownloadRecord record, {
    DownloadFailure? lastFailure,
  }) async {
    final bool sourceInvalidated = lastFailure != null &&
        DownloadSourceResolver.sourceInvalidatingFailures
            .contains(lastFailure.type);
    if (sourceInvalidated) {
      // The captured URL just failed as unusable. Drop it — never re-serve
      // the dead URL, and never let a later attempt inherit it silently.
      _pools.remove(record.id);
      return null;
    }
    return _pools[record.id];
  }
}

/// Verifies and finalizes an engine-reported completion (2G-C §40: a
/// transfer is not `completed` merely because a callback said so).
///
/// The finalizer owns the `.part` → final rename: the engine writes into the
/// part path only; the final media path exists exactly when the manager has
/// verified the transfer. It returns the verified byte count (the engine's
/// count when it reported one — the byte-count audit is the engine's own
/// transfer accounting; the file size is the fallback when it did not) and
/// throws a structured [DownloadFailure] when no valid final file exists.
///
/// Injectable for the same reason as [DownloadClock]: deterministic tests
/// and production share the manager, never the filesystem assumptions.
abstract interface class DownloadCompletionFinalizer {
  Future<int> finalize(DownloadRecord record, int engineBytes);
}

/// The production finalizer: real filesystem verification.
///
/// - part file exists → rename onto the final path (SPECTA's own derived
///   path for this download id — any stale file there is this download's
///   own previous artifact, never an unrelated user file) and verify.
/// - part file absent but a non-empty final exists (e.g. an adopted transfer
///   whose rename already happened) → accept with its size as fallback.
/// - neither → the engine reported completion without producing a file: an
///   honest `engineFailure` (never masked as success).
final class FileDownloadCompletionFinalizer
    implements DownloadCompletionFinalizer {
  const FileDownloadCompletionFinalizer();

  @override
  Future<int> finalize(DownloadRecord record, int engineBytes) async {
    final File part = File(downloadPartPathFor(record.filePath));
    final File finalFile = File(record.filePath);
    if (await part.exists()) {
      try {
        await finalFile.parent.create(recursive: true);
        if (await finalFile.exists()) {
          await finalFile.delete(); // this download's own stale artifact
        }
        await part.rename(finalFile.path);
      } on Object {
        throw DownloadFailure(
          type: DownloadFailureType.storageFailure,
          message: DownloadFailureType.storageFailure.message,
          detail: 'The completed transfer could not be moved into place.',
        );
      }
    }
    if (!await finalFile.exists()) {
      throw DownloadFailure(
        type: DownloadFailureType.engineFailure,
        message: DownloadFailureType.engineFailure.message,
        detail: 'The engine reported completion but produced no file.',
      );
    }
    final int size = await finalFile.length();
    if (size <= 0) {
      throw DownloadFailure(
        type: DownloadFailureType.storageFailure,
        message: DownloadFailureType.storageFailure.message,
        detail: 'The completed transfer produced an empty file.',
      );
    }
    return engineBytes > 0 ? engineBytes : size;
  }
}

/// Decides when a live progress tick is worth a SQLite write (persistence
/// contract §10: progress is persistent SPECTA state, but the events
/// themselves are transient — never write every callback).
///
/// Pure and deterministic: persist when either the byte delta since the last
/// persisted write reaches [minBytesDelta], or at least [minInterval] has
/// passed since it. State transitions always persist and bypass this policy.
final class DownloadProgressPersistPolicy {
  const DownloadProgressPersistPolicy({
    this.minBytesDelta = 256 * 1024,
    this.minInterval = const Duration(seconds: 2),
  });

  final int minBytesDelta;
  final Duration minInterval;

  bool shouldPersist({
    required int lastPersistedBytes,
    required int currentBytes,
    required DateTime? lastPersistedAt,
    required DateTime now,
  }) {
    if (currentBytes - lastPersistedBytes >= minBytesDelta) return true;
    final DateTime? last = lastPersistedAt;
    if (last == null) return true;
    return now.difference(last) >= minInterval;
  }
}

/// SPECTA's download domain orchestrator (Phase 2G-B).
///
/// Owns everything product-level about downloads — identity, persistence
/// coordination, the persistent FIFO queue, the concurrency policy, the state
/// machine enforcement, the retry budget, cancellation, pause/resume,
/// duplicate handling, stale-callback protection and provider-facing change
/// notification — while the [DownloadEngine] abstraction owns only transfer
/// mechanics. The manager never imports a downloader package or platform API.
///
/// Persistence discipline (2G-A contract, unchanged):
/// - the [DownloadStore] is the ONLY authoritative state; the manager's
///   in-memory maps are mirrors that can be rebuilt from it at any time;
/// - the intended state transition is PERSISTED before the engine is asked
///   to act (never the reverse), so a process death between the two leaves
///   an honestly reconcilable record;
/// - a streaming URL is attempt-scoped and never persisted;
/// - every mutating operation runs inside one serialized section (a chained
///   future, the same discipline as the persistent playback sink), so
///   overlapping triggers cannot double-start a download, exceed the
///   concurrency limit or interleave two state transitions.
final class DownloadManager {
  DownloadManager({
    required this.store,
    required this.engine,
    required this.environment,
    DownloadSourceResolver? sourceResolver,
    DownloadCompletionFinalizer? completionFinalizer,
    this.retryPolicy = const DownloadRetryPolicy(),
    this.progressPolicy = const DownloadProgressPersistPolicy(),
    this.clock = const SystemDownloadClock(),
    this.networkPolicy = DownloadNetworkPolicy.wifiOnly,
    Future<String> Function()? mediaDirectory,
    int concurrency = defaultConcurrency,
    this.onChanged,
  })  : _sourceResolver =
            sourceResolver ?? SessionDownloadSourceResolver(),
        _completionFinalizer =
            completionFinalizer ?? const FileDownloadCompletionFinalizer(),
        _mediaDirectory = mediaDirectory ?? _defaultMediaDirectory {
    _concurrency = _clampConcurrency(concurrency);
  }

  /// Agreed product policy (mirrors the Settings foundation's constants):
  /// default 3 concurrent downloads, hard ceiling 9. The manager clamps any
  /// configured value into 1..9 — it must never become unlimited.
  static const int defaultConcurrency = 3;
  static const int maxConcurrency = 9;

  final DownloadStore store;
  final DownloadEngine engine;
  final DeviceEnvironment environment;
  final DownloadSourceResolver _sourceResolver;

  /// Verifies engine-reported completions and owns the final rename
  /// (persistence contract: only the manager turns a transfer into media).
  final DownloadCompletionFinalizer _completionFinalizer;
  final DownloadRetryPolicy retryPolicy;
  final DownloadProgressPersistPolicy progressPolicy;
  final DownloadClock clock;
  final DownloadNetworkPolicy networkPolicy;
  final Future<String> Function() _mediaDirectory;

  /// Fired after every persisted change or active-set change so the provider
  /// layer can refresh (same seam as the persistent playback sink).
  final void Function()? onChanged;

  int _concurrency = defaultConcurrency;
  bool _initialized = false;
  bool _disposed = false;

  /// Serialization of every state decision. Chained futures — no timing luck.
  Future<void> _mutex = Future<void>.value();

  /// In-memory attempt generations: one epoch per engine start. Guards every
  /// asynchronous result against being applied to the wrong attempt.
  final Map<String, int> _activeEpoch = <String, int>{};
  int _epochCounter = 0;

  /// Latest progress reported by the engine for the running attempt.
  final Map<String, DownloadProgress> _liveProgress = <String, DownloadProgress>{};
  final Map<String, int> _lastPersistedBytes = <String, int>{};
  final Map<String, DateTime> _lastPersistedAt = <String, DateTime>{};

  /// The failure that ended the previous attempt of a download, kept for the
  /// one recovery decision that follows it (source-classified failures must
  /// trigger fresh resolution, not a stale captured pool). Cleared when a
  /// new attempt starts.
  final Map<String, DownloadFailure> _lastSourceFailure =
      <String, DownloadFailure>{};

  StreamSubscription<DownloadEngineEvent>? _eventsSubscription;

  /// How many attempts are actually running right now (in-memory truth —
  /// a persisted `downloading` record after process death is NOT counted).
  int get activeCount => _activeEpoch.length;

  int get concurrency => _concurrency;

  static int _clampConcurrency(int value) => value < 1
      ? defaultConcurrency
      : (value > maxConcurrency ? maxConcurrency : value);

  /// Applies a new concurrency limit defensively (invalid values clamp, they
  /// never disable the limit) and re-pumps.
  Future<void> updateConcurrency(int value) {
    final int clamped = _clampConcurrency(value);
    return _serialized(() async {
      if (_concurrency == clamped) return;
      _concurrency = clamped;
      onChanged?.call();
      await _pump();
    });
  }

  static Future<String> _defaultMediaDirectory() async {
    final Directory directory = await SpectaStorage().mediaDirectory();
    return directory.path;
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Future<T> _serialized<T>(Future<T> Function() action) {
    final Future<T> run = _mutex.then((_) => action());
    // Keep the chain alive even when an action fails: the error belongs to
    // the caller, not to the next serialized operation.
    _mutex = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  void _triggerPump() {
    unawaited(_serialized(() async {
      await _pump();
    }));
  }

  /// Test-only quiescence point: resolves when every manager operation
  /// scheduled so far (pumps, reconciliations, retries, settings restores)
  /// has finished — everything runs serialized, so awaiting the tail of the
  /// chain is deterministic and needs no real waiting. Pending backoff
  /// delays are NOT awaited here; tests drive those through the clock.
  @visibleForTesting
  Future<void> get debugIdle async {
    for (int i = 0; i < 100; i++) {
      final Future<void> current = _mutex;
      await current;
      // Drain the event queue so work appended by just-completed actions
      // (e.g. an attempt's reconciliation) is observed before exiting.
      await Future<void>.delayed(Duration.zero);
      if (identical(current, _mutex)) return;
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Loads persisted records, reconciles non-terminal state and resumes
  /// scheduling where currently safe. Safe to call once per manager instance.
  Future<void> initialize() {
    return _serialized(() async {
      if (_initialized || _disposed) return;
      _initialized = true;

      _eventsSubscription = engine.events.listen(
        _onEngineEvent,
        onError: (Object _) {/* engine stream errors are engine bugs; the
                              manager keeps running and reconciles results. */},
      );

      final List<DownloadRecord> records = await store.all();
      for (final DownloadRecord record in records) {
        if (_disposed) return;
        if (record.status != DownloadStatus.downloading) {
          // A paused record whose transfer survived under the engine is
          // STALE engine work: SPECTA says paused, so nothing may keep
          // transferring, and a later resume must enqueue fresh without
          // colliding with the old native task (the plugin has no
          // re-enqueue guard — a surviving task would duplicate work).
          // Best-effort cancel; SPECTA's paused state never depended on it.
          if (record.status == DownloadStatus.paused) {
            bool staleEngineWork = false;
            try {
              staleEngineWork = await engine.isTransferActive(record.id);
            } on Object {
              staleEngineWork = false;
            }
            if (staleEngineWork) {
              try {
                await engine.cancel(record.id);
              } on Object {/* best-effort cleanup */}
            }
          }
          continue;
        }

        // §31: a persisted `downloading` record is neither proof that a
        // transfer survived nor a candidate for a blind failure. Ask the
        // engine (persistence contract §7 seam).
        bool engineActive = false;
        try {
          engineActive = await engine.isTransferActive(record.id);
        } on Object {
          engineActive = false; // an engine that cannot answer is treated as
          // holding nothing — the queue re-attempts under the retry budget.
        }
        if (_disposed) return;
        if (engineActive) {
          // 2G-C reconciliation: the transfer survived under the engine
          // (WorkManager). ADOPT it — the engine re-attaches to the existing
          // native task (never re-enqueues: the SPECTA download id IS the
          // deterministic plugin task id) and the attempt result reconciles
          // through the same epoch-protected path as any other attempt.
          // The engine does NOT become the authority: a terminal engine
          // answer is applied through the usual completion gate / failure
          // translation, and the engine's own records stay bookkeeping.
          final int epoch = ++_epochCounter;
          _activeEpoch[record.id] = epoch;
          _lastPersistedBytes[record.id] = record.bytesDownloaded;
          _lastPersistedAt[record.id] = clock.now();
          unawaited(_runAdoptedAttempt(record, epoch));
          continue;
        }
        await _applyFailure(
          record,
          DownloadFailure(
            type: DownloadFailureType.interrupted,
            message: DownloadFailureType.interrupted.message,
          ),
          record.bytesDownloaded,
        );
      }
      // Resume scheduling where currently safe (§31): queued/paused records
      // left by the previous session now compete for slots under THIS
      // manager's policy.
      await _pump();
    });
  }

  /// Releases the manager. Active attempts are cancelled best-effort;
  /// persisted state is left for the next manager instance to reconcile.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventsSubscription?.cancel();
    _eventsSubscription = null;
    final List<String> active = _activeEpoch.keys.toList(growable: false);
    _activeEpoch.clear();
    for (final String id in active) {
      try {
        await engine.cancel(id);
      } on Object {/* best-effort: the engine owns its own cleanup */}
    }
    _liveProgress.clear();
    _lastPersistedBytes.clear();
    _lastPersistedAt.clear();
  }

  // ---------------------------------------------------------------------------
  // Queue operations
  // ---------------------------------------------------------------------------

  /// Enqueues a download request with documented duplicate semantics.
  Future<EnqueueResult> enqueue(DownloadRequest request) async {
    final EnqueueResult result = await _serialized(() async {
      final DownloadRecord? existing = await store.recordFor(request.id);
      if (existing != null) {
        switch (existing.status) {
          case DownloadStatus.queued:
            return EnqueueResult(
                record: existing, action: DownloadEnqueueAction.alreadyQueued);
          case DownloadStatus.downloading:
            return EnqueueResult(
                record: existing,
                action: DownloadEnqueueAction.alreadyDownloading);
          case DownloadStatus.paused:
            return EnqueueResult(
                record: existing, action: DownloadEnqueueAction.alreadyPaused);
          case DownloadStatus.completed:
            return EnqueueResult(
                record: existing,
                action: DownloadEnqueueAction.alreadyCompleted);
          case DownloadStatus.failed:
          case DownloadStatus.cancelled:
            // Explicit re-request of a dead download = a new run: the
            // machine allows failed→queued and cancelled→queued, and the
            // attempt budget resets deliberately (user-initiated).
            final DownloadRecord requeued = existing.copyWith(
              status: DownloadStatus.queued,
              attempt: 0,
              failure: null,
              waitReason: null,
              updatedAt: clock.now(),
            );
            await _persist(requeued);
            // A deliberate re-request is user-initiated and carries fresh
            // resolution inputs: the previous run's source failure no longer
            // constrains resolution.
            _lastSourceFailure.remove(request.id);
            // The re-request carries the user's FRESH resolution inputs; the
            // next attempt must consume them, not the stale pool captured
            // for the dead run (or nothing at all when the first enqueue
            // never started an attempt, e.g. unsupportedSource).
            _sourceResolver.rememberPool(request.id, request.pool);
            return EnqueueResult(
              record: requeued,
              action: existing.status == DownloadStatus.failed
                  ? DownloadEnqueueAction.requeuedFailed
                  : DownloadEnqueueAction.requeuedCancelled,
            );
        }
      }

      // New identity: plan the destination and classify the pool honestly
      // BEFORE any engine exists in the story. V1 downloads direct files
      // (MP4) only; the ranking order among MP4 candidates is SPECTA's own —
      // the manager consumes it, never re-ranks.
      final String directory = await _mediaDirectory();
      final String fileName =
          '${downloadFileStem(request.id, request.title)}.mp4';
      final String filePath = p.join(directory, fileName);

      final RankedSource? candidate = _pickDownloadable(request.pool);
      if (candidate == null) {
        final DownloadRecord failed = DownloadRecord(
          id: request.id,
          mediaKey: request.mediaKey,
          mediaType: request.mediaType,
          title: request.title,
          subtitleLine: request.subtitleLine,
          seasonNumber: request.seasonNumber,
          episodeNumber: request.episodeNumber,
          status: DownloadStatus.failed,
          bytesDownloaded: 0,
          totalBytes: null,
          filePath: filePath,
          attempt: 0,
          failure: DownloadFailure(
            type: DownloadFailureType.unsupportedSource,
            message: DownloadFailureType.unsupportedSource.message,
          ),
          createdAt: clock.now(),
          updatedAt: clock.now(),
        );
        await _persist(failed);
        return EnqueueResult(
            record: failed, action: DownloadEnqueueAction.createdFailed);
      }

      final DownloadRecord record = DownloadRecord(
        id: request.id,
        mediaKey: request.mediaKey,
        mediaType: request.mediaType,
        title: request.title,
        subtitleLine: request.subtitleLine,
        seasonNumber: request.seasonNumber,
        episodeNumber: request.episodeNumber,
        status: DownloadStatus.queued,
        bytesDownloaded: 0,
        totalBytes: null,
        filePath: filePath,
        sourceExtensionId: candidate.extensionId,
        sourceReference: candidate.reference,
        sourceLabel: candidate.source.label,
        attempt: 0,
        createdAt: clock.now(),
        updatedAt: clock.now(),
      );
      await _persist(record);
      _sourceResolver.rememberPool(request.id, request.pool);
      return EnqueueResult(
          record: record, action: DownloadEnqueueAction.created);
    });
    _triggerPump();
    return result;
  }

  /// Pauses an active download: the persisted state moves first (the user's
  /// intent is SPECTA state), then the engine is asked to stop transferring.
  /// The engine's `paused` result is reconciled idempotently afterwards.
  Future<bool> pause(String id) async {
    final bool requested = await _serialized(() async {
      final DownloadRecord? record = await store.recordFor(id);
      if (record == null || record.status != DownloadStatus.downloading) {
        return false; // machine: only downloading→paused
      }
      final int bytes =
          _maxBytes(record.bytesDownloaded, _liveProgress[id]?.bytesOnDisk);
      await _persist(record.copyWith(
        status: DownloadStatus.paused,
        bytesDownloaded: bytes,
        waitReason: null,
        updatedAt: clock.now(),
      ));
      return true;
    });
    if (requested) {
      try {
        await engine.pause(id);
      } on Object {
        // The engine owns its mechanics; the persisted paused state stands.
      }
    }
    return requested;
  }

  /// Resumes a paused download. When SPECTA's concurrency policy has a free
  /// slot the download returns to `downloading` immediately; otherwise it is
  /// routed through the queue (`paused → queued`, an explicit user resume —
  /// machine-supported) and starts when a slot frees.
  Future<bool> resume(String id) {
    return _serialized(() async {
      final DownloadRecord? record = await store.recordFor(id);
      if (record == null || record.status != DownloadStatus.paused) {
        return false;
      }
      if (_activeEpoch.length < _concurrency) {
        // Resume is NOT a failure retry: the attempt budget is unchanged.
        final DownloadRecord resumed = record.copyWith(
          status: DownloadStatus.downloading,
          waitReason: null,
          updatedAt: clock.now(),
        );
        await _persist(resumed);
        _startAttempt(resumed);
        return true;
      }
      await _persist(record.copyWith(
        status: DownloadStatus.queued,
        waitReason: DownloadWaitReason.waitingForSlot,
        updatedAt: clock.now(),
      ));
      return true;
    }).then((bool resumed) {
      _triggerPump();
      return resumed;
    });
  }

  /// Cancels a download. Idempotent; terminal records are protected (a
  /// cancelled or completed download cannot be "cancelled" into a new
  /// state). The engine is told to stop transferring only when an attempt is
  /// actually running — a queued job has nothing to cancel.
  Future<bool> cancel(String id) async {
    final (bool requested, bool hadAttempt) = await _serialized(() async {
      final DownloadRecord? record = await store.recordFor(id);
      if (record == null) return (false, false); // idempotent
      if (record.status == DownloadStatus.cancelled ||
          record.status == DownloadStatus.completed) {
        return (false, false); // terminal protection
      }
      if (!DownloadStateMachine.canTransition(
          record.status, DownloadStatus.cancelled)) {
        return (false, false);
      }
      final bool hadAttempt = _activeEpoch.containsKey(id);
      final int bytes =
          _maxBytes(record.bytesDownloaded, _liveProgress[id]?.bytesOnDisk);
      await _persist(record.copyWith(
        status: DownloadStatus.cancelled,
        bytesDownloaded: bytes,
        waitReason: null,
        updatedAt: clock.now(),
      ));
      // The generation dies here: any result from this attempt is stale.
      _activeEpoch.remove(id);
      _liveProgress.remove(id);
      return (true, hadAttempt);
    });
    if (requested) {
      if (hadAttempt) {
        try {
          await engine.cancel(id);
        } on Object {/* best-effort: the record is already cancelled */}
      }
      onChanged?.call();
      _triggerPump(); // the slot is free — the queue advances
    }
    return requested;
  }

  /// Explicit user retry: failed/cancelled → queued as a NEW run (attempt
  /// budget resets deliberately). Not an automatic path.
  Future<bool> retry(String id) async {
    final bool requested = await _serialized(() async {
      final DownloadRecord? record = await store.recordFor(id);
      if (record == null) return false;
      if (record.status != DownloadStatus.failed &&
          record.status != DownloadStatus.cancelled) {
        return false;
      }
      if (!DownloadStateMachine.canTransition(
          record.status, DownloadStatus.queued)) {
        return false;
      }
      await _persist(record.copyWith(
        status: DownloadStatus.queued,
        attempt: 0,
        failure: null,
        waitReason: null,
        updatedAt: clock.now(),
      ));
      // 2G-C §25 (stale-pool protection): a manual retry of a FAILED
      // download keeps the previous run's failure in memory so the resolver
      // can re-resolve FRESHLY when that failure was source-invalidating —
      // the captured pool must not serve the same expired URL again. (An
      // enqueue-based re-request supersedes this with the user's fresh pool
      // and clears the memory explicitly.)
      return true;
    });
    _triggerPump();
    return requested;
  }

  /// Removes the record entirely (never the files — the future storage layer
  /// owns file cleanup). Idempotent: removing an absent record is an honest
  /// no-op returning false. An active attempt is cancelled best-effort so no
  /// orphaned transfer keeps running.
  Future<bool> remove(String id) async {
    final (bool existed, bool wasActive) = await _serialized(
        () async {
      final DownloadRecord? record = await store.recordFor(id);
      _activeEpoch.remove(id);
      _liveProgress.remove(id);
      _lastPersistedBytes.remove(id);
      _lastPersistedAt.remove(id);
      _lastSourceFailure.remove(id);
      _sourceResolver.forgetPool(id);
      if (record == null) return (false, false); // idempotent
      await store.remove(id);
      onChanged?.call();
      return (
        true,
        record.status == DownloadStatus.downloading,
      );
    });
    if (existed && wasActive) {
      try {
        await engine.cancel(id);
      } on Object {/* best-effort */}
    }
    _triggerPump(); // removal freed a slot or removed a blocked queued item
    return existed;
  }

  // ---------------------------------------------------------------------------
  // Queue pump
  // ---------------------------------------------------------------------------

  Future<void> _pump() async {
    if (_disposed) return;
    while (_activeEpoch.length < _concurrency) {
      final List<DownloadRecord> all = await store.all(); // FIFO by creation
      final NetworkPolicyVerdict verdict =
          await _evaluateNetworkPolicyOnce();
      DownloadRecord? next;
      for (final DownloadRecord record in all) {
        if (record.status != DownloadStatus.queued) continue;
        if (_activeEpoch.containsKey(record.id)) continue;
        if (!verdict.isAllowed) {
          await _setWaitReason(record, verdict.waitReason);
          continue; // policy blocks every queued job alike
        }
        if (!await _storageAllows(record)) {
          await _setWaitReason(
              record, DownloadWaitReason.insufficientStorage);
          continue; // item-specific: try the next one
        }
        next = record;
        break;
      }
      if (next == null) return;

      // Persist BEFORE the engine is involved (persistence contract §5):
      // a process death after this upsert leaves a `downloading` record the
      // next manager reconciles through the engine seam.
      final DownloadRecord starting = next.copyWith(
        status: DownloadStatus.downloading,
        attempt: next.attempt + 1,
        waitReason: null,
        updatedAt: clock.now(),
      );
      await _persist(starting);
      _startAttempt(starting);
    }

    // At capacity (or nothing eligible): every remaining queued download is
    // honestly "waiting in queue" — descriptive data, never a new state,
    // and a no-op for records that already carry the reason. Runs OUTSIDE
    // the scheduling loop so an at-capacity manager still answers.
    final NetworkPolicyVerdict verdict = await _evaluateNetworkPolicyOnce();
    if (activeCount >= concurrency && verdict.isAllowed) {
      final List<DownloadRecord> remaining = await store.all();
      for (final DownloadRecord record in remaining) {
        if (record.status != DownloadStatus.queued) continue;
        await _setWaitReason(record, DownloadWaitReason.waitingForSlot);
      }
    }
  }

  /// Registers the attempt generation and runs it to its terminal result.
  /// The engine call happens OUTSIDE the serialized section — attempts run
  /// for a long time and must not block scheduling.
  void _startAttempt(DownloadRecord starting) {
    final int epoch = ++_epochCounter;
    _activeEpoch[starting.id] = epoch;
    _lastPersistedBytes[starting.id] = starting.bytesDownloaded;
    _lastPersistedAt[starting.id] = clock.now();
    onChanged?.call();
    unawaited(_runAttempt(starting, epoch));
  }

  Future<void> _runAttempt(DownloadRecord starting, int epoch) async {
    DownloadAttemptResult result;
    try {
      // Recovery-aware resolution: the resolver receives the failure that
      // ended the previous attempt (if any). A source-classified failure
      // FORBIDS reusing any captured pool — the URL itself is suspect — so
      // the resolver must re-resolve through the source architecture (or
      // answer null and let the budget run out honestly). This is the
      // manager-owned recovery decision (2G-C §12/§13): never an unbounded
      // refresh loop, never an attempt-budget reset.
      final SourcePool? pool = await _sourceResolver.resolveSource(
        starting,
        lastFailure: _lastSourceFailure[starting.id],
      );
      _lastSourceFailure.remove(starting.id);
      final RankedSource? candidate =
          pool == null ? null : _pickDownloadable(pool);
      if (candidate == null) {
        final DownloadFailureType type = pool == null
            ? DownloadFailureType.sourcesExhausted
            : DownloadFailureType.unsupportedSource;
        result = DownloadAttemptResult.failed(
          DownloadFailure(type: type, message: type.message),
          starting.bytesDownloaded,
        );
      } else {
        result = await engine.start(DownloadAttemptInput(
          downloadId: starting.id,
          url: candidate.source.url,
          partPath: downloadPartPathFor(starting.filePath),
          resumeFrom: starting.bytesDownloaded,
          headers: candidate.source.headers ?? const <String, String>{},
        ));
      }
    } on Object catch (error) {
      // An engine must report problems as data; a throw is a contract
      // violation and becomes honest structured failure data.
      result = DownloadAttemptResult.failed(
        DownloadFailure(
          type: DownloadFailureType.engineFailure,
          message: DownloadFailureType.engineFailure.message,
          detail: '$error',
        ),
        starting.bytesDownloaded,
      );
    }
    await _serialized(() => _reconcileResult(starting.id, epoch, result));
  }

  /// Runs an ADOPTED attempt (restart reconciliation): the transfer survived
  /// under the engine and is already addressed by SPECTA identity — no
  /// source resolution, no new engine work. The result reconciles through
  /// the same epoch-protected path as a fresh attempt.
  Future<void> _runAdoptedAttempt(DownloadRecord record, int epoch) async {
    DownloadAttemptResult result;
    try {
      result = await engine.attach(record.id);
    } on Object catch (error) {
      result = DownloadAttemptResult.failed(
        DownloadFailure(
          type: DownloadFailureType.engineFailure,
          message: DownloadFailureType.engineFailure.message,
          detail: '$error',
        ),
        record.bytesDownloaded,
      );
    }
    await _serialized(() => _reconcileResult(record.id, epoch, result));
  }

  /// Applies an attempt's terminal result to CURRENT persisted state, with
  /// stale-result protection at two layers: the attempt generation must
  /// still be active, and the persisted record must still be in the state
  /// the result claims to be reconciling from.
  ///
  /// The attempt ALWAYS finishes once its terminal result arrives — even when
  /// the state it would apply is stale (paused/cancelled/removed meanwhile) —
  /// otherwise a dead attempt would leak a concurrency slot forever.
  Future<void> _reconcileResult(
      String id, int epoch, DownloadAttemptResult result) async {
    if (_disposed) return;
    if (_activeEpoch[id] != epoch) return; // stale attempt result
    _finishAttempt(id); // the engine attempt is over; free the slot
    final DownloadRecord? current = await store.recordFor(id);
    if (current == null) return; // removed while the attempt ran
    switch (result.kind) {
      case DownloadAttemptOutcomeKind.completed:
        if (current.status != DownloadStatus.downloading) return; // stale
        // Completion gate (2G-C §40): the engine's word alone does not make
        // media. The transfer is verified on disk and the final rename is
        // performed by the finalizer; a gate failure becomes an honest
        // failure through the retry policy — never a masked success.
        final int bytes = _maxBytes(
            current.bytesDownloaded,
            _maxBytes(result.bytesOnDisk, _liveProgress[id]?.bytesOnDisk));
        final int verifiedBytes;
        try {
          verifiedBytes = await _completionFinalizer.finalize(current, bytes);
        } on DownloadFailure catch (gateFailure) {
          _lastSourceFailure[id] = gateFailure;
          await _applyFailure(current, gateFailure, bytes);
          return;
        }
        final int? total = result.totalBytes ??
            _liveProgress[id]?.totalBytes ??
            current.totalBytes;
        await _persist(current.copyWith(
          status: DownloadStatus.completed,
          bytesDownloaded: verifiedBytes,
          totalBytes: total,
          completedAt: clock.now(),
          updatedAt: clock.now(),
          waitReason: null,
        ));
        await _pump();
      case DownloadAttemptOutcomeKind.paused:
        // The manager already persisted `paused` before asking the engine;
        // the result only settles the final byte count (idempotent). A
        // `paused` result against a resumed (downloading) record is stale.
        if (current.status != DownloadStatus.paused) return;
        final int bytes = _maxBytes(
            current.bytesDownloaded,
            _maxBytes(result.bytesOnDisk, _liveProgress[id]?.bytesOnDisk));
        if (bytes > current.bytesDownloaded) {
          await _persist(current.copyWith(
            bytesDownloaded: bytes,
            updatedAt: clock.now(),
          ));
        }
        // The slot is genuinely free now that the engine has settled — let
        // the queue use it.
        await _pump();
      case DownloadAttemptOutcomeKind.cancelled:
        if (current.status == DownloadStatus.downloading) {
          // Engine-initiated cancellation (not the manager's path in 2G-B)
          // reconciles honestly into the cancelled state.
          await _persist(current.copyWith(
            status: DownloadStatus.cancelled,
            bytesDownloaded: _maxBytes(current.bytesDownloaded,
                _maxBytes(result.bytesOnDisk, _liveProgress[id]?.bytesOnDisk)),
            updatedAt: clock.now(),
            waitReason: null,
          ));
        }
        await _pump();
      case DownloadAttemptOutcomeKind.failed:
        if (current.status != DownloadStatus.downloading) return; // stale
        final DownloadFailure failure = result.failure ??
            DownloadFailure(
              type: DownloadFailureType.engineFailure,
              message: DownloadFailureType.engineFailure.message,
            );
        // Remember WHY this attempt ended: the next attempt's resolver
        // receives it, so a source-classified failure triggers fresh
        // resolution instead of a stale captured pool (2G-C §25). Cleared
        // when the next attempt consumes it, or when the record is removed.
        _lastSourceFailure[id] = failure;
        await _applyFailure(current, failure, result.bytesOnDisk);
    }
  }

  /// Persists the failure and runs the bounded retry policy: retryable
  /// failures with budget left re-queue after backoff; everything else stays
  /// honestly failed until the user acts.
  Future<void> _applyFailure(
      DownloadRecord current, DownloadFailure failure, int engineBytes) async {
    final int bytes = _maxBytes(
        current.bytesDownloaded,
        _maxBytes(engineBytes, _liveProgress[current.id]?.bytesOnDisk));
    final DownloadRecord failedRecord = current.copyWith(
      status: DownloadStatus.failed,
      failure: failure,
      bytesDownloaded: bytes,
      updatedAt: clock.now(),
      waitReason: null,
    );
    await _persist(failedRecord);

    if (retryPolicy.shouldAutoRetry(failure, failedRecord.attempt)) {
      unawaited(_scheduleAutoRetry(
          current.id, retryPolicy.backoffAfter(failedRecord.attempt)));
    }
    await _pump();
  }

  /// Backoff then re-queue — only if the record is STILL failed (the user
  /// may have cancelled, retried manually or removed it meanwhile). The
  /// auto path keeps the attempt count (budget), unlike a manual retry.
  Future<void> _scheduleAutoRetry(String id, Duration backoff) async {
    try {
      await clock.delay(backoff);
    } on Object {
      return; // clock/manager gone
    }
    if (_disposed) return;
    await _serialized(() async {
      final DownloadRecord? record = await store.recordFor(id);
      if (record == null || record.status != DownloadStatus.failed) return;
      await _persist(record.copyWith(
        status: DownloadStatus.queued,
        waitReason: null,
        failure: null,
        updatedAt: clock.now(),
      ));
    });
    _triggerPump();
  }

  // ---------------------------------------------------------------------------
  // Eligibility (network policy + storage seam)
  // ---------------------------------------------------------------------------

  Future<NetworkPolicyVerdict> _evaluateNetworkPolicyOnce() async {
    NetworkAccess? access;
    try {
      access = await environment.networkAccess();
    } on Object {
      access = null; // a failing probe is an unknown network — conservative
    }
    return evaluateNetworkPolicy(networkPolicy, access ?? NetworkAccess.unknown);
  }

  /// Storage pre-flight seam: skip the comparison when either side is
  /// unknown (never fabricate a capacity verdict). No native channel is
  /// implemented in this phase — `DeviceEnvironment` answers null.
  Future<bool> _storageAllows(DownloadRecord record) async {
    final int? total = record.totalBytes;
    if (total == null || total <= 0) return true;
    int? free;
    try {
      free = await environment.freeBytes(record.filePath);
    } on Object {
      free = null;
    }
    if (free == null) return true;
    return free >= (total - record.bytesDownloaded);
  }

  Future<void> _setWaitReason(
      DownloadRecord record, DownloadWaitReason? reason) async {
    if (record.waitReason == reason) return;
    await _persist(record.copyWith(
      waitReason: reason,
      updatedAt: clock.now(),
    ));
  }

  // ---------------------------------------------------------------------------
  // Progress (transient events → coalesced persistence)
  // ---------------------------------------------------------------------------

  void _onEngineEvent(DownloadEngineEvent event) {
    if (event is! DownloadEngineProgress) return;
    if (_disposed) return;
    final DownloadProgress progress = DownloadProgress(
      bytesOnDisk: event.bytesOnDisk,
      totalBytes: event.totalBytes,
    );
    _liveProgress[event.downloadId] = progress;
    onChanged?.call();

    final int persisted = _lastPersistedBytes[event.downloadId] ?? 0;
    final DateTime? persistedAt = _lastPersistedAt[event.downloadId];
    if (!progressPolicy.shouldPersist(
      lastPersistedBytes: persisted,
      currentBytes: event.bytesOnDisk,
      lastPersistedAt: persistedAt,
      now: clock.now(),
    )) {
      return;
    }
    unawaited(_serialized(() async {
      if (_disposed) return;
      final DownloadRecord? record = await store.recordFor(event.downloadId);
      if (record == null || record.status != DownloadStatus.downloading) {
        return; // transient ticks never resurrect or mutate other states
      }
      await _persist(record.copyWith(
        bytesDownloaded:
            _maxBytes(record.bytesDownloaded, event.bytesOnDisk),
        totalBytes: event.totalBytes ?? record.totalBytes,
        updatedAt: clock.now(),
      ));
    }));
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// The best direct-file (MP4) candidate in SPECTA's ranking order — the
  /// manager consumes the existing ranking; it never re-ranks.
  RankedSource? _pickDownloadable(SourcePool pool) {
    for (final RankedSource ranked in pool.ranked) {
      if (ranked.source.type == SourceType.mp4) return ranked;
    }
    return null;
  }

  Future<void> _persist(DownloadRecord record) async {
    await store.upsert(record);
    _lastPersistedBytes[record.id] = record.bytesDownloaded;
    _lastPersistedAt[record.id] = clock.now();
    onChanged?.call();
  }

  void _finishAttempt(String id) {
    _activeEpoch.remove(id);
    _lastPersistedBytes.remove(id);
    _lastPersistedAt.remove(id);
    onChanged?.call();
  }

  static int _maxBytes(int a, int? b) => b == null ? a : math.max(a, b);
}
