import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod; it is
// exposed through the package's public `misc` surface instead.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/app/specta_app.dart';
import 'package:specta/core/database/database_providers.dart';
import 'package:specta/core/settings/specta_setting_keys.dart';
import 'package:specta/features/home/foundation_status.dart';

import '../../support/in_memory_settings_store.dart';

Future<void> _pumpApp(WidgetTester tester, InMemorySettingsStore store) async {
  tester.view.physicalSize = const Size(1200, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      // The widget tests exercise presentation, so the status reader is
      // replaced with fixed rows; SpectaDatabase and the real DAO are covered
      // by test/core/database/specta_database_test.dart.
      overrides: <Override>[
        settingsStoreProvider.overrideWith((Ref ref) => store),
        foundationStatusProvider.overrideWith(
          (Ref ref) async => const <FoundationStatusItem>[
            FoundationStatusItem('SQLite schema', 'v1'),
            FoundationStatusItem('Settings round trip', 'OK'),
          ],
        ),
      ],
      child: const SpectaApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the shell and the live status rows', (tester) async {
    await _pumpApp(tester, InMemorySettingsStore());

    expect(find.text('SPECTA'), findsOneWidget);
    expect(find.text('Phase 0 — foundation'), findsOneWidget);
    expect(find.text('v1'), findsOneWidget);
    expect(find.text('Settings round trip'), findsOneWidget);
  });

  testWidgets('changing download concurrency persists the new value', (
    tester,
  ) async {
    final InMemorySettingsStore store = InMemorySettingsStore();
    await _pumpApp(tester, store);

    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('4'), findsOneWidget);
    expect(await store.read(SpectaSettingKeys.downloadConcurrency), '4');
  });

  testWidgets('does not claim unbuilt features exist', (tester) async {
    await _pumpApp(tester, InMemorySettingsStore());

    expect(find.text('Not implemented yet'), findsOneWidget);
    expect(
      find.textContaining('Extension runtime and sandbox'),
      findsOneWidget,
    );
  });
}
