import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/compat/source_format_detector.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/runtime/extension_runtime.dart';
import 'package:specta/core/extensions/runtime/flutter_js_sandbox.dart';

/// Whether the real QuickJS engine can run in this process.
///
/// Same rule the existing real-engine suites use: skip and say so, rather than
/// report "passing" for code that never executed.
String? _engineSkipReason() {
  if (!Platform.isWindows) return null;
  try {
    final DynamicLibrary bridge = DynamicLibrary.open('quickjs_c_bridge.dll');
    if (!bridge.providesSymbol('jsNewRuntime')) {
      return 'quickjs_c_bridge.dll was found but does not export jsNewRuntime.';
    }
    return null;
  } on Object catch (e) {
    return 'The flutter_js QuickJS bridge is not loadable here ($e).';
  }
}

/// A third-party provider in the REAL shape: no SPECTA header, no exports at
/// all, just top-level functions named the way its own host names them.
const String _globalFunctionProvider = '''
var SITE = 'https://example.invalid';

function getInfo() {
  return { name: 'Global Co', version: '4.2.0', type: 'movie' };
}

function search(query, page) {
  return { results: [{ id: 'r1', title: query + ' page ' + page }] };
}

function getHome() {
  return { results: [{ id: 'h1', title: 'Home item' }] };
}

function getDetail(ref) {
  return { id: ref, title: 'Detail for ' + ref };
}

function getVideoSources(ref) {
  return { sources: [{ url: 'https://example.invalid/' + ref + '.m3u8',
                       quality: '720p', label: 'HD' }] };
}
''';

void main() {
  group('an adapted third-party source EXECUTES on the real engine', () {
    test('the shim reaches a provider that exports nothing', () async {
      final ResolvedImportableSource resolved = resolveImportableSource(
        _globalFunctionProvider,
      );
      expect(resolved.failure, isNull);
      expect(resolved.analysis?.format, SourceFormat.adapted);

      final FlutterJsSandbox sandbox = FlutterJsSandbox();
      addTearDown(sandbox.dispose);
      await sandbox.init();

      // The real runtime evaluates this bootstrap base class before the
      // extension body; `class Extension extends SpectaExtension` needs it.
      // `evaluate` (script mode), NOT `evaluateAsync`: the latter wraps the
      // code in an async IIFE, inside which class and function DECLARATIONS
      // are not valid. This is exactly what ExtensionRuntime.loadExtension
      // does, and it is why the two paths must not be confused.
      await sandbox.evaluate(sandboxBootstrap);
      await sandbox.evaluate(resolved.source);
      // Instantiate the generated bridge the runtime would instantiate.
      await sandbox.evaluate('var e = new Extension();');

      // search: contract name and foreign name coincide.
      final String searchRaw = await sandbox.evaluateAsync(
        'JSON.stringify(await e.search("dune", 1))',
      );
      final Map<String, dynamic> search =
          jsonDecode(searchRaw) as Map<String, dynamic>;
      expect(
        (search['results'] as List).first['title'],
        contains('dune'),
        reason: 'search must reach the provider',
      );

      // latest -> getHome. Calling the contract name against a file that has
      // no `latest` is precisely what used to throw.
      final String latestRaw = await sandbox.evaluateAsync(
        'JSON.stringify(await e.latest(1))',
      );
      final Map<String, dynamic> latest =
          jsonDecode(latestRaw) as Map<String, dynamic>;
      expect(
        (latest['results'] as List).first['title'],
        'Home item',
        reason: 'latest must forward to the provider\'s getHome',
      );

      // details -> getDetail
      final String detailsRaw = await sandbox.evaluateAsync(
        'JSON.stringify(await e.details("abc"))',
      );
      expect(
        (jsonDecode(detailsRaw) as Map<String, dynamic>)['title'],
        'Detail for abc',
      );

      // getSources -> getVideoSources
      final String sourcesRaw = await sandbox.evaluateAsync(
        'JSON.stringify(await e.getSources("abc"))',
      );
      final Map<String, dynamic> sources =
          jsonDecode(sourcesRaw) as Map<String, dynamic>;
      expect(
        (sources['sources'] as List).first['quality'],
        '720p',
        reason: 'getSources must forward to getVideoSources',
      );
    }, skip: _engineSkipReason());

    test(
      'a real third-party file loads and its operations are callable',
      () async {
        final File file = File('test/support/fixtures/third_party/hdhub4u.js');
        if (!file.existsSync()) {
          fail('hdhub4u.js fixture is missing from ${file.path}');
        }
        final ResolvedImportableSource resolved = resolveImportableSource(
          file.readAsStringSync(),
        );
        expect(resolved.failure, isNull);

        final FlutterJsSandbox sandbox = FlutterJsSandbox();
        addTearDown(sandbox.dispose);
        await sandbox.init();

        await sandbox.evaluate(sandboxBootstrap);
        // PROOF that a genuine 30 KB third-party file is accepted, shimmed and
        // evaluated. This is the file the bug report was actually about.
        await sandbox.evaluate(resolved.source);
        await sandbox.evaluate('var e = new Extension();');

        // The provider's own function is present and callable through the
        // bridge under its real name.
        final String raw = await sandbox.evaluateAsync(
          'JSON.stringify(typeof e.getSources === "function")',
        );
        expect(raw, 'true');

        // Its metadata helper really is the author's own function.
        final String info = await sandbox.evaluateAsync(
          'JSON.stringify(getInfo())',
        );
        final Map<String, dynamic> described =
            jsonDecode(info) as Map<String, dynamic>;
        expect(described['name'], 'HDHub4u');
        expect(described['version'], '1.2.4');
      },
      skip: _engineSkipReason(),
    );
  });
}
