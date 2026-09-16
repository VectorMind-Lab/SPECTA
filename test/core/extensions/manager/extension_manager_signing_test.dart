import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/in_memory_extension_registry.dart';
import 'package:specta/core/extensions/manifest.dart';
import 'package:specta/core/extensions/verification/signature_verifier.dart';
import 'package:specta/core/extensions/verification/signing_protocol.dart';

/// End-to-end trust classification: sign a real extension source with a
/// throwaway key pair, then import it through the manager.
///
/// The throwaway key pair is generated per test. No production private key is
/// used, stored, or required, and the outcome is checked against a verifier
/// bound to the same throwaway public key.
const String _body = '''
class Extension extends SpectaExtension {
  async search(query) { return []; }
}
''';

String _source({
  String id = 'com.example.signed',
  String name = 'Signed Extension',
  String version = '1.0.0',
  String capabilities = 'network,search',
  String? signature,
  String body = _body,
}) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('// ==SpectaExtension==')
    ..writeln('// @id $id')
    ..writeln('// @name $name')
    ..writeln('// @version $version')
    ..writeln('// @author Test Author')
    ..writeln('// @apiVersion 2')
    ..writeln('// @type movies_series');
  if (capabilities.isNotEmpty) {
    buffer.writeln('// @capabilities $capabilities');
  }
  if (signature != null) {
    buffer.writeln('// @signature $signature');
  }
  buffer
    ..writeln('// ==/SpectaExtension==')
    ..write(body);
  return buffer.toString();
}

/// Signs [source] exactly as an external signing tool would: parse the header,
/// build the protocol payload over metadata + executable body, sign, and write
/// the `@signature` field back into the header.
Future<String> _sign(String source, KeyPair keyPair) async {
  final ExtensionManifest manifest = ManifestParser.parse(source);
  final List<int> payload = manifest.buildSignedPayload(
    extensionBody: ManifestParser.extractBody(source),
  );
  final Signature signature = await Ed25519().sign(payload, keyPair: keyPair);
  return source.replaceFirst(
    '// ==/SpectaExtension==',
    '// @signature '
        '${SpectaSigningProtocol.encodeSignature(signature.bytes)}\n'
        '// ==/SpectaExtension==',
  );
}

Future<SimplePublicKey> _publicKeyOf(KeyPair keyPair) async =>
    await keyPair.extractPublicKey() as SimplePublicKey;

void main() {
  late InMemoryExtensionRegistry registry;
  late KeyPair keyPair;
  late ExtensionManager manager;

  setUp(() async {
    registry = InMemoryExtensionRegistry();
    keyPair = await Ed25519().newKeyPair();
    manager = ExtensionManager(
      registry: registry,
      verifier: SignatureVerifier.withPublicKey(
        (await _publicKeyOf(keyPair)).bytes,
      ),
    );
  });

  Future<TrustLevel> importTrust(String source) async {
    final SpectaResult<ExtensionRecord> result = await manager.importFromSource(
      extensionId: 'test.signed',
      jsCode: source,
      targetPath: 'ignored.js',
    );
    expect(result.isOk, isTrue, reason: result.failureOrNull?.message);
    return result.valueOrNull!.trustLevel;
  }

  group('a validly signed extension is official', () {
    test('signature produced by the matching private key verifies', () async {
      final String signed = await _sign(_source(), keyPair);

      expect(await importTrust(signed), TrustLevel.official);
    });

    test('the record keeps the signature for later re-verification', () async {
      final String signed = await _sign(_source(), keyPair);
      final SpectaResult<ExtensionRecord> result = await manager
          .importFromSource(
            extensionId: 'test.signed',
            jsCode: signed,
            targetPath: 'ignored.js',
          );

      expect(result.valueOrNull!.signature, startsWith('ed25519:'));
      expect(result.valueOrNull!.signature, isNotNull);
    });

    test('an unsigned extension is unverified', () async {
      expect(await importTrust(_source()), TrustLevel.unverified);
    });
  });

  group('tampering invalidates the signature', () {
    test('a modified JavaScript body is unverified', () async {
      final String signed = await _sign(_source(), keyPair);
      // Same header, same signature, one extra statement in the executable body.
      final String tampered = signed.replaceFirst(
        'return [];',
        'return []; // exfiltrate();',
      );

      expect(tampered, isNot(equals(signed)));
      expect(await importTrust(tampered), TrustLevel.unverified);
    });

    test('appending code after the body is unverified', () async {
      final String signed = await _sign(_source(), keyPair);
      expect(
        await importTrust('$signed\nstealCredentials();\n'),
        TrustLevel.unverified,
      );
    });

    test('a modified manifest field is unverified', () async {
      final String signed = await _sign(_source(), keyPair);
      final String tampered = signed.replaceFirst(
        '// @name Signed Extension',
        '// @name A Different Extension',
      );

      expect(await importTrust(tampered), TrustLevel.unverified);
    });

    test('a modified version is unverified', () async {
      final String signed = await _sign(_source(), keyPair);
      expect(
        await importTrust(
          signed.replaceFirst('// @version 1.0.0', '// @version 9.9.9'),
        ),
        TrustLevel.unverified,
      );
    });

    test('escalating capabilities is unverified', () async {
      // The security property the protocol exists for: an extension cannot
      // widen its own permissions while keeping a valid signature.
      final String signed = await _sign(_source(), keyPair);
      final String escalated = signed.replaceFirst(
        '// @capabilities network,search',
        '// @capabilities network,search,sources,latest,details',
      );

      expect(escalated, isNot(equals(signed)));
      expect(await importTrust(escalated), TrustLevel.unverified);
    });

    test('adding a capability that was absent is unverified', () async {
      final String signed = await _sign(_source(capabilities: ''), keyPair);
      expect(
        await importTrust(
          signed.replaceFirst(
            '// @author Test Author',
            '// @author Test Author\n// @capabilities network',
          ),
        ),
        TrustLevel.unverified,
      );
    });

    test(
      'replaying a signature onto a different extension id is unverified',
      () async {
        final String signed = await _sign(_source(), keyPair);
        final String replayed = signed.replaceFirst(
          '// @id com.example.signed',
          '// @id com.example.other',
        );

        expect(await importTrust(replayed), TrustLevel.unverified);
      },
    );
  });

  group('signature rejection', () {
    test('a signature from a different key pair is unverified', () async {
      final KeyPair other = await Ed25519().newKeyPair();
      final String signedByOther = await _sign(_source(), other);

      expect(await importTrust(signedByOther), TrustLevel.unverified);
    });

    test('a malformed signature value is unverified', () async {
      expect(
        await importTrust(_source(signature: 'ed25519:not-valid-base64!!!')),
        TrustLevel.unverified,
      );
      expect(
        await importTrust(_source(signature: 'rsa:AAAA')),
        TrustLevel.unverified,
      );
    });

    test('a 64-byte signature that is simply wrong is unverified', () async {
      expect(
        await importTrust(_source(signature: 'ed25519:${'A' * 88}')),
        TrustLevel.unverified,
      );
    });
  });

  group("the default verifier does not accept a test key's signature", () {
    test('importing through the production verifier yields unverified', () async {
      // Evidence that no key capable of minting an official extension is
      // reachable from this repository: the manager's default verifier is bound
      // to SPECTA's published key, and a throwaway key's signature fails it.
      final ExtensionManager productionVerifierManager = ExtensionManager(
        registry: InMemoryExtensionRegistry(),
      );
      final String signed = await _sign(_source(), keyPair);

      final SpectaResult<ExtensionRecord> result =
          await productionVerifierManager.importFromSource(
            extensionId: 'test.signed',
            jsCode: signed,
            targetPath: 'ignored.js',
          );

      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.trustLevel, TrustLevel.unverified);
    });
  });

  group('import never rejects on trust, it classifies', () {
    test('an unverified extension still installs and is enabled', () async {
      final SpectaResult<ExtensionRecord> result = await manager
          .importFromSource(
            extensionId: 'test.unverified',
            jsCode: _source(),
            targetPath: 'ignored.js',
          );

      expect(result.isOk, isTrue);
      final ExtensionRecord record = result.valueOrNull!;
      expect(record.trustLevel, TrustLevel.unverified);
      expect(record.enabled, isTrue);
      expect(await registry.getById('test.unverified'), isNotNull);
    });
  });
}
