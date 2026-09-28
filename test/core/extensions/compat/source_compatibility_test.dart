import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/compat/foreign_source_adapter.dart';
import 'package:specta/core/extensions/compat/source_format_detector.dart';
import 'package:specta/core/extensions/contract/extension_capability.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manifest.dart';

/// A foreign source in the shape another host's extension systems commonly use:
/// a CommonJS module that declares its own metadata and exports operations as
/// object members. It has no SPECTA header at all.
String _foreignCommonJs({String name = 'Community Source'}) => '''
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
const String nativeSource = '// ==SpectaExtension==\n'
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
      expect(manifest.capabilities.contains(ExtensionCapability.search), isTrue);
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

  group('a foreign ES module is adapted too', () {
    test('class-method operations are detected', () {
      final ForeignSourceAnalysis analysis = SourceFormatDetector.analyse(
        _foreignEsModule(),
      );
      expect(analysis.format, SourceFormat.adapted);
      expect(analysis.entryPoints, containsAll(<String>['search', 'getSources']));
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
}