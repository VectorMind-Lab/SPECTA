import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/contract/extension_source.dart';
import 'package:specta/core/sources/source_manager.dart';
import 'package:specta/core/sources/source_models.dart';
import 'package:specta/core/sources/source_pool.dart';

import '../../support/discovery_test_harness.dart';

/// A scripted sandbox that also serves getSources/refreshSource calls.
class ScriptedSourcesSandbox extends ScriptedJsSandbox {
  /// Per-reference getSources responses (JS expression → payload).
  final Map<String, Object> sourcesScripts = <String, Object>{};

  /// Per-reference refreshSource responses.
  final Map<String, Object> refreshScripts = <String, Object>{};

  @override
  Future<String> evaluateAsync(String expression) async {
    if (expression.contains('.getSources(')) {
      final Object? scripted = _lookup(sourcesScripts, expression);
      if (scripted != null) {
        if (scripted is String) return scripted;
        throw scripted;
      }
    }
    if (expression.contains('.refreshSource(')) {
      final Object? scripted = _lookup(refreshScripts, expression);
      if (scripted != null) {
        if (scripted is String) return scripted;
        throw scripted;
      }
    }
    return super.evaluateAsync(expression);
  }

  /// Scripts are keyed by reference; the expression embeds the JSON-encoded
  /// reference, so match on the contained raw reference text.
  Object? _lookup(Map<String, Object> scripts, String expression) {
    for (final MapEntry<String, Object> entry in scripts.entries) {
      if (expression.contains('"${entry.key}"')) return entry.value;
    }
    return null;
  }
}

String _sourcesPayload(List<Map<String, Object?>> sources) =>
    jsonEncode(sources);

Map<String, Object?> _mp4(String url, {String? quality}) =>
    <String, Object?>{'url': url, 'type': 'mp4', 'quality': quality};

Map<String, Object?> _hls(String url, {String? quality, bool adaptive = false}) =>
    <String, Object?>{
      'url': url,
      'type': 'hls',
      'quality': quality,
      'isAdaptive': adaptive,
    };

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('specta_source_mgr');
    addTearDown(() {
      try {
        tempDir.delete(recursive: true);
      } on Object catch (_) {}
    });
  });

  DiscoveryTestHarness harness() => DiscoveryTestHarness(
        sandbox: ScriptedSourcesSandbox(),
      );

  group('SourceManager — resolution and provenance', () {
    test('valid candidates carry their extension provenance', () async {
      final DiscoveryTestHarness h = harness();
      await h.installExtension(tempDir, 'extA',
          capabilities: 'search,sources');
      (h.sandbox as ScriptedSourcesSandbox).sourcesScripts['refA'] =
          _sourcesPayload(<Map<String, Object?>>[
        _mp4('https://a/720', quality: '720p'),
      ]);

      final SourcePool pool = await SourceManager.resolve(
        reference: 'refA',
        extensions: <String, String>{'extA': 'refA'},
        manager: h.manager,
      );

      expect(pool.ranked, hasLength(1));
      expect(pool.ranked.single.extensionId, 'extA');
      expect(pool.ranked.single.reference, 'refA');
      expect(pool.selected, isNotNull);
      expect(pool.selected!.source.type, SourceType.mp4);
    });

    test('two extensions produce identifiable candidates with provenance',
        () async {
      final DiscoveryTestHarness h = harness();
      await h.installExtension(tempDir, 'extA',
          capabilities: 'search,sources');
      await h.installExtension(tempDir, 'extB',
          capabilities: 'search,sources');
      final ScriptedSourcesSandbox sandbox = h.sandbox as ScriptedSourcesSandbox;
      sandbox.sourcesScripts['refA'] = _sourcesPayload(<Map<String, Object?>>[
        _hls('https://a/1080', quality: '1080p'),
        _mp4('https://a/720', quality: '720p'),
      ]);
      sandbox.sourcesScripts['refB'] = _sourcesPayload(<Map<String, Object?>>[
        _mp4('https://b/1080', quality: '1080p'),
      ]);

      final SourcePool pool = await SourceManager.resolve(
        reference: 'movie-ref',
        extensions: <String, String>{'extA': 'refA', 'extB': 'refB'},
        manager: h.manager,
      );

      expect(pool.ranked, hasLength(3));
      expect(
        pool.ranked.map((RankedSource r) => r.extensionId).toSet(),
        <String>{'extA', 'extB'},
      );
      // Fallback order preserved: selected + 2 fallbacks.
      expect(pool.fallbacks, hasLength(2));
    });
  });

  group('SourceManager — failure isolation', () {
    test('one extension failing does not stop the healthy one', () async {
      final DiscoveryTestHarness h = harness();
      await h.installExtension(tempDir, 'extA',
          capabilities: 'search,sources');
      await h.installExtension(tempDir, 'extB',
          capabilities: 'search,sources');
      final ScriptedSourcesSandbox sandbox = h.sandbox as ScriptedSourcesSandbox;
      sandbox.sourcesScripts['refA'] = Exception('extA exploded');
      sandbox.sourcesScripts['refB'] = _sourcesPayload(<Map<String, Object?>>[
        _mp4('https://b/720', quality: '720p'),
      ]);

      final SourcePool pool = await SourceManager.resolve(
        reference: 'movie-ref',
        extensions: <String, String>{'extA': 'refA', 'extB': 'refB'},
        manager: h.manager,
      );

      expect(pool.ranked, hasLength(1));
      expect(pool.ranked.single.extensionId, 'extB');
      expect(pool.outcomes.where((ExtensionSourceOutcome o) => o.isFailed),
          hasLength(1));
    });

    test('a timeout on one extension is isolated as data', () async {
      final DiscoveryTestHarness h = harness();
      await h.installExtension(tempDir, 'extA',
          capabilities: 'search,sources');
      await h.installExtension(tempDir, 'extB',
          capabilities: 'search,sources');
      final ScriptedSourcesSandbox sandbox = h.sandbox as ScriptedSourcesSandbox;
      // extA hangs past the coordinator timeout on its call; extB answers.
      sandbox.sourcesScripts['refB'] = _sourcesPayload(<Map<String, Object?>>[
        _mp4('https://b/720', quality: '720p'),
      ]);

      final Future<SourcePool> pending = SourceManager.resolve(
        reference: 'movie-ref',
        extensions: <String, String>{'extA': 'refA', 'extB': 'refB'},
        manager: h.manager,
        perExtensionTimeoutOverride: const Duration(milliseconds: 80),
      );

      // Mark extA's call to hang after the timeout window by scripting a
      // payload that never arrives: override delay on the fake.
      h.sandbox.delay = const Duration(seconds: 5);
      final SourcePool pool = await pending;

      expect(pool.outcomes.any((ExtensionSourceOutcome o) => o.isFailed),
          isTrue);
      expect(pool.ranked, isNotEmpty);
    });

    test('an extension without the sources capability is skipped', () async {
      final DiscoveryTestHarness h = harness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,latest');

      final SourcePool pool = await SourceManager.resolve(
        reference: 'refA',
        extensions: <String, String>{'extA': 'refA'},
        manager: h.manager,
      );

      expect(pool.ranked, isEmpty);
      expect(pool.outcomes.single.isSkipped, isTrue);
      expect(pool.noExtensionAvailable, isTrue);
    });

    test('all-invalid candidates are an honest invalid outcome', () async {
      final DiscoveryTestHarness h = harness();
      await h.installExtension(tempDir, 'extA',
          capabilities: 'search,sources');
      (h.sandbox as ScriptedSourcesSandbox).sourcesScripts['refA'] =
          _sourcesPayload(<Map<String, Object?>>[
        _mp4('file:///etc/passwd'),
      ]);

      final SourcePool pool = await SourceManager.resolve(
        reference: 'refA',
        extensions: <String, String>{'extA': 'refA'},
        manager: h.manager,
      );

      expect(pool.ranked, isEmpty);
      expect(pool.outcomes.single.isInvalid, isTrue);
    });
  });

  group('SourceManager — deduplication and limits', () {
    test('same URL twice from ONE extension collapses to one candidate',
        () async {
      final DiscoveryTestHarness h = harness();
      await h.installExtension(tempDir, 'extA',
          capabilities: 'search,sources');
      (h.sandbox as ScriptedSourcesSandbox).sourcesScripts['refA'] =
          _sourcesPayload(<Map<String, Object?>>[
        _mp4('https://a/720', quality: '720p'),
        _mp4('https://a/720', quality: '720p'),
      ]);

      final SourcePool pool = await SourceManager.resolve(
        reference: 'refA',
        extensions: <String, String>{'extA': 'refA'},
        manager: h.manager,
      );

      expect(pool.ranked, hasLength(1));
    });

    test('same URL from DIFFERENT extensions keeps both (distinct CDN risk)',
        () async {
      final DiscoveryTestHarness h = harness();
      await h.installExtension(tempDir, 'extA',
          capabilities: 'search,sources');
      await h.installExtension(tempDir, 'extB',
          capabilities: 'search,sources');
      final ScriptedSourcesSandbox sandbox = h.sandbox as ScriptedSourcesSandbox;
      sandbox.sourcesScripts['refA'] = _sourcesPayload(<Map<String, Object?>>[
        _mp4('https://shared/720', quality: '720p'),
      ]);
      sandbox.sourcesScripts['refB'] = _sourcesPayload(<Map<String, Object?>>[
        _mp4('https://shared/720', quality: '720p'),
      ]);

      final SourcePool pool = await SourceManager.resolve(
        reference: 'movie-ref',
        extensions: <String, String>{'extA': 'refA', 'extB': 'refB'},
        manager: h.manager,
      );

      expect(pool.ranked, hasLength(2));
      expect(
        pool.ranked.map((RankedSource r) => r.extensionId).toSet(),
        <String>{'extA', 'extB'},
      );
    });

    test('an oversized response is capped at maxSourcesPerExtension',
        () async {
      final DiscoveryTestHarness h = harness();
      await h.installExtension(tempDir, 'extA',
          capabilities: 'search,sources');
      final List<Map<String, Object?>> flood = <Map<String, Object?>>[
        for (int i = 0; i < 5000; i++)
          _mp4('https://a/item/$i', quality: '720p'),
      ];
      (h.sandbox as ScriptedSourcesSandbox).sourcesScripts['refA'] =
          _sourcesPayload(flood);

      final SourcePool pool = await SourceManager.resolve(
        reference: 'refA',
        extensions: <String, String>{'extA': 'refA'},
        manager: h.manager,
      );

      expect(
        pool.ranked.length,
        SourceManager.maxSourcesPerExtension,
      );
    });
  });

  group('SourceManager — refresh', () {
    test('refresh returns a validated candidate', () async {
      final DiscoveryTestHarness h = harness();
      await h.installExtension(tempDir, 'extA',
          capabilities: 'search,sources');
      (h.sandbox as ScriptedSourcesSandbox).refreshScripts['refA'] =
          jsonEncode(_mp4('https://a/refreshed', quality: '1080p'));

      final ExtensionSource? refreshed = await SourceManager.refresh(
        extensionId: 'extA',
        reference: 'refA',
        manager: h.manager,
      );

      expect(refreshed, isNotNull);
      expect(refreshed!.url, 'https://a/refreshed');
    });

    test('refresh failure is an honest null, not a throw', () async {
      final DiscoveryTestHarness h = harness();
      await h.installExtension(tempDir, 'extA',
          capabilities: 'search,sources');
      (h.sandbox as ScriptedSourcesSandbox).refreshScripts['refA'] =
          Exception('refresh blew up');

      final ExtensionSource? refreshed = await SourceManager.refresh(
        extensionId: 'extA',
        reference: 'refA',
        manager: h.manager,
      );

      expect(refreshed, isNull);
    });

    test('refresh without the sources capability is an honest null', () async {
      final DiscoveryTestHarness h = harness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,latest');

      final ExtensionSource? refreshed = await SourceManager.refresh(
        extensionId: 'extA',
        reference: 'refA',
        manager: h.manager,
      );

      expect(refreshed, isNull);
    });
  });

  group('SourceManager — selection', () {
    test('pool exposes selected source and fallback order', () async {
      final DiscoveryTestHarness h = harness();
      await h.installExtension(tempDir, 'extA',
          capabilities: 'search,sources');
      (h.sandbox as ScriptedSourcesSandbox).sourcesScripts['refA'] =
          _sourcesPayload(<Map<String, Object?>>[
        _mp4('https://a/480', quality: '480p'),
        _mp4('https://a/1080', quality: '1080p'),
        _mp4('https://a/720', quality: '720p'),
      ]);

      final SourcePool pool = await SourceManager.resolve(
        reference: 'refA',
        extensions: <String, String>{'extA': 'refA'},
        manager: h.manager,
        preference: QualityPreference.p720,
      );

      expect(pool.selected!.source.url, 'https://a/720');
      expect(
        pool.fallbacks.map((RankedSource r) => r.source.url).toSet(),
        <String>{'https://a/1080', 'https://a/480'},
      );
    });
  });
}
