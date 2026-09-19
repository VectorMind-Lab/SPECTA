import 'package:flutter_test/flutter_test.dart';

import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/library/watch_progress.dart';
import 'package:specta/core/metadata/metadata_manager.dart';
import 'package:specta/core/metadata/metadata_models.dart';
import 'package:specta/features/playback/resume_entry.dart';

WatchProgress movie({
  String mediaKey = 'the matrix|movie|1999',
  String title = 'The Matrix',
  Duration position = const Duration(seconds: 30),
  bool completed = false,
}) =>
    WatchProgress(
      id: mediaKey,
      mediaKey: mediaKey,
      mediaType: MediaType.movie,
      title: title,
      position: position,
      completed: completed,
      updatedAt: DateTime(2026, 1, 1),
    );

WatchProgress episode({
  String mediaKey = 'show|series|2020',
  int season = 1,
  int number = 2,
  Duration position = const Duration(seconds: 45),
  bool completed = false,
}) =>
    WatchProgress(
      id: '$mediaKey|s${season}e$number',
      mediaKey: mediaKey,
      mediaType: MediaType.series,
      title: 'Show',
      subtitleLine: 'Season $season · Episode $number',
      seasonNumber: season,
      episodeNumber: number,
      position: position,
      completed: completed,
      updatedAt: DateTime(2026, 1, 1),
    );

const DiscoveryReference refA =
    DiscoveryReference(extensionId: 'extA', url: 'https://a/show');

/// A series metadata item whose key matches [mediaKey], with S1E1, S1E2, S2E1.
MetadataItem seriesMetadata({String mediaKey = 'show|series|2020'}) =>
    MetadataItem(
      key: mediaKey,
      title: 'Show',
      type: MediaType.series,
      year: 2020,
      details: <ReferenceMetadata>[
        ReferenceMetadata(
          extensionId: 'extA',
          referenceUrl: 'https://a/show',
          title: 'Show',
          seasons: <SeriesSeason>[
            SeriesSeason(
              seasonNumber: 1,
              episodes: <SeriesEpisode>[
                const SeriesEpisode(
                  seasonNumber: 1,
                  episodeNumber: 1,
                  referenceUrl: 'https://a/show/s1e1',
                ),
                const SeriesEpisode(
                  seasonNumber: 1,
                  episodeNumber: 2,
                  referenceUrl: 'https://a/show/s1e2',
                ),
              ],
            ),
            SeriesSeason(
              seasonNumber: 2,
              episodes: <SeriesEpisode>[
                const SeriesEpisode(
                  seasonNumber: 2,
                  episodeNumber: 1,
                  referenceUrl: 'https://a/show/s2e1',
                ),
              ],
            ),
          ],
        ),
      ],
    );

MetadataItem movieMetadata({String mediaKey = 'the matrix|movie|1999'}) =>
    MetadataItem(
      key: mediaKey,
      title: 'The Matrix',
      type: MediaType.movie,
      year: 1999,
      details: <ReferenceMetadata>[
        ReferenceMetadata(
          extensionId: 'extA',
          referenceUrl: 'https://a/matrix',
          title: 'The Matrix',
        ),
      ],
    );

void main() {
  group('discoveryItemFor — identity reconstruction', () {
    test('rebuilds the exact identity for a movie', () {
      final DiscoveryItem? item =
          discoveryItemFor(movie(), <DiscoveryReference>[refA]);

      expect(item, isNotNull);
      expect(item!.title, 'the matrix');
      expect(item.type, MediaType.movie);
      expect(item.year, 1999);
      expect(item.key, 'the matrix|movie|1999');
      expect(item.references, <DiscoveryReference>[refA]);
    });

    test('the reconstructed identity round-trips to the stored key', () {
      final WatchProgress p = movie();
      final DiscoveryItem item =
          discoveryItemFor(p, <DiscoveryReference>[refA])!;

      // The metadata layer derives its key from (title, type, year); it MUST
      // reproduce the key that was persisted, or resume would drift identity.
      expect(
        MetadataManager.identityKey(
          normalizedTitle: item.title,
          type: item.type,
          year: item.year,
        ),
        p.mediaKey,
      );
    });

    test('a missing year round-trips through the `none` part', () {
      final WatchProgress p = movie(mediaKey: 'untitled|movie|none');
      final DiscoveryItem item =
          discoveryItemFor(p, <DiscoveryReference>[refA])!;

      expect(item.year, isNull);
      expect(
        MetadataManager.identityKey(
          normalizedTitle: item.title,
          type: item.type,
          year: item.year,
        ),
        'untitled|movie|none',
      );
    });

    test('no provenance cannot be resumed', () {
      expect(
        discoveryItemFor(movie(), const <DiscoveryReference>[]),
        isNull,
      );
    });

    test('a malformed identity is refused, never guessed', () {
      // Wrong number of parts.
      expect(
        discoveryItemFor(movie(mediaKey: 'broken|movie'), <DiscoveryReference>[refA]),
        isNull,
      );
      // A year part that is neither `none` nor a number.
      expect(
        discoveryItemFor(
          movie(mediaKey: 'the matrix|movie|nineteen'),
          <DiscoveryReference>[refA],
        ),
        isNull,
      );
      // Unknown media type.
      expect(
        discoveryItemFor(
          movie(mediaKey: 'the matrix|book|1999'),
          <DiscoveryReference>[refA],
        ),
        isNull,
      );
    });
  });

  group('episodeFor — exact episode selection', () {
    test('S1E2 selects episode 2, never episode 1', () {
      final SeriesEpisode? e = episodeFor(seriesMetadata(), episode());
      expect(e, isNotNull);
      expect(e!.seasonNumber, 1);
      expect(e.episodeNumber, 2);
      expect(e.referenceUrl, 'https://a/show/s1e2');
    });

    test('S1E1 and S2E1 select their own episodes', () {
      final MetadataItem meta = seriesMetadata();

      final SeriesEpisode? s1e1 =
          episodeFor(meta, episode(season: 1, number: 1));
      final SeriesEpisode? s2e1 =
          episodeFor(meta, episode(season: 2, number: 1));

      expect(s1e1!.referenceUrl, 'https://a/show/s1e1');
      expect(s2e1!.referenceUrl, 'https://a/show/s2e1');
    });

    test('a missing episode reports null honestly', () {
      expect(episodeFor(seriesMetadata(), episode(season: 3, number: 9)), isNull);
    });

    test('a movie has no episode', () {
      expect(episodeFor(movieMetadata(), movie()), isNull);
    });
  });

  group('resumeStartPosition', () {
    test('an unfinished item resumes at its stored position', () {
      expect(
        resumeStartPosition(movie(position: const Duration(minutes: 12))),
        const Duration(minutes: 12),
      );
    });

    test('a completed item restarts from the beginning', () {
      expect(
        resumeStartPosition(movie(position: const Duration(minutes: 90), completed: true)),
        isNull,
      );
    });

    test('no known position means no seek', () {
      expect(resumeStartPosition(movie(position: Duration.zero)), isNull);
    });
  });

  group('resumeWith — orchestration', () {
    test('a movie resumes through the pipeline with fresh provenance', () async {
      final WatchProgress p = movie(position: const Duration(minutes: 5));
      MetadataItem? startedWith;
      DiscoveryItem? startedItem;
      Duration? startedPosition;
      SeriesEpisode? startedEpisode;
      bool called = false;

      final ResumeResult result = await resumeWith(
        progress: p,
        loadReferences: () async => <DiscoveryReference>[refA],
        lookup: (DiscoveryItem item) async => movieMetadata(),
        starter: ({
          required MetadataItem metadata,
          required DiscoveryItem item,
          SeriesEpisode? episode,
          Duration? startPosition,
        }) async {
          called = true;
          startedWith = metadata;
          startedItem = item;
          startedPosition = startPosition;
          startedEpisode = episode;
        },
      );

      expect(result.status, ResumeStatus.started);
      expect(called, isTrue);
      expect(startedWith!.key, p.mediaKey);
      // Sources are NOT stored or reused — the stored discovery PROVENANCE is
      // handed to the existing pipeline, which re-resolves fresh sources.
      expect(startedItem!.references, <DiscoveryReference>[refA]);
      expect(startedEpisode, isNull);
      expect(startedPosition, const Duration(minutes: 5));
    });

    test('an episode resumes the exact episode with its position', () async {
      SeriesEpisode? startedEpisode;
      Duration? startedPosition;

      final ResumeResult result = await resumeWith(
        progress: episode(season: 1, number: 2),
        loadReferences: () async => <DiscoveryReference>[refA],
        lookup: (DiscoveryItem item) async => seriesMetadata(),
        starter: ({
          required MetadataItem metadata,
          required DiscoveryItem item,
          SeriesEpisode? episode,
          Duration? startPosition,
        }) async {
          startedEpisode = episode;
          startedPosition = startPosition;
        },
      );

      expect(result.status, ResumeStatus.started);
      expect(startedEpisode!.seasonNumber, 1);
      expect(startedEpisode!.episodeNumber, 2);
      expect(startedPosition, const Duration(seconds: 45));
    });

    test('S1E2 and S2E2 never collapse onto each other', () async {
      Future<SeriesEpisode?> selectedFor(WatchProgress p) async {
        SeriesEpisode? captured;
        await resumeWith(
          progress: p,
          loadReferences: () async => <DiscoveryReference>[refA],
          lookup: (DiscoveryItem item) async => seriesMetadata(),
          starter: ({
            required MetadataItem metadata,
            required DiscoveryItem item,
            SeriesEpisode? episode,
            Duration? startPosition,
          }) async {
            captured = episode;
          },
        );
        return captured;
      }

      final SeriesEpisode? s1e2 = await selectedFor(episode(season: 1, number: 2));
      final SeriesEpisode? s2e1 = await selectedFor(episode(season: 2, number: 1));

      expect(s1e2!.referenceUrl, isNot(s2e1!.referenceUrl));
      expect(s1e2.episodeNumber, 2);
      expect(s2e1.episodeNumber, 1);
    });

    test('no stored provenance fails honestly without starting playback',
        () async {
      bool called = false;
      final ResumeResult result = await resumeWith(
        progress: movie(),
        loadReferences: () async => const <DiscoveryReference>[],
        lookup: (DiscoveryItem item) async => movieMetadata(),
        starter: ({
          required MetadataItem metadata,
          required DiscoveryItem item,
          SeriesEpisode? episode,
          Duration? startPosition,
        }) async {
          called = true;
        },
      );

      expect(result.status, ResumeStatus.noReferences);
      expect(called, isFalse);
      expect(result.message, isNotEmpty);
    });

    test('a metadata failure fails honestly without starting playback',
        () async {
      for (final MetadataLookup lookup in <MetadataLookup>[
        (DiscoveryItem item) async => null,
        (DiscoveryItem item) async => throw StateError('provider down'),
      ]) {
        bool called = false;
        final ResumeResult result = await resumeWith(
          progress: movie(),
          loadReferences: () async => <DiscoveryReference>[refA],
          lookup: lookup,
          starter: ({
            required MetadataItem metadata,
            required DiscoveryItem item,
            SeriesEpisode? episode,
            Duration? startPosition,
          }) async {
            called = true;
          },
        );

        expect(result.status, ResumeStatus.metadataUnavailable);
        expect(called, isFalse);
      }
    });

    test('a vanished episode fails honestly', () async {
      bool called = false;
      final ResumeResult result = await resumeWith(
        progress: episode(season: 9, number: 9),
        loadReferences: () async => <DiscoveryReference>[refA],
        lookup: (DiscoveryItem item) async => seriesMetadata(),
        starter: ({
          required MetadataItem metadata,
          required DiscoveryItem item,
          SeriesEpisode? episode,
          Duration? startPosition,
        }) async {
          called = true;
        },
      );

      expect(result.status, ResumeStatus.episodeMissing);
      expect(called, isFalse);
    });

    test('a completed episode restarts rather than resuming mid-episode',
        () async {
      Duration? startedPosition;
      final ResumeResult result = await resumeWith(
        progress: episode(
          season: 1,
          number: 2,
          position: const Duration(minutes: 40),
          completed: true,
        ),
        loadReferences: () async => <DiscoveryReference>[refA],
        lookup: (DiscoveryItem item) async => seriesMetadata(),
        starter: ({
          required MetadataItem metadata,
          required DiscoveryItem item,
          SeriesEpisode? episode,
          Duration? startPosition,
        }) async {
          startedPosition = startPosition;
        },
      );

      expect(result.status, ResumeStatus.started);
      expect(startedPosition, isNull);
    });
  });
}
