/// Defensive AniList GraphQL payload models.
///
/// AniList is an external catalogue, so wrong-typed or partial fields degrade
/// to null/empty data instead of throwing into SPECTA's metadata pipeline.
library;

String? _string(Object? value) {
  if (value is! String) return null;
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _int(Object? value) => value is int ? value : null;

int? _year(Object? value) {
  if (value is! String) return null;
  final String text = value.trim();
  if (text.length < 4) return null;
  return int.tryParse(text.substring(0, 4));
}

/// AniList descriptions are wiki HTML (`<br>`, `<i>`, â€¦). SPECTA renders plain
/// text, so tags are removed and block-level breaks become real newlines.
/// Found on a REAL DEVICE: raw `<br><br>` was visible in Details.
///
/// Deliberately a conservative strip â€” nothing here interprets or executes
/// provider markup, and SPECTA never renders provider HTML.
String? _plainText(Object? value) {
  final String? raw = _string(value);
  if (raw == null) return null;
  // Line/paragraph breaks become newlines BEFORE tags are dropped, otherwise
  // `<br><br>` would collapse away and lose the paragraph split.
  final String withBreaks = raw
      .replaceAll(RegExp(r'</?br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<[^>]*>'), '');
  final String text = withBreaks
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .trim();
  return text.isEmpty ? null : text;
}

/// The AniList media formats SPECTA may display.
enum AniListFormat {
  tv('TV'),
  movie('MOVIE'),
  ova('OVA'),
  ona('ONA'),
  special('SPECIAL'),
  music('MUSIC'),
  unknown('UNKNOWN');

  const AniListFormat(this.code);
  final String code;

  static AniListFormat fromCode(String? value) {
    for (final AniListFormat format in AniListFormat.values) {
      if (format.code == value) return format;
    }
    return AniListFormat.unknown;
  }
}

/// AniList title variants, preserving the user's language plus native/romaji.
final class AniListTitle {
  const AniListTitle({this.romaji, this.english, this.native});

  final String? romaji;
  final String? english;
  final String? native;

  /// Best display title, preferring English then romaji then native.
  String? get display => english ?? romaji ?? native;

  static AniListTitle? fromJson(Object? value) {
    if (value is! Map) return null;
    return AniListTitle(
      romaji: _string(value['romaji']),
      english: _string(value['english']),
      native: _string(value['native']),
    );
  }
}

/// A studio name useful to SPECTA's details metadata.
final class AniListStudio {
  const AniListStudio({required this.name, this.isAnimationStudio = false});

  final String name;
  final bool isAnimationStudio;

  static AniListStudio? fromJson(Object? value) {
    if (value is! Map) return null;
    final String? name = _string(value['name']);
    if (name == null) return null;
    return AniListStudio(
      name: name,
      isAnimationStudio: value['isAnimationStudio'] == true,
    );
  }
}

/// One AniList media record, limited to fields SPECTA consumes.
final class AniListMedia {
  const AniListMedia({
    required this.id,
    required this.title,
    this.description,
    this.startDateYear,
    this.format = AniListFormat.unknown,
    this.status,
    this.episodes,
    this.duration,
    this.averageScore,
    this.genres = const <String>[],
    this.coverImageUrl,
    this.bannerImageUrl,
    this.studios = const <AniListStudio>[],
  });

  final int id;
  final AniListTitle title;
  final String? description;

  /// Release year, taken from AniList's fuzzy `startDate.year`. Null when the
  /// entry has no known start year.
  final int? startDateYear;
  final AniListFormat format;
  final String? status;
  final int? episodes;
  final int? duration;
  final double? averageScore;
  final List<String> genres;
  final String? coverImageUrl;
  final String? bannerImageUrl;
  final List<AniListStudio> studios;

  int? get year => startDateYear;
  String get cacheKey => 'media:$id';

  /// AniList's 0-100 score converted to SPECTA's existing 0-10 metadata scale.
  double? get rating => averageScore == null ? null : averageScore! / 10;

  static AniListMedia? fromJson(Object? value) {
    if (value is! Map) return null;
    final int? id = _int(value['id']);
    final AniListTitle? title = AniListTitle.fromJson(value['title']);
    if (id == null || id <= 0 || title == null || title.display == null) {
      return null;
    }

    final List<String> genres = <String>[];
    final Object? rawGenres = value['genres'];
    if (rawGenres is List) {
      for (final Object? genre in rawGenres) {
        final String? name = _string(genre);
        if (name != null) genres.add(name);
      }
    }

    final List<AniListStudio> studios = <AniListStudio>[];
    final Object? rawStudios = value['studios'];
    if (rawStudios is Map) {
      final Object? nodes = rawStudios['nodes'];
      if (nodes is List) {
        for (final Object? node in nodes) {
          final AniListStudio? studio = AniListStudio.fromJson(node);
          if (studio != null) studios.add(studio);
        }
      }
    }

    return AniListMedia(
      id: id,
      title: title,
      description: _plainText(value['description']),
      startDateYear: _startDateOf(value['startDate']),
      format: AniListFormat.fromCode(_string(value['format'])),
      status: _string(value['status']),
      episodes: _int(value['episodes']),
      duration: _int(value['duration']),
      averageScore: switch (value['averageScore']) {
        final num score => score.toDouble(),
        _ => null,
      },
      genres: genres,
      coverImageUrl: _coverImageOf(value['coverImage']),
      bannerImageUrl: _string(value['bannerImage']),
      studios: studios,
    );
  }

  /// AniList returns `startDate` as a fuzzy date OBJECT (`{year, month, day}`),
  /// not a string. The year is all SPECTA needs; a plain ISO string is still
  /// accepted so a cached older payload keeps working.
  static int? _startDateOf(Object? value) {
    if (value is Map) return _int(value['year']);
    return _year(value);
  }

  /// `coverImage` is an OBJECT (`MediaCoverImage`), so the URL must be read
  /// from one of its sub-fields. `extraLarge` is preferred, then `large`.
  static String? _coverImageOf(Object? value) {
    if (value is Map) {
      return _string(value['extraLarge']) ?? _string(value['large']);
    }
    // Tolerate a bare string, which is what an older cached payload holds.
    return _string(value);
  }
}
