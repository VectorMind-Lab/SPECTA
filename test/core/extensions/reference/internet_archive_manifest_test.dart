@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/catalogue/extension_type.dart';
import 'package:specta/core/extensions/contract/extension_capability.dart';
import 'package:specta/core/extensions/manifest.dart';

/// Phase 2I — the reference extension's INSTALL-TIME contract.
///
/// This suite needs no JavaScript engine and therefore never skips: it is the
/// deterministic half of the Phase 2I verification, and it is what the default
/// `flutter test` run always covers. The executable half (real QuickJS) lives
/// in `internet_archive_engine_test.dart` and is skipped when the bridge is
/// absent, honestly reported as unverified.
///
/// It also carries the ARCHITECTURAL GUARD for rule 0.7: SPECTA Core must stay
/// provider-agnostic, so no provider-specific knowledge may appear anywhere in
/// `lib/`.
const String _referenceExtensionPath = 'extensions/internet_archive_reference.js';
const String _expectedId = 'org.specta.reference.internetarchive';

/// Markers that would mean provider-specific knowledge leaked into Core.
const List<String> _forbiddenCoreMarkers = <String>[
  'archive.org',
  'internetarchive',
  'internet archive',
  'mediatype:movies',
  'charlie_chaplin',
  'primeflix',
  'vidrock',
  'advancedsearch.php',
];

void main() {
  late String source;
  late ExtensionManifest manifest;

  setUpAll(() {
    source = File(_referenceExtensionPath).readAsStringSync();
    manifest = ManifestParser.parse(source);
  });

  group('Reference extension manifest', () {
    test('is a complete, API-compatible manifest', () {
      expect(manifest.id, _expectedId);
      expect(manifest.name, 'Internet Archive (Reference)');
      expect(manifest.version, '1.0.0');
      expect(manifest.apiVersion, SpectaApiVersion.current);
      expect(manifest.isApiCompatible, isTrue);
    });

    test('declares movie content only, matching what it can actually answer',
        () {
      expect(manifest.type, ExtensionContentType.movie);
    });

    test('declares exactly the capabilities it needs — no more', () {
      // Least privilege, asserted rather than assumed. `sources` covers both
      // getSources() and refreshSource(); `logging` is used by load().
      expect(
        manifest.capabilities,
        <ExtensionCapability>{
          ExtensionCapability.network,
          ExtensionCapability.logging,
          ExtensionCapability.search,
          ExtensionCapability.latest,
          ExtensionCapability.details,
          ExtensionCapability.sources,
        },
      );
    });

    test('is unsigned, so it can never be classified Official', () {
      // The production private key is not in this repository and must never be.
      // The reference extension is therefore expected to install as unverified
      // — and the engine suite asserts that through the real manager.
      expect(manifest.hasSignature, isFalse);
    });

    test('implements every operation its declared capabilities imply', () {
      const List<String> requiredOperations = <String>[
        'async load()',
        'async capabilities()',
        'async search(',
        'async latest(',
        'async details(',
        'async getSources(',
        'async refreshSource(',
        'async healthCheck()',
        'async shutdown()',
      ];
      for (final String operation in requiredOperations) {
        expect(
          source.contains(operation),
          isTrue,
          reason: 'the extension must implement $operation',
        );
      }
      // The runtime instantiates a class named exactly `Extension`.
      expect(source.contains('class Extension extends SpectaExtension'), isTrue);
    });

    test('carries no credential and no authentication path', () {
      // A reference extension for a PUBLIC provider must not ship a key, and
      // must not contain a mechanism for one. This is a guard, not a formality:
      // a hardcoded token here would be committed to a public repository.
      for (final String marker in <String>[
        'api_key',
        'apikey',
        'Authorization',
        'Bearer ',
        'password',
        'secret',
        'token',
      ]) {
        expect(
          source.toLowerCase().contains(marker.toLowerCase()),
          isFalse,
          reason: 'the reference extension must not contain "$marker"',
        );
      }
    });

    test('sends every request through the sandbox request() channel', () {
      // No fetch/XHR/native access exists in the sandbox anyway; this asserts
      // the extension does not try, and that its only network entry point is
      // the controlled one.
      expect(source.contains('this.request('), isTrue);
      for (final String forbidden in <String>[
        'fetch(',
        'XMLHttpRequest',
        'require(',
        'process.',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason: 'the sandbox exposes no "$forbidden" and the extension must '
              'not attempt to use one',
        );
      }
    });
  });

  group('Core provider-agnosticism (rule 0.7 architectural guard)', () {
    test('no provider-specific knowledge exists anywhere in lib/', () {
      final List<String> offenders = <String>[];
      final List<File> dartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList();

      expect(
        dartFiles.length,
        greaterThan(50),
        reason: 'the scan must actually be looking at the source tree',
      );

      for (final File file in dartFiles) {
        final String body = file.readAsStringSync();
        final String lower = body.toLowerCase();
        for (final String marker in _forbiddenCoreMarkers) {
          if (lower.contains(marker)) {
            offenders.add('${file.path} contains "$marker"');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'SPECTA Core must not know any provider. Remove this extension and '
            'install another compatible one: Core must need no change. '
            'Offenders: $offenders',
      );
    });

    test('the generic source model is unchanged: mp4 and hls only', () {
      // The reference provider also publishes Ogg/MPEG2/DivX derivatives. The
      // contract deliberately has no slot for them, and the reference
      // extension reports only MP4 rather than widening the Core model.
      expect(
        File('lib/core/extensions/contract/extension_source.dart')
            .readAsStringSync()
            .contains('DASH is deliberately NOT included'),
        isTrue,
      );
    });
  });
}
