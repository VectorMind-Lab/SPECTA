import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/library/library_dao.dart';
import 'package:specta/core/library/watch_progress.dart';

void main() {
  test('canonical progress and media-reference identity survive a real reopen', () async {
    final Directory dir = await Directory.systemTemp.createTemp('specta-c1');
    addTearDown(() => dir.delete(recursive: true));
    final File file = File('${dir.path}/specta.sqlite');

    final SpectaDatabase first = SpectaDatabase(NativeDatabase(file));
    final LibraryDao firstDao = LibraryDao(first);
    await firstDao.upsert(
      WatchProgress(
        id: 'anilist:16498',
        mediaKey: 'anilist:16498',
        mediaType: MediaType.anime,
        title: 'Spirited Away',
        canonicalId: 'anilist:16498',
        identityVersion: 2,
        position: const Duration(seconds: 12),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    await firstDao.saveReferences(
      'anilist:16498',
      const <DiscoveryReference>[
        DiscoveryReference(extensionId: 'extA', url: 'https://a.test/anime'),
      ],
      canonicalId: 'anilist:16498',
      identityVersion: 2,
    );
    await first.close();

    final SpectaDatabase second = SpectaDatabase(NativeDatabase(file));
    final LibraryDao secondDao = LibraryDao(second);
    final WatchProgress? progress = await secondDao.progressFor(
      'anilist:16498',
    );
    expect(progress!.mediaType, MediaType.anime);
    expect(progress.canonicalId, 'anilist:16498');
    expect(progress.identityVersion, 2);
    expect(await secondDao.referencesFor('anilist:16498'), hasLength(1));

    final row = await second
        .customSelect(
          'SELECT canonical_id, identity_version FROM media_references LIMIT 1',
        )
        .getSingle();
    expect(row.read<String>('canonical_id'), 'anilist:16498');
    expect(row.read<int>('identity_version'), 2);
    await second.close();
  });
}
