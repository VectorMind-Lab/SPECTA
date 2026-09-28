import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:specta/app/navigation/specta_destination.dart';
import 'package:specta/app/navigation/specta_nav_label_layout.dart';

/// The width a destination slot is given on the phone the collision was
/// reported on: 720 px at 300 dpi, i.e. 384 logical dp split six ways.
const double kPhoneSlotWidth = 384 / 6;

/// The six labels exactly as the app presents them.
final List<String> kLabels = <String>[
  for (final SpectaDestination destination in SpectaDestination.values)
    destination.label,
];

/// Tolerance for the layout assertions: text metrics are floating point.
const double kEpsilon = 0.01;

/// Width of the widest label rendered at [fontSize] with the user's font scale
/// folded in, measured the same way the bar will measure it.
double widestLabelWidth(double fontSize, double textScaleFactor) {
  double widest = 0;
  for (final String label in kLabels) {
    for (final FontWeight weight in <FontWeight>[
      FontWeight.w500,
      FontWeight.w700,
    ]) {
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: fontSize * textScaleFactor,
            fontWeight: weight,
            letterSpacing: 0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      widest = math.max(widest, painter.width);
    }
  }
  return widest;
}

double _sizeForSlot(double slotWidth, {double textScaleFactor = 1}) {
  return SpectaNavLabelLayout.fontSizeFor(
    slotWidth: slotWidth,
    labels: kLabels,
    scaledLabelSize:
        SpectaNavLabelLayout.maxFontSize *
        textScaleFactor, // what MediaQuery.textScalerOf(context).scale() yields
    textDirection: TextDirection.ltr,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Documents the defect itself: Material's default label style (labelMedium —
  // 12 sp with 0.5 tracking) is wider than the slot NavigationBar gives it, and
  // the bar paints a single word at its intrinsic width instead of clipping it,
  // so the two widest labels met in the middle and read as one word.
  test(
    'the Material default label style is wider than a phone destination slot',
    () {
      final double widestAtMaterialDefault = widestLabelWidth(12, 1);
      expect(
        widestAtMaterialDefault,
        greaterThan(kPhoneSlotWidth),
        reason:
            'the collision this guards only exists because the default '
            'label overflows its slot',
      );
    },
  );

  test('on a phone, every label fits inside its own slot', () {
    final double size = _sizeForSlot(kPhoneSlotWidth);

    expect(
      widestLabelWidth(size, 1),
      lessThanOrEqualTo(
        kPhoneSlotWidth - SpectaNavLabelLayout.slotGutter + kEpsilon,
      ),
    );
  });

  test('neighbouring labels keep a visible gutter instead of touching', () {
    final double size = _sizeForSlot(kPhoneSlotWidth);
    final double freeSpacePerSlot = kPhoneSlotWidth - widestLabelWidth(size, 1);

    expect(
      freeSpacePerSlot,
      greaterThanOrEqualTo(SpectaNavLabelLayout.slotGutter - kEpsilon),
    );
  });

  test('the size never grows past the maximum', () {
    expect(
      _sizeForSlot(kPhoneSlotWidth),
      lessThanOrEqualTo(SpectaNavLabelLayout.maxFontSize),
    );
    // A screen with room to spare keeps labels at the maximum rather than
    // inflating them.
    expect(_sizeForSlot(160), SpectaNavLabelLayout.maxFontSize);
  });

  // The reason a hand-picked fixed size was not enough: the label grows with
  // the user's system font scale while the slot does not.
  test(
    'a large system font scale shrinks the label rather than overflowing',
    () {
      final double atDefaultScale = _sizeForSlot(kPhoneSlotWidth);
      final double atLargeScale = _sizeForSlot(
        kPhoneSlotWidth,
        textScaleFactor: 1.5,
      );

      expect(atLargeScale, lessThan(atDefaultScale));
      expect(
        widestLabelWidth(atLargeScale, 1.5),
        lessThanOrEqualTo(
          kPhoneSlotWidth - SpectaNavLabelLayout.slotGutter + kEpsilon,
        ),
      );
    },
  );

  test(
    'a slot narrower than the gutter yields no label rather than a collision',
    () {
      expect(_sizeForSlot(SpectaNavLabelLayout.slotGutter), 0);
    },
  );
}
