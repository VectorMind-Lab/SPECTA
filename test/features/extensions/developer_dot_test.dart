import 'dart:io';

import 'package:flutter/material.dart';
// SemanticsNode / SemanticsHandle are not re-exported by material.dart.
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:specta/app/theme/specta_colors.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_providers.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/in_memory_extension_registry.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';
import 'package:specta/features/extensions/extensions_view.dart';
import 'package:specta/features/extensions/state/extensions_state.dart';
import 'package:specta/ui/widgets/specta_developer_dot.dart';

import '../../support/fake_js_sandbox.dart';

/// The developer dot is a TRUST mark, so the only thing worth testing is the
/// gate: it must appear for a signature-verified extension and for nothing
/// else. A regression here would not crash anything — it would quietly tell the
/// user that code they installed themselves came from SPECTA.
void main() {
  late Directory dir;
  late InMemoryExtensionRegistry registry;
  late ExtensionManager manager;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('specta_dev_dot');
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

  /// Persists one installed extension directly into the authoritative registry.
  ///
  /// Seeding the registry (rather than driving an install) is deliberate: the
  /// point of these tests is how the list RENDERS a trust level, and going
  /// through the installer would only re-test signature classification, which
  /// `extension_manager_signing_test.dart` already covers with a real key.
  Future<void> seed(
    WidgetTester tester, {
    required String id,
    required String name,
    required TrustLevel trust,
  }) async {
    final File file = File('${dir.path}/$id.js');
    // A widget test runs inside a FakeAsync zone, where a real filesystem
    // await never completes — it would hang the test rather than fail it.
    // runAsync steps outside that zone for the duration, which is the same
    // pattern extensions_view_test.dart uses for its file I/O.
    await tester.runAsync(() => file.writeAsString('// fixture'));
    await registry.install(
      ExtensionRecord(
        id: id,
        name: name,
        version: '1.0.0',
        author: 'SPECTA Tests',
        apiVersion: 2,
        contentType: 'movie',
        signature: trust == TrustLevel.official ? 'test-signature' : null,
        trustLevel: trust,
        enabled: true,
        filePath: file.path,
        installedAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
  }

  Future<ProviderContainer> pumpView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        extensionManagerProvider.overrideWith((Ref ref) => manager),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ExtensionsView())),
      ),
    );
    return container;
  }

  /// Lets real asynchronous work finish (registry reads), then flushes frames.
  Future<void> settle(
    WidgetTester tester,
    ProviderContainer container,
    bool Function() done,
  ) async {
    final Stopwatch watch = Stopwatch()..start();
    while (!done() && watch.elapsed < const Duration(seconds: 8)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('a verified extension carries the dot and an unverified one does '
      'not', (WidgetTester tester) async {
    await seed(
      tester,
      id: 'com.test.dev',
      name: 'Developer Extension',
      trust: TrustLevel.official,
    );
    await seed(
      tester,
      id: 'com.test.user',
      name: 'Personal Extension',
      trust: TrustLevel.unverified,
    );

    final ProviderContainer container = await pumpView(tester);
    await settle(
      tester,
      container,
      () => container.read(extensionsProvider).items.length == 2,
    );

    // Slice 5: the card is identified by its node label, not the source's own
    // name. The two nodes are the verified one and the personal one, in node
    // order.
    expect(find.text('Node 1'), findsOneWidget);
    expect(find.text('Node 2'), findsOneWidget);
    expect(find.text('Developer Extension'), findsNothing);
    expect(find.text('Personal Extension'), findsNothing);

    // Exactly one dot across the whole screen: the verified extension's. The
    // personal one is installed, enabled and healthy — it is simply not
    // SPECTA's, and that is the only thing the dot reports.
    expect(find.byType(SpectaDeveloperDot), findsOneWidget);

    // And it sits on the verified extension's card, not the personal one. The
    // verified source was seeded first, so it holds the lower node index.
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Node 1'),
          matching: find.byType(Row),
        ),
        matching: find.byType(SpectaDeveloperDot),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Node 2'),
          matching: find.byType(Row),
        ),
        matching: find.byType(SpectaDeveloperDot),
      ),
      findsNothing,
      reason: 'the personal node must carry no dot',
    );
  });

  testWidgets('the dot is absent when nothing installed is verified', (
    WidgetTester tester,
  ) async {
    await seed(
      tester,
      id: 'com.test.user',
      name: 'Personal Extension',
      trust: TrustLevel.unverified,
    );

    final ProviderContainer container = await pumpView(tester);
    await settle(
      tester,
      container,
      () => container.read(extensionsProvider).items.length == 1,
    );

    expect(find.text('Node 1'), findsOneWidget);
    expect(find.text('Personal Extension'), findsNothing);
    expect(find.byType(SpectaDeveloperDot), findsNothing);
  });

  group('SpectaDeveloperDot', () {
    testWidgets('is a small green circle, and nothing else', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: SpectaDeveloperDot(size: 7))),
        ),
      );

      // No text anywhere: the mark must never explain itself.
      expect(find.byType(Text), findsNothing);

      final Container container = tester.widget<Container>(
        find.descendant(
          of: find.byType(SpectaDeveloperDot),
          matching: find.byType(Container),
        ),
      );
      final BoxDecoration decoration = container.decoration! as BoxDecoration;

      expect(decoration.shape, BoxShape.circle);
      expect(
        decoration.color,
        SpectaColors.success,
        reason: 'the mark reuses the existing success colour, not a new one',
      );
      expect(container.constraints!.maxWidth, 7);
    });

    testWidgets('is hidden from the accessibility tree', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: SpectaDeveloperDot())),
        ),
      );

      // The dot is a private signal, so a screen reader must not announce it —
      // and equally must not announce a label we do not want to explain.
      final SemanticsHandle handle = tester.ensureSemantics();
      final SemanticsNode node = tester.getSemantics(
        find.byType(SpectaDeveloperDot),
      );
      expect(node.label, isEmpty);
      handle.dispose();

      expect(
        find.descendant(
          of: find.byType(SpectaDeveloperDot),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
    });
  });
}

class _NoopRuntimeApi implements ExtensionRuntimeApi {
  @override
  Future<ExtensionResponse> request(ExtensionRequest request) async =>
      const ExtensionResponse(status: 200, ok: true, body: '{}');

  @override
  void log(ExtensionLogLevel level, String message) {}
}
