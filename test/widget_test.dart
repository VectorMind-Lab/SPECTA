// SPECTA — application smoke test.
//
// Verifies that the root widget tree pumps without error and that the
// application title is visible.  This is intentionally minimal: the Phase 0
// foundation screen is temporary, and deeper widget coverage lives in
// test/features/home/home_page_test.dart.

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod; it is
// exposed through the package's public `misc` surface instead.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:specta/app/specta_app.dart';
import 'package:specta/core/database/database_providers.dart';
import 'package:specta/features/home/foundation_status.dart';

import 'support/in_memory_settings_store.dart';

void main() {
  testWidgets('SPECTA root renders without error', (WidgetTester tester) async {
    // SpectaApp must be wrapped in a ProviderScope so Riverpod providers
    // are available.  Tests do not need to inject overrides here because
    // the smoke test only cares that the widget tree assembles at all.
    await tester.pumpWidget(
      ProviderScope(
        // Override the real Drift database with an in-memory settings store
        // so the smoke test does not open a database or leave a pending timer.
        overrides: <Override>[
          settingsStoreProvider.overrideWith(
            (Ref ref) => InMemorySettingsStore(),
          ),
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

    // Pump once more to allow any async providers to settle.
    await tester.pump();

    // The Phase 0 home screen includes the word 'SPECTA' in a Text widget.
    expect(find.text('SPECTA'), findsWidgets);
  });
}
