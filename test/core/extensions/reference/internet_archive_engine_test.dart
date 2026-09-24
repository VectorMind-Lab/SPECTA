@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/discovery/discovery_coordinator.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/contract/extension_capabilities.dart';
import 'package:specta/core/extensions/contract/extension_source.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/extension_registry.dart';
import 'package:specta/core/extensions/manager/in_memory_extension_registry.dart';
import 'package:specta/core/extensions/runtime/controlled_runtime_api.dart';
import 'package:specta/core/extensions/runtime/extension_runtime.dart';
import 'package:specta/core/extensions/runtime/flutter_js_sandbox.dart';
import 'package:specta/core/extensions/runtime/request_policy.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';
import 'package:specta/core/metadata/metadata_manager.dart';
import 'package:specta/core/sources/source_manager.dart';
import 'package:specta/core/sources/source_pool.dart';

import '../../../support/internet_archive_fixture_transport.dart';

/// Phase 2I — the reference extension driven through the REAL QuickJS engine.
///
/// The extension under test is the real
/// `extensions/internet_archive_reference.js`; the network is replaced by the
/// recorded-fixture transport, so the engine, the manifest gate, the capability
/// enforcement, the contract parsers and SPECTA's discovery/metadata/source
/// layers are all exercised for real while the suite stays offline and
/// deterministic.
///
/// The last group is the END-TO-END proof this phase exists for:
///
///   search() -> DiscoveryCoordinator -> details() -> MetadataManager
///            -> getSources() -> SourceManager (validate + rank) -> SourcePool
///
/// Playback itself (MediaKit) is NOT covered here: it needs a real media stack
/// and is a device-level concern. Phase 2E already verified MediaKit playback
/// on hardware (5/5) and the live suite in this directory verifies that the
/// provider really does serve a playable MP4.
const String _extensionPath = 'extensions/internet_archive_reference.js';
const String _extensionId = 'org.specta.reference.internetarchive';

void main() {
  final String? skip = internetArchiveEngineSkipReason();
  late Directory dir;
  late String extensionSource;
  late InternetArchiveFixtureTransport transport;
  late List<String> logs;

  ExtensionManager buildManager(ExtensionRegistry registry) => ExtensionManager(
    registry: registry,
    runtimeApi: ControlledExtensionRuntimeApi(
      transport: transport,
      logSink: (ExtensionLogLevel level, String message) =>
          logs.add('${level.code}:$message'),
      // Test-only policy. No external host is contacted (the transport answers
      // everything from fixtures), and private-host blocking stays ON in every
      // production wiring.
      policy: const ExtensionRequestPolicy(blockPrivateHosts: false),
    ),
    sandboxFactory: FlutterJsSandbox.new,
  );

  setUpAll(() async {
    extensionSource = await File(_extensionPath).readAsString();
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('specta_ia_reference');
    transport = InternetArchiveFixtureTransport();
    logs = <String>[];
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on Object catch (_) {
      // Windows may briefly hold a handle; cleanup must not fail a test.
    }
  });

  /// Installs the real extension file through the real installation boundary.
  Future<ExtensionManager> installAndLoad() async {
    final InMemoryExtensionRegistry registry = InMemoryExtensionRegistry();
    final ExtensionManager manager = buildManager(registry);
    final File file = File('${dir.path}/internet_archive_reference.js');
    await file.writeAsString(extensionSource);

    final SpectaResult<ExtensionRecord> installed = await manager
        .importExtension(filePath: file.path);
    expect(
      installed.isOk,
      isTrue,
      reason: installed.failureOrNull?.message,
    );

    final SpectaResult<ExtensionRuntime> loaded = await manager.loadRuntime(
      _extensionId,
    );
    expect(loaded.isOk, isTrue, reason: loaded.failureOrNull?.message);
    return manager;
  }

  Future<SpectaResult<T>> call<T>(
    ExtensionManager manager,
    Future<SpectaResult<T>> Function(ExtensionRuntime runtime) operation,
  ) => manager.callOperation<T>(_extensionId, operation);

  /// The full text of a failure as a developer would see it in diagnostics.
  ///
  /// A JavaScript `throw` surface lands in `detail` (the runtime's `message`
  /// names the operation), so both fields are joined here: asserting on the
  /// message alone would silently stop checking the provider reason.
  String failureText(SpectaFailure failure) {
    final String? detail =
        failure is ExtensionFailure ? failure.detail : null;
    return '${failure.message} | ${detail ?? ''}';
  }

  group('Phase 2I reference extension — real QuickJS engine', () {
    test('installs as a real, unverified movie extension', () async {
      final InMemoryExtensionRegistry registry = InMemoryExtensionRegistry();
      final ExtensionManager manager = buildManager(registry);
      final File file = File('${dir.path}/internet_archive_reference.js');
      await file.writeAsString(extensionSource);

      final SpectaResult<ExtensionRecord> installed = await manager
          .importExtension(filePath: file.path);

      expect(installed.isOk, isTrue, reason: installed.failureOrNull?.message);
      final ExtensionRecord record = installed.valueOrNull!;
      expect(record.id, _extensionId);
      expect(record.name, 'Internet Archive (Reference)');
      expect(record.version, '1.0.0');
      expect(record.apiVersion, 2);
      expect(record.contentType, 'movie');
      expect(
        record.trustLevel,
        TrustLevel.unverified,
        reason: 'the reference extension is unsigned by design and must never '
            'be classified Official',
      );

      // Loading it proves the JavaScript itself is valid on the real engine.
      final SpectaResult<ExtensionRuntime> loaded = await manager.loadRuntime(
        _extensionId,
      );
      expect(loaded.isOk, isTrue, reason: loaded.failureOrNull?.message);
      expect(logs, contains('info:Internet Archive reference extension loaded'));
    });

    test('declares only capabilities SPECTA actually grants it', () async {
      final ExtensionManager manager = await installAndLoad();

      final SpectaResult<ExtensionCapabilities> caps = await call(
        manager,
        (ExtensionRuntime r) => r.capabilities(),
      );
      expect(caps.isOk, isTrue, reason: caps.failureOrNull?.message);

      final ExtensionCapabilities value = caps.valueOrNull!;
      expect(value.contentTypes, <MediaType>[MediaType.movie]);
      expect(value.supportsSearch, isTrue);
      expect(value.supportsLatest, isTrue);
      expect(value.supportsDetails, isTrue);
      expect(value.providesMp4, isTrue);
      expect(value.providesHls, isFalse);
      // The documented limitations, asserted so they cannot drift silently.
      expect(value.seasons, isFalse);
      expect(value.episodes, isFalse);
      expect(value.multipleSources, isTrue);
      expect(value.subtitles, isTrue);
      expect(value.downloads, isTrue);
      expect(value.searchPagination, isTrue);
    });

    test('search() returns normalized results from a recorded response',
        () async {
      final ExtensionManager manager = await installAndLoad();

      final SpectaResult<List<SearchResult>> search = await call(
        manager,
        (ExtensionRuntime r) => r.search(query: 'chaplin', page: 1),
      );
      expect(search.isOk, isTrue, reason: search.failureOrNull?.message);

      final List<SearchResult> results = search.valueOrNull!;
      expect(results.length, 3);
      expect(
        results.every((SearchResult r) => r.type == MediaType.movie),
        isTrue,
      );
      expect(results.first.url, 'namus-kanla-yazilir_movie');
      expect(results.first.title, 'Namus Kanla Yazılır, Turkish Movie');
      expect(
        results.first.cover,
        'https://archive.org/services/img/namus-kanla-yazilir_movie',
      );

      // Two of the three recorded documents declare no year. The extension must
      // report null rather than invent one.
      expect(results[0].year, isNull);
      expect(results[1].year, isNull);
      expect(results[2].year, isNull);

      // The query reached the provider through the controlled channel, changed
      // into the Archive's own syntax, over GET.
      expect(transport.calls, 1);
      expect(transport.methods.single, 'GET');
      final String requested = Uri.decodeComponent(transport.onlyRequest.query);
      expect(requested, contains('mediatype:movies'));
      expect(requested, contains('chaplin'));
    });

    test('search() sanitises query characters that are search operators',
        () async {
      final ExtensionManager manager = await installAndLoad();

      await call(
        manager,
        (ExtensionRuntime r) => r.search(query: 'a:b AND (c) "d"*', page: 1),
      );

      final String requested = Uri.decodeComponent(transport.onlyRequest.query);
      // The words survive and are searched against both fields.
      expect(requested, contains('title:(a b AND c d)'));
      expect(requested, contains('description:(a b AND c d)'));
      // The user's operator characters are gone entirely: neither `"` nor `*`
      // appears anywhere in the request, and the sanitised fragment carries no
      // leftover punctuation from the input.
      expect(requested.contains('"'), isFalse);
      expect(requested.contains('*'), isFalse);
      expect(
        RegExp(r'title:\((.*?)\) OR').firstMatch(requested)!.group(1),
        'a b AND c d',
        reason: 'every Solr operator character in the user input must be '
            'removed, not merely escaped',
      );
    });

    test('search() maps an empty provider response to an empty list, not a '
        'failure', () async {
      final ExtensionManager manager = await installAndLoad();

      final SpectaResult<List<SearchResult>> search = await call(
        manager,
        (ExtensionRuntime r) => r.search(query: 'nosuchtitlezzzqqq', page: 1),
      );

      expect(search.isOk, isTrue, reason: search.failureOrNull?.message);
      expect(search.valueOrNull, isEmpty);
    });

    test('search() skips malformed rows without losing the valid ones',
        () async {
      final ExtensionManager manager = await installAndLoad();

      final SpectaResult<List<SearchResult>> search = await call(
        manager,
        (ExtensionRuntime r) => r.search(query: 'malformedprobe', page: 1),
      );
      expect(search.isOk, isTrue, reason: search.failureOrNull?.message);

      final List<SearchResult> results = search.valueOrNull!;
      // Four of the seven recorded rows are unusable (no identifier, no title,
      // a bare string, a null). The three usable rows must survive.
      expect(results.length, 3);
      expect(
        results.map((SearchResult r) => r.url),
        isNot(contains('a_document_whose_title_is_missing')),
      );
      expect(
        results.any((SearchResult r) => r.url == 'jesus-film-kru-language'),
        isTrue,
      );
      // A non-numeric year is dropped for that row only.
      final SearchResult oddYear = results.firstWhere(
        (SearchResult r) => r.url == 'a_document_with_a_non_numeric_year',
      );
      expect(oddYear.year, isNull);
    });

    test('latest() asks for the curated collection, newest first', () async {
      final ExtensionManager manager = await installAndLoad();

      final SpectaResult<List<SearchResult>> latest = await call(
        manager,
        (ExtensionRuntime r) => r.latest(page: 2),
      );
      expect(latest.isOk, isTrue, reason: latest.failureOrNull?.message);

      final String requested = Uri.decodeComponent(transport.onlyRequest.query);
      expect(requested, contains('collection:feature_films'));
      expect(requested, contains('addeddate desc'));
      expect(requested, contains('page=2'));
    });

    test('details() builds movie metadata, stripping provider HTML',
        () async {
      final ExtensionManager manager = await installAndLoad();

      final SpectaResult<MediaDetails> details = await call(
        manager,
        (ExtensionRuntime r) =>
            r.details(url: 'charlie_chaplin_film_fest'),
      );
      expect(details.isOk, isTrue, reason: details.failureOrNull?.message);

      final MediaDetails movie = details.valueOrNull!;
      expect(movie.id, 'charlie_chaplin_film_fest');
      expect(movie.type, MediaType.movie);
      expect(movie.title, 'Charlie Chaplin Festival');
      expect(movie.url, 'charlie_chaplin_film_fest');
      expect(movie.year, 1938);
      expect(movie.genres, <String>['comedy']);
      // `runtime: "1:17:26"` -> 4646 seconds.
      expect(movie.durationSeconds, 4646);
      expect(
        movie.cover,
        'https://archive.org/services/img/charlie_chaplin_film_fest',
      );
      expect(movie.description, contains('Four Chaplin shorts from 1917'));
      expect(
        movie.description,
        isNot(contains('<a href')),
        reason: 'provider HTML must be stripped before it reaches the UI',
      );
      expect(movie.rating, isNull, reason: 'the provider publishes no rating');
      expect(
        movie.seasons,
        isEmpty,
        reason: 'items are not series; a season tree would be fabricated',
      );
      expect(transport.sawMetadataRequest, isTrue);
    });

    test('details() reads a string year and falls back to a file duration',
        () async {
      final ExtensionManager manager = await installAndLoad();

      final SpectaResult<MediaDetails> details = await call(
        manager,
        (ExtensionRuntime r) =>
            r.details(url: 'TheFastandtheFuriousJohnIreland1954goofyrip'),
      );
      expect(details.isOk, isTrue, reason: details.failureOrNull?.message);

      final MediaDetails movie = details.valueOrNull!;
      // The provider reports `"year": "1955"` as a STRING.
      expect(movie.year, 1955);
      // No `runtime` field exists, so duration comes from the first file's
      // `length` (4356.1s -> 4356).
      expect(movie.durationSeconds, 4356);
      expect(movie.genres, <String>['drag Racing', 'action']);
    });

    test('details() fails honestly on a restricted item', () async {
      final ExtensionManager manager = await installAndLoad();

      final SpectaResult<MediaDetails> details = await call(
        manager,
        (ExtensionRuntime r) => r.details(url: 'night_of_the_living_dead'),
      );

      expect(details.isErr, isTrue);
      expect(
        failureText(details.failureOrNull!),
        contains('not publicly available'),
        reason: 'a restricted item is a distinguished outcome, not a generic '
            'error and never a fabricated payload',
      );
    });

    test('details() fails honestly when the payload has no metadata',
        () async {
      final ExtensionManager manager = await installAndLoad();

      final SpectaResult<MediaDetails> details = await call(
        manager,
        (ExtensionRuntime r) => r.details(url: 'absent_item'),
      );

      expect(details.isErr, isTrue);
      expect(
        failureText(details.failureOrNull!),
        contains('exposes no metadata'),
      );
    });

    test('details() fails honestly on a non-JSON provider response',
        () async {
      final ExtensionManager manager = await installAndLoad();

      final SpectaResult<MediaDetails> details = await call(
        manager,
        (ExtensionRuntime r) => r.details(url: 'not_json_item'),
      );

      expect(details.isErr, isTrue);
      expect(failureText(details.failureOrNull!), contains('not JSON'));
    });

    test('details() fails honestly on a provider HTTP error', () async {
      final ExtensionManager manager = await installAndLoad();

      final SpectaResult<MediaDetails> details = await call(
        manager,
        (ExtensionRuntime r) => r.details(url: 'server_error_item'),
      );

      expect(details.isErr, isTrue);
      expect(failureText(details.failureOrNull!), contains('HTTP 502'));
    });

    test('details() fails honestly when the device is offline', () async {
      final ExtensionManager manager = await installAndLoad();

      final SpectaResult<MediaDetails> details = await call(
        manager,
        (ExtensionRuntime r) => r.details(url: 'offline_item'),
      );

      expect(details.isErr, isTrue);
      expect(
        failureText(details.failureOrNull!).toLowerCase(),
        anyOf(contains('network'), contains('socket')),
      );
    });

    test('getSources() reports every playable MP4 and nothing else',
        () async {
      final ExtensionManager manager = await installAndLoad();

      final SpectaResult<List<ExtensionSource>> sources = await call(
        manager,
        (ExtensionRuntime r) =>
            r.getSources(reference: 'charlie_chaplin_film_fest'),
      );
      expect(sources.isOk, isTrue, reason: sources.failureOrNull?.message);

      final List<ExtensionSource> list = sources.valueOrNull!;
      expect(
        list.length,
        2,
        reason: 'the item has exactly two MP4 derivatives; the Ogg, MPEG2 and '
            'DivX files must NOT be reported as MP4',
      );
      expect(list.every((ExtensionSource s) => s.type == SourceType.mp4), isTrue);

      // Ordered as the provider lists them, best first: the h.264 480p
      // derivative, then the 240p one.
      expect(list[0].quality, '480p');
      expect(list[1].quality, '240p');
      expect(list[0].label, 'Source 1');
      expect(list[1].label, 'Source 2');
      expect(list[0].url, 'https://archive.org/download/charlie_chaplin_film_'
          'fest/charlie_chaplin_film_fest.mp4');
      expect(list[1].url, contains('charlie_chaplin_film_fest_512kb.mp4'));
      expect(
        list.every((ExtensionSource s) => s.url.startsWith('https://')),
        isTrue,
      );
      // Every reported URL must survive SPECTA's own structural validation.
      expect(list.every((ExtensionSource s) => s.url.length <= 2048), isTrue);
    });

    test('getSources() attaches only the subtitles that belong to the file',
        () async {
      final ExtensionManager manager = await installAndLoad();

      final SpectaResult<List<ExtensionSource>> sources = await call(
        manager,
        (ExtensionRuntime r) =>
            r.getSources(reference: 'charlie_chaplin_film_fest'),
      );

      final List<SubtitleTrack> subtitles = sources.valueOrNull!.first.subtitles!;
      expect(subtitles.length, 1);
      expect(
        subtitles.single.url,
        'https://archive.org/download/charlie_chaplin_film_fest/'
        'charlie_chaplin_film_fest.asr.srt',
      );
      // `asr` is the provider's transcription marker, NOT a language code.
      expect(
        subtitles.single.language,
        isNull,
        reason: 'a marker must not be reported as a language',
      );
      expect(subtitles.single.label, isNull);
    });

    test('getSources() reports NO sources rather than promoting a non-MP4 '
        'file', () async {
      final ExtensionManager manager = await installAndLoad();

      final SpectaResult<List<ExtensionSource>> sources = await call(
        manager,
        (ExtensionRuntime r) =>
            r.getSources(reference: 'no_playable_item'),
      );

      expect(
        sources.isOk,
        isTrue,
        reason: 'a legitimately empty pool is a successful resolution',
      );
      expect(sources.valueOrNull, isEmpty);
    });

    test('getSources() fails honestly on a restricted item', () async {
      final ExtensionManager manager = await installAndLoad();

      final SpectaResult<List<ExtensionSource>> sources = await call(
        manager,
        (ExtensionRuntime r) =>
            r.getSources(reference: 'night_of_the_living_dead'),
      );

      expect(sources.isErr, isTrue);
      expect(
        failureText(sources.failureOrNull!),
        contains('not publicly available'),
      );
    });

    test('refreshSource() re-resolves and is honest when nothing is playable',
        () async {
      final ExtensionManager manager = await installAndLoad();

      final SpectaResult<ExtensionSource> refreshed = await call(
        manager,
        (ExtensionRuntime r) =>
            r.refreshSource(reference: 'charlie_chaplin_film_fest'),
      );
      expect(refreshed.isOk, isTrue, reason: refreshed.failureOrNull?.message);
      expect(refreshed.valueOrNull!.quality, '480p');

      final SpectaResult<ExtensionSource> empty = await call(
        manager,
        (ExtensionRuntime r) =>
            r.refreshSource(reference: 'no_playable_item'),
      );
      expect(empty.isErr, isTrue);
      expect(
        failureText(empty.failureOrNull!),
        contains('no playable source'),
      );
    });

    test('healthCheck() answers, and shutdown() retires the runtime', () async {
      final ExtensionManager manager = await installAndLoad();

      expect(await manager.healthCheck(_extensionId), isTrue);

      await manager.shutdown(_extensionId);
      final SpectaResult<bool> afterShutdown = await call(
        manager,
        (ExtensionRuntime r) => r.healthCheck(),
      );
      expect(afterShutdown.isErr, isTrue);
    });

    test('two identical rounds produce identical results (deterministic)',
        () async {
      final ExtensionManager manager = await installAndLoad();

      final SpectaResult<List<SearchResult>> first = await call(
        manager,
        (ExtensionRuntime r) => r.search(query: 'chaplin', page: 1),
      );
      final SpectaResult<List<SearchResult>> second = await call(
        manager,
        (ExtensionRuntime r) => r.search(query: 'chaplin', page: 1),
      );

      expect(
        first.valueOrNull!.map((SearchResult r) => r.url).toList(),
        second.valueOrNull!.map((SearchResult r) => r.url).toList(),
      );
    });
  }, skip: skip);

  group('Phase 2I end-to-end — extension through SPECTA Core', () {
    test(
      'search -> discovery -> details -> metadata -> sources -> ranked pool',
      () async {
        final ExtensionManager manager = await installAndLoad();

        // --- 1. Discovery: ExtensionManager -> reference extension ---------
        final DiscoveryResult discovery = await DiscoveryCoordinator.discover(
          request: const SearchRequest(query: 'chainprobe'),
          manager: manager,
        );

        expect(discovery.items.length, 2, reason: 'two recorded items');
        expect(discovery.droppedCount, 0);
        expect(discovery.successes.length, 1);

        final DiscoveryItem item = discovery.items.firstWhere(
          (DiscoveryItem i) =>
              i.references.first.url == 'charlie_chaplin_film_fest',
        );
        expect(item.type, MediaType.movie);
        expect(item.year, 1938);
        expect(item.cover, contains('services/img/charlie_chaplin_film_fest'));
        // Provenance is preserved by Core, not discarded.
        expect(item.references.single.extensionId, _extensionId);

        // --- 2. Metadata: discovery provenance -> details() ----------------
        final MetadataResult metadata = await MetadataManager.metadataFor(
          item: item,
          manager: manager,
        );

        expect(metadata.hasItem, isTrue);
        expect(metadata.failures, isEmpty);
        expect(metadata.item!.title, 'Charlie Chaplin Festival');
        expect(metadata.item!.year, 1938);
        expect(metadata.item!.details.length, 1);

        // --- 3. Sources: same provenance -> getSources() -> ranked pool ----
        final SourcePool pool = await SourceManager.resolve(
          reference: item.key,
          extensions: <String, String>{
            for (final DiscoveryReference reference in item.references)
              reference.extensionId: reference.url,
          },
          manager: manager,
        );

        expect(pool.ranked.length, 2);
        expect(pool.failures, isEmpty);
        expect(pool.noExtensionAvailable, isFalse);

        // SPECTA chose, not the extension: the 480p candidate outranks 240p.
        expect(pool.selected, isNotNull);
        expect(pool.selected!.source.quality, '480p');
        expect(pool.selected!.extensionId, _extensionId);
        expect(
          pool.selected!.source.url,
          'https://archive.org/download/charlie_chaplin_film_fest/'
          'charlie_chaplin_film_fest.mp4',
        );
        // A real fallback order exists for the player to use.
        expect(pool.fallbacks.length, 1);
        expect(pool.fallbacks.single.source.quality, '240p');
        // Subtitles survived the whole pipeline to the selected candidate.
        expect(pool.selected!.source.subtitles, isNotEmpty);
      },
    );

    test('a provider failure is isolated: discovery still succeeds for the '
        'items that exist', () async {
      final ExtensionManager manager = await installAndLoad();

      // The second recorded item's metadata IS available; the first request the
      // coordinator makes is search. Then resolve sources for an item whose
      // provider response is a restricted document, proving the failure stays
      // contained and the pool is honestly empty rather than fabricated.
      final DiscoveryResult discovery = await DiscoveryCoordinator.discover(
        request: const SearchRequest(query: 'chainprobe'),
        manager: manager,
      );
      expect(discovery.items.length, 2);

      final SourcePool restricted = await SourceManager.resolve(
        reference: 'restricted',
        extensions: <String, String>{_extensionId: 'night_of_the_living_dead'},
        manager: manager,
      );

      expect(restricted.ranked, isEmpty);
      expect(restricted.selected, isNull);
      expect(restricted.allQueriedFailed, isTrue);
    });

    test('disabling the extension removes it from discovery entirely',
        () async {
      final ExtensionManager manager = await installAndLoad();

      await manager.setEnabled(_extensionId, false);

      final DiscoveryResult discovery = await DiscoveryCoordinator.discover(
        request: const SearchRequest(query: 'chainprobe'),
        manager: manager,
      );

      expect(discovery.items, isEmpty);
      expect(discovery.noExtensionAvailable, isTrue);
    });
  }, skip: skip);
}
