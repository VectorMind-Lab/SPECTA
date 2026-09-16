import 'dart:convert';
import 'dart:typed_data';

/// The frozen SPECTA extension signing protocol, version 1.
///
/// This file is the single normative definition of *what a SPECTA extension
/// signature covers*. Any external signing tool must reproduce these bytes
/// exactly, or the resulting signature will not verify.
///
/// ## What is signed
///
/// The signed payload is a byte string built from two parts:
///
/// 1. the extension's **manifest metadata**, as canonical JSON, and
/// 2. the extension's **JavaScript body** — the code that actually executes.
///
/// Covering the body is deliberate. A signature over metadata alone would
/// authenticate an extension's name and version while leaving the executable
/// code free to change, which is worse than no coverage at all because the
/// result still reads as "official".
///
/// ## Exact byte layout
///
/// Concatenate, in this order, with nothing else added:
///
/// ```
/// 1.  ASCII  "SPECTA-EXT-SIG-V1"          (19 bytes, no trailing newline yet)
/// 2.  LF     0x0A
/// 3.  ASCII  decimal byte length of part 4, no padding
/// 4.  LF     0x0A
/// 5.  UTF-8  the canonical metadata JSON  (exactly `part 3` bytes)
/// 6.  ASCII  decimal byte length of part 8, no padding
/// 7.  LF     0x0A
/// 8.  UTF-8  the extension body           (exactly `part 6` bytes)
/// ```
///
/// The two length prefixes make the concatenation unambiguous: without them a
/// crafted manifest could shift the boundary between metadata and body. Because
/// part 5 is length-delimited, its JSON needs no trailing newline.
///
/// ## Canonical metadata JSON
///
/// * an object whose keys are the [signedMetadataFields] that are present;
/// * keys sorted by Unicode code point (ascending);
/// * optional fields whose value is null or the empty string are omitted;
/// * compact separators — no spaces, no indentation, no newlines;
/// * string values escaped by `dart:convert`'s `JsonEncoder`, which leaves
///   non-ASCII characters as literal characters (so the following UTF-8 encode
///   produces real UTF-8, not an escaped ASCII approximation).
///
/// ## Encoding
///
/// Parts 5 and 8 are UTF-8. This is a hard requirement: the earlier
/// implementation signed `String.codeUnits`, which is UTF-16 and therefore
/// produces different bytes from UTF-8 for any non-ASCII metadata (an accented
/// author name, a CJK title). Two implementations of "the same" protocol could
/// not have agreed on it.
///
/// ## Signature encoding
///
/// `ed25519:<base64 of the 64 raw Ed25519 signature bytes>`
///
/// ## Public key representation
///
/// The raw 32 Ed25519 public key bytes, base64-encoded, as published in
/// [TrustedKeys.publicKeyBase64]. No DER/PEM wrapper is used.
///
/// ## Verification procedure
///
/// 1. Read the `.js` file as UTF-8 text.
/// 2. Parse the `// ==SpectaExtension==` header into the metadata fields.
/// 3. Take the body to be the text after the header's closing marker line
///    (`ManifestParser.extractBody`).
/// 4. Build the payload with [buildPayload].
/// 5. Verify the `@signature` value against that payload using Ed25519 and the
///    published public key ([SignatureVerifier.verify]).
abstract final class SpectaSigningProtocol {
  /// Protocol identifier. Changing anything in this file's layout requires a
  /// new identifier; it is part of the signed payload precisely so a future
  /// version cannot be confused with this one.
  static const String magic = 'SPECTA-EXT-SIG-V1';

  /// Signature scheme prefix used in the manifest `@signature` field.
  static const String scheme = 'ed25519';

  /// Manifest fields covered by the signature, in canonical sort order.
  ///
  /// `signature` is excluded (a signature cannot cover itself), and
  /// `capabilities` is included: what an extension is allowed to do must not be
  /// editable without invalidating its signature.
  static const List<String> signedMetadataFields = <String>[
    'apiVersion',
    'author',
    'capabilities',
    'description',
    'icon',
    'id',
    'lang',
    'name',
    'type',
    'version',
    'website',
  ];

  /// Prefix bytes, including the terminator newline.
  static List<int> get prefixBytes => utf8.encode('$magic\n');

  /// Renders [metadata] as the canonical JSON described in the class docs.
  ///
  /// Only [signedMetadataFields] are considered; unknown keys are dropped so
  /// that an unrelated header field can never silently change the payload.
  static String canonicalMetadataJson(Map<String, dynamic> metadata) {
    final Map<String, dynamic> considered = <String, dynamic>{};
    for (final String field in signedMetadataFields) {
      final dynamic value = metadata[field];
      if (value == null) continue;
      if (value is String && value.isEmpty) continue;
      considered[field] = value;
    }

    final List<String> sortedKeys = considered.keys.toList()..sort();
    final Map<String, dynamic> sorted = <String, dynamic>{
      for (final String key in sortedKeys) key: considered[key],
    };
    return jsonEncode(sorted);
  }

  /// Builds the exact bytes that are signed and verified.
  ///
  /// [metadata] supplies the manifest fields; [extensionBody] is the extension
  /// source after the manifest header block. Both are encoded as UTF-8.
  static List<int> buildPayload({
    required Map<String, dynamic> metadata,
    required String extensionBody,
  }) {
    final Uint8List metadataBytes = utf8.encode(
      canonicalMetadataJson(metadata),
    );
    final Uint8List bodyBytes = utf8.encode(extensionBody);

    final BytesBuilder builder = BytesBuilder(copy: false)
      ..add(prefixBytes)
      ..add(utf8.encode('${metadataBytes.length}\n'))
      ..add(metadataBytes)
      ..add(utf8.encode('${bodyBytes.length}\n'))
      ..add(bodyBytes);
    return builder.takeBytes();
  }

  /// Wraps raw Ed25519 signature bytes in the manifest signature format.
  static String encodeSignature(List<int> signatureBytes) =>
      '$scheme:${base64Encode(signatureBytes)}';
}
