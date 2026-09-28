import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod; it is
// exposed through the package's public `misc` surface instead.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:specta/app/navigation/specta_app_shell.dart';
import 'package:specta/app/navigation/specta_destination.dart';
import 'package:specta/app/navigation/specta_nav_label_layout.dart';
import 'package:specta/core/database/database_providers.dart';
import 'package:specta/core/library/library_providers.dart';
import 'package:specta/features/home/foundation_status.dart';
import 'package:specta/features/home/home_feed.dart';

import '../../support/in_memory_library_store.dart';
import '../../support/in_memory_settings_store.dart';

/// The phone the collision was reported on: 720 x 1600 px at 2.0 density, i.e.
/// 360 x 800 logical pixels, which gives each of the six destinations 60 dp.
const Size kPhoneSize = Size(360, 800);

Future<void> _pumpPhoneShell(
  WidgetTester tester, {
  required double textScaleFactor,
}) async {
  tester.view.physicalSize = const Size(720, 1600);
  tester.view.devicePixelRatio = 2.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        settingsStoreProvider.overrideWith(
          (Ref ref) => InMemorySettingsStore(),
        ),
        libraryStoreProvider.overrideWith((Ref ref) => InMemoryLibraryStore()),
        // The body content is irrelevant here; keep it deterministic and offline
        // so only the navigation strip is under test.
        homeFeedProvider.overrideWith(
          (Ref ref) async =>
              const HomeFeed(status: HomeFeedStatus.noExtensions),
        ),
        trendingFeedProvider.overrideWith(
          (Ref ref) async =>
              const TrendingFeed(status: TrendingStatus.notConfigured),
        ),
        foundationStatusProvider.overrideWith(
          (Ref ref) async => const <FoundationStatusItem>[],
        ),
      ],
      child: const MaterialApp(home: SpectaAppShell()),
    ),
  );
  await tester.pumpAndSettle();
}

/// The rendered rectangle of each destination label, in the order the bar shows
/// them, measured from the real widget tree.
List<Rect> _labelRects(WidgetTester tester) {
  final Finder bar = find.byType(NavigationBar);
  return <Rect>[
    for (final SpectaDestination destination in SpectaDestination.values)
      tester.getRect(
        find.descendant(of: bar, matching: find.text(destination.label)),
      ),
  ];
}

void main() {
  testWidgets('the strip spans the screen edge to edge', (
    WidgetTester tester,
  ) async {
    await _pumpPhoneShell(tester, textScaleFactor: 1);

    final Rect bar = tester.getRect(find.byType(NavigationBar));

    expect(bar.width, kPhoneSize.width);
    // Every label sits inside the strip: nothing is painted off-screen.
    for (final Rect label in _labelRects(tester)) {
      expect(label.left, greaterThanOrEqualTo(bar.left));
      expect(label.right, lessThanOrEqualTo(bar.right));
    }
  });

  testWidgets('labels fill the strip without one word running into the next', (
    WidgetTester tester,
  ) async {
    await _pumpPhoneShell(tester, textScaleFactor: 1);

    final List<Rect> labels = _labelRects(tester);
    final double stripWidth = kPhoneSize.width;

    // The row as a whole uses the width it is given instead of crowding the
    // middle: the leftmost label starts inside the first slot and the rightmost
    // ends inside the last one.
    final double leftMost = labels
        .map((Rect r) => r.left)
        .reduce((double a, double b) => a < b ? a : b);
    final double rightMost = labels
        .map((Rect r) => r.right)
        .reduce((double a, double b) => a > b ? a : b);
    expect(leftMost, lessThan(stripWidth / 2));
    expect(rightMost, greaterThan(stripWidth / 2));

    // No two labels share a pixel column, and the gap between the closest pair
    // is at least the gutter the layout promises.
    double narrowestGap = double.infinity;
    for (int a = 0; a < labels.length; a++) {
      for (int b = a + 1; b < labels.length; b++) {
        final bool disjoint =
            labels[a].right <= labels[b].left ||
            labels[b].right <= labels[a].left;
        expect(
          disjoint,
          isTrue,
          reason:
              '"${SpectaDestination.values[a].label}" and '
              '"${SpectaDestination.values[b].label}" overlap',
        );
        if (labels[a].right <= labels[b].left) {
          narrowestGap = labels[b].left - labels[a].right;
        } else if (labels[b].right <= labels[a].left) {
          narrowestGap = labels[a].left - labels[b].right;
        }
      }
    }
    expect(narrowestGap, greaterThanOrEqualTo(SpectaNavLabelLayout.slotGutter));
  });

  testWidgets('a large system font scale still keeps every label inside', (
    WidgetTester tester,
  ) async {
    await _pumpPhoneShell(tester, textScaleFactor: 2);

    final Rect bar = tester.getRect(find.byType(NavigationBar));
    for (final Rect label in _labelRects(tester)) {
      expect(
        label.width,
        lessThanOrEqualTo(bar.width / SpectaDestination.values.length),
        reason: 'the label escaped the slot the bar gave it',
      );
    }
  });
}
