import 'dart:convert';

/// SPECTA's trusted Ed25519 public key for extension signature verification.
///
/// The corresponding private signing key is NEVER stored in this repository
/// or the application.  It lives only on an offline, secured signing machine,
/// in a directory outside this repository that is never committed.
/// Production signing must be performed on a properly secured, air-gapped
/// machine.
///
/// Trust classification flow:
/// 1. Parse the extension manifest `@signature` field (`ed25519:BASE64`).
/// 2. Decode the base64 signature into 64 raw bytes.
/// 3. Verify against [publicKeyBytes] using Ed25519.
/// 4. Valid -> official; invalid/missing -> unverified.
abstract final class TrustedKeys {
  /// Base64-encoded Ed25519 public key.
  ///
  /// Generated for this SPECTA Phase 1 build on 2026-09-15.
  /// The private key was generated alongside it and stored outside the
  /// repository, in an offline directory that is never committed.
  static const String publicKeyBase64 =
      'uDm0fWmDu0dQ/32eXEw7O78VhqEA72YYcEpXPECxAYc=';

  /// Decoded raw 32-byte Ed25519 public key bytes.
  static List<int> get publicKeyBytes => base64Decode(publicKeyBase64);

  /// Signature scheme identifier used in manifest `@signature` fields.
  static const String ed25519Scheme = 'ed25519';
}
