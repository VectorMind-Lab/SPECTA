import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps family types in the misc library (same split as `Override`,
// which this project's tests already import from there).
import 'package:riverpod/misc.dart';

import '../database/database_providers.dart';
import '../extensions/manager/extension_providers.dart';
import '../settings/specta_setting_keys.dart';
import '../storage/specta_storage.dart';
import 'background_downloader_engine.dart';
import 'device_environment.dart';
import 'download_dao.dart';
import 'download_engine.dart';
import 'download_manager.dart';
import 'download_models.dart';
import 'download_store.dart';
import 'source_manager_download_resolver.dart';

/// The download store binding (Phase 2G-B) — the authoritative persistence
/// path, overridden with an in-memory/file-backed store in tests exactly like
/// the library and settings providers.
final Provider<DownloadStore> downloadStoreProvider = Provider<DownloadStore>((
  Ref ref,
) {
  return DownloadDao(ref.watch(spectaDatabaseProvider));
});

/// The download engine seam — Phase 2G-C: the REAL transfer engine.
///
/// The adapter is SPECTA-owned ([BackgroundDownloaderEngine]): the only
/// file that knows `background_downloader` types, translating them into the
/// SPECTA [DownloadEngine] contract. The manager keeps ownership of identity,
/// queueing, concurrency, retry, persistence and recovery; the plugin only
/// executes transfers. Tests override this provider with a deterministic
/// fake, exactly as in 2G-B.
final Provider<DownloadEngine> downloadEngineProvider = Provider<DownloadEngine>(
  (Ref ref) => BackgroundDownloaderEngine(),
);

/// Phase 2G-C production source resolver: real re-resolution through the
/// SourceManager using the persisted provenance (replaces the 2G-B
/// session-only resolver in production; tests inject their own).
final Provider<SourceManagerDownloadResolver>
    downloadSourceResolverProvider = Provider<SourceManagerDownloadResolver>(
  (Ref ref) => SourceManagerDownloadResolver(
    extensionManager: () => ref.watch(extensionManagerProvider),
  ),
);

/// Phase 2G-C completion gate: verifies engine-reported completions on the
/// real filesystem and owns the final rename. Tests override this with a
/// pass-through stub when the fake engine is used without real files.
final Provider<DownloadCompletionFinalizer>
    downloadCompletionFinalizerProvider = Provider<DownloadCompletionFinalizer>(
  (Ref ref) => const FileDownloadCompletionFinalizer(),
);

/// Bumped after every persisted download change or active-set change so the
/// read providers refresh — the same revision-counter discipline as the
/// library (no polling).
final class DownloadRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final NotifierProvider<DownloadRevision, int> downloadRevisionProvider =
    NotifierProvider<DownloadRevision, int>(DownloadRevision.new);

/// Where download files live. Exposed as an overridable provider so tests
/// can point it at a temp directory; production resolves the platform media
/// directory through SPECTA storage exactly as before.
final Provider<Future<String> Function()> downloadMediaDirectoryProvider =
    Provider<Future<String> Function()>((Ref ref) {
      return () => SpectaStorage()
          .mediaDirectory()
          .then((Directory directory) => directory.path);
    });

/// The download manager (2G-C wiring: real engine + real source resolver;
/// The download network policy (Phase 2G-C wiring). Defaults to the
/// conservative Wi-Fi-only product policy; the Settings surface (2G-F) will
/// persist user changes through this provider, and tests may override it.
final Provider<DownloadNetworkPolicy> deviceNetworkPolicyProvider =
    Provider<DownloadNetworkPolicy>(
  (Ref ref) => DownloadNetworkPolicy.wifiOnly,
);

/// tests override the engine and resolver providers with deterministic
/// fakes).
final Provider<DownloadManager> downloadManagerProvider =
    Provider<DownloadManager>((Ref ref) {
      final DownloadManager manager = DownloadManager(
        store: ref.watch(downloadStoreProvider),
        engine: ref.watch(downloadEngineProvider),
        environment: ref.watch(deviceEnvironmentProvider),
        sourceResolver: ref.watch(downloadSourceResolverProvider),
        completionFinalizer: ref.watch(downloadCompletionFinalizerProvider),
        networkPolicy: ref.watch(deviceNetworkPolicyProvider),
        concurrency: DownloadManager.defaultConcurrency,
        mediaDirectory: ref.watch(downloadMediaDirectoryProvider),
        onChanged: () => ref.read(downloadRevisionProvider.notifier).bump(),
      );
      ref.onDispose(() {
        unawaited(manager.dispose());
      });
      unawaited(manager.initialize());

      // The persisted concurrency setting is restored once the settings store
      // answers (the same restore discipline as the Settings notifier). The
      // manager clamps defensively; live updates from the Settings surface
      // call updateConcurrency when 2G-F wires them.
      unawaited(() async {
        try {
          final String? stored = await ref
              .read(settingsStoreProvider)
              .read(SpectaSettingKeys.downloadConcurrency);
          final int? parsed = int.tryParse(stored ?? '');
          if (parsed != null) {
            await manager.updateConcurrency(parsed);
          }
        } on Object {
          // A missing/garbled setting leaves the clamped default in place.
        }
      }());

      return manager;
    });

/// Every download record, oldest-queued first (the persisted FIFO order).
final FutureProvider<List<DownloadRecord>> allDownloadsProvider =
    FutureProvider<List<DownloadRecord>>((Ref ref) async {
      ref.watch(downloadRevisionProvider);
      return ref.watch(downloadStoreProvider).all();
    });

/// Queued downloads, in queue order.
final FutureProvider<List<DownloadRecord>> queuedDownloadsProvider =
    FutureProvider<List<DownloadRecord>>((Ref ref) async {
      ref.watch(downloadRevisionProvider);
      final List<DownloadRecord> all = await ref
          .watch(downloadStoreProvider)
          .all();
      return all
          .where((DownloadRecord r) => r.status == DownloadStatus.queued)
          .toList(growable: false);
    });

/// Actively downloading records (persisted state; the manager's
/// [DownloadManager.activeCount] is the in-memory truth about attempts).
final FutureProvider<List<DownloadRecord>> activeDownloadsProvider =
    FutureProvider<List<DownloadRecord>>((Ref ref) async {
      ref.watch(downloadRevisionProvider);
      final List<DownloadRecord> all = await ref
          .watch(downloadStoreProvider)
          .all();
      return all
          .where((DownloadRecord r) => r.status == DownloadStatus.downloading)
          .toList(growable: false);
    });

/// Paused downloads.
final FutureProvider<List<DownloadRecord>> pausedDownloadsProvider =
    FutureProvider<List<DownloadRecord>>((Ref ref) async {
      ref.watch(downloadRevisionProvider);
      final List<DownloadRecord> all = await ref
          .watch(downloadStoreProvider)
          .all();
      return all
          .where((DownloadRecord r) => r.status == DownloadStatus.paused)
          .toList(growable: false);
    });

/// Completed downloads.
final FutureProvider<List<DownloadRecord>> completedDownloadsProvider =
    FutureProvider<List<DownloadRecord>>((Ref ref) async {
      ref.watch(downloadRevisionProvider);
      final List<DownloadRecord> all = await ref
          .watch(downloadStoreProvider)
          .all();
      return all
          .where((DownloadRecord r) => r.status == DownloadStatus.completed)
          .toList(growable: false);
    });

/// Failed downloads.
final FutureProvider<List<DownloadRecord>> failedDownloadsProvider =
    FutureProvider<List<DownloadRecord>>((Ref ref) async {
      ref.watch(downloadRevisionProvider);
      final List<DownloadRecord> all = await ref
          .watch(downloadStoreProvider)
          .all();
      return all
          .where((DownloadRecord r) => r.status == DownloadStatus.failed)
          .toList(growable: false);
    });

/// Cancelled downloads.
final FutureProvider<List<DownloadRecord>> cancelledDownloadsProvider =
    FutureProvider<List<DownloadRecord>>((Ref ref) async {
      ref.watch(downloadRevisionProvider);
      final List<DownloadRecord> all = await ref
          .watch(downloadStoreProvider)
          .all();
      return all
          .where((DownloadRecord r) => r.status == DownloadStatus.cancelled)
          .toList(growable: false);
    });

/// One download by identity (Riverpod 3 family provider).
final FutureProviderFamily<DownloadRecord?, String> downloadByIdProvider =
    FutureProvider.family<DownloadRecord?, String>((
      Ref ref,
      String id,
    ) async {
      ref.watch(downloadRevisionProvider);
      return ref.watch(downloadStoreProvider).recordFor(id);
    });

/// How many attempts the manager is actually running right now (in-memory
/// truth — NOT the count of persisted `downloading` rows after a restart).
final Provider<int> activeCountProvider = Provider<int>((Ref ref) {
  ref.watch(downloadRevisionProvider);
  return ref.watch(downloadManagerProvider).activeCount;
});

/// Queue status: persisted record counts plus the manager's live scheduling
/// truth. Derived state only — every business rule stays in the manager.
final class DownloadQueueStatus {
  const DownloadQueueStatus({
    required this.totalCount,
    required this.activeCount,
    required this.queuedCount,
    required this.concurrency,
  });

  final int totalCount;
  final int activeCount;
  final int queuedCount;
  final int concurrency;
}

final Provider<DownloadQueueStatus> downloadQueueStatusProvider =
    Provider<DownloadQueueStatus>((Ref ref) {
      final DownloadManager manager = ref.watch(downloadManagerProvider);
      final List<DownloadRecord> all =
          ref.watch(allDownloadsProvider).value ?? const <DownloadRecord>[];
      return DownloadQueueStatus(
        totalCount: all.length,
        activeCount: manager.activeCount,
        queuedCount:
            all.where((DownloadRecord r) => r.status == DownloadStatus.queued).length,
        concurrency: manager.concurrency,
      );
    });
