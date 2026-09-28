import 'dart:io';

import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/catalogue/extension_catalogue.dart';
import 'package:specta/core/extensions/distribution/dart_io_extension_download_transport.dart';
import 'package:specta/core/extensions/distribution/extension_downloader.dart';
import 'package:specta/core/extensions/distribution/extension_storage.dart';
import 'package:specta/core/extensions/identity/extension_health.dart';
import 'package:specta/core/extensions/identity/source_node.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manifest.dart';

import 'extension_manager.dart';
import 'extension_record.dart';

/// One installed extension as the application layer sees it.
///
/// [ExtensionRecord] is the persisted installation state; [health] is the
/// descriptive classification SPECTA derives from facts it already holds
/// (enabled flag, API compatibility, recent failures). Bundling them in one
/// value keeps the UI and any future orchestration layer reading a single,
/// authoritative view instead of re-deriving health ad hoc.
final class ManagedExtension {
  const ManagedExtension({required this.record, required this.health});

  /// The validated, persisted installation record.
  final ExtensionRecord record;

  /// Descriptive health. Never a controller — see [ExtensionHealthRules].
  final ExtensionHealthState health;

  String get id => record.id;
  String get name => record.name;
  String get version => record.version;
  String get author => record.author;
  int get apiVersion => record.apiVersion;
  String get contentType => record.contentType;
  String get filePath => record.filePath;
  TrustLevel get trustLevel => record.trustLevel;
  bool get enabled => record.enabled;
  SourceNode? get node => record.node;
  String? get nodeLabel => record.node?.label;
  bool get nodeLocked => record.nodeLocked;
  int get nodeOrder => record.nodeOrder;
  ExtensionHealth get healthState => health.health;
}

/// The application-facing boundary for extension installation and lifecycle.
///
/// This is deliberately a thin wrapper over [ExtensionManager]: the manager
/// remains the single owner of manifest validation, trust classification,
/// runtime creation and persistence. The service exists so that UI state and
/// future orchestration code depend on an application-level contract
/// (install / list / enable / disable / uninstall / shutdown) rather than
/// re-implementing those steps — and so nothing outside the manager can
/// bypass manifest validation or signature verification.
///
/// It never touches files itself: [installFromFile] hands the path to the
/// manager, which reads, parses, validates, verifies the signature, checks API
/// compatibility and only then persists. A malformed or untrusted file never
/// reaches the registry (a malformed one is rejected outright; an unsigned or
/// badly signed one is installed as [TrustLevel.unverified], never Official).
final class ExtensionLifecycleService {
  ExtensionLifecycleService({
    required this.manager,
    ExtensionDownloader? downloader,
    ExtensionStorage? storage,
  }) : _downloader =
           downloader ??
           ExtensionDownloader(DartIoExtensionDownloadTransport()),
       _storage = storage ?? const AppPrivateExtensionStorage();

  final ExtensionManager manager;

  /// Fetches extension bytes. Distribution only — never trust.
  final ExtensionDownloader _downloader;

  /// Where downloaded bytes are written before import.
  final ExtensionStorage _storage;

  /// Installs (or replaces) an extension from a local `.js` file.
  ///
  /// Returns the installed record, or a structured failure describing exactly
  /// why the file was rejected. Failure is safe: the registry is left
  /// untouched unless the file passed every gate.
  Future<SpectaResult<ExtensionRecord>> installFromFile(String filePath) =>
      manager.importExtension(filePath: filePath);

  /// Installs an extension from an HTTPS URL.
  ///
  /// The downloaded bytes are written into app-private storage and then handed
  /// to [installFromFile] — deliberately the SAME entry point the device picker
  /// uses. That is what makes the three installation paths (device import,
  /// direct URL, official catalogue) converge on one manifest/compatibility/
  /// trust pipeline instead of parallel ones.
  ///
  /// [expectedSha256] is an optional TRANSPORT checksum published by the
  /// catalogue. It is not a trust signal: the manifest signature is still
  /// verified by the manager.
  Future<SpectaResult<ExtensionRecord>> installFromUrl(
    String url, {
    String? expectedSha256,
    int? expectedSizeBytes,
  }) async {
    final SpectaResult<DownloadedExtension> download = await _downloader
        .download(
          url,
          expectedSha256: expectedSha256,
          expectedSizeBytes: expectedSizeBytes,
        );
    if (download.isErr) return Err<ExtensionRecord>(download.failureOrNull!);

    final SpectaResult<Directory> directory = await _storage.resolveDirectory();
    if (directory.isErr) {
      return Err<ExtensionRecord>(directory.failureOrNull!);
    }

    // The id used for the file name is the one the manager will install under.
    // It is taken from the downloaded manifest, and sanitised before use, so a
    // hostile id cannot write outside the target directory.
    final String code = download.valueOrNull!.sourceCode;
    final String? extensionId = _idFromSource(code);
    if (extensionId == null) {
      // The download SUCCEEDED — the bytes arrived. What is missing is a
      // `// ==SpectaExtension==` manifest, so this file simply is not an
      // extension. This used to report `tooLarge`, which told the user their
      // file was too big when it was in fact a 343-byte JSON catalogue: the
      // overwhelmingly common cause is a repo.json pasted into "Install from a
      // link". The explanation comes from the same helper the manager uses, so
      // both routes describe the mistake identically.
      return Err<ExtensionRecord>(
        ExtensionDistributionFailure(
          type: ExtensionDistributionFailureType.notAnExtension,
          stage: 'verify',
          message: describeUnimportableSource(
            code,
            ManifestParseException(
              'Downloaded file has no readable manifest id.',
            ),
          ),
          detail: 'Downloaded file has no readable manifest id.',
        ),
      );
    }

    final SpectaResult<String> written = await ExtensionFileStore.write(
      directory.valueOrNull!,
      extensionId,
      code,
    );
    if (written.isErr) return Err<ExtensionRecord>(written.failureOrNull!);

    // Converges with the device-import path from here on.
    return installFromFile(written.valueOrNull!);
  }

  /// Installs one catalogue entry.
  ///
  /// Identical to [installFromUrl] apart from reading the entry's claims. The
  /// catalogue is NOT trusted: the entry only supplies a URL and an optional
  /// checksum, and everything else is re-derived by the manager.
  Future<SpectaResult<ExtensionRecord>> installFromCatalogueEntry(
    ExtensionCatalogueEntry entry,
  ) => installFromUrl(
    entry.downloadUrl,
    expectedSha256: entry.sha256,
    expectedSizeBytes: entry.sizeBytes,
  );

  /// Reads the manifest id out of downloaded source, without validating it.
  ///
  /// Used only to choose a file name. A null result (unparseable manifest) is
  /// rejected here; a WRONG id is caught by the manager, which installs under
  /// the id in the manifest itself.
  static String? _idFromSource(String sourceCode) {
    try {
      return ManifestParser.parse(sourceCode).id;
    } on Object {
      return null;
    }
  }

  /// Returns every installed extension (enabled and disabled), each with its
  /// derived health, in display order.
  ///
  /// Ordering is by `nodeOrder` — the user's own arrangement — then by node
  /// label, then by id. It is deliberately NOT ordered by name: the source
  /// supplies its own name, so ordering by it would let a provider decide the
  /// order of the user's list, and would put a site name into the UI's most
  /// prominent position.
  ///
  /// A missing node backfills first, so a database written before schema v9
  /// acquires labels on first read rather than rendering blank rows.
  Future<List<ManagedExtension>> installed() async {
    await manager.ensureNodesAssigned();
    final List<ExtensionRecord> records = await manager.getAllExtensions();
    final List<ManagedExtension> managed = <ManagedExtension>[];
    for (final ExtensionRecord record in records) {
      final SpectaResult<ExtensionHealthState> health = await manager.healthOf(
        record.id,
      );
      managed.add(
        ManagedExtension(
          record: record,
          health: health.valueOrNull ?? _fallbackHealth(record),
        ),
      );
    }
    managed.sort(_byDisplayOrder);
    return managed;
  }

  /// The display ordering, mirroring the manager's `reorder` exactly.
  ///
  /// The two must agree: if the list sorted by one rule and a drag wrote
  /// positions for another, a node would jump to a different place than the
  /// one the user dropped it on.
  static int _byDisplayOrder(ManagedExtension a, ManagedExtension b) {
    final int byOrder = a.nodeOrder.compareTo(b.nodeOrder);
    if (byOrder != 0) return byOrder;
    final int byLabel = (a.nodeLabel ?? '').compareTo(b.nodeLabel ?? '');
    if (byLabel != 0) return byLabel;
    return a.id.compareTo(b.id);
  }

  /// Moves [id] to [index] in the user's display order and persists it.
  ///
  /// Node 0 is not pinned: it moves like any other node, and stays
  /// undeletable wherever it lands.
  Future<void> reorder(String id, int index) => manager.reorder(id, index);

  /// Enables or disables an extension. Persisted, and enforced by the manager.
  Future<void> setEnabled(String id, bool enabled) =>
      manager.setEnabled(id, enabled);

  /// Permanently removes an extension, retires its runtime and deletes its file.
  ///
  /// Returns a controlled failure — never a throw, never a silent no-op — when
  /// the node is locked (Node 0) or the id is not installed.
  Future<SpectaResult<UninstallOutcome>> uninstall(String id) =>
      manager.uninstall(id);

  /// Whether [id] may be removed at all.
  ///
  /// Lets the UI disable the delete affordance for Node 0 before the user taps
  /// it. The authoritative check is still [uninstall]: this is a hint, not a
  /// gate, and a stale answer here can never permit an illegal delete.
  Future<bool> canUninstall(String id) async {
    final ExtensionRecord? record = await manager.getExtension(id);
    return record != null && !record.nodeLocked;
  }

  /// Whether a rollback point exists for [id] (a previous version was
  /// snapshotted by an earlier update).
  Future<bool> isRollbackAvailable(String id) =>
      manager.isRollbackAvailable(id);

  /// Restores the previous known-good version of an extension.
  ///
  /// Returns true when a rollback point existed and was restored. The user's
  /// enabled/disabled choice is preserved: this replaces the runtime, it does
  /// not reinstall the extension.
  Future<bool> rollback(String id) => manager.rollback(id);

  /// Shuts down every live runtime. Used when the application is torn down.
  Future<void> shutdownAll() => manager.shutdownAll();

  /// Health classification used only if the manager cannot answer for a record
  /// it just returned. Pure fallback; it must never mask a real failure.
  static ExtensionHealthState _fallbackHealth(ExtensionRecord record) {
    return ExtensionHealthState(
      health: ExtensionHealthRules.evaluate(
        enabled: record.enabled,
        apiCompatible: SpectaApiVersion.isCompatible(record.apiVersion),
        recentFailureCount: 0,
      ),
      recentFailureCount: 0,
      apiVersion: record.apiVersion,
    );
  }
}
