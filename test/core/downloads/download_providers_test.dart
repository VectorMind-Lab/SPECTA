@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod; it is
// exposed through the package's public `misc` surface instead.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/database/database_providers.dart';
import 'package:specta/core/database/settings_store.dart';
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/downloads/device_environment.dart';
import 'package:specta/core/downloads/download_manager.dart';
import 'package:specta/core/downloads/download_models.dart';
import 'package:specta/core/downloads/download_providers.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/contract/extension_source.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/settings/specta_setting_keys.dart';
import 'package:specta/core/sources/source_models.dart';
import 'package:specta/core/sources/source_pool.dart';

import '../../support/fake_download_engine.dart';
import '../../support/in_memory_settings_store.dart';

/// Wi-Fi environment: the real platform channel answers null on the VM and
/// the conservative policy would (correctly) refuse every start — downloads
/// in these tests need an answerable network.
class _WifiEnv implements DeviceEnvironment {
  @override
  Future<NetworkAccess?> networkAccess() async => NetworkAccess.wifi;

  @override
  Future<int?> freeBytes(String path) async => null;
}

SourcePool _mp4Pool() => SourcePool(
      ranked: <RankedSource>[
        RankedSource(
          extensionId: 'extA',
          reference: 'ref-a',
          source: const ExtensionSource(
            url: 'https://cdn.example/video.mp4',
            type: SourceType.mp4,
            quality: '1080p',
            label: 'Server 2',
          ),
          score: 100,
        ),
      ],
      outcomes: const <ExtensionSourceOutcome>[],
      reference: 'ref-a',
    );

void main() {
  // The REAL provider graph with only the platform seams swapped: the
  // database is a real file-backed SQLite opened exactly the way the app
  // opens it, the engine is the deterministic fake, and the environment
  // answers Wi-Fi. No fake stores, no fake filters.
  late Directory tempDir;
  late String dbPath;
  late FakeDownloadEngine engine;
  final List<SpectaDatabase> openedDatabases = <SpectaDatabase>[];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('specta_prov_test');
    dbPath = '${tempDir.path}${Platform.pathSeparator}downloads.db';
    engine = FakeDownloadEngine();
    openedDatabases.clear();
  });

  tearDown(() async {
    engine.dispose();
    // Close every database this test opened BEFORE deleting the directory:
    // Windows keeps the SQLite file locked until the handle is gone.
    for (final SpectaDatabase db in openedDatabases) {
      await db.close();
    }
    await tempDir.delete(recursive: true);
  });

  List<Override> overrides({SettingsStore? settingsStore}) =>
      <Override>[
        spectaDatabaseProvider.overrideWith((Ref ref) {
          final SpectaDatabase db = SpectaDatabase(
            NativeDatabase(File(dbPath)),
          );
          openedDatabases.add(db);
          ref.onDispose(db.close);
          return db;
        }),
        downloadMediaDirectoryProvider.overrideWithValue(
          () async => tempDir.path,
        ),
        if (settingsStore != null)
          settingsStoreProvider.overrideWithValue(settingsStore),
        deviceEnvironmentProvider.overrideWithValue(_WifiEnv()),
        downloadEngineProvider.overrideWithValue(engine),
      ];

  // Async providers: always await the fresh computation instead of trusting
  // a possibly-stale `.value` snapshot.
  Future<List<DownloadRecord>> allOf(ProviderContainer c) =>
      c.read(allDownloadsProvider.future);
  Future<List<DownloadRecord>> filteredOf(
          ProviderContainer c, FutureProvider<List<DownloadRecord>> p) =>
      c.read(p.future);
  Future<DownloadRecord> recordOfFresh(ProviderContainer c, String id) async {
    final DownloadRecord? record =
        await c.read(downloadByIdProvider(id).future);
    if (record == null) fail('no record for $id');
    return record;
  }

  // Derived status depends on the async list; force the list to resolve
  // before reading the derived value so the assertion is never stale.
  Future<DownloadQueueStatus> statusOf(ProviderContainer c) async {
    await c.read(allDownloadsProvider.future);
    return c.read(downloadQueueStatusProvider);
  }

  DownloadRequest request(String id) => DownloadRequest(
        id: id,
        mediaKey: id,
        mediaType: MediaType.movie,
        title: 'Title $id',
        extensions: const <String, String>{'extA': 'ref-a'},
        pool: _mp4Pool(),
      );

  group('unconfigured seams are honest (§35)', () {
    test('the engine seam throws without an override — no fake downloads',
        () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(downloadEngineProvider),
        throwsA(anything),
        reason: 'the shipping 2G-B app must not pretend a downloader exists '
            '(the error carries the honest 2G-C message)',
      );
    });

    test('the manager cannot be constructed without an engine either',
        () async {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          spectaDatabaseProvider.overrideWith((Ref ref) {
            final SpectaDatabase db = SpectaDatabase(
              NativeDatabase(File(dbPath)),
            );
            openedDatabases.add(db);
            ref.onDispose(db.close);
            return db;
          }),
        ],
      );
      addTearDown(container.dispose);

      expect(
        () => container.read(downloadManagerProvider),
        throwsA(anything),
      );
    });
  });

  group('provider state derives from real persisted state (§35)', () {
    test('filters start empty, then reflect live queue + concurrency behavior',
        () async {
      final ProviderContainer container =
          ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      final DownloadManager manager = container.read(downloadManagerProvider);
      await manager.debugIdle;

      expect(await allOf(container), isEmpty);
      expect(await filteredOf(container, queuedDownloadsProvider), isEmpty);
      expect(await filteredOf(container, activeDownloadsProvider), isEmpty);

      // Occupy all 3 default slots so the 4th stays queued.
      for (final String id in <String>[
        'p0|movie|1', 'p1|movie|1', 'p2|movie|1', 'p3|movie|1',
      ]) {
        await manager.enqueue(request(id));
      }
      await manager.debugIdle;

      expect(await allOf(container), hasLength(4));
      expect(
        (await filteredOf(container, queuedDownloadsProvider))
            .map((DownloadRecord r) => r.id),
        <String>['p3|movie|1'],
        reason: 'the 4th job waits FIFO at concurrency 3',
      );
      expect(
        (await filteredOf(container, activeDownloadsProvider))
            .map((DownloadRecord r) => r.id),
        <String>['p0|movie|1', 'p1|movie|1', 'p2|movie|1'],
      );
      expect(await filteredOf(container, pausedDownloadsProvider), isEmpty);
      expect(await filteredOf(container, completedDownloadsProvider), isEmpty);
      expect(await filteredOf(container, failedDownloadsProvider), isEmpty);
      expect(await filteredOf(container, cancelledDownloadsProvider), isEmpty);

      // Pause p0: the paused filter fills, and the queue advances because a
      // slot freed up.
      expect(await manager.pause('p0|movie|1'), isTrue);
      await manager.debugIdle;

      expect(
        (await filteredOf(container, pausedDownloadsProvider))
            .map((DownloadRecord r) => r.id),
        <String>['p0|movie|1'],
      );
      expect(await filteredOf(container, activeDownloadsProvider), hasLength(3),
          reason: 'p3 took the freed slot');
      expect(await filteredOf(container, queuedDownloadsProvider), isEmpty);
    });

    test('terminal states land in their filters and stay there', () async {
      final ProviderContainer container =
          ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      final DownloadManager manager = container.read(downloadManagerProvider);
      await manager.debugIdle;

      engine.completeWith(1 << 20);
      await manager.enqueue(request('ok|movie|1'));
      await manager.debugIdle;
      // sourcesExhausted is non-retryable: no retry timers are left pending.
      engine.failWith(
        DownloadFailure(
          type: DownloadFailureType.sourcesExhausted,
          message: 'exhausted',
        ),
        0,
      );
      await manager.enqueue(request('bad|movie|1'));
      await manager.debugIdle;

      expect(
        (await filteredOf(container, completedDownloadsProvider))
            .map((DownloadRecord r) => r.id),
        <String>['ok|movie|1'],
      );
      expect(
        (await filteredOf(container, failedDownloadsProvider))
            .map((DownloadRecord r) => r.id),
        <String>['bad|movie|1'],
      );
      expect(await filteredOf(container, activeDownloadsProvider), isEmpty);
    });

    test('identity family lookup refreshes on revision bumps', () async {
      final ProviderContainer container =
          ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      final DownloadManager manager = container.read(downloadManagerProvider);
      await manager.debugIdle;

      expect(container.read(downloadByIdProvider('f|movie|1')).value, isNull,
          reason: 'nothing persisted for that identity yet');

      await manager.enqueue(request('f|movie|1'));
      await manager.debugIdle;

      final DownloadRecord record = await recordOfFresh(container, 'f|movie|1');
      expect(record.status, DownloadStatus.downloading);
      expect(record.title, 'Title f|movie|1');
      expect(record.sourceExtensionId, 'extA',
          reason: 'provenance is part of the provider-visible state');
    });
  });

  group('queue status + active count (§39.10)', () {
    test('queue status reflects counts and the live concurrency value',
        () async {
      final ProviderContainer container =
          ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      final DownloadManager manager = container.read(downloadManagerProvider);
      await manager.debugIdle;

      expect(container.read(downloadQueueStatusProvider).concurrency, 3);
      expect(container.read(downloadQueueStatusProvider).activeCount, 0);

      for (final String id in <String>[
        'q0|movie|1', 'q1|movie|1', 'q2|movie|1', 'q3|movie|1',
      ]) {
        await manager.enqueue(request(id));
      }
      await manager.debugIdle;

      final DownloadQueueStatus status = await statusOf(container);
      expect(status.totalCount, 4);
      expect(status.activeCount, 3);
      expect(status.queuedCount, 1);
      expect(status.concurrency, 3);
      expect(container.read(activeCountProvider), 3,
          reason: 'activeCount is the manager truth, not a row count');

      await manager.updateConcurrency(5);
      await manager.debugIdle;
      final DownloadQueueStatus grown = await statusOf(container);
      expect(grown.concurrency, 5);
      expect(grown.activeCount, 4,
          reason: 'the waiting job started when capacity grew');
    });

    test('invalid concurrency values are clamped, never unlimited', () async {
      final ProviderContainer container =
          ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      final DownloadManager manager = container.read(downloadManagerProvider);
      await manager.debugIdle;

      await manager.updateConcurrency(0);
      expect(manager.concurrency, 3,
          reason: '0 clamps to the default, never to unlimited');
      await manager.updateConcurrency(-4);
      expect(manager.concurrency, 3);
      await manager.updateConcurrency(99);
      expect(manager.concurrency, DownloadManager.maxConcurrency);
      expect(DownloadManager.maxConcurrency, 9);
      expect(DownloadManager.defaultConcurrency, 3);
    });

    test('the persisted concurrency setting is restored on construction',
        () async {
      // Seed the store exactly the way the Settings surface persists it.
      final InMemorySettingsStore store = InMemorySettingsStore();
      await store.write(SpectaSettingKeys.downloadConcurrency, '7');

      final ProviderContainer container = ProviderContainer(
        overrides: overrides(settingsStore: store),
      );
      addTearDown(container.dispose);
      final DownloadManager manager = container.read(downloadManagerProvider);

      // The restore is async after construction; drain deterministically.
      for (int i = 0; i < 50 && manager.concurrency != 7; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(manager.concurrency, 7,
          reason: 'the persisted value is restored over the default');
    });
  });

  group('manager state survives container recreation (§39.8)', () {
    test('dispose the graph, reopen the same database: persisted state drives '
        'the new manager', () async {
      final ProviderContainer first =
          ProviderContainer(overrides: overrides());
      final DownloadManager m1 = first.read(downloadManagerProvider);
      await m1.debugIdle;

      await m1.enqueue(request('survivor|movie|1'));
      await m1.debugIdle;
      engine.emitProgress('survivor|movie|1', 700000, totalBytes: 1 << 20);
      await m1.debugIdle;
      expect((await recordOfFresh(first, 'survivor|movie|1')).bytesDownloaded,
          700000,
          reason: 'meaningful progress was persisted, not only held live');
      final int startsBefore = engine.startedCount;

      // Dispose the whole graph (manager + database), then reopen the same
      // database file through a brand-new container and engine.
      // (ProviderContainer.dispose is synchronous; the manager's own dispose
      // hook runs unawaited inside it.)
      first.dispose();

      final ProviderContainer second =
          ProviderContainer(overrides: overrides());
      addTearDown(second.dispose);
      final DownloadManager m2 = second.read(downloadManagerProvider);
      await m2.debugIdle;

      // Honest reconciliation story (identical to the manager restart test
      // driven with virtual time): the new engine holds no transfer, so the
      // record is reclassified as interrupted and the bounded auto-retry
      // re-attempts it. That retry runs on the REAL system clock here — wait
      // for it, then the attempt fails sourcesExhausted because the 2G-B
      // session resolver holds no pool after restart (2G-C owns recovery).
      final DownloadRecord reclassified =
          await recordOfFresh(second, 'survivor|movie|1');
      expect(reclassified.status, DownloadStatus.failed,
          reason: 'a dead downloading record is honestly failed, not '
              'assumed alive and not blindly lost');
      expect(reclassified.failure!.type, DownloadFailureType.interrupted);
      expect(reclassified.attempt, 1);
      expect(reclassified.bytesDownloaded, 700000,
          reason: 'progress survives recreation');
      expect(reclassified.sourceExtensionId, 'extA',
          reason: 'provenance survives');

      await Future<void>.delayed(const Duration(milliseconds: 2600));
      await m2.debugIdle;

      final DownloadRecord afterRetry =
          await recordOfFresh(second, 'survivor|movie|1');
      expect(afterRetry.status, DownloadStatus.failed);
      expect(afterRetry.failure!.type, DownloadFailureType.sourcesExhausted);
      expect(afterRetry.attempt, 2,
          reason: 'the attempt count survived restart and the re-attempt '
              'spent exactly one budget unit');
      expect(engine.startedCount, startsBefore,
          reason: 'the re-attempt never reached the engine: resolution fails '
              'first — the engine seam is untouched');
      expect(await allOf(second), hasLength(1),
          reason: 'no duplicate records after recreation');
    });
  });
}
