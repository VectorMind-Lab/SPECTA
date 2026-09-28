import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/discovery/discovery_deduplicator.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/discovery/discovery_normalizer.dart';
import 'package:specta/core/extensions/contract/result_models.dart';

/// Helper: normalize + dedupe in one step, the way the coordinator does.
List<DiscoveryItem> _dedupeRaw(Map<String, List<SearchResult>> byExtension) {
  final List<DiscoveryObservation> observations = <DiscoveryObservation>[];
  byExtension.forEach((String extId, List<SearchResult> results) {
    for (final SearchResult r in results) {
      final DiscoveryObservation? o = DiscoveryNormalizer.normalize(r, extId);
      if (o != null) observations.add(o);
    }
  });
  return DiscoveryDeduplicator.dedupe(observations);
}

SearchResult _movie(
  String title, {
  int? year,
  String url = 'https://e.test/default',
}) => SearchResult(title: title, url: url, type: MediaType.movie, year: year);

SearchResult _series(
  String title, {
  int? year,
  String url = 'https://e.test/default',
}) => SearchResult(title: title, url: url, type: MediaType.series, year: year);

void main() {
  group('DiscoveryDeduplicator', () {
    group('exact duplicates', () {
      test(
        'the same observation twice from ONE extension is one reference',
        () {
          final List<DiscoveryItem>
          items = _dedupeRaw(<String, List<SearchResult>>{
            'ext.a': <SearchResult>[
              _movie('Inception', year: 2010, url: 'https://a.test/inception'),
              _movie('Inception', year: 2010, url: 'https://a.test/inception'),
            ],
          });

          expect(items.length, 1);
          expect(items.single.references.length, 1);
          expect(items.single.references.single.extensionId, 'ext.a');
        },
      );

      test(
        'the same URL from TWO different extensions keeps both references',
        () {
          final List<DiscoveryItem> items = _dedupeRaw(
            <String, List<SearchResult>>{
              'ext.a': <SearchResult>[
                _movie('Heat', year: 1995, url: 'https://shared.test/heat'),
              ],
              'ext.b': <SearchResult>[
                _movie('Heat', year: 1995, url: 'https://shared.test/heat'),
              ],
            },
          );

          expect(items.length, 1);
          expect(items.single.references.length, 2);
          expect(
            items.single.references.map(
              (DiscoveryReference r) => r.extensionId,
            ),
            <String>['ext.a', 'ext.b'],
          );
        },
      );
    });

    group('title variants merge', () {
      test('casing differences merge', () {
        final List<DiscoveryItem> items = _dedupeRaw(
          <String, List<SearchResult>>{
            'ext.a': <SearchResult>[
              _movie('THE MATRIX', year: 1999, url: 'https://a.test/m'),
            ],
            'ext.b': <SearchResult>[
              _movie('the matrix', year: 1999, url: 'https://b.test/m'),
            ],
          },
        );

        expect(items.length, 1);
        expect(items.single.references.length, 2);
        expect(
          items.single.title,
          'THE MATRIX',
          reason: 'display title stays as first observed',
        );
      });

      test('whitespace differences merge', () {
        final List<DiscoveryItem> items = _dedupeRaw(
          <String, List<SearchResult>>{
            'ext.a': <SearchResult>[
              _movie('Blade    Runner', year: 1982, url: 'https://a.test/b'),
            ],
            'ext.b': <SearchResult>[
              _movie('Blade Runner', year: 1982, url: 'https://b.test/b'),
            ],
          },
        );

        expect(items.length, 1);
        expect(items.single.references.length, 2);
      });

      test('punctuation differences merge', () {
        final List<DiscoveryItem> items = _dedupeRaw(
          <String, List<SearchResult>>{
            'ext.a': <SearchResult>[
              _movie(
                'Spider-Man: No Way Home!',
                year: 2021,
                url: 'https://a.test/s',
              ),
            ],
            'ext.b': <SearchResult>[
              _movie(
                'Spider Man No Way Home',
                year: 2021,
                url: 'https://b.test/s',
              ),
            ],
          },
        );

        expect(items.length, 1);
        expect(items.single.references.length, 2);
      });
    });

    group('unrelated works stay separate', () {
      test('different years do not merge', () {
        final List<DiscoveryItem> items = _dedupeRaw(
          <String, List<SearchResult>>{
            'ext.a': <SearchResult>[
              _movie('The Batman', year: 2022, url: 'https://a.test/2022'),
            ],
            'ext.b': <SearchResult>[
              _movie('The Batman', year: 1966, url: 'https://b.test/1966'),
            ],
          },
        );

        expect(items.length, 2);
        expect(items.map((DiscoveryItem i) => i.year), <int?>[2022, 1966]);
      });

      test('a year does not merge with a missing year', () {
        final List<DiscoveryItem> items = _dedupeRaw(
          <String, List<SearchResult>>{
            'ext.a': <SearchResult>[
              _movie('Dune', year: 2021, url: 'https://a.test/d'),
            ],
            'ext.b': <SearchResult>[_movie('Dune', url: 'https://b.test/d')],
          },
        );

        expect(items.length, 2);
      });

      test('different media types do not merge', () {
        final List<DiscoveryItem> items = _dedupeRaw(
          <String, List<SearchResult>>{
            'ext.a': <SearchResult>[
              _movie('Last of Us', year: 2010, url: 'https://a.test/l'),
            ],
            'ext.b': <SearchResult>[
              _series('Last of Us', year: 2010, url: 'https://b.test/l'),
            ],
          },
        );

        expect(items.length, 2);
      });

      test('similar but different titles do not merge', () {
        final List<DiscoveryItem> items = _dedupeRaw(
          <String, List<SearchResult>>{
            'ext.a': <SearchResult>[
              _movie('Alien', year: 1979, url: 'https://a.test/al'),
            ],
            'ext.b': <SearchResult>[
              _movie('Aliens', year: 1986, url: 'https://b.test/als'),
            ],
          },
        );

        expect(items.length, 2);
      });

      test('remakes with the same title but different years stay separate', () {
        final List<DiscoveryItem> items = _dedupeRaw(
          <String, List<SearchResult>>{
            'ext.a': <SearchResult>[
              _movie('Ocean', year: 1960, url: 'https://a.test/o60'),
            ],
            'ext.b': <SearchResult>[
              _movie('Ocean', year: 2001, url: 'https://b.test/o01'),
            ],
          },
        );

        expect(items.length, 2);
      });
    });

    group('provenance (mandatory rule)', () {
      test(
        'one unified item keeps a reference for EVERY contributing extension',
        () {
          final List<DiscoveryItem> items = _dedupeRaw(
            <String, List<SearchResult>>{
              'ext.a': <SearchResult>[
                _movie('Arrival', year: 2016, url: 'https://a.test/arrival'),
              ],
              'ext.b': <SearchResult>[
                _movie('arrivals', year: 2016, url: 'https://b.test/arrival'),
              ],
              'ext.c': <SearchResult>[
                _movie('ARRIVAL!!', year: 2016, url: 'https://c.test/arrival'),
              ],
            },
          );

          // 'arrivals' is a different title key, so it stays its own item;
          // ext.a and ext.c merge.
          expect(items.length, 2);

          final DiscoveryItem merged = items.first;
          expect(merged.title, 'Arrival');
          expect(merged.references.length, 2);
          expect(
            merged.references.map((DiscoveryReference r) => r.extensionId),
            <String>['ext.a', 'ext.c'],
          );
          expect(
            merged.references.every((DiscoveryReference r) => r.url.isNotEmpty),
            isTrue,
            reason: 'per-extension references keep their URLs for 2C/2D',
          );
        },
      );

      test('provenance survives an observation order swap', () {
        final List<DiscoveryItem> forward = _dedupeRaw(
          <String, List<SearchResult>>{
            'ext.a': <SearchResult>[_movie('Tenet', year: 2020)],
            'ext.b': <SearchResult>[_movie('Tenet', year: 2020)],
          },
        );
        final List<DiscoveryItem> reverse = _dedupeRaw(
          <String, List<SearchResult>>{
            'ext.b': <SearchResult>[_movie('Tenet', year: 2020)],
            'ext.a': <SearchResult>[_movie('Tenet', year: 2020)],
          },
        );

        expect(forward.single.references.length, 2);
        expect(reverse.single.references.length, 2);
        expect(forward.single.title, 'Tenet');
        expect(reverse.single.title, 'Tenet');
      });

      test(
        'a merged item keeps the first-seen cover but gains one if absent',
        () {
          final List<DiscoveryItem> items = _dedupeRaw(
            <String, List<SearchResult>>{
              'ext.a': <SearchResult>[
                SearchResult(
                  title: 'No Art',
                  url: 'https://a.test/na',
                  type: MediaType.movie,
                  year: 2000,
                ),
              ],
              'ext.b': <SearchResult>[
                SearchResult(
                  title: 'No Art',
                  url: 'https://b.test/na',
                  type: MediaType.movie,
                  year: 2000,
                  cover: 'https://b.test/art.jpg',
                ),
              ],
            },
          );

          expect(items.single.cover, 'https://b.test/art.jpg');
          expect(items.single.references.length, 2);
        },
      );

      test('isCrossExtension reflects the merge', () {
        final List<DiscoveryItem> items = _dedupeRaw(
          <String, List<SearchResult>>{
            'ext.a': <SearchResult>[_movie('Solo', year: 2001)],
            'ext.b': <SearchResult>[_movie('Solo', year: 2001)],
          },
        );

        expect(items.single.isCrossExtension, isTrue);
      });
    });

    group('ordering and stability', () {
      test('first-seen order is stable and deterministic', () {
        final List<DiscoveryItem> items = _dedupeRaw(
          <String, List<SearchResult>>{
            'ext.a': <SearchResult>[
              _movie('Beta', year: 2001, url: 'https://a.test/beta'),
              _movie('Alpha', year: 2002, url: 'https://a.test/alpha'),
              _movie('Gamma', year: 2003, url: 'https://a.test/gamma'),
            ],
          },
        );

        expect(items.map((DiscoveryItem i) => i.title), <String>[
          'Beta',
          'Alpha',
          'Gamma',
        ]);
      });

      test('merging does not change item order', () {
        final List<DiscoveryItem> items = _dedupeRaw(
          <String, List<SearchResult>>{
            'ext.a': <SearchResult>[
              _movie('First', year: 2001, url: 'https://a.test/1'),
              _movie('Second', year: 2002, url: 'https://a.test/2'),
            ],
            'ext.b': <SearchResult>[
              _movie('First', year: 2001, url: 'https://b.test/1'),
            ],
          },
        );

        expect(items.map((DiscoveryItem i) => i.title), <String>[
          'First',
          'Second',
        ]);
      });

      test('the identity key is deterministic', () {
        final List<DiscoveryItem> items = _dedupeRaw(
          <String, List<SearchResult>>{
            'ext.a': <SearchResult>[_movie('A Movie!', year: 2020)],
          },
        );

        expect(items.single.key, 'a movie|movie|2020');
      });
    });

    group('within one extension', () {
      test(
        'same title+year+type with different URLs stays as two references',
        () {
          final List<DiscoveryItem> items = _dedupeRaw(
            <String, List<SearchResult>>{
              'ext.a': <SearchResult>[
                _movie('Film', year: 2020, url: 'https://a.test/cut-a'),
                _movie('Film', year: 2020, url: 'https://a.test/cut-b'),
              ],
            },
          );

          expect(items.length, 1);
          expect(items.single.references.length, 2);
        },
      );
    });
  });
}
