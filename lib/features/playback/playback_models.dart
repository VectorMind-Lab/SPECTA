// Playback-layer models for the Phase 2E player.
//
// `SubtitleTrack` is re-exported from the Phase 1 extension contract — the
// canonical source/subtitle model. No duplicate subtitle model is created.
library;

export '../../core/extensions/contract/extension_source.dart'
    show SubtitleTrack;

import '../../core/errors/specta_failure.dart';
import '../../core/extensions/contract/extension_source.dart'
    show ExtensionSource, SubtitleTrack;
import '../../core/playback/playback_engine.dart';
import '../../core/sources/source_pool.dart';

/// Playback session status. Honest transitions only: `playing` is reached
/// when the engine reports the candidate actually reached a playable state,
/// never merely because an open call returned.
enum PlaybackStatus {
  /// Nothing requested yet.
  idle,

  /// A candidate is being opened (loading / first buffer).
  loading,

  /// The current candidate is playing.
  playing,

  /// The current candidate is paused (only after it was playing).
  paused,

  /// The current candidate stalled and is re-buffering.
  buffering,

  /// A fallback candidate is being opened after a failure.
  switchingSource,

  /// The candidate finished playing to the end.
  completed,

  /// Every usable candidate failed — the session is dead.
  failed,
}

/// One ordered candidate the session will attempt, with its provenance.
///
/// This is SPECTA's own playback-layer view of a [RankedSource]: the
/// candidate itself ([ExtensionSource] via [RankedSource]) is NOT duplicated
/// — the ranked source is referenced directly.
final class PlaybackCandidate {
  const PlaybackCandidate({
    required this.ranked,
    required this.attempt,
  });

  /// The ranked pool entry (source + extensionId + reference + score).
  final RankedSource ranked;

  /// 0-based attempt order within the session's candidate list.
  final int attempt;

  /// The validated source to open.
  ExtensionSource get source => ranked.source;

  /// Provenance: the contributing extension's registry id.
  String get extensionId => ranked.extensionId;

  /// Provenance: the extension-internal reference this candidate came from.
  String get reference => ranked.reference;

  @override
  String toString() =>
      'PlaybackCandidate(#$attempt, $extensionId, ${source.type.code})';
}

/// How one playback attempt ended. Data, never an exception.
enum PlaybackAttemptOutcomeKind {
  /// The candidate reached a playable state.
  success,

  /// The candidate failed before or during playback.
  failed,

  /// The session was superseded (new open/reset) while this attempt ran.
  aborted,
}

/// The structured result of one playback attempt.
final class PlaybackAttempt {
  const PlaybackAttempt({
    required this.candidate,
    required this.kind,
    this.failure,
  });

  final PlaybackCandidate candidate;
  final PlaybackAttemptOutcomeKind kind;

  /// The structured failure — only for [PlaybackAttemptOutcomeKind.failed].
  final PlaybackFailure? failure;

  bool get isFailed => kind == PlaybackAttemptOutcomeKind.failed;

  @override
  String toString() =>
      'PlaybackAttempt(${candidate.extensionId}, ${kind.name}, '
      '${failure?.type.code ?? '-'})';
}

/// Descriptive playback observations (brief §16).
///
/// The player records what actually happened — nothing is invented. These
/// records are data for diagnostics and for a future ranker health term;
/// they are NOT a ranking algorithm and never permanently disable anything.
final class PlaybackAttemptRecord {
  const PlaybackAttemptRecord({
    required this.extensionId,
    required this.reference,
    required this.url,
    required this.typeCode,
    required this.quality,
    required this.attempt,
    required this.outcome,
    required this.failure,
    required this.timeToPlayable,
    required this.recordedAt,
  });

  final String extensionId;
  final String reference;
  final String url;
  final String typeCode;
  final String? quality;
  final int attempt;

  /// 'success' or the [PlaybackFailureType.code] of the failure.
  final String outcome;

  /// The structured failure, when the outcome was a failure.
  final PlaybackFailure? failure;

  /// Measured time from open to first playable frame. Null when the
  /// candidate never became playable.
  final Duration? timeToPlayable;

  final DateTime recordedAt;

  @override
  String toString() => 'PlaybackAttemptRecord($extensionId, $outcome, '
      'ttff: ${timeToPlayable ?? "-"}, attempt: $attempt)';
}

/// The full, immutable playback session snapshot the UI renders.
final class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.status,
    required this.generation,
    this.title,
    this.subtitle,
    this.candidates = const <PlaybackCandidate>[],
    this.current,
    this.attemptedCount = 0,
    this.failures = const <PlaybackAttempt>[],
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.rate = 1.0,
    this.volume = 1.0,
    this.availableSubtitles = const <SubtitleTrack>[],
    this.selectedSubtitle,
    this.refreshedOnce = false,
    this.failure,
    this.engine,
  });

  final PlaybackStatus status;

  /// Monotonic session counter — a stale open/fallback can never overwrite a
  /// newer session (same race discipline as the 2B/2C/2D sessions).
  final int generation;

  /// Display title (item/episode title — never a provider URL or label).
  final String? title;

  /// Optional second line (e.g. `Season 1 · Episode 2`).
  final String? subtitle;

  /// The ordered candidate list this session is working through (selected
  /// first, then 2D's fallbacks — SPECTA's order, not the player's).
  final List<PlaybackCandidate> candidates;

  /// The candidate currently loaded/playing, if any.
  final PlaybackCandidate? current;

  /// How many candidates were attempted so far (for honest "source 2 of N").
  final int attemptedCount;

  /// Structured failures of the attempts so far (provenance preserved).
  final List<PlaybackAttempt> failures;

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final double rate;
  final double volume;

  /// Subtitle tracks offered by the current candidate (may be empty).
  final List<SubtitleTrack> availableSubtitles;

  /// The currently selected external subtitle, if any.
  final SubtitleTrack? selectedSubtitle;

  /// Whether the refresh seam was already exercised this session — refresh
  /// is attempted at most once per session to keep fallback bounded.
  final bool refreshedOnce;

  /// The terminal failure — only for [PlaybackStatus.failed].
  final PlaybackFailure? failure;

  /// The engine instance driving the current candidate. Exposed ONLY so the
  /// video surface can bind its controller to the same engine; all playback
  /// control flows through the session notifier.
  final PlaybackEngine? engine;

  bool get isTerminal =>
      status == PlaybackStatus.completed || status == PlaybackStatus.failed;

  /// Sentinel for [copyWith]: marks an argument as "not supplied", so an
  /// explicit `null` can mean *clear this field* instead of *keep it*.
  static const Object unset = Object();

  /// Returns a copy with the supplied fields replaced.
  ///
  /// Nullable fields ([title], [subtitle], [current], [selectedSubtitle],
  /// [failure], [engine]) accept [unset] (the default) to keep their current
  /// value; pass an explicit `null` to clear them.
  PlaybackSnapshot copyWith({
    PlaybackStatus? status,
    int? generation,
    Object? title = unset,
    Object? subtitle = unset,
    List<PlaybackCandidate>? candidates,
    Object? current = unset,
    int? attemptedCount,
    List<PlaybackAttempt>? failures,
    Duration? position,
    Duration? duration,
    Duration? buffered,
    double? rate,
    double? volume,
    List<SubtitleTrack>? availableSubtitles,
    Object? selectedSubtitle = unset,
    bool? refreshedOnce,
    Object? failure = unset,
    Object? engine = unset,
  }) {
    return PlaybackSnapshot(
      status: status ?? this.status,
      generation: generation ?? this.generation,
      title: identical(title, unset) ? this.title : title as String?,
      subtitle: identical(subtitle, unset) ? this.subtitle : subtitle as String?,
      candidates: candidates ?? this.candidates,
      current: identical(current, unset)
          ? this.current
          : current as PlaybackCandidate?,
      attemptedCount: attemptedCount ?? this.attemptedCount,
      failures: failures ?? this.failures,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      buffered: buffered ?? this.buffered,
      rate: rate ?? this.rate,
      volume: volume ?? this.volume,
      availableSubtitles: availableSubtitles ?? this.availableSubtitles,
      selectedSubtitle: identical(selectedSubtitle, unset)
          ? this.selectedSubtitle
          : selectedSubtitle as SubtitleTrack?,
      refreshedOnce: refreshedOnce ?? this.refreshedOnce,
      failure: identical(failure, unset)
          ? this.failure
          : failure as PlaybackFailure?,
      engine: identical(engine, unset) ? this.engine : engine as PlaybackEngine?,
    );
  }

  @override
  String toString() =>
      'PlaybackSnapshot(${status.name}, gen: $generation, '
      'attempted: $attemptedCount/${candidates.length})';
}
