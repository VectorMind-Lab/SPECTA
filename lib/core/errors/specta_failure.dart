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
