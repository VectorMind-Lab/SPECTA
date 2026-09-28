import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/metadata/catalogue_enricher.dart';
import 'package:specta/core/metadata/metadata_models.dart';
import 'package:specta/core/tmdb/tmdb_client.dart';
import 'package:specta/core/tmdb/tmdb_config.dart';
import 'package:specta/core/tmdb/tmdb_dto.dart';
import 'package:specta/core/tmdb/tmdb_normalizer.dart';
import 'package:specta/core/tmdb/tmdb_transport.dart';
import 'package:specta/core/tvmaze/tvmaze_client.dart';
import 'package:specta/core/tvmaze/tvmaze_transport.dart';

/// A syntactically valid, entirely fictional v3-shaped key. Not a credential.
const String _testKey = '0123456789abcdef0123456789abcdef';

/// A TMDB transport that answers per ENDPOINT.
///
/// The completion path makes TWO calls for one work — `/search/multi` to find
/// the entry, then `/movie/{id}` (or `/tv/{id}`) for the full record — so a
/// single-response fake cannot exercise it. Routing by endpoint is also what
/// lets a test assert the full-detail call actually happened, which is the
/// difference between a real record and a search-summary stub.
class _RoutingTmdbTransport implements TmdbTransport {
  _RoutingTmdbTransport({required this.responses});

  final Map<String, TmdbHttpResponse> responses;
  final List<String> calledEndpoints = <String>[];

  @override
  Future<TmdbHttpResponse> get({
    required Uri uri,
    required String endpoint,
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    calledEndpoints.add(endpoint);
    return responses[endpoint] ??
        const TmdbHttpResponse(statusCode: 404, body: '{}');
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

String _searchBody({
  int id = 603,
  String mediaType = 'movie',
  String title = 'The Matrix',
  int year = 1999,
}) => jsonEncode(<String, Object?>{
  'page': 1,
  'total_pages': 1,
  'total_results': 1,
  'results': <Object?>[
    <String, Object?>{
      'id': id,
      'media_type': mediaType,
      if (mediaType == 'movie') ...<String, Object?>{
        'title': title,
        'release_date': '$year-03-30',
      } else ...<String, Object?>{
        'name': title,
        'first_air_date': '$year-08-20',
      },
      'overview': 'Search-summary overview.',
      'poster_path': '/p.jpg',
      'vote_average': 8.2,
    },
  ],
});

String _movieDetailBody() => jsonEncode(<String, Object?>{
  'id': 603,
  'title': 'The Matrix',
  'original_title': 'The Matrix',
  'release_date': '1999-03-30',
  'overview': 'A hacker learns the truth.',
  'poster_path': '/p.jpg',
  'backdrop_path': '/b.jpg',
  'vote_average': 8.2,
  'runtime': 136,
  'genres': <Object?>[
    <String, Object?>{'id': 878, 'name': 'Science Fiction'},
    <String, Object?>{'id': 18, 'name': 'Drama'},
  ],
});

String _seriesDetailBody() => jsonEncode(<String, Object?>{
  'id': 1396,
  'name': 'Breaking Bad',
  'first_air_date': '2008-01-20',
  'overview': 'A chemistry teacher turns to crime.',
  'poster_path': '/bb.jpg',
  'vote_average': 8.9,
  'episode_run_time': <Object?>[47],
  'genres': <Object?>[
    <String, Object?>{'id': 18, 'name': 'Drama'},
  ],
  'seasons': <Object?>[
    <String, Object?>{'id': 3624, 'season_number': 1, 'name': 'Season 1'},
  ],
});

String _tvmazeSearchBody() => jsonEncode(<Object?>[
  <String, Object?>{
    'id': 169,
    'name': 'Breaking Bad',
    'summary': 'A chemistry teacher turns to crime.',
    'image': 'https://static.tvmaze.com/poster.jpg',
    'premiered': '2008-01-20',
    'genres': <String>['Drama', 'Crime'],
    'rating': <String, Object?>{'average': 9.3},
    'averageRuntime': 47,
  },
]);

ProviderReport _reportFor(EnrichmentResult result, String id) =>
    result.reports.firstWhere((ProviderReport r) => r.providerId == id);

TmdbClient _client(_RoutingTmdbTransport transport) => TmdbClient(
  config: const TmdbConfig(apiKey: _testKey),
  transport: transport,
);

/// A routing transport preloaded with a working movie search + detail pair.
_RoutingTmdbTransport _movieTransport() => _RoutingTmdbTransport(
  responses: <String, TmdbHttpResponse>{
    '/search/multi': TmdbHttpResponse(statusCode: 200, body: _searchBody()),
    '/movie/603': TmdbHttpResponse(statusCode: 200, body: _movieDetailBody()),
  },
);

/// A routing transport preloaded with a working series search + detail pair.
_RoutingTmdbTransport _seriesTransport() => _RoutingTmdbTransport(
  responses: <String, TmdbHttpResponse>{
    '/search/multi': TmdbHttpResponse(
      statusCode: 200,
      body: _searchBody(
        id: 1396,
        mediaType: 'tv',
        title: 'Breaking Bad',
        year: 2008,
      ),
    ),
    '/tv/1396': TmdbHttpResponse(statusCode: 200, body: _seriesDetailBody()),
  },
);

/// A routing transport that matches nothing (every endpoint 404s).
_RoutingTmdbTransport _emptyTransport() =>
    _RoutingTmdbTransport(responses: const <String, TmdbHttpResponse>{});

/// Regression suite for the blank-details defect found on a real device.
///
/// Home's "Popular" rail lists titles the CATALOGUE discovered (TMDB). Those
/// `DiscoveryItem`s carry NO extension reference, so the extension round has
/// nothing to ask and yields no metadata. Enrichment used to read "no base
/// metadata" as "no identity" and refuse to answer, which left the details
/// screen permanently on "Details could not be loaded — the extensions could not
/// be reached" for a title the app had just listed itself.
void main() {
  group('catalogue-only completion (no extension behind the title)', () {
    test('a movie with an existing identity IS completed by TMDB', () async {
      final _RoutingTmdbTransport transport = _movieTransport();

      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: null,
        type: MediaType.movie,
        title: 'The Matrix',
        year: 1999,
        identityKey: 'the matrix|movie|1999',
        tmdb: _client(transport),
      );

      expect(result.item, isNotNull);
      // The identity is the CALLER'S, verbatim — never recomputed from the
      // provider payload, which is what stops a second identity being minted.
      expect(result.item!.key, 'the matrix|movie|1999');
      expect(result.item!.type, MediaType.movie);
      expect(result.item!.year, 1999);
      // The FULL payload arrived, not the search summary.
      expect(result.item!.description, 'A hacker learns the truth.');
      expect(result.item!.genres, contains('Science Fiction'));
      expect(result.item!.rating, 8.2);
      expect(transport.calledEndpoints, contains('/movie/603'));
      expect(_reportFor(result, 'tmdb').outcome, ProviderOutcome.matched);
    });

    test('the completed record is provider metadata, never a source', () async {
      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: null,
        type: MediaType.movie,
        title: 'The Matrix',
        year: 1999,
        identityKey: 'the matrix|movie|1999',
        tmdb: _client(_movieTransport()),
      );

      // Every entry is provider metadata, so no surface can mistake this record
      // for a playable source — the invariant that keeps a catalogue-only title
      // from ever promising a stream it cannot deliver.
      expect(result.item!.details, isNotEmpty);
      for (final ReferenceMetadata d in result.item!.details) {
        expect(d.isProviderMetadata, isTrue);
      }
      expect(result.item!.hasExtensionContribution, isFalse);
    });

    test('series get their season structure from the full payload', () async {
      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: null,
        type: MediaType.series,
        title: 'Breaking Bad',
        year: 2008,
        identityKey: 'breaking bad|series|2008',
        tmdb: _client(_seriesTransport()),
      );

      expect(result.item!.key, 'breaking bad|series|2008');
      expect(result.item!.seasons, hasLength(1));
      expect(result.item!.seasons.single.seasonNumber, 1);
    });

    test('the year and cover the user tapped are preserved', () async {
      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: null,
        type: MediaType.movie,
        title: 'The Matrix',
        year: 1999,
        identityKey: 'the matrix|movie|1999',
        cover: 'https://image.tmdb.org/t/p/w500/rail-poster.jpg',
        tmdb: _client(
          _RoutingTmdbTransport(
            responses: <String, TmdbHttpResponse>{
              '/search/multi': TmdbHttpResponse(
                statusCode: 200,
                body: _searchBody(),
              ),
              // A detail payload with NO poster: the rail's artwork must not be
              // lost just because the fuller record happens to omit one.
              '/movie/603': const TmdbHttpResponse(
                statusCode: 200,
                body: '{"id":603,"title":"The Matrix","overview":"x"}',
              ),
            },
          ),
        ),
      );

      expect(result.item!.year, 1999);
      expect(
        result.item!.cover,
        'https://image.tmdb.org/t/p/w500/rail-poster.jpg',
      );
    });

    test('a null discovery year is not backfilled by the provider', () async {
      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: null,
        type: MediaType.movie,
        title: 'The Matrix',
        identityKey: 'the matrix|movie|none',
        tmdb: _client(_movieTransport()),
      );

      // The identity says `none`, so the year must stay null — otherwise the
      // record contradicts the very key it is stored under.
      expect(result.item!.key, 'the matrix|movie|none');
      expect(result.item!.year, isNull);
    });

    test('TVMaze completes a series when TMDB has no match', () async {
      final _FakeTvmazeTransport tvmaze = _FakeTvmazeTransport(
        TvmazeHttpResponse(statusCode: 200, body: _tvmazeSearchBody()),
      );

      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: null,
        type: MediaType.series,
        title: 'Breaking Bad',
        year: 2008,
        identityKey: 'breaking bad|series|2008',
        tmdb: _client(_emptyTransport()),
        tvmaze: TvmazeClient(transport: tvmaze),
      );

      expect(result.item, isNotNull);
      expect(result.item!.key, 'breaking bad|series|2008');
      expect(result.item!.description, contains('chemistry teacher'));
      expect(tvmaze.callCount, 1);
      expect(_reportFor(result, 'tmdb').outcome, ProviderOutcome.noMatch);
      expect(_reportFor(result, 'tvmaze').outcome, ProviderOutcome.matched);
    });

    test('TVMaze is never consulted for a movie', () async {
      final _FakeTvmazeTransport tvmaze = _FakeTvmazeTransport(
        const TvmazeHttpResponse(statusCode: 200, body: '[]'),
      );

      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: null,
        type: MediaType.movie,
        title: 'The Matrix',
        year: 1999,
        identityKey: 'the matrix|movie|1999',
        tmdb: _client(_emptyTransport()),
        tvmaze: TvmazeClient(transport: tvmaze),
      );

      // TVMaze publishes no movie catalogue, so asking it would be theatre.
      expect(tvmaze.callCount, 0);
      expect(
        _reportFor(result, 'tvmaze').outcome,
        ProviderOutcome.notApplicable,
      );
    });

    test(
      'an unconfigured build reports why rather than failing silently',
      () async {
        final EnrichmentResult result = await CatalogueEnricher.enrich(
          base: null,
          type: MediaType.movie,
          title: 'The Matrix',
          identityKey: 'the matrix|movie|1999',
          tmdb: TmdbClient(config: const TmdbConfig()),
        );

        expect(result.item, isNull);
        expect(
          _reportFor(result, 'tmdb').outcome,
          ProviderOutcome.notConfigured,
        );
      },
    );

    test('a failing detail call is reported, not half-presented', () async {
      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: null,
        type: MediaType.movie,
        title: 'The Matrix',
        year: 1999,
        identityKey: 'the matrix|movie|1999',
        tmdb: _client(
          _RoutingTmdbTransport(
            responses: <String, TmdbHttpResponse>{
              '/search/multi': TmdbHttpResponse(
                statusCode: 200,
                body: _searchBody(),
              ),
              '/movie/603': const TmdbHttpResponse(
                statusCode: 500,
                body: 'boom',
              ),
            },
          ),
        ),
      );

      // Matched, but the record could not be fetched: no item, and the truth is
      // in the reports rather than in a half-built MetadataItem.
      expect(result.item, isNull);
      expect(
        result.reports.any(
          (ProviderReport r) =>
              r.providerId == 'tmdb' &&
              r.outcome == ProviderOutcome.networkFailure,
        ),
        isTrue,
      );
    });

    test('WITHOUT an identity key nothing is created', () async {
      final _RoutingTmdbTransport transport = _emptyTransport();

      final EnrichmentResult result = await CatalogueEnricher.enrich(
        base: null,
        type: MediaType.movie,
        title: 'The Matrix',
        year: 1999,
        tmdb: _client(transport),
      );

      // The original safety rule is intact: with no identity to complete, the
      // enricher still refuses rather than minting one.
      expect(result.item, isNull);
      expect(result.reports, isEmpty);
      expect(transport.calledEndpoints, isEmpty);
    });
  });

  group('TmdbNormalizer identity overrides', () {
    TmdbMediaDetails details() => TmdbMediaDetails.fromJson(
      jsonDecode(_movieDetailBody()) as Map<String, Object?>,
      type: MediaType.movie,
    )!;

    test('no override derives the key from the payload', () {
      final MetadataItem item = TmdbNormalizer.toMetadataItem(
        details(),
        imageBaseUrl: TmdbConfig.defaultImageBaseUrl,
      );

      expect(item.key, 'the matrix|movie|1999');
      expect(item.year, 1999);
      expect(item.cover, isNotNull);
    });

    test('an override is honoured verbatim', () {
      final MetadataItem item = TmdbNormalizer.toMetadataItem(
        details(),
        imageBaseUrl: TmdbConfig.defaultImageBaseUrl,
        identity: const CatalogueIdentity(
          key: 'custom key|movie|none',
          year: null,
          cover: 'https://rail/poster.jpg',
        ),
      );

      expect(item.key, 'custom key|movie|none');
      // A null year in the identity STAYS null: `?? details.year` would have
      // silently produced 1999 here, so the record would contradict its own key.
      expect(item.year, isNull);
      expect(item.cover, 'https://rail/poster.jpg');
      // A key override changes identity only — never the type or the payload.
      expect(item.type, MediaType.movie);
      expect(item.description, 'A hacker learns the truth.');
    });
  });
}
