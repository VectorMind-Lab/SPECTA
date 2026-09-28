import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Sizes the phone bottom-navigation labels to the slot they are actually
/// given, so that six labels always stay separated.
///
/// Material's `NavigationBar` lays a destination label out at its *intrinsic*
/// width and centres it inside the destination slot: it neither wraps a single
/// word, nor clips it, nor shrinks it. On a 384 dp-wide phone six destinations
/// leave each label a 64 dp slot, and the widest labels ("Downloads",
/// "Extensions") are wider than that, so the two overhangs met in the middle
/// and read as a single word ("DownloadsExtensions") on a real device.
///
/// A fixed font size cannot solve that: the label width scales with the user's
/// system font scale while the slot does not, so any hand-picked size that fits
/// today collides again tomorrow. This helper therefore measures the real text
/// and returns the largest size at which every label still fits its slot, which
/// keeps working at any font scale and any screen width. Nothing about the
/// destinations, their order, their labels or their colours changes.
abstract final class SpectaNavLabelLayout {
  /// The largest label size ever used; longer labels are scaled down from here.
  static const double maxFontSize = 11;

  /// Width deliberately left unused inside each slot. This is the guarantee
  /// that two neighbouring labels never share a pixel column: 2 dp of gutter
  /// on each side of a label, i.e. a 4 dp minimum gap between neighbours.
  static const double slotGutter = 4;

  /// Weights a label can render at: unselected and selected respectively. Both
  /// are measured because the bold weight is wider and the selected
  /// destination moves as the user navigates.
  static const List<FontWeight> _labelWeights = <FontWeight>[
    FontWeight.w500,
    FontWeight.w700,
  ];

  /// Returns the label font size (in logical pixels, before the user's font
  /// scale is applied by the framework) at which the widest of [labels] fits a
  /// slot of [slotWidth].
  ///
  /// [slotWidth] is the width each destination is allocated by the bar, and
  /// [scaledLabelSize] is [maxFontSize] as the user's text scaler renders it —
  /// `MediaQuery.textScalerOf(context).scale(maxFontSize)` — because that is the
  /// text whose width has to fit.
  static double fontSizeFor({
    required double slotWidth,
    required Iterable<String> labels,
    required double scaledLabelSize,
    required TextDirection textDirection,
  }) {
    final double available = slotWidth - slotGutter;
    if (available <= 0) {
      // A slot no wider than the gutter cannot hold text at all, and Material
      // will lay the label out regardless. Showing nothing is the honest
      // answer; showing an overlapping row of words is not.
      return 0;
    }

    double widest = 0;
    for (final String label in labels) {
      for (final FontWeight weight in _labelWeights) {
        final TextPainter painter = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              fontSize: scaledLabelSize,
              fontWeight: weight,
              letterSpacing: 0,
            ),
          ),
          textDirection: textDirection,
        )..layout();
        widest = math.max(widest, painter.width);
      }
    }

    if (widest <= available) {
      return maxFontSize;
    }
    // Text width is linear in font size, so this lands exactly on `available`
    // once the framework re-applies the same text scaler.
    return maxFontSize * available / widest;
  }
}
