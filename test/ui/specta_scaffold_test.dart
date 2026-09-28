import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/ui/widgets/specta_scaffold.dart';

/// The top bar is rendered by EVERY screen, so an overflow here is a global
/// visual defect rather than a per-screen one.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(body: child),
  );

  testWidgets('the top bar fits a narrow phone width (real-device fix)', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const SpectaTopBar(showSearchBar: true)));

    // Phase F found this overflowing by 147 px on a real 360dp phone because
    // the search container had a hard `width: 320`.
    expect(tester.takeException(), isNull);
    expect(find.text('SPECTA'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('the top bar keeps a usable search field on a wide screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const SpectaTopBar(showSearchBar: true)));

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
  });
}
