import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/identity/extension_health.dart';

void main() {
  group('ExtensionHealthRules.evaluate', () {
    test('a compatible, enabled, failure-free extension is healthy', () {
      expect(
        ExtensionHealthRules.evaluate(
          enabled: true,
          apiCompatible: true,
          recentFailureCount: 0,
        ),
        ExtensionHealth.healthy,
      );
    });

    test('recent failures degrade, then make it temporarily unavailable', () {
      ExtensionHealth at(int failures) => ExtensionHealthRules.evaluate(
        enabled: true,
        apiCompatible: true,
        recentFailureCount: failures,
      );

      expect(
        at(ExtensionHealthRules.degradedAtFailures),
        ExtensionHealth.degraded,
      );
      expect(
        at(ExtensionHealthRules.degradedAtFailures + 1),
        ExtensionHealth.degraded,
      );
      expect(
        at(ExtensionHealthRules.unavailableAtFailures),
        ExtensionHealth.temporarilyUnavailable,
      );
      expect(at(99), ExtensionHealth.temporarilyUnavailable);
    });

    test(
      'a disabled extension is reported disabled regardless of failures',
      () {
        expect(
          ExtensionHealthRules.evaluate(
            enabled: false,
            apiCompatible: true,
            recentFailureCount: 5,
          ),
          ExtensionHealth.disabled,
        );
      },
    );

    test('incompatibility outranks the user flag', () {
      expect(
        ExtensionHealthRules.evaluate(
          enabled: false,
          apiCompatible: false,
          recentFailureCount: 0,
        ),
        ExtensionHealth.incompatible,
      );
      expect(
        ExtensionHealthRules.evaluate(
          enabled: true,
          apiCompatible: false,
          recentFailureCount: 9,
        ),
        ExtensionHealth.incompatible,
      );
    });

    test('classification never mutates: it is a pure function', () {
      // Calling it repeatedly with the same facts yields the same answer, and
      // nothing about the extension changes. There is no auto-disable step.
      const bool enabled = true;
      for (int i = 0; i < 5; i++) {
        expect(
          ExtensionHealthRules.evaluate(
            enabled: enabled,
            apiCompatible: true,
            recentFailureCount: 10,
          ),
          ExtensionHealth.temporarilyUnavailable,
        );
      }
      expect(enabled, isTrue);
    });

    test('failure counts are described within a 24 hour window', () {
      expect(ExtensionHealthRules.failureWindow, const Duration(hours: 24));
    });
  });

  group('ExtensionHealth', () {
    test('exposes stable codes', () {
      expect(ExtensionHealth.healthy.code, 'healthy');
      expect(ExtensionHealth.degraded.code, 'degraded');
      expect(
        ExtensionHealth.temporarilyUnavailable.code,
        'temporarily_unavailable',
      );
      expect(ExtensionHealth.disabled.code, 'disabled');
      expect(ExtensionHealth.incompatible.code, 'incompatible');
    });

    test('reports which states would still be executed', () {
      expect(ExtensionHealth.healthy.isRunnable, isTrue);
      expect(ExtensionHealth.degraded.isRunnable, isTrue);
      expect(ExtensionHealth.temporarilyUnavailable.isRunnable, isTrue);
      expect(ExtensionHealth.disabled.isRunnable, isFalse);
      expect(ExtensionHealth.incompatible.isRunnable, isFalse);
    });

    test('round-trips through fromCode', () {
      for (final ExtensionHealth health in ExtensionHealth.values) {
        expect(ExtensionHealth.fromCode(health.code), health);
      }
      expect(ExtensionHealth.fromCode('nonsense'), isNull);
    });
  });

  group('ExtensionHealthState', () {
    test('carries the facts behind the classification', () {
      const ExtensionHealthState state = ExtensionHealthState(
        health: ExtensionHealth.degraded,
        recentFailureCount: 2,
        apiVersion: 2,
      );
      expect(state.toString(), contains('degraded'));
      expect(state.recentFailureCount, 2);
      expect(state.apiVersion, 2);
    });
  });
}
