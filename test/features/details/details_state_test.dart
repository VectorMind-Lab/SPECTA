import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart' as t;

import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/identity/title_key.dart';
import 'package:specta/core/metadata/metadata_manager.dart';
import 'package:specta/core/tmdb/tmdb_client.dart';
import 'package:specta/core/tmdb/tmdb_config.dart';
import 'package:specta/core/tmdb/tmdb_transport.dart';
import 'package:specta/features/details/details_state.dart';

import '../../support/discovery_test_harness.dart';

/// A syntactically valid, entirely fictional v3-shaped key. Not a credential.
const String _testTmdbKey = '0123456789abcdef0123456789abcdef';

/// A `DiscoveryItem` shaped exactly like the ones TMDB's "Popular" rail builds:
/// a real identity key, a title, a year, artwork — and NO extension reference.
DiscoveryItem _catalogueOnlyItem(String title, int year) => DiscoveryItem(
  key: TitleKey.identityKey(
    title: title,
    typeCode: MediaType.movie.code,
    year: year,
  ),
  title: title,
  type: MediaType.movie,
  year: year,
  cover: 'https://image.tmdb.org/t/p/w500/rail.jpg',
  references: const <DiscoveryReference>[],
);

/// Answers per endpoint, so a test can distinguish "found the entry" from
/// "fetched the full record behind it".
class _RoutingTmdbTransport implements TmdbTransport {
  _RoutingTmdbTransport({this.searchStatus = 200});

  final int searchStatus;

  @override
  Future<TmdbHttpResponse> get({
    required Uri uri,
    required String endpoint,
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    if (endpoint == '/search/multi') {
      if (searchStatus != 200) {
        return TmdbHttpResponse(statusCode: searchStatus, body: 'boom');
      }
      return TmdbHttpResponse(
        statusCode: 200,
        body: jsonEncode(<String, Object?>{
          'page': 1,
          'total_pages': 1,
          'total_results': 1,
          'results': <Object?>[
            <String, Object?>{
              'id': 603,
              'media_type': 'movie',
              'title': 'The Matrix',
              'release_date': '1999-03-30',
              'overview': 'Search-summary overview.',
              'poster_path': '/p.jpg',
              'vote_average': 8.2,
            },
          ],
        }),
      );
    }
    if (endpoint == '/movie/603') {
      return TmdbHttpResponse(
        statusCode: 200,
        body: jsonEncode(<String, Object?>{
          'id': 603,
          'title': 'The Matrix',
          'release_date': '1999-03-30',
          'overview': 'A hacker learns the truth.',
          'poster_path': '/p.jpg',
          'vote_average': 8.2,
          'runtime': 136,
          'genres': <Object?>[
            <String, Object?>{'id': 878, 'name': 'Science Fiction'},
          ],
        }),
      );
    }
    return const TmdbHttpResponse(statusCode: 404, body: '{}');
  }
}

String _moviePayload(String url) => jsonEncode(<String, Object?>{
  'id': 'm1',
  'title': 'Test Movie',
  'type': 'movie',
  'url': url,
  'year': 2020,
});

DiscoveryItem _movieItem(String extensionId, String url) => DiscoveryItem(
  key: 'test|movie|2020',
  title: 'Test Movie',
  type: MediaType.movie,
  year: 2020,
  references: <DiscoveryReference>[
    DiscoveryReference(extensionId: extensionId, url: url),
  ],
);

Future<void> _waitFor(
  bool Function() test, {
  String reason = 'condition not met in time',
}) async {
  final Stopwatch sw = Stopwatch()..start();
  while (!test()) {
    if (sw.elapsed > const Duration(seconds: 5)) {
      t.fail(reason);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// A resolver that finds nothing, so a test can exercise the details screen
/// without an extension subsystem behind it.
///
/// This is the DEFAULT for every test in this file. A catalogue-only item with
/// no installed source is exactly this case: nothing to match, metadata comes
/// from the catalogue alone, and the screen must still work. Tests that care
/// about matching override it with [ScriptedCatalogueReferenceResolver].
class _NoMatchResolver implements CatalogueReferenceResolver {
  const _NoMatchResolver();

  @override
  Future<List<DiscoveryReference>> resolve(DiscoveryItem item) async =>
      const <DiscoveryReference>[];
}

/// Returns whatever references the test scripted, recording what it was asked.
class ScriptedCatalogueReferenceResolver implements CatalogueReferenceResolver {
  ScriptedCatalogueReferenceResolver(this.references);

  final List<DiscoveryReference> references;

  /// Every item the resolver was asked about, in call order.
  final List<DiscoveryItem> asked = <DiscoveryItem>[];

  /// When set, [resolve] throws it instead of answering.
  Object? throwInstead;

  @override
  Future<List<DiscoveryReference>> resolve(DiscoveryItem item) async {
    asked.add(item);
    if (throwInstead != null) throw throwInstead!;
    return references;
  }
}

ProviderContainer _container(
  DiscoveryTestHarness h, {
  TmdbClient? tmdb,
  CatalogueReferenceResolver? resolver,
}) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      metadataServiceProvider.overrideWith(
        (Ref ref) => MetadataService(manager: h.manager, tmdb: tmdb),
      ),
      catalogueReferenceResolverProvider.overrideWithValue(
        resolver ?? const _NoMatchResolver(),
      ),
    ],
  );
  t.addTearDown(container.dispose);
  return container;
}

void main() {
  late Directory tempDir;

  t.setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('specta_details_state');
    t.addTearDown(() => tempDir.delete(recursive: true));
  });

  t.group('DetailsSessionNotifier — statuses', () {
    t.test('starts idle', () {
      final ProviderContainer container = _container(DiscoveryTestHarness());
      t.expect(
        container.read(detailsSessionProvider).status,
        DetailsStatus.idle,
      );
    });

    t.test('successful open ends in success with canonical metadata', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,details');
      const String url = 'https://example.com/movie/1';
      h.sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.details("$url"))',
        _moviePayload(url),
      );

      final ProviderContainer container = _container(h);
      await container
          .read(detailsSessionProvider.notifier)
          .open(_movieItem('extA', url));

      final DetailsState state = container.read(detailsSessionProvider);
      t.expect(state.status, DetailsStatus.success);
      t.expect(state.metadata, t.isNotNull);
      t.expect(state.metadata!.title, 'Test Movie');
      t.expect(state.metadata!.details.single.extensionId, 'extA');
      t.expect(state.isPartial, t.isFalse);
    });

    t.test('open shows discovery data immediately while loading', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,details');
      const String url = 'https://example.com/movie/1';
      h.sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.details("$url"))',
        _moviePayload(url),
      );
      h.sandbox.delay = const Duration(milliseconds: 120);

      final ProviderContainer container = _container(h);
      final Future<void> opening = container
          .read(detailsSessionProvider.notifier)
          .open(_movieItem('extA', url));

      await _waitFor(
        () =>
            container.read(detailsSessionProvider).status ==
            DetailsStatus.loading,
        reason: 'loading state never appeared',
      );
      final DetailsState loading = container.read(detailsSessionProvider);
      // Discovery-observed data is available during loading; nothing invented.
      t.expect(loading.item!.title, 'Test Movie');
      t.expect(loading.metadata, t.isNull);

      await opening;
      t.expect(
        container.read(detailsSessionProvider).status,
        DetailsStatus.success,
      );
    });

    t.test(
      'all references failing ends in failure with reference ids',
      () async {
        final DiscoveryTestHarness h = DiscoveryTestHarness();
        await h.installExtension(
          tempDir,
          'extA',
          capabilities: 'search,details',
        );
        const String url = 'https://example.com/movie/1';
        h.sandbox.setAsyncError(
          'JSON.stringify(await _spectaInstance.details("$url"))',
          'down',
        );

        final ProviderContainer container = _container(h);
        await container
            .read(detailsSessionProvider.notifier)
            .open(_movieItem('extA', url));

        final DetailsState state = container.read(detailsSessionProvider);
        t.expect(state.status, DetailsStatus.failure);
        t.expect(state.metadata, t.isNull);
        t.expect(state.failedReferences, <String>['extA']);
      },
    );

    t.test(
      'one reference failing among two is an honest partial success',
      () async {
        final DiscoveryTestHarness h = DiscoveryTestHarness();
        await h.installExtension(
          tempDir,
          'extA',
          capabilities: 'search,details',
        );
        await h.installExtension(
          tempDir,
          'extB',
          capabilities: 'search,details',
        );

        const String urlA = 'https://example.com/a/movie/1';
        const String urlB = 'https://example.com/b/movie/1';
        h.sandbox.setAsyncError(
          'JSON.stringify(await _spectaInstance.details("$urlA"))',
          'down',
        );
        h.sandbox.setAsyncResult(
          'JSON.stringify(await _spectaInstance.details("$urlB"))',
          _moviePayload(urlB),
        );

        final DiscoveryItem item = DiscoveryItem(
          key: 'test|movie|2020',
          title: 'Test Movie',
          type: MediaType.movie,
          year: 2020,
          references: <DiscoveryReference>[
            const DiscoveryReference(extensionId: 'extA', url: urlA),
            const DiscoveryReference(extensionId: 'extB', url: urlB),
          ],
        );

        final ProviderContainer container = _container(h);
        await container.read(detailsSessionProvider.notifier).open(item);

        final DetailsState state = container.read(detailsSessionProvider);
        t.expect(state.status, DetailsStatus.success);
        t.expect(state.isPartial, t.isTrue);
        t.expect(state.failedReferences, t.contains('extA'));
        t.expect(state.metadata!.details.single.extensionId, 'extB');
      },
    );

    t.test('reset returns to idle and rejects in-flight requests', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,details');
      const String url = 'https://example.com/movie/1';
      h.sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.details("$url"))',
        _moviePayload(url),
      );
      h.sandbox.delay = const Duration(milliseconds: 120);

      final ProviderContainer container = _container(h);
      final Future<void> opening = container
          .read(detailsSessionProvider.notifier)
          .open(_movieItem('extA', url));
      await _waitFor(
        () =>
            container.read(detailsSessionProvider).status ==
            DetailsStatus.loading,
        reason: 'loading state never appeared',
      );

      container.read(detailsSessionProvider.notifier).reset();
      t.expect(
        container.read(detailsSessionProvider).status,
        DetailsStatus.idle,
      );

      await opening;
      // The stale response must not have overwritten the idle reset.
      t.expect(
        container.read(detailsSessionProvider).status,
        DetailsStatus.idle,
      );
    });

    t.test(
      'a stale slow open cannot overwrite a newer open (A then B)',
      () async {
        final DiscoveryTestHarness h = DiscoveryTestHarness();
        await h.installExtension(
          tempDir,
          'extA',
          capabilities: 'search,details',
        );
        await h.installExtension(
          tempDir,
          'extB',
          capabilities: 'search,details',
        );

        const String urlA = 'https://example.com/a/movie/1';
        const String urlB = 'https://example.com/b/movie/1';

        // A responds slowly with a DISTINCT title; B responds fast.
        final String payloadA = jsonEncode(<String, Object?>{
          'id': 'mA',
          'title': 'Slow Movie A',
          'type': 'movie',
          'url': urlA,
        });
        final String payloadB = jsonEncode(<String, Object?>{
          'id': 'mB',
          'title': 'Fast Movie B',
          'type': 'movie',
          'url': urlB,
        });

        h.sandbox.setAsyncResult(
          'JSON.stringify(await _spectaInstance.details("$urlA"))',
          payloadA,
        );
        h.sandbox.setAsyncResult(
          'JSON.stringify(await _spectaInstance.details("$urlB"))',
          payloadB,
        );
        h.sandbox.delay = const Duration(milliseconds: 150);

        final ProviderContainer container = _container(h);
        final DetailsSessionNotifier notifier = container.read(
          detailsSessionProvider.notifier,
        );

        final Future<void> openA = notifier.open(_movieItem('extA', urlA));
        await _waitFor(
          () =>
              container.read(detailsSessionProvider).status ==
              DetailsStatus.loading,
          reason: 'A never reached loading',
        );
        h.sandbox.delay = Duration.zero; // B answers immediately

        await notifier.open(_movieItem('extB', urlB));
        await openA; // A lands late — must be rejected

        final DetailsState state = container.read(detailsSessionProvider);
        t.expect(state.status, DetailsStatus.success);
        t.expect(state.metadata!.title, 'Fast Movie B');
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Real-device regression: a CATALOGUE-ONLY item (Home "Popular", discovered by
  // TMDB, with no extension behind it) used to land on `failure` forever.
  // ---------------------------------------------------------------------------
  t.group('DetailsSessionNotifier — catalogue-only items', () {
    t.test(
      'an item with no extension reference still reaches success',
      () async {
        final ProviderContainer container = _container(
          DiscoveryTestHarness(),
          tmdb: TmdbClient(
            config: const TmdbConfig(apiKey: _testTmdbKey),
            transport: _RoutingTmdbTransport(),
          ),
        );

        await container
            .read(detailsSessionProvider.notifier)
            .open(_catalogueOnlyItem('The Matrix', 1999));

        final DetailsState state = container.read(detailsSessionProvider);
        t.expect(
          state.status,
          DetailsStatus.success,
          reason: 'a catalogue-only title must be completed, not refused',
        );
        t.expect(state.metadata, t.isNotNull);
        // The identity stays the one the tapped card already carried.
        t.expect(state.metadata!.key, 'the matrix|movie|1999');
        t.expect(state.metadata!.description, 'A hacker learns the truth.');
        // No extension was ever consulted, so nothing claims to be playable.
        t.expect(state.metadata!.hasExtensionContribution, t.isFalse);
        t.expect(state.hasExtensionReference, t.isFalse);
      },
    );

    t.test('a refresh keeps the resolved metadata on screen', () async {
      final ProviderContainer container = _container(
        DiscoveryTestHarness(),
        tmdb: TmdbClient(
          config: const TmdbConfig(apiKey: _testTmdbKey),
          transport: _RoutingTmdbTransport(),
        ),
      );
      final DetailsSessionNotifier notifier = container.read(
        detailsSessionProvider.notifier,
      );
      final DiscoveryItem item = _catalogueOnlyItem('The Matrix', 1999);

      await notifier.open(item);
      t.expect(
        container.read(detailsSessionProvider).status,
        DetailsStatus.success,
      );

      // Mid-refresh the screen must NOT be blank: `loading` here means "new
      // round in flight", and the old record stays readable throughout.
      final Future<void> refreshing = notifier.open(item, refresh: true);
      await _waitFor(
        () =>
            container.read(detailsSessionProvider).status ==
            DetailsStatus.loading,
        reason: 'refresh never reached loading',
      );
      t.expect(container.read(detailsSessionProvider).metadata, t.isNotNull);
      await refreshing;

      t.expect(
        container.read(detailsSessionProvider).status,
        DetailsStatus.success,
      );
      t.expect(container.read(detailsSessionProvider).metadata, t.isNotNull);
    });

    t.test('an unreachable catalogue lands on failure, not loading', () async {
      final ProviderContainer container = _container(
        DiscoveryTestHarness(),
        tmdb: TmdbClient(
          config: const TmdbConfig(apiKey: _testTmdbKey),
          transport: _RoutingTmdbTransport(searchStatus: 500),
        ),
      );

      await container
          .read(detailsSessionProvider.notifier)
          .open(_catalogueOnlyItem('The Matrix', 1999));

      // The zero-reference case deliberately holds `loading` while enrichment
      // runs; if enrichment cannot complete the work it must resolve to
      // `failure` rather than spinning forever.
      t.expect(
        container.read(detailsSessionProvider).status,
        DetailsStatus.failure,
      );
    });
  });

  t.group('catalogue-only items resolve to a playable source', () {
    t.test('a matched catalogue item gains the reference that resolves it', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      const String url = 'https://example.com/matrix';
      final ScriptedCatalogueReferenceResolver resolver =
          ScriptedCatalogueReferenceResolver(<DiscoveryReference>[
            const DiscoveryReference(
              extensionId: 'extA',
              url: 'https://example.com/matrix',
            ),
          ]);

      // The extension can now answer `details` because it was matched.
      h.sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.details("$url"))',
        _moviePayload(url),
      );

      final ProviderContainer container = _container(
        h,
        resolver: resolver,
        tmdb: TmdbClient(
          config: const TmdbConfig(apiKey: _testTmdbKey),
          transport: _RoutingTmdbTransport(),
        ),
      );

      await container
          .read(detailsSessionProvider.notifier)
          .open(_catalogueOnlyItem('The Matrix', 1999));

      final DetailsState state = container.read(detailsSessionProvider);
      t.expect(state.status, DetailsStatus.success);
      // The item the screen now holds carries a reference — this is what makes
      // "Play" possible for a title that came from the catalogue.
      t.expect(state.item!.references, t.hasLength(1));
      t.expect(state.item!.references.single.extensionId, 'extA');
      t.expect(state.hasExtensionReference, t.isTrue);
      // The catalogue's own identity is preserved, not replaced.
      t.expect(state.item!.title, 'The Matrix');
      t.expect(state.item!.cover, 'https://image.tmdb.org/t/p/w500/rail.jpg');
    });

    t.test('an item that already has references is never re-matched', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,details');
      const String url = 'https://example.com/movie/1';
      h.sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.details("$url"))',
        _moviePayload(url),
      );
      final ScriptedCatalogueReferenceResolver resolver =
          ScriptedCatalogueReferenceResolver(const <DiscoveryReference>[]);

      final ProviderContainer container = _container(h, resolver: resolver);
      await container
          .read(detailsSessionProvider.notifier)
          .open(_movieItem('extA', url));

      // Discovery already established provenance; re-matching would risk
      // overwriting it with a guess.
      t.expect(resolver.asked, t.isEmpty);
      t.expect(
        container
            .read(detailsSessionProvider)
            .item!
            .references
            .single
            .extensionId,
        'extA',
      );
    });

    t.test('a throwing resolver does not break the details screen', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      final ScriptedCatalogueReferenceResolver resolver =
          ScriptedCatalogueReferenceResolver(const <DiscoveryReference>[])
            ..throwInstead = StateError('registry unavailable');

      final ProviderContainer container = _container(
        h,
        resolver: resolver,
        tmdb: TmdbClient(
          config: const TmdbConfig(apiKey: _testTmdbKey),
          transport: _RoutingTmdbTransport(),
        ),
      );

      await container
          .read(detailsSessionProvider.notifier)
          .open(_catalogueOnlyItem('The Matrix', 1999));

      // A broken source lookup must never become a broken details screen: the
      // catalogue metadata is still perfectly good.
      final DetailsState state = container.read(detailsSessionProvider);
      t.expect(state.status, DetailsStatus.success);
      t.expect(state.item!.references, t.isEmpty);
    });
  });
}
