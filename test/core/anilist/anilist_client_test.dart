import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/anilist/anilist_client.dart';
import 'package:specta/core/anilist/anilist_dto.dart';
import 'package:specta/core/anilist/anilist_transport.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';

import '../../support/anilist_test_harness.dart';

void main() {
  group('AniListClient — request shape', () {
    test(
      'sends a credential-free GraphQL POST to the AniList endpoint',
      () async {
        final FakeAniListTransport transport = FakeAniListTransport(
          response: AniListHttpResponse(
            statusCode: 200,
            body: anilistMediaBody(),
          ),
        );

        final SpectaResult<AniListMedia> result = await AniListClient(
          transport: transport,
        ).getMedia(16498);

        expect(result.isOk, isTrue);
        expect(result.valueOrNull!.id, 16498);
        expect(transport.callCount, 1);
        expect(transport.uris.single.toString(), AniListClient.apiEndpoint);
        final Map<String, Object?> sent =
            jsonDecode(transport.bodies.single) as Map<String, Object?>;
        expect(sent['variables'], <String, Object?>{'id': 16498});
        expect(sent['query'], contains('type: ANIME'));
        // A public API receives no credential of any kind.
        expect(transport.bodies.single, isNot(contains('api_key')));
        expect(transport.bodies.single, isNot(contains('Authorization')));
      },
    );

    test('search sends the trimmed term and parses each row', () async {
      final FakeAniListTransport transport = FakeAniListTransport(
        response: AniListHttpResponse(
          statusCode: 200,
          body: anilistSearchBody(),
        ),
      );

      final SpectaResult<List<AniListMedia>> result = await AniListClient(
        transport: transport,
      ).searchMedia('  ghibli  ');

      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.map((AniListMedia m) => m.id), <int>[
        16498,
        21,
      ]);
      final Map<String, Object?> sent =
          jsonDecode(transport.bodies.single) as Map<String, Object?>;
      expect(sent['variables'], <String, Object?>{
        'search': 'ghibli',
        'page': 1,
      });
    });

    test('an empty search short-circuits without a network call', () async {
      final FakeAniListTransport transport = FakeAniListTransport();
      final SpectaResult<List<AniListMedia>> result = await AniListClient(
        transport: transport,
      ).searchMedia('   ');

      expect(result.isOk, isTrue);
      expect(result.valueOrNull, isEmpty);
      expect(transport.callCount, 0);
    });

    test('a non-positive AniList id fails without a network call', () async {
      final FakeAniListTransport transport = FakeAniListTransport();
      for (final int id in <int>[0, -1]) {
        final SpectaResult<AniListMedia> result = await AniListClient(
          transport: transport,
        ).getMedia(id);
        expect(result.isErr, isTrue);
      }
      expect(transport.callCount, 0);
    });
  });

  group('AniListClient — structured error mapping', () {
    Future<AniListFailure> run(AniListHttpResponse response) async {
      return anilistFailureOf(
        await AniListClient(transport: FakeAniListTransport(response: response))
            .getMedia(1),
      );
    }

    test('404 maps to notFound', () async {
      final AniListFailure failure = await run(
        const AniListHttpResponse(statusCode: 404, body: ''),
      );
      expect(failure.type, AniListFailureType.notFound);
      expect(failure.statusCode, 404);
    });

    test('429 maps to rateLimited and is retryable', () async {
      final AniListFailure failure = await run(
        const AniListHttpResponse(statusCode: 429, body: ''),
      );
      expect(failure.type, AniListFailureType.rateLimited);
      expect(failure.isRetryable, isTrue);
    });

    test('5xx maps to serverError and is retryable', () async {
      for (final int status in <int>[500, 502, 503]) {
        final AniListFailure failure = await run(
          AniListHttpResponse(statusCode: status, body: ''),
        );
        expect(failure.type, AniListFailureType.serverError);
        expect(failure.isRetryable, isTrue);
      }
    });

    test('other non-2xx maps to httpError and is not retryable', () async {
      final AniListFailure failure = await run(
        const AniListHttpResponse(statusCode: 400, body: ''),
      );
      expect(failure.type, AniListFailureType.httpError);
      expect(failure.isRetryable, isFalse);
    });

    test('a transport failure stays a structured failure', () async {
      final AniListFailure failure = await run(
        AniListHttpResponse(
          failure: AniListFailure(
            type: AniListFailureType.networkError,
            detail: 'offline',
          ),
        ),
      );
      expect(failure.type, AniListFailureType.networkError);
      expect(failure.isRetryable, isTrue);
    });

    test('malformed JSON is a parseError, not an exception', () async {
      final AniListFailure failure = await run(
        const AniListHttpResponse(statusCode: 200, body: 'not json'),
      );
      expect(failure.type, AniListFailureType.parseError);
      expect(failure.isRetryable, isFalse);
    });

    test('a GraphQL errors array is a parse failure', () async {
      final AniListFailure failure = await run(
        AniListHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'errors': <Object?>[
              <String, Object?>{'message': 'Not Found'},
            ],
          }),
        ),
      );
      expect(failure.type, AniListFailureType.parseError);
    });

    test(
      'a missing media payload is rejected, not partially accepted',
      () async {
        final AniListFailure failure = await run(
          AniListHttpResponse(
            statusCode: 200,
            body: jsonEncode(<String, Object?>{'data': <String, Object?>{}}),
          ),
        );
        expect(failure.type, AniListFailureType.parseError);
      },
    );
  });
}
