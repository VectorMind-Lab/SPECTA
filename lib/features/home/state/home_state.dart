import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/media_item.dart';

/// State representation for the SPECTA Home presentation.
class HomeState {
  const HomeState({
    required this.spotlightItem,
    required this.continueWatching,
    required this.trending,
    required this.latestReleases,
    required this.isLoading,
  });

  final MediaItem spotlightItem;
  final List<MediaItem> continueWatching;
  final List<MediaItem> trending;
  final List<MediaItem> latestReleases;
  final bool isLoading;

  static const HomeState initial = HomeState(
    spotlightItem: MediaItem(
      id: 'spotlight-1',
      title: 'THE LAST HORIZON',
      type: MediaType.series,
      year: 2024,
      genres: <String>['Adventure', 'Sci-Fi'],
      qualityBadge: '4K HDR',
      overview:
          'In a distant future on the edge of charted space, a lone explorer journeys across the outer rim to recover the lost coordinates of humanity.',
      episodeInfo: 'S1 · E3',
      progressPercentage: 0.65,
      remainingDuration: '42m',
    ),
    continueWatching: <MediaItem>[
      MediaItem(
        id: 'cw-1',
        title: 'The Last Horizon',
        type: MediaType.series,
        year: 2024,
        genres: <String>['Adventure', 'Sci-Fi'],
        episodeInfo: 'S1 · E3',
        remainingDuration: '42m',
        progressPercentage: 0.65,
      ),
      MediaItem(
        id: 'cw-2',
        title: 'Breaking Dawn',
        type: MediaType.series,
        year: 2024,
        genres: <String>['Drama', 'Thriller'],
        episodeInfo: 'S2 · E5',
        remainingDuration: '38m',
        progressPercentage: 0.40,
      ),
      MediaItem(
        id: 'cw-3',
        title: 'Shadow Lines',
        type: MediaType.series,
        year: 2024,
        genres: <String>['Mystery', 'Crime'],
        episodeInfo: 'S1 · E1',
        remainingDuration: '46m',
        progressPercentage: 0.85,
      ),
      MediaItem(
        id: 'cw-4',
        title: 'The Hunters',
        type: MediaType.series,
        year: 2024,
        genres: <String>['Action', 'Thriller'],
        episodeInfo: 'S1 · E2',
        remainingDuration: '41m',
        progressPercentage: 0.20,
      ),
    ],
    trending: <MediaItem>[
      MediaItem(
        id: 'tr-1',
        title: 'Dune: Part Two',
        type: MediaType.movie,
        year: 2024,
        genres: <String>['Sci-Fi', 'Action'],
        qualityBadge: '4K',
        rating: 8.8,
      ),
      MediaItem(
        id: 'tr-2',
        title: 'The Boys',
        type: MediaType.series,
        year: 2019,
        genres: <String>['Action', 'Sci-Fi'],
        qualityBadge: '4K HDR',
        rating: 8.7,
      ),
      MediaItem(
        id: 'tr-3',
        title: 'Fallout',
        type: MediaType.series,
        year: 2024,
        genres: <String>['Action', 'Sci-Fi'],
        qualityBadge: '4K',
        rating: 8.4,
      ),
      MediaItem(
        id: 'tr-4',
        title: 'Shogun',
        type: MediaType.series,
        year: 2024,
        genres: <String>['Drama', 'History'],
        qualityBadge: '4K HDR',
        rating: 9.1,
      ),
    ],
    latestReleases: <MediaItem>[
      MediaItem(
        id: 'lr-1',
        title: 'Dune: Part Two',
        type: MediaType.movie,
        year: 2024,
        genres: <String>['Sci-Fi', 'Action'],
      ),
      MediaItem(
        id: 'lr-2',
        title: 'The Boys',
        type: MediaType.series,
        year: 2019,
        genres: <String>['Action'],
      ),
      MediaItem(
        id: 'lr-3',
        title: 'Fallout',
        type: MediaType.series,
        year: 2024,
        genres: <String>['Action'],
      ),
      MediaItem(
        id: 'lr-4',
        title: 'Shogun',
        type: MediaType.series,
        year: 2024,
        genres: <String>['Drama'],
      ),
    ],
    isLoading: false,
  );
}

final Provider<HomeState> homeStateProvider = Provider<HomeState>((Ref ref) {
  return HomeState.initial;
});
