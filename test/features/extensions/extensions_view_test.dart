import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/app/platform/file_picker.dart';
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

  Future<ProviderContainer> pumpView(
    WidgetTester tester, {
    FilePicker? picker,
  }) async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        extensionManagerProvider.overrideWith((Ref ref) => manager),
        if (picker != null)
          filePickerProvider.overrideWith((Ref ref) => picker),
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
      () => file.writeAsString(
        _source(id: 'com.test.view', name: 'View Fixture'),
      ),
    );

    final ProviderContainer container = await pumpView(
      tester,
      picker: _PathPicker(file),
    );
    await settle(
      tester,
      container,
      () => container.read(extensionsProvider).status == ExtensionsStatus.ready,
    );

    // The flow is picker-first (PRE-F §15): choose a file, then install. No
    // filesystem path is ever typed or displayed.
    await tester.tap(find.text('Install extension'));
    await openDialog(tester);
    await tester.tap(find.text('Choose a .js file…'));
    // The picker performs real file I/O; pump the real async zone until the
    // dialog reflects the pick.
    for (int i = 0; i < 20 && find.text('view.js').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(find.text('view.js'), findsOneWidget);
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
    // A file that exists but is not a valid extension: the picker succeeds, and
    // the manager is what rejects it. This proves the error comes from the
    // ExtensionManager pipeline rather than from the picker.
    final File bad = File('${dir.path}/broken.js');
    await tester.runAsync(() => bad.writeAsString('not an extension at all'));

    final ProviderContainer container = await pumpView(
      tester,
      picker: _PathPicker(bad),
    );
    await settle(
      tester,
      container,
      () => container.read(extensionsProvider).status == ExtensionsStatus.ready,
    );

    await tester.tap(find.text('Install extension'));
    await openDialog(tester);
    await tester.tap(find.text('Choose a .js file…'));
    for (int i = 0; i < 20 && find.text('broken.js').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(TextButton, 'Install'));
    await tester.pump();

    await settle(
      tester,
      container,
      () => container.read(extensionsProvider).errorMessage != null,
    );

    // PRE-F §16: the reason is now explained in plain language instead of a raw
    // parser prefix, and it never blames a size limit that was never hit.
    expect(find.textContaining('not a SPECTA extension'), findsOneWidget);
    expect(find.textContaining('too large'), findsNothing);
    // PRE-F §15: the surfaced error never carries a filesystem path.
    expect(find.textContaining(dir.path), findsNothing);
    expect(find.textContaining('/data/user/'), findsNothing);
    expect(find.textContaining('No extensions are installed'), findsOneWidget);
  });

  // PRE-F §15: no filesystem path may ever be rendered to the user.
  testWidgets('the install dialog never shows a filesystem path', (
    WidgetTester tester,
  ) async {
    final File file = File('${dir.path}/secret-name.js');
    await tester.runAsync(
      () => file.writeAsString(_source(id: 'com.test.path', name: 'P')),
    );

    final ProviderContainer container = await pumpView(
      tester,
      picker: _PathPicker(file),
    );
    await settle(
      tester,
      container,
      () => container.read(extensionsProvider).status == ExtensionsStatus.ready,
    );

    await tester.tap(find.text('Install extension'));
    await openDialog(tester);
    await tester.tap(find.text('Choose a .js file…'));
    for (
      int i = 0;
      i < 20 && find.text('secret-name.js').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    // The document's own name is shown...
    expect(find.text('secret-name.js'), findsOneWidget);
    // ...and neither the app-private path nor any sdcard path is rendered.
    expect(find.textContaining(dir.path), findsNothing);
    expect(find.textContaining('/data/user/'), findsNothing);
    expect(find.textContaining('/sdcard'), findsNothing);
    expect(find.textContaining('/storage/emulated'), findsNothing);
    expect(find.textContaining('Extension file path'), findsNothing);
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

  testWidgets(
    'removing an extension asks for confirmation and then removes it',
    (WidgetTester tester) async {
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

      expect(
        find.textContaining('No extensions are installed'),
        findsOneWidget,
      );
      expect(await registry.getById('com.test.remove'), isNull);
    },
  );

  // Regression, found on a REAL device during Phase F: at phone width the
  // header's action Row overflowed by 147 px, which Flutter renders as a
  // black/yellow hatch and one-character-per-line text. Every action must stay
  // reachable on a narrow screen.
  testWidgets(
    'the extensions header does not overflow on a narrow phone width',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final ProviderContainer container = await pumpView(tester);
      await settle(tester, container, () => true);

      expect(tester.takeException(), isNull);
      // Every action is still present and reachable.
      expect(find.text('From a link'), findsOneWidget);
      expect(find.text('Install'), findsOneWidget);
      expect(find.byIcon(Icons.travel_explore_rounded), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    },
  );
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

/// Stands in for the Android SAF document picker. The real implementation
/// copies the document into app-private storage; this fake reports the source
/// file directly, which is the same contract the picker satisfies.
class _PathPicker implements FilePicker {
  _PathPicker(this.file);

  final File file;

  @override
  Future<FilePickResult> pick({
    List<String> mimeTypes = defaultMimeTypes,
  }) async {
    final String name = file.uri.pathSegments.last;
    if (!await file.exists()) {
      // Mirrors the platform contract: a document that cannot be read is a
      // failed pick, never a usable path handed to the importer.
      return const FilePickFailed(
        'That file could not be read on this device.',
      );
    }
    final List<int> bytes = await file.readAsBytes();
    return FilePicked(
      PickedFile(
        path: file.path,
        displayName: name,
        sizeBytes: bytes.length,
        sha256: await _sha256Hex(bytes),
      ),
    );
  }
}

Future<String> _sha256Hex(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  return hash.bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
}
