/// Baseline failure categories for extension operations.
///
/// An extension failure must NEVER crash SPECTA: the runtime converts every
/// extension error into one of these controlled categories and isolates the
/// failing extension. The string codes are the canonical names used in
/// diagnostics and logs.
enum ExtensionFailureType {
  networkError('NETWORK_ERROR', retryable: true),
  timeout('TIMEOUT', retryable: true),
  httpError('HTTP_ERROR', retryable: true),
  parseError('PARSE_ERROR'),
  invalidResult('INVALID_RESULT'),
  unsupported('UNSUPPORTED'),
  runtimeError('RUNTIME_ERROR', retryable: true),
  capabilityError('CAPABILITY_ERROR');

  const ExtensionFailureType(this.code, {this.retryable = false});

  /// Canonical, stable name for diagnostics.
  final String code;

  /// Whether retrying the same operation can plausibly succeed.
  final bool retryable;
}

/// Base type for every failure SPECTA models as data instead of an unhandled
/// exception. Sealed so callers must handle all cases.
sealed class SpectaFailure implements Exception {
  const SpectaFailure(this.message, {this.isRetryable = false});

  /// Human-readable, non-technical summary.
  final String message;

  /// Whether the caller may sensibly retry.
  final bool isRetryable;

  @override
  String toString() => '$runtimeType($message)';
}

/// A controlled failure produced by an extension operation.
final class ExtensionFailure extends SpectaFailure {
  // Not const: the default retryability is read from [type] at runtime.
  ExtensionFailure({
    required this.extensionId,
    required this.operation,
    required this.type,
    required String message,
    required this.timestamp,
    this.detail,
    bool? isRetryable,
  }) : super(message, isRetryable: isRetryable ?? type.retryable);

  /// Real extension identity, never the neutral user-facing label.
  final String extensionId;

  /// Extension contract operation that failed (search, details, ...).
  final String operation;

  final ExtensionFailureType type;
  final DateTime timestamp;

  /// Developer-only diagnostics. Never rendered on an ordinary user screen
  /// (see §15 of the architecture brief).
  final String? detail;

  /// Structured diagnostics record for internal logging.
  Map<String, Object?> toDiagnostics() => <String, Object?>{
    'extensionId': extensionId,
    'operation': operation,
    'errorType': type.code,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'message': message,
    if (detail != null) 'detail': detail,
  };

  @override
  String toString() => '${type.code} [$extensionId/$operation] $message';
}

/// Structured local persistence failed (open, migrate, read or write).
final class StorageFailure extends SpectaFailure {
  const StorageFailure(super.message, {this.path, super.isRetryable = false});

  /// Location involved, where known.
  final String? path;

  @override
  String toString() =>
      'StorageFailure($message${path == null ? '' : ' @ $path'})';
}

/// A playback attempt failed in a controlled, structured way.
///
/// The player (Phase 2E) converts every engine/transport/decoder problem into
/// one of these instead of letting an exception escape into the UI. The
/// failure is attached to the exact candidate that failed (extension id +
/// reference provenance by the caller) so fallback and refresh decisions
/// keep their provenance.
enum PlaybackFailureType {
  /// The source could not be opened at all (unreachable URL, refused
  /// handshake, rejected container).
  sourceOpenFailure('SOURCE_OPEN_FAILURE', retryable: true),

  /// The media cannot be decoded/played on this device (unsupported codec,
  /// broken container).
  unsupportedMedia('UNSUPPORTED_MEDIA'),

  /// The network failed mid-stream or the stream stalled.
  networkFailure('NETWORK_FAILURE', retryable: true),

  /// Playback stalled/was interrupted while buffering.
  bufferingFailure('BUFFERING_FAILURE', retryable: true),

  /// The player engine itself failed (decoder/device error).
  playerFailure('PLAYER_FAILURE', retryable: true),

  /// The engine was not usable in the first place (missing platform support,
  /// failed initialization).
  engineUnavailable('ENGINE_UNAVAILABLE'),

  /// The session was stopped before playback could be established.
  sessionAborted('SESSION_ABORTED'),

  /// Every usable candidate in the pool failed.
  sourcesExhausted('SOURCES_EXHAUSTED'),

  /// A refresh attempt through the source manager could not produce a
  /// usable source.
  refreshFailed('REFRESH_FAILED', retryable: true);

  const PlaybackFailureType(this.code, {this.retryable = false});

  /// Canonical, stable name for diagnostics.
  final String code;

  /// Whether retrying the same candidate can plausibly succeed.
  final bool retryable;
}

final class PlaybackFailure extends SpectaFailure {
  // Not const: the default retryability is read from [type] at runtime.
  PlaybackFailure({
    required this.type,
    required String message,
    this.engineDetail,
    bool? isRetryable,
  }) : super(message, isRetryable: isRetryable ?? type.retryable);

  final PlaybackFailureType type;

  /// Raw engine/driver diagnostics. Developer-only; never rendered on an
  /// ordinary user screen (mirrors [ExtensionFailure.detail]).
  final String? engineDetail;

  /// Structured diagnostics record for internal logging.
  Map<String, Object?> toDiagnostics() => <String, Object?>{
        'errorType': type.code,
        'message': message,
        if (engineDetail != null) 'engineDetail': engineDetail,
      };

  @override
  String toString() => '${type.code} $message';
}

/// An extension was asked for something it never declared.
///
/// SPECTA must not assume a function exists merely because a JavaScript
/// function happens to exist; capabilities have to be declared explicitly.
final class CapabilityFailure extends SpectaFailure {
  const CapabilityFailure({
    required this.extensionId,
    required this.capability,
    String? message,
  }) : super(message ?? 'Extension does not declare capability "$capability".');

  final String extensionId;
  final String capability;

  @override
  String toString() => 'CapabilityFailure($extensionId: $capability) $message';
}

/// A download attempt failed in a controlled, structured way (Phase 2G).
///
/// The download system converts every transport/storage/policy problem into
/// one of these instead of letting an exception escape into the UI. The
/// failure mirrors the [ExtensionFailure] / [PlaybackFailure] discipline:
/// categories are data, each with an honest user-facing default message and
/// an explicit retryability verdict.
///
/// This class lives in THIS library — next to every other [SpectaFailure]
/// subtype — because [SpectaFailure] is sealed and can only be extended
/// here. The download models reference it; they must not redefine it.
enum DownloadFailureType {
  /// Network failed mid-transfer or the request could not connect.
  networkError('NETWORK_ERROR', retryable: true),

  /// The transfer stalled past the engine's idle timeout.
  timeout('TIMEOUT', retryable: true),

  /// The server answered with a 5xx — plausibly transient.
  serverError('SERVER_ERROR', retryable: true),

  /// The server answered with a 4xx — the URL/attempt is not usable.
  httpError('HTTP_ERROR'),

  /// The response was not a usable progressive media stream.
  invalidResponse('INVALID_RESPONSE'),

  /// The device ran out of storage (checked up front or hit mid-download).
  insufficientStorage('INSUFFICIENT_STORAGE'),

  /// The download could not be safely continued/restarted on disk.
  storageFailure('STORAGE_FAILURE', retryable: true),

  /// The attempt did not survive a process/app interruption (device restart,
  /// process death). Auto-retryable under the bounded budget — the download
  /// itself did nothing wrong.
  interrupted('INTERRUPTED', retryable: true),

  /// No downloadable source for this item (e.g. HLS-only pool — V1 is MP4
  /// first; the playlist is never saved as if it were the media).
  unsupportedSource('UNSUPPORTED_SOURCE'),

  /// Resolution itself could not produce a pool (no sources / refresh
  /// unavailable / provenance gone).
  sourcesExhausted('SOURCES_EXHAUSTED'),

  /// The engine violated its contract (threw instead of reporting a
  /// structured result). Never retryable on its own — a broken engine is not
  /// fixed by re-running the same transfer.
  engineFailure('ENGINE_FAILURE');

  const DownloadFailureType(this.code, {this.retryable = false});

  /// Canonical, stable name for diagnostics.
  final String code;

  /// Whether retrying the same source can plausibly succeed.
  final bool retryable;

  static DownloadFailureType? fromCode(String? code) {
    for (final DownloadFailureType t in DownloadFailureType.values) {
      if (t.code == code) return t;
    }
    return null;
  }

  /// User-facing, non-technical wording.
  String get message => switch (this) {
        DownloadFailureType.networkError =>
          'The network dropped during the download.',
        DownloadFailureType.timeout => 'The download stalled for too long.',
        DownloadFailureType.serverError =>
          'The server had a problem while serving the file.',
        DownloadFailureType.httpError =>
          'The server refused this download (source unavailable).',
        DownloadFailureType.invalidResponse =>
          'The server did not return a downloadable file.',
        DownloadFailureType.insufficientStorage =>
          'There is not enough free storage for this download.',
        DownloadFailureType.storageFailure =>
          'The download could not be written to storage.',
        DownloadFailureType.interrupted =>
          'The download was interrupted and can be resumed.',
        DownloadFailureType.unsupportedSource =>
          'Only direct file downloads are supported right now; this item '
              'only offers a streaming source.',
        DownloadFailureType.sourcesExhausted =>
          'No downloadable source could be found for this item.',
        DownloadFailureType.engineFailure =>
          'The download engine reported an unexpected problem.',
      };
}

final class DownloadFailure extends SpectaFailure {
  // Not const: the default retryability is read from [type] at runtime.
  DownloadFailure({
    required this.type,
    required String message,
    this.detail,
    bool? isRetryable,
  }) : super(message, isRetryable: isRetryable ?? type.retryable);

  final DownloadFailureType type;

  /// Developer-only diagnostics. Never rendered on an ordinary user screen.
  final String? detail;

  /// Structured diagnostics record for internal logging.
  Map<String, Object?> toDiagnostics() => <String, Object?>{
        'errorType': type.code,
        'message': message,
        if (detail != null) 'detail': detail,
      };

  @override
  String toString() => '${type.code} $message';
}
