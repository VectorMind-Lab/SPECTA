import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/tmdb/tmdb_media_identity.dart';
import 'package:specta/core/tmdb/tmdb_provider_matcher.dart';

import '../../support/discovery_test_harness.dart';

/// One search-result row as an extension would report it.
Map<String, Object?> _row(
  String title, {
  String url = 'https://ext.test/item/1',
  MediaType type = MediaType.movie,
  int? year,
}) => <String, Object?>{
  'title': title,
  'url': url,
  'type': type.code,
  'year': ?year,
};

const SpectaMediaIdentity _movieIdentity = SpectaMediaIdentity(
  type: MediaType.movie,
  tmdbId: 603,
);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('specta_matcher');
    addTearDown(() => tempDir.delete(recursive: true));
  });

  /// Harness with ONE extension whose search answers [rows].
  Future<DiscoveryTestHarness> harnessServing(List<Object?> rows) async {
    final DiscoveryTestHarness h = DiscoveryTestHarness(
      sandbox: ScriptedJsSandbox(),
    );
    await h.installExtension(tempDir, 'com.test.provider');
    final ScriptedJsSandbox sb = h.sandbox as ScriptedJsSandbox;
    sb.searchScripts = <Object>[searchPayload(rows)];
    return h;
  }

  group('TmdbProviderMatcher.match â€” scoring', () {
    test('exact normalized title + exact year matches', () async {
      final DiscoveryTestHarness h = await harnessServing(<Object?>[
        _row('the. Matrix!', year: 1999, url: 'https://ext.test/m/603'),
        _row('Inception', year: 2010, url: 'https://ext.test/m/other'),
      ]);

      final TmdbMatchResult result = await TmdbProviderMatcher.match(
        identity: _movieIdentity,
        title: 'The Matrix',
        extensionManager: h.manager,
        year: 1999,
      );

      expect(result.hasMatch, isTrue);
      // Discovery keeps the first-seen observed title; identity matching is
      // done on the NORMALIZED key, not the display string.
      expect(result.matchedDiscoveryItem!.title, 'the. Matrix!');
      expect(result.matchedDiscoveryItem!.key, 'the matrix|movie|1999');
      expect(result.references.single.url, 'https://ext.test/m/603');
      expect(result.extensionReferences, <String, String>{
        'com.test.provider': 'https://ext.test/m/603',
      });
    });

    test('Â±1 year still matches (international release offset)', () async {
      final DiscoveryTestHarness h = await harnessServing(<Object?>[
        _row('The Matrix', year: 1998),
      ]);

      final TmdbMatchResult result = await TmdbProviderMatcher.match(
        identity: _movieIdentity,
        title: 'The Matrix',
        extensionManager: h.manager,
        year: 1999,
      );

      expect(result.hasMatch, isTrue);
    });

    test(
      'a title-year far apart with only a containment match fails',
      () async {
        // Containment (+3) with a 10-year gap (-5) = -2, below the threshold.
        final DiscoveryTestHarness h = await harnessServing(<Object?>[
          _row('The Matrix Reloaded', year: 2003),
        ]);

        final TmdbMatchResult result = await TmdbProviderMatcher.match(
          identity: _movieIdentity,
          title: 'The Matrix',
          extensionManager: h.manager,
          year: 1999,
        );

        expect(result.hasMatch, isFalse);
        expect(result.references, isEmpty);
        expect(result.matchedDiscoveryItem, isNull);
      },
    );

    test('missing year on both sides still matches on exact title', () async {
      final DiscoveryTestHarness h = await harnessServing(<Object?>[
        _row('The Matrix'), // no year observed
      ]);

      final TmdbMatchResult result = await TmdbProviderMatcher.match(
        identity: _movieIdentity,
        title: 'The Matrix',
        extensionManager: h.manager,
        year: null,
      );

      expect(result.hasMatch, isTrue);
    });

    test(
      'the best-scoring candidate wins when several titles are near',
      () async {
        // "The Matrix" (exact, +10) vs "The Matrix Reloaded" (containment, +3)
        // with the same year: the exact one must be selected.
        final DiscoveryTestHarness h = await harnessServing(<Object?>[
          _row(
            'The Matrix Reloaded',
            year: 1999,
            url: 'https://ext.test/reloaded',
          ),
          _row('The Matrix', year: 1999, url: 'https://ext.test/original'),
        ]);

        final TmdbMatchResult result = await TmdbProviderMatcher.match(
          identity: _movieIdentity,
          title: 'The Matrix',
          extensionManager: h.manager,
          year: 1999,
        );

        expect(result.hasMatch, isTrue);
        expect(result.matchedDiscoveryItem!.title, 'The Matrix');
        expect(result.references.single.url, 'https://ext.test/original');
      },
    );
  });

  group('TmdbProviderMatcher.match â€” boundaries', () {
    test(
      'media type is strict: a series with the same title never matches',
      () async {
        final DiscoveryTestHarness h = await harnessServing(<Object?>[
          _row(
            'The Matrix',
            type: MediaType.series, // wrong type for a movie identity
            year: 1999,
            url: 'https://ext.test/tv',
          ),
        ]);

        final TmdbMatchResult result = await TmdbProviderMatcher.match(
          identity: _movieIdentity,
          title: 'The Matrix',
          extensionManager: h.manager,
          year: 1999,
        );

        expect(result.hasMatch, isFalse);
      },
    );

    test('an uninstalled-extension round yields no match, no throw', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();

      final TmdbMatchResult result = await TmdbProviderMatcher.match(
        identity: _movieIdentity,
        title: 'The Matrix',
        extensionManager: h.manager,
        year: 1999,
      );

      expect(result.hasMatch, isFalse);
      expect(result.identity, _movieIdentity);
    });

    test(
      'a blank title short-circuits without dispatching discovery',
      () async {
        final DiscoveryTestHarness h = DiscoveryTestHarness(
          sandbox: ScriptedJsSandbox(),
        );
        await h.installExtension(tempDir, 'com.test.provider');
        final ScriptedJsSandbox sb = h.sandbox as ScriptedJsSandbox;
        sb.searchScripts = <Object>['[]'];

        final TmdbMatchResult result = await TmdbProviderMatcher.match(
          identity: _movieIdentity,
          title: '   ',
          extensionManager: h.manager,
        );

        expect(result.hasMatch, isFalse);
        // The invalid request must never reach the extension layer.
        expect(sb.searchCallCount, 0);
      },
    );

    test('a completely different title yields no match', () async {
      final DiscoveryTestHarness h = await harnessServing(<Object?>[
        _row('Casablanca', year: 1942),
      ]);

      final TmdbMatchResult result = await TmdbProviderMatcher.match(
        identity: _movieIdentity,
        title: 'The Matrix',
        extensionManager: h.manager,
        year: 1999,
      );

      expect(result.hasMatch, isFalse);
    });

    test('containment match with agreeing year passes the threshold', () async {
      // Discovery reports a longer title containing the TMDB title:
      // containment (+3) + exact year (+10) = 13 â‰¥ 5.
      final DiscoveryTestHarness h = await harnessServing(<Object?>[
        _row('The Matrix (1999)', year: 1999, url: 'https://ext.test/long'),
      ]);

      final TmdbMatchResult result = await TmdbProviderMatcher.match(
        identity: _movieIdentity,
        title: 'The Matrix',
        extensionManager: h.manager,
        year: 1999,
      );

      expect(result.hasMatch, isTrue);
      expect(result.references.single.url, 'https://ext.test/long');
    });

    test('the result always carries the requested identity', () async {
      final DiscoveryTestHarness h = await harnessServing(<Object?>[
        _row('The Matrix', year: 1999),
      ]);

      final TmdbMatchResult result = await TmdbProviderMatcher.match(
        identity: _movieIdentity,
        title: 'The Matrix',
        extensionManager: h.manager,
        year: 1999,
      );

      expect(result.identity, _movieIdentity);
      expect(result.identity.code, 'movie:603');
    });
  });
}
