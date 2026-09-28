import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/database/database_capabilities.dart';

void main() {
  test('the probe answers without throwing, whatever the environment', () {
    // `flutter_test` installs a binding even for a plain `test`, so the honest
    // assertion here is not a specific value but the contract that matters: the
    // probe must never throw, because callers use it as a guard.
    expect(() => catalogueDatabaseUsable(), returnsNormally);
  });

  testWidgets('the probe reports usable inside a running app surface', (
    WidgetTester tester,
  ) async {
    // This is the environment the catalogue step actually runs in.
    expect(catalogueDatabaseUsable(), isTrue);
  });
}
