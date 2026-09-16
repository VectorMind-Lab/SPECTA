import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/app/platform/form_factor.dart';

void main() {
  group('resolveFormFactor', () {
    test('treats a typical phone viewport as phone', () {
      expect(resolveFormFactor(const Size(390, 844)), SpectaFormFactor.phone);
    });

    test('treats a landscape phone viewport as phone', () {
      expect(resolveFormFactor(const Size(844, 390)), SpectaFormFactor.phone);
    });

    test('maps a large shortest side to tablet', () {
      expect(resolveFormFactor(const Size(800, 1280)), SpectaFormFactor.tablet);
    });

    test('maps television-sized viewports to television', () {
      expect(
        resolveFormFactor(const Size(1920, 1080)),
        SpectaFormFactor.television,
      );
    });

    test('breakpoints are inclusive', () {
      expect(
        resolveFormFactor(const Size(SpectaBreakpoints.largeScreen, 1000)),
        SpectaFormFactor.tablet,
      );
      expect(
        resolveFormFactor(const Size(SpectaBreakpoints.television, 1600)),
        SpectaFormFactor.television,
      );
      expect(
        resolveFormFactor(const Size(SpectaBreakpoints.television - 1, 1600)),
        SpectaFormFactor.tablet,
      );
    });
  });

  group('SpectaFormFactor', () {
    test('reports large-screen layouts', () {
      expect(SpectaFormFactor.phone.isLargeScreen, isFalse);
      expect(SpectaFormFactor.tablet.isLargeScreen, isTrue);
      expect(SpectaFormFactor.television.isLargeScreen, isTrue);
      expect(SpectaFormFactor.television.isTelevision, isTrue);
    });
  });
}
