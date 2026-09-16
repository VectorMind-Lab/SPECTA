enum MediaType {
  movie,
  series,
}

/// UI presentation model for Movie and TV Series cards.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.type,
    required this.year,
    required this.genres,
    this.rating,
    this.posterUrl,
    this.backdropUrl,
    this.overview,
    this.episodeInfo,
    this.progressPercentage,
    this.remainingDuration,
    this.qualityBadge = '4K',
  });

  final String id;
  final String title;
  final MediaType type;
  final int year;
  final List<String> genres;
  final double? rating;
  final String? posterUrl;
  final String? backdropUrl;
  final String? overview;

  /// For continue watching: e.g. "S1 · E3" or "Episode 3"
  final String? episodeInfo;

  /// Watch progress (0.0 to 1.0)
  final double? progressPercentage;

  /// Remaining watch time, e.g. "42m"
  final String? remainingDuration;

  /// Quality label: 4K, 1080p, HD
  final String qualityBadge;

  String get genreText => genres.join(' · ');

  String get subtitleLine {
    final List<String> parts = <String>[];
    if (episodeInfo != null) parts.add(episodeInfo!);
    if (remainingDuration != null) parts.add(remainingDuration!);
    if (parts.isEmpty) {
      parts.add('$year');
      parts.addAll(genres.take(2));
    }
    return parts.join(' · ');
  }
}
