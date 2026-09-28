// SLICE 1 + SLICE 2 — REAL DEVICE VERIFICATION (test-only; no lib/ change).
//
// docs/SOURCE_RUN_REPORT.md §C.3 recorded two things as NOT VERIFIED:
//
//   (1) "No real Android device run - no APK built for these slices; all layout
//        claims are from widget-test geometry, not a device screenshot."
//   (2) "Runtime execution of an ADAPTED source in a live JS sandbox is
//        UNVERIFIED - the shim is proven to parse natively ... but never
//        evaluated in flutter_js; install is VERIFIED, resolve is NOT."
//
// This suite closes both on physical hardware. It imports product code and
// changes none of it; `integration_test/` is not compiled into the shipping app.
//
//   PART A — the Sources screen as it really renders on the device:
//     A1  the header offers "+ Add Source" and it lies wholly inside the real
//         screen, without scrolling;
//     A2  the header contains no horizontally scrollable viewport (the defect
//         Slice 1 removed) and the render produces no overflow exception;
//     A3  the node card measures under the old three-row 138 px height;
//     A4  the Add Source sheet is fully on-screen and offers only the routes
//         this build implements;
//     A5  the compact card still reaches details and remove through the overflow
//         menu, so compaction removed no capability;
//     A6  the same layout holds when constrained to a 320 px-wide phone.
//
//   PART B — a foreign source actually executed by the real QuickJS engine:
//     B1  a CommonJS source with no SPECTA header is adapted, not refused;
//     B2  it installs through the real Drift registry on the device database;
//     B3  it LOADS in the real flutter_js/QuickJS sandbox on the device;
//     B4  calling search()/details() through the shim runs the FOREIGN code and
//         returns the foreign code's own values — the shim forwards, end to end;
//     B5  a call the foreign source does not implement is reported, not faked;
//     B6  adaptation confers no trust: the record stays unverified and lands in
//         the user node space, never the undeletable Node 0.
//
// Run (from the project root):
//   flutter test integration_test/slice12_device_verification_test.dart -d R83L20FRDFM
//
// Second evidence trail:  adb logcat -s flutter | grep SPECTA-S12
//
// A failure here is reported as a test failure, never hidden.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod.
import 'package:riverpod/misc.dart' show Override;

import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/compat/source_format_detector.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/extensions/identity/source_node.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/drift_extension_registry.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_providers.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/in_memory_extension_registry.dart';
import 'package:specta/core/extensions/runtime/extension_runtime.dart';
import 'package:specta/core/extensions/runtime/flutter_js_sandbox.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';
import 'package:specta/features/extensions/extensions_view.dart';
import 'package:specta/features/extensions/state/extensions_state.dart';
import 'package:specta/ui/widgets/specta_card.dart';

/// logcat evidence marker: `adb logcat -s flutter | grep SPECTA-S12`
const String _tag = 'SPECTA-S12';

void _log(String step, String detail) {
  debugPrint('[$_tag] $step :: $detail');
}

/// The nodes user-owned sources receive.
const SourceNode node1 = SourceNode(space: SourceNodeSpace.user, index: 1);
const SourceNode node2 = SourceNode(space: SourceNodeSpace.user, index: 2);
const SourceNode node3 = SourceNode(space: SourceNodeSpace.user, index: 3);

/// A minimal installed record, for the layout checks that only care about shape.
ExtensionRecord _record(String id, String name, SourceNode node) {
  final DateTime now = DateTime.now().toUtc();
  return ExtensionRecord(
    id: id,
    name: name,
    version: '1.0.0',
    author: 'SPECTA Device Run',
    apiVersion: 2,
    contentType: 'movie',
    signature: null,
    trustLevel: TrustLevel.unverified,
    enabled: true,
    filePath: '$id.js',
    installedAt: now,
    updatedAt: now,
    node: node,
  );
}

/// A foreign source in the shape another host's extension systems commonly use:
/// a CommonJS module that declares its own metadata and exports its operations
/// as object members. It carries no SPECTA header.
///
/// This is deliberately the SAME shape as the in-repo unit fixture, because that
/// is the shape Slice 2 claims to support. It returns deterministic values and
/// touches no network, so a failure here can only mean the bridge is broken —
/// never that the device happened to be offline.
String _foreignCommonJs() => '''
const BUILD = 'foreign-build-7';

module.exports = {
  name: 'Community Device Source',
  version: '2.3.1',
  author: 'A Community Developer',
  description: 'A source written for another host.',
  website: 'https://example.invalid',
  type: 'movie',

  search: async function (query, page) {
    return [{
      title: 'FOREIGN[' + query + ']' + BUILD,
      url: 'https://example.invalid/watch/' + encodeURIComponent(query),
      type: 'movie',
      year: 2026,
    }];
  },

  details: async function (reference) {
    return {
      id: reference,
      title: 'FOREIGN-DETAILS ' + reference,
      url: reference,
      type: 'movie',
      year: 2026,
    };
  },

  healthCheck: async function () { return true; },
};
''';

/// Host API for the compatibility run. It refuses every network call, so the run
/// also proves the adapted source reached no host authority it was not granted.
final class _RefusingApi implements ExtensionRuntimeApi {
  int requestCalls = 0;

  @override
  Future<ExtensionResponse> request(ExtensionRequest request) async {
    requestCalls++;
    throw StateError(
      'the adapted fixture must not reach the host transport '
      '(${request.method} ${request.url})',
    );
  }

  @override
  void log(ExtensionLogLevel level, String message) {
    _log('ext-log', '${level.code}: $message');
  }
}

/// A runtime API for the layout run: the Sources screen never executes JS, but
/// the manager requires one, and a device run must not stand up a sandbox it
/// will not use.
final class _NoopRuntimeApi implements ExtensionRuntimeApi {
  @override
  Future<ExtensionResponse> request(ExtensionRequest request) async =>
      const ExtensionResponse(status: 200, ok: true, body: '{}');

  @override
  void log(ExtensionLogLevel level, String message) {}
}

/// App-private temp directory. Android points TMPDIR at the app's own cache
/// directory, so this is the real condition the import path runs under.
Future<File> _writeSource(String source, String fileName) async {
  final Directory dir = Directory(
    '${Directory.systemTemp.path}/specta_s12_probe',
  ).absolute;
  await dir.create(recursive: true);
  final File file = File('${dir.path}/$fileName');
  await file.writeAsString(source, flush: true);
  return file;
}

/// Whether [finder]'s rendered box lies wholly inside the given logical size.
///
/// Defaults to the device's own real screen. A control pushed off the edge is
/// as unusable as a clipped one, which is the property the requirement is about.
bool _insideScreen(
  WidgetTester tester,
  Finder finder,
  String label, {
  double? boundsWidth,
  double? boundsHeight,
}) {
  final Rect box = tester.getRect(finder);
  final Size view = tester.view.physicalSize / tester.view.devicePixelRatio;
  final double w = boundsWidth ?? view.width;
  final double h = boundsHeight ?? view.height;
  final bool inside =
      box.left >= 0 && box.top >= 0 && box.right <= w && box.bottom <= h;
  _log(
    'geometry',
    '$label -> '
        '${box.left.round()},${box.top.round()} .. '
        '${box.right.round()},${box.bottom.round()} '
        'within ${w.round()}x${h.round()} = $inside',
  );
  return inside;
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Real time and real frames: this is a hardware run, not a simulation.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  group('SLICE 1 — the Sources screen as the device really renders it', () {
    late InMemoryExtensionRegistry registry;
    late ExtensionManager manager;

    setUp(() {
      registry = InMemoryExtensionRegistry();
      manager = ExtensionManager(
        registry: registry,
        runtimeApi: _NoopRuntimeApi(),
        sandboxFactory: FlutterJsSandbox.new,
      );
    });

    /// Pumps the real Sources screen through the real provider graph.
    ///
    /// With [widthPx] the screen is laid out at that width inside the real
    /// device surface, which is how a 320 px phone is exercised without needing
    /// a second physical phone.
    Future<ProviderContainer> pumpSources(
      WidgetTester tester, {
      double? widthPx,
    }) async {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          extensionManagerProvider.overrideWith((Ref ref) => manager),
        ],
      );
      addTearDown(container.dispose);

      final Widget view = MaterialApp(home: Scaffold(body: ExtensionsView()));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: widthPx == null
              ? view
              : MediaQuery(
                  data: MediaQueryData(size: Size(widthPx, 800)),
                  child: Center(
                    child: SizedBox(width: widthPx, child: view),
                  ),
                ),
        ),
      );
      return container;
    }

    /// Lets real asynchronous work (registry reads) finish, then flushes frames.
    Future<void> settle(
      WidgetTester tester,
      ProviderContainer container,
      bool Function() done,
    ) async {
      final Stopwatch watch = Stopwatch()..start();
      while (!done() && watch.elapsed < const Duration(seconds: 10)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pump();
    }

    Future<void> pumpThreeSources(WidgetTester tester) async {
      await registry.install(_record('dev.test.alpha', 'Alpha', node1));
      await registry.install(_record('dev.test.beta', 'Beta', node2));
      await registry.install(_record('dev.test.gamma', 'Gamma', node3));
    }

    void reportDevice(WidgetTester tester) {
      final Size view = tester.view.physicalSize / tester.view.devicePixelRatio;
      _log(
        'device',
        'logical ${view.width.round()}x${view.height.round()} '
            '@${tester.view.devicePixelRatio}x, '
            'textScaleFactor ${tester.platformDispatcher.textScaleFactor}',
      );
    }

    testWidgets('A1/A2: Add Source is on-screen and nothing scrolls sideways', (
      WidgetTester tester,
    ) async {
      reportDevice(tester);
      await pumpThreeSources(tester);
      final ProviderContainer c = await pumpSources(tester);
      await settle(
        tester,
        c,
        () => c.read(extensionsProvider).items.length == 3,
      );

      expect(find.text('Sources'), findsOneWidget);
      final Finder addSource = find.text('Add Source');
      expect(addSource, findsOneWidget);
      expect(
        _insideScreen(tester, addSource, 'Add Source'),
        isTrue,
        reason:
            '"Add Source" must be fully visible without scrolling on the '
            'real device screen.',
      );

      // The defect Slice 1 removed was a horizontally scrolling action strip.
      // No horizontally scrollable viewport may exist anywhere in this screen.
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
        findsNothing,
        reason: 'the header must not scroll sideways on a real phone.',
      );

      // Secondary chrome is still present as fixed, non-scrolling actions.
      expect(find.byIcon(Icons.monitor_heart_outlined), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(find.byIcon(Icons.upgrade_rounded), findsOneWidget);

      // A layout overflow on real hardware paints stripes and records an
      // exception. Neither may happen.
      expect(tester.takeException(), isNull);
      _log(
        'A1',
        'Add Source fully on-screen; no horizontal viewport; no '
            'overflow exception',
      );
    });

    testWidgets('A3: the node card is compact on the device', (
      WidgetTester tester,
    ) async {
      reportDevice(tester);
      await pumpThreeSources(tester);
      final ProviderContainer c = await pumpSources(tester);
      await settle(
        tester,
        c,
        () => c.read(extensionsProvider).items.length == 3,
      );

      final double h = tester.getSize(find.byType(SpectaCard).first).height;
      _log('A3', 'node card height on device = ${h.toStringAsFixed(1)} px');
      expect(
        h,
        lessThan(110),
        reason:
            'the card must stay well under the old three-row 138 px height '
            'on real hardware, not only in a widget test.',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('A4: the Add Source sheet is fully on-screen', (
      WidgetTester tester,
    ) async {
      reportDevice(tester);
      await pumpThreeSources(tester);
      final ProviderContainer c = await pumpSources(tester);
      await settle(
        tester,
        c,
        () => c.read(extensionsProvider).items.length == 3,
      );

      await tester.tap(find.text('Add Source'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Exactly the routes this build implements, and nothing invented.
      for (final String route in <String>[
        'Install from a link',
        'Import a JavaScript file',
        'Browse the official catalogue',
        'Add from a repository',
      ]) {
        final Finder option = find.text(route);
        expect(option, findsOneWidget, reason: '"$route" is missing.');
        expect(
          _insideScreen(tester, option, route),
          isTrue,
          reason: '"$route" must be readable without horizontal scrolling.',
        );
      }
      expect(tester.takeException(), isNull);
      _log('A4', 'all four install routes rendered fully on-screen');
    });

    testWidgets('A5: the compact card still reaches details and remove', (
      WidgetTester tester,
    ) async {
      reportDevice(tester);
      await pumpThreeSources(tester);
      final ProviderContainer c = await pumpSources(tester);
      await settle(
        tester,
        c,
        () => c.read(extensionsProvider).items.length == 3,
      );

      expect(find.text('Node 1'), findsOneWidget);
      expect(find.text('Enabled'), findsWidgets);

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Remove source'), findsOneWidget);
      expect(tester.takeException(), isNull);
      _log('A5', 'overflow menu still carries details and remove');
    });

    testWidgets('A6: the layout holds on a 320 px phone', (
      WidgetTester tester,
    ) async {
      reportDevice(tester);
      await pumpThreeSources(tester);
      final ProviderContainer c = await pumpSources(tester, widthPx: 320);
      await settle(
        tester,
        c,
        () => c.read(extensionsProvider).items.length == 3,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Add Source'), findsOneWidget);
      expect(
        _insideScreen(
          tester,
          find.text('Add Source'),
          'Add Source @320px',
          boundsWidth: 320,
        ),
        isTrue,
        reason: 'the primary action must fit a 320 px phone.',
      );
      expect(
        _insideScreen(
          tester,
          find.text('Node 1'),
          'Node 1 label @320px',
          boundsWidth: 320,
        ),
        isTrue,
        reason: 'the node label must not be pushed off a 320 px phone.',
      );
      _log('A6', 'layout holds at 320 px with no overflow');
    });
  });

  group('SLICE 2 — a foreign source executed by the device’s real JS engine', () {
    // One database for the whole group: opening a second SpectaDatabase while
    // this one is live draws a cross-isolate-unsafe warning from Drift (see
    // phase2f_device_verification_test.dart's note on the same trap).
    late SpectaDatabase db;
    late DriftExtensionRegistry registry;
    late _RefusingApi api;
    late ExtensionManager manager;
    String? installedId;

    setUp(() {
      db = SpectaDatabase();
      registry = DriftExtensionRegistry(db);
      api = _RefusingApi();
      manager = ExtensionManager(
        registry: registry,
        runtimeApi: api,
        sandboxFactory: FlutterJsSandbox.new,
      );
    });

    tearDown(() async {
      // Never leave a verification source installed on the user's device.
      if (installedId != null) {
        try {
          await manager.shutdown(installedId!);
        } on Object catch (_) {}
        try {
          await manager.uninstall(installedId!);
        } on Object catch (_) {}
        installedId = null;
      }
      await db.close();
    });

    testWidgets(
      'B1-B6: a foreign CommonJS source adapts, installs, LOADS and answers',
      (WidgetTester tester) async {
        await tester.runAsync(() async {
          // ---- B1: adaptation, not refusal ---------------------------------
          final String foreign = _foreignCommonJs();
          final ResolvedImportableSource resolved = resolveImportableSource(
            foreign,
          );
          _log(
            'B1',
            'format=${resolved.analysis?.format.name} '
                'adapted=${resolved.wasAdapted} '
                'failure=${resolved.failure?.message}',
          );
          expect(
            resolved.failure,
            isNull,
            reason:
                'a foreign source must not be refused for lacking a '
                'SPECTA header.',
          );
          expect(
            resolved.wasAdapted,
            isTrue,
            reason:
                'resolveImportableSource '
                'did not mark a CommonJS source as adapted.',
          );
          expect(resolved.analysis!.format, SourceFormat.adapted);
          // The detector read the foreign module's own metadata, which is what
          // the generated header is built from.
          expect(resolved.analysis!.name, 'Community Device Source');
          expect(resolved.source, contains('// ==SpectaExtension=='));
          expect(
            resolved.source,
            contains('module.exports'),
            reason:
                'the foreign body must be embedded verbatim, not rewritten.',
          );

          // ---- B2: install through the real Drift registry ------------------
          final File file = await _writeSource(
            resolved.source,
            'adapted_foreign_device.js',
          );
          final SpectaResult<ExtensionRecord> imported = await manager
              .importExtension(filePath: file.path);
          _log(
            'B2',
            imported.isOk
                ? 'install OK id=${imported.valueOrNull!.id} '
                      'node=${imported.valueOrNull!.node?.label} '
                      'trust=${imported.valueOrNull!.trustLevel.name} '
                      'contentType=${imported.valueOrNull!.contentType}'
                : 'install FAILED ${imported.failureOrNull}',
          );
          expect(
            imported.isOk,
            isTrue,
            reason: 'install failed: ${imported.failureOrNull}',
          );
          installedId = imported.valueOrNull!.id;

          // ---- B6: adaptation confers no trust and no privileged node ------
          expect(imported.valueOrNull!.trustLevel, TrustLevel.unverified);
          final SourceNode? landedNode = imported.valueOrNull!.node;
          expect(
            landedNode,
            isNotNull,
            reason: 'every installed source must hold a node.',
          );
          expect(landedNode!.space, SourceNodeSpace.user);
          expect(
            landedNode.index,
            greaterThan(0),
            reason:
                'an adapted third-party source must never land in the '
                'undeletable Node 0.',
          );

          // ---- B3: the real QuickJS engine evaluates the adapted source ----
          final SpectaResult<ExtensionRuntime> load = await manager.loadRuntime(
            installedId!,
          );
          _log(
            'B3',
            load.isOk
                ? 'loadRuntime OK — QuickJS on the device evaluated the shim '
                      'and the embedded foreign body'
                : 'loadRuntime FAILED: ${load.failureOrNull}',
          );
          expect(
            load.isOk,
            isTrue,
            reason:
                'THE ADAPTED SOURCE DOES NOT RUN ON THE DEVICE ENGINE: '
                '${load.failureOrNull}',
          );

          // ---- B4: the shim forwards into the FOREIGN code -----------------
          final SpectaResult<List<SearchResult>> search = await manager
              .callOperation<List<SearchResult>>(
                installedId!,
                (ExtensionRuntime runtime) =>
                    runtime.search(query: 'ghost', page: 1),
              );
          _log(
            'B4',
            search.isOk
                ? 'search OK -> ${search.valueOrNull!.map((SearchResult e) => e.title).toList()}'
                : 'search FAILED: ${search.failureOrNull}',
          );
          expect(
            search.isOk,
            isTrue,
            reason: 'search() through the shim failed: ${search.failureOrNull}',
          );
          // The value can only have come from the foreign body: both strings
          // are that source's own literals.
          expect(search.valueOrNull, hasLength(1));
          expect(
            search.valueOrNull!.single.title,
            'FOREIGN[ghost]foreign-build-7',
            reason:
                'the host received something other than what the foreign '
                'source returned.',
          );
          expect(search.valueOrNull!.single.year, 2026);

          final SpectaResult<MediaDetails> details = await manager
              .callOperation<MediaDetails>(
                installedId!,
                (ExtensionRuntime runtime) =>
                    runtime.details(url: 'https://example.invalid/watch/ghost'),
              );
          _log(
            'B4',
            details.isOk
                ? 'details OK -> ${details.valueOrNull!.title}'
                : 'details FAILED: ${details.failureOrNull}',
          );
          expect(
            details.isOk,
            isTrue,
            reason:
                'details() through the shim failed: ${details.failureOrNull}',
          );
          expect(details.valueOrNull!.title, contains('FOREIGN-DETAILS'));

          // ---- B5: an operation the foreign source lacks is reported -------
          // The fixture implements search/details/healthCheck only, so the
          // adapter granted no `latest` capability. The host must say so rather
          // than fabricate a feed.
          final SpectaResult<List<SearchResult>> latest = await manager
              .callOperation<List<SearchResult>>(
                installedId!,
                (ExtensionRuntime runtime) => runtime.latest(page: 1),
              );
          _log(
            'B5',
            latest.isErr
                ? 'absent latest() reported as: ${latest.failureOrNull?.message}'
                : 'absent latest() RETURNED DATA — a fabricated feed',
          );
          expect(
            latest.isErr,
            isTrue,
            reason:
                'an operation the foreign source does not implement must '
                'be reported, never faked.',
          );

          // No host authority was reached while running untrusted foreign code.
          expect(api.requestCalls, 0);

          // ---- and the source leaves the device as cleanly as it arrived ---
          await manager.shutdown(installedId!);
          _log('cleanup', 'shutdown OK — the QuickJS context was released');

          final ExtensionRecord? stillInstalled = await registry.getById(
            installedId!,
          );
          expect(
            stillInstalled,
            isNotNull,
            reason: 'shutdown must not remove the installation itself.',
          );
          _log(
            'cleanup',
            'source is still installed after shutdown, as it '
                'should be',
          );
        });
      },
    );
  });
}
