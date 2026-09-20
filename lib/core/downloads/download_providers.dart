import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps family types in the misc library (same split as `Override`,
// which this project's tests already import from there).
import 'package:riverpod/misc.dart';

import '../database/database_providers.dart';
import '../settings/specta_setting_keys.dart';
import '../storage/specta_storage.dart';
import 'device_environment.dart';
import 'download_dao.dart';
import 'download_engine.dart';
import 'download_manager.dart';
import 'download_models.dart';
import 'download_store.dart';

/// The download store binding (Phase 2G-B) — the authoritative persistence
/// path, overridden with an in-memory/file-backed store in tests exactly like
/// the library and settings providers.
final Provider<DownloadStore> downloadStoreProvider = Provider<DownloadStore>((
  Ref ref,
) {
  return DownloadDao(ref.watch(spectaDatabaseProvider));
});

/// The download engine seam.
///
/// Deliberately UNCONFIGURED in Phase 2G-B: no real transfer engine exists
/// yet, and pretending otherwise would let the app fabricate downloads.
/// Phase 2G-C installs the real adapter (behind the SPECTA-owned
/// [DownloadEngine] interface) by overriding this provider; tests override it
/// with a deterministic fake. Nothing reads [downloadManagerProvider] until
/// then, so this never fires in the running app.
final Provider<DownloadEngine> downloadEngineProvider = Provider<DownloadEngine>(
  (Ref ref) {
    throw StateError(
      'No DownloadEngine is configured yet: the real transfer adapter is '
      'installed in Phase 2G-C. Override downloadEngineProvider to inject '
      'one (tests use a deterministic fake).',
    );
  },
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

/// The download manager. Constructing it reads the engine seam, so in a
/// shipping 2G-B build this throws honestly (nothing reads it yet); tests
/// override [downloadEngineProvider] with a fake engine.
final Provider<DownloadManager> downloadManagerProvider =
    Provider<DownloadManager>((Ref ref) {
      final DownloadManager manager = DownloadManager(
        store: ref.watch(downloadStoreProvider),
        engine: ref.watch(downloadEngineProvider),
        environment: ref.watch(deviceEnvironmentProvider),
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
