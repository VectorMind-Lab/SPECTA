import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod; it is
// exposed through the package's public `misc` surface instead.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:specta/app/navigation/specta_app_shell.dart';
import 'package:specta/core/database/database_providers.dart';
import 'package:specta/core/settings/specta_setting_keys.dart';
import 'package:specta/features/home/foundation_status.dart';

import '../../support/in_memory_settings_store.dart';

Future<void> _pumpShell(WidgetTester tester, InMemorySettingsStore store) async {
  tester.view.physicalSize = const Size(1200, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        settingsStoreProvider.overrideWith((Ref ref) => store),
        foundationStatusProvider.overrideWith(
          (Ref ref) async => const <FoundationStatusItem>[
            FoundationStatusItem('SQLite schema', 'v1'),
            FoundationStatusItem('Settings round trip', 'OK'),
          ],
        ),
      ],
      // The shell is normally hosted inside MaterialApp; the test host
      // supplies the same Directionality/Theme ancestry.
      child: const MaterialApp(
        home: SpectaAppShell(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('home shows the visual home surface, not diagnostics', (
    tester,
  ) async {
    await _pumpShell(tester, InMemorySettingsStore());

    expect(find.text('Continue Watching'), findsOneWidget);
    expect(find.text('Trending Now'), findsOneWidget);
    expect(find.text('Latest Releases'), findsOneWidget);
    // Hero spotlight content from the design fixture.
    expect(find.text('THE LAST HORIZON'), findsOneWidget);
  });

  testWidgets('diagnostics live under Settings, not on the home surface', (
    tester,
  ) async {
    final InMemorySettingsStore store = InMemorySettingsStore();
    await _pumpShell(tester, store);

    // At the shell's default test size the layout family is large-screen, so
    // destinations live in the TV sidebar.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('SQLite schema'), findsOneWidget);
    expect(find.text('v1'), findsOneWidget);
    expect(find.text('Settings round trip'), findsOneWidget);
  });

  testWidgets('download concurrency control persists through Settings', (
    tester,
  ) async {
    final InMemorySettingsStore store = InMemorySettingsStore();
    await _pumpShell(tester, store);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('4'), findsOneWidget);
    expect(await store.read(SpectaSettingKeys.downloadConcurrency), '4');
  });
}
