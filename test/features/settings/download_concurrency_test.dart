import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod; it is
// exposed through the package's public `misc` surface instead.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/database/database_providers.dart';
import 'package:specta/core/settings/specta_setting_keys.dart';
import 'package:specta/features/settings/state/download_concurrency.dart';

import '../../support/in_memory_settings_store.dart';

ProviderContainer _containerWith(InMemorySettingsStore store) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      settingsStoreProvider.overrideWith((Ref ref) => store),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('DownloadConcurrencyNotifier', () {
    test('defaults to the agreed values', () {
      final ProviderContainer container = _containerWith(
        InMemorySettingsStore(),
      );

      expect(DownloadConcurrencyNotifier.defaultConcurrency, 3);
      expect(DownloadConcurrencyNotifier.maxConcurrency, 9);
      expect(
        container.read(downloadConcurrencyProvider),
        DownloadConcurrencyNotifier.defaultConcurrency,
      );
    });

    test('persists a new value through the settings store', () async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      final ProviderContainer container = _containerWith(store);

      await container.read(downloadConcurrencyProvider.notifier).set(7);

      expect(container.read(downloadConcurrencyProvider), 7);
      expect(await store.read(SpectaSettingKeys.downloadConcurrency), '7');
      expect(store.writeCount, 1);
    });

    test('restores the persisted value on start', () async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      await store.write(SpectaSettingKeys.downloadConcurrency, '5');
      final ProviderContainer container = _containerWith(store);

      container.read(downloadConcurrencyProvider); // triggers build()
      await pumpEventQueue();

      expect(container.read(downloadConcurrencyProvider), 5);
    });

    test('ignores a persisted value outside the supported range', () async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      await store.write(SpectaSettingKeys.downloadConcurrency, '42');
      final ProviderContainer container = _containerWith(store);

      container.read(downloadConcurrencyProvider);
      await pumpEventQueue();

      expect(
        container.read(downloadConcurrencyProvider),
        DownloadConcurrencyNotifier.defaultConcurrency,
      );
    });

    test('rejects out-of-range values instead of clamping silently', () async {
      final ProviderContainer container = _containerWith(
        InMemorySettingsStore(),
      );
      final DownloadConcurrencyNotifier notifier = container.read(
        downloadConcurrencyProvider.notifier,
      );

      await expectLater(notifier.set(0), throwsArgumentError);
      await expectLater(notifier.set(10), throwsArgumentError);
      expect(
        container.read(downloadConcurrencyProvider),
        DownloadConcurrencyNotifier.defaultConcurrency,
      );
    });
  });
}
