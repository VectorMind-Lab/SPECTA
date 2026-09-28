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
import 'package:specta/features/extensions/extensions_view.dart';
import 'package:specta/features/extensions/state/extensions_state.dart';
import 'package:specta/ui/widgets/specta_developer_dot.dart';

import '../../support/fake_js_sandbox.dart';

/// Slice 5: the installed-source card shows the NODE LABEL and nothing else.
///
/// These run against the REAL `ExtensionsView` over a real manager, so what is
/// asserted is the shipped card — not a copy of it that could drift.
///
/// Every fixture is named with an unmissable streaming-site name, so a leak
/// cannot hide behind a fuzzy match.
void main() {
  late Directory dir;
  late InMemoryExtensionRegistry registry;
  late ExtensionManager manager;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('specta_node_label');
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

  Future<void> install({
    required String id,
    required String name,
    required String author,
    required SourceNode node,
    TrustLevel trust = TrustLevel.unverified,
    bool locked = false,
  }) async {
    final DateTime now = DateTime.utc(2026, 1, 1);
    await registry.install(
      ExtensionRecord(
        id: id,
        name: name,
        version: '4.2.0',
        author: author,
        apiVersion: 2,
        contentType: 'movies_series',
        trustLevel: trust,
        enabled: true,
        // A realistic app-private path: it must never surface in the UI.
        filePath: '${dir.path}${'\\'}secret.js',
        installedAt: now,
        updatedAt: now,
        node: node,
        nodeLocked: locked,
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
        child: const MaterialApp(home: Scaffold(body: ExtensionsView())),
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
    // The loop exits on the same frame the state lands, so the rebuild it
    // schedules has not been drawn yet. Pump until the tree catches up.
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return container;
  }

  /// Every string rendered anywhere in the current tree.
  ///
  /// A finder can assert a string is PRESENT; it cannot assert one is ABSENT.
  /// Walking the tree is the only way to prove a site name is not on screen.
  String renderedText(WidgetTester tester) {
    final StringBuffer buffer = StringBuffer();
    for (final Element element in find.byType(Text).evaluate()) {
      buffer.write('${(element.widget as Text).data ?? ''} ');
    }
    for (final Element element in find.byType(Tooltip).evaluate()) {
      buffer.write('${(element.widget as Tooltip).message ?? ''} ');
    }
    return buffer.toString();
  }

  const SourceNode node0 = SourceNode(space: SourceNodeSpace.official, index: 0);
  const SourceNode nodeA = SourceNode(space: SourceNodeSpace.official, index: 1);
  const SourceNode node1 = SourceNode(space: SourceNodeSpace.user, index: 1);

  group('the card shows the node label and nothing else', () {
    testWidgets('a user source renders only "Node 1"', (
      WidgetTester tester,
    ) async {
      await install(
        id: 'com.leak.sites',
        name: 'ZoroAnime',
        author: 'PirateSoftware',
        node: node1,
      );
      await pumpView(tester);

      expect(find.text('Node 1'), findsOneWidget);
      final String text = renderedText(tester);
      expect(text, isNot(contains('ZoroAnime')), reason: 'no site name');
      expect(text, isNot(contains('PirateSoftware')), reason: 'no author');
      expect(text, isNot(contains('com.leak.sites')), reason: 'no id');
      expect(text, isNot(contains('4.2.0')), reason: 'no version');
    });

    testWidgets('official sources render "Node 0" and "Node A"', (
      WidgetTester tester,
    ) async {
      await install(
        id: 'com.leak.core',
        name: 'AnimeKai',
        author: 'ShadowLabs',
        node: node0,
        locked: true,
      );
      await install(
        id: 'com.leak.alt',
        name: 'Hianime',
        author: 'RogueTeam',
        node: nodeA,
        trust: TrustLevel.official,
      );
      await pumpView(tester);

      expect(find.text('Node 0'), findsOneWidget);
      expect(find.text('Node A'), findsOneWidget);
      final String text = renderedText(tester);
      expect(text, isNot(contains('AnimeKai')));
      expect(text, isNot(contains('Hianime')));
      expect(text, isNot(contains('ShadowLabs')));
    });

    testWidgets('no filesystem path reaches the card', (
      WidgetTester tester,
    ) async {
      await install(
        id: 'com.leak.path',
        name: 'SecretName',
        author: 'Someone',
        node: node1,
      );
      await pumpView(tester);

      final String text = renderedText(tester);
      expect(text, isNot(contains('secret.js')));
      expect(text, isNot(contains(dir.path)));
    });
  });

  group('the green dot is provenance, not identity', () {
    testWidgets('shows for the signed source only, in the same list', (
      WidgetTester tester,
    ) async {
      await install(
        id: 'com.leak.signed',
        name: 'SignedOne',
        author: 'A',
        node: node1,
        trust: TrustLevel.official,
      );
      await install(
        id: 'com.leak.unsigned',
        name: 'UnsignedOne',
        author: 'B',
        node: nodeA,
      );
      await pumpView(tester);

      // Both coexist in ONE list; only the verified one carries the dot.
      expect(find.byType(SpectaDeveloperDot), findsOneWidget);
      expect(find.text('Node 1'), findsOneWidget);
      expect(find.text('Node A'), findsOneWidget);
    });

    testWidgets('a signed USER source keeps its dot and stays a user node', (
      WidgetTester tester,
    ) async {
      // Q1: a signature proves provenance, NOT that a node is official. A file
      // the user brought themselves keeps the dot and is still Node 1.
      await install(
        id: 'com.leak.signeduser',
        name: 'SignedButUser',
        author: 'C',
        node: node1,
        trust: TrustLevel.official,
      );
      await pumpView(tester);

      expect(find.byType(SpectaDeveloperDot), findsOneWidget);
      expect(find.text('Node 1'), findsOneWidget);
      expect(find.text('Node A'), findsNothing);
    });
  });

  group('the details sheet', () {
    /// Opens the details sheet from the card's trailing overflow menu.
    ///
    /// Slice 1 moved Details out of the card face and into the overflow menu to
    /// keep the card two rows. The sheet's contents and purpose are unchanged -
    /// this is still where the source's own name lives, one tap away.
    Future<void> openDetails(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('contains the name, version, author and id', (
      WidgetTester tester,
    ) async {
      await install(
        id: 'com.leak.details',
        name: 'ZoroAnime',
        author: 'PirateSoftware',
        node: node1,
      );
      await pumpView(tester);
      await openDetails(tester);

      // Titled by the node, so even the modal heading is name-free...
      expect(find.text('Node 1'), findsWidgets);
      // ...and every removed fact is still one tap away. Nothing is hidden.
      expect(find.text('ZoroAnime'), findsOneWidget);
      expect(find.text('PirateSoftware'), findsOneWidget);
      expect(find.text('4.2.0'), findsOneWidget);
      expect(find.text('com.leak.details'), findsOneWidget);
    });

    testWidgets('never shows the filesystem path', (WidgetTester tester) async {
      await install(
        id: 'com.leak.details',
        name: 'ZoroAnime',
        author: 'PirateSoftware',
        node: node1,
      );
      await pumpView(tester);
      await openDetails(tester);

      final String text = renderedText(tester);
      expect(text, isNot(contains('secret.js')));
      expect(text, isNot(contains(dir.path)));
    });

    testWidgets('states that a locked node is not removable', (
      WidgetTester tester,
    ) async {
      await install(
        id: 'com.leak.core',
        name: 'AnimeKai',
        author: 'A',
        node: node0,
        locked: true,
      );
      await pumpView(tester);
      await openDetails(tester);

      expect(find.textContaining('core source'), findsOneWidget);
    });
  });

  group('the delete control respects Node 0', () {
    // Slice 1: the delete affordance is now an entry in the card's trailing
    // overflow menu rather than a delete IconButton on the card face. These
    // still assert the real invariant - Node 0 cannot be deleted, a user node
    // can - via the control that now carries it.
    testWidgets('is disabled and shows a lock for a locked node', (
      WidgetTester tester,
    ) async {
      await install(
        id: 'com.leak.core',
        name: 'AnimeKai',
        author: 'A',
        node: node0,
        locked: true,
      );
      await pumpView(tester);

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The reason is stated rather than the control silently vanishing.
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      final PopupMenuItem<String> item = tester.widget<PopupMenuItem<String>>(
        find.widgetWithText(
          PopupMenuItem<String>,
          'Node 0 is the core source and cannot be removed',
        ),
      );
      expect(item.enabled, isFalse, reason: 'Node 0 must not be deletable');
    });

    testWidgets('is enabled for a user node', (WidgetTester tester) async {
      await install(id: 'com.leak.user', name: 'A', author: 'B', node: node1);
      await pumpView(tester);

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final PopupMenuItem<String> item = tester.widget<PopupMenuItem<String>>(
        find.widgetWithText(PopupMenuItem<String>, 'Remove source'),
      );
      expect(item.enabled, isTrue);
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
