import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/compat/foreign_source_adapter.dart';
import 'package:specta/core/extensions/compat/source_format_detector.dart';
import 'package:specta/core/extensions/contract/extension_capability.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manifest.dart';

/// A foreign source in the shape another host's extension systems commonly use:
/// a CommonJS module that declares its own metadata and exports operations as
/// object members. It has no SPECTA header at all.
String _foreignCommonJs({String name = 'Community Source'}) =>
    '''
const BASE = 'https://example.invalid';

module.exports = {
  name: '$name',
  version: '2.3.1',
  author: 'A Community Developer',
  description: 'A source written for another host.',
  website: 'https://example.invalid',
  type: 'anime',

  search: async function (query, page) {
    const res = await fetch(BASE + '/search?q=' + query + '&page=' + page);
    return { results: await res.json() };
  },

  latest: async function (page) {
    return { results: [] };
  },

  details: async function (ref) {
    return { id: ref };
  },

  getSources: async function (ref) {
    return { sources: [] };
  },
};
''';

/// A foreign source written as an ES module with a class, rather than CommonJS
/// object members. Exercises the other common shape.
String _foreignEsModule() => '''
export class Provider {
  constructor(options) {
    this.base = 'https://example.invalid';
  }

  async search(query, page) {
    return { results: [] };
  }

  async getSources(reference) {
    return { sources: [] };
  }
}

export default new Provider({});
''';

/// The native contract, used to prove native sources are untouched.
const String nativeSource =
    '// ==SpectaExtension==\n'
    '// @id org.test.native\n'
    '// @name Native\n'
    '// @version 1.0.0\n'
    '// @author SPECTA\n'
    '// @apiVersion 2\n'
    '// @type movie\n'
    '// @capabilities search,network\n'
    '// ==/SpectaExtension==\n'
    'class Extension extends SpectaExtension {}\n';

void main() {
  group('a native SPECTA source is recognised as native', () {
    test('is classified native and is not modified', () {
      final ResolvedImportableSource resolved = resolveImportableSource(
        nativeSource,
      );

      expect(resolved.failure, isNull);
      expect(resolved.analysis?.format, SourceFormat.native);
      expect(resolved.wasAdapted, isFalse);
      // Byte-identical: a native source is registered exactly as written.
      expect(resolved.source, nativeSource);
    });

    test('is never given a generated shim', () {
      final ResolvedImportableSource resolved = resolveImportableSource(
        nativeSource,
      );
      expect(resolved.source, isNot(contains('compatibility shim')));
    });
  });

  group('a foreign CommonJS source is adapted, not refused', () {
    test('is detected as adapted and reads its own metadata', () {
      final ResolvedImportableSource resolved = resolveImportableSource(
        _foreignCommonJs(),
      );

      expect(
        resolved.failure,
        isNull,
        reason:
            'A foreign source must not be refused merely for lacking the '
            'SPECTA header.',
      );
      expect(resolved.wasAdapted, isTrue);

      final ForeignSourceAnalysis analysis = resolved.analysis!;
      expect(analysis.format, SourceFormat.adapted);
      expect(analysis.name, 'Community Source');
      expect(analysis.author, 'A Community Developer');
      expect(analysis.version, '2.3.1');
      expect(analysis.contentTypeCode, 'anime');
      expect(analysis.website, 'https://example.invalid');
    });

    test('finds all four contract operations', () {
      final ForeignSourceAnalysis analysis = SourceFormatDetector.analyse(
        _foreignCommonJs(),
      );
      expect(
        analysis.entryPoints,
        containsAll(<String>['search', 'latest', 'details', 'getSources']),
      );
    });

    test('derives capabilities from what the code actually uses', () {
      final ForeignSourceAnalysis analysis = SourceFormatDetector.analyse(
        _foreignCommonJs(),
      );
      // It calls fetch(), so network is genuinely required.
      expect(analysis.usesNetwork, isTrue);
      expect(
        analysis.capabilities,
        containsAll(<ExtensionCapability>[
          ExtensionCapability.network,
          ExtensionCapability.search,
          ExtensionCapability.latest,
          ExtensionCapability.details,
          ExtensionCapability.sources,
        ]),
      );
      // It never logs, so logging must NOT be granted. Adaptation never widens
      // authority beyond what the code demonstrably needs.
      expect(analysis.usesLogging, isFalse);
      expect(
        analysis.capabilities.contains(ExtensionCapability.logging),
        isFalse,
      );
    });

    test('produces a file the NATIVE parser accepts', () {
      // The decisive test: adaptation is only real if the existing native
      // pipeline can then read the result with no changes to that pipeline.
      final ResolvedImportableSource resolved = resolveImportableSource(
        _foreignCommonJs(),
      );
      final ExtensionManifest manifest = ManifestParser.parse(resolved.source);

      expect(manifest.id, startsWith('foreign.'));
      expect(manifest.name, 'Community Source');
      expect(manifest.apiVersion, NativeContractBridge.apiMajor);
      expect(manifest.isCompatible, isTrue);
      expect(
        manifest.capabilities.contains(ExtensionCapability.search),
        isTrue,
      );
    });

    test('preserves the original code verbatim', () {
      // The user's or a third party's code must never be rewritten.
      const String source = 'ORIGINAL_SOURCE_MARKER';
      final String shim = ForeignSourceAdapter.buildShimmedBody(
        SourceFormatDetector.analyse(_foreignCommonJs()),
        source,
      );
      expect(shim, contains(source));
    });

    test('the shim forwards operations and reports absent ones', () {
      final String shim = ForeignSourceAdapter.buildShimmedBody(
        SourceFormatDetector.analyse(_foreignCommonJs()),
        _foreignCommonJs(),
      );
      // Only implemented operations are bridged...
      expect(shim, contains('async search(query, page)'));
      expect(shim, contains('async getSources(reference)'));
      // ...and the bridge reports a real error rather than returning nothing.
      expect(shim, contains('does not implement'));
    });
  });

  group('the generated shim must parse and run in the sandbox', () {
    // Regression, found by EXECUTING the adapter's real output in a JavaScript
    // engine rather than reading it as text: an escaped `}}` in the Dart
    // template emitted a stray `}` that closed `class Extension` before
    // `healthCheck`, so every adapted source died with a SyntaxError at load.
    // Content-only assertions could not see it, because the text was all there.
    String shimFor(String body) => ForeignSourceAdapter.buildShimmedBody(
      SourceFormatDetector.analyse(body),
      body,
    );

    test('braces balance, so the class is never closed early', () {
      for (final String body in <String>[
        _foreignCommonJs(),
        _foreignEsModule(),
      ]) {
        final String text = shimFor(body);
        expect(
          '{'.allMatches(text).length,
          '}'.allMatches(text).length,
          reason: 'unbalanced braces: the sandbox cannot parse this file.',
        );
      }
    });

    test('no member is generated after the class has closed', () {
      final String text = shimFor(_foreignCommonJs());
      expect(
        RegExp(r'^\}[ \t]*\n[ \t]*async ', multiLine: true).hasMatch(text),
        isFalse,
        reason:
            'a method was emitted outside the class body, which is a '
            'syntax error in every JavaScript engine.',
      );
    });

    test('a CommonJS module is given a module object to export into', () {
      // The sandbox defines `SpectaExtension` and nothing else. Without this
      // prelude the imported code's own `module.exports = ...` statement throws
      // ReferenceError before any operation can run.
      final String text = shimFor(_foreignCommonJs());
      expect(text, contains('const __spectaModule = { exports: {} };'));
      expect(text, contains('var module = __spectaModule;'));
      expect(
        text.indexOf('var module = __spectaModule;'),
        lessThan(text.indexOf(_foreignCommonJs())),
        reason:
            'the prelude must be declared before the imported code runs, '
            'not after it.',
      );
    });

    test('an uncapturable export fails honestly instead of recursing', () {
      final String text = shimFor(_foreignCommonJs());
      // Resolving the call target to `this` would invoke the shim's own
      // forwarding method again: unbounded recursion, so the host saw a stack
      // overflow where it should see "this source does not implement X".
      expect(text, isNot(contains('return this;')));
      expect(text, contains('return null;'));
      expect(text, contains('does not implement'));
    });

    test('KNOWN GAP: an ES module is wrapped for a script global that '
        'cannot parse it', () {
      // Characterisation, not endorsement: SPECTA evaluates extensions as
      // plain scripts, where a top-level `export` is a syntax error. The
      // adapter currently ships such a source as if it would run. Recorded in
      // docs/SOURCE_RUN_REPORT.md; the fix is to transform the module or to
      // refuse it at import with a message that says why.
      final String text = shimFor(_foreignEsModule());
      expect(
        RegExp(r'^export ', multiLine: true).hasMatch(text),
        isTrue,
        reason:
            'if ES syntax is ever rewritten out of the wrapper, this '
            'test must be replaced by one that proves the rewrite.',
      );
    });
  });

  group('a foreign ES module is adapted too', () {
    test('class-method operations are detected', () {
      final ForeignSourceAnalysis analysis = SourceFormatDetector.analyse(
        _foreignEsModule(),
      );
      expect(analysis.format, SourceFormat.adapted);
      expect(
        analysis.entryPoints,
        containsAll(<String>['search', 'getSources']),
      );
      // Only the operations the file defines are bridged.
      expect(analysis.entryPoints.contains('latest'), isFalse);
    });

    test('adapts into a natively parseable file', () {
      final ResolvedImportableSource resolved = resolveImportableSource(
        _foreignEsModule(),
      );
      expect(resolved.failure, isNull);
      expect(() => ManifestParser.parse(resolved.source), returnsNormally);
    });
  });

  group('genuinely unrunnable files are refused, with a real reason', () {
    test('plain prose is refused because it is not a JS module', () {
      final ResolvedImportableSource resolved = resolveImportableSource(
        'These are my notes about a streaming site.',
      );
      expect(resolved.failure, isNotNull);
      expect(resolved.failure!.message, contains('not a JavaScript source'));
    });

    test('a JS module with no operations is refused for that reason', () {
      final ResolvedImportableSource resolved = resolveImportableSource(
        'function helper() { return 1; }\nmodule.exports = { helper };',
      );
      expect(resolved.failure, isNotNull);
      expect(resolved.failure!.message, contains('none of the operations'));
    });

    test('an empty file is refused', () {
      expect(resolveImportableSource('   ').failure, isNotNull);
    });

    test('no refusal is ever justified by a missing SPECTA header', () {
      // The central product rule, asserted directly: whatever the reason given,
      // the message must not blame the header format.
      for (final String bad in <String>[
        'These are my notes about a streaming site.',
        'function helper() { return 1; }\nmodule.exports = { helper };',
        '   ',
      ]) {
        final String? message = resolveImportableSource(bad).failure?.message;
        expect(message, isNotNull);
        expect(message, isNot(contains('header')));
        expect(message, isNot(contains('SpectaExtension')));
      }
    });
  });

  group('identity and provenance stay honest', () {
    test('a derived id is stable across runs and namespaced', () {
      final ForeignSourceAnalysis a = SourceFormatDetector.analyse(
        _foreignCommonJs(),
      );
      final ForeignSourceAnalysis b = SourceFormatDetector.analyse(
        _foreignCommonJs(),
      );
      // Stability matters: the id becomes the record id and the node identity,
      // and Dart's String.hashCode is not stable across runs.
      expect(a.id, b.id);
      expect(a.id, startsWith('foreign.community-source.'));
    });

    test('two different bodies with the same name get different ids', () {
      final ForeignSourceAnalysis a = SourceFormatDetector.analyse(
        _foreignCommonJs(),
      );
      final String other = _foreignCommonJs().replaceAll(
        "description: 'A source written for another host.'",
        "description: 'A different body with the same name.'",
      );
      final ForeignSourceAnalysis c = SourceFormatDetector.analyse(other);
      // Different files must not silently replace one another.
      expect(c.id, isNot(a.id));
    });

    test('an unstated version is reported absent, not invented', () {
      final String noVersion = _foreignCommonJs().replaceAll(
        "version: '2.3.1',",
        "buildNumber: '77',",
      );
      final ForeignSourceAnalysis analysis = SourceFormatDetector.analyse(
        noVersion,
      );
      // A fabricated 0.0.0 presented as a real version would be a small lie in
      // the user's source list.
      expect(analysis.version, isNull);
    });

    test('adaptation does not confer trust', () {
      final ResolvedImportableSource resolved = resolveImportableSource(
        _foreignCommonJs(),
      );
      final ExtensionManifest manifest = ManifestParser.parse(resolved.source);
      // No signature was ever supplied, so the green dot must remain absent.
      expect(manifest.hasSignature, isFalse);
      expect(manifest.signature, isNull);
    });
  });

  // ===========================================================================
  // REAL third-party providers.
  //
  // Everything above uses fixtures written to match what SPECTA already
  // understood. These groups use the UNMODIFIED files from a real, independent
  // provider repository, because the original failures were only ever visible
  // against real files: those providers export nothing at all and name their
  // operations `getHome` / `getDetail` / `getVideoSources`.
  // ===========================================================================

  group('a real third-party provider is adapted onto the contract', () {
    late Map<String, String> files;

    setUpAll(() {
      final Directory dir = Directory('test/support/fixtures/third_party');
      if (!dir.existsSync()) {
        fail(
          'The real third-party fixtures are missing from ${dir.path}. See '
          'test/support/fixtures/third_party/README.md for provenance.',
        );
      }
      files = <String, String>{
        for (final FileSystemEntity e in dir.listSync())
          // Only the JavaScript. The folder also holds a README, and a markdown
          // document is not a source file - including it would make this suite
          // assert that a README installs.
          if (e is File && e.path.toLowerCase().endsWith('.js'))
            e.uri.pathSegments.last: e.readAsStringSync(),
      };
    });

    test('every shipped real provider is recognised and adapted', () {
      expect(files.keys, isNotEmpty, reason: 'no fixtures were found to test');
      for (final MapEntry<String, String> entry in files.entries) {
        final ResolvedImportableSource resolved = resolveImportableSource(
          entry.value,
          sourcePath: entry.key,
        );
        expect(
          resolved.failure,
          isNull,
          reason: '${entry.key} was refused: ${resolved.failure?.message}',
        );
        expect(
          resolved.analysis?.format,
          SourceFormat.adapted,
          reason: '${entry.key} should be adapted, not native',
        );
        expect(resolved.wasAdapted, isTrue);
      }
    });

    test('every real provider fills all four contract operations', () {
      for (final MapEntry<String, String> entry in files.entries) {
        final ForeignSourceAnalysis analysis = SourceFormatDetector.analyse(
          entry.value,
        );
        // Each of these files defines search, getHome, getDetail and
        // getVideoSources. If any stop resolving, the source installs and then
        // fails on the first call - the exact bug this covers.
        expect(
          analysis.entryPoints,
          containsAll(<String>['search', 'latest', 'details', 'getSources']),
          reason: '${entry.key} resolved only ${analysis.entryPoints}',
        );
      }
    });

    test('a real provider is mapped onto the names it actually uses', () {
      for (final MapEntry<String, String> entry in files.entries) {
        final Map<String, String> members = SourceFormatDetector.analyse(
          entry.value,
        ).operationMembers;
        // These providers name the operations their own way, so the shim must
        // call THOSE names, not the contract names.
        expect(members['latest'], 'getHome', reason: entry.key);
        expect(members['details'], 'getDetail', reason: entry.key);
        expect(members['getSources'], 'getVideoSources', reason: entry.key);
        // `search` shares a name with the contract and must map to itself.
        expect(members['search'], 'search', reason: entry.key);
      }
    });

    test("the generated shim calls the provider's real function names", () {
      for (final MapEntry<String, String> entry in files.entries) {
        final String source = resolveImportableSource(entry.value).source;
        // The forwarders must name the author's members...
        expect(source, contains("__spectaCall('getHome'"), reason: entry.key);
        expect(source, contains("__spectaCall('getDetail'"), reason: entry.key);
        expect(
          source,
          contains("__spectaCall('getVideoSources'"),
          reason: entry.key,
        );
        // ...and must not call names the file does not define.
        expect(
          source,
          isNot(contains("__spectaCall('latest'")),
          reason: entry.key,
        );
        expect(
          source,
          isNot(contains("__spectaCall('getSources'")),
          reason: entry.key,
        );
      }
    });

    test("a real provider's own body is preserved verbatim", () {
      for (final MapEntry<String, String> entry in files.entries) {
        // Adaptation wraps the author's code; it never edits it.
        expect(
          resolveImportableSource(entry.value).source,
          contains(entry.value),
          reason: entry.key,
        );
      }
    });

    test('a real provider keeps the version it declares about itself', () {
      // Regression: metadata was read one key per line, so a provider returning
      // { name: ..., type: ..., version: '1.0.8' } on ONE line lost its version.
      final ForeignSourceAnalysis anikoto = SourceFormatDetector.analyse(
        files['anikoto.js']!,
      );
      expect(anikoto.name, 'AniKoto');
      expect(anikoto.version, isNotNull);
      expect(anikoto.contentTypeCode, 'anime');
    });
    test('adapting a real provider still confers no trust', () {
      for (final MapEntry<String, String> entry in files.entries) {
        final ExtensionManifest manifest = ManifestParser.parse(
          resolveImportableSource(entry.value).source,
        );
        expect(manifest.hasSignature, isFalse, reason: entry.key);
      }
    });
  });

  group('a JSON repository index is routed, not misread as JavaScript', () {
    /// The real shape of the index that was reported as broken: a root object
    /// with a `sources` array of relative file paths.
    const String zangetsuIndex = '''
{
  "name": "Zangetsu Providers",
  "description": "Streaming sources for the Zangetsu app.",
  "sources": [
    { "id": "anikoto", "name": "AniKoto", "version": "1.0.8",
      "type": "anime", "file": "providers/anikoto.js" },
    { "id": "hdhub4u", "name": "HDHub4u", "version": "1.2.4",
      "type": "movie", "file": "providers/hdhub4u.js" }
  ]
}
''';

    test('is detected as a repository index, not unrecognised JavaScript', () {
      // The bug: `_looksLikeJavaScriptModule` accepted anything starting with
      // `{`, so every JSON index went down the JavaScript path and was refused
      // with "implements none of the operations".
      final ForeignSourceAnalysis analysis = SourceFormatDetector.analyse(
        zangetsuIndex,
      );
      expect(analysis.format, SourceFormat.unrecognised);
      expect(analysis.rejectionReason, contains('repository index'));
    });

    test('is never described as a JavaScript module', () {
      for (final String document in <String>[
        zangetsuIndex,
        '[{"id":"a","file":"a.js"}]',
        '{"sources":[]}',
      ]) {
        final String? reason = SourceFormatDetector.analyse(document)
            .rejectionReason;
        expect(reason, isNotNull);
        expect(reason, isNot(contains('operations')));
        expect(reason, isNot(contains('JavaScript')));
      }
    });

    test('the message reports how many sources it lists', () {
      // Saying "your index holds 2 providers" is far more useful than a bare
      // refusal.
      expect(
        SourceFormatDetector.analyse(zangetsuIndex).rejectionReason,
        contains('2 sources'),
      );
    });

    test(
      'a bare object-literal JavaScript file is still treated as JavaScript',
      () {
        // The JSON check must not swallow real JS, which legitimately starts
        // with `{` as an expression statement.
        const String jsObject = '''
function search(q) { return { results: [] }; }
module.exports = { search };
''';
        final ResolvedImportableSource resolved = resolveImportableSource(
          jsObject,
        );
        expect(resolved.failure, isNull);
        expect(resolved.analysis?.format, SourceFormat.adapted);
      },
    );
  });

  group('operation aliases are spellings, never a provider allowlist', () {
    test('an unknown author using the same names is treated identically', () {
      // No provider name, host or URL appears in the alias table, so nobody is
      // special-cased: it only maps NAMES onto contract slots.
      const String unknown = '''
function search(q, p) { return { results: [] }; }
function getHome() { return { results: [] }; }
function getDetail(ref) { return { id: ref }; }
function getVideoSources(ref) { return { sources: [] }; }
''';
      final ResolvedImportableSource resolved = resolveImportableSource(
        unknown,
      );
      expect(resolved.failure, isNull);
      expect(resolved.analysis?.entryPoints, contains('getSources'));
      expect(
        resolved.analysis?.operationMembers['getSources'],
        'getVideoSources',
      );
    });

    test('a file that implements nothing is still refused', () {
      // Widening the name table must not make everything acceptable.
      final ResolvedImportableSource resolved = resolveImportableSource(
        'function helper() { return 1; }\nmodule.exports = { helper };',
      );
      expect(resolved.failure, isNotNull);
      expect(resolved.failure!.message, contains('none of the operations'));
    });
  });
}
