import 'package:specta/core/library/library_store.dart';
import 'package:specta/core/library/watch_progress.dart';
import 'package:specta/core/extensions/contract/result_models.dart';

/// Reports elapsed watch time to a consumer.
///
/// The player reports honest, measured progress through this one seam; where
/// it goes is the consumer's business. Phase 2E bound it to an in-memory sink;
/// Phase 2F binds it to persistent storage. The player is unaware of the
/// difference.
///
/// Phase 2F extended the payload with OPTIONAL descriptive fields ([mediaKey],
/// [mediaType], [title], [subtitleLine], [seasonNumber], [episodeNumber],
/// [duration]) so a persistent consumer can rebuild a library screen without
/// reaching back into the (in-memory) metadata layer. Existing callers keep
/// compiling unchanged.
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
    Duration? duration,
    required bool completed,
    String? mediaKey,
    String? mediaType,
    String? title,
    String? subtitleLine,
    int? seasonNumber,
    int? episodeNumber,
  });
}

/// Phase 2E in-memory progress sink.
///
/// Keeps only what this process observed since launch; nothing is persisted.
/// Retained as the test/offline binding and as the honest fallback if a
/// persistent store is unavailable.
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
    Duration? duration,
    required bool completed,
    String? mediaKey,
    String? mediaType,
    String? title,
    String? subtitleLine,
    int? seasonNumber,
    int? episodeNumber,
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

/// Phase 2F persistent progress sink.
///
/// Maps each report onto one [WatchProgress] row, keyed by the session's own
/// playback identity. Writes are serialised through a single future chain so a
/// one-second tick can never interleave two upserts, and every failure is
/// contained: persistence must never affect playback or surface into the UI.
final class PersistentPlaybackProgressSink implements PlaybackProgressSink {
  PersistentPlaybackProgressSink(
    this._store, {
    this.onChanged,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final LibraryStore _store;

  /// Called after a successful (or dropped) write so read providers refresh.
  final void Function()? onChanged;

  final DateTime Function() _clock;

  Future<void> _queue = Future<void>.value();

  /// Awaits all writes queued so far. Tests use this to observe persistence
  /// deterministically; production code never needs to.
  Future<void> get idle => _queue;

  @override
  void report({
    required String targetKey,
    required Duration elapsed,
    Duration? position,
    Duration? duration,
    required bool completed,
    String? mediaKey,
    String? mediaType,
    String? title,
    String? subtitleLine,
    int? seasonNumber,
    int? episodeNumber,
  }) {
    if (targetKey.isEmpty) return; // identity is required — never guessed

    final WatchProgress progress = WatchProgress(
      id: targetKey,
      mediaKey: (mediaKey == null || mediaKey.isEmpty) ? targetKey : mediaKey,
      mediaType: MediaType.fromCode(mediaType) ?? MediaType.movie,
      // A report without a title is still a valid progress write; the identity
      // is the key, not the label.
      title: (title == null || title.isEmpty) ? targetKey : title,
      subtitleLine: subtitleLine,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      position: position ?? Duration.zero,
      duration: duration,
      elapsed: elapsed,
      completed: completed,
      updatedAt: _clock(),
    );

    _queue = _queue.then((_) => _write(progress)).catchError((Object _) {
      // Containment: a storage failure is not a playback failure.
    });
  }

  Future<void> _write(WatchProgress progress) async {
    try {
      await _store.upsert(progress);
      onChanged?.call();
    } on Object {
      // Containment: see [report].
    }
  }
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
