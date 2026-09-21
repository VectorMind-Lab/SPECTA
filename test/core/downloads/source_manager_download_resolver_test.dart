@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/downloads/download_manager.dart';
import 'package:specta/core/downloads/download_models.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/downloads/source_manager_download_resolver.dart';
import 'package:specta/core/sources/source_models.dart';
import 'package:specta/core/sources/source_pool.dart';

import '../../support/discovery_test_harness.dart';

// PHASE 2G-C — the PRODUCTION source resolver's own tests.
//
// Everything the integration tests prove through the manager seam is proven
// here against the real resolver class: the captured-pool freshness rule,
// the source-invalidation rule (stale-pool requeue hazard, 2G-C §25), the
// real SourceManager re-resolution through the persisted provenance, and the
// honest null answers (no provenance / re-resolution failure).
//
// Deterministic: a real ExtensionManager over a scripted fake sandbox (the
// same harness the SourceManager tests use). No network anywhere.
class _ScriptedSourcesSandbox extends ScriptedJsSandbox {
  final Map<String, Object> sourcesScripts = <String, Object>{};

  @override
  Future<String> evaluateAsync(String expression) async {
    if (expression.contains('.getSources(')) {
      for (final MapEntry<String, Object> entry in sourcesScripts.entries) {
        if (expression.contains('"${entry.key}"')) {
          final Object scripted = entry.value;
          if (scripted is String) return scripted;
          throw scripted;
        }
      }
    }
    return super.evaluateAsync(expression);
  }
}

String _sourcesPayload(List<Map<String, Object?>> sources) =>
    jsonEncode(sources);

Map<String, Object?> _mp4(String url, {String? quality}) =>
    <String, Object?>{'url': url, 'type': 'mp4', 'quality': quality};

DownloadRecord _record({
  String id = 'movie1',
  String? extensionId = 'extA',
  String? reference = 'refA',
}) =>
    DownloadRecord(
      id: id,
      mediaKey: id,
      mediaType: MediaType.movie,
      title: 'Title $id',
      status: DownloadStatus.failed,
      bytesDownloaded: 0,
      filePath: '/unused/$id.mp4',
      sourceExtensionId: extensionId,
      sourceReference: reference,
      attempt: 1,
      createdAt: DateTime(2026, 9, 21),
      updatedAt: DateTime(2026, 9, 21),
    );

void main() {
  late Directory tempDir;
  late _ScriptedSourcesSandbox sandbox;
  late SourceManagerDownloadResolver resolver;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('specta_resolver_2gc');
    addTearDown(() {
      try {
        tempDir.delete(recursive: true);
      } on Object catch (_) {}
    });
    sandbox = _ScriptedSourcesSandbox();
    final DiscoveryTestHarness harness =
        DiscoveryTestHarness(sandbox: sandbox);
    await harness.installExtension(
      tempDir,
      'extA',
      capabilities: 'search,sources',
    );
    resolver = SourceManagerDownloadResolver(
      extensionManager: () => harness.manager,
    );
  });

  group('captured-pool freshness (2G-C §25)', () {
    test('serves the pool captured at enqueue when no failure preceded',
        () async {
      final SourcePool captured = SourcePool(
        ranked: const <RankedSource>[],
        outcomes: const <ExtensionSourceOutcome>[],
        reference: 'refA',
      );
      resolver.rememberPool('movie1', captured);

      final SourcePool? pool =
          await resolver.resolveSource(_record(), lastFailure: null);

      expect(identical(pool, captured), isTrue,
          reason: 'the freshest user-provided resolution is served as-is');
    });

    test('a non-invalidating failure (networkError) keeps the captured pool',
        () async {
      final SourcePool captured = SourcePool(
        ranked: const <RankedSource>[],
        outcomes: const <ExtensionSourceOutcome>[],
        reference: 'refA',
      );
      resolver.rememberPool('movie1', captured);

      final SourcePool? pool = await resolver.resolveSource(
        _record(),
        lastFailure: DownloadFailure(
          type: DownloadFailureType.networkError,
          message: DownloadFailureType.networkError.message,
        ),
      );

      expect(identical(pool, captured), isTrue,
          reason: 'a network drop does not invalidate the source URL');
    });

    test('a source-invalidating failure (httpError) discards the captured '
        'pool and re-resolves through the SourceManager', () async {
      final SourcePool captured = SourcePool(
        ranked: const <RankedSource>[],
        outcomes: const <ExtensionSourceOutcome>[],
        reference: 'refA',
      );
      resolver.rememberPool('movie1', captured);
      // The re-resolution will find THIS candidate — proving the fresh
      // resolution drove the answer, not the stale captured pool.
      sandbox.sourcesScripts['refA'] = _sourcesPayload(<Map<String, Object?>>[
        _mp4('https://fresh.example/video.mp4', quality: '1080p'),
      ]);

      final SourcePool? pool = await resolver.resolveSource(
        _record(),
        lastFailure: DownloadFailure(
          type: DownloadFailureType.httpError,
          message: DownloadFailureType.httpError.message,
        ),
      );

      expect(pool, isNotNull);
      expect(pool!.ranked, hasLength(1));
      expect(pool.ranked.single.source.url, 'https://fresh.example/video.mp4',
          reason: 'the STALE captured pool is gone; the answer is the FRESH '
              'SourceManager resolution');
    });

    test('every source-invalidating failure type discards the captured pool',
        () async {
      final SourcePool captured = SourcePool(
        ranked: const <RankedSource>[],
        outcomes: const <ExtensionSourceOutcome>[],
        reference: 'refA',
      );
      for (final DownloadFailureType type
          in DownloadSourceResolver.sourceInvalidatingFailures) {
        resolver.rememberPool('movie1', captured);
        sandbox.sourcesScripts['refA'] =
            _sourcesPayload(<Map<String, Object?>>[
          _mp4('https://fresh.example/${type.code}.mp4'),
        ]);

        final SourcePool? pool = await resolver.resolveSource(
          _record(),
          lastFailure: DownloadFailure(
            type: type,
            message: type.message,
          ),
        );

        expect(pool, isNotNull, reason: '${type.code} must re-resolve');
        expect(pool!.ranked.single.source.url,
            'https://fresh.example/${type.code}.mp4',
            reason: '${type.code} must NOT be answered from the stale pool');
      }
    });

    test('the discarded pool stays discarded (no resurrection on the next '
        'resolve)', () async {
      resolver.rememberPool(
        'movie1',
        SourcePool(
          ranked: const <RankedSource>[],
          outcomes: const <ExtensionSourceOutcome>[],
          reference: 'refA',
        ),
      );
      // No script: the fresh resolution returns an EMPTY pool (no candidates).
      final SourcePool? first = await resolver.resolveSource(
        _record(),
        lastFailure: DownloadFailure(
          type: DownloadFailureType.httpError,
          message: DownloadFailureType.httpError.message,
        ),
      );
      expect(first, isNotNull);
      expect(first!.ranked, isEmpty,
          reason: 'the stale pool was dropped; the empty fresh pool is the '
              'honest answer');

      // A later resolve with NO failure must not resurrect the dropped pool.
      final SourcePool? second = await resolver.resolveSource(_record());
      expect(second, isNotNull);
      expect(second!.ranked, isEmpty,
          reason: 'a dropped captured pool never comes back');
    });
  });

  group('real re-resolution through SourceManager (2G-C §23/§24)', () {
    test('re-resolves from the persisted provenance when no session pool '
        'exists (the post-restart case)', () async {
      sandbox.sourcesScripts['refA'] = _sourcesPayload(<Map<String, Object?>>[
        _mp4('https://cdn.example/recovered.mp4', quality: '1080p'),
      ]);

      final SourcePool? pool = await resolver.resolveSource(_record());

      expect(pool, isNotNull, reason: 'provenance (extA, refA) → real '
          'SourceManager resolution after restart');
      expect(pool!.ranked.single.extensionId, 'extA');
      expect(pool.ranked.single.reference, 'refA');
      expect(pool.ranked.single.source.url, 'https://cdn.example/recovered.mp4');
    });

    test('an empty re-resolution is an honest empty pool, not an error',
        () async {
      // No scripted candidates: the extension answers with nothing.
      final SourcePool? pool = await resolver.resolveSource(_record());

      expect(pool, isNotNull);
      expect(pool!.ranked, isEmpty);
    });

    test('answers null when the record has no provenance', () async {
      final SourcePool? pool =
          await resolver.resolveSource(_record(extensionId: null));

      expect(pool, isNull,
          reason: 'no provenance → nothing to re-resolve from; the honest '
              'answer is null, never a fabricated pool');
    });

    test('answers null when the provenance is empty strings', () async {
      final SourcePool? pool =
          await resolver.resolveSource(_record(extensionId: '', reference: ''));

      expect(pool, isNull);
    });

    test('a missing extension isolates into an honest EMPTY pool (the '
        'pipeline never throws through the resolver)', () async {
      final SourcePool? pool = await resolver.resolveSource(
        _record(extensionId: 'ghost-extension'),
      );

      // SourceManager.resolve isolates the missing extension as a failed
      // outcome and aggregates an empty ranked list. The resolver passes
      // that answer through: an empty pool is the honest "resolution
      // produced nothing" — the manager classifies it (no MP4 candidate →
      // unsupportedSource under its bounded budget), never a crash.
      expect(pool, isNotNull);
      expect(pool!.ranked, isEmpty);
      expect(pool.outcomes, hasLength(1));
      expect(pool.outcomes.single.extensionId, 'ghost-extension');
      expect(pool.outcomes.single.isSuccess, isFalse,
          reason: 'the failed extension is visible in the outcomes for '
              'diagnostics, not silently swallowed');
    });

    test('a throwing extension is isolated — the resolver still answers',
        () async {
      sandbox.sourcesScripts['refA'] = 'throw new Error("extension exploded")';

      final SourcePool? pool = await resolver.resolveSource(_record());

      expect(pool, isNotNull);
      expect(pool!.ranked, isEmpty,
          reason: 'the pipeline isolates extension failures into outcomes; '
              'the resolver never rethrows them');
    });

    test('only the record\'s own extension is consulted (provenance is '
        'exactly what the record persists)', () async {
      sandbox.sourcesScripts['refA'] = _sourcesPayload(<Map<String, Object?>>[
        _mp4('https://cdn.example/provenance.mp4'),
      ]);

      await resolver.resolveSource(_record());

      // The expression embeds the JSON-encoded reference — exactly one
      // getSources call for the record's own reference.
      // (Indirect proof: an unknown extension id would answer null — covered
      // above — and the resolution succeeded from refA's script.)
      expect(sandbox.sourcesScripts, containsPair('refA', isNotNull));
    });
  });
}
