import 'package:specta/core/extensions/contract/result_models.dart';

/// One persisted watch-progress record (Phase 2F).
///
/// This is SPECTA's own model for "where the viewer is" in one playback
/// identity. It is deliberately persistence-shaped, not player-shaped: the
/// player keeps its `PlaybackSnapshot`; this is what survives a process
/// restart.
final class WatchProgress {
  const WatchProgress({
    required this.id,
    required this.mediaKey,
    required this.mediaType,
    required this.title,
    this.subtitleLine,
    this.seasonNumber,
    this.episodeNumber,
    this.position = Duration.zero,
    this.duration,
    this.elapsed = Duration.zero,
    this.completed = false,
    required this.updatedAt,
  });

  /// Stable playback identity:
  /// `<mediaKey>` for a movie, `<mediaKey>|s<S>e<E>` for an episode.
  final String id;

  /// The parent work's canonical metadata key.
  final String mediaKey;

  /// Movie or series — never guessed from the title.
  final MediaType mediaType;

  /// Display title.
  final String title;

  /// Optional second display line (e.g. `Season 1 · Episode 2`).
  final String? subtitleLine;

  /// Season / episode numbers for a series episode; null for a movie.
  final int? seasonNumber;
  final int? episodeNumber;

  /// Last observed playback position.
  final Duration position;

  /// Total media duration when the engine reported one.
  final Duration? duration;

  /// Accumulated watch time the player measured.
  final Duration elapsed;

  /// Whether the player reported playback reached the end.
  final bool completed;

  /// Last time the player reported progress for this identity.
  final DateTime updatedAt;

  /// True for a series episode (both numbers present).
  bool get isEpisode => seasonNumber != null && episodeNumber != null;

  /// Position as a fraction of duration, when duration is known and positive.
  /// Null when it genuinely cannot be computed — never fabricated.
  double? get fraction {
    final Duration? d = duration;
    if (d == null || d.inMilliseconds <= 0) return null;
    if (!position.isNegative && position.inMilliseconds <= 0) return 0.0;
    final double f = position.inMilliseconds / d.inMilliseconds;
    return f.clamp(0.0, 1.0);
  }

  /// Remaining watch time, when duration is known.
  Duration? get remaining {
    final Duration? d = duration;
    if (d == null) return null;
    final Duration r = d - position;
    return r.isNegative ? Duration.zero : r;
  }

  /// A copy with the fields a write path is allowed to change.
  WatchProgress copyWith({
    String? id,
    String? mediaKey,
    MediaType? mediaType,
    String? title,
    String? subtitleLine,
    int? seasonNumber,
    int? episodeNumber,
    Duration? position,
    Duration? duration,
    Duration? elapsed,
    bool? completed,
    DateTime? updatedAt,
  }) =>
      WatchProgress(
        id: id ?? this.id,
        mediaKey: mediaKey ?? this.mediaKey,
        mediaType: mediaType ?? this.mediaType,
        title: title ?? this.title,
        subtitleLine: subtitleLine ?? this.subtitleLine,
        seasonNumber: seasonNumber ?? this.seasonNumber,
        episodeNumber: episodeNumber ?? this.episodeNumber,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        elapsed: elapsed ?? this.elapsed,
        completed: completed ?? this.completed,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  String toString() =>
      'WatchProgress($id, ${mediaType.code}, $position/$duration, '
      'completed: $completed)';
}
