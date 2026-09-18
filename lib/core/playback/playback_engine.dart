import 'dart:async';

import '../extensions/contract/extension_source.dart';

/// What the engine wants the session layer to know happened.
///
/// Kept deliberately small: the session layer decides fallbacks, refreshes
/// and retries — the engine only reports facts.
sealed class PlaybackEngineEvent {
  const PlaybackEngineEvent();
}

/// The candidate is buffering (before first frame, or re-buffering).
final class EngineBuffering extends PlaybackEngineEvent {
  const EngineBuffering();
}

/// The candidate reached a playable state (first frame rendered).
final class EnginePlaying extends PlaybackEngineEvent {
  const EnginePlaying();
}

/// The user/engine paused playback.
final class EnginePaused extends PlaybackEngineEvent {
  const EnginePaused();
}

/// The candidate finished playing to the end.
final class EngineCompleted extends PlaybackEngineEvent {
  const EngineCompleted();
}

/// The engine could not play the candidate.
final class EngineFailed extends PlaybackEngineEvent {
  const EngineFailed(this.reason);

  /// Raw engine/driver diagnostics. Never shown verbatim to users.
  final String reason;
}

/// Transport/decoder error surfaced by the engine's error stream while the
/// candidate may still technically be "playing" (e.g. mid-stream failure).
final class EngineErrored extends PlaybackEngineEvent {
  const EngineErrored(this.message);

  /// Raw engine error text. Never shown verbatim to users.
  final String message;
}

/// A position/duration/buffer/rate/volume progress tick.
final class EngineProgress extends PlaybackEngineEvent {
  const EngineProgress({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.rate,
    required this.volume,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final double rate;
  final double volume;
}

/// How the engine was asked to change its playback rate.
final class EngineRateChanged extends PlaybackEngineEvent {
  const EngineRateChanged(this.rate);

  final double rate;
}

/// A volume change was applied by the engine.
final class EngineVolumeChanged extends PlaybackEngineEvent {
  const EngineVolumeChanged(this.volume);

  final double volume;
}

/// A subtitle selection was applied by the engine.
final class EngineSubtitleChanged extends PlaybackEngineEvent {
  const EngineSubtitleChanged(this.subtitle);

  final SubtitleTrack? subtitle;
}

/// Buffering ended and playback is flowing again.
final class EngineRecovered extends PlaybackEngineEvent {
  const EngineRecovered();
}

/// The engine's selected/available track set changed.
final class EngineTracksChanged extends PlaybackEngineEvent {
  const EngineTracksChanged();
}

/// Transport-agnostic playback engine.
///
/// This is the ONLY seam between SPECTA's player session and the underlying
/// engine (MediaKit). The session layer never imports MediaKit directly, so:
/// - unit tests run against a deterministic [FakePlaybackEngine];
/// - the real engine (MediaKit) can be initialized lazily on demand.
///
/// Contract:
/// - [open] starts loading [source]; the implementation must surface exactly
///   one terminal event per open through [events]: [EnginePlaying],
///   [EngineFailed] or [EngineCompleted] (Buffering may precede Playing).
/// - [stop] aborts the current open; a pending open then emits nothing
///   further through [events] (the session's abort guard handles it).
/// - [dispose] releases engine resources; the engine must be safe to dispose
///   exactly once, and every method after dispose is a no-op (never throws).
abstract interface class PlaybackEngine {
  /// Events emitted by this engine, in order.
  Stream<PlaybackEngineEvent> get events;

  /// The subtitle track currently applied, if any.
  SubtitleTrack? get currentSubtitle;

  /// Opens [source] (an MP4 or HLS candidate from a validated pool).
  Future<void> open(ExtensionSource source);

  /// Pauses playback.
  Future<void> pause();

  /// Resumes playback.
  Future<void> play();

  /// Seeks to [position].
  Future<void> seek(Duration position);

  /// Applies a playback rate multiplier (e.g. 0.5 .. 2.0).
  Future<void> setRate(double rate);

  /// Applies a volume multiplier (0.0 .. 1.0).
  Future<void> setVolume(double volume);

  /// Applies a subtitle track from the candidate's own list, or null to
  /// disable subtitles.
  Future<void> setSubtitle(SubtitleTrack? subtitle);

  /// Aborts the current open/playback without releasing the engine.
  Future<void> stop();

  /// Releases all engine resources. Idempotent.
  Future<void> dispose();
}
