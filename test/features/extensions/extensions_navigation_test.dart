import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/app/platform/file_picker.dart';
import 'package:specta/core/extensions/identity/source_node.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_providers.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/in_memory_extension_registry.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';
import 'package:specta/features/extensions/extensions_view.dart';
import 'package:specta/features/extensions/source_health_view.dart';
import 'package:specta/features/extensions/state/extensions_state.dart';

import '../../support/fake_js_sandbox.dart';

/// Slice 7b: the two surfaces that were built, tested and shipped - and were
/// unreachable - are now proven reachable THROUGH THE REAL NAVIGATION PATH.
///
/// The defect this file exists to prevent: Slice 7 passed its gate with 1252
/// green tests while `SourceHealthView` had no import, no route and no
/// construction site anywhere in `lib/`. Its own tests pumped the widget
/// directly, so nothing ever travelled through navigation and the gap was
/// invisible to the suite.
///
/// Therefore, deliberately: **no test in this file ever constructs
/// `SourceHealthView` or the install dialog directly.** Every one of them starts
/// at `ExtensionsView` - the screen a person is actually looking at - and gets
/// there by tapping, exactly as a user would. A test that pumps the destination
/// widget could not have caught the original defect, so none is written here.
void main() {
  late Directory dir;
  late InMemoryExtensionRegistry registry;
  late ExtensionManager manager;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('specta_7b_nav');
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

  /// Installs a record straight into the registry, standing in for a node a
  /// previous session already persisted.
  Future<void> seed({
    required String id,
    required String name,
    required int index,
  }) async {
    final DateTime now = DateTime.utc(2026, 1, 1);
    await registry.install(
      ExtensionRecord(
        id: id,
        name: name,
        version: '1.0.0',
        author: 'SPECTA Tests',
        apiVersion: 2,
        contentType: 'movie',
        signature: null,
        trustLevel: TrustLevel.unverified,
        enabled: true,
        filePath: '${dir.path}\\seed.js',
        installedAt: now,
        updatedAt: now,
        node: SourceNode(space: SourceNodeSpace.user, index: index),
      ),
    );
  }

  /// Waits, across the real async zone, until [done] or the budget expires.
  Future<void> waitFor(
    WidgetTester tester,
    bool Function() done, {
    Duration budget = const Duration(seconds: 8),
  }) async {
    final Stopwatch watch = Stopwatch()..start();
    while (!done() && watch.elapsed < budget) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  /// Pumps the REAL Sources screen, never the destination under test.
  Future<ProviderContainer> pumpSources(
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

    await waitFor(
      tester,
      () => container.read(extensionsProvider).status == ExtensionsStatus.ready,
    );
    // `ready` can be published a frame before the item list is committed to the
    // widget tree, so flush a few more frames before any finder is used.
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return container;
  }

  /// Taps a header action.
  ///
  /// Slice 1 removed the horizontal scroll view this helper existed to scroll.
  /// The header's actions are now fixed, always-on-screen icon buttons, so a
  /// plain tap is correct. The helper is kept - rather than inlined - because
  /// these tests are about reachability, and one place to tap is one place to
  /// keep true.
  Future<void> tapHeaderAction(WidgetTester tester, Finder target) async {
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  group('Source Health is reachable from the Sources screen', () {
    testWidgets('tapping its action opens the screen', (
      WidgetTester tester,
    ) async {
      await seed(id: 'com.test.one', name: 'PirateSource', index: 1);
      await pumpSources(tester);

      // We are on Sources, and Source Health is NOT on screen yet.
      expect(find.byType(SourceHealthView), findsNothing);

      await tapHeaderAction(tester, find.byIcon(Icons.monitor_heart_outlined));

      // The screen is now genuinely on screen, reached by a tap.
      expect(find.byType(SourceHealthView), findsOneWidget);
    });

    testWidgets('the screen can be left again and returns to Sources', (
      WidgetTester tester,
    ) async {
      await seed(id: 'com.test.one', name: 'PirateSource', index: 1);
      await pumpSources(tester);

      await tapHeaderAction(tester, find.byIcon(Icons.monitor_heart_outlined));
      expect(find.byType(SourceHealthView), findsOneWidget);

      // A pushed route with no way back would strand the user. Assert the
      // escape, which is the half of navigation that is easy to forget.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(SourceHealthView), findsNothing);
      expect(find.byType(ExtensionsView), findsOneWidget);
    });

    testWidgets('reached this way, it shows node labels and no source name', (
      WidgetTester tester,
    ) async {
      await seed(id: 'com.test.one', name: 'PirateSource', index: 1);
      await seed(id: 'com.test.two', name: 'AnotherLeak', index: 2);
      await pumpSources(tester);

      await tapHeaderAction(tester, find.byIcon(Icons.monitor_heart_outlined));

      final StringBuffer buffer = StringBuffer();
      for (final Element element in find.byType(Text).evaluate()) {
        buffer.write('${(element.widget as Text).data ?? ''} ');
      }
      final String text = buffer.toString();

      // Node labels, per the contract...
      expect(text, contains('Node 1'));
      expect(text, contains('Node 2'));
      // ...and none of the third-party strings the provider chose.
      expect(text, isNot(contains('PirateSource')));
      expect(text, isNot(contains('AnotherLeak')));
      expect(text, isNot(contains('com.test.one')));
      expect(text, isNot(contains(dir.path)));
    });

    testWidgets('an unused node reads "No data yet" through the real path', (
      WidgetTester tester,
    ) async {
      // Healthy and enabled with zero failures, but nothing has ever succeeded.
      // A confident percentage here would be a fabricated measurement.
      await seed(id: 'com.test.fresh', name: 'PirateSource', index: 1);
      await pumpSources(tester);

      await tapHeaderAction(tester, find.byIcon(Icons.monitor_heart_outlined));

      expect(find.text('No data yet'), findsOneWidget);
      expect(find.text('100%'), findsNothing);
    });
  });

  group('installing from a file works when sources already exist', () {
    testWidgets('the action is offered even with sources installed', (
      WidgetTester tester,
    ) async {
      await seed(id: 'com.test.existing', name: 'Already Here', index: 1);
      await pumpSources(tester);

      // Before this slice the ONLY file-install entry point lived inside the
      // empty state, so with one node installed a second source could not be
      // added from a file at all. The action is now unconditional.
      expect(find.text('1 installed'), findsOneWidget);
      // Slice 1: the action is one always-visible "+ Add Source" button, and
      // the file route is one of its options. Assert both, so the file route
      // can never quietly become unreachable once sources are installed.
      expect(find.text('Add Source'), findsOneWidget);
      await tapHeaderAction(tester, find.text('Add Source'));
      expect(find.text('Import a JavaScript file'), findsOneWidget);
    });

    testWidgets('a second source is installed and becomes Node 2', (
      WidgetTester tester,
    ) async {
      await seed(id: 'com.test.existing', name: 'Already Here', index: 1);

      final File file = File('${dir.path}/second.js');
      await tester.runAsync(
        () => file.writeAsString(
          _source(id: 'com.test.second', name: 'Second Fixture'),
        ),
      );

      await pumpSources(tester, picker: _PathPicker(file));
      // Slice 1: the file route now lives in the "Add Source" sheet, which is
      // the single visible entry point for adding a source.
      await tapHeaderAction(tester, find.text('Add Source'));
      await tapHeaderAction(tester, find.text('Import a JavaScript file'));

      await tester.tap(find.text('Choose a .js file…'));
      await waitFor(
        tester,
        () => find.text('second.js').evaluate().isNotEmpty,
      );
      expect(find.text('second.js'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Install'));
      await tester.pumpAndSettle();
      await waitFor(tester, () => find.text('2 installed').evaluate().isNotEmpty);

      // Two nodes coexist, and the numbering continued rather than restarting.
      expect(find.text('2 installed'), findsOneWidget);
      expect(find.text('Node 1'), findsOneWidget);
      expect(find.text('Node 2'), findsOneWidget);
      // The card still leaks nothing.
      expect(find.text('Second Fixture'), findsNothing);
    });

    testWidgets('the empty state keeps its own install button', (
      WidgetTester tester,
    ) async {
      // The empty-state button is KEPT, not replaced: it is the most obvious
      // call to action on a screen with nothing in it.
      await pumpSources(tester);

      expect(find.text('0 installed'), findsOneWidget);
      expect(find.text('Install source'), findsOneWidget);
    });
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

/// Stands in for the Android SAF document picker. Same contract as the real
/// one: it reports a verified copy, never a bare path.
class _PathPicker implements FilePicker {
  _PathPicker(this.file);

  final File file;

  @override
  Future<FilePickResult> pick({
    List<String> mimeTypes = defaultMimeTypes,
  }) async {
    final String name = file.uri.pathSegments.last;
    if (!await file.exists()) {
      return const FilePickFailed(
        'That file could not be read on this device.',
      );
    }
    final List<int> bytes = await file.readAsBytes();
    final Hash hash = await Sha256().hash(bytes);
    return FilePicked(
      PickedFile(
        path: file.path,
        displayName: name,
        sizeBytes: bytes.length,
        sha256: hash.bytes
            .map((int b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
      ),
    );
  }
}
