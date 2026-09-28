import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod; it is
// exposed through the package's public `misc` surface instead.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:specta/app/theme/specta_theme_preset.dart';
import 'package:specta/app/theme/specta_theme_provider.dart';
import 'package:specta/core/database/database_providers.dart';

import '../../support/in_memory_settings_store.dart';

void main() {
  test('theme preset defaults to the SPECTA brand (cyan/teal)', () {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        settingsStoreProvider.overrideWith(
          (Ref ref) => InMemorySettingsStore(),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(spectaThemePresetProvider).name, 'cyanTeal');
  });

  test('setPreset applies and persists the choice', () async {
    final InMemorySettingsStore store = InMemorySettingsStore();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        settingsStoreProvider.overrideWith((Ref ref) => store),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(spectaThemePresetProvider.notifier)
        .setPreset(SpectaThemePreset.warmAmber);

    expect(
      container.read(spectaThemePresetProvider),
      SpectaThemePreset.warmAmber,
    );
    expect(store.writeCount, 1);
    expect(
      await store.read('ui.themePreset'),
      SpectaThemePreset.warmAmber.name,
    );
  });

  test('a persisted preset is restored on build', () async {
    final InMemorySettingsStore store = InMemorySettingsStore();
    await store.write('ui.themePreset', 'oceanBlue');

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        settingsStoreProvider.overrideWith((Ref ref) => store),
      ],
    );
    addTearDown(container.dispose);

    // The first read returns the brand default; the restore completes
    // asynchronously afterwards.
    expect(container.read(spectaThemePresetProvider).name, 'cyanTeal');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(spectaThemePresetProvider).name, 'oceanBlue');
  });

  test(
    'an unknown persisted preset name falls back to the brand default',
    () async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      await store.write('ui.themePreset', 'not-a-preset');

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          settingsStoreProvider.overrideWith((Ref ref) => store),
        ],
      );
      addTearDown(container.dispose);

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(spectaThemePresetProvider).name, 'cyanTeal');
    },
  );
}
