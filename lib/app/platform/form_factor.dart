import 'dart:ui' show FlutterView, Size;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Layout families SPECTA builds for.
///
/// The agreed architecture is one Flutter codebase serving Android phone and
/// Android TV, so the form factor selects presentation only; it never gates
/// features.
enum SpectaFormFactor {
  phone,
  tablet,
  television;

  bool get isTelevision => this == SpectaFormFactor.television;

  bool get isLargeScreen => this != SpectaFormFactor.phone;
}

/// Breakpoints in logical pixels, measured on the shortest side of the view.
abstract final class SpectaBreakpoints {
  /// At or above this, phone-portrait layouts are replaced by large layouts.
  static const double largeScreen = 600;

  /// At or above this, a large screen is treated as a television.
  static const double television = 960;
}

/// Pure mapping from a logical view size to a [SpectaFormFactor].
///
/// Kept free of Flutter bindings so it is unit-testable without a widget
/// harness.
SpectaFormFactor resolveFormFactor(Size logicalSize) {
  final double shortestSide = logicalSize.shortestSide;
  if (shortestSide >= SpectaBreakpoints.television) {
    return SpectaFormFactor.television;
  }
  if (shortestSide >= SpectaBreakpoints.largeScreen) {
    return SpectaFormFactor.tablet;
  }
  return SpectaFormFactor.phone;
}

/// The form factor of the primary view.
///
/// Phase 0 limitation: this is a viewport-based approximation. A 10" tablet
/// and a 1080p Android TV both report a large shortest side, so true TV
/// detection (Leanback feature / input-device capability) is a Phase 1
/// platform-channel task. This provider is the seam where that detection will
/// be installed, so no UI code needs to change when it lands.
final Provider<SpectaFormFactor> formFactorProvider =
    Provider<SpectaFormFactor>((Ref ref) {
      final List<FlutterView> views = WidgetsBinding
          .instance
          .platformDispatcher
          .views
          .toList();
      if (views.isEmpty) {
        return SpectaFormFactor.phone;
      }
      final FlutterView view = views.first;
      return resolveFormFactor(view.physicalSize / view.devicePixelRatio);
    });
