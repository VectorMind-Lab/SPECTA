import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:specta/app/theme/specta_colors.dart';
import 'package:specta/core/database/database_providers.dart';
import 'package:specta/features/splash/splash_page.dart';

import '../../support/in_memory_settings_store.dart';

/// The launch frame is the first thing anyone sees, and it is also the frame
/// most likely to rot silently, because nothing else in the app depends on it.
/// These tests pin what the redesign actually changed.
void main() {
  /// Pumps the splash with auto-transition OFF so the timer cannot fire and
  /// swap the screen out from under an assertion.
  Future<void> pumpSplash(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          settingsStoreProvider.overrideWith(
            (Ref ref) => InMemorySettingsStore(),
          ),
        ],
        child: const MaterialApp(home: SplashPage(autoTransition: false)),
      ),
    );
  }

  /// The asset names the splash actually renders, so a swap to a different
  /// image cannot pass unnoticed.
  Iterable<String> renderedAssets(WidgetTester tester) {
    return tester
        .widgetList<Image>(find.byType(Image))
        .where((Image image) => image.image is AssetImage)
        .map((Image image) => (image.image as AssetImage).assetName);
  }

  testWidgets('renders the SPECTA brand and its tagline', (
    WidgetTester tester,
  ) async {
    await pumpSplash(tester);
    await tester.pump();

    expect(find.text('SPECTA'), findsOneWidget);
    expect(find.text('YOUR WORLD. YOUR CONTENT.'), findsOneWidget);
    expect(find.text('FREE.'), findsOneWidget);
  });

  testWidgets('shows the app mark, not the retired city illustration', (
    WidgetTester tester,
  ) async {
    await pumpSplash(tester);
    await tester.pump();

    final Iterable<String> assets = renderedAssets(tester);

    expect(assets, contains('assets/images/app_icon.png'));

    // The previous splash layered a stock illustration, a feature-pillar block
    // and a manual call to action over the brand. All three were removed: the
    // launch frame is only the brand now.
    expect(assets, isNot(contains('assets/images/man_facing_city_pure.png')));
    expect(find.text('Enter SPECTA'), findsNothing);
    expect(find.text('MORE SOURCES'), findsNothing);
  });

  testWidgets('paints SPECTA\'s own canvas colour, never a light one', (
    WidgetTester tester,
  ) async {
    await pumpSplash(tester);
    await tester.pump();

    // The native launch window was changed from the stock white to this same
    // colour, so the hand-off from Android to Flutter is one continuous dark
    // frame instead of a white flash followed by a dark screen.
    final Scaffold scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, SpectaColors.background);
  });

  testWidgets('plays a reveal that finishes and then stops', (
    WidgetTester tester,
  ) async {
    await pumpSplash(tester);
    await tester.pump();

    // Something is genuinely animating: the mark has a highlight sweep driven
    // by the reveal controller, so the composition is not a static image.
    expect(find.byType(ShaderMask), findsOneWidget);
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpAndSettle();

    // And it settles. An animation that never completes would hold frames
    // forever and keep the transition from ever running.
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('SPECTA'), findsOneWidget);
  });
}
