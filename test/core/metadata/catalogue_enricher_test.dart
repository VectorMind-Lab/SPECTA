import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/metadata/catalogue_enricher.dart';
import 'package:specta/core/metadata/metadata_models.dart';
import 'package:specta/core/tmdb/tmdb_client.dart';
import 'package:specta/core/tmdb/tmdb_config.dart';
import 'package:specta/core/tmdb/tmdb_transport.dart';
import 'package:specta/core/tvmaze/tvmaze_client.dart';
import 'package:specta/core/tvmaze/tvmaze_transport.dart';

/// A syntactically valid, entirely fictional v3-shaped key. Not a credential.
const String _testKey = '0123456789abcdef0123456789abcdef';

class _FakeTmdbTransport implements TmdbTransport {
  _FakeTmdbTransport(this.response);
  TmdbHttpResponse response;
  int callCount = 0;
  final List<Uri> uris = <Uri>[];

  @override
  Future<TmdbHttpResponse> get({
    required Uri uri,
    required String endpoint,
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    callCount++;
    uris.add(uri);
    return response;
  }
}

class _FakeTvmazeTransport implements TvmazeTransport {
  _FakeTvmazeTransport(this.response);
  TvmazeHttpResponse response;
  int callCount = 0;

  @override
  Future<TvmazeHttpResponse> get({
    required Uri uri,
    required String endpoint,
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    callCount++;
    return response;
  }
}

String _tmdbSearchBody({
  int id = 603,
  String type = 'movie',
  String title = 'The Matrix',
  int year = 1999,
}) {
  return jsonEncode(<String, Object?>{
    'page': 1,
    'total_pages': 1,
    'total_results': 1,
    'results': <Object?>[
      <String, Object?>{
        'id': id,
        'media_type': type,
        if (type == 'movie') ...<String, Object?>{
          'title': title,
          'original_title': title,
          'release_date': '$year-03-30',
        } else ...<String, Object?>{
          'name': title,
          'original_name': title,
          'first_air_date': '$year-08-20',
        },
        'overview': 'A hacker learns the truth.',
        'poster_path': '/p.jpg',
        'backdrop_path': '/b.jpg',
        'vote_average': 8.2,
        'genre_ids': <int>[878, 18],
      },
    ],
  });
}

String _tvmazeSearchBody({int id = 1, String name = 'Breaking Bad'}) {
  return jsonEncode(<Object?>[
    <String, Object?>{
      'id': id,
      'name': name,
      'summary': 'A chemistry teacher turns to crime.',
      'image': 'https://static.tvmaze.com/x.jpg',
      'premiered': '2008-01-20',
      'genres': <String>['Drama', 'Crime'],
      'rating': <String, Object?>{'average': 9.3},
      'averageRuntime': 47,
    },
  ]);
}

MetadataItem _baseMovie() => const MetadataItem(
  key: 'the matrix|movie|1999',
  title: 'The Matrix',
  type: MediaType.movie,
  year: 1999,
  details: <ReferenceMetadata>[
    ReferenceMetadata(
      extensionId: 'com.ext.one',
      referenceUrl: 'https://ext.one/m/1',
      title: 'The Matrix',
      description: 'Extension description wins.',
    ),
  ],
);

MetadataItem _baseSeries() => const MetadataItem(
  key: 'breaking bad|series|2008',
  title: 'Breaking Bad',
  type: MediaType.series,
  year: 2008,
  details: <ReferenceMetadata>[
    ReferenceMetadata(
      extensionId: 'com.ext.one',
      referenceUrl: 'https://ext.one/s/1',
      title: 'Breaking Bad',
    ),
  ],
);

ProviderReport _reportFor(EnrichmentResult result, String id) =>
    result.reports.firstWhere((ProviderReport r) => r.providerId == id);

void main() {
  group('C3 TMDB credential states', () {
    test('unconfigured reports notConfigured, not a network error', () async {
      final _FakeTmdbTransport transport = _FakeTmdbTransport(
        const TmdbHttpResponse(statusCode: 200, body: '{}'),
      );

      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: _baseMovie(),
        type: MediaType.movie,
        title: 'The Matrix',
        year: 1999,
        tmdb: TmdbClient(config: const TmdbConfig(), transport: transport),
      );

      final ProviderReport tmdb = _reportFor(result, 'tmdb');
      expect(tmdb.outcome, ProviderOutcome.notConfigured);
      expect(
        (tmdb.failure! as TmdbFailure).type,
        TmdbFailureType.notConfigured,
      );
      expect(transport.callCount, 0);
      expect(result.item!.key, 'the matrix|movie|1999');
    });

    test('a blank credential counts as absent', () async {
      final _FakeTmdbTransport transport = _FakeTmdbTransport(
        const TmdbHttpResponse(statusCode: 200, body: '{}'),
      );

      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: _baseMovie(),
        type: MediaType.movie,
        title: 'The Matrix',
        tmdb: TmdbClient(
          config: const TmdbConfig(apiKey: '   '),
          transport: transport,
        ),
      );

      expect(_reportFor(result, 'tmdb').outcome, ProviderOutcome.notConfigured);
      expect(transport.callCount, 0);
    });

    test('a rejected key is notConfigured, never a crash', () async {
      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: _baseMovie(),
        type: MediaType.movie,
        title: 'The Matrix',
        tmdb: TmdbClient(
          config: const TmdbConfig(apiKey: _testKey),
          transport: _FakeTmdbTransport(
            const TmdbHttpResponse(statusCode: 401, body: '{}'),
          ),
        ),
      );

      expect(_reportFor(result, 'tmdb').outcome, ProviderOutcome.notConfigured);
      expect(result.item, isNotNull);
    });

    test(
      'the key never leaks into a failure, endpoint or report text',
      () async {
        final _FakeTmdbTransport transport = _FakeTmdbTransport(
          const TmdbHttpResponse(statusCode: 500, body: 'boom'),
        );

        final EnrichmentResult result = await CatalogueEnricher.enrich(
          base: _baseMovie(),
          type: MediaType.movie,
          title: 'The Matrix',
          tmdb: TmdbClient(
            config: const TmdbConfig(apiKey: _testKey),
            transport: transport,
          ),
        );

        final String dump = result.reports
            .map((ProviderReport r) => '${r.outcome} ${r.failure}')
            .join(' ');
        expect(dump, isNot(contains(_testKey)));
        // It does travel to the provider as a query parameter, by design.
        expect(transport.uris.single.queryParameters['api_key'], _testKey);
        // The recorded failure keeps only the endpoint path.
        final TmdbFailure failure =
            result.reports.first.failure! as TmdbFailure;
        expect(failure.endpoint, startsWith('/'));
        expect(failure.endpoint, isNot(contains(_testKey)));
      },
    );
  });

  group('C3 TMDB movie and series enrichment', () {
    TmdbClient fakeClient(TmdbHttpResponse response) => TmdbClient(
      config: const TmdbConfig(apiKey: _testKey),
      transport: _FakeTmdbTransport(response),
    );

    test('a movie is enriched and extension data still wins', () async {
      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: _baseMovie(),
        type: MediaType.movie,
        title: 'The Matrix',
        year: 1999,
        tmdb: fakeClient(
          TmdbHttpResponse(statusCode: 200, body: _tmdbSearchBody()),
        ),
      );

      expect(result.reports.single.outcome, ProviderOutcome.matched);
      final MetadataItem item = result.item!;
      // Identity is untouched by enrichment.
      expect(item.key, 'the matrix|movie|1999');
      expect(item.type, MediaType.movie);
      expect(item.identityVersion, 1);
      expect(item.canonicalId, isNull);
      // The extension description still wins; TMDB is an extra contribution.
      expect(item.description, 'Extension description wins.');
      expect(item.details, hasLength(2));
      expect(item.details.last.extensionId, 'tmdb');
      expect(item.details.last.referenceUrl, 'movie:603');
      expect(item.rating, closeTo(8.2, 0.0001));
    });

    test('a series is enriched with a strictly matching type', () async {
      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: _baseSeries(),
        type: MediaType.series,
        title: 'Breaking Bad',
        year: 2008,
        tmdb: fakeClient(
          TmdbHttpResponse(
            statusCode: 200,
            body: _tmdbSearchBody(
              id: 1396,
              type: 'tv',
              title: 'Breaking Bad',
              year: 2008,
            ),
          ),
        ),
      );

      expect(result.reports.first.outcome, ProviderOutcome.matched);
      expect(result.item!.key, 'breaking bad|series|2008');
      expect(result.item!.type, MediaType.series);
    });

    test('a movie request never accepts a series answer', () async {
      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: _baseMovie(),
        type: MediaType.movie,
        title: 'The Matrix',
        tmdb: fakeClient(
          TmdbHttpResponse(
            statusCode: 200,
            body: _tmdbSearchBody(type: 'tv', title: 'The Matrix'),
          ),
        ),
      );

      expect(result.reports.first.outcome, ProviderOutcome.noMatch);
      expect(result.item!.details, hasLength(1));
    });

    test('a distant year is no match, not a bad merge', () async {
      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: _baseMovie(),
        type: MediaType.movie,
        title: 'The Matrix',
        year: 1999,
        tmdb: fakeClient(
          TmdbHttpResponse(statusCode: 200, body: _tmdbSearchBody(year: 1980)),
        ),
      );
      expect(result.reports.first.outcome, ProviderOutcome.noMatch);
    });

    test('an empty result set is a genuine no match', () async {
      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: _baseMovie(),
        type: MediaType.movie,
        title: 'Nothing At All',
        tmdb: fakeClient(
          const TmdbHttpResponse(
            statusCode: 200,
            body: '{"page":1,"total_pages":1,"total_results":0,"results":[]}',
          ),
        ),
      );
      expect(result.reports.first.outcome, ProviderOutcome.noMatch);
    });

    test('malformed provider data is reported as malformed', () async {
      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: _baseMovie(),
        type: MediaType.movie,
        title: 'The Matrix',
        tmdb: fakeClient(
          const TmdbHttpResponse(statusCode: 200, body: 'not json'),
        ),
      );
      expect(result.reports.first.outcome, ProviderOutcome.malformed);
    });
  });

  group('C3 TVMaze fallback rules', () {
    TvmazeClient fakeClient(TvmazeHttpResponse response) =>
        TvmazeClient(transport: _FakeTvmazeTransport(response));

    test('a movie never consults TVMaze (no movie catalogue exists)', () async {
      final _FakeTvmazeTransport tvmaze = _FakeTvmazeTransport(
        TvmazeHttpResponse(statusCode: 200, body: _tvmazeSearchBody()),
      );

      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: _baseMovie(),
        type: MediaType.movie,
        title: 'The Matrix',
        tmdb: null,
        tvmaze: TvmazeClient(transport: tvmaze),
      );

      expect(tvmaze.callCount, 0);
      expect(
        _reportFor(result, 'tvmaze').outcome,
        ProviderOutcome.notApplicable,
      );
      expect(result.item!.details, hasLength(1));
    });

    test('a series falls back to TVMaze when TMDB is not configured', () async {
      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: _baseSeries(),
        type: MediaType.series,
        title: 'Breaking Bad',
        tmdb: null,
        tvmaze: fakeClient(
          TvmazeHttpResponse(statusCode: 200, body: _tvmazeSearchBody()),
        ),
      );

      expect(_reportFor(result, 'tmdb').outcome, ProviderOutcome.notConfigured);
      expect(_reportFor(result, 'tvmaze').outcome, ProviderOutcome.matched);
      expect(result.fallbacksUsed, <String>['tvmaze']);

      final MetadataItem item = result.item!;
      // A fallback never mints a second identity.
      expect(item.key, 'breaking bad|series|2008');
      expect(item.type, MediaType.series);
      expect(item.description, 'A chemistry teacher turns to crime.');
      expect(item.genres, containsAll(<String>['Drama', 'Crime']));
      expect(item.details.last.extensionId, 'tvmaze');
      expect(item.details.last.referenceUrl, 'show:1');
    });

    test('TVMaze is not consulted when TMDB already answered', () async {
      final _FakeTvmazeTransport tvmaze = _FakeTvmazeTransport(
        TvmazeHttpResponse(statusCode: 200, body: _tvmazeSearchBody()),
      );

      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: _baseSeries(),
        type: MediaType.series,
        title: 'Breaking Bad',
        year: 2008,
        tmdb: TmdbClient(
          config: const TmdbConfig(apiKey: _testKey),
          transport: _FakeTmdbTransport(
            TmdbHttpResponse(
              statusCode: 200,
              body: _tmdbSearchBody(
                id: 1396,
                type: 'tv',
                title: 'Breaking Bad',
                year: 2008,
              ),
            ),
          ),
        ),
        tvmaze: TvmazeClient(transport: tvmaze),
      );

      expect(result.reports, hasLength(1));
      expect(result.fallbacksUsed, isEmpty);
      expect(tvmaze.callCount, 0);
    });

    test('a TVMaze network failure is isolated and recorded as data', () async {
      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: _baseSeries(),
        type: MediaType.series,
        title: 'Breaking Bad',
        tmdb: null,
        tvmaze: fakeClient(
          TvmazeHttpResponse(
            failure: TvmazeFailure(
              type: TvmazeFailureType.networkError,
              detail: 'offline',
            ),
          ),
        ),
      );

      final ProviderReport tvmaze = _reportFor(result, 'tvmaze');
      expect(tvmaze.outcome, ProviderOutcome.networkFailure);
      expect(tvmaze.didContribute, isFalse);
      // Extension metadata survives a total provider outage.
      expect(result.item, isNotNull);
      expect(result.item!.details, hasLength(1));
    });

    test('rate limiting and empty results stay distinguishable', () async {
      final EnrichmentResult limited = await CatalogueEnricher.enrich(
        base: _baseSeries(),
        type: MediaType.series,
        title: 'Breaking Bad',
        tmdb: null,
        tvmaze: fakeClient(const TvmazeHttpResponse(statusCode: 429, body: '')),
      );
      expect(
        _reportFor(limited, 'tvmaze').outcome,
        ProviderOutcome.networkFailure,
      );

      final EnrichmentResult empty = await CatalogueEnricher.enrich(
        base: _baseSeries(),
        type: MediaType.series,
        title: 'Nothing',
        tmdb: null,
        tvmaze: fakeClient(
          const TvmazeHttpResponse(statusCode: 200, body: '[]'),
        ),
      );
      expect(_reportFor(empty, 'tvmaze').outcome, ProviderOutcome.noMatch);
    });
  });

  group('C3 identity safety and anime regression', () {
    test('anime is never enriched by TMDB or TVMaze', () async {
      final _FakeTmdbTransport tmdb = _FakeTmdbTransport(
        TmdbHttpResponse(statusCode: 200, body: _tmdbSearchBody()),
      );
      final _FakeTvmazeTransport tvmaze = _FakeTvmazeTransport(
        TvmazeHttpResponse(statusCode: 200, body: _tvmazeSearchBody()),
      );

      const MetadataItem anime = MetadataItem(
        key: 'anilist:16498',
        title: 'Spirited Away',
        type: MediaType.anime,
        year: 2001,
        canonicalId: 'anilist:16498',
        identityVersion: 2,
        details: <ReferenceMetadata>[
          ReferenceMetadata(
            extensionId: 'anilist',
            referenceUrl: 'anilist:16498',
            title: 'Spirited Away',
          ),
        ],
      );

      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: anime,
        type: MediaType.anime,
        title: 'Spirited Away',
        year: 2001,
        tmdb: TmdbClient(
          config: const TmdbConfig(apiKey: _testKey),
          transport: tmdb,
        ),
        tvmaze: TvmazeClient(transport: tvmaze),
      );

      // Identity safety is unchanged: TMDB/TVMaze are never consulted for anime.
      expect(tmdb.callCount, 0);
      expect(tvmaze.callCount, 0);
      // The identity is never altered.
      expect(result.item!.key, 'anilist:16498');
      expect(result.item!.canonicalId, 'anilist:16498');
      expect(result.item!.identityVersion, 2);
      expect(result.item!.details, hasLength(1));
      // No AniList client/id was supplied, so that is now REPORTED rather than
      // silently dropped (found on a real device, C4 gate run).
      expect(result.reports.single.providerId, 'anilist');
      expect(result.reports.single.outcome, ProviderOutcome.notConfigured);
    });

    test('an item with no identity yet gets no provider metadata', () async {
      final _FakeTmdbTransport tmdb = _FakeTmdbTransport(
        TmdbHttpResponse(statusCode: 200, body: _tmdbSearchBody()),
      );

      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: null,
        type: MediaType.movie,
        title: 'The Matrix',
        tmdb: TmdbClient(
          config: const TmdbConfig(apiKey: _testKey),
          transport: tmdb,
        ),
      );

      expect(tmdb.callCount, 0);
      expect(result.item, isNull);
      expect(result.reports, isEmpty);
    });

    test('enrichment is additive and never overwrites extension artwork', () {
      final MetadataItem base = MetadataItem(
        key: 'k|movie|2000',
        title: 'T',
        type: MediaType.movie,
        cover: 'https://ext/cover.jpg',
        details: const <ReferenceMetadata>[
          ReferenceMetadata(
            extensionId: 'ext',
            referenceUrl: 'https://ext/1',
            title: 'T',
            cover: 'https://ext/cover.jpg',
          ),
        ],
      );

      final MetadataItem enriched = base.withEnrichment(
        const ReferenceMetadata(
          extensionId: 'tmdb',
          referenceUrl: 'movie:1',
          title: 'Different title',
          cover: 'https://tmdb/cover.jpg',
          backdrop: 'https://tmdb/backdrop.jpg',
        ),
      );

      expect(enriched.title, 'T');
      expect(enriched.cover, 'https://ext/cover.jpg');
      expect(enriched.backdrop, 'https://tmdb/backdrop.jpg');
      expect(enriched.key, base.key);
      expect(enriched.details, hasLength(2));
    });
  });
}
