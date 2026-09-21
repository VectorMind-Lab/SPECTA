import '../errors/specta_failure.dart';
import '../sources/source_manager.dart';
import '../sources/source_pool.dart';
import '../extensions/manager/extension_manager.dart';
import 'download_manager.dart';
import 'download_models.dart';

/// Phase 2G-C production [DownloadSourceResolver]: real source recovery
/// through SPECTA's existing source-resolution architecture.
///
/// Recovery semantics (2G-C §12/§23/§24/§25):
/// - The session pool captured at enqueue time is the FRESHEST user-provided
///   resolution and is served as-is — but ONLY while the previous attempt did
///   not fail with a source-classified failure. After such a failure the URL
///   itself is suspect: the captured pool is stale by definition and is
///   discarded, never reused.
/// - When no session pool exists (the normal post-restart case — pools are
///   in-memory by design) the persisted provenance
///   (`sourceExtensionId` + `sourceReference`) is re-resolved through the
///   real [SourceManager]: the extension is asked again for `getSources`,
///   candidates are re-validated/re-ranked by SPECTA, and a fresh
///   [SourcePool] comes back. The old URL is never persisted as authority,
///   so there is nothing to "un-persist" — the provenance is the authority.
/// - The resolver answers null when re-resolution fails or the record lacks
///   provenance; the manager's bounded retry budget decides what that means
///   (never an unbounded refresh loop — §13).
///
/// Boundary discipline: this resolver calls SPECTA's SourceManager — it never
/// touches extensions directly, never scrapes URLs, and is never consulted by
/// the engine adapter (the engine receives only the resolved attempt input).
final class SourceManagerDownloadResolver implements DownloadSourceResolver {
  SourceManagerDownloadResolver({required this.extensionManager});

  /// SPECTA's extension manager (the same instance the SourceManager
  /// pipeline uses). Injectable function so the resolver can be constructed
  /// before the manager is ready and fetched lazily at first use.
  final ExtensionManager Function() extensionManager;

  /// Pools captured at enqueue/re-enqueue time within this manager session.
  final Map<String, SourcePool> _pools = <String, SourcePool>{};

  @override
  void rememberPool(String id, SourcePool pool) => _pools[id] = pool;

  @override
  void forgetPool(String id) => _pools.remove(id);

  @override
  Future<SourcePool?> resolveSource(
    DownloadRecord record, {
    DownloadFailure? lastFailure,
  }) async {
    final SourcePool? captured = _pools[record.id];
    final bool sourceInvalidated = lastFailure != null &&
        DownloadSourceResolver.sourceInvalidatingFailures
            .contains(lastFailure.type);
    if (captured != null && !sourceInvalidated) {
      return captured;
    }
    if (captured != null && sourceInvalidated) {
      // The URL the pool was built from just failed as unusable. Drop it and
      // re-resolve fresh — this is the whole point of source recovery.
      _pools.remove(record.id);
    }
    return _resolveThroughSourceManager(record);
  }

  /// Real re-resolution through the SourceManager using the persisted
  /// provenance. Never throws; null means "cannot resolve right now".
  Future<SourcePool?> _resolveThroughSourceManager(
    DownloadRecord record,
  ) async {
    final String? extensionId = record.sourceExtensionId;
    final String? reference = record.sourceReference;
    if (extensionId == null ||
        extensionId.isEmpty ||
        reference == null ||
        reference.isEmpty) {
      // No provenance to re-resolve from. Honest answer: unresolvable —
      // the manager's retry policy classifies `sourcesExhausted`.
      return null;
    }
    try {
      return await SourceManager.resolve(
        reference: reference,
        extensions: <String, String>{extensionId: reference},
        manager: extensionManager(),
      );
    } on Object {
      // The pipeline isolates extension failures internally; a throw here
      // would be an infrastructure problem. The manager decides what an
      // unresolvable download means — the resolver only reports.
      return null;
    }
  }
}
