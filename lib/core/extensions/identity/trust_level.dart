/// Trust classification for an extension.
///
/// Determines the provenance of an extension based on signature verification.
/// File location never determines trust — only the cryptographic signature
/// does.  A manually imported extension that carries a valid trusted signature
/// is [TrustLevel.official].
///
/// Classification rules:
/// * Valid Ed25519 signature with SPECTA's trusted public key → [official]
/// * Missing signature → [unverified]
/// * Invalid signature → [unverified]
/// * Modified signed content → [unverified]
enum TrustLevel {
  /// Signed by SPECTA's trusted Ed25519 private key.
  official('official'),

  /// Unsigned or signature verification failed.
  unverified('unverified');

  const TrustLevel(this.code);

  /// Stable string identifier persisted in the registry.
  final String code;

  static TrustLevel? fromCode(String code) {
    for (final TrustLevel level in TrustLevel.values) {
      if (level.code == code) return level;
    }
    return null;
  }
}
