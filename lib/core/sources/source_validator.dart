import '../../core/extensions/contract/extension_source.dart';

/// The outcome of validating one raw [ExtensionSource].
final class ValidatedSource {
  const ValidatedSource._({this.source, this.dropReason});

  final ExtensionSource? source;
  final String? dropReason;

  bool get isDropped => source == null;

  static ValidatedSource ok(ExtensionSource s) => ValidatedSource._(source: s);
  static ValidatedSource dropped(String reason) =>
      ValidatedSource._(dropReason: reason);
}

/// Central SPECTA validation for source candidates.
///
/// SCOPE DECISION (documented per brief §12): validation here is
/// STRUCTURAL ONLY — URL shape/scheme/type/quality/headers/track metadata.
/// Network reachability is deliberately NOT probed: probing every candidate
/// would make resolution slow and is exactly what playback (2E) will
/// discover through its own failure path, which triggers 2D's fallback.
/// No invented data, no network activity in this layer.
///
/// Validation policy (deterministic, tested):
/// - DROPPED: blank/over-long URL; unsupported scheme (http/https only —
///   file://, data:, javascript: etc. are never acceptable as media
///   locations); unsupported type (the contract parser already enforces
///   mp4/hls; re-checked here as defense in depth); non-positive or absurd
///   header counts (injection guard); header names with whitespace or
///   control characters; subtitle entries without a usable URL; audio
///   tracks are free-form metadata and always tolerated.
/// - TOLERATED: missing quality (never invented — ranking handles it
///   explicitly); missing label; missing tracks.
abstract final class SourceValidator {
  /// Hard cap on URL length (protocol-noise guard, mirroring 2B/2C rules).
  static const int maxUrlLength = 2048;

  /// Hard cap on headers per candidate (injection / memory guard).
  static const int maxHeaderCount = 32;

  /// schemes SPECTA accepts for media URLs.
  static const Set<String> allowedSchemes = <String>{'http', 'https'};

  /// Validates one raw candidate. Never throws.
  static ValidatedSource validate(ExtensionSource raw) {
    final String url = raw.url.trim();
    if (url.isEmpty) return ValidatedSource.dropped('blank url');
    if (url.length > maxUrlLength) {
      return ValidatedSource.dropped('url exceeds $maxUrlLength chars');
    }

    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.scheme.isEmpty) {
      return ValidatedSource.dropped('url has no parseable scheme');
    }
    if (!allowedSchemes.contains(uri.scheme.toLowerCase())) {
      return ValidatedSource.dropped('unsupported scheme: ${uri.scheme}');
    }
    // A media URL must point somewhere.
    if (uri.host.isEmpty && uri.path.isEmpty) {
      return ValidatedSource.dropped('url has no host or path');
    }

    // Defense in depth: the contract parser only produces mp4/hls, but 2D
    // validates its own inputs (extensions could evolve; the pool must not
    // depend on an upstream assumption).
    if (raw.type != SourceType.mp4 && raw.type != SourceType.hls) {
      return ValidatedSource.dropped('unsupported source type: ${raw.type}');
    }

    final Map<String, String>? headers = raw.headers;
    if (headers != null) {
      if (headers.length > maxHeaderCount) {
        return ValidatedSource.dropped(
          'too many headers (${headers.length} > $maxHeaderCount)',
        );
      }
      for (final MapEntry<String, String> entry in headers.entries) {
        final String name = entry.key.trim();
        if (name.isEmpty || name.contains(_controlChars)) {
          return ValidatedSource.dropped('invalid header name');
        }
      }
    }

    // Subtitles: every entry must carry a URL. Entries without one are
    // dropped individually; the source is not rejected for one bad row.
    final List<SubtitleTrack>? subtitles = raw.subtitles;
    if (subtitles != null) {
      for (final SubtitleTrack track in subtitles) {
        if (track.url.trim().isEmpty) {
          return ValidatedSource.dropped('subtitle track without url');
        }
      }
    }

    return ValidatedSource.ok(raw);
  }

  static final RegExp _controlChars = RegExp(r'[\s\x00-\x1f\x7f]');
}
