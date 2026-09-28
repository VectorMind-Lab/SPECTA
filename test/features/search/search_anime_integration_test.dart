import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/anilist/anilist_client.dart';
import 'package:specta/core/anilist/anilist_providers.dart';
import 'package:specta/core/anilist/anilist_transport.dart';
import 'package:specta/core/discovery/discovery_coordinator.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/features/search/search_state.dart';

import '../../support/anilist_test_harness.dart';
import '../../support/discovery_test_harness.dart';

/// C4.2 ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â Search reaches ANIME through the metadata system while extension
/// discovery remains the authority for what is playable.
///
/// Deliberately a WIDGET test: the catalogue step needs the local database,
/// which needs platform services (see `database_capabilities.dart`). A headless
/// test would skip the step entirely and therefore prove nothing.
class _StubTransport implements AniListTransport {
  _StubTransport(this.stubBody);

  final String stubBody;

  @override
  Future<AniListHttpResponse> post({
    required Uri uri,
    required String body,
    required Map<String, String> headers,
    required Duration timeout,
  }) async => AniListHttpResponse(statusCode: 200, body: stubBody);
}

void main() {
  test('anime results appear alongside extension results', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'specta_search_anime',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final DiscoveryTestHarness harness = DiscoveryTestHarness(
      sandbox: ScriptedJsSandbox(),
    );
    await harness.installExtension(tempDir, 'com.test.found');
    (harness.sandbox as ScriptedJsSandbox).searchScripts = <Object>[
      jsonEncode(<Map<String, Object?>>[
        <String, Object?>{
          'title': 'A Movie',
          'url': 'https://f.test/1',
          'type': 'movie',
          'year': 2020,
        },
      ]),
    ];

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        discoveryServiceProvider.overrideWith(
          (Ref ref) => DiscoveryService(manager: harness.manager),
        ),
        catalogueDatabaseUsableProvider.overrideWith((Ref ref) => true),
        anilistClientProvider.overrideWith(
          (Ref ref) => AniListClient(
            transport: _StubTransport(anilistSearchBody(ids: <int>[16498])),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final SearchSessionNotifier notifier = container.read(
      searchSessionProvider.notifier,
    );
    await notifier.submit('spirited');

    final SearchState state = container.read(searchSessionProvider);
    // Extension discovery still decides the round's status.
    expect(state.status, SearchStatus.results);
    // The anime identity arrived from the catalogue, with its AniList key.
    expect(state.catalogueItems, hasLength(1));
    final DiscoveryItem anime = state.catalogueItems.single;
    expect(anime.type, MediaType.anime);
    expect(anime.key, 'anilist:16498');
    expect(anime.externalIds!.anilistId, 16498);
    // A catalogue result carries no extension reference: it is not a source.
    expect(anime.references, isEmpty);
    // Both lists render together, extension results first.
    expect(state.allItems, hasLength(state.items.length + 1));
  });

  test('an AniList outage does not break the extension round', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'specta_search_anime_fail',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final DiscoveryTestHarness harness = DiscoveryTestHarness(
      sandbox: ScriptedJsSandbox(),
    );
    await harness.installExtension(tempDir, 'com.test.found');
    (harness.sandbox as ScriptedJsSandbox).searchScripts = <Object>[
      jsonEncode(<Map<String, Object?>>[
        <String, Object?>{
          'title': 'A Movie',
          'url': 'https://f.test/1',
          'type': 'movie',
          'year': 2020,
        },
      ]),
    ];

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        discoveryServiceProvider.overrideWith(
          (Ref ref) => DiscoveryService(manager: harness.manager),
        ),
        catalogueDatabaseUsableProvider.overrideWith((Ref ref) => true),
        anilistClientProvider.overrideWith(
          (Ref ref) => AniListClient(
            transport: _StubTransport(
              jsonEncode(<String, Object?>{
                'errors': <Object?>[
                  <String, Object?>{'message': 'boom'},
                ],
              }),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final SearchSessionNotifier notifier = container.read(
      searchSessionProvider.notifier,
    );
    await notifier.submit('spirited');

    final SearchState state = container.read(searchSessionProvider);
    // Extensions answered, so the round is still a success with no anime.
    expect(state.status, SearchStatus.results);
    expect(state.catalogueItems, isEmpty);
  });
}
