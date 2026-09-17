import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/sources/source_manager.dart';
import 'package:specta/features/playback/source_session_state.dart';

import '../../support/discovery_test_harness.dart'
    show DiscoveryTestHarness, ScriptedJsSandbox;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('specta_source_session');
    addTearDown(() {
      try {
        tempDir.delete(recursive: true);
      } on Object catch (_) {}
    });
  });

  ProviderContainer buildContainer(DiscoveryTestHarness h) {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        sourceServiceProvider.overrideWith(
          (Ref ref) => SourceService(manager: h.manager),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('starts idle', () {
    final ProviderContainer container = buildContainer(DiscoveryTestHarness());
    expect(container.read(sourceSessionProvider).status,
        SourceSessionStatus.idle);
  });

  test('resolve with candidates ends ready with a selected source', () async {
    final DiscoveryTestHarness h = DiscoveryTestHarness(
      sandbox: _Scripted(),
    );
    await h.installExtension(tempDir, 'extA', capabilities: 'search,sources');
    (_scripted(h)).sourcesScripts['refA'] = jsonEncode(<Object?>[
      <String, Object?>{'url': 'https://a/720', 'type': 'mp4', 'quality': '720p'},
    ]);

    final ProviderContainer container = buildContainer(h);
    await container.read(sourceSessionProvider.notifier).resolve(
          reference: 'movie-ref',
          extensions: <String, String>{'extA': 'refA'},
        );

    final SourceSessionState state = container.read(sourceSessionProvider);
    expect(state.status, SourceSessionStatus.ready);
    expect(state.pool!.selected, isNotNull);
    expect(state.pool!.selected!.source.url, 'https://a/720');
    expect(state.pool!.fallbacks, isEmpty);
  });

  test('all extensions failing ends in failure', () async {
    final DiscoveryTestHarness h = DiscoveryTestHarness(
      sandbox: _Scripted(),
    );
    await h.installExtension(tempDir, 'extA', capabilities: 'search,sources');
    _scripted(h).sourcesScripts['refA'] = Exception('down');

    final ProviderContainer container = buildContainer(h);
    await container.read(sourceSessionProvider.notifier).resolve(
          reference: 'movie-ref',
          extensions: <String, String>{'extA': 'refA'},
        );

    expect(container.read(sourceSessionProvider).status,
        SourceSessionStatus.failure);
  });

  test('a stale slow resolve cannot overwrite a newer resolve', () async {
    final DiscoveryTestHarness h = DiscoveryTestHarness(
      sandbox: _Scripted(),
    );
    await h.installExtension(tempDir, 'extA', capabilities: 'search,sources');
    await h.installExtension(tempDir, 'extB', capabilities: 'search,sources');
    final _Scripted sandbox = _scripted(h);

    // Episode 1 resolves slowly; Episode 2 resolves fast.
    sandbox.sourcesScripts['ep1'] = jsonEncode(<Object?>[
      <String, Object?>{'url': 'https://a/ep1', 'type': 'mp4'},
    ]);
    sandbox.sourcesScripts['ep2'] = jsonEncode(<Object?>[
      <String, Object?>{'url': 'https://a/ep2', 'type': 'mp4'},
    ]);

    final ProviderContainer container = buildContainer(h);
    final SourceSessionNotifier notifier =
        container.read(sourceSessionProvider.notifier);

    h.sandbox.delay = const Duration(milliseconds: 200);
    final Future<void> slow =
        notifier.resolve(reference: 'ep1', extensions: <String, String>{'extA': 'ep1'});
    await Future<void>.delayed(const Duration(milliseconds: 30));
    h.sandbox.delay = Duration.zero;
    await notifier.resolve(
        reference: 'ep2', extensions: <String, String>{'extB': 'ep2'});
    await slow; // lands late — must be rejected

    final SourceSessionState state = container.read(sourceSessionProvider);
    expect(state.status, SourceSessionStatus.ready);
    expect(state.pool!.selected!.source.url, 'https://a/ep2');
  });

  test('reset returns to idle and rejects in-flight resolves', () async {
    final DiscoveryTestHarness h = DiscoveryTestHarness(
      sandbox: _Scripted(),
    );
    await h.installExtension(tempDir, 'extA', capabilities: 'search,sources');
    _scripted(h).sourcesScripts['refA'] = jsonEncode(<Object?>[
      <String, Object?>{'url': 'https://a/720', 'type': 'mp4'},
    ]);

    final ProviderContainer container = buildContainer(h);
    final SourceSessionNotifier notifier =
        container.read(sourceSessionProvider.notifier);

    h.sandbox.delay = const Duration(milliseconds: 150);
    final Future<void> pending =
        notifier.resolve(reference: 'refA', extensions: <String, String>{'extA': 'refA'});
    await Future<void>.delayed(const Duration(milliseconds: 30));

    notifier.reset();
    expect(container.read(sourceSessionProvider).status,
        SourceSessionStatus.idle);

    await pending;
    expect(container.read(sourceSessionProvider).status,
        SourceSessionStatus.idle);
  });
}

class _Scripted extends ScriptedJsSandbox {
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

  /// Per-reference getSources payloads.
  final Map<String, Object> sourcesScripts = <String, Object>{};
}

_Scripted _scripted(DiscoveryTestHarness h) => h.sandbox as _Scripted;
