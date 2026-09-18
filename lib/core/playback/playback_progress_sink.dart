/// Reports elapsed watch time to a consumer.
///
/// Phase 2E boundary: persistent watch progress belongs to Phase 2F. This
/// seam exists so the player already reports honest progress without any
/// database, schema, or persistence work happening in this phase. The 2E
/// implementation is in-memory only; 2F replaces the binding without
/// touching the player.
abstract interface class PlaybackProgressSink {
  /// Reports [elapsed] of watch time for one playback target.
  ///
  /// [targetKey] is a session-supplied identity string (e.g. the metadata
  /// key for a movie, or metadata key + episode reference for an episode).
  /// [positionSeconds] is the last observed playback position, when known.
  void report({
    required String targetKey,
    required Duration elapsed,
    Duration? position,
    required bool completed,
  });
}

/// Phase 2E in-memory progress sink.
///
/// Keeps only what this process observed since launch; nothing is persisted
/// (no Drift table, no schema change — hard 2E boundary). Also caps memory
/// defensively: at most [_maxEntries] targets retain progress.
final class InMemoryPlaybackProgressSink implements PlaybackProgressSink {
  static const int _maxEntries = 512;

  final Map<String, _ProgressEntry> _entries = <String, _ProgressEntry>{};

  /// The last reported elapsed time for [targetKey], or null.
  Duration? elapsedFor(String targetKey) => _entries[targetKey]?.elapsed;

  @override
  void report({
    required String targetKey,
    required Duration elapsed,
    Duration? position,
    required bool completed,
  }) {
    if (targetKey.isEmpty) return; // identity is required — never guessed
    if (!_entries.containsKey(targetKey) && _entries.length >= _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[targetKey] = _ProgressEntry(
      elapsed: elapsed,
      position: position,
      completed: completed,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  /// Clears all in-memory progress (used by tests; process-lifetime data).
  void clear() => _entries.clear();
}

final class _ProgressEntry {
  const _ProgressEntry({
    required this.elapsed,
    required this.position,
    required this.completed,
    required this.updatedAt,
  });

  final Duration elapsed;
  final Duration? position;
  final bool completed;
  final DateTime updatedAt;

  @override
  String toString() =>
      '_ProgressEntry($elapsed, pos: $position, completed: $completed)';
}
