import 'result_models.dart';

/// Capabilities an extension declares through its `capabilities()` operation.
///
/// SPECTA must not assume a function exists merely because a JavaScript
/// function happens to exist; capabilities must be explicitly declared.
final class ExtensionCapabilities {
  const ExtensionCapabilities({
    this.contentTypes = const <MediaType>[],
    this.search = false,
    this.latest = false,
    this.details = false,
    this.seasons = false,
    this.episodes = false,
    this.mp4Sources = false,
    this.hlsSources = false,
    this.multipleSources = false,
    this.multipleQualities = false,
    this.sourceHeaders = false,
    this.subtitles = false,
    this.audioTracks = false,
    this.downloads = false,
    this.searchPagination = false,
    this.latestPagination = false,
  });

  final List<MediaType> contentTypes;
  final bool search;
  final bool latest;
  final bool details;
  final bool seasons;
  final bool episodes;
  final bool mp4Sources;
  final bool hlsSources;
  final bool multipleSources;
  final bool multipleQualities;
  final bool sourceHeaders;
  final bool subtitles;
  final bool audioTracks;
  final bool downloads;
  final bool searchPagination;
  final bool latestPagination;

  bool get supportsSearch => search;
  bool get supportsLatest => latest;
  bool get supportsDetails => details;
  bool get providesMp4 => mp4Sources;
  bool get providesHls => hlsSources;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'contentTypes': contentTypes.map((MediaType t) => t.code).toList(),
    'discovery': <String, dynamic>{'search': search, 'latest': latest},
    'metadata': <String, dynamic>{
      'details': details,
      'seasons': seasons,
      'episodes': episodes,
    },
    'sources': <String, dynamic>{
      'mp4': mp4Sources,
      'hls': hlsSources,
      'dash': false,
      'multipleSources': multipleSources,
      'multipleQualities': multipleQualities,
      'headers': sourceHeaders,
      'subtitles': subtitles,
      'audioTracks': audioTracks,
    },
    'downloads': <String, dynamic>{'supported': downloads},
    'pagination': <String, dynamic>{
      'search': searchPagination,
      'latest': latestPagination,
    },
  };

  static ExtensionCapabilities fromJson(Map<String, dynamic> json) {
    final dynamic discovery = json['discovery'] as Map<String, dynamic>?;
    final dynamic metadata = json['metadata'] as Map<String, dynamic>?;
    final dynamic sources = json['sources'] as Map<String, dynamic>?;
    final dynamic downloadInfo = json['downloads'] as Map<String, dynamic>?;
    final dynamic pagination = json['pagination'] as Map<String, dynamic>?;

    final List<dynamic> rawTypes =
        json['contentTypes'] as List<dynamic>? ?? <dynamic>[];

    return ExtensionCapabilities(
      contentTypes: rawTypes
          .map((dynamic t) => MediaType.fromCode(t.toString()))
          .where((MediaType? t) => t != null)
          .cast<MediaType>()
          .toList(),
      search: discovery?['search'] as bool? ?? false,
      latest: discovery?['latest'] as bool? ?? false,
      details: metadata?['details'] as bool? ?? false,
      seasons: metadata?['seasons'] as bool? ?? false,
      episodes: metadata?['episodes'] as bool? ?? false,
      mp4Sources: sources?['mp4'] as bool? ?? false,
      hlsSources: sources?['hls'] as bool? ?? false,
      multipleSources: sources?['multipleSources'] as bool? ?? false,
      multipleQualities: sources?['multipleQualities'] as bool? ?? false,
      sourceHeaders: sources?['headers'] as bool? ?? false,
      subtitles: sources?['subtitles'] as bool? ?? false,
      audioTracks: sources?['audioTracks'] as bool? ?? false,
      downloads: downloadInfo?['supported'] as bool? ?? false,
      searchPagination: pagination?['search'] as bool? ?? false,
      latestPagination: pagination?['latest'] as bool? ?? false,
    );
  }
}
