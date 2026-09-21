/// The single SPECTA title-key normalization rule.
///
/// Phase 2G-C pre-flight (§36.1): discovery's `_keyTitle` and metadata's
/// `_keyTitle` were two copies of the same rule and had drifted in no way yet
/// but were ONE BUG away from disagreeing — and both used `RegExp(r'[^\w\s]')`,
/// where Dart's `\w` matches ASCII `[A-Za-z0-9_]` only. Every non-ASCII letter
/// was therefore replaced with a space, so Japanese/Korean/Chinese/Arabic/
/// Cyrillic titles normalized to an EMPTY key ("Amélie" became "am lie"), all
/// such titles with the same type and year collided into one identity, and the
/// discovery dedup / library / watch-progress / download identities built on
/// that key collided with them.
///
/// This library is now the ONLY implementation. Discovery and metadata must
/// call it — never re-derive the rule locally.
///
/// Rules (deliberately simple, deterministic, and backward compatible):
///
/// 1. lowercase;
/// 2. replace every character that is NOT a Unicode letter (`\p{L}`), digit
///    (`\p{N}`), underscore, or whitespace with a space (Unicode-aware, so
///    non-Latin letters and accented Latin letters are KEPT, not stripped);
/// 3. collapse whitespace runs to one space and trim;
/// 4. EMPTY-RESULT FALLBACK: if the result would be empty (a title made only
///    of symbols/punctuation), fall back to the trimmed lowercase original —
///    two different titles must never share an empty key.
///
/// Backward compatibility: for pure-ASCII titles this function produces
/// BYTE-IDENTICAL output to the old ASCII-`\w` implementation (the only
/// characters the old rule kept that the new rule would strip are none: ASCII
/// letters, digits, underscore and whitespace are all kept here too), so
/// persisted keys for ASCII titles remain valid. Proven by a golden test over
/// a varied ASCII set. Keys for non-ASCII titles DO change (they were wrong);
/// see the Phase 2G-C pre-flight report for the persisted-data impact analysis.
///
/// The `|` separator can never occur in the title part (it is not a letter,
/// digit, underscore or whitespace), so the identity key
/// `title|type|year` stays parseable exactly as before.
abstract final class TitleKey {
  /// Everything that is not a Unicode letter, digit, underscore or whitespace.
  static final RegExp _nonKeyCharacters = RegExp(
    r'[^\p{L}\p{N}_\s]',
    unicode: true,
  );

  /// Any run of whitespace (the old rule's collapse step, unchanged).
  static final RegExp _whitespace = RegExp(r'\s+');

  /// Normalizes [title] into the case/punctuation/whitespace-insensitive
  /// title key. Never returns an empty string for a non-blank input, and the
  /// result NEVER contains `|` or a whitespace run — so the identity key
  /// `title|type|year` stays exactly parseable (the resume path depends on
  /// that; see `discoveryItemFor`).
  static String normalize(String title) {
    final String lowered = title.toLowerCase();
    final String collapsed = lowered
        .replaceAll(_nonKeyCharacters, ' ')
        .replaceAll(_whitespace, ' ')
        .trim();
    if (collapsed.isNotEmpty) return collapsed;

    // Empty-result fallback (§36.1.3): a symbols-only title must not produce
    // an empty key that would collide with every other symbols-only title.
    // The fallback keeps the title's own characters so two different
    // symbol-only titles stay distinct — except `|` itself, which would break
    // the key format, and whitespace runs, which would break trimming.
    final String safe = lowered
        .replaceAll('|', ' ')
        .replaceAll(_whitespace, ' ')
        .trim();
    if (safe.isNotEmpty) return safe;

    // A title made only of pipe characters/whitespace: a deterministic,
    // non-empty, pipe-free sentinel (stable FNV-1a over the UTF-16 units).
    return 't${_fnv1a32(lowered).toRadixString(36)}';
  }

  static int _fnv1a32(String input) {
    int hash = 0x811c9dc5;
    for (final int unit in input.codeUnits) {
      hash ^= unit & 0xFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
      hash ^= (unit >> 8) & 0xFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// Builds the evidence identity key for a work:
  /// `<keyTitle>|<typeCode>|<year or "none">`.
  ///
  /// The FORMAT is unchanged (see the 2C/2F identity decisions); only the
  /// title normalization inside it is shared and Unicode-aware now.
  static String identityKey({
    required String title,
    required String typeCode,
    required int? year,
  }) =>
      '${normalize(title)}|$typeCode|${year?.toString() ?? 'none'}';
}
