import 'dart:async';

import 'package:media_kit/media_kit.dart' as mk;

import '../errors/specta_failure.dart';
import '../extensions/contract/extension_source.dart';
import 'playback_engine.dart';

/// MediaKit-backed [PlaybackEngine].
///
/// Bridges SPECTA's engine contract onto MediaKit's `Player` streams. All
/// state lives in the `Player`; this class only translates events and keeps
/// candidates isolated from each other:
///
/// * **Idempotent lifecycle.** [dispose] is safe to call more than once and
///   every method after disposal is a no-op — the contract the playback
///   session relies on when it leaves a session and the provider graph is
///   disposed at the same time. (MediaKit asserts `[Player] has been disposed`
///   if a disposed player is touched, so the guard is load-bearing.)
/// * **Settled transitions.** A candidate's open first settles the previous
///   load with its events suppressed. The playback session asks for the next
///   candidate the moment a failure surfaces, so the old load can still be
///   mid-teardown; without this, the old candidate's late `error`/`buffering`
///   events could be attributed to the candidate being opened.
/// * **No cross-candidate leakage.** Events emitted while a transition is in
///   progress are dropped, so a new candidate can never inherit the previous
///   candidate's terminal events.
///
/// MediaKit is initialized lazily on first construction — the process-wide
/// `MediaKit.ensureInitialized()` performed in `main.dart` remains the
/// startup path; this is the defensive re-entry for hosts that skipped it.
final class MediaKitPlaybackEngine implements PlaybackEngine {
  MediaKitPlaybackEngine() {
    mk.MediaKit.ensureInitialized();
    _player = mk.Player();
    _subscriptions = <StreamSubscription<dynamic>>[
      _player.stream.playing.listen(_onPlaying),
      _player.stream.completed.listen(_onCompleted),
      _player.stream.buffering.listen(_onBuffering),
      _player.stream.error.listen(_onError),
      _player.stream.position.listen(_onPosition),
      _player.stream.duration.listen(_onDuration),
      _player.stream.buffer.listen(_onBuffer),
      _player.stream.rate.listen(_onRate),
      _player.stream.volume.listen(_onVolume),
    ];
  }

  late final mk.Player _player;
  late List<StreamSubscription<dynamic>> _subscriptions;

  final StreamController<PlaybackEngineEvent> _events =
      StreamController<PlaybackEngineEvent>.broadcast();

  /// Set once [dispose] has run; every later call is a no-op.
  bool _disposed = false;

  /// True between `open` and the first terminal event of that open.
  bool _opening = false;

  /// While true every native player event is DROPPED. Set only around a
  /// candidate transition: those events belong to the old load and must never
  /// fail the candidate being opened.
  bool _suppressing = false;

  /// Guards against cross-candidate event leaks: token of the current open.
  int _openToken = 0;

  SubtitleTrack? _currentSubtitle;

  // Last known progress values so every tick can carry a complete snapshot
  // (position ticks arrive far more often than duration/buffer ticks).
  Duration _lastPosition = Duration.zero;
  Duration _lastDuration = Duration.zero;
  Duration _lastBuffered = Duration.zero;

  @override
  Stream<PlaybackEngineEvent> get events => _events.stream;

  @override
  SubtitleTrack? get currentSubtitle => _currentSubtitle;

  /// The underlying MediaKit player. Exposed ONLY for view-layer video
  /// surface binding ([VideoController] must attach to the same player the
  /// engine drives); all playback control goes through [PlaybackEngine].
  mk.Player get player => _player;

  // ---------------------------------------------------------------------------
  // Engine contract
  // ---------------------------------------------------------------------------

  @override
  Future<void> open(ExtensionSource source) async {
    if (_disposed) return;

    // Settle the previous candidate with its events suppressed before the new
    // one is requested (see the class docs).
    _suppressing = true;
    _opening = false;
    _openToken++;
    try {
      await _player.stop();
    } on Object {
      // Stopping a dead or never-started load can fail; the open below is
      // still attempted from a settled state.
    }

    _opening = true;
    final int token = ++_openToken;
    _lastPosition = Duration.zero;
    _lastDuration = Duration.zero;
    _lastBuffered = Duration.zero;
    _suppressing = false;
    try {
      await _player.open(
        mk.Media(
          source.url,
          httpHeaders: (source.headers == null || source.headers!.isEmpty)
              ? null
              : Map<String, String>.of(source.headers!),
        ),
        play: true,
      );
    } on Object catch (e) {
      // MediaKit's open itself failed synchronously (rare; failures usually
      // arrive through stream.error). Report as a terminal failure only if
      // this open was not superseded in the meantime.
      if (!_disposed && token == _openToken && _opening) {
        _opening = false;
        _events.add(
          EngineFailed(
            PlaybackFailure(
              type: PlaybackFailureType.sourceOpenFailure,
              message: 'The source could not be opened.',
              engineDetail: e.toString(),
            ).toString(),
          ),
        );
      }
    }
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    await _player.pause();
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    await _player.play();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_disposed) return;
    await _player.seek(position);
  }

  @override
  Future<void> setRate(double rate) async {
    if (_disposed) return;
    await _player.setRate(rate);
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    await _player.setVolume(volume);
  }

  @override
  Future<void> setSubtitle(SubtitleTrack? subtitle) async {
    if (_disposed) return;
    _currentSubtitle = subtitle;
    await _player.setSubtitleTrack(
      subtitle == null
          ? mk.SubtitleTrack.no()
          : mk.SubtitleTrack.uri(
              subtitle.url,
              title: subtitle.label,
              language: subtitle.language,
            ),
    );
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    _suppressing = true;
    _opening = false;
    _openToken++; // invalidate any in-flight open
    try {
      await _player.stop();
    } on Object {
      // Nothing to recover: the next open starts from a settled state.
    } finally {
      _suppressing = false;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _suppressing = true;
    for (final StreamSubscription<dynamic> s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions = <StreamSubscription<dynamic>>[];
    await _events.close();
    try {
      await _player.dispose();
    } on Object {
      // Disposal is best-effort: a native failure here must not escape.
    }
  }

  // ---------------------------------------------------------------------------
  // Stream bridges
  // ---------------------------------------------------------------------------

  /// True when an event must be dropped (stream closed, engine disposed, or a
  /// candidate transition in progress).
  bool get _muted => _events.isClosed || _suppressing || _disposed;

  void _onPlaying(bool playing) {
    if (_muted) return;
    if (!_opening) {
      // A pause/play toggle after the first frame is a normal event.
      _events.add(playing ? const EnginePlaying() : const EnginePaused());
      return;
    }
    if (playing) {
      _opening = false;
      _events.add(const EnginePlaying());
    }
    // A `playing=false` during an open is buffering noise; the buffering
    // stream carries that state.
  }

  void _onCompleted(bool completed) {
    if (completed && !_muted) _events.add(const EngineCompleted());
  }

  void _onBuffering(bool buffering) {
    if (_muted) return;
    _events.add(buffering ? const EngineBuffering() : const EngineRecovered());
  }

  void _onError(String error) {
    if (_muted) return;
    if (_opening) {
      // Terminal for the candidate currently being opened.
      _opening = false;
      _events.add(EngineFailed(error));
    } else {
      // Mid-stream transport error while playing.
      _events.add(EngineErrored(error));
    }
  }

  void _onPosition(Duration position) => _emitProgress(position);

  void _onDuration(Duration duration) =>
      _emitProgress(_lastPosition, duration: duration);

  void _onBuffer(Duration buffer) =>
      _emitProgress(_lastPosition, buffered: buffer);

  void _onRate(double rate) {
    if (!_muted) _events.add(EngineRateChanged(rate));
  }

  void _onVolume(double volume) {
    if (!_muted) _events.add(EngineVolumeChanged(volume));
  }

  void _emitProgress(
    Duration position, {
    Duration? duration,
    Duration? buffered,
  }) {
    if (position != Duration.zero) _lastPosition = position;
    if (duration != null && duration != Duration.zero) _lastDuration = duration;
    if (buffered != null) _lastBuffered = buffered;
    if (_muted) return;
    _events.add(
      EngineProgress(
        position: _lastPosition,
        duration: _lastDuration,
        buffered: _lastBuffered,
        rate: _player.state.rate,
        volume: _player.state.volume,
      ),
    );
  }
}
