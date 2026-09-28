import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/anilist/anilist_client.dart';
import 'package:specta/core/anilist/anilist_dto.dart';
import 'package:specta/core/anilist/anilist_normalizer.dart';
import 'package:specta/core/anilist/anilist_transport.dart';
import 'package:specta/core/discovery/discovery_deduplicator.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/discovery/discovery_normalizer.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/metadata/catalogue_enricher.dart';
import 'package:specta/core/metadata/metadata_models.dart';

import '../../support/anilist_test_harness.dart';

AniListMedia parseMedia(Map<String, Object?> json) =>
    AniListMedia.fromJson(json)!;

Map<String, Object?> mediaJson({
  int id = 16498,
  String? english = 'Spirited Away',
  String? romaji = 'Sen to Chihiro no Kamikakushi',
  String? native = 'åƒã¨åƒå°‹ã®ç¥žéš ã—',
  String format = 'MOVIE',
  int? episodes,
  String? startDate = '2001-07-20',
}) {
  return <String, Object?>{
    'id': id,
    'title': <String, Object?>{
      'romaji': romaji,
      'english': english,
      'native': native,
    },
    'description': 'A girl works in a bathhouse for spirits.',
    'startDate': startDate,
    'format': format,
    'status': 'FINISHED',
    'episodes': episodes,
    'duration': 125,
    'averageScore': 85,
    'genres': <String>['Fantasy', 'Adventure'],
    'coverImage': 'https://img.ani/st.jpg',
    'bannerImage': 'https://img.ani/bn.jpg',
    'studios': <String, Object?>{
      'nodes': <Object?>[
        <String, Object?>{'name': 'Studio Ghibli', 'isAnimationStudio': true},
        <String, Object?>{'name': 'Some Publisher', 'isAnimationStudio': false},
      ],
    },
  };
}

void main() {
  group('AniList DTO â€” defensive parsing', () {
    test('maps the fields SPECTA consumes', () {
      final AniListMedia media = parseMedia(mediaJson());

      expect(media.id, 16498);
      expect(media.title.english, 'Spirited Away');
      expect(media.title.romaji, 'Sen to Chihiro no Kamikakushi');
      expect(media.title.native, 'åƒã¨åƒå°‹ã®ç¥žéš ã—');
      expect(media.year, 2001);
      expect(media.format, AniListFormat.movie);
      expect(media.duration, 125);
      expect(media.episodes, isNull);
      expect(media.genres, <String>['Fantasy', 'Adventure']);
      expect(media.coverImageUrl, 'https://img.ani/st.jpg');
      expect(media.bannerImageUrl, 'https://img.ani/bn.jpg');
      // AniList scores 0-100; SPECTA's metadata scale is 0-10.
      expect(media.rating, closeTo(8.5, 0.0001));
    });

    test('a TV format with an episode count is preserved', () {
      final AniListMedia media = parseMedia(
        mediaJson(format: 'TV', episodes: 12),
      );

      expect(media.format, AniListFormat.tv);
      expect(media.episodes, 12);
    });

    test('an unknown format degrades to unknown rather than throwing', () {
      expect(
        parseMedia(mediaJson(format: 'PODCAST')).format,
        AniListFormat.unknown,
      );
    });

    test('rejects a record with no id, a non-positive id, or no title', () {
      final Map<String, Object?> noId = mediaJson()..remove('id');
      expect(AniListMedia.fromJson(noId), isNull);
      expect(AniListMedia.fromJson(mediaJson(id: 0)), isNull);
      expect(AniListMedia.fromJson(mediaJson(id: -5)), isNull);

      expect(AniListMedia.fromJson(mediaJson()..remove('title')), isNull);
    });

    test('wrong-typed fields degrade to null instead of throwing', () {
      final AniListMedia? media = AniListMedia.fromJson(<String, Object?>{
        'id': 16498,
        'title': <String, Object?>{'english': 'Spirited Away'},
        'description': 12345,
        'episodes': 'twelve',
        'duration': <String>[],
        'averageScore': 'high',
        'genres': 'Fantasy',
        'studios': 'Ghibli',
      });

      expect(media, isNotNull);
      expect(media!.description, isNull);
      expect(media.episodes, isNull);
      expect(media.duration, isNull);
      expect(media.averageScore, isNull);
      expect(media.genres, isEmpty);
      expect(media.studios, isEmpty);
    });

    test('a non-map payload is rejected', () {
      expect(AniListMedia.fromJson(null), isNull);
      expect(AniListMedia.fromJson('nope'), isNull);
      expect(AniListMedia.fromJson(<Object?>[]), isNull);
    });

    test('title variants are preserved and display falls back sensibly', () {
      expect(
        parseMedia(mediaJson(romaji: null, native: null)).title.display,
        'Spirited Away',
      );
      expect(
        parseMedia(mediaJson(english: null)).title.display,
        'Sen to Chihiro no Kamikakushi',
      );
      expect(
        parseMedia(mediaJson(english: null, romaji: null)).title.display,
        'åƒã¨åƒå°‹ã®ç¥žéš ã—',
      );
    });
  });

  group('AniList enrichment â€” catalogue-only anime (device-found regression)', () {
    // A real AniList search result carries NO extension reference. Details used
    // to fail on exactly that item, because the base round had nothing to
    // return. AniList owns anime identity, so it must be able to COMPLETE the
    // work rather than leave the screen empty.
    test(
      'with no extension metadata, AniList supplies the whole item',
      () async {
        final FakeAniListTransport transport = FakeAniListTransport(
          response: AniListHttpResponse(
            statusCode: 200,
            body: anilistMediaBody(id: 1),
          ),
        );

        final EnrichmentResult result = await CatalogueEnricher.enrich(
          base: null,
          type: MediaType.anime,
          title: 'Cowboy Bebop',
          anilist: AniListClient(transport: transport),
          anilistId: 1,
        );

        expect(result.item, isNotNull);
        expect(result.item!.type, MediaType.anime);
        expect(result.item!.key, 'anilist:1');
        expect(result.item!.canonicalId, 'anilist:1');
        expect(result.item!.identityVersion, 2);
        expect(result.reports.single.providerId, 'anilist');
        expect(result.reports.single.outcome, ProviderOutcome.matched);
      },
    );

    test('extension metadata is preserved and only filled in', () async {
      final FakeAniListTransport transport = FakeAniListTransport(
        response: AniListHttpResponse(
          statusCode: 200,
          body: anilistMediaBody(id: 1),
        ),
      );
      const MetadataItem base = MetadataItem(
        key: 'anilist:1',
        title: 'Cowboy Bebop (extension title)',
        type: MediaType.anime,
        details: <ReferenceMetadata>[
          ReferenceMetadata(
            extensionId: 'com.ext.anime',
            referenceUrl: 'https://ext/anime/1',
            title: 'Cowboy Bebop (extension title)',
          ),
        ],
      );

      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: base,
        type: MediaType.anime,
        title: 'Cowboy Bebop',
        anilist: AniListClient(transport: transport),
        anilistId: 1,
      );

      // Identity and the extension's own title are untouched.
      expect(result.item!.key, 'anilist:1');
      expect(result.item!.title, 'Cowboy Bebop (extension title)');
      // The provider contributed additively.
      expect(result.item!.details, hasLength(2));
      expect(result.item!.description, isNotNull);
    });

    test('an AniList outage never mints an identity', () async {
      final FakeAniListTransport transport = FakeAniListTransport(
        response: AniListHttpResponse(
          failure: AniListFailure(type: AniListFailureType.networkError),
        ),
      );

      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: null,
        type: MediaType.anime,
        title: 'Cowboy Bebop',
        anilist: AniListClient(transport: transport),
        anilistId: 1,
      );

      expect(result.item, isNull);
      expect(result.reports.single.outcome, ProviderOutcome.networkFailure);
    });

    test(
      'no AniList client or id is reported, never silently ignored',
      () async {
        final EnrichmentResult noClient = await CatalogueEnricher.enrich(
          base: null,
          type: MediaType.anime,
          title: 'X',
          anilistId: 1,
        );
        expect(noClient.item, isNull);
        expect(noClient.reports.single.outcome, ProviderOutcome.notConfigured);

        final EnrichmentResult noId = await CatalogueEnricher.enrich(
          base: null,
          type: MediaType.anime,
          title: 'X',
          anilist: AniListClient(transport: FakeAniListTransport()),
        );
        expect(noId.item, isNull);
        expect(noId.reports.single.outcome, ProviderOutcome.notConfigured);
      },
    );
  });

  group('AniList description is plain text (device-found regression)', () {
    // AniList descriptions carry wiki HTML. Raw `<br><br>` was visible on the
    // Details screen on a real device.
    test('tags are stripped and line breaks become newlines', () {
      final AniListMedia media = AniListMedia.fromJson(<String, Object?>{
        'id': 1,
        'title': <String, Object?>{'english': 'Cowboy Bebop'},
        'description': 'First line.<br><br>Second <i>line</i>.',
      })!;

      expect(media.description, 'First line.\n\nSecond line.');
      expect(media.description, isNot(contains('<')));
    });

    test('common entities are decoded', () {
      final AniListMedia media = AniListMedia.fromJson(<String, Object?>{
        'id': 1,
        'title': <String, Object?>{'english': 'X'},
        'description': 'Spike &amp; Jet &quot;the stray&quot;',
      })!;

      expect(media.description, 'Spike & Jet "the stray"');
    });

    test('an empty or whitespace-only description becomes null', () {
      expect(
        AniListMedia.fromJson(<String, Object?>{
          'id': 1,
          'title': <String, Object?>{'english': 'X'},
          'description': '   <br>  ',
        })!.description,
        isNull,
      );
    });
  });

  group('AniList DTO â€” live schema shapes (device-found regression)', () {
    // These two shapes were wrong until a REAL device run: the live AniList
    // schema returns `startDate` as a fuzzy date OBJECT and `coverImage` as a
    // `MediaCoverImage` OBJECT. The old code read both as strings, so the year
    // and the cover silently came back null.
    test('startDate is a date object, and the year is read from it', () {
      final AniListMedia media = AniListMedia.fromJson(<String, Object?>{
        'id': 1,
        'title': <String, Object?>{'english': 'Cowboy Bebop'},
        'startDate': <String, Object?>{'year': 1998, 'month': 4, 'day': 3},
      })!;

      expect(media.startDateYear, 1998);
      expect(media.year, 1998);
    });

    test('coverImage is an object; extraLarge wins over large', () {
      final AniListMedia media = AniListMedia.fromJson(<String, Object?>{
        'id': 1,
        'title': <String, Object?>{'english': 'Cowboy Bebop'},
        'coverImage': <String, Object?>{
          'extraLarge': 'https://img.ani/extra.jpg',
          'large': 'https://img.ani/large.jpg',
        },
      })!;

      expect(media.coverImageUrl, 'https://img.ani/extra.jpg');
    });

    test('coverImage falls back to large, then tolerates a bare string', () {
      expect(
        AniListMedia.fromJson(<String, Object?>{
          'id': 1,
          'title': <String, Object?>{'english': 'X'},
          'coverImage': <String, Object?>{'large': 'https://img.ani/l.jpg'},
        })!.coverImageUrl,
        'https://img.ani/l.jpg',
      );
      // An older cached payload may still hold a plain string.
      expect(
        AniListMedia.fromJson(<String, Object?>{
          'id': 1,
          'title': <String, Object?>{'english': 'X'},
          'coverImage': 'https://img.ani/old.jpg',
        })!.coverImageUrl,
        'https://img.ani/old.jpg',
      );
    });

    test('a record with no cover and no start year still parses', () {
      final AniListMedia? media = AniListMedia.fromJson(<String, Object?>{
        'id': 1,
        'title': <String, Object?>{'english': 'X'},
      });

      expect(media, isNotNull);
      expect(media!.coverImageUrl, isNull);
      expect(media.startDateYear, isNull);
    });
  });

  group('isEpisodic / hasExtensionContribution (device-found regressions)', () {
    // A real device run showed a "Seasons" panel for Spirited Away, an anime
    // FILM (AniList format MOVIE). Type alone cannot answer this: anime is
    // usually episodic, but an anime film is a single title.
    MetadataItem animeItem({
      String? format,
      List<ReferenceMetadata> details = const <ReferenceMetadata>[],
    }) => MetadataItem(
      key: 'anilist:1',
      title: 'X',
      type: MediaType.anime,
      format: format,
      details: details,
    );

    test('a movie is never episodic, format or not', () {
      expect(
        const MetadataItem(
          key: 'k',
          title: 'M',
          type: MediaType.movie,
          details: <ReferenceMetadata>[],
        ).isEpisodic,
        isFalse,
      );
    });

    test('an anime film (format MOVIE) is a single title', () {
      expect(animeItem(format: 'MOVIE').isEpisodic, isFalse);
      expect(
        animeItem(format: 'movie').isEpisodic,
        isFalse,
      ); // case-insensitive
    });

    test('a TV/OVA/ONA/special anime is episodic', () {
      for (final String format in <String>['TV', 'OVA', 'ONA', 'SPECIAL']) {
        expect(animeItem(format: format).isEpisodic, isTrue, reason: format);
      }
    });

    test('an anime with no known format is NOT assumed episodic', () {
      // Type alone cannot answer this. Showing a Seasons panel for an unknown
      // format would be a guess, so the surface stays quiet instead.
      expect(animeItem().isEpisodic, isFalse);
    });

    test('series is episodic', () {
      expect(
        const MetadataItem(
          key: 'k',
          title: 'S',
          type: MediaType.series,
          details: <ReferenceMetadata>[],
        ).isEpisodic,
        isTrue,
      );
    });

    test(
      'a provider-only item is NOT counted as an extension contribution',
      () {
        // The AniList entry is provider metadata, so no extension exists to
        // have "not reported episode information yet".
        expect(animeItem(format: 'TV').hasExtensionContribution, isFalse);

        final MetadataItem withExtension = animeItem(
          format: 'TV',
          details: const <ReferenceMetadata>[
            ReferenceMetadata(
              extensionId: 'com.ext.one',
              referenceUrl: 'https://ext.one/a/1',
              title: 'X',
            ),
          ],
        );
        expect(withExtension.hasExtensionContribution, isTrue);
      },
    );

    test('the AniList normalizer marks its entry as provider metadata', () {
      // A TV series, so it IS episodic (the default MOVIE harness payload is
      // deliberately not used here).
      final AniListMedia media = AniListMedia.fromJson(
        anilistMediaPayload(format: 'TV'),
      )!;
      final MetadataItem item = AniListNormalizer.toMetadataItem(media);

      expect(item.details.single.isProviderMetadata, isTrue);
      expect(item.hasExtensionContribution, isFalse);
      expect(item.isEpisodic, isTrue);
    });

    test('a real AniList MOVIE normalizes to a non-episodic title', () {
      // The exact device case: Spirited Away, format MOVIE, must NOT get a
      // Seasons panel.
      final AniListMedia movie = AniListMedia.fromJson(anilistMediaPayload())!;
      final MetadataItem item = AniListNormalizer.toMetadataItem(movie);

      expect(item.type, MediaType.anime);
      expect(item.format, 'MOVIE');
      expect(item.isEpisodic, isFalse);
    });
  });

  group('AniList normalizer â€” C1 anime identity', () {
    test('discovery item uses the AniList canonical identity', () {
      final DiscoveryItem item = AniListNormalizer.toDiscoveryItem(
        parseMedia(mediaJson()),
      );

      expect(item.type, MediaType.anime);
      expect(item.key, 'anilist:16498');
      expect(item.externalIds!.anilistId, 16498);
      expect(item.title, 'Spirited Away');
      expect(item.year, 2001);
      expect(item.cover, 'https://img.ani/st.jpg');
    });

    test('metadata item carries canonical identity at identity version 2', () {
      final MetadataItem item = AniListNormalizer.toMetadataItem(
        parseMedia(mediaJson()),
      );

      expect(item.type, MediaType.anime);
      expect(item.key, 'anilist:16498');
      expect(item.canonicalId, 'anilist:16498');
      expect(item.identityVersion, 2);
      expect(item.format, 'MOVIE');
      expect(item.backdrop, 'https://img.ani/bn.jpg');
    });

    test('reference metadata keeps AniList identity, format and studios', () {
      final MetadataItem item = AniListNormalizer.toMetadataItem(
        parseMedia(mediaJson(format: 'TV', episodes: 26)),
      );
      final ReferenceMetadata reference = item.details.single;

      expect(item.format, 'TV');
      expect(item.episodeCount, 26);
      expect(reference.extensionId, 'anilist');
      expect(reference.externalIds!.anilistId, 16498);
      expect(reference.format, 'TV');
      expect(reference.episodeCount, 26);
      expect(reference.durationSeconds, 125 * 60);
      expect(reference.rating, closeTo(8.5, 0.0001));
      expect(reference.studios, <String>['Studio Ghibli']);
    });
  });

  group('C2 identity integration â€” no cross-type collisions', () {
    test('anime identity is independent of the movie/series title key', () {
      final MetadataItem anime = AniListNormalizer.toMetadataItem(
        parseMedia(mediaJson()),
      );
      final MetadataItem movie = MetadataItem(
        key: 'spirited away|movie|2001',
        title: 'Spirited Away',
        type: MediaType.movie,
        year: 2001,
        details: const <ReferenceMetadata>[],
      );

      expect(anime.key, isNot(movie.key));
      expect(anime.canonicalId, isNotNull);
      expect(movie.canonicalId, isNull);
      expect(movie.identityVersion, 1);
    });

    test('two anime with the same title but different AniList ids differ', () {
      final MetadataItem a = AniListNormalizer.toMetadataItem(
        parseMedia(mediaJson(id: 100)),
      );
      final MetadataItem b = AniListNormalizer.toMetadataItem(
        parseMedia(mediaJson(id: 200)),
      );

      expect(a.title, b.title);
      expect(a.key, isNot(b.key));
      expect(a.key, 'anilist:100');
      expect(b.key, 'anilist:200');
    });

    test('the same AniList id under different titles is one identity', () {
      final MetadataItem a = AniListNormalizer.toMetadataItem(
        parseMedia(mediaJson(id: 16498, english: 'Spirited Away')),
      );
      final MetadataItem b = AniListNormalizer.toMetadataItem(
        parseMedia(mediaJson(id: 16498, english: "Miyazaki's Spirited Away")),
      );

      expect(a.key, b.key);
      expect(a.canonicalId, b.canonicalId);
    });

    test('movie and series identity rules are unchanged by C2', () {
      final DiscoveryObservation movie = DiscoveryNormalizer.normalize(
        const SearchResult(
          title: 'Spirited Away',
          url: 'https://ext.one/m/1',
          type: MediaType.movie,
          year: 2001,
        ),
        'com.ext.one',
      )!;
      final DiscoveryObservation series = DiscoveryNormalizer.normalize(
        const SearchResult(
          title: 'Spirited Away',
          url: 'https://ext.one/s/1',
          type: MediaType.series,
          year: 2001,
        ),
        'com.ext.one',
      )!;

      // Legacy evidence keys stay exactly as C1 defined them.
      expect(movie.keyTitle, 'spirited away');
      expect(series.keyTitle, 'spirited away');

      final List<DiscoveryItem> items = DiscoveryDeduplicator.dedupe(
        <DiscoveryObservation>[movie, series],
      );
      expect(items, hasLength(2));
      expect(
        items
            .map(
              (DiscoveryItem i) => '${i.key.split('|')[0]}|${i.type.code}|2001',
            )
            .toList(),
        <String>['spirited away|movie|2001', 'spirited away|series|2001'],
      );
    });
  });
}
