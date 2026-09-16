/// Playback source type.
///
/// Only MP4 and HLS/M3U8 are supported in V1.
/// DASH is deliberately NOT included — it is out of scope for Phase 1.
enum SourceType {
  /// Progressive MP4 download / direct file URL.
  mp4('mp4'),

  /// HTTP Live Streaming (M3U8 playlist).
  hls('hls');

  const SourceType(this.code);

  final String code;

  static SourceType? fromCode(String code) {
    for (final SourceType type in SourceType.values) {
      if (type.code == code.toLowerCase()) return type;
    }
    return null;
  }
}

/// A single audio track on a [ExtensionSource].
final class AudioTrack {
  const AudioTrack({required this.language, this.label});

  /// ISO 639-2/3 language code or `null` for unknown.
  final String? language;

  /// Human-readable track label, if provided.
  final String? label;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'language': language,
    'label': label,
  };

  static AudioTrack fromJson(Map<String, dynamic> json) => AudioTrack(
    language: json['language'] as String?,
    label: json['label'] as String?,
  );
}

/// A subtitle track on a [ExtensionSource].
final class SubtitleTrack {
  const SubtitleTrack({required this.url, this.language, this.label});

  /// URL of the subtitle file.
  final String url;

  /// ISO 639-2/3 language code or `null` for unknown.
  final String? language;

  /// Human-readable track label, if provided.
  final String? label;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'url': url,
    'language': language,
    'label': label,
  };

  static SubtitleTrack fromJson(Map<String, dynamic> json) => SubtitleTrack(
    url: json['url'] as String,
    language: json['language'] as String?,
    label: json['label'] as String?,
  );
}

/// A media playback source discovered by an extension.
///
/// SPECTA normalises, validates and ranks sources before playback —
/// extensions only discover them, never decide which one plays.
final class ExtensionSource {
  const ExtensionSource({
    required this.url,
    required this.type,
    this.quality,
    this.label,
    this.isAdaptive = false,
    this.headers,
    this.audioTracks,
    this.subtitles,
  });

  /// Direct URL to the media file or playlist.
  final String url;

  /// Playback container/protocol type.
  final SourceType type;

  /// Quality label (e.g. `480p`, `720p`, `1080p`, `4K`).  Null when unknown.
  final String? quality;

  /// Neutral, user-facing label (e.g. `Server 1`).  Provider-domain names are
  /// never exposed as the user-facing label.
  final String? label;

  /// Whether the source uses adaptive bitrate streaming.
  final bool isAdaptive;

  /// HTTP headers the player should send when fetching the source.
  final Map<String, String>? headers;

  /// Available audio tracks.
  final List<AudioTrack>? audioTracks;

  /// Available subtitle tracks.
  final List<SubtitleTrack>? subtitles;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'url': url,
    'type': type.code,
    'quality': quality,
    'label': label,
    'isAdaptive': isAdaptive,
    'headers': headers,
    'audioTracks': audioTracks?.map((AudioTrack t) => t.toJson()).toList(),
    'subtitles': subtitles?.map((SubtitleTrack t) => t.toJson()).toList(),
  };

  static ExtensionSource fromJson(Map<String, dynamic> json) {
    final String? typeStr = json['type'] as String?;
    final SourceType? sourceType = typeStr != null
        ? SourceType.fromCode(typeStr)
        : null;
    if (sourceType == null) {
      throw FormatException('Unknown source type: $typeStr');
    }

    return ExtensionSource(
      url: json['url'] as String,
      type: sourceType,
      quality: json['quality'] as String?,
      label: json['label'] as String?,
      isAdaptive: json['isAdaptive'] as bool? ?? false,
      headers: (json['headers'] as Map<String, dynamic>?)?.map(
        (String k, Object? v) => MapEntry(k, v.toString()),
      ),
      audioTracks: (json['audioTracks'] as List<dynamic>?)
          ?.map((dynamic t) => AudioTrack.fromJson(t as Map<String, dynamic>))
          .toList(),
      subtitles: (json['subtitles'] as List<dynamic>?)
          ?.map(
            (dynamic s) => SubtitleTrack.fromJson(s as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}
