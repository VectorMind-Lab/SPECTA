import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/contract/extension_capability.dart';
import 'package:specta/core/extensions/contract/extension_source.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/extensions/runtime/extension_runtime.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';

import '../../../support/fake_js_sandbox.dart';

/// 2G-C pre-flight §36.4: one malformed entry must not break a whole result
/// list, and harmless-but-odd scalar values must not fail a request.
void main() {
  late FakeJsSandbox sandbox;
  late FakeRuntimeApi api;
  late ExtensionRuntime runtime;

  setUp(() {
    sandbox = FakeJsSandbox();
    api = FakeRuntimeApi();
  });

  Future<void> loadRuntime() async {
    sandbox.setEvalResult(sandboxBootstrap, '');
    runtime = ExtensionRuntime(
      sandbox: sandbox,
      api: api,
      capabilities: ExtensionCapability.values.toSet(),
    );
    final SpectaResult<void> result = await runtime.loadExtension(
      extensionId: 'test',
      jsCode: 'class Extension extends SpectaExtension {}',
    );
    expect(result.isOk, isTrue, reason: result.failureOrNull.toString());
  }

  group('§36.4 getSources — one bad source among good ones', () {
    test('a non-object row is skipped, good rows survive', () async {
      await loadRuntime();
      const String reference = 'https://example.com/m/1';
      sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.getSources("$reference"))',
        jsonEncode(<dynamic>[
          <String, dynamic>{'url': 'https://cdn.test/a.mp4', 'type': 'mp4'},
          'not-an-object',
          <String, dynamic>{'url': 'https://cdn.test/b.mp4', 'type': 'mp4'},
        ]),
      );

      final SpectaResult<List<ExtensionSource>> result =
          await runtime.getSources(reference: reference);

      expect(result.isOk, isTrue);
      expect(result.valueOrNull, hasLength(2));
    });

    test('a source with an unsupported type is skipped, others survive',
        () async {
      await loadRuntime();
      const String reference = 'https://example.com/m/2';
      sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.getSources("$reference"))',
        jsonEncode(<dynamic>[
          <String, dynamic>{'url': 'https://cdn.test/a.mp4', 'type': 'mp4'},
          <String, dynamic>{'url': 'https://cdn.test/x.mpd', 'type': 'dash'},
          <String, dynamic>{'url': 'https://cdn.test/b.mp4', 'type': 'mp4'},
        ]),
      );

      final SpectaResult<List<ExtensionSource>> result =
          await runtime.getSources(reference: reference);

      expect(result.isOk, isTrue);
      expect(
        result.valueOrNull!.map((ExtensionSource s) => s.url),
        <String>['https://cdn.test/a.mp4', 'https://cdn.test/b.mp4'],
      );
    });

    test('a source without a url is skipped, not fatal', () async {
      await loadRuntime();
      const String reference = 'https://example.com/m/3';
      sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.getSources("$reference"))',
        jsonEncode(<dynamic>[
          <String, dynamic>{'type': 'mp4'},
          <String, dynamic>{'url': 'https://cdn.test/a.mp4', 'type': 'mp4'},
        ]),
      );

      final SpectaResult<List<ExtensionSource>> result =
          await runtime.getSources(reference: reference);

      expect(result.isOk, isTrue);
      expect(result.valueOrNull, hasLength(1));
    });

    test('a list that is entirely unusable parses to an empty success',
        () async {
      await loadRuntime();
      const String reference = 'https://example.com/m/4';
      sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.getSources("$reference"))',
        jsonEncode(<dynamic>['nope', <String, dynamic>{'type': 'mp4'}]),
      );

      final SpectaResult<List<ExtensionSource>> result =
          await runtime.getSources(reference: reference);

      expect(result.isOk, isTrue);
      expect(result.valueOrNull, isEmpty);
    });
  });

  group('§36.4 request timeout — num handling', () {
    test('a fractional timeout (2.5) becomes a duration, not a failure',
        () async {
      await loadRuntime();
      final dynamic response = await sandbox.handlers['specta_request']!(
        <String, dynamic>{
          'url': 'https://example.test/api',
          'method': 'GET',
          'timeout': 2.5,
        },
      );
      final Map<String, dynamic> decoded =
          jsonDecode(response as String) as Map<String, dynamic>;

      expect(decoded['ok'], isTrue,
          reason: 'a fractional JS timeout must not fail the request');
      expect(api.lastRequest, isNotNull);
      expect(api.lastRequest!.timeout, const Duration(milliseconds: 3));
    });

    test('a string timeout degrades to the default, not a failure', () async {
      await loadRuntime();
      final dynamic response = await sandbox.handlers['specta_request']!(
        <String, dynamic>{
          'url': 'https://example.test/api',
          'method': 'GET',
          'timeout': 'soon',
        },
      );
      final Map<String, dynamic> decoded =
          jsonDecode(response as String) as Map<String, dynamic>;

      expect(decoded['ok'], isTrue);
      expect(api.lastRequest!.timeout, const Duration(milliseconds: 15000));
    });

    test('a large timeout is clamped by the API policy as before', () async {
      await loadRuntime();
      await sandbox.handlers['specta_request']!(
        <String, dynamic>{
          'url': 'https://example.test/api',
          'method': 'GET',
          'timeout': 999999999,
        },
      );
      expect(api.lastRequest!.timeout, greaterThan(const Duration(days: 1)));
    });
  });

  group('§36.4 details — non-string status must not fail the payload', () {
    test('a numeric status degrades to null/unknown without failing',
        () async {
      await loadRuntime();
      const String reference = 'https://example.com/m/1';
      sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.details("$reference"))',
        jsonEncode(<String, dynamic>{
          'id': 'm1',
          'title': 'Test Movie',
          'url': reference,
          'type': 'movie',
          'status': 7, // wrong type entirely
        }),
      );

      final SpectaResult<MediaDetails> result =
          await runtime.details(url: reference);

      expect(result.isOk, isTrue, reason: result.failureOrNull.toString());
      expect(result.valueOrNull!.status, isNull);
    });

    test('a valid string status still parses', () async {
      await loadRuntime();
      const String reference = 'https://example.com/m/1';
      sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.details("$reference"))',
        jsonEncode(<String, dynamic>{
          'id': 'm1',
          'title': 'Test Series',
          'url': reference,
          'type': 'series',
          'status': 'ongoing',
          'seasons': <Map<String, dynamic>>[
            <String, dynamic>{
              'seasonNumber': 1,
              'episodes': <Map<String, dynamic>>[
                <String, dynamic>{'episodeNumber': 1, 'url': 'https://x/e1'},
              ],
            },
          ],
        }),
      );

      final SpectaResult<MediaDetails> result =
          await runtime.details(url: reference);

      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.status, SeriesStatus.ongoing);
    });

    test('non-string optional detail fields degrade to null, not failure',
        () async {
      await loadRuntime();
      const String reference = 'https://example.com/m/1';
      sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.details("$reference"))',
        jsonEncode(<String, dynamic>{
          'id': 'm1',
          'title': 'Test Movie',
          'url': reference,
          'type': 'movie',
          'originalTitle': 99,
          'cover': <String>['nope'],
          'backdrop': true,
          'description': 3.14,
        }),
      );

      final SpectaResult<MediaDetails> result =
          await runtime.details(url: reference);

      expect(result.isOk, isTrue, reason: result.failureOrNull.toString());
      expect(result.valueOrNull!.originalTitle, isNull);
      expect(result.valueOrNull!.cover, isNull);
      expect(result.valueOrNull!.backdrop, isNull);
      expect(result.valueOrNull!.description, isNull);
    });
  });

  group('§36.4 search — malformed optional fields skip only that entry', () {
    test('numeric type/cover entries are skipped without losing others',
        () async {
      await loadRuntime();
      sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.search("batman", 1))',
        jsonEncode(<dynamic>[
          <String, dynamic>{
            'title': 'Good',
            'url': 'https://e.test/good',
            'type': 'movie',
          },
          <String, dynamic>{
            'title': 'NumericType',
            'url': 'https://e.test/t',
            'type': 7,
          },
          <String, dynamic>{
            'title': 'NumericCover',
            'url': 'https://e.test/c',
            'type': 'movie',
            'cover': 12345,
          },
        ]),
      );

      final SpectaResult<List<SearchResult>> result =
          await runtime.search(query: 'batman', page: 1);

      expect(result.isOk, isTrue);
      final List<SearchResult> results = result.valueOrNull!;
      // NumericType is skipped (unsupported type); NumericCover survives
      // with the cover dropped (a bad cover must not lose the row).
      expect(results, hasLength(2));
      expect(results[0].title, 'Good');
      expect(results[1].title, 'NumericCover');
      expect(results[1].cover, isNull);
    });
  });
}

class FakeRuntimeApi implements ExtensionRuntimeApi {
  ExtensionRequest? lastRequest;

  @override
  Future<ExtensionResponse> request(ExtensionRequest request) async {
    lastRequest = request;
    return ExtensionResponse(status: 200, ok: true, body: '{}');
  }

  @override
  void log(ExtensionLogLevel level, String message) {}
}
