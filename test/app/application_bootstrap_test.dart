@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/app/application_bootstrap.dart';
import 'package:specta/core/database/database_providers.dart';
import 'package:specta/core/database/settings_store.dart';
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/downloads/device_environment.dart';
import 'package:specta/core/downloads/download_manager.dart';
import 'package:specta/core/downloads/download_models.dart';
import 'package:specta/core/downloads/download_providers.dart';
import 'package:specta/core/downloads/download_store.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/contract/extension_source.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/extensions/manager/extension_providers.dart';
import 'package:specta/core/settings/specta_setting_keys.dart';
import 'package:specta/core/sources/source_models.dart';
import 'package:specta/core/sources/source_pool.dart';

import '../support/fake_download_engine.dart';
import '../support/in_memory_settings_store.dart';

class _WifiEnv implements DeviceEnvironment {
  @override
  Future<NetworkAccess?> networkAccess() async => NetworkAccess.wifi;

  @override
  Future<int?> freeBytes(String path) async => null;
}

class _StubFinalizer implements DownloadCompletionFinalizer {
  const _StubFinalizer();

  @override
  Future<int> finalize(DownloadRecord record, int engineBytes) async =>
      engineBytes;
}

SourcePool _mp4Pool() => SourcePool(
  ranked: <RankedSource>[
    RankedSource(
      extensionId: 'extA',
      reference: 'ref-a',
      source: const ExtensionSource(
        url: 'https://cdn.example/video.mp4',
        type: SourceType.mp4,
      ),
      score: 100,
    ),
  ],
  outcomes: const <ExtensionSourceOutcome>[],
  reference: 'ref-a',
);

DownloadRequest _request(String id) => DownloadRequest(
  id: id,
  mediaKey: id,
  mediaType: MediaType.movie,
  title: 'Title $id',
  extensions: const <String, String>{'extA': 'ref-a'},
  pool: _mp4Pool(),
);

/// Phase 2L hardening: the launch bootstrap is what turns "queue persistence"
/// into a real promise. This test drives the WHOLE application-launch path
/// (the bootstrap provider, exactly what `main()` watches) against a real
/// file-backed SQLite database, and proves the persisted queue is reconciled
/// WITHOUT any screen being built — because `main()` never mentions Downloads.
void main() {
  late Directory tempDir;
  late String dbPath;
  final List<SpectaDatabase> opened = <SpectaDatabase>[];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('specta_bootstrap');
    dbPath = '${tempDir.path}${Platform.pathSeparator}app.db';
    opened.clear();
  });

  tearDown(() async {
    for (final SpectaDatabase db in opened) {
      await db.close();
    }
    await tempDir.delete(recursive: true);
  });

  List<Override> overrides({
    required FakeDownloadEngine engine,
    SettingsStore? settingsStore,
  }) => <Override>[
    spectaDatabaseProvider.overrideWith((Ref ref) {
      final SpectaDatabase db = SpectaDatabase(NativeDatabase(File(dbPath)));
      opened.add(db);
      ref.onDispose(db.close);
      return db;
    }),
    downloadMediaDirectoryProvider.overrideWithValue(() async => tempDir.path),
    settingsStoreProvider.overrideWithValue(
      settingsStore ?? InMemorySettingsStore(),
    ),
    deviceEnvironmentProvider.overrideWithValue(_WifiEnv()),
    downloadCompletionFinalizerProvider.overrideWithValue(
      const _StubFinalizer(),
    ),
    downloadEngineProvider.overrideWithValue(engine),
  ];

  test('reading the launch bootstrap starts an interrupted download recovery '
      'with no screen involved', () async {
    // ---- Session 1: the user queues a download, then the app dies. ----
    final FakeDownloadEngine engine1 = FakeDownloadEngine();
    final ProviderContainer session1 = ProviderContainer(
      overrides: overrides(engine: engine1),
    );
    final DownloadManager manager1 = session1.read(downloadManagerProvider);
    await manager1.debugIdle;
    await manager1.enqueue(_request('queued|movie|2024'));
    await manager1.debugIdle;
    expect(
      session1.read(downloadManagerProvider).activeCount,
      1,
      reason: 'the download really was in flight when the app died',
    );

    // Session 1's OWN persisted state, captured before it dies. `attempt` is
    // exactly 1 because starting an attempt is what persists it, and `failure`
    // is null because that attempt never ended. This is the guard that makes
    // the session-2 assertions unfakeable: session 1 writes NO failure, so an
    // `interrupted` failure can only have been produced by the launch manager.
    final DownloadStore session1Store = session1.read(downloadStoreProvider);
    final DownloadRecord inFlight = (await session1Store.recordFor(
      'queued|movie|2024',
    ))!;
    expect(inFlight.status, DownloadStatus.downloading);
    expect(inFlight.attempt, 1);
    expect(inFlight.failure, isNull);

    session1.dispose();
    engine1.dispose();

    // ---- Session 2: cold launch. The ONLY thing that happens is the launch
    // bootstrap — no DownloadsView, no download entry point, and crucially the
    // manager is never read directly here. If someone removed the download
    // watch from [applicationBootstrapProvider], nothing would touch the
    // manager and this test would fail.
    final FakeDownloadEngine engine2 = FakeDownloadEngine();
    final ProviderContainer session2 = ProviderContainer(
      overrides: overrides(engine: engine2),
    );
    addTearDown(session2.dispose);

    session2.read(applicationBootstrapProvider);

    // Observed through the STORE, which does not construct the manager.
    final DownloadStore store = session2.read(downloadStoreProvider);
    final Stopwatch elapsed = Stopwatch()..start();

    // (1) The dead `downloading` row is reconciled HONESTLY: neither assumed
    // alive nor left as a phantom active download the queue can never drain.
    // This failure is written before any backoff delay, and a later re-attempt
    // keeps it as last-attempt provenance — so it is observable deterministically.
    DownloadRecord? reconciled;
    while (elapsed.elapsed < const Duration(seconds: 15)) {
      final DownloadRecord? record = await store.recordFor('queued|movie|2024');
      if (record?.failure?.type == DownloadFailureType.interrupted) {
        reconciled = record;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(
      reconciled,
      isNotNull,
      reason:
          'the launch bootstrap must reconcile the persisted queue with no '
          'screen involved. Without it nothing constructs a manager, so the '
          'row stays `downloading` with a null failure — exactly as session 1 '
          'left it.',
    );

    // (2) And the recovered queue is actually RESUMED by that launch manager,
    // not merely classified: `interrupted` is retryable, so the 2s backoff is
    // spent and a SECOND attempt is started (attempt 1 -> 2). Reaching attempt
    // 2 is impossible without a live manager, and session 1 left exactly 1.
    //
    // The engine is deliberately NOT asserted here: in this container the real
    // production source resolver runs, and a fresh process holds no captured
    // pool, so the resumed attempt legitimately fails at RESOLUTION (before any
    // engine start). The attempt counter is the manager-only proof of resumption.
    DownloadRecord? resumed;
    while (elapsed.elapsed < const Duration(seconds: 30)) {
      final DownloadRecord? record = await store.recordFor('queued|movie|2024');
      if (record != null && record.attempt >= 2) {
        resumed = record;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(
      resumed,
      isNotNull,
      reason:
          'the launch manager must resume the recovered queue, not just '
          'record that it died (attempt never reached 2)',
    );
  });

  test('the launch bootstrap arms the extension subsystem too', () async {
    final FakeDownloadEngine engine = FakeDownloadEngine();
    addTearDown(engine.dispose);
    final ProviderContainer container = ProviderContainer(
      overrides: overrides(engine: engine),
    );
    addTearDown(container.dispose);

    // Reading the bootstrap constructs the real manager over the real
    // registry without throwing — the entry point's contract.
    container.read(applicationBootstrapProvider);

    expect(() => container.read(extensionManagerProvider), returnsNormally);
  });

  test(
    'the persisted download concurrency setting is restored at launch',
    () async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      await store.write(SpectaSettingKeys.downloadConcurrency, '5');

      final FakeDownloadEngine engine = FakeDownloadEngine();
      addTearDown(engine.dispose);
      final ProviderContainer container = ProviderContainer(
        overrides: overrides(engine: engine, settingsStore: store),
      );
      addTearDown(container.dispose);

      container.read(applicationBootstrapProvider);
      final DownloadManager manager = container.read(downloadManagerProvider);

      for (int i = 0; i < 50 && manager.concurrency != 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(manager.concurrency, 5);
    },
  );
}
