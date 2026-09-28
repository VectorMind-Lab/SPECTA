/// Defensive extraction helpers for TVMaze payloads.
///
/// TVMaze is a third-party service we do not control, so a wrong-typed field
/// must degrade to null rather than throw a [TypeError] into the catalogue
/// pipeline. These mirror the TMDB DTO rules exactly.
String? _string(Object? value) => value is String ? value : null;

int? _int(Object? value) => value is int ? value : null;

/// Leading four-digit year of a `YYYY-MM-DD` date, or null.
int? _yearOf(Object? value) {
  if (value is! String) return null;
  final String date = value.trim();
  if (date.length < 4) return null;
  return int.tryParse(date.substring(0, 4));
}

/// One TVMaze show, normalized out of the raw JSON.
///
/// TVMaze IS SERIES ONLY. It publishes no movie catalogue, so there is
/// deliberately no type field and no movie constructor on this model: asking
/// TVMaze for a movie is a programming error, not a cache miss.
final class TvmazeShow {
  const TvmazeShow({
    required this.id,
    required this.title,
    this.originalTitle,
    this.overview,
    this.posterUrl,
    this.officialSite,
    this.premieredYear,
    this.status,
    this.genres = const <String>[],
    this.rating,
    this.averageRuntimeMinutes,
  });

  /// TVMaze's own numeric show id. Never a playback or extension reference.
  final int id;

  /// Canonical display title.
  final String title;

  /// TVMaze's `originalTitle` when it differs from the localized [title].
  final String? originalTitle;

  final String? overview;

  /// Absolute artwork URL, already the full `static.tvmaze.com` address. TVMaze
  /// serves images on its own CDN, so — unlike TMDB — no base-URL join is
  /// needed; the URL is stored as-is inside the cached payload.
  final String? posterUrl;

  final String? officialSite;

  final int? premieredYear;

  /// Raw TVMaze status string, e.g. `Running`, `Ended`.
  final String? status;

  final List<String> genres;

  /// TVMaze's `rating.average`, 0-10. Null when unrated.
  final double? rating;

  final int? averageRuntimeMinutes;

  /// Stable cache identity for this show, namespaced so it can never collide
  /// with a TMDB key for a different catalogue entry.
  String get cacheKey => 'show:$id';

  /// Returns null when the payload cannot be trusted (missing/zero id or no
  /// usable title) rather than fabricating a partial show.
  static TvmazeShow? fromJson(Map<String, Object?> json) {
    final Object? rawId = json['id'];
    if (rawId is! int || rawId <= 0) return null;

    final String? title = _string(json['name']);
    if (title == null || title.trim().isEmpty) return null;

    final List<String> genres = <String>[];
    final Object? rawGenres = json['genres'];
    if (rawGenres is List) {
      for (final Object? element in rawGenres) {
        if (element is String && element.trim().isNotEmpty) {
          genres.add(element.trim());
        }
      }
    }

    return TvmazeShow(
      id: rawId,
      title: title.trim(),
      originalTitle: _string(json['originalTitle'])?.trim(),
      overview: _string(json['summary'])?.trim(),
      posterUrl: _string(json['image'])?.trim(),
      officialSite: _string(json['officialSite'])?.trim(),
      premieredYear: _yearOf(json['premiered']),
      status: _string(json['status'])?.trim(),
      genres: genres,
      rating: switch (json['rating']) {
        final Map<String, Object?> rating => switch (rating['average']) {
          final num n => n.toDouble(),
          _ => null,
        },
        _ => null,
      },
      averageRuntimeMinutes: _int(json['averageRuntime']),
    );
  }
}

/// A result list of TVMaze shows.
///
/// TVMaze paginates with an opaque integer index rather than a page count, so
/// this deliberately does not mirror a TMDB page shape: inventing
/// `totalPages` would be a fabricated value.
final class TvmazeShowList {
  const TvmazeShowList({required this.results});

  final List<TvmazeShow> results;
}
