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

/// How obtaining an extension's bytes over the network failed.
///
/// This is DISTRIBUTION, not trust: a successful download says nothing about
/// whether the extension is legitimate. Trust remains the manifest signature,
/// verified by [ExtensionManager] after the bytes land. See
/// `lib/core/extensions/distribution/`.
enum ExtensionDistributionFailureType {
  /// The URL was empty, unparseable, or not HTTPS.
  invalidUrl('INVALID_URL'),

  /// The host was refused by the transport policy (loopback/private/link-local).
  hostBlocked('HOST_BLOCKED'),

  /// Too many redirects, or a redirect left the allowed scheme/host rules.
  redirectRefused('REDIRECT_REFUSED'),

  /// The request never completed (DNS, socket, TLS).
  networkError('NETWORK_ERROR', retryable: true),

  /// The request exceeded the deadline.
  timeout('TIMEOUT', retryable: true),

  /// The server answered 5xx — plausibly transient.
  serverError('SERVER_ERROR', retryable: true),

  /// The server answered another non-success status (404, 429, ...).
  httpError('HTTP_ERROR'),

  /// The body exceeded the extension size cap.
  ///
  /// This is now ONLY ever a genuine size problem. Two unrelated failure modes
  /// used to be folded into this type — a body that is not UTF-8 text, and an
  /// empty body — and both surfaced to the user as "That extension file is too
  /// large to install." That sent people hunting for a size problem that did
  /// not exist: a 343-byte JSON catalogue was reported as too large. Each cause
  /// now has its own truthful type.
  tooLarge('TOO_LARGE'),

  /// The body arrived intact but does not decode as UTF-8 text (e.g. a binary
  /// archive was served instead of a `.js` file).
  notText('NOT_TEXT'),

  /// The body arrived fine, but it is not a SPECTA extension: there is no
  /// `// ==SpectaExtension==` manifest to read an id from.
  ///
  /// This type exists because the "not an extension" case was reported as
  /// `tooLarge`, which is how a 343-byte `repo.json` catalogue reached the user
  /// as "That extension file is too large to install."
  notAnExtension('NOT_AN_EXTENSION'),

  /// The host answered successfully but returned an empty body.
  emptyResponse('EMPTY_RESPONSE'),

  /// The bytes did not match the SHA-256 the source declared, when one was
  /// declared. Transport integrity only — still not a trust verdict.
  integrityMismatch('INTEGRITY_MISMATCH'),

  /// The file could not be written to app-private storage.
  storageFailure('STORAGE_FAILURE', retryable: true),

  /// The caller abandoned the request.
  cancelled('CANCELLED');

  const ExtensionDistributionFailureType(this.code, {this.retryable = false});

  final String code;
  final bool retryable;

  String get message => switch (this) {
    ExtensionDistributionFailureType.invalidUrl =>
      'That does not look like a valid extension link.',
    ExtensionDistributionFailureType.hostBlocked =>
      'That address cannot be used for extensions.',
    ExtensionDistributionFailureType.redirectRefused =>
      'The extension link redirected somewhere SPECTA will not follow.',
    ExtensionDistributionFailureType.networkError =>
      'The extension could not be downloaded. Check your connection.',
    ExtensionDistributionFailureType.timeout =>
      'The extension download took too long. Try again.',
    ExtensionDistributionFailureType.serverError =>
      'The extension host reported a problem. Try again later.',
    ExtensionDistributionFailureType.httpError =>
      'The extension link could not be fetched.',
    ExtensionDistributionFailureType.tooLarge =>
      'That extension file is too large to install.',
    ExtensionDistributionFailureType.notText =>
      'That link did not return a readable text file.',
    ExtensionDistributionFailureType.notAnExtension =>
      'That link is not a SPECTA extension.',
    ExtensionDistributionFailureType.emptyResponse =>
      'That link returned an empty file.',
    ExtensionDistributionFailureType.integrityMismatch =>
      'The downloaded extension did not match its published checksum.',
    ExtensionDistributionFailureType.storageFailure =>
      'The extension could not be saved on this device.',
    ExtensionDistributionFailureType.cancelled => 'The download was cancelled.',
  };
}

final class ExtensionDistributionFailure extends SpectaFailure {
  ExtensionDistributionFailure({
    required this.type,
    String? message,
    this.stage,
    this.statusCode,
    this.detail,
    bool? isRetryable,
  }) : super(
         message ?? type.message,
         isRetryable: isRetryable ?? type.retryable,
       );

  final ExtensionDistributionFailureType type;

  /// Which step failed: `validate`, `download`, `verify` or `store`.
  final String? stage;

  final int? statusCode;

  /// Developer-only. Never contains a full URL query or any credential.
  final String? detail;

  @override
  String toString() => 'ExtensionDistributionFailure(${type.code}, $message)';
}

/// A catalogue request failed in a controlled, structured way (Phase D).
///
/// The catalogue is a DISCOVERY document only. A catalogue failure is never a
/// trust decision, and a successful catalogue fetch never implies that any
/// entry is trustworthy — each extension is still verified on its own.
enum ExtensionCatalogueFailureType {
  networkError('NETWORK_ERROR', retryable: true),
  timeout('TIMEOUT', retryable: true),
  serverError('SERVER_ERROR', retryable: true),
  httpError('HTTP_ERROR'),
  invalidUrl('INVALID_URL'),
  parseError('PARSE_ERROR'),
  unsupportedSchema('UNSUPPORTED_SCHEMA'),

  /// The document parsed, but it lists nothing SPECTA can install — typically a
  /// repository whose entries are compiled/binary provider plugins rather than
  /// JavaScript files.
  ///
  /// Deliberately NOT `unsupportedSchema`: the document may be perfectly valid,
  /// and saying the format is "unsupported" would be a lie that sends the user
  /// hunting for a format problem that does not exist.
  noInstallableEntries('NO_INSTALLABLE_ENTRIES'),
  cancelled('CANCELLED');

  const ExtensionCatalogueFailureType(this.code, {this.retryable = false});

  final String code;
  final bool retryable;

  String get message => switch (this) {
    ExtensionCatalogueFailureType.networkError =>
      'The extension catalogue could not be reached. Check your connection.',
    ExtensionCatalogueFailureType.timeout =>
      'The extension catalogue took too long to answer. Try again.',
    ExtensionCatalogueFailureType.serverError =>
      'The extension catalogue reported a problem. Try again later.',
    ExtensionCatalogueFailureType.httpError =>
      'The extension catalogue could not be fetched.',
    ExtensionCatalogueFailureType.invalidUrl =>
      'That does not look like a valid catalogue address.',
    ExtensionCatalogueFailureType.parseError =>
      'The extension catalogue could not be read.',
    ExtensionCatalogueFailureType.unsupportedSchema =>
      'This extension catalogue uses an unsupported format.',
    ExtensionCatalogueFailureType.noInstallableEntries =>
      'That repository does not list any JavaScript extensions SPECTA can '
          'install.',
    ExtensionCatalogueFailureType.cancelled => 'The request was cancelled.',
  };
}

final class ExtensionCatalogueFailure extends SpectaFailure {
  ExtensionCatalogueFailure({
    required this.type,
    String? message,
    this.statusCode,
    this.detail,
    bool? isRetryable,
  }) : super(
         message ?? type.message,
         isRetryable: isRetryable ?? type.retryable,
       );

  final ExtensionCatalogueFailureType type;
  final int? statusCode;
  final String? detail;

  @override
  String toString() => 'ExtensionCatalogueFailure(${type.code}, $message)';
}

///
/// AniList is a public metadata provider and requires no credential. The
/// failure therefore has no configuration or secret category; it reuses the
/// same retryability discipline as the other catalogue clients.
enum AniListFailureType {
  networkError('NETWORK_ERROR', retryable: true),
  timeout('TIMEOUT', retryable: true),
  rateLimited('RATE_LIMITED', retryable: true),
  serverError('SERVER_ERROR', retryable: true),
  httpError('HTTP_ERROR'),
  notFound('NOT_FOUND'),
  parseError('PARSE_ERROR'),
  cancelled('CANCELLED');

  const AniListFailureType(this.code, {this.retryable = false});

  final String code;
  final bool retryable;

  String get message => switch (this) {
    AniListFailureType.networkError =>
      'The anime catalogue could not be reached. Check your connection.',
    AniListFailureType.timeout =>
      'The anime catalogue took too long to answer. Try again.',
    AniListFailureType.rateLimited =>
      'The anime catalogue is temporarily limiting requests. Try again later.',
    AniListFailureType.serverError =>
      'The anime catalogue reported a problem on its side. Try again later.',
    AniListFailureType.httpError => 'The anime catalogue request was refused.',
    AniListFailureType.notFound => 'That anime is no longer available.',
    AniListFailureType.parseError =>
      'The anime catalogue answer could not be read.',
    AniListFailureType.cancelled =>
      'The anime catalogue request was cancelled.',
  };
}

final class AniListFailure extends SpectaFailure {
  AniListFailure({
    required this.type,
    String? message,
    this.operation,
    this.statusCode,
    this.detail,
    bool? isRetryable,
  }) : super(
         message ?? type.message,
         isRetryable: isRetryable ?? type.retryable,
       );

  final AniListFailureType type;
  final String? operation;
  final int? statusCode;
  final String? detail;

  @override
  String toString() => 'AniListFailure(${type.code}, $message)';
}

/// A TMDB catalogue request failed in a controlled, structured way
/// (Phase 3 — TMDB content foundation).
///
/// TMDB is SPECTA's metadata/catalogue provider, NOT an extension: a TMDB
/// failure must never be confused with an [ExtensionFailure] (nothing about
/// it belongs to an extension), so it gets its own category, mirroring the
/// [DownloadFailure] / [PlaybackFailure] discipline.
///
/// SECRET HYGIENE: [detail] must NEVER contain the API key or a full request
/// URI (the key is sent as a query parameter). [TmdbClient] therefore records
/// only the endpoint path and status code — see [TmdbFailure.endpoint].
enum TmdbFailureType {
  /// The build was produced without `--dart-define=TMDB_API_KEY=...`, so there
  /// is no credential to use. This is a build-configuration state, not
  /// something a user can fix, which is why it has no Settings remedy.
  notConfigured('NOT_CONFIGURED'),

  /// TMDB rejected the build-time credential (HTTP 401).
  invalidKey('INVALID_KEY'),

  /// The request never reached TMDB (DNS, socket, TLS).
  networkError('NETWORK_ERROR', retryable: true),

  /// The request exceeded SPECTA's deadline.
  timeout('TIMEOUT', retryable: true),

  /// TMDB rate-limited the request (HTTP 429).
  rateLimited('RATE_LIMITED', retryable: true),

  /// TMDB answered 5xx — plausibly transient.
  serverError('SERVER_ERROR', retryable: true),

  /// TMDB answered with an unexpected non-success status.
  httpError('HTTP_ERROR'),

  /// The requested title/season does not exist (HTTP 404).
  notFound('NOT_FOUND'),

  /// The response was not usable JSON in the documented shape.
  parseError('PARSE_ERROR'),

  /// The caller abandoned the request (surface left, query replaced).
  cancelled('CANCELLED');

  const TmdbFailureType(this.code, {this.retryable = false});

  /// Canonical, stable name for diagnostics.
  final String code;

  /// Whether retrying the same request can plausibly succeed.
  final bool retryable;

  /// User-facing, non-technical wording. Never mentions HTTP, keys or hosts.
  String get message => switch (this) {
    TmdbFailureType.notConfigured =>
      'The catalogue is unavailable in this build.',
    TmdbFailureType.invalidKey =>
      'The catalogue could not be loaded right now. Try again later.',
    TmdbFailureType.networkError =>
      'The catalogue could not be reached. Check your connection.',
    TmdbFailureType.timeout =>
      'The catalogue took too long to answer. Try again.',
    TmdbFailureType.rateLimited =>
      'TMDB is temporarily limiting requests. Try again in a moment.',
    TmdbFailureType.serverError =>
      'TMDB reported a problem on its side. Try again later.',
    TmdbFailureType.httpError => 'The catalogue request was refused.',
    TmdbFailureType.notFound => 'That title is no longer available on TMDB.',
    TmdbFailureType.parseError => 'The catalogue answer could not be read.',
    TmdbFailureType.cancelled => 'The request was cancelled.',
  };
}

final class TmdbFailure extends SpectaFailure {
  // Not const: the default retryability is read from [type] at runtime.
  TmdbFailure({
    required this.type,
    String? message,
    this.endpoint,
    this.statusCode,
    this.detail,
    bool? isRetryable,
  }) : super(
         message ?? type.message,
         isRetryable: isRetryable ?? type.retryable,
       );

  final TmdbFailureType type;

  /// Endpoint PATH only (e.g. `/movie/popular`) — never a full URI, because a
  /// full URI would carry the API key.
  final String? endpoint;

  /// HTTP status, when the failure came from a response.
  final int? statusCode;

  /// Developer-only diagnostics. MUST NOT contain the API key. Never rendered
  /// on an ordinary user screen.
  final String? detail;

  /// Structured diagnostics record for internal logging (key-free by
  /// construction).
  Map<String, Object?> toDiagnostics() => <String, Object?>{
    'errorType': type.code,
    'message': message,
    if (endpoint != null) 'endpoint': endpoint,
    if (statusCode != null) 'status': statusCode,
    if (detail != null) 'detail': detail,
  };

  @override
  String toString() =>
      '${type.code}${endpoint == null ? '' : ' $endpoint'}'
      '${statusCode == null ? '' : ' ($statusCode)'} $message';
}

/// Failure categories for the TVMaze source.
///
/// TVMaze is a SECONDARY, CREDENTIAL-FREE catalogue, not an extension and not
/// TMDB. It gets its own category for the same reason [TmdbFailure] does: a
/// TVMaze outage must never be reported as a TMDB key problem, and neither may
/// be confused with an [ExtensionFailure].
///
/// Notably there is NO `notConfigured` and NO `invalidKey`: TVMaze requires no
/// credential, so a credential-shaped failure is not expressible.
///
/// TVMaze COVERS SERIES ONLY. There is deliberately no movie failure path.
enum TvmazeFailureType {
  /// The request never reached TVMaze (DNS, socket, TLS).
  networkError('NETWORK_ERROR', retryable: true),

  /// The request exceeded SPECTA's deadline.
  timeout('TIMEOUT', retryable: true),

  /// TVMaze rate-limited the request (HTTP 429).
  rateLimited('RATE_LIMITED', retryable: true),

  /// TVMaze answered 5xx — plausibly transient.
  serverError('SERVER_ERROR', retryable: true),

  /// TVMaze answered with an unexpected non-success status.
  httpError('HTTP_ERROR'),

  /// The requested show does not exist (HTTP 404).
  notFound('NOT_FOUND'),

  /// The response was not usable JSON in the documented shape.
  parseError('PARSE_ERROR'),

  /// The caller abandoned the request.
  cancelled('CANCELLED');

  const TvmazeFailureType(this.code, {this.retryable = false});

  /// Canonical, stable name for diagnostics.
  final String code;

  /// Whether retrying the same request can plausibly succeed.
  final bool retryable;

  /// User-facing, non-technical wording. Never mentions HTTP or hosts.
  String get message => switch (this) {
    TvmazeFailureType.networkError =>
      'The show guide could not be reached. Check your connection.',
    TvmazeFailureType.timeout =>
      'The show guide took too long to answer. Try again.',
    TvmazeFailureType.rateLimited =>
      'The show guide is temporarily limiting requests. Try again in a moment.',
    TvmazeFailureType.serverError =>
      'The show guide reported a problem on its side. Try again later.',
    TvmazeFailureType.httpError => 'The show guide request was refused.',
    TvmazeFailureType.notFound => 'That show is no longer available.',
    TvmazeFailureType.parseError => 'The show guide answer could not be read.',
    TvmazeFailureType.cancelled => 'The request was cancelled.',
  };
}

final class TvmazeFailure extends SpectaFailure {
  // Not const: the default retryability is read from [type] at runtime.
  TvmazeFailure({
    required this.type,
    String? message,
    this.endpoint,
    this.statusCode,
    this.detail,
    bool? isRetryable,
  }) : super(
         message ?? type.message,
         isRetryable: isRetryable ?? type.retryable,
       );

  final TvmazeFailureType type;

  /// Endpoint PATH only (e.g. `/shows/1`). TVMaze needs no credential, so a full
  /// URI would carry nothing secret — the path-only rule is kept for symmetry
  /// with [TmdbFailure] and to avoid echoing arbitrary query text.
  final String? endpoint;

  /// HTTP status, when the failure came from a response.
  final int? statusCode;

  /// Developer-only diagnostics. Never rendered on an ordinary user screen.
  final String? detail;

  /// Structured diagnostics record for internal logging.
  Map<String, Object?> toDiagnostics() => <String, Object?>{
    'errorType': type.code,
    'message': message,
    if (endpoint != null) 'endpoint': endpoint,
    if (statusCode != null) 'status': statusCode,
    if (detail != null) 'detail': detail,
  };

  @override
  String toString() =>
      '${type.code}${endpoint == null ? '' : ' $endpoint'}'
      '${statusCode == null ? '' : ' ($statusCode)'} $message';
}
