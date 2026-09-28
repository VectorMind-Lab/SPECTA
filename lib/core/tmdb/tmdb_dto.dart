import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/tmdb/tmdb_media_identity.dart';

/// Safe extraction helpers for defensive TMDB payload parsing.
///
/// TMDB documents its shapes, but a wrong-typed field (a string where a
/// number belongs, a number where a string belongs) must degrade to null or
/// a default — never throw a [TypeError] into the catalogue pipeline. These
/// replace raw `as String?` / `as int?` casts throughout this library.
String? _string(Object? value) => value is String ? value : null;

int? _int(Object? value) => value is int ? value : null;

double? _double(Object? value) => switch (value) {
  final num n => n.toDouble(),
  _ => null,
};

enum TmdbImageSize {
  posterSmall('w185'),
  posterMedium('w342'),
  posterLarge('w500'),
  posterOriginal('original'),
  backdropSmall('w300'),
  backdropMedium('w780'),
  backdropLarge('w1280'),
  backdropOriginal('original');

  const TmdbImageSize(this.sizeSegment);
  final String sizeSegment;
}

abstract final class TmdbImageUrl {
  static String? build({
    required String? path,
    required String imageBaseUrl,
    TmdbImageSize size = TmdbImageSize.posterLarge,
  }) {
    if (path == null) return null;
    final String trimmed = path.trim();
    if (trimmed.isEmpty) return null;

    final String cleanBase = imageBaseUrl.endsWith('/')
        ? imageBaseUrl.substring(0, imageBaseUrl.length - 1)
        : imageBaseUrl;

    final String cleanPath = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return '$cleanBase/${size.sizeSegment}$cleanPath';
  }
}

final class TmdbMediaSummary {
  const TmdbMediaSummary({
    required this.identity,
    required this.title,
    this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.voteAverage,
    this.voteCount,
    this.popularity,
    this.genreIds = const <int>[],
  });

  final SpectaMediaIdentity identity;
  final String title;
  final String? originalTitle;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final double? voteAverage;
  final int? voteCount;
  final double? popularity;
  final List<int> genreIds;

  int? get year {
    final String? date = releaseDate?.trim();
    if (date == null || date.length < 4) return null;
    return int.tryParse(date.substring(0, 4));
  }

  static TmdbMediaSummary? fromJson(
    Map<String, Object?> json, {
    MediaType? forcedType,
  }) {
    final Object? rawId = json['id'];
    if (rawId is! int || rawId <= 0) return null;

    final MediaType? resolvedType =
        forcedType ??
        (switch (json['media_type']) {
          'movie' => MediaType.movie,
          'tv' => MediaType.series,
          _ => null,
        });

    if (resolvedType == null) return null;

    final String? title = switch (resolvedType) {
      MediaType.movie => _string(json['title']),
      MediaType.series => _string(json['name']),
      MediaType.anime => null,
    };

    if (title == null || title.trim().isEmpty) return null;

    final String? originalTitle = switch (resolvedType) {
      MediaType.movie => _string(json['original_title']),
      MediaType.series => _string(json['original_name']),
      MediaType.anime => null,
    };

    final String? releaseDate = switch (resolvedType) {
      MediaType.movie => _string(json['release_date']),
      MediaType.series => _string(json['first_air_date']),
      MediaType.anime => null,
    };

    final List<int> genreIds = <int>[];
    final Object? rawGenres = json['genre_ids'];
    if (rawGenres is List) {
      for (final Object? item in rawGenres) {
        if (item is int) genreIds.add(item);
      }
    }

    final double? voteAverage = _double(json['vote_average']);

    final int? voteCount = switch (json['vote_count']) {
      final int i => i,
      _ => null,
    };

    final double? popularity = _double(json['popularity']);

    return TmdbMediaSummary(
      identity: SpectaMediaIdentity(type: resolvedType, tmdbId: rawId),
      title: title.trim(),
      originalTitle: originalTitle?.trim(),
      overview: (_string(json['overview']))?.trim(),
      posterPath: _string(json['poster_path']),
      backdropPath: _string(json['backdrop_path']),
      releaseDate: releaseDate,
      voteAverage: voteAverage,
      voteCount: voteCount,
      popularity: popularity,
      genreIds: genreIds,
    );
  }
}

final class TmdbMediaPage {
  const TmdbMediaPage({
    required this.page,
    required this.totalPages,
    required this.totalResults,
    required this.results,
  });

  final int page;
  final int totalPages;
  final int totalResults;
  final List<TmdbMediaSummary> results;

  static TmdbMediaPage fromJson(
    Map<String, Object?> json, {
    MediaType? forcedType,
  }) {
    final int page = _int(json['page']) ?? 1;
    final int totalPages = _int(json['total_pages']) ?? 1;
    final int totalResults = _int(json['total_results']) ?? 0;

    final List<TmdbMediaSummary> list = <TmdbMediaSummary>[];
    final Object? rawList = json['results'];
    if (rawList is List) {
      for (final Object? elem in rawList) {
        if (elem is Map<String, Object?>) {
          final TmdbMediaSummary? parsed = TmdbMediaSummary.fromJson(
            elem,
            forcedType: forcedType,
          );
          if (parsed != null) list.add(parsed);
        }
      }
    }

    return TmdbMediaPage(
      page: page,
      totalPages: totalPages,
      totalResults: totalResults,
      results: list,
    );
  }
}

final class TmdbEpisodeDetails {
  const TmdbEpisodeDetails({
    required this.id,
    required this.episodeNumber,
    required this.seasonNumber,
    required this.name,
    this.overview,
    this.stillPath,
    this.airDate,
    this.voteAverage,
    this.runtimeMinutes,
  });

  final int id;
  final int episodeNumber;
  final int seasonNumber;
  final String name;
  final String? overview;
  final String? stillPath;
  final String? airDate;
  final double? voteAverage;
  final int? runtimeMinutes;

  static TmdbEpisodeDetails? fromJson(Map<String, Object?> json) {
    final Object? rawId = json['id'];
    final Object? rawEpNum = json['episode_number'];
    final Object? rawSeasNum = json['season_number'];
    final Object? rawName = json['name'];

    if (rawId is! int || rawId <= 0) return null;
    if (rawEpNum is! int || rawEpNum <= 0) return null;
    if (rawSeasNum is! int || rawSeasNum < 0) return null;
    if (rawName is! String || rawName.trim().isEmpty) return null;

    final double? voteAvg = _double(json['vote_average']);

    final int? runtime = switch (json['runtime']) {
      final int i => i,
      _ => null,
    };

    return TmdbEpisodeDetails(
      id: rawId,
      episodeNumber: rawEpNum,
      seasonNumber: rawSeasNum,
      name: rawName.trim(),
      overview: (_string(json['overview']))?.trim(),
      stillPath: _string(json['still_path']),
      airDate: _string(json['air_date']),
      voteAverage: voteAvg,
      runtimeMinutes: runtime,
    );
  }
}

final class TmdbSeasonDetails {
  const TmdbSeasonDetails({
    required this.id,
    required this.seasonNumber,
    required this.name,
    this.overview,
    this.posterPath,
    this.airDate,
    this.episodes = const <TmdbEpisodeDetails>[],
  });

  final int id;
  final int seasonNumber;
  final String name;
  final String? overview;
  final String? posterPath;
  final String? airDate;
  final List<TmdbEpisodeDetails> episodes;

  static TmdbSeasonDetails? fromJson(Map<String, Object?> json) {
    final Object? rawId = json['id'];
    final Object? rawSeasNum = json['season_number'];
    final Object? rawName = json['name'];

    if (rawId is! int || rawId <= 0) return null;
    if (rawSeasNum is! int || rawSeasNum < 0) return null;
    if (rawName is! String || rawName.trim().isEmpty) return null;

    final List<TmdbEpisodeDetails> episodes = <TmdbEpisodeDetails>[];
    final Object? rawEpisodes = json['episodes'];
    if (rawEpisodes is List) {
      for (final Object? elem in rawEpisodes) {
        if (elem is Map<String, Object?>) {
          final TmdbEpisodeDetails? ep = TmdbEpisodeDetails.fromJson(elem);
          if (ep != null) episodes.add(ep);
        }
      }
    }

    return TmdbSeasonDetails(
      id: rawId,
      seasonNumber: rawSeasNum,
      name: rawName.trim(),
      overview: (_string(json['overview']))?.trim(),
      posterPath: _string(json['poster_path']),
      airDate: _string(json['air_date']),
      episodes: episodes,
    );
  }
}

final class TmdbSeasonSummary {
  const TmdbSeasonSummary({
    required this.id,
    required this.seasonNumber,
    required this.name,
    this.episodeCount = 0,
    this.posterPath,
    this.airDate,
  });

  final int id;
  final int seasonNumber;
  final String name;
  final int episodeCount;
  final String? posterPath;
  final String? airDate;

  static TmdbSeasonSummary? fromJson(Map<String, Object?> json) {
    final Object? rawId = json['id'];
    final Object? rawSeasNum = json['season_number'];
    final Object? rawName = json['name'];

    if (rawId is! int || rawId <= 0) return null;
    if (rawSeasNum is! int || rawSeasNum < 0) return null;
    if (rawName is! String || rawName.trim().isEmpty) return null;

    return TmdbSeasonSummary(
      id: rawId,
      seasonNumber: rawSeasNum,
      name: rawName.trim(),
      episodeCount: _int(json['episode_count']) ?? 0,
      posterPath: _string(json['poster_path']),
      airDate: _string(json['air_date']),
    );
  }
}

final class TmdbMediaDetails {
  const TmdbMediaDetails({
    required this.identity,
    required this.title,
    this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.voteAverage,
    this.voteCount,
    this.status,
    this.tagline,
    this.genres = const <String>[],
    this.runtimeMinutes,
    this.seasons = const <TmdbSeasonSummary>[],
  });

  final SpectaMediaIdentity identity;
  final String title;
  final String? originalTitle;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final double? voteAverage;
  final int? voteCount;
  final String? status;
  final String? tagline;
  final List<String> genres;
  final int? runtimeMinutes;
  final List<TmdbSeasonSummary> seasons;

  int? get year {
    final String? date = releaseDate?.trim();
    if (date == null || date.length < 4) return null;
    return int.tryParse(date.substring(0, 4));
  }

  static TmdbMediaDetails? fromJson(
    Map<String, Object?> json, {
    required MediaType type,
  }) {
    final Object? rawId = json['id'];
    if (rawId is! int || rawId <= 0) return null;

    final String? title = switch (type) {
      MediaType.movie => _string(json['title']),
      MediaType.series => _string(json['name']),
      MediaType.anime => null,
    };

    if (title == null || title.trim().isEmpty) return null;

    final String? originalTitle = switch (type) {
      MediaType.movie => _string(json['original_title']),
      MediaType.series => _string(json['original_name']),
      MediaType.anime => null,
    };

    final String? releaseDate = switch (type) {
      MediaType.movie => _string(json['release_date']),
      MediaType.series => _string(json['first_air_date']),
      MediaType.anime => null,
    };

    final List<String> genres = <String>[];
    final Object? rawGenres = json['genres'];
    if (rawGenres is List) {
      for (final Object? elem in rawGenres) {
        if (elem is Map<String, Object?> && elem['name'] is String) {
          genres.add((elem['name'] as String).trim());
        }
      }
    }

    final double? voteAverage = _double(json['vote_average']);

    final int? voteCount = switch (json['vote_count']) {
      final int i => i,
      _ => null,
    };

    final int? runtime = switch (type) {
      MediaType.movie => switch (json['runtime']) {
        final int i => i,
        _ => null,
      },
      MediaType.series => switch (json['episode_run_time']) {
        final List list when list.isNotEmpty && list.first is int =>
          list.first as int,
        _ => null,
      },
      MediaType.anime => null,
    };

    final List<TmdbSeasonSummary> seasons = <TmdbSeasonSummary>[];
    if (type == MediaType.series) {
      final Object? rawSeasons = json['seasons'];
      if (rawSeasons is List) {
        for (final Object? elem in rawSeasons) {
          if (elem is Map<String, Object?>) {
            final TmdbSeasonSummary? s = TmdbSeasonSummary.fromJson(elem);
            if (s != null) seasons.add(s);
          }
        }
      }
    }

    return TmdbMediaDetails(
      identity: SpectaMediaIdentity(type: type, tmdbId: rawId),
      title: title.trim(),
      originalTitle: originalTitle?.trim(),
      overview: (_string(json['overview']))?.trim(),
      posterPath: _string(json['poster_path']),
      backdropPath: _string(json['backdrop_path']),
      releaseDate: releaseDate,
      voteAverage: voteAverage,
      voteCount: voteCount,
      status: _string(json['status']),
      tagline: (_string(json['tagline']))?.trim(),
      genres: genres,
      runtimeMinutes: runtime,
      seasons: seasons,
    );
  }
}
