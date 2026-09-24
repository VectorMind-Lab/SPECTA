// ==SpectaExtension==
// @id org.specta.reference.internetarchive
// @name Internet Archive (Reference)
// @version 1.0.0
// @author SPECTA
// @apiVersion 2
// @type movie
// @capabilities network,logging,search,latest,details,sources
// @description Phase 2I reference extension for the Internet Archive's public movie collection.
// @website https://archive.org
// ==/SpectaExtension==
//
// ---------------------------------------------------------------------------
// SPECTA — Phase 2I REFERENCE EXTENSION (Internet Archive)
// ---------------------------------------------------------------------------
//
// PURPOSE. This file exists to prove that the SPECTA extension architecture can
// integrate with a REAL, publicly reachable provider end to end:
//
//   search() -> SearchResult -> details() -> MediaDetails
//            -> getSources() -> ExtensionSource -> SourceManager -> MediaKit
//
// It is a REFERENCE, not a provider endorsement. Nothing in SPECTA Core knows
// the Internet Archive exists: every provider-specific detail (URLs, query
// syntax, response shape, which files are playable) lives in this file, and the
// numbers below are the Archive's own documented and observed behaviour. The
// Core only ever sees the normalised extension contract.
//
// Remove this file and install any other compatible extension: Core needs no
// change. That is the architectural test this extension is here to satisfy.
//
// ---------------------------------------------------------------------------
// WHAT THIS EXTENSION SUPPORTS (and what it deliberately does not)
// ---------------------------------------------------------------------------
//
// SUPPORTED
//   search(query, page)   Archive advanced search over `mediatype:movies`.
//   latest(page)          The Archive's curated public-domain feature-film
//                         collection, newest first.
//   details(identifier)   Item metadata (title, year, description, genres,
//                         duration, artwork), read from the public
//                         `https://archive.org/metadata/<id>` endpoint.
//   getSources(id)        Every browser-playable MP4 derivative of the item,
//                         as `SourceType.mp4` candidates. SPECTA validates,
//                         ranks and selects among them — this extension only
//                         reports what the Archive exposes.
//   refreshSource(id)     Re-asks the metadata endpoint. Archive download URLs
//                         are signed-by-path rather than time-limited, but the
//                         correct way to renew any URL is to ask the provider
//                         again, so that is what happens: nothing is cached and
//                         no stale URL is ever replayed.
//   Subtitles             The Archive's SubRip (`.srt`) derivatives that belong
//                         to a given video file are reported as subtitle
//                         tracks on that source.
//
// NOT SUPPORTED (deliberate, documented — not an oversight)
//   * Series / seasons / episodes. The Archive is an ITEM archive, not a
//     catalogue with a season/episode structure. A multi-file item is the SAME
//     work at different derivative qualities, NOT a season of episodes, so
//     inventing a season tree would fabricate structure that does not exist.
//     Every item is reported as `movie` and `seasons` is always empty.
//   * HLS. The Archive publishes progressive derivatives for these items; the
//     files list exposes no M3U8 playlist, so `hls` is declared false rather
//     than claimed and then failed at playback time.
//   * DASH, and any DRM / access control. None exists here and none is
//     attempted.
//   * Ratings. The Archive publishes no rating. `rating` is omitted so SPECTA
//     records "unknown" — an invented score would be worse than no score.
//
// ---------------------------------------------------------------------------
// ACCESS AND SAFETY BOUNDARY (unchanged, not weakened)
// ---------------------------------------------------------------------------
//
// Every network call goes through the sandbox's `request()` channel, so the
// host request policy (scheme allow-list, method allow-list, URL length cap,
// response size cap, whole-request deadline, per-hop redirect re-evaluation,
// private/loopback host blocking) applies to all of it. This file claims no
// capability it does not need, touches no filesystem, and holds no credential:
// the Internet Archive's search and metadata endpoints are genuinely public.
//
// It does not authenticate, does not bypass a paywall, does not defeat an
// anti-bot control, and does not decrypt anything. Where an item is restricted
// by the Archive itself (`is_dark`), this extension reports an honest failure
// instead of working around it.
//
// ---------------------------------------------------------------------------

class Extension extends SpectaExtension {
  constructor() {
    super();

    // Public Internet Archive JSON endpoints (verified against the live
    // service; see docs/PHASE_2I_REFERENCE_EXTENSION_REPORT.md).
    this.ADVANCED_SEARCH = 'https://archive.org/advancedsearch.php';
    this.METADATA = 'https://archive.org/metadata/';
    this.DOWNLOAD = 'https://archive.org/download/';
    this.THUMBNAIL = 'https://archive.org/services/img/';

    // `latest()` is scoped to the Archive's curated public-domain feature-film
    // collection. Scoping is a provider decision made INSIDE the extension: an
    // unscoped "newest movies" feed across the whole Archive is dominated by
    // user uploads and makes a poor default rail. `search()` is deliberately
    // NOT scoped, so a user searching for a title the Archive holds elsewhere
    // still finds it.
    this.LATEST_COLLECTION = 'feature_films';

    this.PAGE_SIZE = 30;
    this.REQUEST_TIMEOUT_MS = 20000;

    // Container/format vocabulary the Archive uses in its `files[]` entries
    // for progressive MP4 derivatives. Only MP4 is reported: the Archive also
    // publishes Ogg Video, MPEG2, DivX and Matroska derivatives, and this
    // extension is a movie-only reference target, NOT a tour of the Archive's
    // format zoo. Claiming an `.ogv` file as `type: 'mp4'` would be a lie the
    // Source Manager would then have to live with.
    this.MP4_FORMATS = ['h.264', '512Kb MPEG4', 'MPEG4', 'HiRes MPEG4'];

    // Subtitle derivatives the Archive produces.
    this.SUBTITLE_FORMATS = ['SubRip', 'Web Video Text Tracks'];
  }

  // -- lifecycle -----------------------------------------------------------

  async load() {
    this.log('info', 'Internet Archive reference extension loaded');
  }

  // De-clared capabilities, in the shape SPECTA's contract expects. Every
  // claim here is checked by the reference test suite against what the
  // extension can actually do.
  async capabilities() {
    return {
      contentTypes: ['movie'],
      discovery: { search: true, latest: true },
      metadata: { details: true, seasons: false, episodes: false },
      sources: {
        mp4: true,
        hls: false,
        multipleSources: true,
        multipleQualities: true,
        headers: false,
        subtitles: true,
        audioTracks: false
      },
      downloads: { supported: true },
      pagination: { search: true, latest: true }
    };
  }

  // No network here on purpose: healthCheck() is called by the Extensions
  // surface and must not spend a request per repaint. It answers "is this
  // extension's code alive and responsive", not "is archive.org up" — a
  // provider outage is reported honestly by the operation that hits it.
  async healthCheck() {
    return true;
  }

  async shutdown() {}

  // -- discovery -----------------------------------------------------------

  async search(query, page) {
    return await this._searchRound(this._queryFor(query), page, null);
  }

  async latest(page) {
    return await this._searchRound(
      'mediatype:movies AND collection:' + this.LATEST_COLLECTION,
      page,
      'addeddate desc'
    );
  }

  // -- metadata ------------------------------------------------------------

  async details(reference) {
    const item = await this._item(reference, 'details');
    const metadata = item.metadata;
    const files = item.files;

    const title = this._str(metadata.title) || this._str(metadata.identifier);
    if (!title) {
      throw new Error(
        'Internet Archive item has no title at the expected location'
      );
    }

    const videos = this._videoFiles(files);

    return {
      id: this._identifier(reference),
      title: title,
      type: 'movie',
      url: this._identifier(reference),
      cover: this.THUMBNAIL + encodeURIComponent(this._identifier(reference)),
      backdrop: this.THUMBNAIL + encodeURIComponent(this._identifier(reference)),
      year: this._yearOf(metadata),
      description: this._plainText(metadata.description),
      genres: this._subjects(metadata.subject),
      duration: this._durationSeconds(metadata.runtime, videos),
      // `rating` is intentionally absent: the Archive publishes none.
      // `seasons` is always empty: see the file header — items are not series,
      // and a multi-file item is the same work at several qualities.
      seasons: []
    };
  }

  // -- sources -------------------------------------------------------------

  async getSources(reference) {
    const item = await this._item(reference, 'getSources');
    const videos = this._videoFiles(item.files);
    const identifier = this._identifier(reference);

    const out = [];
    for (let i = 0; i < videos.length; i++) {
      const file = videos[i];
      const source = {
        url: this._fileUrl(identifier, file.name),
        type: 'mp4',
        label: 'Source ' + (i + 1)
      };

      const quality = this._qualityFor(file);
      if (quality) source.quality = quality;

      const subtitles = this._subtitlesFor(identifier, item.files, file.name);
      if (subtitles.length > 0) source.subtitles = subtitles;

      out.push(source);
    }
    return out;
  }

  async refreshSource(reference) {
    // Ask the provider again rather than reusing anything. Archive source URLs
    // are not persisted by SPECTA at all, so a "refresh" here is simply a
    // fresh resolution; returning the first surviving candidate is the honest
    // answer when the caller only wants one.
    const sources = await this.getSources(reference);
    if (!sources || sources.length === 0) {
      throw new Error(
        'Internet Archive returned no playable source for this item'
      );
    }
    return sources[0];
  }

  // ========================================================================
  // Provider-specific helpers. Every one of these encodes knowledge about the
  // Internet Archive and nothing else; none of it belongs in SPECTA Core.
  // ========================================================================

  // -- search --------------------------------------------------------------

  // Builds the Archive's Solr-ish query for `mediatype:movies`.
  //
  // Sanitisation, stated plainly: the Archive's search syntax has operators
  // (`:`, `(`, `)`, `"`, `+`, `-`, `&&`, `||`, `*`, `~`, `\`, ...) and a user's
  // typed title is not a query. Rather than attempt brittle per-character
  // escaping, every operator character is REMOVED and the remaining terms are
  // searched against title or description. A query made entirely of operator
  // characters therefore degrades to "all movies" instead of an invalid query.
  _queryFor(query) {
    const raw = this._str(query);
    const cleaned = raw
      ? raw
          .replace(/[+\-&|!(){}\[\]^"~*?:\\\/]/g, ' ')
          .replace(/\s+/g, ' ')
          .trim()
      : '';
    if (cleaned.length === 0) return 'mediatype:movies';
    return (
      'mediatype:movies AND (title:(' + cleaned + ') OR description:(' + cleaned + '))'
    );
  }

  _searchUrl(query, page, sort) {
    let url =
      this.ADVANCED_SEARCH +
      '?q=' + encodeURIComponent(query) +
      '&fl%5B%5D=identifier' +
      '&fl%5B%5D=title' +
      '&fl%5B%5D=year' +
      '&rows=' + this.PAGE_SIZE +
      '&page=' + page +
      '&output=json';
    if (sort) {
      url += '&sort%5B%5D=' + encodeURIComponent(sort);
    }
    return url;
  }

  async _searchRound(query, page, sort) {
    const requested = this._toInt(page);
    const safePage = requested && requested > 0 ? requested : 1;

    const document = await this._getJson(this._searchUrl(query, safePage, sort));
    const response = document ? document.response : null;
    const docs = response && response.docs ? response.docs : null;
    if (!docs || !Array.isArray(docs)) return [];

    const out = [];
    for (let i = 0; i < docs.length; i++) {
      const doc = docs[i];
      if (!doc || typeof doc !== 'object') continue;

      const identifier = this._str(doc.identifier);
      const title = this._str(doc.title);
      // One unparsable row is skipped; the rest of the response survives.
      if (!identifier || !title) continue;

      out.push({
        title: title,
        url: identifier,
        type: 'movie',
        cover: this.THUMBNAIL + encodeURIComponent(identifier),
        year: this._toInt(doc.year)
      });
    }
    return out;
  }

  // -- item metadata -------------------------------------------------------

  _identifier(reference) {
    const identifier = this._str(reference);
    if (!identifier) {
      throw new Error('No Internet Archive item identifier was provided');
    }
    return identifier;
  }

  // Fetches and validates one `/metadata/<id>` document.
  //
  // Failure modes are reported honestly and distinctly, because they mean
  // different things to a user: a restricted item (`is_dark`) is a policy
  // outcome, a missing metadata object is a shape the Archive does not serve,
  // and a transport failure is a network problem.
  async _item(reference, operation) {
    const identifier = this._identifier(reference);
    const document = await this._getJson(
      this.METADATA + encodeURIComponent(identifier)
    );

    if (!document || typeof document !== 'object') {
      throw new Error(
        'Internet Archive returned no metadata document for "' + identifier + '"'
      );
    }
    if (document.is_dark === true) {
      throw new Error(
        'Internet Archive item "' + identifier + '" is not publicly available'
      );
    }
    const metadata = document.metadata;
    if (!metadata || typeof metadata !== 'object') {
      throw new Error(
        'Internet Archive item "' + identifier + '" exposes no metadata'
      );
    }

    return {
      metadata: metadata,
      files: Array.isArray(document.files) ? document.files : [],
      operation: operation
    };
  }

  // The playable MP4 files of an item, in the order the Archive lists them.
  //
  // Two independent conditions must BOTH hold, because either one alone is
  // wrong: the Archive labels a file "MPEG4" while the name says `.mp4` and the
  // container really is MP4, but it also labels Ogg/MPEG2/DivX derivatives with
  // formats this list does not contain, and names some files `.ogv` while
  // reporting an MP4-ish format. Requiring the declared format AND an `.mp4`
  // name is the only combination that never mislabels a file as an MP4 that
  // SPECTA's player cannot open as one.
  //
  // `source: original` is deliberately NOT excluded: for items uploaded as MP4,
  // the original IS the best available file, and dropping it would remove the
  // highest-quality source for no reason. The format+name pair already excludes
  // the AVI/MPEG2/Matroska originals that motivated the old rule.
  _videoFiles(files) {
    if (!Array.isArray(files)) return [];
    const out = [];
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      if (!file || typeof file !== 'object') continue;

      const name = this._str(file.name);
      if (!name) continue;

      const format = this._str(file.format);
      if (!format || this.MP4_FORMATS.indexOf(format) === -1) continue;

      if (!this._hasMp4Extension(name)) continue;

      out.push(file);
    }
    return out;
  }

  _hasMp4Extension(name) {
    const lower = name.toLowerCase();
    return lower.length > 4 && lower.substring(lower.length - 4) === '.mp4';
  }

  // `https://archive.org/download/<id>/<name>`, with each path segment encoded
  // separately so a name containing a subdirectory keeps its separator while
  // spaces and brackets are escaped. A single encodeURIComponent over the whole
  // name would turn `/` into `%2F` and break such items.
  _fileUrl(identifier, name) {
    const segments = String(name).split('/');
    const encoded = [];
    for (let i = 0; i < segments.length; i++) {
      encoded.push(encodeURIComponent(segments[i]));
    }
    return this.DOWNLOAD + encodeURIComponent(identifier) + '/' + encoded.join('/');
  }

  // A neutral quality label derived from the Archive's own reported height.
  // Null when the Archive did not declare a height, which SPECTA's ranker
  // handles explicitly as "unknown" — an invented resolution would be worse.
  _qualityFor(file) {
    const height = this._toInt(file.height);
    if (!height || height <= 0) return null;
    if (height >= 2000) return '4K';
    return height + 'p';
  }

  // Subtitle derivatives that belong to `videoName`. The Archive names them
  // after the video (`<base>.srt`, `<base>.en.srt`, `<base>.asr.srt`). Only
  // mentions whose stem starts with the video's own stem are attached: a
  // subtitle for a different file in the same item would be a wrong-language,
  // wrong-content track, which is worse than no subtitle.
  _subtitlesFor(identifier, files, videoName) {
    if (!Array.isArray(files)) return [];
    const stem = this._stem(videoName);
    const out = [];
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      if (!file || typeof file !== 'object') continue;

      const format = this._str(file.format);
      if (!format || this.SUBTITLE_FORMATS.indexOf(format) === -1) continue;

      const name = this._str(file.name);
      if (!name) continue;
      if (this._stem(name).indexOf(stem) !== 0) continue;

      const track = {
        url: this._fileUrl(identifier, name)
      };
      const language = this._languageFor(name, stem);
      if (language) {
        track.language = language;
        track.label = language.toUpperCase();
      }
      out.push(track);
    }
    return out;
  }

  _stem(name) {
    const lower = String(name).toLowerCase();
    const slash = lower.lastIndexOf('/');
    const base = slash === -1 ? lower : lower.substring(slash + 1);
    const dot = base.lastIndexOf('.');
    return dot === -1 ? base : base.substring(0, dot);
  }

  // `foo.en.srt` -> `en`; `foo.srt` -> null (the Archive does not always say).
  //
  // Only a two-letter ISO 639-1 code is accepted. The Archive's other suffix in
  // this position is `asr` (its automatic-speech-recognition marker), which is
  // NOT a language: reporting it as one would tell the user a track is in a
  // language called "ASR". An unrecognised suffix degrades to no language and
  // no label, which is the honest answer — the track is still offered.
  _languageFor(name, stem) {
    const own = this._stem(name);
    if (own.length <= stem.length) return null;
    const rest = own.substring(stem.length).replace(/^[.\-_]/, '');
    if (!/^[a-z]{2}$/.test(rest)) return null;
    return rest;
  }

  _durationSeconds(runtime, videos) {
    const fromRuntime = this._parseRuntime(runtime);
    if (fromRuntime) return fromRuntime;

    // Fall back to a derivative's own length when the Archive publishes no
    // `runtime` field (it often does not).
    if (videos && videos.length > 0) {
      const seconds = this._toInt(videos[0].length);
      if (seconds && seconds > 0) return seconds;
    }
    return null;
  }

  // `1:17:26` or `77:26` -> seconds. Null when unparseable, never a guess.
  _parseRuntime(runtime) {
    const text = this._str(runtime);
    if (!text) return null;
    const parts = text.split(':');
    if (parts.length < 2 || parts.length > 3) return null;

    let total = 0;
    for (let i = 0; i < parts.length; i++) {
      const value = this._toInt(parts[i]);
      if (value === null || value < 0) return null;
      total = total * 60 + value;
    }
    return total > 0 ? total : null;
  }

  _yearOf(metadata) {
    const year = this._toInt(metadata.year);
    if (year) return year;

    // The Archive carries either `year` or a `date`, and `date` is often a
    // full date (`1955-01-01`) or just a year. Only a plausible four-digit
    // leading year is accepted; anything else stays unknown.
    const date = this._str(metadata.date);
    if (date && date.length >= 4) {
      const leading = this._toInt(date.substring(0, 4));
      if (leading && leading > 1800 && leading < 2200) return leading;
    }
    return null;
  }

  // The Archive's `subject` is a single string with `;` or `,` separators, or
  // occasionally a real array. Both shapes are handled; entries are trimmed,
  // de-duplicated case-insensitively and capped, because some items carry
  // dozens of near-duplicate tags.
  _subjects(subject) {
    const raw = [];
    if (Array.isArray(subject)) {
      for (let i = 0; i < subject.length; i++) raw.push(subject[i]);
    } else if (this._str(subject)) {
      const parts = this._str(subject).split(/[;,]/);
      for (let i = 0; i < parts.length; i++) raw.push(parts[i]);
    }

    const seen = {};
    const out = [];
    for (let i = 0; i < raw.length && out.length < 12; i++) {
      const value = this._str(raw[i]);
      if (!value) continue;
      if (value.length > 60) continue;
      const key = value.toLowerCase();
      if (seen[key]) continue;
      seen[key] = true;
      out.push(value);
    }
    return out;
  }

  // Descriptions are frequently HTML fragments. Tags are removed and the
  // common entities decoded so the details screen shows prose, not markup.
  // This is presentation cleanup of provider data, not sanitisation of
  // untrusted input for a browser context.
  _plainText(value) {
    const text = this._str(value);
    if (!text) return null;

    let out = text.replace(/<[^>]*>/g, ' ');
    out = out
      .replace(/&nbsp;/gi, ' ')
      .replace(/&amp;/gi, '&')
      .replace(/&lt;/gi, '<')
      .replace(/&gt;/gi, '>')
      .replace(/&quot;/gi, '"')
      .replace(/&#0?39;/g, "'")
      .replace(/&#x27;/gi, "'");
    out = out.replace(/\s+/g, ' ').trim();
    if (out.length === 0) return null;
    return out.length > 4000 ? out.substring(0, 4000) : out;
  }

  // -- transport -----------------------------------------------------------

  // The ONLY network entry point in this file. Every failure is surfaced as a
  // thrown Error, which the runtime converts into a structured, attributed
  // failure: a provider problem is reported honestly and never silently
  // becomes an empty result list that looks like "no movies found".
  async _getJson(url) {
    const response = await this.request({
      url: url,
      method: 'GET',
      timeout: this.REQUEST_TIMEOUT_MS
    });

    if (!response || response.ok !== true) {
      let detail = 'no response';
      if (response) {
        if (response.errorType) detail = response.errorType;
        if (response.error) detail = response.error;
        if (response.status) detail = 'HTTP ' + response.status;
      }
      throw new Error('Internet Archive request failed: ' + detail);
    }

    if (!response.json) {
      throw new Error('Internet Archive returned a response that is not JSON');
    }
    return response.json;
  }

  // -- primitives ----------------------------------------------------------

  _str(value) {
    if (value === null || value === undefined) return null;
    if (typeof value === 'string') {
      const trimmed = value.trim();
      return trimmed.length === 0 ? null : trimmed;
    }
    if (typeof value === 'number') return String(value);
    return null;
  }

  _toInt(value) {
    if (value === null || value === undefined) return null;
    if (typeof value === 'number') {
      return isFinite(value) ? Math.trunc(value) : null;
    }
    if (typeof value === 'string') {
      const text = value.trim();
      if (text.length === 0) return null;
      const parsed = parseInt(text, 10);
      return isNaN(parsed) ? null : parsed;
    }
    return null;
  }
}
