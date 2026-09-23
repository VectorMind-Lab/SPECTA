import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_providers.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/in_memory_extension_registry.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';
import 'package:specta/features/extensions/extensions_view.dart';
import 'package:specta/features/extensions/state/extensions_state.dart';

import '../../support/fake_js_sandbox.dart';

/// Widget coverage for the extension-management surface: it renders persisted
/// state, and its controls drive the real lifecycle service.

void main() {
  late Directory dir;
  late InMemoryExtensionRegistry registry;
  late ExtensionManager manager;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('specta_ext_view');
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
    return container;
  }

  /// Lets real asynchronous work (file I/O, registry reads) finish, then
  /// flushes the resulting frames.
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
    await tester.pump();
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('an empty registry shows the install prompt', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await pumpView(tester);
    await settle(
      tester,
      container,
      () => container.read(extensionsProvider).status == ExtensionsStatus.ready,
    );

    expect(find.text('Extensions'), findsOneWidget);
    expect(find.text('0 installed'), findsOneWidget);
    expect(find.textContaining('No extensions are installed'), findsOneWidget);
    expect(find.text('Install extension'), findsOneWidget);
  });

  testWidgets('installing a file adds it to the list as Unverified', (
    WidgetTester tester,
  ) async {
    final File file = File('${dir.path}/view.js');
    await tester.runAsync(
      () => file.writeAsString(_source(id: 'com.test.view', name: 'View Fixture')),
    );

    final ProviderContainer container = await pumpView(tester);
    await settle(
      tester,
      container,
      () => container.read(extensionsProvider).status == ExtensionsStatus.ready,
    );

    await tester.tap(find.text('Install extension'));
    await openDialog(tester);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), file.path);
    await tester.tap(find.widgetWithText(TextButton, 'Install'));
    await tester.pump();

    await settle(
      tester,
      container,
      () => container.read(extensionsProvider).items.isNotEmpty,
    );

    expect(find.text('View Fixture'), findsOneWidget);
    expect(find.text('Unverified'), findsOneWidget);
    expect(find.text('1 installed'), findsOneWidget);
  });

  testWidgets('a rejected file surfaces an error and lists nothing', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await pumpView(tester);
    await settle(
      tester,
      container,
      () => container.read(extensionsProvider).status == ExtensionsStatus.ready,
    );

    await tester.tap(find.text('Install extension'));
    await openDialog(tester);
    await tester.enterText(
      find.byType(TextField),
      '${dir.path}/does-not-exist.js',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Install'));
    await tester.pump();

    await settle(
      tester,
      container,
      () => container.read(extensionsProvider).errorMessage != null,
    );

    expect(find.textContaining('Cannot read extension file'), findsOneWidget);
    expect(find.textContaining('No extensions are installed'), findsOneWidget);
  });

  testWidgets('the switch disables an installed extension and it persists', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime.now().toUtc();
    await registry.install(
      ExtensionRecord(
        id: 'com.test.toggle',
        name: 'Toggle Me',
        version: '1.0.0',
        author: 'SPECTA Tests',
        apiVersion: 2,
        contentType: 'movie',
        signature: null,
        trustLevel: TrustLevel.unverified,
        enabled: true,
        filePath: '${dir.path}/toggle.js',
        installedAt: now,
        updatedAt: now,
      ),
    );

    final ProviderContainer container = await pumpView(tester);
    await settle(
      tester,
      container,
      () => container.read(extensionsProvider).items.isNotEmpty,
    );
    expect(find.text('Toggle Me'), findsOneWidget);
    expect(find.text('Enabled'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await settle(
      tester,
      container,
      () => !container.read(extensionsProvider).items.single.enabled,
    );

    expect(find.text('Disabled'), findsWidgets);
    expect((await registry.getById('com.test.toggle'))!.enabled, isFalse);
  });

  testWidgets('removing an extension asks for confirmation and then removes it', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime.now().toUtc();
    await registry.install(
      ExtensionRecord(
        id: 'com.test.remove',
        name: 'Remove Me',
        version: '1.0.0',
        author: 'SPECTA Tests',
        apiVersion: 2,
        contentType: 'movie',
        signature: null,
        trustLevel: TrustLevel.unverified,
        enabled: true,
        filePath: '${dir.path}/remove.js',
        installedAt: now,
        updatedAt: now,
      ),
    );

    final ProviderContainer container = await pumpView(tester);
    await settle(
      tester,
      container,
      () => container.read(extensionsProvider).items.isNotEmpty,
    );

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await openDialog(tester);
    expect(find.text('Remove extension'), findsOneWidget);

    // Cancelling leaves the extension installed.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await openDialog(tester);
    expect(container.read(extensionsProvider).items, hasLength(1));

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await openDialog(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pump();

    await settle(
      tester,
      container,
      () => container.read(extensionsProvider).items.isEmpty,
    );

    expect(find.textContaining('No extensions are installed'), findsOneWidget);
    expect(await registry.getById('com.test.remove'), isNull);
  });
}

String _source({
  required String id,
  String name = 'Fixture',
  String version = '1.0.0',
}) {
  return '// ==SpectaExtension==\n'
      '// @id $id\n'
      '// @name $name\n'
      '// @version $version\n'
      '// @author SPECTA Tests\n'
      '// @apiVersion 2\n'
      '// @type movie\n'
      '// @capabilities search\n'
      '// ==/SpectaExtension==\n'
      'class Extension extends SpectaExtension {}';
}

class _NoopRuntimeApi implements ExtensionRuntimeApi {
  @override
  Future<ExtensionResponse> request(ExtensionRequest request) async =>
      const ExtensionResponse(status: 200, ok: true, body: '{}');

  @override
  void log(ExtensionLogLevel level, String message) {}
}
