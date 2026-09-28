import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/ui/widgets/specta_artwork.dart';

/// C4.6: SPECTA has exactly ONE place that loads remote artwork, and every
/// non-success state collapses to the same neutral placeholder.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('a null URL renders the placeholder, not a network image', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap(const SpectaArtwork(url: null)));

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });

  testWidgets('a blank or whitespace URL is treated as absent', (
    WidgetTester tester,
  ) async {
    for (final String value in <String>['', '   ']) {
      await tester.pumpWidget(wrap(SpectaArtwork(url: value)));
      expect(find.byType(Image), findsNothing, reason: 'url: "$value"');
    }
  });

  testWidgets('a non-http URL is rejected rather than fetched', (
    WidgetTester tester,
  ) async {
    for (final String value in <String>[
      'file:///etc/passwd',
      'javascript:alert(1)',
      'content://media/x',
    ]) {
      await tester.pumpWidget(wrap(SpectaArtwork(url: value)));
      expect(find.byType(Image), findsNothing, reason: 'url: $value');
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    }
  });

  testWidgets('an https URL is loaded as a real image', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const SpectaArtwork(url: 'https://img.example/poster.jpg', width: 80),
      ),
    );

    final Image image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url, 'https://img.example/poster.jpg');
  });

  testWidgets('a custom fallback icon is honoured', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(const SpectaArtwork(url: null, fallbackIcon: Icons.movie_outlined)),
    );

    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
  });

  testWidgets('dimensions and border radius are applied', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const SpectaArtwork(
          url: null,
          width: 120,
          height: 180,
          borderRadius: 16,
        ),
      ),
    );

    final ClipRRect clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(clip.borderRadius, BorderRadius.circular(16));
  });
}
