import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod; it is
// exposed through the package's public `misc` surface instead.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:specta/features/settings/state/auto_update_state.dart';
import 'package:specta/core/database/database_providers.dart';

import '../../support/in_memory_settings_store.dart';

void main() {
  test('auto-update defaults to enabled', () {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        settingsStoreProvider.overrideWith(
          (Ref ref) => InMemorySettingsStore(),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(autoUpdateExtensionsProvider), isTrue);
  });

  test('setEnabled applies and persists the choice', () async {
    final InMemorySettingsStore store = InMemorySettingsStore();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        settingsStoreProvider.overrideWith((Ref ref) => store),
      ],
    );
    addTearDown(container.dispose);

    await container.read(autoUpdateExtensionsProvider.notifier).setEnabled(false);

    expect(container.read(autoUpdateExtensionsProvider), isFalse);
    expect(
      await store.read('extensions.autoUpdate'),
      'false',
    );
  });

  test('a persisted value is restored on build', () async {
    final InMemorySettingsStore store = InMemorySettingsStore();
    await store.write('extensions.autoUpdate', 'false');

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        settingsStoreProvider.overrideWith((Ref ref) => store),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(autoUpdateExtensionsProvider), isTrue);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(autoUpdateExtensionsProvider), isFalse);
  });
}
