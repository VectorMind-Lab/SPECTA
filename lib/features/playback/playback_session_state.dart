import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/specta_failure.dart';
import '../../core/extensions/contract/extension_source.dart';
import '../../core/extensions/contract/result_models.dart';
import '../../core/library/library_providers.dart';
import '../../core/playback/media_kit_engine.dart';
import '../../core/playback/playback_engine.dart';
import '../../core/playback/playback_progress_sink.dart';
import '../../core/sources/source_manager.dart';
import '../../core/sources/source_pool.dart';
import 'playback_models.dart';

/// A playback request: the ordered candidate list SPECTA decided on (from a
/// 2D [SourcePool]) plus display identity.
final class PlaybackRequest {
  const PlaybackRequest({
    required this.candidates,
    this.playbackKey,
    this.title,
    this.subtitle,
    this.mediaKey,
    this.mediaType,
    this.seasonNumber,
    this.episodeNumber,
  });

  /// Opens playback from a resolved 2D pool: its selection first, then its
  /// fallbacks — SPECTA's order, never re-ranked here.
  factory PlaybackRequest.fromPool(
    SourcePool pool, {
    String? playbackKey,
    String? title,
    String? subtitle,
    String? mediaKey,
    MediaType? mediaType,
    int? seasonNumber,
    int? episodeNumber,
  }) =>
      PlaybackRequest(
        candidates: pool.ranked,
        playbackKey: playbackKey,
        title: title,
        subtitle: subtitle,
        mediaKey: mediaKey,
        mediaType: mediaType,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      );

  /// Opens a direct candidate list (already-ordered RankedSources). Used for
  /// direct opens and by tests.
  const PlaybackRequest.direct(
    List<RankedSource> ranked, {
    this.playbackKey,
    this.title,
    this.subtitle,
    this.mediaKey,
    this.mediaType,
    this.seasonNumber,
    this.episodeNumber,
  }) : candidates = ranked;

  /// Ordered best-first. Every entry carries its provenance.
  final List<RankedSource> candidates;

  /// Progress-reporting identity (persisted in 2F). Null disables progress
  /// reporting for the session.
  final String? playbackKey;

  /// Display title. Never a provider URL or extension label.
  final String? title;

  /// Optional second display line (e.g. `Season 1 · Episode 2`).
  final String? subtitle;

  /// The parent work's canonical metadata key (progress identity). Defaults
  /// to [playbackKey] when omitted.
  final String? mediaKey;

  /// Movie or series — carried so persistence never has to guess.
  final MediaType? mediaType;

  /// Series episode numbers, preserved so a completed Episode 2 can never
  /// update Episode 1.
  final int? seasonNumber;
  final int? episodeNumber;
}

/// How long one candidate may take to reach a playable state.
final Provider<Duration> playbackOpenTimeoutProvider =
    Provider<Duration>((Ref ref) => const Duration(seconds: 45));

/// How long a mid-playback stall may last before the candidate is failed.
final Provider<Duration> playbackStallTimeoutProvider =
    Provider<Duration>((Ref ref) => const Duration(seconds: 30));

/// Creates the real engine (MediaKit). Tests override this provider with a
/// fake factory for deterministic, engine-free playback tests.
final Provider<PlaybackEngine Function()> playbackEngineFactoryProvider =
    Provider<PlaybackEngine Function()>(
  (Ref ref) => MediaKitPlaybackEngine.new,
);

/// The progress sink binding.
///
/// Phase 2F binds the session's honest progress reports to persistent storage
/// through [libraryStoreProvider]; overwriting the sink is the ONLY change the
/// player needed. Tests override this with an in-memory sink (or a fake).
final Provider<PlaybackProgressSink> playbackProgressSinkProvider =
    Provider<PlaybackProgressSink>((Ref ref) {
  return PersistentPlaybackProgressSink(
    ref.watch(libraryStoreProvider),
    onChanged: () => ref.read(libraryRevisionProvider.notifier).bump(),
  );
});

/// Drives one playback session over the engine seam.
///
/// Architecture (2E):
/// - The player is a CONSUMER of the source manager: it receives the ordered
///   candidates (selected + fallbacks) and never re-resolves, re-ranks or
///   re-validates them.
/// - Ordered fallback: on candidate failure the session advances to the next
///   candidate; a single failed source never becomes "no sources available"
///   while ordered alternatives remain.
/// - Refresh: a candidate whose source may be stale gets at most ONE refresh
///   attempt per session through the existing 2D/Phase 1 refresh contract;
///   refresh failure falls through to the next candidate. The refresh
///   contract itself is not duplicated here.
/// - Races: every state write is generation-guarded (stale opens, stale
///   fallbacks and post-disposal writes are rejected).
/// - Errors: engine problems become [PlaybackFailure] data with provenance
///   preserved; nothing throws into the UI.
class PlaybackSessionNotifier extends Notifier<PlaybackSnapshot> {
  static const int _maxFailureRecords = 32;

  int _generation = 0;
  bool _disposed = false;

  PlaybackEngine? _engine;
  StreamSubscription<PlaybackEngineEvent>? _engineSub;

  List<PlaybackCandidate> _candidates = const <PlaybackCandidate>[];
  int _index = 0;

  bool _awaitingTerminal = false;
  bool _refreshedOnce = false;
  DateTime? _openStartedAt;

  Timer? _openTimer;
  Timer? _stallTimer;
  Timer? _tickTimer;
  Duration _elapsedWatch = Duration.zero;

  final List<PlaybackAttemptRecord> _records = <PlaybackAttemptRecord>[];

  @override
  PlaybackSnapshot build() {
    ref.onDispose(_handleDisposal);
    return PlaybackSnapshot(status: PlaybackStatus.idle, generation: 0);
  }

  /// Descriptive playback observations recorded this process lifetime
  /// (honest, measured; no invented telemetry). Bounded.
  List<PlaybackAttemptRecord> get observationLog =>
      List<PlaybackAttemptRecord>.unmodifiable(_records);

  // ---------------------------------------------------------------------------
  // Session lifecycle
  // ---------------------------------------------------------------------------

  /// Starts (or switches) playback for [request].
  Future<void> open(PlaybackRequest request) async {
    if (_disposed) return;
    final int gen = ++_generation;

    // Abort whatever the engine is doing; late events of an abandoned
    // candidate are suppressed by the engine's stop contract.
    _cancelTimers();
    _awaitingTerminal = false;
    await _engine?.stop();

    if (request.candidates.isEmpty) {
      // Honest terminal: an open with no candidates is a failed session.
      _candidates = const <PlaybackCandidate>[];
      _index = 0;
      _progressKey = request.playbackKey;
      _title = request.title;
      _subtitleLine = request.subtitle;
      _applyIdentity(request);
      _refreshedOnce = false;
      _elapsedWatch = Duration.zero;
      _failures.clear();
      state = PlaybackSnapshot(
        status: PlaybackStatus.failed,
        generation: gen,
        title: _title,
        subtitle: _subtitleLine,
        candidates: const <PlaybackCandidate>[],
        attemptedCount: 0,
        failure: PlaybackFailure(
          type: PlaybackFailureType.sourcesExhausted,
          message: 'No sources are available for this item.',
        ),
      );
      return;
    }

    _candidates = <PlaybackCandidate>[
      for (int i = 0; i < request.candidates.length; i++)
        PlaybackCandidate(ranked: request.candidates[i], attempt: i),
    ];
    _index = 0;
    _refreshedOnce = false;
    _elapsedWatch = Duration.zero;
    _playedThisCandidate = false;
    _progressKey = request.playbackKey;
    _title = request.title;
    _subtitleLine = request.subtitle;
    _applyIdentity(request);
    _failures.clear();

    final bool wasActive = switch (state.status) {
      PlaybackStatus.playing ||
      PlaybackStatus.paused ||
      PlaybackStatus.buffering =>
        true,
      _ => false,
    };

    state = _snapshot(
      status: wasActive
          ? PlaybackStatus.switchingSource
          : PlaybackStatus.loading,
      gen: gen,
      title: request.title,
      subtitleLine: request.subtitle,
      clearCurrent: true,
      clearFailure: true,
    );

    await _ensureEngine();
    _attemptCurrent(gen);
  }

  /// Leaves playback: aborts the engine and returns to idle. The engine is
  /// disposed; the next open creates a fresh one.
  Future<void> leave() async {
    if (_disposed) return;
    final int gen = ++_generation;
    _cancelTimers();
    _awaitingTerminal = false;
    _flushProgress(completed: false);
    final PlaybackEngine? engine = _engine;
    _engine = null;
    await _engineSub?.cancel();
    _engineSub = null;
    state = PlaybackSnapshot(status: PlaybackStatus.idle, generation: gen);
    await engine?.stop();
    await engine?.dispose();
  }

  // ---------------------------------------------------------------------------
  // Player controls
  // ---------------------------------------------------------------------------

  /// Toggles play/pause of the current candidate.
  Future<void> togglePlay() async {
    final PlaybackEngine? engine = _engine;
    if (engine == null || _disposed) return;
    if (state.status == PlaybackStatus.playing) {
      await engine.pause();
    } else if (state.status == PlaybackStatus.paused) {
      await engine.play();
    }
  }

  /// Seeks the current candidate.
  Future<void> seek(Duration position) async {
    if (_disposed) return;
    if (state.status != PlaybackStatus.playing &&
        state.status != PlaybackStatus.paused &&
        state.status != PlaybackStatus.buffering) {
      return;
    }
    await _engine?.seek(position);
  }

  /// Applies a playback rate multiplier.
  Future<void> setRate(double rate) async {
    if (_disposed) return;
    await _engine?.setRate(rate);
  }

  /// Applies a volume multiplier (0.0 .. 1.0).
  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    await _engine?.setVolume(volume);
  }

  /// Selects an external subtitle from the candidate's own list, or null to
  /// turn subtitles off.
  Future<void> selectSubtitle(SubtitleTrack? track) async {
    if (_disposed) return;
    await _engine?.setSubtitle(track);
    // Explicit null clears the selection (see [PlaybackSnapshot.copyWith]).
    state = state.copyWith(selectedSubtitle: track);
  }

  /// Restarts the SAME ordered candidate list from its beginning after a
  /// terminal state (completed / exhausted), preserving the session identity
  /// (title, subtitle, progress key). Never a new resolution, never a new
  /// ranking — SPECTA's original order is replayed.
  Future<void> retry() async {
    if (_disposed || _candidates.isEmpty) return;
    await open(
      PlaybackRequest.direct(
        <RankedSource>[
          for (final PlaybackCandidate c in _candidates) c.ranked,
        ],
        playbackKey: _progressKey,
        title: _title,
        subtitle: _subtitleLine,
        mediaKey: _mediaKey,
        mediaType: _mediaType,
        seasonNumber: _seasonNumber,
        episodeNumber: _episodeNumber,
      ),
    );
  }

  /// Records the persistence identity a request carried (2F).
  void _applyIdentity(PlaybackRequest request) {
    _mediaKey = request.mediaKey ?? request.playbackKey;
    _mediaType = request.mediaType;
    _seasonNumber = request.seasonNumber;
    _episodeNumber = request.episodeNumber;
  }

  // ---------------------------------------------------------------------------
  // Engine attempts / fallback / refresh
  // ---------------------------------------------------------------------------

  Future<void> _ensureEngine() async {
    if (_engine != null) return;
    final PlaybackEngine engine = ref.read(playbackEngineFactoryProvider)();
    _engine = engine;
    _engineSub = engine.events.listen(_onEngineEvent);
  }

  void _attemptCurrent(int gen) {
    if (_disposed || gen != _generation) return;
    final PlaybackCandidate candidate = _candidates[_index];

    _awaitingTerminal = true;
    _openStartedAt = DateTime.now();
    _playedThisCandidate = false;

    state = _copyCurrent(
      status: candidate.attempt == 0
          ? PlaybackStatus.loading
          : PlaybackStatus.switchingSource,
      current: candidate,
      attemptedCount: _index + 1,
      availableSubtitles: candidate.source.subtitles ?? const <SubtitleTrack>[],
      selectedSubtitle: null,
      position: Duration.zero,
      duration: Duration.zero,
      buffered: Duration.zero,
    );

    _startOpenTimer(gen);

    // The open is deferred to a microtask: fallbacks start INSIDE the
    // engine's event delivery (a failure event triggers the next attempt).
    // A synchronous open there would re-enter the engine's broadcast stream
    // controller while it is still firing ("Cannot fire new event") — on
    // the fake engine and on MediaKit alike. Scheduling after the current
    // turn keeps event delivery and engine opens strictly separated.
    scheduleMicrotask(() {
      if (_disposed || gen != _generation) return;
      () async {
        try {
          await _engine?.open(candidate.source);
        } on Object catch (e) {
          // Engine contract violation containment: treat as a candidate
          // failure, never an escape into the UI.
          _onCandidateFailed(
            gen,
            PlaybackFailure(
              type: PlaybackFailureType.engineUnavailable,
              message: 'The player engine could not open this source.',
              engineDetail: e.toString(),
            ),
          );
        }
      }();
    });
  }

  void _startOpenTimer(int gen) {
    _openTimer?.cancel();
    final Duration timeout = ref.read(playbackOpenTimeoutProvider);
    _openTimer = Timer(timeout, () {
      if (_disposed || gen != _generation || !_awaitingTerminal) return;
      _awaitingTerminal = false;
      _onCandidateFailed(
        gen,
        PlaybackFailure(
          type: PlaybackFailureType.bufferingFailure,
          message: 'This source took too long to start playing.',
        ),
      );
    });
  }

  void _startStallTimer(int gen) {
    _stallTimer?.cancel();
    final Duration timeout = ref.read(playbackStallTimeoutProvider);
    _stallTimer = Timer(timeout, () {
      if (_disposed || gen != _generation) return;
      _onCandidateFailed(
        gen,
        PlaybackFailure(
          type: PlaybackFailureType.bufferingFailure,
          message: 'The stream stalled for too long.',
        ),
      );
    });
  }

  void _onCandidateFailed(int gen, PlaybackFailure failure) {
    if (_disposed || gen != _generation) return;
    // A finished session cannot be failed: a stray late engine event must
    // never restart playback on a fallback behind the user's back.
    if (state.isTerminal) return;
    final PlaybackCandidate? current = _safeCurrent;
    if (current == null) return; // no attempt in flight — nothing to fail
    _openTimer?.cancel();
    _stallTimer?.cancel();
    _tickTimer?.cancel();
    _flushProgress(completed: false);

    final PlaybackCandidate candidate = current;
    _record(
      PlaybackAttemptRecord(
        extensionId: candidate.extensionId,
        reference: candidate.reference,
        url: candidate.source.url,
        typeCode: candidate.source.type.code,
        quality: candidate.source.quality,
        attempt: candidate.attempt,
        outcome: failure.type.code,
        failure: failure,
        timeToPlayable: _playedThisCandidate ? _timeSinceOpen : null,
        recordedAt: DateTime.now().toUtc(),
      ),
    );

    _failures.add(
      PlaybackAttempt(
        candidate: candidate,
        kind: PlaybackAttemptOutcomeKind.failed,
        failure: failure,
      ),
    );
    if (_failures.length > _maxFailureRecords) {
      _failures.removeAt(0);
    }

    _advanceAfterFailure(gen);
  }

  /// Ordered fallback: refresh (once, when applicable) then the next
  /// candidate; exhaustion becomes the honest terminal failure.
  Future<void> _advanceAfterFailure(int gen) async {
    if (_disposed || gen != _generation) return;

    final PlaybackCandidate candidate = _candidates[_index];

    // One refresh attempt per session, only for candidates whose source type
    // plausibly goes stale (HLS playlists), through the EXISTING 2D contract.
    if (!_refreshedOnce && _mayRequireRefresh(candidate)) {
      _refreshedOnce = true;
      state = _copyCurrent(status: PlaybackStatus.switchingSource);
      ExtensionSource? refreshed;
      try {
        refreshed = await ref.read(sourceServiceProvider).refresh(
              extensionId: candidate.extensionId,
              reference: candidate.reference,
            );
      } on Object {
        // Refresh seam containment: failure falls through to the next
        // candidate (the contract represents unavailability as null; an
        // escaping error is contained here and treated the same way).
        refreshed = null;
      }
      if (_disposed || gen != _generation) return;
      if (refreshed != null) {
        // Retry the SAME candidate with the refreshed source.
        _candidates[_index] = PlaybackCandidate(
          ranked: RankedSource(
            source: refreshed,
            extensionId: candidate.extensionId,
            reference: candidate.reference,
            score: candidate.ranked.score,
          ),
          attempt: candidate.attempt,
        );
        _attemptCurrent(gen);
        return;
      }
    }

    if (_index + 1 < _candidates.length) {
      _index++;
      _playedThisCandidate = false;
      _attemptCurrent(gen);
      return;
    }

    // Exhausted: every usable candidate failed.
    _awaitingTerminal = false;
    state = _snapshot(
      status: PlaybackStatus.failed,
      gen: gen,
      failure: PlaybackFailure(
        type: PlaybackFailureType.sourcesExhausted,
        message: _refreshedOnce
            ? 'None of the available sources could be played, and no '
                'refreshed source was available.'
            : 'None of the available sources could be played.',
      ),
    );
  }

  /// A candidate whose source type plausibly goes stale. HLS playlists are
  /// the documented 2E heuristic; MP4 URLs are static files.
  static bool _mayRequireRefresh(PlaybackCandidate candidate) =>
      candidate.source.type == SourceType.hls;

  // ---------------------------------------------------------------------------
  // Engine event routing
  // ---------------------------------------------------------------------------

  void _onEngineEvent(PlaybackEngineEvent event) {
    if (_disposed) return;
    final int gen = _generation;

    switch (event) {
      case EnginePlaying():
        if (_awaitingTerminal) {
          // MediaKit/mpv reports playing=true OPTIMISTICALLY at open — even
          // for URLs that cannot connect (measured on device). The honest
          // playable signal is content actually flowing, which the
          // EngineProgress case below requires (position > 0). Until then
          // the session stays honestly in loading and the open timer stays
          // armed.
          return;
        }
        if (state.status == PlaybackStatus.buffering) {
          _stallTimer?.cancel();
          state = _copyCurrent(status: PlaybackStatus.playing);
          _startTick();
          return;
        }
        // Explicit resume after pause (play() reports through the stream).
        if (state.status == PlaybackStatus.paused) {
          state = _copyCurrent(status: PlaybackStatus.playing);
          _startTick();
        }

      case EnginePaused():
        if (state.status == PlaybackStatus.playing) {
          _tickTimer?.cancel();
          state = _copyCurrent(status: PlaybackStatus.paused);
        }

      case EngineBuffering():
        if (state.status == PlaybackStatus.playing) {
          _tickTimer?.cancel();
          _startStallTimer(gen);
          state = _copyCurrent(status: PlaybackStatus.buffering);
        }

      case EngineRecovered():
        if (state.status == PlaybackStatus.buffering) {
          _stallTimer?.cancel();
          state = _copyCurrent(status: PlaybackStatus.playing);
          _startTick();
        }

      case EngineCompleted():
        if (_awaitingTerminal ||
            state.status == PlaybackStatus.playing ||
            state.status == PlaybackStatus.buffering) {
          _awaitingTerminal = false;
          _openTimer?.cancel();
          _stallTimer?.cancel();
          _tickTimer?.cancel();
          _flushProgress(completed: true);
          state = _copyCurrent(status: PlaybackStatus.completed);
        }

      case EngineFailed(:final String reason):
        _awaitingTerminal = false;
        _onCandidateFailed(
          gen,
          PlaybackFailure(
            type: PlaybackFailureType.sourceOpenFailure,
            message: 'This source could not be played.',
            engineDetail: reason,
          ),
        );

      case EngineErrored(:final String message):
        if (_awaitingTerminal) {
          // Open-phase error: no content ever flowed — fail the candidate
          // immediately (fast, honest dead-candidate detection).
          _awaitingTerminal = false;
          _onCandidateFailed(
            gen,
            PlaybackFailure(
              type: PlaybackFailureType.sourceOpenFailure,
              message: 'This source could not be played.',
              engineDetail: message,
            ),
          );
        } else if (state.status == PlaybackStatus.playing ||
            state.status == PlaybackStatus.paused) {
          // A mid-play error event is treated as a STALL signal, not an
          // immediate candidate death: MediaKit/mpv can surface non-fatal
          // transport errors that playback recovers from. Enter buffering
          // and arm the stall timer — recovery (EnginePlaying/Recovered)
          // resumes, a real interruption times out into a failure.
          _tickTimer?.cancel();
          _startStallTimer(gen);
          state = _copyCurrent(status: PlaybackStatus.buffering);
        } else if (state.status == PlaybackStatus.buffering) {
          // Already stalled: extend patience by re-arming the stall timer.
          _startStallTimer(gen);
        }

      case EngineProgress(
          :final Duration position,
          :final Duration duration,
          :final Duration buffered,
          :final double rate,
          :final double volume,
        ):
        if (_awaitingTerminal) {
          // The honest playable signal: media position is actually advancing.
          // (EnginePlaying is optimistic — see the EnginePlaying case.)
          if (position > Duration.zero) {
            _awaitingTerminal = false;
            _openTimer?.cancel();
            _playedThisCandidate = true;
            final PlaybackCandidate candidate = _candidates[_index];
            _record(
              PlaybackAttemptRecord(
                extensionId: candidate.extensionId,
                reference: candidate.reference,
                url: candidate.source.url,
                typeCode: candidate.source.type.code,
                quality: candidate.source.quality,
                attempt: candidate.attempt,
                outcome: 'success',
                failure: null,
                timeToPlayable: _timeSinceOpen,
                recordedAt: DateTime.now().toUtc(),
              ),
            );
            state = _copyCurrent(
              status: PlaybackStatus.playing,
              position: position,
              duration: duration,
              buffered: buffered,
              rate: rate,
              volume: volume,
            );
            _startTick();
          }
          return;
        }
        if (state.status == PlaybackStatus.playing ||
            state.status == PlaybackStatus.paused ||
            state.status == PlaybackStatus.buffering) {
          state = _copyCurrent(
            position: position,
            duration: duration,
            buffered: buffered,
            rate: rate,
            volume: volume,
          );
        }

      case EngineRateChanged(:final double rate):
        state = _copyCurrent(rate: rate);

      case EngineVolumeChanged(:final double volume):
        state = _copyCurrent(volume: volume);

      case EngineSubtitleChanged():
        break; // selection state is applied by [selectSubtitle]

      case EngineTracksChanged():
        break; // embedded track surfaces are a later concern (2E scope note)
    }
  }

  // ---------------------------------------------------------------------------
  // Progress sink (in-memory 2E seam; 2F persists)
  // ---------------------------------------------------------------------------

  void _startTick() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      if (_disposed || state.status != PlaybackStatus.playing) return;
      _elapsedWatch += const Duration(seconds: 1);
      _flushProgress(completed: false);
    });
  }

  void _flushProgress({required bool completed}) {
    final String? key = _progressKey;
    if (key == null || _candidates.isEmpty) return;
    try {
      ref.read(playbackProgressSinkProvider).report(
            targetKey: key,
            elapsed: _elapsedWatch,
            position: state.position,
            // An unknown duration is reported as null, never as a fake zero.
            duration: state.duration == Duration.zero ? null : state.duration,
            completed: completed,
            mediaKey: _mediaKey,
            mediaType: _mediaType?.code,
            title: _title,
            subtitleLine: _subtitleLine,
            seasonNumber: _seasonNumber,
            episodeNumber: _episodeNumber,
          );
    } on Object {
      // Progress reporting must never affect playback.
    }
  }

  // ---------------------------------------------------------------------------
  // Snapshot assembly
  // ---------------------------------------------------------------------------

  /// Identity used for progress reporting (null disables it for the session).
  String? _progressKey;
  String? _title;
  String? _subtitleLine;
  String? _mediaKey;
  MediaType? _mediaType;
  int? _seasonNumber;
  int? _episodeNumber;
  final List<PlaybackAttempt> _failures = <PlaybackAttempt>[];
  bool _playedThisCandidate = false;

  Duration? get _timeSinceOpen {
    final DateTime? startedAt = _openStartedAt;
    if (startedAt == null) return null;
    return DateTime.now().difference(startedAt);
  }

  /// A reset-shaped snapshot: position/buffer/subtitle surfaces cleared, the
  /// candidate list rebuilt from the live session fields.
  PlaybackSnapshot _snapshot({
    required PlaybackStatus status,
    required int gen,
    String? title,
    String? subtitleLine,
    PlaybackFailure? failure,
    bool clearCurrent = false,
    bool clearFailure = false,
  }) {
    _title = title ?? _title;
    // Keep the previous line when the caller does not supply one: the
    // exhausted-failure snapshot must not silently drop `Season 1 · Episode 2`.
    _subtitleLine = subtitleLine ?? _subtitleLine;
    if (clearFailure) _failures.clear();
    return state.copyWith(
      status: status,
      generation: gen,
      title: _title,
      subtitle: _subtitleLine,
      candidates: List<PlaybackCandidate>.unmodifiable(_candidates),
      current: clearCurrent ? null : _safeCurrent,
      attemptedCount: clearCurrent ? 0 : _index + 1,
      failures: List<PlaybackAttempt>.unmodifiable(_failures),
      position: Duration.zero,
      duration: Duration.zero,
      buffered: Duration.zero,
      availableSubtitles: const <SubtitleTrack>[],
      selectedSubtitle: null,
      refreshedOnce: _refreshedOnce,
      failure: failure,
      engine: _engine,
    );
  }

  PlaybackCandidate? get _safeCurrent =>
      _candidates.isEmpty || _index >= _candidates.length
          ? null
          : _candidates[_index];

  /// A light copy of the live session state: the candidate list and failure
  /// list are re-read from the live fields (a just-recorded failure or a
  /// refreshed candidate must be visible immediately), and the engine is
  /// always the live one.
  ///
  /// Nullable fields default to [PlaybackSnapshot.unset] (keep); pass an
  /// explicit `null` to clear them.
  PlaybackSnapshot _copyCurrent({
    PlaybackStatus? status,
    Object? current = PlaybackSnapshot.unset,
    int? attemptedCount,
    Duration? position,
    Duration? duration,
    Duration? buffered,
    double? rate,
    double? volume,
    List<SubtitleTrack>? availableSubtitles,
    Object? selectedSubtitle = PlaybackSnapshot.unset,
    Object? failure = PlaybackSnapshot.unset,
  }) {
    return state.copyWith(
      status: status,
      candidates: List<PlaybackCandidate>.unmodifiable(_candidates),
      current: current,
      attemptedCount: attemptedCount,
      failures: List<PlaybackAttempt>.unmodifiable(_failures),
      position: position,
      duration: duration,
      buffered: buffered,
      rate: rate,
      volume: volume,
      availableSubtitles: availableSubtitles,
      selectedSubtitle: selectedSubtitle,
      refreshedOnce: _refreshedOnce,
      failure: failure,
      engine: _engine,
    );
  }

  void _record(PlaybackAttemptRecord record) {
    _records.add(record);
    if (_records.length > _maxFailureRecords) _records.removeAt(0);
  }

  // ---------------------------------------------------------------------------
  // Disposal
  // ---------------------------------------------------------------------------

  void _handleDisposal() {
    _disposed = true;
    _generation++; // invalidate any in-flight attempt/fallback
    _cancelTimers();
    final PlaybackEngine? engine = _engine;
    _engine = null;
    _engineSub?.cancel();
    _engineSub = null;
    engine?.stop().whenComplete(() => engine.dispose());
  }

  void _cancelTimers() {
    _openTimer?.cancel();
    _stallTimer?.cancel();
    _tickTimer?.cancel();
  }
}

/// The current playback session state.
final NotifierProvider<PlaybackSessionNotifier, PlaybackSnapshot>
    playbackSessionProvider =
    NotifierProvider<PlaybackSessionNotifier, PlaybackSnapshot>(
      PlaybackSessionNotifier.new,
    );
