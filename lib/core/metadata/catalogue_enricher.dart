import 'package:specta/core/anilist/anilist_client.dart';
import 'package:specta/core/anilist/anilist_dto.dart';
import 'package:specta/core/anilist/anilist_normalizer.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/metadata/metadata_models.dart';
import 'package:specta/core/tmdb/tmdb_client.dart';
import 'package:specta/core/tmdb/tmdb_dto.dart';
import 'package:specta/core/tmdb/tmdb_normalizer.dart';
import 'package:specta/core/tvmaze/tvmaze_client.dart';
import 'package:specta/core/tvmaze/tvmaze_dto.dart';

/// Why one catalogue provider did or did not contribute metadata.
///
/// The brief requires these states to be DISTINGUISHABLE, because they mean
/// very different things to the user: "TMDB is not configured" is a build
/// fact, "no match" is a real answer, and "network failed" is transient.
enum ProviderOutcome {
  /// The provider answered and supplied usable metadata.
  matched,

  /// The provider was reachable and genuinely has no entry for this work.
  noMatch,

  /// The provider is not configured in this build (e.g. no TMDB key).
  notConfigured,

  /// The provider could not be reached.
  networkFailure,

  /// The provider answered with an untrustworthy payload.
  malformed,

  /// The provider does not serve this content type at all.
  ///
  /// TVMaze publishes no movie catalogue, so a movie request is a deliberate
  /// no-op rather than a failure.
  notApplicable,

  /// The provider refused or failed in another way.
  failed,
}

/// One provider's participation in an enrichment round.
final class ProviderReport {
  const ProviderReport({
    required this.providerId,
    required this.outcome,
    this.contribution,
    this.failure,
  });

  final String providerId;
  final ProviderOutcome outcome;

  /// Present only when [outcome] is [ProviderOutcome.matched].
  final ReferenceMetadata? contribution;

  /// The structured failure, when one explains the outcome.
  final SpectaFailure? failure;

  bool get didContribute => contribution != null;

  @override
  String toString() => 'ProviderReport($providerId, ${outcome.name})';
}

/// The result of enriching one work with catalogue metadata.
final class EnrichmentResult {
  const EnrichmentResult({required this.item, required this.reports});

  /// The enriched item. Identity fields are never changed by enrichment, so
  /// the key stays byte-identical to the extension-derived metadata key.
  final MetadataItem? item;

  /// One report per provider consulted, in consultation order.
  final List<ProviderReport> reports;

  bool get hasEnrichment => reports.any((ProviderReport r) => r.didContribute);

  /// Providers that were actually used after an earlier one did not answer.
  List<String> get fallbacksUsed => reports
      .skip(1)
      .where((ProviderReport r) => r.didContribute)
      .map((ProviderReport r) => r.providerId)
      .toList(growable: false);
}

/// One TMDB search result chosen to complete a work, reduced to the only two
/// fields the completion path needs.
///
/// Deliberately not a `TmdbMediaSummary`: the summary is a search hit whose
/// overview/artwork are partial, and the completion path immediately follows up
/// with the full detail call. Carrying the summary would invite a second code
/// path that skips that call.
final class _CatalogueMatch {
  const _CatalogueMatch({required this.tmdbId});

  final int tmdbId;
}

/// The outcome of one TMDB lookup: a match, a failure, or "the search worked
/// and genuinely has no such title".
///
/// A nullable match alone cannot express the third case apart from the first
/// two, which is how a build with no TMDB key ended up reporting "no match" —
/// telling the user their title is missing from a catalogue the app never
/// successfully asked.
final class _TmdbLookup {
  const _TmdbLookup({this.match, this.failure});

  /// The chosen entry, or null when there is none.
  final _CatalogueMatch? match;

  /// Why the search itself failed, or null when it merely found nothing.
  final SpectaFailure? failure;
}

/// Enriches extension metadata with TMDB and TVMaze catalogue data.
///
/// PROVIDER ROLE â€” these are METADATA providers only. They contribute titles,
/// overviews, artwork, genres, ratings and season structure. They NEVER provide
/// playable sources: streaming resolution remains exclusively the extensions'
/// responsibility, and nothing here is reachable from `SourceManager` or
/// `getSources()`.
///
/// FALLBACK RULES (deliberate, documented, testable):
/// 1. Movie  -> TMDB only. TVMaze publishes no movie catalogue, so it is not
///    consulted; consulting it would be theatre, not fallback.
/// 2. Series -> TMDB first; TVMaze only when TMDB did not contribute.
/// 3. Anime  -> never here. AniList owns anime identity (C1/C2); a TMDB or
///    TVMaze answer must never rename or re-identify anime.
/// 4. A failing provider is isolated: enrichment returns whatever succeeded and
///    records the failure as data. Enrichment never throws.
abstract final class CatalogueEnricher {
  /// Enriches [base] for [type], consulting providers in fallback order.
  /// Anime enrichment: AniList is the anime catalogue AND the anime identity.
  ///
  /// Unlike movie/series, an anime item may legitimately have NO extension
  /// reference (a catalogue-only AniList result), so `base` can be null. In
  /// that case AniList supplies the whole metadata item under the very same
  /// `anilist:<id>` key the item already carries — this completes a work rather
  /// than inventing a second identity for it.
  ///
  /// When `base` is present, only its missing fields are filled; its key, type,
  /// year, canonicalId and identityVersion are never altered.
  static Future<EnrichmentResult> _enrichAnime({
    required MetadataItem? base,
    required AniListClient? anilist,
    required int? anilistId,
  }) async {
    if (anilist == null || anilistId == null || anilistId <= 0) {
      return EnrichmentResult(
        item: base,
        reports: const <ProviderReport>[
          ProviderReport(
            providerId: 'anilist',
            outcome: ProviderOutcome.notConfigured,
          ),
        ],
      );
    }

    final SpectaResult<AniListMedia> result = await anilist.getMedia(anilistId);
    return result.fold(
      ok: (AniListMedia media) {
        final MetadataItem fromAnilist = AniListNormalizer.toMetadataItem(
          media,
        );
        if (base == null) {
          return EnrichmentResult(
            item: fromAnilist,
            reports: const <ProviderReport>[
              ProviderReport(
                providerId: 'anilist',
                outcome: ProviderOutcome.matched,
              ),
            ],
          );
        }
        // Extension metadata already exists: merge additively. The identity of
        // the base item is preserved even if the AniList payload disagrees.
        return EnrichmentResult(
          item: base.withEnrichment(fromAnilist.details.first),
          reports: const <ProviderReport>[
            ProviderReport(
              providerId: 'anilist',
              outcome: ProviderOutcome.matched,
            ),
          ],
        );
      },
      err: (SpectaFailure failure) {
        final AniListFailure? anilistFailure = failure is AniListFailure
            ? failure
            : null;
        return EnrichmentResult(
          item: base,
          reports: <ProviderReport>[
            ProviderReport(
              providerId: 'anilist',
              outcome: switch (anilistFailure?.type) {
                AniListFailureType.networkError ||
                AniListFailureType.timeout => ProviderOutcome.networkFailure,
                AniListFailureType.parseError => ProviderOutcome.malformed,
                _ => ProviderOutcome.failed,
              },
            ),
          ],
        );
      },
    );
  }

  /// Builds a complete [MetadataItem] for a CATALOGUE-ONLY movie/series, under
  /// the identity the caller already established ([identityKey]).
  ///
  /// This is the counterpart to `_enrichAnime` for movie/series, and it exists
  /// because of a real device defect: Home's "Popular" rail lists titles the
  /// catalogue discovered (TMDB), those `DiscoveryItem`s carry NO extension
  /// reference, and the extension round therefore yields nothing. Before this
  /// path, enrichment saw `base == null`, declined to create a movie/series
  /// identity, and the details screen stayed on "Details could not be loaded —
  /// the extensions could not be reached" — blaming the network for a title the
  /// app had simply discovered a different way.
  ///
  /// Contract:
  /// - [identityKey] is used verbatim. No second identity is ever minted.
  /// - [year] and [cover] come from the item the user tapped, so the completed
  ///   record keeps agreeing with the card they pressed.
  /// - The FULL detail payload is fetched (not the search summary), so artwork,
  ///   overview, genres, rating, runtime and season structure all arrive.
  /// - The result is always a `ReferenceMetadata` with `isProviderMetadata:
  ///   true`, so nothing downstream can mistake it for a playable source.
  /// - TVMaze is consulted for series only, and only after TMDB produced
  ///   nothing (the same fallback order as the additive path).
  /// - Never throws. Every failure is reported as a [ProviderReport].
  static Future<EnrichmentResult> _completeFromCatalogue({
    required MediaType type,
    required String title,
    required String identityKey,
    int? year,
    String? cover,
    required TmdbClient? tmdb,
    required TvmazeClient? tvmaze,
    required String? imageBaseUrl,
  }) async {
    final List<ProviderReport> reports = <ProviderReport>[];

    if (tmdb != null) {
      final _TmdbLookup lookup = await _matchTmdb(
        tmdb: tmdb,
        type: type,
        title: title,
        year: year,
      );
      final _CatalogueMatch? match = lookup.match;
      if (match == null) {
        // The search either failed or found nothing, and those are DIFFERENT
        // facts: "TMDB isn't configured" must never be reported as "TMDB has
        // no such title", or the user is told to fix a build that was never
        // given a key. The failure, when there is one, travels with the report.
        reports.add(
          ProviderReport(
            providerId: 'tmdb',
            outcome: lookup.failure != null
                ? _outcomeForTmdbFailure(lookup.failure!)
                : ProviderOutcome.noMatch,
            failure: lookup.failure,
          ),
        );
      } else {
        reports.add(
          const ProviderReport(
            providerId: 'tmdb',
            outcome: ProviderOutcome.matched,
          ),
        );

        // The summary is only a pointer; the detail call is what carries
        // artwork, genres, runtime and seasons.
        final SpectaResult<TmdbMediaDetails> details = type == MediaType.movie
            ? await tmdb.getMovieDetails(match.tmdbId)
            : await tmdb.getSeriesDetails(match.tmdbId);

        if (details.isOk) {
          return EnrichmentResult(
            item: TmdbNormalizer.toMetadataItem(
              details.valueOrNull!,
              imageBaseUrl: imageBaseUrl ?? tmdb.config.imageBaseUrl,
              identity: CatalogueIdentity(
                key: identityKey,
                year: year,
                cover: cover,
              ),
            ),
            reports: reports,
          );
        }

        // Matched but the detail payload failed. Report it truthfully and let
        // the series fallback try — never present a half-record as complete.
        reports.add(
          ProviderReport(
            providerId: 'tmdb',
            outcome: _outcomeForTmdbFailure(details.failureOrNull!),
            failure: details.failureOrNull,
          ),
        );
      }
    } else {
      reports.add(
        const ProviderReport(
          providerId: 'tmdb',
          outcome: ProviderOutcome.notConfigured,
        ),
      );
    }

    if (type == MediaType.series) {
      if (tvmaze != null) {
        final ProviderReport report = await _fromTvmaze(
          tvmaze: tvmaze,
          title: title,
        );
        reports.add(report);
        if (report.didContribute) {
          return EnrichmentResult(
            item: _fromContribution(
              contribution: report.contribution!,
              identityKey: identityKey,
              type: type,
              year: year,
              cover: cover,
            ),
            reports: reports,
          );
        }
      } else {
        reports.add(
          const ProviderReport(
            providerId: 'tvmaze',
            outcome: ProviderOutcome.notConfigured,
          ),
        );
      }
    } else {
      reports.add(
        const ProviderReport(
          providerId: 'tvmaze',
          outcome: ProviderOutcome.notApplicable,
        ),
      );
    }

    // Nothing could complete the work. The reports still travel with the null
    // item so the UI can say WHY rather than shrugging.
    return EnrichmentResult(item: null, reports: reports);
  }

  /// Wraps a provider contribution as a standalone [MetadataItem] under
  /// [identityKey] — the no-extension-base counterpart of
  /// [MetadataItem.withEnrichment].
  static MetadataItem _fromContribution({
    required ReferenceMetadata contribution,
    required String identityKey,
    required MediaType type,
    int? year,
    String? cover,
  }) {
    return MetadataItem(
      key: identityKey,
      title: contribution.title,
      type: type,
      year: year,
      cover: cover ?? contribution.cover,
      backdrop: contribution.backdrop,
      details: <ReferenceMetadata>[contribution],
    );
  }

  static Future<EnrichmentResult> enrich({
    required MetadataItem? base,
    required MediaType type,
    required String title,
    int? year,
    TmdbClient? tmdb,
    TvmazeClient? tvmaze,
    AniListClient? anilist,
    int? anilistId,

    /// The identity the CALLER already established for this work — the
    /// `title|type|year` key carried by the [DiscoveryItem] the user tapped.
    ///
    /// Supplied so a catalogue-only item (no extension behind it) can be
    /// COMPLETED under its existing identity instead of being refused. When
    /// null, this method keeps its original, stricter behaviour and declines to
    /// create a movie/series identity out of nothing.
    String? identityKey,

    /// Cover the caller already holds, preserved if the provider's detail
    /// payload omits a poster.
    String? cover,

    /// TMDB image base, needed to turn `poster_path` into a URL.
    String? imageBaseUrl,
  }) async {
    if (type == MediaType.anime) {
      return _enrichAnime(base: base, anilist: anilist, anilistId: anilistId);
    }
    if (base == null) {
      // No extension contributed. A provider answer must never MINT an
      // identity here — but when the caller hands back the key it already
      // established, the provider is completing a work that already exists,
      // which is legitimate and is the only way a catalogue-only title (found
      // through the Home "Popular" rail, with no extension installed) can ever
      // show anything but a failure screen.
      if (identityKey == null) {
        return const EnrichmentResult(item: null, reports: <ProviderReport>[]);
      }
      return _completeFromCatalogue(
        type: type,
        title: title,
        year: year,
        identityKey: identityKey,
        cover: cover,
        tmdb: tmdb,
        tvmaze: tvmaze,
        imageBaseUrl: imageBaseUrl,
      );
    }

    final List<ProviderReport> reports = <ProviderReport>[];

    if (tmdb != null) {
      final ProviderReport report = await _fromTmdb(
        tmdb: tmdb,
        type: type,
        title: title,
        year: year,
      );
      reports.add(report);
      if (report.didContribute) {
        return EnrichmentResult(
          item: base.withEnrichment(report.contribution!),
          reports: reports,
        );
      }
    } else {
      reports.add(
        const ProviderReport(
          providerId: 'tmdb',
          outcome: ProviderOutcome.notConfigured,
        ),
      );
    }

    if (type == MediaType.series) {
      if (tvmaze != null) {
        final ProviderReport report = await _fromTvmaze(
          tvmaze: tvmaze,
          title: title,
        );
        reports.add(report);
        if (report.didContribute) {
          return EnrichmentResult(
            item: base.withEnrichment(report.contribution!),
            reports: reports,
          );
        }
      } else {
        reports.add(
          const ProviderReport(
            providerId: 'tmdb',
            outcome: ProviderOutcome.notConfigured,
          ),
        );
      }
    }

    // Fallback: series only, and only after TMDB produced nothing.
    if (type == MediaType.series) {
      if (tvmaze != null) {
        final ProviderReport report = await _fromTvmaze(
          tvmaze: tvmaze,
          title: title,
        );
        reports.add(report);
        if (report.didContribute) {
          return EnrichmentResult(
            item: base.withEnrichment(report.contribution!),
            reports: reports,
          );
        }
      } else {
        reports.add(
          const ProviderReport(
            providerId: 'tvmaze',
            outcome: ProviderOutcome.notConfigured,
          ),
        );
      }
    } else {
      reports.add(
        const ProviderReport(
          providerId: 'tvmaze',
          outcome: ProviderOutcome.notApplicable,
        ),
      );
    }

    return EnrichmentResult(item: base, reports: reports);
  }

  /// Searches TMDB and returns the best match for [title] of [type], together
  /// with the failure if the search itself could not be completed.
  ///
  /// Shared by the additive path ([_fromTmdb]) and the catalogue-only
  /// completion path ([_completeFromCatalogue]) so both agree — byte for byte —
  /// on which catalogue entry a title refers to.
  static Future<_TmdbLookup> _matchTmdb({
    required TmdbClient tmdb,
    required MediaType type,
    required String title,
    int? year,
  }) async {
    final SpectaResult<TmdbMediaPage> search = await tmdb.searchMulti(
      query: title,
    );
    if (search.isErr) {
      return _TmdbLookup(failure: search.failureOrNull);
    }

    // Strict type agreement: a movie request never accepts a series answer.
    final Iterable<TmdbMediaSummary> typed = search.valueOrNull!.results.where(
      (TmdbMediaSummary s) => s.identity.type == type,
    );

    final TmdbMediaSummary? best = _bestByYear(typed, year);
    if (best == null) return const _TmdbLookup();
    return _TmdbLookup(match: _CatalogueMatch(tmdbId: best.identity.tmdbId));
  }

  static Future<ProviderReport> _fromTmdb({
    required TmdbClient tmdb,
    required MediaType type,
    required String title,
    int? year,
  }) async {
    SpectaResult<TmdbMediaPage> search;
    try {
      search = await tmdb.searchMulti(query: title);
    } on Object catch (e) {
      return ProviderReport(
        providerId: 'tmdb',
        outcome: ProviderOutcome.networkFailure,
        failure: TmdbFailure(
          type: TmdbFailureType.networkError,
          detail: 'Enrichment transport raised ${e.runtimeType}',
        ),
      );
    }

    if (search.isErr) {
      return ProviderReport(
        providerId: 'tmdb',
        outcome: _outcomeForTmdbFailure(search.failureOrNull!),
        failure: search.failureOrNull,
      );
    }

    // Strict type agreement: a movie request never accepts a series answer.
    final Iterable<TmdbMediaSummary> typed = search.valueOrNull!.results.where(
      (TmdbMediaSummary s) => s.identity.type == type,
    );

    final TmdbMediaSummary? best = _bestByYear(typed, year);
    if (best == null) {
      return const ProviderReport(
        providerId: 'tmdb',
        outcome: ProviderOutcome.noMatch,
      );
    }
    return ProviderReport(
      providerId: 'tmdb',
      outcome: ProviderOutcome.matched,
      contribution: ReferenceMetadata(
        extensionId: 'tmdb',
        referenceUrl: best.identity.code,
        title: best.title,
        originalTitle: best.originalTitle,
        description: best.overview,
        rating: best.voteAverage,
      ),
    );
  }

  /// Best year match, with a +/-1 year tolerance for international release
  /// offsets. Beyond the tolerance this reports no match rather than guessing.
  static TmdbMediaSummary? _bestByYear(
    Iterable<TmdbMediaSummary> candidates,
    int? year,
  ) {
    if (candidates.isEmpty) return null;
    if (year == null) return candidates.first;
    TmdbMediaSummary? best;
    int bestDistance = 1 << 30;
    for (final TmdbMediaSummary c in candidates) {
      final int? cYear = c.year;
      if (cYear == null) continue;
      final int distance = (cYear - year).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = c;
      }
    }
    return bestDistance <= 1 ? best : null;
  }

  static Future<ProviderReport> _fromTvmaze({
    required TvmazeClient tvmaze,
    required String title,
  }) async {
    SpectaResult<TvmazeShowList> search;
    try {
      search = await tvmaze.searchShows(title);
    } on Object catch (e) {
      return ProviderReport(
        providerId: 'tvmaze',
        outcome: ProviderOutcome.networkFailure,
        failure: TvmazeFailure(
          type: TvmazeFailureType.networkError,
          detail: 'Enrichment transport raised ${e.runtimeType}',
        ),
      );
    }

    if (search.isErr) {
      return ProviderReport(
        providerId: 'tvmaze',
        outcome: _outcomeForTvmazeFailure(search.failureOrNull!),
        failure: search.failureOrNull,
      );
    }

    final List<TvmazeShow> shows = search.valueOrNull!.results;
    if (shows.isEmpty) {
      return const ProviderReport(
        providerId: 'tvmaze',
        outcome: ProviderOutcome.noMatch,
      );
    }

    final TvmazeShow show = shows.first;
    return ProviderReport(
      providerId: 'tvmaze',
      outcome: ProviderOutcome.matched,
      contribution: ReferenceMetadata(
        extensionId: 'tvmaze',
        referenceUrl: show.cacheKey,
        title: show.title,
        originalTitle: show.originalTitle,
        description: show.overview,
        cover: show.posterUrl,
        genres: show.genres,
        rating: show.rating,
        durationSeconds: show.averageRuntimeMinutes == null
            ? null
            : show.averageRuntimeMinutes! * 60,
      ),
    );
  }

  /// A missing or rejected build-time credential is reported as
  /// [ProviderOutcome.notConfigured], not as a network error, so the UI can
  /// say something true instead of blaming the network.
  static ProviderOutcome _outcomeForTmdbFailure(SpectaFailure failure) {
    if (failure is! TmdbFailure) return ProviderOutcome.failed;
    return switch (failure.type) {
      TmdbFailureType.notConfigured => ProviderOutcome.notConfigured,
      TmdbFailureType.invalidKey => ProviderOutcome.notConfigured,
      TmdbFailureType.notFound => ProviderOutcome.noMatch,
      TmdbFailureType.parseError => ProviderOutcome.malformed,
      TmdbFailureType.networkError ||
      TmdbFailureType.timeout => ProviderOutcome.networkFailure,
      TmdbFailureType.rateLimited ||
      TmdbFailureType.serverError => ProviderOutcome.networkFailure,
      TmdbFailureType.httpError ||
      TmdbFailureType.cancelled => ProviderOutcome.failed,
    };
  }

  static ProviderOutcome _outcomeForTvmazeFailure(SpectaFailure failure) {
    if (failure is! TvmazeFailure) return ProviderOutcome.failed;
    return switch (failure.type) {
      TvmazeFailureType.notFound => ProviderOutcome.noMatch,
      TvmazeFailureType.parseError => ProviderOutcome.malformed,
      TvmazeFailureType.networkError ||
      TvmazeFailureType.timeout => ProviderOutcome.networkFailure,
      TvmazeFailureType.rateLimited ||
      TvmazeFailureType.serverError => ProviderOutcome.networkFailure,
      TvmazeFailureType.httpError ||
      TvmazeFailureType.cancelled => ProviderOutcome.failed,
    };
  }
}
