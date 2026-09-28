import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/identity/source_node.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_providers.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/in_memory_extension_registry.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';
import 'package:specta/features/extensions/source_health_view.dart';
import 'package:specta/features/extensions/state/extensions_state.dart';

import '../../support/fake_js_sandbox.dart';

/// Slice 7: the Source Health screen shows recorded facts and invents nothing.
///
/// The percentages are asserted against the mapping table, and the screen is
/// checked for the two leaks that matter: a provider-chosen name and a path.
void main() {
  late Directory dir;
  late InMemoryExtensionRegistry registry;
  late ExtensionManager manager;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('specta_health_view');
    registry = InMemoryExtensionRegistry();
    manager = ExtensionManager(
      registry: registry,
      runtimeApi: _NoopRuntimeApi(),
      sandboxFactory: FakeJsSandbox.new,
    );
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on Object catch (_) {
      // Best-effort cleanup.
    }
  });

  Future<void> seed({
    required String id,
    required String name,
    required SourceNode node,
    bool enabled = true,
    int apiVersion = 2,
    DateTime? lastSuccessAt,
  }) async {
    final DateTime now = DateTime.utc(2026, 1, 1);
    await registry.install(
      ExtensionRecord(
        id: id,
        name: name,
        version: '4.2.0',
        author: 'PirateSoftware',
        apiVersion: apiVersion,
        contentType: 'movies_series',
        trustLevel: TrustLevel.unverified,
        enabled: enabled,
        filePath: '${dir.path}\\secret.js',
        installedAt: now,
        updatedAt: now,
        node: node,
        lastSuccessAt: lastSuccessAt,
      ),
    );
  }

  Future<ProviderContainer> pumpView(WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        extensionManagerProvider.overrideWith((Ref ref) => manager),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SourceHealthView())),
      ),
    );
    final Stopwatch watch = Stopwatch()..start();
    while (container.read(extensionsProvider).items.isEmpty &&
        watch.elapsed < const Duration(seconds: 8)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return container;
  }

  String renderedText(WidgetTester tester) {
    final StringBuffer buffer = StringBuffer();
    for (final Element element in find.byType(Text).evaluate()) {
      buffer.write('${(element.widget as Text).data ?? ''} ');
    }
    return buffer.toString();
  }

  const SourceNode node1 = SourceNode(space: SourceNodeSpace.user, index: 1);
  const SourceNode node2 = SourceNode(space: SourceNodeSpace.user, index: 2);

  group('no figure is invented', () {
    testWidgets('a source never used reads "No data yet", not a number', (
      WidgetTester tester,
    ) async {
      // Healthy and enabled, with zero failures - but nothing has ever actually
      // succeeded. A confident 100% here would be a fabricated measurement.
      await seed(
        id: 'com.leak.fresh',
        name: 'ZoroAnime',
        node: node1,
      );
      await pumpView(tester);

      expect(find.text('No data yet'), findsOneWidget);
      expect(find.text('100%'), findsNothing);
      expect(
        renderedText(tester),
        isNot(contains('100%')),
        reason: 'nothing has been recorded, so no percentage may appear',
      );
    });

    testWidgets('a source with a real success reads 100%', (
      WidgetTester tester,
    ) async {
      await seed(
        id: 'com.leak.working',
        name: 'AnimeKai',
        node: node1,
        lastSuccessAt: DateTime.utc(2026, 1, 2, 3, 4),
      );
      await pumpView(tester);

      expect(find.text('100%'), findsOneWidget);
      expect(find.text('No data yet'), findsNothing);
      expect(find.textContaining('last worked'), findsOneWidget);
    });
  });

  group('every state is labelled from the real facts', () {
    testWidgets('a disabled node reads Off even if it had been working', (
      WidgetTester tester,
    ) async {
      // Enabled=false wins over a recorded success: the source is not serving
      // anything now, and reporting 100% would misdescribe that.
      await seed(
        id: 'com.leak.off',
        name: 'Hianime',
        node: node1,
        enabled: false,
        lastSuccessAt: DateTime.utc(2026, 1, 2),
      );
      await pumpView(tester);

      expect(find.text('0%'), findsOneWidget);
      expect(find.text('100%'), findsNothing);
      expect(find.text('Off'), findsWidgets);
    });

    testWidgets('an unsupported node reads 0%', (WidgetTester tester) async {
      // An API version this build cannot run.
      await seed(
        id: 'com.leak.future',
        name: 'FutureSite',
        node: node1,
        apiVersion: 99,
        lastSuccessAt: DateTime.utc(2026, 1, 2),
      );
      await pumpView(tester);

      expect(find.text('0%'), findsOneWidget);
      expect(find.textContaining('Not supported'), findsOneWidget);
    });
  });

  group('no leak reaches the screen', () {
    testWidgets('no site name and no path, ever', (WidgetTester tester) async {
      await seed(
        id: 'com.leak.one',
        name: 'ZoroAnime',
        node: node1,
        lastSuccessAt: DateTime.utc(2026, 1, 2),
      );
      await seed(
        id: 'com.leak.two',
        name: 'AnimeKai',
        node: node2,
      );
      await pumpView(tester);

      final String text = renderedText(tester);
      expect(text, isNot(contains('ZoroAnime')));
      expect(text, isNot(contains('AnimeKai')));
      expect(text, isNot(contains('PirateSoftware')), reason: 'no author');
      expect(text, isNot(contains('com.leak')), reason: 'no id');
      expect(text, isNot(contains('secret.js')), reason: 'no path');
      expect(text, isNot(contains(dir.path)));

      // It is identified by the node labels SPECTA owns.
      expect(find.text('Node 1'), findsOneWidget);
      expect(find.text('Node 2'), findsOneWidget);
    });
  });

  group('it reports only what exists', () {
    testWidgets('an empty registry says so rather than showing a figure', (
      WidgetTester tester,
    ) async {
      // Nothing seeded. `pumpView` returns as soon as the state settles; it must
      // not be allowed to invent a row to report on.
      final ProviderContainer container = await pumpView(tester);

      expect(container.read(extensionsProvider).items, isEmpty);
      expect(find.textContaining('No sources are installed'), findsOneWidget);
      expect(find.text('No data yet'), findsNothing);
      expect(find.text('100%'), findsNothing);
    });
  });
}

/// Minimal host API; this suite never performs a network request.
class _NoopRuntimeApi implements ExtensionRuntimeApi {
  @override
  Future<ExtensionResponse> request(ExtensionRequest request) async {
    return const ExtensionResponse(status: 200, ok: true, body: '{}');
  }

  @override
  void log(ExtensionLogLevel level, String message) {}
}
