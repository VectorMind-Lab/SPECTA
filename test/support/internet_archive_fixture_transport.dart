library;

import 'dart:ffi';
import 'dart:io';

import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/runtime/controlled_runtime_api.dart';

/// Phase 2I test support: a deterministic transport that answers the Internet
/// Archive reference extension from RECORDED fixtures instead of the network.
///
/// Why this exists: the reference extension must be exercised through the REAL
/// QuickJS engine (that is the only way to run extension JavaScript in this
/// project), but the default test suite must never depend on a live third-party
/// website. This transport is the seam that makes both true at once — real
/// engine, real extension code, recorded provider responses, zero network.
///
/// Live validation is a SEPARATE, opt-in test
/// (`test/core/extensions/reference/internet_archive_live_test.dart`), so
/// "verified against fixtures" and "verified against the live provider" are
/// never confused for one another.

/// Absolute path of the recorded fixtures, relative to the package root (the
/// working directory `flutter test` runs in).
const String internetArchiveFixtureDirectory =
    'test/support/fixtures/internet_archive';

/// Why the real-engine Phase 2I suite cannot run here, or null when it can.
///
/// Mirrors the Phase 2H real-engine gate exactly: on Windows the flutter_js
/// QuickJS bridge must be loadable in the test process (see
/// `tool/run_tests_real_js.sh`). When it is not, the suite is SKIPPED and
/// reported as unverified — never as passing.
String? internetArchiveEngineSkipReason() {
  if (!Platform.isWindows) return null;
  try {
    final DynamicLibrary bridge = DynamicLibrary.open('quickjs_c_bridge.dll');
    if (!bridge.providesSymbol('jsNewRuntime')) {
      return 'quickjs_c_bridge.dll was found but does not export jsNewRuntime.';
    }
    return null;
  } on Object catch (e) {
    return 'The flutter_js QuickJS bridge is not loadable in this process '
        '($e). Run tool/run_tests_real_js.sh. Phase 2I real-engine '
        'verification is PENDING here.';
  }
}

/// Loads one recorded fixture body.
String internetArchiveFixture(String name) =>
    File('$internetArchiveFixtureDirectory/$name').readAsStringSync();

/// A transport that answers every request from the recorded fixtures.
///
/// Mapping is by request URL, which is the same thing the extension decides on:
/// `/advancedsearch.php` is a discovery call and `/metadata/<id>` is an item
/// call. The identifiers below are chosen per test to select the failure shape
/// under test (restricted item, missing metadata, non-JSON body, HTTP error,
/// transport failure, item with no playable file).
final class InternetArchiveFixtureTransport implements ExtensionHttpTransport {
  /// Every URL the extension asked for, in order.
  final List<Uri> requests = <Uri>[];

  /// Every method, parallel to [requests].
  final List<String> methods = <String>[];

  int get calls => requests.length;

  /// The single URL that was requested, asserted in tests that expect exactly
  /// one exchange.
  Uri get onlyRequest => requests.single;

  bool get sawAdvancedSearch =>
      requests.any((Uri u) => u.path.contains('advancedsearch.php'));

  bool get sawMetadataRequest =>
      requests.any((Uri u) => u.path.contains('/metadata/'));

  @override
  Future<ExtensionHttpResult> send({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
    required int maxBytes,
    required int maxRedirects,
  }) async {
    requests.add(uri);
    methods.add(method);

    final String url = uri.toString();

    if (url.contains('advancedsearch.php')) {
      final String query = Uri.decodeComponent(uri.query);
      if (query.contains('nosuchtitlezzzqqq')) {
        return _jsonFixture('search_empty.json');
      }
      if (query.contains('malformedprobe')) {
        return _jsonFixture('search_malformed.json');
      }
      // Note: the marker is a single word with no Solr operator characters,
      // because the extension STRIPS those from a user query before sending it.
      if (query.contains('chainprobe')) {
        return _jsonFixture('search_chain.json');
      }
      return _jsonFixture('search_movies.json');
    }

    if (url.contains('/metadata/')) {
      final String identifier = Uri.decodeComponent(
        url.split('/metadata/').last.split('?').first,
      );
      switch (identifier) {
        case 'charlie_chaplin_film_fest':
          return _jsonFixture('metadata_feature_film.json');
        case 'TheFastandtheFuriousJohnIreland1954goofyrip':
          return _jsonFixture('metadata_no_runtime.json');
        case 'night_of_the_living_dead':
          return _jsonFixture('metadata_dark.json');
        case 'absent_item':
          return _jsonFixture('metadata_no_metadata.json');
        case 'no_playable_item':
          return _jsonFixture('metadata_no_playable_file.json');
        case 'not_json_item':
          // HTTP 200 with an HTML body: the extension must classify this as a
          // parse failure, not mine a value out of it.
          return ExtensionHttpResult(
            statusCode: 200,
            headers: const <String, String>{'content-type': 'text/html'},
            body: internetArchiveFixture('error_not_json.txt'),
          );
        case 'server_error_item':
          // Non-2xx: the controlled API marks this not-ok and names the status.
          return const ExtensionHttpResult(
            statusCode: 502,
            headers: <String, String>{'content-type': 'text/html'},
            body: '<html><body>502 Bad Gateway</body></html>',
          );
        case 'offline_item':
          // No response at all: a transport failure, the shape a device with no
          // connectivity produces.
          return const ExtensionHttpResult(
            failureType: ExtensionFailureType.networkError,
            error: 'Socket failure: test transport',
          );
      }
    }

    return const ExtensionHttpResult(
      statusCode: 404,
      headers: <String, String>{'content-type': 'application/json'},
      body: '{"error":"no fixture for this request"}',
    );
  }

  ExtensionHttpResult _jsonFixture(String name) => ExtensionHttpResult(
    statusCode: 200,
    headers: const <String, String>{'content-type': 'application/json'},
    body: internetArchiveFixture(name),
  );
}
