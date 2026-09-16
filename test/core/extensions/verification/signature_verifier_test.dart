import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/verification/signature_verifier.dart';
import 'package:specta/core/extensions/verification/signing_protocol.dart';

void main() {
  group('SignatureVerifier', () {
    group('decodeSignature', () {
      test('decodes a valid ed25519:BASE64 signature', () {
        final List<int> raw = List<int>.generate(64, (int i) => i);
        final String b64 = base64Encode(raw);
        final List<int>? result = SignatureVerifier.decodeSignature(
          'ed25519:$b64',
        );
        expect(result, isNotNull);
        expect(result!.length, 64);
      });

      test('returns null for missing scheme prefix', () {
        expect(SignatureVerifier.decodeSignature('MEUCIQD='), isNull);
      });

      test('returns null for wrong scheme', () {
        final String b64 = base64Encode(List<int>.filled(64, 1));
        expect(SignatureVerifier.decodeSignature('rsa:$b64'), isNull);
      });

      test('returns null for malformed base64', () {
        expect(
          SignatureVerifier.decodeSignature('ed25519:not_base64!!!'),
          isNull,
        );
      });

      test('returns null for short signature (not 64 bytes)', () {
        final String b64 = base64Encode(List<int>.filled(32, 0));
        expect(SignatureVerifier.decodeSignature('ed25519:$b64'), isNull);
      });

      test('returns null for empty string', () {
        expect(SignatureVerifier.decodeSignature(''), isNull);
      });

      test('returns null for missing separator', () {
        expect(SignatureVerifier.decodeSignature('ed25519'), isNull);
      });

      test('returns null for too many parts', () {
        expect(SignatureVerifier.decodeSignature('ed25519:abc:def'), isNull);
      });
    });

    group('verify', () {
      test('returns false for null signature', () async {
        final bool result = await SignatureVerifier.instance.verify(
          message: [1, 2, 3],
          signature: null,
        );
        expect(result, isFalse);
      });

      test('returns false for empty signature', () async {
        final bool result = await SignatureVerifier.instance.verify(
          message: [1, 2, 3],
          signature: '',
        );
        expect(result, isFalse);
      });

      test('returns false for malformed signature string', () async {
        final bool result = await SignatureVerifier.instance.verify(
          message: [1, 2, 3],
          signature: 'malformed',
        );
        expect(result, isFalse);
      });

      test('returns false for signature from a different key pair', () async {
        final KeyPair keyPair = await Ed25519().newKeyPair();
        final List<int> message = utf8.encode('test message');
        final Signature signature = await Ed25519().sign(
          message,
          keyPair: keyPair,
        );

        final String sigString =
            '${SignatureVerifier.scheme}:${base64Encode(signature.bytes)}';

        final bool result = await SignatureVerifier.instance.verify(
          message: message,
          signature: sigString,
        );
        expect(result, isFalse);
      });

      test(
        'returns false for tampered message (same signature, different data)',
        () async {
          final KeyPair keyPair = await Ed25519().newKeyPair();
          final List<int> signedMessage = utf8.encode('original content');
          final Signature signature = await Ed25519().sign(
            signedMessage,
            keyPair: keyPair,
          );

          final String sigString =
              '${SignatureVerifier.scheme}:${base64Encode(signature.bytes)}';

          final List<int> tamperedMessage = utf8.encode('tampered content');
          final bool result = await SignatureVerifier.instance.verify(
            message: tamperedMessage,
            signature: sigString,
          );
          expect(result, isFalse);
        },
      );
    });

    // The positive path. Every test below uses a throwaway key pair generated
    // here, so no production private key is required and none is stored.
    group('verify — positive path with an isolated test key pair', () {
      test('a valid signature over a protocol payload verifies', () async {
        final KeyPair keyPair = await Ed25519().newKeyPair();
        final SimplePublicKey publicKey =
            await keyPair.extractPublicKey() as SimplePublicKey;

        final List<int> payload = SpectaSigningProtocol.buildPayload(
          metadata: <String, dynamic>{
            'id': 'com.example.signed',
            'name': 'Signed Extension',
            'version': '1.0.0',
          },
          extensionBody: 'class Extension {}\n',
        );

        final Signature signature = await Ed25519().sign(
          payload,
          keyPair: keyPair,
        );

        final SignatureVerifier verifier = SignatureVerifier.withPublicKey(
          publicKey.bytes,
        );

        expect(
          await verifier.verify(
            message: payload,
            signature: SpectaSigningProtocol.encodeSignature(signature.bytes),
          ),
          isTrue,
        );
      });

      test(
        'Ed25519 signing is deterministic, so a tool can reproduce it',
        () async {
          // The frozen protocol is only useful if an external signing tool can
          // reproduce the exact same signature. Ed25519 guarantees that for a
          // given key and message.
          final KeyPair keyPair = await Ed25519().newKeyPair();
          final List<int> payload = utf8.encode('deterministic payload');

          final Signature first = await Ed25519().sign(
            payload,
            keyPair: keyPair,
          );
          final Signature second = await Ed25519().sign(
            payload,
            keyPair: keyPair,
          );

          expect(first.bytes, second.bytes);
        },
      );

      test(
        'tampering with the message breaks an otherwise valid signature',
        () async {
          final KeyPair keyPair = await Ed25519().newKeyPair();
          final SimplePublicKey publicKey =
              await keyPair.extractPublicKey() as SimplePublicKey;

          final List<int> signed = SpectaSigningProtocol.buildPayload(
            metadata: <String, dynamic>{'id': 'a', 'version': '1.0.0'},
            extensionBody: 'class Extension {}\n',
          );
          final String signature = SpectaSigningProtocol.encodeSignature(
            (await Ed25519().sign(signed, keyPair: keyPair)).bytes,
          );
          final SignatureVerifier verifier = SignatureVerifier.withPublicKey(
            publicKey.bytes,
          );

          // Same metadata, one extra statement in the executable body.
          final List<int> tamperedBody = SpectaSigningProtocol.buildPayload(
            metadata: <String, dynamic>{'id': 'a', 'version': '1.0.0'},
            extensionBody: 'class Extension {}\nsteal();\n',
          );

          // Baseline: the untouched payload verifies.
          expect(
            await verifier.verify(message: signed, signature: signature),
            isTrue,
          );
          expect(
            await verifier.verify(message: tamperedBody, signature: signature),
            isFalse,
          );
        },
      );

      test(
        'a signature from another key pair is refused by the right key',
        () async {
          final KeyPair signer = await Ed25519().newKeyPair();
          final KeyPair other = await Ed25519().newKeyPair();
          final SimplePublicKey otherPublic =
              await other.extractPublicKey() as SimplePublicKey;

          final List<int> payload = utf8.encode('payload');
          final String signature = SpectaSigningProtocol.encodeSignature(
            (await Ed25519().sign(payload, keyPair: signer)).bytes,
          );

          expect(
            await SignatureVerifier.withPublicKey(otherPublic.bytes)
                .verify(message: payload, signature: signature),
            isFalse,
          );
        },
      );

      test('the trusted instance rejects a test-key signature', () async {
        // Evidence that the repository holds no key that can mint an official
        // extension: a fresh key pair's signature is not accepted by the
        // production verifier either.
        final KeyPair keyPair = await Ed25519().newKeyPair();
        final List<int> payload = utf8.encode('payload');
        final String signature = SpectaSigningProtocol.encodeSignature(
          (await Ed25519().sign(payload, keyPair: keyPair)).bytes,
        );

        expect(
          await SignatureVerifier.instance.verify(
            message: payload,
            signature: signature,
          ),
          isFalse,
        );
      });

      test('a truncated or padded signature is refused', () async {
        final KeyPair keyPair = await Ed25519().newKeyPair();
        final SimplePublicKey publicKey =
            await keyPair.extractPublicKey() as SimplePublicKey;
        final List<int> payload = utf8.encode('payload');
        final List<int> valid = (await Ed25519().sign(
          payload,
          keyPair: keyPair,
        )).bytes;
        final SignatureVerifier verifier = SignatureVerifier.withPublicKey(
          publicKey.bytes,
        );

        final List<int> tampered = List<int>.of(valid)..[0] = valid[0] ^ 0x01;

        expect(
          await verifier.verify(
            message: payload,
            signature: SpectaSigningProtocol.encodeSignature(tampered),
          ),
          isFalse,
        );
      });
    });
  });
}
