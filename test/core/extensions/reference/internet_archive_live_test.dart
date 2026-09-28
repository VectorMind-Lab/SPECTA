@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/contract/extension_source.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/in_memory_extension_registry.dart';
import 'package:specta/core/extensions/runtime/controlled_runtime_api.dart';
import 'package:specta/core/extensions/runtime/extension_runtime.dart';
import 'package:specta/core/extensions/runtime/flutter_js_sandbox.dart';

/// Phase 2I — LIVE validation against the real Internet Archive.
///
/// This suite is OPT-IN and is NOT part of the default `flutter test` run,
/// because the project's automated verification must never depend on a
/// third-party website being up. It is separated deliberately so that
/// "verified against recorded fixtures" and "verified against the live
/// provider" can never be confused for one another.
///
/// Run it explicitly:
///
///   SPECTA_LIVE_IA=1 flutter test \
///     test/core/extensions/reference/internet_archive_live_test.dart
///
/// With `tool/run_tests_real_js.sh`-style PATH setup on Windows, so the QuickJS
/// bridge is loadable.
///
/// It uses the PRODUCTION request policy (private-host blocking ON) and the
/// real `dart:io` transport — the same code path the shipped application uses.
const String _extensionPath = 'extensions/internet_archive_reference.js';
const String _extensionId = 'org.specta.reference.internetarchive';

void main() {
  final bool enabled = Platform.environment['SPECTA_LIVE_IA'] == '1';

  if (!enabled) {
    test('live Internet Archive validation (opt-in)', () {
      // Reported as skipped, with the reason, rather than silently absent.
      markTestSkipped(
        'Set SPECTA_LIVE_IA=1 to run the live provider validation.',
      );
    });
    return;
  }

  late Directory dir;
  late ExtensionManager manager;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('specta_ia_live');
    final File file = File('${dir.path}/internet_archive_reference.js');
    await file.writeAsString(await File(_extensionPath).readAsString());

    manager = ExtensionManager(
      registry: InMemoryExtensionRegistry(),
      // Production wiring: no transport override, no policy weakening.
      runtimeApi: ControlledExtensionRuntimeApi(),
      sandboxFactory: FlutterJsSandbox.new,
    );

    final SpectaResult<ExtensionRecord> installed = await manager
        .importExtension(filePath: file.path);
    expect(installed.isOk, isTrue, reason: installed.failureOrNull?.message);

    final SpectaResult<ExtensionRuntime> loaded = await manager.loadRuntime(
      _extensionId,
    );
    expect(loaded.isOk, isTrue, reason: loaded.failureOrNull?.message);
  });

  tearDownAll(() async {
    await manager.shutdownAll();
    try {
      await dir.delete(recursive: true);
    } on Object catch (_) {
      // Best effort on Windows.
    }
  });

  test('LIVE-1 search returns real results from archive.org', () async {
    final SpectaResult<List<SearchResult>> search = await manager
        .callOperation<List<SearchResult>>(
          _extensionId,
          (ExtensionRuntime r) => r.search(query: 'chaplin', page: 1),
        );

    expect(search.isOk, isTrue, reason: search.failureOrNull?.message);
    expect(search.valueOrNull, isNotEmpty);
    expect(
      search.valueOrNull!.every((SearchResult r) => r.type == MediaType.movie),
      isTrue,
    );
    // ignore: avoid_print
    print(
      'LIVE-1: ${search.valueOrNull!.length} results; '
      'first=${search.valueOrNull!.first.title} '
      '(${search.valueOrNull!.first.url})',
    );
  });

  test('LIVE-2 details and sources resolve to a real playable MP4', () async {
    final SpectaResult<List<SearchResult>> search = await manager
        .callOperation<List<SearchResult>>(
          _extensionId,
          (ExtensionRuntime r) =>
              r.search(query: 'chaplin film festival', page: 1),
        );
    expect(search.isOk, isTrue, reason: search.failureOrNull?.message);
    expect(search.valueOrNull, isNotEmpty);

    // Walk the results until one yields both metadata and a playable source:
    // the Archive is an open corpus and a first hit may legitimately be an item
    // with no MP4 derivative or a restricted one. Reporting how many had to be
    // skipped is part of the honest record.
    int inspected = 0;
    ExtensionSource? playable;
    String? reference;

    for (final SearchResult result in search.valueOrNull!) {
      inspected++;
      if (inspected > 5) break;

      final SpectaResult<MediaDetails> details = await manager
          .callOperation<MediaDetails>(
            _extensionId,
            (ExtensionRuntime r) => r.details(url: result.url),
          );
      if (details.isErr) continue;

      expect(details.valueOrNull!.title, isNotEmpty);
      expect(details.valueOrNull!.type, MediaType.movie);
      expect(details.valueOrNull!.seasons, isEmpty);

      final SpectaResult<List<ExtensionSource>> sources = await manager
          .callOperation<List<ExtensionSource>>(
            _extensionId,
            (ExtensionRuntime r) => r.getSources(reference: result.url),
          );
      if (sources.isErr || sources.valueOrNull!.isEmpty) continue;

      playable = sources.valueOrNull!.first;
      reference = result.url;
      break;
    }

    final ExtensionSource? found = playable;
    expect(
      found,
      isNotNull,
      reason:
          'no item out of the first $inspected search results yielded a '
          'playable MP4; the live provider may have changed',
    );
    final ExtensionSource source = found!;
    expect(source.type, SourceType.mp4);
    expect(source.url.startsWith('https://'), isTrue);

    // ignore: avoid_print
    print(
      'LIVE-2: reference=$reference extracted=$inspected '
      'source=${source.url} quality=${source.quality}',
    );

    // The decisive check: the URL SPECTA would hand to MediaKit must really be
    // a video/mp4 endpoint. Probed independently of the extension, so the
    // extension cannot be "right" by its own definition.
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.headUrl(
        Uri.parse(source.url),
      );
      request.followRedirects = true;
      final HttpClientResponse response = await request.close();
      expect(
        response.statusCode,
        200,
        reason: 'the resolved source must answer HEAD 200 after redirects',
      );
      final String contentType =
          response.headers.value(HttpHeaders.contentTypeHeader) ?? '';
      expect(
        contentType.toLowerCase(),
        contains('video/mp4'),
        reason: 'the resolved source must actually be an MP4',
      );
      // ignore: avoid_print
      print('LIVE-2: HEAD 200 content-type=$contentType');
    } finally {
      client.close(force: true);
    }
  });

  test('LIVE-3 a deliberately impossible query is an empty success, not an '
      'error', () async {
    final SpectaResult<List<SearchResult>> search = await manager
        .callOperation<List<SearchResult>>(
          _extensionId,
          (ExtensionRuntime r) =>
              r.search(query: 'zzzqqqnosuchtitle12345xy', page: 1),
        );

    expect(search.isOk, isTrue, reason: search.failureOrNull?.message);
    expect(search.valueOrNull, isEmpty);
  });

  test('LIVE-4 a restricted item fails honestly', () async {
    final SpectaResult<MediaDetails> details = await manager
        .callOperation<MediaDetails>(
          _extensionId,
          (ExtensionRuntime r) => r.details(url: 'night_of_the_living_dead'),
        );

    // Either the item is still restricted (a clean failure) or the Archive has
    // since made it public (a clean success). What must never happen is an
    // invented payload or a crash.
    if (details.isErr) {
      final SpectaFailure failure = details.failureOrNull!;
      expect(failure.message, isNotEmpty);
      // The provider reason lives in `detail`; both are printed so the evidence
      // records WHY it failed, not just that it did.
      final String? detail = failure is ExtensionFailure
          ? failure.detail
          : null;
      expect(detail, isNotNull);
      expect(detail, isNotEmpty);
      // ignore: avoid_print
      print(
        'LIVE-4: restricted item rejected: '
        '${failure.message} | $detail',
      );
    } else {
      expect(details.valueOrNull!.title, isNotEmpty);
      // ignore: avoid_print
      print('LIVE-4: item is now public: ${details.valueOrNull!.title}');
    }
  });
}
