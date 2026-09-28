import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/identity/extension_health.dart';

/// Slice 7: the health percentage is a DISPLAY MAPPING over recorded facts.
///
/// The rule this suite exists to enforce: no number is ever shown for a source
/// SPECTA has never actually seen succeed. Everything else is arithmetic.
void main() {
  group('the mapping table', () {
    test('no recorded activity reads "No data yet", not a number', () {
      expect(
        SourceHealthMapping.of(
          health: ExtensionHealth.healthy,
          hasRecordedActivity: false,
        ),
        SourceHealthDisplay.noDataYet,
        reason: 'a source nobody has run must not read 100%',
      );
      expect(SourceHealthDisplay.noDataYet.label, 'No data yet');
      expect(
        SourceHealthDisplay.noDataYet.label.contains('%'),
        isFalse,
        reason: 'a percentage here would be a fabricated measurement',
      );
    });

    test('healthy with recorded activity is 100%', () {
      expect(
        SourceHealthMapping.of(
          health: ExtensionHealth.healthy,
          hasRecordedActivity: true,
        ),
        SourceHealthDisplay.working,
      );
      expect(SourceHealthDisplay.working.label, '100%');
    });

    test('degraded is 50%', () {
      expect(
        SourceHealthMapping.of(
          health: ExtensionHealth.degraded,
          hasRecordedActivity: true,
        ),
        SourceHealthDisplay.degraded,
      );
      expect(SourceHealthDisplay.degraded.label, '50%');
    });

    test('unavailable is 10%', () {
      expect(
        SourceHealthMapping.of(
          health: ExtensionHealth.temporarilyUnavailable,
          hasRecordedActivity: true,
        ),
        SourceHealthDisplay.unavailable,
      );
      expect(SourceHealthDisplay.unavailable.label, '10%');
    });

    test('disabled and incompatible are both 0%', () {
      expect(SourceHealthDisplay.off.label, '0%');
      expect(SourceHealthDisplay.unsupported.label, '0%');
    });
  });

  group('precedence', () {
    test('a disabled node reads Off even when it has been working', () {
      // The user switched it off. Reporting 100% would describe a source that
      // is not currently serving anything.
      expect(
        SourceHealthMapping.of(
          health: ExtensionHealth.disabled,
          hasRecordedActivity: true,
        ),
        SourceHealthDisplay.off,
      );
    });

    test('a disabled node reads Off even with no activity either', () {
      expect(
        SourceHealthMapping.of(
          health: ExtensionHealth.disabled,
          hasRecordedActivity: false,
        ),
        SourceHealthDisplay.off,
        reason: '"Off" is the more useful fact than "No data yet"',
      );
    });

    test('incompatible wins over disabled', () {
      // The stronger statement: this build cannot run it at all, whether or
      // not the user also has it switched off.
      expect(
        SourceHealthMapping.of(
          health: ExtensionHealth.incompatible,
          hasRecordedActivity: false,
        ),
        SourceHealthDisplay.unsupported,
      );
    });

    test('degraded reads 50% even with no recorded success', () {
      // Failures ARE recorded activity. A source that has only ever failed has
      // data — it is bad data, not absent data.
      expect(
        SourceHealthMapping.of(
          health: ExtensionHealth.degraded,
          hasRecordedActivity: false,
        ),
        SourceHealthDisplay.degraded,
      );
      expect(
        SourceHealthMapping.of(
          health: ExtensionHealth.temporarilyUnavailable,
          hasRecordedActivity: false,
        ),
        SourceHealthDisplay.unavailable,
      );
    });
  });

  group('it is total and honest', () {
    test('every health state maps to something, and never to itself', () {
      for (final ExtensionHealth health in ExtensionHealth.values) {
        for (final bool activity in <bool>[true, false]) {
          final SourceHealthDisplay mapped = SourceHealthMapping.of(
            health: health,
            hasRecordedActivity: activity,
          );
          expect(
            mapped,
            isNotNull,
            reason: '$health / activity=$activity must map to something',
          );
          expect(
            mapped.label,
            isNotEmpty,
            reason: 'every display must have user-facing text',
          );
        }
      }
    });

    test('every display label is one of the agreed strings', () {
      // A hard guard against a stray percentage appearing in the enum.
      expect(
        <String>{
          for (final SourceHealthDisplay d in SourceHealthDisplay.values)
            d.label,
        },
        <String>{'No data yet', '100%', '50%', '10%', '0%'},
      );
    });

    test('the wording never mentions a provider or a site', () {
      for (final SourceHealthDisplay d in SourceHealthDisplay.values) {
        expect(d.label.toLowerCase(), isNot(contains('http')));
        expect(d.label.toLowerCase(), isNot(contains('.com')));
      }
      for (final ExtensionHealth health in ExtensionHealth.values) {
        final String text = SourceHealthMapping.describe(health).toLowerCase();
        expect(text, isNot(contains('http')));
        expect(text, isNot(contains('.com')));
      }
    });

    test('every state has a plain-language description', () {
      for (final ExtensionHealth health in ExtensionHealth.values) {
        expect(SourceHealthMapping.describe(health), isNotEmpty);
      }
    });
  });
}
