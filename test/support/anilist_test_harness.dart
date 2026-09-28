import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/anilist/anilist_transport.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';

/// Scriptable AniList transport double used by the C2 tests. No network, no
/// credential, and every request is recorded for assertions.
class FakeAniListTransport implements AniListTransport {
  FakeAniListTransport({this.response});

  AniListHttpResponse? response;
  int callCount = 0;
  final List<String> bodies = <String>[];
  final List<Uri> uris = <Uri>[];

  @override
  Future<AniListHttpResponse> post({
    required Uri uri,
    required String body,
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    callCount++;
    uris.add(uri);
    bodies.add(body);
    return response ?? const AniListHttpResponse(statusCode: 200, body: '{}');
  }
}

/// A realistic AniList `Media` response for Spirited Away.
String anilistMediaBody({
  int id = 16498,
  String english = 'Spirited Away',
  String format = 'MOVIE',
  int? episodes,
  int averageScore = 85,
}) {
  return jsonEncode(<String, Object?>{
    'data': <String, Object?>{
      'Media': <String, Object?>{
        'id': id,
        'title': <String, Object?>{
          'romaji': 'Sen to Chihiro no Kamikakushi',
          'english': english,
          'native': 'åƒã¨åƒå°‹ã®ç¥žéš ã—',
        },
        'description': 'A girl works in a bathhouse for spirits.',
        'startDate': <String, Object?>{'year': 2001, 'month': 7, 'day': 20},
        'format': format,
        'status': 'FINISHED',
        'episodes': episodes,
        'duration': 125,
        'averageScore': averageScore,
        'genres': <String>['Fantasy', 'Adventure'],
        'coverImage': <String, Object?>{
          'extraLarge': 'https://img.ani/st.jpg',
          'large': 'https://img.ani/st-sm.jpg',
          'color': '#fff',
        },
        'bannerImage': 'https://img.ani/bn.jpg',
        'studios': <String, Object?>{
          'nodes': <Object?>[
            <String, Object?>{
              'name': 'Studio Ghibli',
              'isAnimationStudio': true,
            },
            <String, Object?>{
              'name': 'Some Publisher',
              'isAnimationStudio': false,
            },
          ],
        },
      },
    },
  });
}

/// An AniList `Page.media` search response.
String anilistSearchBody({List<int> ids = const <int>[16498, 21]}) {
  return jsonEncode(<String, Object?>{
    'data': <String, Object?>{
      'Page': <String, Object?>{
        'media': <Object?>[
          for (final int id in ids)
            <String, Object?>{
              'id': id,
              'title': <String, Object?>{'english': 'Title $id'},
              'format': 'TV',
              'episodes': 12,
            },
        ],
      },
    },
  });
}

/// The raw `Media` object used by [anilistMediaBody], so a test can hand the
/// exact provider shape to the DTO without re-encoding a wrapper.
Map<String, Object?> anilistMediaPayload({
  int id = 16498,
  String format = 'MOVIE',
  int? episodes,
}) {
  final Object? decoded = jsonDecode(
    anilistMediaBody(id: id, format: format, episodes: episodes),
  );
  final Map<String, Object?> root = decoded! as Map<String, Object?>;
  final Map<String, Object?> data = root['data']! as Map<String, Object?>;
  return data['Media']! as Map<String, Object?>;
}

/// Extracts the [AniListFailure] from an error result, asserting the type.
AniListFailure anilistFailureOf(SpectaResult<Object?> result) {
  final SpectaFailure failure = result.failureOrNull!;
  expect(failure, isA<AniListFailure>());
  return failure as AniListFailure;
}
