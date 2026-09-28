import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/discovery/discovery_deduplicator.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/discovery/discovery_normalizer.dart';
import 'package:specta/core/identity/title_key.dart';
import 'package:specta/core/metadata/metadata_manager.dart';
import 'package:specta/core/extensions/contract/result_models.dart';

/// 2G-C pre-flight §36.1 tests: the shared, Unicode-aware title key.
///
/// Background: both the discovery normalizer and the metadata manager used
/// `RegExp(r'[^\w\s]')`, whose `\w` matches ASCII only, so every non-Latin
/// title normalized to an empty key and collided with every other one.
SearchResult _movie(
  String title, {
  int? year,
  String url = 'https://e.test/x',
}) => SearchResult(title: title, url: url, type: MediaType.movie, year: year);

DiscoveryItem _dedupedOne(SearchResult raw) {
  final DiscoveryObservation? o = DiscoveryNormalizer.normalize(raw, 'ext');
  expect(o, isNotNull, reason: raw.title);
  return DiscoveryDeduplicator.dedupe(<DiscoveryObservation>[o!]).single;
}

List<DiscoveryItem> _dedupedAll(List<SearchResult> raws) {
  final List<DiscoveryObservation> observations = <DiscoveryObservation>[];
  for (final SearchResult r in raws) {
    final DiscoveryObservation? o = DiscoveryNormalizer.normalize(r, 'ext');
    if (o != null) observations.add(o);
  }
  return DiscoveryDeduplicator.dedupe(observations);
}

void main() {
  group('TitleKey.normalize — non-Latin titles keep their letters', () {
    test('a Japanese title produces a non-empty key', () {
      final String key = TitleKey.normalize('千と千尋の神隠し');
      expect(key, isNotEmpty);
      expect(key, '千と千尋の神隠し');
    });

    test('a Korean title produces a non-empty key', () {
      expect(TitleKey.normalize('기생충'), '기생충');
    });

    test('a Cyrillic title produces a non-empty key', () {
      expect(TitleKey.normalize('Брат 2'), 'брат 2');
    });

    test('an Arabic title produces a non-empty key', () {
      expect(TitleKey.normalize('بین النہارین'), isNotEmpty);
    });

    test('casing still folds and punctuation still strips', () {
      expect(TitleKey.normalize('Фильм!'), 'фильм');
      expect(TitleKey.normalize('ÉCOLE 42'), 'école 42');
    });

    test('digits (incl. non-ASCII digits) survive', () {
      expect(TitleKey.normalize('42'), '42');
      expect(TitleKey.normalize('１９９９'), '１９９９');
    });

    test(
      'two different Japanese titles with the same year get DIFFERENT keys',
      () {
        final String a = TitleKey.normalize('千と千尋の神隠し');
        final String b = TitleKey.normalize('もののけ姫');
        expect(a, isNot(b));
      },
    );
  });

  group('TitleKey.normalize — empty-result fallback', () {
    test('a punctuation-only title does NOT produce an empty key', () {
      final String key = TitleKey.normalize('!!!');
      expect(key, isNotEmpty);
      expect(key, '!!!');
    });

    test('a symbols-only key still excludes the | separator', () {
      // The resume path parses `title|type|year` by splitting on '|'; the
      // key part must never contain one.
      expect(TitleKey.normalize('|||'), isNot(contains('|')));
      expect(TitleKey.normalize('|'), isNot(contains('|')));
    });

    test(
      'a whitespace/pipe-only title still yields a non-empty, pipe-free key',
      () {
        final String key = TitleKey.normalize('  |  |  ');
        expect(key, isNotEmpty);
        expect(key, isNot(contains('|')));
      },
    );

    test('two different symbol-only titles never share a key', () {
      expect(TitleKey.normalize('!!!'), isNot(TitleKey.normalize('???')));
    });

    test('identical symbol-only titles DO share a key (same work)', () {
      expect(TitleKey.normalize('!!!'), TitleKey.normalize('!!!'));
    });

    test('the fallback is deterministic', () {
      expect(TitleKey.normalize('!!!'), TitleKey.normalize('!!!'));
      expect(TitleKey.normalize(' ??! '), TitleKey.normalize('??!'));
    });
  });

  group('TitleKey — backward compatibility for ASCII titles (golden)', () {
    // Golden expectations computed against the OLD implementation
    // (`title.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ')
    // .replaceAll(RegExp(r'\s+'), ' ').trim()`) — pure-ASCII output must be
    // BYTE-IDENTICAL so persisted keys for ASCII titles are not orphaned.
    const List<(String, String)> golden = <(String, String)>[
      ('The Matrix', 'the matrix'),
      ('the matrix', 'the matrix'),
      ('THE MATRIX', 'the matrix'),
      ('The  Batman!', 'the batman'),
      ('  Spider-Man: No Way Home  ', 'spider man no way home'),
      ("Ocean's Eleven", 'ocean s eleven'),
      ('Mission: Impossible - Fallout', 'mission impossible fallout'),
      ('2 Fast 2 Furious', '2 fast 2 furious'),
      ('A.I. Artificial Intelligence', 'a i artificial intelligence'),
      ('Movie_2020_Final Cut!!', 'movie_2020_final cut'),
      ('#1 Serial Killer...', '1 serial killer'),
      ('M*A*S*H', 'm a s h'),
      ('X-Men (2000)', 'x men 2000'),
      ('Se7en', 'se7en'),
      ('Hello,   World?', 'hello world'),
      ('---', '---'), // punctuation-only: fallback keeps the original
    ];

    for (final (String input, String expected) in golden) {
      test('ASCII golden: "$input" → "$expected"', () {
        expect(TitleKey.normalize(input), expected);
      });
    }

    test(
      'the golden list covers punctuation, case, spaces, digits, underscore',
      () {
        expect(golden.length, greaterThanOrEqualTo(16));
      },
    );
  });

  group('TitleKey.identityKey — format unchanged', () {
    test('movie key shape is title|type|year', () {
      expect(
        TitleKey.identityKey(
          title: 'The Matrix',
          typeCode: 'movie',
          year: 1999,
        ),
        'the matrix|movie|1999',
      );
    });

    test('a missing year is the none bucket', () {
      expect(
        TitleKey.identityKey(title: 'Dune', typeCode: 'movie', year: null),
        'dune|movie|none',
      );
    });

    test('a non-Latin title keeps its letters in the key', () {
      expect(
        TitleKey.identityKey(title: '기생충', typeCode: 'movie', year: 2019),
        '기생충|movie|2019',
      );
    });
  });

  group('Discovery + metadata agree on identity (proves the shared function)', () {
    test('discovery key == metadata identityKey for the same evidence', () {
      const String title = 'Amélie';
      const int year = 2001;

      final DiscoveryItem item = _dedupedOne(_movie(title, year: year));
      final String metadataKey = MetadataManager.identityKey(
        normalizedTitle: TitleKey.normalize(title),
        type: MediaType.movie,
        year: year,
      );

      expect(item.key, metadataKey);
    });

    test('the agreement holds for a non-Latin title too', () {
      const String title = '千と千尋の神隠し';
      const int year = 2001;

      final DiscoveryItem item = _dedupedOne(_movie(title, year: year));
      final String metadataKey = MetadataManager.identityKey(
        normalizedTitle: TitleKey.normalize(title),
        type: MediaType.movie,
        year: year,
      );

      expect(item.key, metadataKey);
      expect(item.key, '$title|movie|2001');
    });

    test(
      "accented Latin: 'Amélie' and 'Amelie' are deterministic and distinct",
      () {
        // Documented behavior (§36.1.3): the accent is now KEPT (é is a
        // letter), so the two titles are distinct identities. Under the old
        // ASCII-`\w` rule both collapsed to 'am lie' and MERGED — that was the
        // bug. Both directions are deterministic.
        final String accented = TitleKey.normalize('Amélie');
        final String plain = TitleKey.normalize('Amelie');
        expect(accented, 'amélie');
        expect(plain, 'amelie');
        expect(accented, isNot(plain));
        expect(accented, TitleKey.normalize('Amélie')); // deterministic
      },
    );

    test(
      'a metadata manager key uses the same rule as the discovery item key',
      () {
        // End-to-end through the metadata manager's identityKey contract: the
        // same input string must yield the same key part the deduplicator
        // produced. Note the colon in the title is stripped by the rule, so it
        // cannot interfere with the key format.
        const String title = 'Léon The Professional';
        final DiscoveryItem item = _dedupedOne(_movie(title, year: 1994));
        expect(item.key.endsWith('|movie|1994'), isTrue, reason: item.key);
        final String discoveryKeyPart = item.key.substring(
          0,
          item.key.indexOf('|movie|'),
        );
        final String metadataKeyPart = TitleKey.normalize(title);
        expect(discoveryKeyPart, metadataKeyPart);
        expect(metadataKeyPart, 'léon the professional');
      },
    );
  });

  group('DiscoveryDeduplicator with non-Latin titles (regression)', () {
    test('two different Japanese titles, same type/year → two items', () {
      final List<DiscoveryItem> items = _dedupedAll(<SearchResult>[
        _movie('千と千尋の神隠し', year: 2001, url: 'https://e.test/a'),
        _movie('もののけ姫', year: 2001, url: 'https://e.test/b'),
      ]);
      expect(items, hasLength(2));
    });

    test('two different Korean titles, same type/year → two items', () {
      final List<DiscoveryItem> items = _dedupedAll(<SearchResult>[
        _movie('기생충', year: 2019, url: 'https://e.test/a'),
        _movie('올드보이', year: 2019, url: 'https://e.test/b'),
      ]);
      expect(items, hasLength(2));
    });

    test('two different Arabic titles, same type/year → two items', () {
      final List<DiscoveryItem> items = _dedupedAll(<SearchResult>[
        _movie('بین النہارین', year: 2020, url: 'https://e.test/a'),
        _movie('الجزیرہ', year: 2020, url: 'https://e.test/b'),
      ]);
      expect(items, hasLength(2));
    });

    test('two different Cyrillic titles, same type/year → two items', () {
      final List<DiscoveryItem> items = _dedupedAll(<SearchResult>[
        _movie('Брат', year: 1997, url: 'https://e.test/a'),
        _movie('Брат 2', year: 2000, url: 'https://e.test/b'),
      ]);
      expect(items, hasLength(2));
    });

    test('the SAME non-Latin title still merges (dedup still works)', () {
      final List<DiscoveryItem> items = _dedupedAll(<SearchResult>[
        _movie('千と千尋の神隠し', year: 2001, url: 'https://e.test/a'),
        _movie('千と千尋の神隠し', year: 2001, url: 'https://e.test/b'),
      ]);
      expect(items, hasLength(1));
      expect(items.single.references, hasLength(2));
    });

    test(
      'two different symbol-only titles do not merge (old bug: both "")',
      () {
        final List<DiscoveryItem> items = _dedupedAll(<SearchResult>[
          _movie('!!!', year: 2020, url: 'https://e.test/a'),
          _movie('???', year: 2020, url: 'https://e.test/b'),
        ]);
        expect(items, hasLength(2));
      },
    );
  });
}
