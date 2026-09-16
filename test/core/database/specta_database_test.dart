@TestOn('vm')
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/database/daos/settings_dao.dart';
import 'package:specta/core/database/specta_database.dart';

// sqlite3 3.x ships its SQLite build as a Dart native code asset, which the
// Dart VM resolves automatically (including under `flutter test`); Android
// builds get the same treatment through drift_flutter. No host-OS loader
// override is needed.

void main() {
  late SpectaDatabase database;
  late SettingsDao dao;

  setUp(() {
    database = SpectaDatabase(NativeDatabase.memory());
    dao = SettingsDao(database);
  });

  tearDown(() => database.close());

  test('opens the schema at the version this build declares', () {
    expect(database.schemaVersion, 2);
  });

  test('writes and reads a setting back', () async {
    await dao.write('downloads.concurrency', '3');

    expect(await dao.read('downloads.concurrency'), '3');
  });

  test('replacing a value keeps a single row per key', () async {
    await dao.write('downloads.concurrency', '3');
    await dao.write('downloads.concurrency', '5');

    expect(await dao.readAll(), <String, String>{'downloads.concurrency': '5'});
  });

  test('missing settings read as null and can be removed', () async {
    expect(await dao.read('absent.key'), isNull);

    await dao.write('absent.key', 'value');
    await dao.remove('absent.key');

    expect(await dao.read('absent.key'), isNull);
  });
}
