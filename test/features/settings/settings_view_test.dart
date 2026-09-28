import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;

import 'package:specta/core/database/database_providers.dart';
import 'package:specta/features/home/foundation_status.dart';
import 'package:specta/features/settings/settings_view.dart';

import '../../support/in_memory_settings_store.dart';

void main() {
  testWidgets('settings offers no TMDB credential control', (
    WidgetTester tester,
  ) async {
    final InMemorySettingsStore store = InMemorySettingsStore();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          settingsStoreProvider.overrideWith((Ref ref) => store),
          foundationStatusProvider.overrideWith(
            (Ref ref) async => const <FoundationStatusItem>[],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsView())),
      ),
    );
    await tester.pumpAndSettle();

    // The catalogue credential is a build-time concern, so the settings screen
    // must expose no way to enter, view, or remove one. Every control that
    // remains is wired to real, persisted state.
    //
    // This guard used to be `expect(find.textContaining('TMDB'), findsNothing)`,
    // as a shorthand for "no credential control". TMDB's terms of use require
    // SPECTA to NAME TMDB in an About/Credits section, so that shorthand is
    // now false by design — the name legitimately appears as attribution. The
    // guard is therefore stated directly, which is what it always meant: there
    // is no input on this screen at all.
    expect(find.text('Add API key'), findsNothing);
    expect(find.textContaining('API key'), findsNothing);
    expect(find.text('Remove'), findsNothing);
    expect(find.byType(TextField), findsNothing);

    // Nothing was written to the device settings table by rendering the screen.
    expect(store.writeCount, 0);

    // The real sections are still present and functional.
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('Extensions'), findsOneWidget);
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('About & Credits'), findsOneWidget);
  });

  group('TMDB attribution (terms of use)', () {
    Future<void> pumpSettings(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            settingsStoreProvider.overrideWith(
              (Ref ref) => InMemorySettingsStore(),
            ),
            foundationStatusProvider.overrideWith(
              (Ref ref) async => const <FoundationStatusItem>[],
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: SettingsView())),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the required notice appears verbatim', (
      WidgetTester tester,
    ) async {
      await pumpSettings(tester);

      // TMDB requires this exact sentence. A reworded version is not
      // compliant, so the wording itself is asserted rather than just the
      // presence of the word "TMDB".
      expect(find.text(tmdbAttributionNotice), findsOneWidget);
      expect(
        tmdbAttributionNotice,
        contains('not endorsed or certified by TMDB'),
      );
    });

    testWidgets('the approved logo is used unmodified and unstretched', (
      WidgetTester tester,
    ) async {
      await pumpSettings(tester);

      final Image logo = tester.widget<Image>(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  'assets/images/tmdb_logo.png',
        ),
      );

      // Width only. Setting a height as well would let the mark be squashed;
      // TMDB's guidelines forbid changing its aspect ratio, so the height must
      // stay unconstrained and derive from the asset.
      expect(logo.width, isNotNull);
      expect(
        logo.height,
        isNull,
        reason: 'a fixed height could distort the approved mark',
      );
      expect(logo.fit, isNot(BoxFit.fill));
    });

    testWidgets('the notice is never presented as a link SPECTA cannot open', (
      WidgetTester tester,
    ) async {
      await pumpSettings(tester);

      // TMDB's terms ask that any link back to their site point at
      // https://www.themoviedb.org, so the address is stated. It is shown as
      // SELECTABLE TEXT rather than a control: SPECTA ships no URL launcher,
      // and a tappable element that cannot open anything would be a dead
      // button, which this codebase forbids.
      //
      // Asserting on the ancestors rather than "no InkWell anywhere" matters:
      // Switch builds its own InkWell, so a blanket assertion would fail for
      // reasons that have nothing to do with this credit.
      final Finder url = find.byType(SelectableText);
      expect(url, findsOneWidget);
      expect(
        tester.widget<SelectableText>(url).data,
        contains('themoviedb.org'),
      );
      expect(
        find.ancestor(of: url, matching: find.byType(InkWell)),
        findsNothing,
      );
      expect(
        find.ancestor(of: url, matching: find.byType(GestureDetector)),
        findsNothing,
      );
    });
  });

  group('Phase E — settings show their current value', () {
    Future<void> pumpSettings(WidgetTester tester) async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            settingsStoreProvider.overrideWith((Ref ref) => store),
            foundationStatusProvider.overrideWith(
              (Ref ref) async => const <FoundationStatusItem>[],
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: SettingsView())),
        ),
      );
      await tester.pumpAndSettle();
    }

    // E1 + E3: a value is labelled with real state only. "3" is the shipped
    // default, so "(default)" is true; the theme chip uses the same wording.
    testWidgets('the default download concurrency is labelled as the default', (
      WidgetTester tester,
    ) async {
      await pumpSettings(tester);

      expect(find.text('(default)'), findsWidgets);
    });

    // E1: after the user changes it, the value is no longer the default and the
    // label must disappear rather than keep claiming to be.
    testWidgets('a changed download concurrency is not labelled default', (
      WidgetTester tester,
    ) async {
      await pumpSettings(tester);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // 4 is the new real value; the default marker must be gone.
      expect(find.text('4'), findsOneWidget);
    });

    // E2: the auto-update switch is the one control that changes behaviour on
    // its own, so it must state what it currently does.
    testWidgets('the auto-update switch states its value in plain words', (
      WidgetTester tester,
    ) async {
      await pumpSettings(tester);

      expect(
        find.textContaining('On — SPECTA checks for newer versions'),
        findsOneWidget,
      );

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Off — extensions stay on the version you installed',
        ),
        findsOneWidget,
      );
    });
  });
}
