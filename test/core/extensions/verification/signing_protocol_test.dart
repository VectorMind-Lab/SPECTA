import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/catalogue/extension_type.dart';
import 'package:specta/core/extensions/contract/extension_capability.dart';
import 'package:specta/core/extensions/manifest.dart';
import 'package:specta/core/extensions/verification/signing_protocol.dart';

/// Pins the frozen protocol. If any of these fail, the protocol changed and
/// every existing signature is invalid — which is the point of pinning them.
void main() {
  group('SpectaSigningProtocol', () {
    test('identifies itself as version 1 with the ed25519 scheme', () {
      expect(SpectaSigningProtocol.magic, 'SPECTA-EXT-SIG-V1');
      expect(SpectaSigningProtocol.scheme, 'ed25519');
    });

    test('covers the JavaScript body as well as the metadata', () {
      // The protocol's whole reason for existing: 'capabilities' is signed so
      // permissions cannot be widened silently, and the body is signed by
      // construction because buildPayload requires it.
      expect(
        SpectaSigningProtocol.signedMetadataFields,
        containsAll(<String>['id', 'name', 'version', 'capabilities']),
      );
      // A signature field inside the payload would be self-referential.
      expect(
        SpectaSigningProtocol.signedMetadataFields,
        isNot(contains('signature')),
      );
    });

    test('canonical JSON is sorted, compact and drops absent optionals', () {
      final String canonical = SpectaSigningProtocol.canonicalMetadataJson(
        <String, dynamic>{
          'version': '1.0.0',
          'id': 'com.example.a',
          'name': 'A',
          'description': '',
          'website': null,
          'unrelated': 'ignored',
        },
      );

      expect(canonical, '{"id":"com.example.a","name":"A","version":"1.0.0"}');
      expect(canonical, isNot(contains(' ')));
      expect(canonical, isNot(contains('unrelated')));
    });

    test('canonical JSON is independent of key order', () {
      final String a = SpectaSigningProtocol.canonicalMetadataJson(
        <String, dynamic>{'id': 'x', 'name': 'y', 'version': '1'},
      );
      final String b = SpectaSigningProtocol.canonicalMetadataJson(
        <String, dynamic>{'version': '1', 'name': 'y', 'id': 'x'},
      );
      expect(a, b);
    });

    test(
      'payload is magic + length-prefixed metadata + length-prefixed body',
      () {
        final Map<String, dynamic> metadata = <String, dynamic>{
          'id': 'com.example.a',
          'name': 'A',
          'version': '1.0.0',
        };
        const String body = 'class Extension extends SpectaExtension {}\n';

        final List<int> metadataBytes = utf8.encode(
          SpectaSigningProtocol.canonicalMetadataJson(metadata),
        );
        final List<int> bodyBytes = utf8.encode(body);
        final List<int> expected = <int>[
          ...utf8.encode('SPECTA-EXT-SIG-V1\n'),
          ...utf8.encode('${metadataBytes.length}\n'),
          ...metadataBytes,
          ...utf8.encode('${bodyBytes.length}\n'),
          ...bodyBytes,
        ];

        expect(
          SpectaSigningProtocol.buildPayload(
            metadata: metadata,
            extensionBody: body,
          ),
          expected,
        );
      },
    );

    test('payload is UTF-8, not UTF-16 code units', () {
      final Map<String, dynamic> metadata = <String, dynamic>{
        'id': 'com.example.unicode',
        'name': 'Café 日本語',
        'author': 'José',
      };
      const String body = 'var x = "über";';

      final String canonical = SpectaSigningProtocol.canonicalMetadataJson(
        metadata,
      );
      final List<int> utf8Metadata = utf8.encode(canonical);

      // The two encodings really do differ for this input, so the distinction
      // is not theoretical.
      expect(utf8Metadata, isNot(equals(canonical.codeUnits)));

      final List<int> payload = SpectaSigningProtocol.buildPayload(
        metadata: metadata,
        extensionBody: body,
      );

      final List<int> expected = <int>[
        ...utf8.encode('SPECTA-EXT-SIG-V1\n'),
        ...utf8.encode('${utf8Metadata.length}\n'),
        ...utf8Metadata,
        ...utf8.encode('${utf8.encode(body).length}\n'),
        ...utf8.encode(body),
      ];
      expect(payload, expected);
      expect(utf8.decode(payload), contains('Café 日本語'));
      // The non-ASCII metadata contributes multi-byte sequences, so the payload
      // can only be reproduced by an implementation that encodes UTF-8.
      expect(payload.length, greaterThan(canonical.length));
    });

    test('changing the body changes the payload', () {
      final Map<String, dynamic> metadata = <String, dynamic>{'id': 'a'};
      expect(
        SpectaSigningProtocol.buildPayload(
          metadata: metadata,
          extensionBody: 'one',
        ),
        isNot(
          equals(
            SpectaSigningProtocol.buildPayload(
              metadata: metadata,
              extensionBody: 'two',
            ),
          ),
        ),
      );
    });

    test('the length prefix prevents a metadata/body boundary shift', () {
      // Two different splits that would concatenate identically without length
      // prefixes must produce different payloads.
      final List<int> a = SpectaSigningProtocol.buildPayload(
        metadata: <String, dynamic>{'id': 'ab'},
        extensionBody: 'c',
      );
      final List<int> b = SpectaSigningProtocol.buildPayload(
        metadata: <String, dynamic>{'id': 'a'},
        extensionBody: 'bc',
      );
      expect(a, isNot(equals(b)));
    });

    test('encodeSignature emits the manifest signature format', () {
      final String encoded = SpectaSigningProtocol.encodeSignature(
        List<int>.filled(64, 7),
      );
      expect(encoded.startsWith('ed25519:'), isTrue);
      expect(base64Decode(encoded.substring('ed25519:'.length)).length, 64);
    });
  });

  group('ExtensionManifest signed payload', () {
    test('includes the canonical capabilities declaration', () {
      final ExtensionManifest manifest = ExtensionManifest(
        id: 'com.example.caps',
        name: 'Caps',
        version: '1.0.0',
        author: 'Author',
        apiVersion: 2,
        type: ExtensionContentType.movie,
        signature: null,
        capabilities: const <ExtensionCapability>{
          ExtensionCapability.logging,
          ExtensionCapability.network,
        },
      );

      expect(
        manifest.canonicalMetadataJson(),
        contains('"capabilities":"logging,network"'),
      );
    });

    test('the capability order in the declaration does not matter', () {
      const ExtensionCapability a = ExtensionCapability.network;
      const ExtensionCapability b = ExtensionCapability.logging;

      ExtensionManifest build(Set<ExtensionCapability> caps) =>
          ExtensionManifest(
            id: 'x',
            name: 'x',
            version: '1',
            author: 'x',
            apiVersion: 2,
            type: ExtensionContentType.movie,
            signature: null,
            capabilities: caps,
          );

      expect(
        build(<ExtensionCapability>{a, b}).canonicalMetadataJson(),
        build(<ExtensionCapability>{b, a}).canonicalMetadataJson(),
      );
    });
  });

  group('ManifestParser.extractBody', () {
    test('returns everything after the closing marker line', () {
      const String source =
          '// ==SpectaExtension==\n'
          '// @id com.example.a\n'
          '// ==/SpectaExtension==\n'
          'class Extension {}\n';

      expect(ManifestParser.extractBody(source), 'class Extension {}\n');
    });

    test(
      'handles CRLF line endings without leaving a stray carriage return',
      () {
        const String source =
            '// ==SpectaExtension==\r\n'
            '// @id com.example.a\r\n'
            '// ==/SpectaExtension==\r\n'
            'class Extension {}\r\n';

        expect(ManifestParser.extractBody(source), 'class Extension {}\r\n');
      },
    );

    test('returns the whole source when there is no header block', () {
      const String source = 'var x = 1;';
      expect(ManifestParser.extractBody(source), source);
    });

    test('returns empty when the closing marker is the last line', () {
      const String source = '// ==SpectaExtension==\n// ==/SpectaExtension==';
      expect(ManifestParser.extractBody(source), '');
    });

    test('is unaffected by edits inside the header', () {
      const String before =
          '// ==SpectaExtension==\n'
          '// @id com.example.a\n'
          '// ==/SpectaExtension==\n'
          'body();\n';
      const String after =
          '// ==SpectaExtension==\n'
          '// @id com.example.a\n'
          '// @name Changed\n'
          '// ==/SpectaExtension==\n'
          'body();\n';

      expect(
        ManifestParser.extractBody(before),
        ManifestParser.extractBody(after),
      );
    });
  });
}
