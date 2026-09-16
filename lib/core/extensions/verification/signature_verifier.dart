import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'signing_protocol.dart';
import 'trusted_keys.dart';

/// Verifies Ed25519 signatures over a [SpectaSigningProtocol] payload and
/// classifies extension trust.
///
/// [instance] verifies against SPECTA's published public key. Use
/// [SignatureVerifier.withPublicKey] to verify against another key — tests use
/// it with a throwaway key pair, because the production private key is
/// deliberately absent from this repository.
///
/// Classification rules:
/// * Valid Ed25519 signature with the expected public key → Official
/// * Missing signature → Unverified
/// * Invalid signature → Unverified
/// * Modified signed content → Unverified
class SignatureVerifier {
  SignatureVerifier._(this.publicKey);

  /// A verifier bound to an explicit Ed25519 public key (raw 32 bytes).
  factory SignatureVerifier.withPublicKey(List<int> publicKeyBytes) =>
      SignatureVerifier._(
        SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
      );

  /// The verifier bound to SPECTA's trusted public key.
  static final SignatureVerifier instance = SignatureVerifier._(
    SimplePublicKey(TrustedKeys.publicKeyBytes, type: KeyPairType.ed25519),
  );

  /// The public key this instance verifies against.
  final SimplePublicKey publicKey;

  final Ed25519 _ed25519 = Ed25519();

  /// The signature scheme prefix used in manifest `@signature` fields.
  static const String scheme = SpectaSigningProtocol.scheme;

  /// Verifies [signature] over [message] against [publicKey].
  ///
  /// [message] is the exact signed payload, built with
  /// [SpectaSigningProtocol.buildPayload] — never a string's code units.
  /// [signature] is the raw `@signature` value from the manifest
  /// (e.g. `ed25519:MEU...`).
  Future<bool> verify({
    required List<int> message,
    required String? signature,
  }) async {
    if (signature == null || signature.isEmpty) return false;

    final List<int>? signatureBytes = decodeSignature(signature);
    if (signatureBytes == null) return false;

    final Signature sig = Signature(signatureBytes, publicKey: publicKey);
    try {
      return await _ed25519.verify(message, signature: sig);
    } catch (_) {
      return false;
    }
  }

  /// Parses a raw [`ed25519:BASE64`] signature string into raw bytes.
  ///
  /// Returns null for malformed input.
  static List<int>? decodeSignature(String signature) {
    final List<String> parts = signature.split(':');
    if (parts.length != 2 || parts[0] != scheme) return null;
    final List<int> bytes;
    try {
      bytes = base64Decode(parts[1]);
    } on FormatException {
      return null;
    }
    if (bytes.length != 64) return null;
    return bytes;
  }
}
