// ==SpectaExtension==
// @id com.specta.test.lifecycle
// @name Lifecycle Fixture
// @version 1.0.0
// @author SPECTA Tests
// @apiVersion 2
// @type movies_series
// @capabilities network,logging,search,latest,details,sources
// @description Deterministic local fixture proving the Phase 2H extension lifecycle.
// ==/SpectaExtension==
//
// A self-contained, network-free extension used by the real-QuickJS lifecycle
// tests. It exercises every contract operation SPECTA defines, plus request()
// and log(), without contacting any external website. It is NOT a movie-site
// extension and it holds no reference to any real content source.
class Extension extends SpectaExtension {
  constructor() {
    super();
    this.loaded = false;
  }

  async load() {
    this.loaded = true;
    this.log('info', 'lifecycle fixture loaded');
  }

  async capabilities() {
    return {
      contentTypes: ['movie', 'series'],
      discovery: { search: true, latest: true },
      metadata: { details: true, seasons: true, episodes: true },
      sources: { mp4: true, hls: false, multipleSources: true },
    };
  }

  async healthCheck() {
    return true;
  }

  async shutdown() {
    this.loaded = false;
  }

  async search(query, page) {
    return [
      {
        title: 'Fixture Movie ' + query,
        url: 'specta://fixture/movie/1',
        type: 'movie',
        year: 2021,
      },
      {
        title: 'Fixture Series ' + query,
        url: 'specta://fixture/series/1',
        type: 'series',
        year: 2022,
      },
    ];
  }

  async latest(page) {
    return [
      {
        title: 'Fixture Latest',
        url: 'specta://fixture/latest/1',
        type: 'movie',
        year: 2023,
      },
    ];
  }

  async details(url) {
    if (url.indexOf('series') !== -1) {
      return {
        id: 'fixture-series-1',
        title: 'Fixture Series',
        type: 'series',
        url: url,
        year: 2022,
        genres: ['Drama'],
        status: 'ongoing',
        seasons: [
          {
            seasonNumber: 1,
            title: 'Season 1',
            episodes: [
              {
                episodeNumber: 1,
                url: 'specta://fixture/series/1/s1e1',
                title: 'Pilot'
              },
              {
                episodeNumber: 2,
                url: 'specta://fixture/series/1/s1e2',
                title: 'Second'
              }
            ]
          }
        ]
      };
    }
    return {
      id: 'fixture-movie-1',
      title: 'Fixture Movie',
      type: 'movie',
      url: url,
      year: 2021,
      description: 'A deterministic local fixture.',
      genres: ['Test'],
      duration: 5400,
      rating: 7.5,
      status: 'completed'
    };
  }

  async getSources(reference) {
    return [
      {
        url: 'https://media.example.com/fixture.mp4',
        type: 'mp4',
        quality: '1080p',
        label: 'Fixture 1080p'
      }
    ];
  }

  async refreshSource(reference) {
    return {
      url: 'https://media.example.com/fixture.mp4',
      type: 'mp4',
      quality: '1080p'
    };
  }

  async ping() {
    return await this.request({ url: 'https://api.example.com/ping' });
  }
}
