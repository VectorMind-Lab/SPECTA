import '../discovery/discovery_models.dart';
import '../errors/specta_failure.dart';
import '../extensions/contract/result_models.dart';
import '../sources/source_pool.dart';

/// Phase 2G — the SPECTA download system's own models.
///
/// Boundary discipline:
/// - Download identity IS the existing media identity (2C metadata key,
///   episode-qualified exactly like the 2F watch-progress identity). No
///   second identity model is invented, and a source URL is never identity.
/// - Every terminal condition is data ([DownloadFailure]), never an
///   exception escaping into the UI.
abstract final class DownloadIdentity {
  /// The download identity for a movie: the parent media key itself.
  static String forMovie(String mediaKey) => mediaKey;

  /// The download identity for an episode: `<mediaKey>|s<S>e<E>` — the same
  /// episode-qualified identity the player and watch progress already use.
  static String forEpisode(String mediaKey, int season, int episode) =>
      '$mediaKey|s${season}e$episode';

  /// True when [id] is an episode identity (contains the `|s…e…` suffix and
  /// has the 3-part media-key prefix + episode part).
  static bool isEpisode(String id) {
    final int last = id.lastIndexOf('|');
    if (last < 0) return false;
    return RegExp(r'^s\d+e\d+$').hasMatch(id.substring(last + 1));
  }
}

/// The explicit, testable download state machine.
///
/// Allowed transitions (enforced by [DownloadStateMachine.canTransition]):
///   queued      → downloading, cancelled
///   downloading → paused, completed, failed, cancelled
///   paused      → downloading, queued (explicit resume routed through the
///                 queue when SPECTA's concurrency policy has no free slot),
///                 cancelled
///   failed      → queued (intentional retry), cancelled
///   cancelled   → queued (intentional retry)
///   completed   → (terminal; removal is the user's explicit delete)
///
/// Process-death recovery deliberately uses NO new transition: a persisted
/// `downloading` record that the engine no longer holds is classified as an
/// `interrupted` failure (downloading → failed) and re-queued by the bounded
/// retry policy (failed → queued).
enum DownloadStatus {
  queued('queued'),
  downloading('downloading'),
  paused('paused'),
  completed('completed'),
  failed('failed'),
  cancelled('cancelled');

  const DownloadStatus(this.code);

  /// Canonical persisted code (matches the DB rows exactly).
  final String code;

  static DownloadStatus? fromCode(String? code) {
    for (final DownloadStatus s in DownloadStatus.values) {
      if (s.code == code) return s;
    }
    return null;
  }

  bool get isActive => this == queued || this == downloading || this == paused;
  bool get isTerminal => this == completed || this == failed || this == cancelled;
}

/// The download state machine as data: which transitions are allowed.
abstract final class DownloadStateMachine {
  static const Map<DownloadStatus, Set<DownloadStatus>> _allowed =
      <DownloadStatus, Set<DownloadStatus>>{
    DownloadStatus.queued: <DownloadStatus>{
      DownloadStatus.downloading,
      DownloadStatus.cancelled,
    },
    DownloadStatus.downloading: <DownloadStatus>{
      DownloadStatus.paused,
      DownloadStatus.completed,
      DownloadStatus.failed,
      DownloadStatus.cancelled,
    },
    DownloadStatus.paused: <DownloadStatus>{
      DownloadStatus.downloading,
      // Explicit user resume when SPECTA's concurrency policy has no free
      // slot: the download joins the queue (fair FIFO order) instead of
      // silently exceeding the limit.
      DownloadStatus.queued,
      DownloadStatus.cancelled,
    },
    DownloadStatus.failed: <DownloadStatus>{
      DownloadStatus.queued,
      DownloadStatus.cancelled,
    },
    DownloadStatus.cancelled: <DownloadStatus>{
      DownloadStatus.queued,
    },
    DownloadStatus.completed: <DownloadStatus>{},
  };

  /// Whether [from] may move to [to]. Illegal transitions are refused by the
  /// manager instead of silently rewritten.
  static bool canTransition(DownloadStatus from, DownloadStatus to) =>
      _allowed[from]!.contains(to);
}

/// Why a queued job is not being started right now. Descriptive data — the
/// state stays `queued`; this is displayed so waiting is never silent.
enum DownloadWaitReason {
  /// The Wi-Fi-only policy is on and the current network is metered/unknown.
  waitingForWifi('waitingForWifi'),

  /// Free storage is below the requirement for the known size.
  insufficientStorage('insufficientStorage'),

  /// The queue is full (concurrency limit) — nothing is wrong.
  waitingForSlot('waitingForSlot');

  const DownloadWaitReason(this.code);
  final String code;

  static DownloadWaitReason? fromCode(String? code) {
    for (final DownloadWaitReason r in DownloadWaitReason.values) {
      if (r.code == code) return r;
    }
    return null;
  }

  /// User-facing, non-technical wording.
  String get message => switch (this) {
        DownloadWaitReason.waitingForWifi => 'Waiting for Wi-Fi',
        DownloadWaitReason.insufficientStorage => 'Not enough free storage',
        DownloadWaitReason.waitingForSlot => 'Waiting in queue',
      };
}

/// Network policy for downloads. Default is conservative (Wi-Fi only).
enum DownloadNetworkPolicy {
  /// Never download over metered (mobile) data. The default.
  wifiOnly('wifiOnly'),

  /// Wi-Fi and mobile data are both acceptable.
  wifiAndMobile('wifiAndMobile');

  const DownloadNetworkPolicy(this.code);
  final String code;

  static DownloadNetworkPolicy fromCode(String? code) {
    for (final DownloadNetworkPolicy p in DownloadNetworkPolicy.values) {
      if (p.code == code) return p;
    }
    // The persisted default is conservative, never permissive.
    return DownloadNetworkPolicy.wifiOnly;
  }
}

/// What the platform reports about the current network. `unknown` means the
/// probe could not answer (no capability, platform channel failure) — the
/// policy then applies conservatively instead of optimistically.
enum NetworkAccess {
  none('none'),
  wifi('wifi'),
  mobile('mobile'),
  ethernet('ethernet'),
  other('other'),
  unknown('unknown');

  const NetworkAccess(this.code);
  final String code;

  static NetworkAccess fromCode(String? code) {
    for (final NetworkAccess a in NetworkAccess.values) {
      if (a.code == code) return a;
    }
    return NetworkAccess.unknown;
  }

  bool get isMeteredLike => this == mobile || this == unknown || this == none;
}

/// The policy verdict for starting/resuming a download. Data, not exception.
enum NetworkPolicyVerdict {
  /// The current network satisfies the policy.
  allowed,

  /// The policy forbids downloading on the current network.
  blockedMetered,

  /// No network at all.
  blockedOffline,

  /// The platform could not answer; the conservative policy treats this as
  /// blocked when Wi-Fi-only is selected.
  blockedUnknown;

  bool get isAllowed => this == NetworkPolicyVerdict.allowed;

  DownloadWaitReason? get waitReason => switch (this) {
        NetworkPolicyVerdict.allowed => null,
        NetworkPolicyVerdict.blockedMetered => DownloadWaitReason.waitingForWifi,
        NetworkPolicyVerdict.blockedOffline => DownloadWaitReason.waitingForWifi,
        NetworkPolicyVerdict.blockedUnknown => DownloadWaitReason.waitingForWifi,
      };
}

/// Evaluates [policy] against [access]. Pure and unit-tested.
NetworkPolicyVerdict evaluateNetworkPolicy(
  DownloadNetworkPolicy policy,
  NetworkAccess access,
) {
  if (access == NetworkAccess.none) return NetworkPolicyVerdict.blockedOffline;
  if (policy == DownloadNetworkPolicy.wifiAndMobile) {
    return NetworkPolicyVerdict.allowed;
  }
  // Wi-Fi-only: any network SPECTA cannot prove is unmetered is blocked.
  return access == NetworkAccess.wifi || access == NetworkAccess.ethernet
      ? NetworkPolicyVerdict.allowed
      : NetworkPolicyVerdict.blockedUnknown;
}

/// The queued request the details surface hands to the download manager.
///
/// It carries exactly what the pipeline needs: identity, display metadata,
/// the resolution inputs SPECTA already owns (extension id → reference), and
/// the resolved 2D pool. It never carries a *single* URL as identity.
final class DownloadRequest {
  const DownloadRequest({
    required this.id,
    required this.mediaKey,
    required this.mediaType,
    required this.title,
    this.subtitleLine,
    this.seasonNumber,
    this.episodeNumber,
    required this.extensions,
    required this.pool,
  });

  /// Stable download identity: `<mediaKey>` for a movie, `<mediaKey>|s<S>e<E>`
  /// for an episode.
  final String id;

  /// The parent work's canonical metadata key.
  final String mediaKey;
  final MediaType mediaType;

  /// Display metadata for the download UI (never a provider URL).
  final String title;
  final String? subtitleLine;
  final int? seasonNumber;
  final int? episodeNumber;

  /// The extension ids + references the pool was resolved over — the same
  /// resolution inputs the playback pipeline uses (provenance, not URLs of
  /// media files).
  final Map<String, String> extensions;

  /// The resolved 2D pool: SPECTA's ranked, validated candidates. The
  /// download system consumes it; it never re-ranks or re-validates.
  final SourcePool pool;
}

/// One durable download record — the DB-shaped state the UI renders.
final class DownloadRecord {
  const DownloadRecord({
    required this.id,
    required this.mediaKey,
    required this.mediaType,
    required this.title,
    this.subtitleLine,
    this.seasonNumber,
    this.episodeNumber,
    required this.status,
    this.waitReason,
    required this.bytesDownloaded,
    this.totalBytes,
    required this.filePath,
    this.sourceExtensionId,
    this.sourceReference,
    this.sourceLabel,
    required this.attempt,
    this.failure,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });

  final String id;
  final String mediaKey;
  final MediaType mediaType;
  final String title;
  final String? subtitleLine;
  final int? seasonNumber;
  final int? episodeNumber;
  final DownloadStatus status;

  /// Why the queue is not starting this job (null when it is running or
  /// terminal).
  final DownloadWaitReason? waitReason;

  final int bytesDownloaded;

  /// Declared total, or null when unknown — the UI must not invent one.
  final int? totalBytes;

  /// Final completed-media path.
  final String filePath;

  /// Provenance of the last attempt (never a URL).
  final String? sourceExtensionId;
  final String? sourceReference;

  /// Neutral label of the last attempt (e.g. `Server 1`), display only.
  final String? sourceLabel;

  /// Auto-retry budget used in the current run.
  final int attempt;

  /// The structured failure — only for [DownloadStatus.failed].
  final DownloadFailure? failure;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  bool get isEpisode => seasonNumber != null && episodeNumber != null;

  /// Progress fraction when the total is known and positive; null otherwise
  /// (never a fabricated percentage).
  double? get fraction {
    final int? total = totalBytes;
    if (total == null || total <= 0) return null;
    return (bytesDownloaded / total).clamp(0.0, 1.0);
  }

  DownloadRecord copyWith({
    DownloadStatus? status,
    Object? waitReason = _unset,
    int? bytesDownloaded,
    Object? totalBytes = _unset,
    Object? sourceExtensionId = _unset,
    Object? sourceReference = _unset,
    Object? sourceLabel = _unset,
    int? attempt,
    Object? failure = _unset,
    DateTime? updatedAt,
    Object? completedAt = _unset,
  }) {
    return DownloadRecord(
      id: id,
      mediaKey: mediaKey,
      mediaType: mediaType,
      title: title,
      subtitleLine: subtitleLine,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      status: status ?? this.status,
      waitReason: identical(waitReason, _unset)
          ? this.waitReason
          : waitReason as DownloadWaitReason?,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      totalBytes: identical(totalBytes, _unset)
          ? this.totalBytes
          : totalBytes as int?,
      filePath: filePath,
      sourceExtensionId: identical(sourceExtensionId, _unset)
          ? this.sourceExtensionId
          : sourceExtensionId as String?,
      sourceReference: identical(sourceReference, _unset)
          ? this.sourceReference
          : sourceReference as String?,
      sourceLabel: identical(sourceLabel, _unset)
          ? this.sourceLabel
          : sourceLabel as String?,
      attempt: attempt ?? this.attempt,
      failure: identical(failure, _unset)
          ? this.failure
          : failure as DownloadFailure?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: identical(completedAt, _unset)
          ? this.completedAt
          : completedAt as DateTime?,
    );
  }

  static const Object _unset = Object();

  @override
  String toString() =>
      'DownloadRecord($id, ${status.code}, $bytesDownloaded'
      '${totalBytes == null ? '?' : '/$totalBytes'})';
}

/// The in-flight attempt input handed to the download engine.
///
/// The engine is identified per download ([downloadId]) so the manager can
/// address control operations (pause/cancel) and match async results/events
/// back to the download — SPECTA's own identity crosses the seam; the engine
/// never issues one of its own that the domain would have to store.
final class DownloadAttemptInput {
  const DownloadAttemptInput({
    required this.downloadId,
    required this.url,
    required this.partPath,
    this.resumeFrom = 0,
    this.headers = const <String, String>{},
  });

  /// The SPECTA download identity this attempt belongs to. In-memory only.
  final String downloadId;

  /// The candidate's direct media URL (mp4). Held in memory for the attempt
  /// only — never persisted as identity.
  final String url;

  /// The safe partial file the bytes are written into.
  final String partPath;

  /// Bytes already present in the part file this attempt may continue from.
  final int resumeFrom;

  /// The candidate's own headers (e.g. User-Agent/Referer). In-memory only;
  /// never persisted (they may carry credentials).
  final Map<String, String> headers;
}

/// How one engine attempt ended.
enum DownloadAttemptOutcomeKind {
  /// The file was fully received and verified; the engine has already
  /// flushed and left the final rename to the manager.
  completed,

  /// The user (or the manager) paused the attempt; bytes are safe on disk.
  paused,

  /// The attempt was cancelled; the part file is left for cleanup.
  cancelled,

  /// The attempt failed with a structured failure.
  failed,
}

final class DownloadAttemptResult {
  const DownloadAttemptResult.completed(int bytes, {this.totalBytes})
      : kind = DownloadAttemptOutcomeKind.completed,
        bytesOnDisk = bytes,
        failure = null;

  const DownloadAttemptResult.paused(int bytes)
      : kind = DownloadAttemptOutcomeKind.paused,
        bytesOnDisk = bytes,
        totalBytes = null,
        failure = null;

  const DownloadAttemptResult.cancelled(int bytes)
      : kind = DownloadAttemptOutcomeKind.cancelled,
        bytesOnDisk = bytes,
        totalBytes = null,
        failure = null;

  const DownloadAttemptResult.failed(this.failure, int bytes)
      : kind = DownloadAttemptOutcomeKind.failed,
        bytesOnDisk = bytes,
        totalBytes = null;

  final DownloadAttemptOutcomeKind kind;

  /// Bytes actually safe on disk when the attempt ended.
  final int bytesOnDisk;

  /// The declared total when the server provided one during this attempt.
  final int? totalBytes;

  final DownloadFailure? failure;

  bool get isCompleted => kind == DownloadAttemptOutcomeKind.completed;
  bool get isPaused => kind == DownloadAttemptOutcomeKind.paused;
  bool get isCancelled => kind == DownloadAttemptOutcomeKind.cancelled;
  bool get isFailed => kind == DownloadAttemptOutcomeKind.failed;
}

/// Live progress of one running attempt. Bytes only when the size is
/// unknown — the UI never receives an invented percentage.
final class DownloadProgress {
  const DownloadProgress({required this.bytesOnDisk, this.totalBytes});

  final int bytesOnDisk;
  final int? totalBytes;

  double? get fraction {
    final int? total = totalBytes;
    if (total == null || total <= 0) return null;
    return (bytesOnDisk / total).clamp(0.0, 1.0);
  }
}

/// The safe filename stem for a download, derived from the identity — never
/// from a URL. Everything outside `[A-Za-z0-9 _-]` (including `/`, `\`, `..`
/// separators and the `|` identity separator) becomes `_`, whitespace
/// collapses, and the result is capped so no filesystem chokes on it.
String downloadFileStem(String id, String title) {
  String sanitize(String raw) => raw
      .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String stem = sanitize(title);
  if (stem.isEmpty) stem = 'download';
  if (stem.length > 80) stem = stem.substring(0, 80).trim();
  return '$stem (${_fnv1a32(id).toRadixString(36)})';
}

/// The safe partial-file path for a download whose final path is [filePath].
///
/// Persistence-contract discipline: the `.part` path is DERIVED, never
/// stored, so it cannot drift from the final path and is always reconstructable
/// from the persisted `filePath` alone after a restart. Only the completed
/// download is ever found at [filePath]; incomplete bytes live at the derived
/// `.part` path until the engine's final rename makes the file complete.
String downloadPartPathFor(String filePath) => '$filePath.part';

/// Deterministic FNV-1a 32-bit — a stable, dependency-free filename salt so
/// two titles that sanitize identically still cannot share one file.
int _fnv1a32(String input) {
  int hash = 0x811c9dc5;
  for (final int unit in input.codeUnits) {
    hash ^= unit & 0xFF;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
    hash ^= (unit >> 8) & 0xFF;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// Builds the enqueue request for a movie from SPECTA's own canonical layers.
/// Resolution inputs and pool come from the existing pipeline — this is a
/// pure adapter, not a second resolution path.
DownloadRequest buildMovieDownloadRequest({
  required MetadataAdapter metadata,
  required SourcePool pool,
}) {
  final Map<String, String> extensions = <String, String>{
    for (final DiscoveryReference r in metadata.references)
      r.extensionId: r.url,
  };
  return DownloadRequest(
    id: DownloadIdentity.forMovie(metadata.key),
    mediaKey: metadata.key,
    mediaType: MediaType.movie,
    title: metadata.title,
    extensions: extensions,
    pool: pool,
  );
}

/// Builds the enqueue request for one episode.
DownloadRequest buildEpisodeDownloadRequest({
  required MetadataAdapter metadata,
  required EpisodeAdapter episode,
  required SourcePool pool,
}) {
  final Map<String, String> extensions = <String, String>{
    for (final DiscoveryReference r in metadata.references)
      r.extensionId: episode.referenceUrl,
  };
  return DownloadRequest(
    id: DownloadIdentity.forEpisode(
      metadata.key,
      episode.seasonNumber,
      episode.episodeNumber,
    ),
    mediaKey: metadata.key,
    mediaType: MediaType.series,
    title: metadata.title,
    subtitleLine:
        'Season ${episode.seasonNumber} · Episode ${episode.episodeNumber}',
    seasonNumber: episode.seasonNumber,
    episodeNumber: episode.episodeNumber,
    extensions: extensions,
    pool: pool,
  );
}

/// The thin view of metadata the download entry needs, so the entry stays
/// decoupled from the full [MetadataItem] shape (and trivially testable).
abstract interface class MetadataAdapter {
  String get key;
  String get title;
  List<DiscoveryReference> get references;
}

/// The thin view of an episode the download entry needs.
abstract interface class EpisodeAdapter {
  int get seasonNumber;
  int get episodeNumber;
  String get referenceUrl;
}
