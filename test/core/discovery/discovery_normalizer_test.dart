import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/discovery/discovery_normalizer.dart';
import 'package:specta/core/extensions/contract/result_models.dart';

DiscoveryObservation? _normalize(
  SearchResult raw, {
  String extensionId = 'ext.a',
}) => DiscoveryNormalizer.normalize(raw, extensionId);

void main() {
  group('DiscoveryNormalizer', () {
    group('valid results', () {
      test('normalizes a complete movie result', () {
        final DiscoveryObservation? o = _normalize(
          const SearchResult(
            title: 'The Batman',
            url: 'https://e.test/movie/the-batman',
            type: MediaType.movie,
            cover: 'https://e.test/cover.jpg',
            year: 2022,
          ),
        );

        expect(o, isNotNull);
        expect(o!.title, 'The Batman');
        expect(o.keyTitle, 'the batman');
        expect(o.type, MediaType.movie);
        expect(o.year, 2022);
        expect(o.url, 'https://e.test/movie/the-batman');
        expect(o.cover, 'https://e.test/cover.jpg');
        expect(o.extensionId, 'ext.a');
        expect(o.raw.title, 'The Batman');
      });

      test('normalizes a series result', () {
        final DiscoveryObservation? o = _normalize(
          const SearchResult(
            title: 'Severance',
            url: 'https://e.test/series/severance',
            type: MediaType.series,
          ),
        );

        expect(o, isNotNull);
        expect(o!.type, MediaType.series);
        expect(o.year, isNull);
        expect(o.cover, isNull);
      });

      test('trims whitespace from title, URL and cover', () {
        final DiscoveryObservation? o = _normalize(
          const SearchResult(
            title: '  Alien   ',
            url: '  https://e.test/alien  ',
            type: MediaType.movie,
            cover: '   ',
          ),
        );

        expect(o!.title, 'Alien');
        expect(o.url, 'https://e.test/alien');
        expect(o.cover, isNull, reason: 'a blank cover is dropped, not kept');
      });

      test('title casing is preserved but the key is case-insensitive', () {
        final DiscoveryObservation? o = _normalize(
          const SearchResult(
            title: 'Mad Max: FURY Road',
            url: 'https://e.test/mm',
            type: MediaType.movie,
          ),
        );

        expect(o!.title, 'Mad Max: FURY Road');
        expect(o.keyTitle, 'mad max fury road');
      });
    });

    group('malformed values are dropped with a reason, never invented', () {
      test('blank title is dropped', () {
        expect(
          _normalize(
            const SearchResult(
              title: '   ',
              url: 'https://e.test/x',
              type: MediaType.movie,
            ),
          ),
          isNull,
        );
      });

      test('blank URL is dropped', () {
        expect(
          _normalize(
            const SearchResult(
              title: 'A Movie',
              url: '',
              type: MediaType.movie,
            ),
          ),
          isNull,
        );
      });

      test('oversized title is dropped (protocol-noise guard)', () {
        expect(
          _normalize(
            SearchResult(
              title: 'A' * 513,
              url: 'https://e.test/x',
              type: MediaType.movie,
            ),
          ),
          isNull,
        );
      });

      test('oversized URL is dropped (protocol-noise guard)', () {
        expect(
          _normalize(
            SearchResult(
              title: 'A Movie',
              url: 'https://e.test/${'x' * 513}',
              type: MediaType.movie,
            ),
          ),
          isNull,
        );
      });

      test('a 512-character title is still accepted (boundary)', () {
        expect(
          _normalize(
            SearchResult(
              title: 'A' * 512,
              url: 'https://e.test/x',
              type: MediaType.movie,
            ),
          ),
          isNotNull,
        );
      });
    });

    group('missing optional values are tolerated, not dropped', () {
      test('missing year is kept as null and never guessed', () {
        final DiscoveryObservation? o = _normalize(
          const SearchResult(
            title: 'No Year',
            url: 'https://e.test/ny',
            type: MediaType.movie,
          ),
        );

        expect(o, isNotNull);
        expect(o!.year, isNull);
      });

      test('missing cover is kept as null', () {
        final DiscoveryObservation? o = _normalize(
          const SearchResult(
            title: 'No Cover',
            url: 'https://e.test/nc',
            type: MediaType.series,
          ),
        );

        expect(o, isNotNull);
        expect(o!.cover, isNull);
      });
    });

    group('provider-specific references are preserved', () {
      test('the raw result and URL survive normalization untouched', () {
        const SearchResult raw = SearchResult(
          title: 'Preserved',
          url: 'https://provider.example/internal/id/12345?token=x',
          type: MediaType.series,
          year: 2015,
        );

        final DiscoveryObservation? o = _normalize(raw, extensionId: 'ext.z');

        expect(o!.raw, same(raw));
        expect(o.url, raw.url);
        expect(o.extensionId, 'ext.z');
      });
    });
  });
}
