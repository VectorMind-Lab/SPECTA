# SPECTA — Phase 2I Reference Extension Report

Phase: **2I — First real reference extension + end-to-end integration**
Date: 2026-09-24
Status: **PHASE 2I COMPLETE — REFERENCE EXTENSION IMPLEMENTED AND VERIFIED**
Reference provider: **Internet Archive** (`https://archive.org`)
Scope: one real extension + its verification. No Core change, no catalogue, no
push.

---

## 1. What this phase had to prove

Two things, and only two:

1. **SPECTA's extension architecture can integrate with a real, publicly
   reachable provider end to end:**

   ```
   search() -> SearchResult -> details() -> MediaDetails
           -> getSources() -> ExtensionSource
           -> SourceManager (validate + rank) -> SourcePool -> MediaKit
   ```

2. **Core stays provider-agnostic.** Remove this extension, install another
   compatible one, and Core must need no change.

Claim 2 is not left as an assertion in prose — it is enforced by a test
(§7.2).

## 2. Target selection history (recorded, not rewritten)

The owner's ORIGINAL Phase 2I target was **PrimeFlix (`https://primeflix.ru`)**.
A full forensic re-verification of the live site was performed before any
extension code was written, and the result was **BLOCKED_BY_TECHNICAL_PROTECTION**:

- the movie/TV catalogue is served from a private Supabase backend and
  anonymous requests to the catalogue tables are refused (HTTP 404 / RLS);
- TMDB-backed discovery is routed through authenticated edge functions;
- the playback path (`https://vidrock.ru/api/movie/<tmdbId>`) does **not**
  return a URL. It returns per-server obfuscated tokens (Nova/Atlas/Luna) that
  the shipped client decrypts with AES-GCM using a key embedded in the client
  bundle.

Reproducing that decryption inside an extension would mean extracting the
provider's client-side secret to obtain media the site does not hand out in the
clear. That is outside the project's access boundary, and it was **not** done.
No extension code was written for PrimeFlix and no PrimeFlix-specific logic
exists anywhere in SPECTA.

**The owner then re-selected Internet Archive as the Phase 2I reference
target**, explicitly as a technical reference to prove the architecture, with
the instruction not to turn it into a permanent dependency. That is what was
built.

## 3. Provider investigation (before any code was written)

Every fact below was verified against the live service on 2026-09-24 with
direct HTTP requests. Nothing here is assumed from documentation.

| Question | Finding |
| --- | --- |
| Publicly reachable? | Yes. HTTPS, no login required. |
| Public search? | Yes. `GET https://archive.org/advancedsearch.php?...&output=json` returned HTTP 200 JSON. `mediatype:movies AND collection:feature_films` reported `numFound: 28488`. |
| Public metadata? | Yes. `GET https://archive.org/metadata/<identifier>` returned HTTP 200 JSON with a `metadata` object and a `files[]` array. Responses measured 35–40 KB for the sampled items. |
| Playback URL publicly obtainable? | Yes. `GET https://archive.org/download/<identifier>/<file>` answers **302** with `Content-Type: video/mp4`, `Accept-Ranges: bytes`, and a `Location` on an `ia…`/`dn…` node over HTTPS. |
| Format? | Progressive **MP4** derivatives (`format: "h.264"`, `format: "512Kb MPEG4"`). The Archive also publishes Ogg Video, MPEG2, DivX and Matroska derivatives. |
| HLS? | Not exposed in the items' `files[]` lists. Declared `false` rather than claimed and failed later. |
| Authentication required? | No. |
| DRM? | No. |
| Security mechanism to bypass? | **None.** No anti-bot challenge, no paywall, no token to forge, nothing encrypted. |
| Seasons / episodes? | Not applicable. The Archive is an ITEM archive. |
| Subtitles? | Yes for some items: `SubRip` (`.srt`) derivatives. |
| Ratings? | Not published. |

Two real-world wrinkles were found and are handled explicitly:

- Some items are **restricted** (`is_dark: true`). The metadata response then
  contains no `metadata` object and no `files` array at all. Verified on the
  live `night_of_the_living_dead` item.
- Some items have **no MP4 derivative**, only an Ogg/MPEG2 master.

## 4. Deliverable

### 4.1 The extension

`extensions/internet_archive_reference.js` — a single-file SPECTA extension
with a `// ==SpectaExtension==` manifest header and a class named `Extension`,
exactly as the frozen Phase 1/2H contract requires.

```
// @id org.specta.reference.internetarchive
// @name Internet Archive (Reference)
// @version 1.0.0
// @apiVersion 2
// @type movie
// @capabilities network,logging,search,latest,details,sources
```

Implemented operations: `load`, `capabilities`, `search`, `latest`, `details`,
`getSources`, `refreshSource`, `healthCheck`, `shutdown`. Every network call
goes through the sandbox's controlled `request()` channel — there is no
`fetch`, no `XMLHttpRequest`, no native binding, and no credential.

The file is addressed to a human reader as much as to the engine: each
provider-specific decision states WHY it was made, and the header documents the
access boundary and the supported/unsupported capability set up front.

### 4.2 Capability mapping (what the reference target does and does not provide)

| SPECTA contract operation | Supported | Mapping |
| --- | --- | --- |
| `search(query, page)` | ✔ | `advancedsearch.php`, `q = mediatype:movies AND (title:(Q) OR description:(Q))`, paginated. |
| `latest(page)` | ✔ | Same endpoint, scoped to `collection:feature_films`, `sort[]=addeddate desc`. |
| `details(reference)` | ✔ | `/metadata/<id>` → title, year, description, genres, duration, artwork. |
| `getSources(reference)` | ✔ | Every `.mp4` derivative, as `SourceType.mp4`. |
| `refreshSource(reference)` | ✔ | Re-asks the provider; nothing is cached or replayed. |
| Subtitles | ✔ | `SubRip` derivatives attached to the matching video file. |
| Seasons / episodes | ✘ | Deliberate. Items are not series, and a multi-file item is the SAME work at several qualities — a season tree would be fabricated structure. `seasons` is always `[]`. |
| HLS | ✘ | Not exposed by the provider for these items. |
| DASH / DRM | ✘ | Does not exist here and is not attempted. |
| Ratings | ✘ | The provider publishes none; `rating` is omitted so SPECTA records "unknown". |

Honesty rules enforced in the extension:

- An unparsable **search row** is skipped individually; the rest of the
  response survives.
- A non-numeric year → `null`, never a guessed year.
- A **restricted item** → a distinguished failure ("not publicly available"),
  never a fabricated payload.
- A missing `metadata` object → its own distinguished failure.
- A non-JSON body or a non-2xx status → a failure naming the cause.
- A file is reported as MP4 only when its declared `format` AND its `.mp4`
  name agree. The `.ogv`, `.mpeg` and `.avi` files are never relabelled.
- `asr` (the provider's transcription marker) is **not** reported as a
  subtitle language.
- Genres are de-duplicated case-insensitively and capped; description HTML is
  reduced to prose.

### 4.3 No Core change

`git status` for this phase contains **no `lib/` change at all**. The reference
extension is a new file under `extensions/`, its fixtures under `test/`, and
this report. Source Manager, MediaKit, DownloadManager, the runtime, the
sandbox, the request policy, the signing protocol and the schema are untouched.

## 5. End-to-end chain, as actually exercised

The last group of the engine suite drives the real chain over recorded provider
data, through the real QuickJS engine and the real Core services:

```
DiscoveryCoordinator.discover(SearchRequest('chainprobe'))
  -> ExtensionManager -> reference extension search() -> 2 SearchResults
  -> normalisation + dedup -> 2 DiscoveryItems with preserved provenance
MetadataManager.metadataFor(item)
  -> details() -> MediaDetails -> normalisation -> MetadataItem
SourceManager.resolve(reference, {extensionId: referenceUrl})
  -> getSources() -> 2 ExtensionSources
  -> SourceValidator (both accepted)
  -> SourceRanker  -> SourcePool(ranked: 2)
       selected  = the 480p candidate   (SPECTA chose, not the extension)
       fallbacks = the 240p candidate
       subtitles survived to the selected candidate
```

Playback is the one link not covered by an automated test: MediaKit needs a
real media stack. It was verified on hardware in Phase 2E (5/5, including real
MP4 and HLS), and the live suite below verifies that the provider really does
serve a playable MP4 at the URL SPECTA would hand to it.

## 6. Deterministic fixtures

`test/support/fixtures/internet_archive/` — the normal automated suite NEVER
contacts the Internet Archive. Implemented fixtures, with provenance recorded
inside each file under `_fixture_note`:

| Fixture | Provenance |
| --- | --- |
| `search_movies.json` | **REAL** recording (advanced-search response). |
| `search_empty.json` | **REAL** recording (`numFound: 0`). |
| `metadata_feature_film.json` | **REAL** recording (`charlie_chaplin_film_fest`), trimmed of ~85 generated thumbnail entries. |
| `metadata_no_runtime.json` | **REAL** recording (second film; string `year`, absent `runtime`, AVI original). |
| `metadata_dark.json` | **REAL** recording (restricted item, verbatim). |
| `metadata_no_playable_file.json` | **DERIVED** from the real recording by removing the two `.mp4` entries. |
| `search_malformed.json` | **DERIVED** — real envelope, deliberately malformed rows. |
| `search_chain.json` | **DERIVED** — real envelope, the two real items with recorded metadata. |
| `metadata_no_metadata.json` | **SYNTHETIC**, labelled as such. |
| `error_not_json.txt` | **SYNTHETIC**, labelled as such. |

Nothing is presented as recorded data unless it was recorded. Two fixtures
carry hand-written hash fields only where the real values were fetched and
inserted verbatim.

## 7. Tests

### 7.1 Suites

| File | Tests | Engine needed | Covers |
| --- | --- | --- | --- |
| `test/core/extensions/reference/internet_archive_manifest_test.dart` | 9 | No | manifest completeness, exact capability set (least privilege), unsigned ⇒ never Official, every declared operation present, **no credential/authentication path in the file**, `request()`-only networking, and the **Core provider-agnosticism guard**. |
| `test/core/extensions/reference/internet_archive_engine_test.dart` | 24 | Yes (real QuickJS) | install/load/trust, `capabilities`, `search` (normal, empty, malformed, query sanitisation, determinism), `latest`, `details` (movie, string year + duration fallback, restricted, no-metadata, non-JSON, HTTP error, offline), `getSources` (MP4-only, ordering, subtitles, empty pool, restricted), `refreshSource`, `healthCheck`/`shutdown`, provider failure isolation, and the END-TO-END chain. |
| `test/core/extensions/reference/internet_archive_live_test.dart` | 4 (opt-in) | Yes + network | the real provider. |

The engine suite is skipped — and reported as unverified — when the flutter_js
QuickJS bridge is not loadable, exactly like the Phase 2H real-engine suite.

### 7.2 The architectural guard (rule 0.7)

`internet_archive_manifest_test.dart` scans **every `.dart` file under `lib/`**
for provider markers (`archive.org`, `internetarchive`, `internet archive`,
`mediatype:movies`, `charlie_chaplin`, `primeflix`, `vidrock`,
`advancedsearch.php`) and fails if any appears. It also asserts the scan
actually covered more than 50 files, so a broken walk cannot pass vacuously.

Result: **zero offenders.** The answer to the architectural test in the brief
("does Core require provider-specific code changes to replace this extension?")
is **NO**, and the test keeps it that way.

### 7.3 Validation results

| Gate | Result |
| --- | --- |
| `flutter analyze` | **No issues found** |
| `flutter test test/core/extensions/reference/` (bridge active) | **33 passed / 1 skipped / 0 failed** |
| `flutter test` (bridge active, full suite) | **850 passed / 1 skipped / 0 failed** — was 817/0/0 at Phase 2H |
| `SPECTA_LIVE_IA=1 flutter test …internet_archive_live_test.dart` | **4 passed / 0 failed** |

### 7.4 LIVE validation record (real provider, real network)

| Test | Result |
| --- | --- |
| LIVE-1 search | 30 real results retrieved from `archive.org`. |
| LIVE-2 details + sources + playable check | Item `a-thief-catcher-1914-directed-by-ford-sterling` resolved to `https://archive.org/download/a-thief-catcher-1914-directed-by-ford-sterling/A%20Thief%20Catcher%20(1914)%20Directed%20by%20Ford%20Sterling%20(colorized).mp4` (quality `360p`). An **independent** HEAD request on that URL returned **200 `content-type: video/mp4`**. |
| LIVE-3 impossible query | Empty result reported as success, not an error. |
| LIVE-4 restricted item | `night_of_the_living_dead` rejected with a distinguished, non-fabricated failure. |

LIVE-2 is the decisive evidence for the phase: the URL the extension produces
is one the real provider really serves as an MP4, confirmed by a probe that
does not go through the extension. It also exercised a filename containing
spaces and parentheses, confirming the per-segment URL encoding is correct on
real data rather than only on tidy fixtures.

Note on where a provider error message lives: a JavaScript `throw` inside an
extension surfaces to Dart as the runtime's `message` ("JS evaluation failed
for details") plus the provider reason in `ExtensionFailure.detail`. The tests
assert on both, so the provider reason is genuinely verified and not merely
present.

## 8. Access boundary — unchanged and not weakened

- No authentication, no paywall, no anti-bot control, no DRM and no encryption
  is bypassed anywhere in this phase. One target was **rejected** for requiring
  exactly that, and the report records why.
- The extension claims only the six capabilities it uses. `network` and
  `logging` are the only host channels it can reach.
- The extension holds no credential and no authentication mechanism at all —
  asserted by a test, because a hardcoded token in a public repository is
  exactly the failure mode that guard exists to catch.
- The typed-request channel, the request policy (scheme/method/URL-length/size
  caps, whole-request deadline, per-hop redirect re-evaluation, private-host
  blocking) and the capability gate apply to every call, unchanged.
- The signing protocol and `trusted_keys.dart` were not modified. No key was
  created, read, printed or logged. The reference extension is unsigned and
  installs as `unverified` — asserted through the real manager.

## 9. Known limitations (real, and none of them hidden)

- **Movie-only.** Series/seasons/episodes are not modelled for this provider,
  by deliberate decision. The series path is proven separately by the Phase 2H
  real-engine fixture (movie **and** series details with seasons/episodes).
- **No HLS** from this provider for these items.
- **Only MP4 derivatives** are reported. An item with no MP4 derivative yields
  an honestly empty source list.
- **Result quality is the provider's**, not SPECTA's: `search()` is deliberately
  unscoped over `mediatype:movies`, so it includes user uploads. This is
  provider data quality, not an architecture defect, and it is documented
  rather than papered over with a hidden allow-list.
- **No rating data** (the provider publishes none).
- **Artwork is a single image per item** (the provider exposes one), so
  `cover` and `backdrop` are the same URL.
- **Device/emulator validation of the reference extension itself was not
  performed**: no device and no AVD is attached to this session (`adb devices`
  is empty). What WAS validated is the real engine on the host (QuickJS via the
  Real-JS desktop bridge) plus the real provider over the network, and the fact
  that the exact same QuickJS engine ships inside the APK and was exercised on
  hardware in Phases 1/2E/2F/2G-C.
- The extension is unsigned. That is intentional: the production private key
  must never be in this repository, and an unsigned extension is correctly
  classified `unverified`.

## 10. What this phase deliberately did NOT do

- No Core change of any kind.
- No second extension API, no second source model, no second discovery path.
- No provider allow-list, block-list or preference anywhere in Core.
- No official catalogue, no `SPECTA-Extensions` repository, no marketplace.
- No resurrecting of the abandoned, uncommitted API-Adapter subsystem — see
  `docs/API_ADAPTER_SUBSYSTEM_AUDIT.md` for its disposition.
- No push.

## 11. Verdict

| Acceptance criterion | Verified |
| --- | --- |
| One real reference extension exists and is installable | ✔ |
| It targets a genuinely public, non-protected provider | ✔ |
| It uses the EXISTING extension contract (no second API) | ✔ |
| Search returns normalized `SearchResult`s | ✔ (fixtures + live) |
| Details returns a normalized `MediaDetails` (movie) | ✔ (fixtures + live) |
| Sources return validated `ExtensionSource`s | ✔ (fixtures + live) |
| The resolved source is a real playable MP4 | ✔ (independent HEAD 200 `video/mp4`) |
| It flows through SourceManager ranking into a `SourcePool` | ✔ |
| Provider failure is isolated, never a crash | ✔ |
| Restricted / malformed / offline data is handled honestly | ✔ |
| Deterministic fixtures; the default suite needs no network | ✔ |
| Live validation exists and is separated from the default suite | ✔ |
| Core contains no provider-specific logic | ✔ (enforced by test) |
| Extension can be replaced without changing Core | ✔ (guarded by test) |
| No credential, no authentication, no bypass | ✔ |
| No new dependency | ✔ |
| `flutter analyze` clean, relevant tests pass | ✔ |
| Documentation updated accurately | ✔ |
| No push performed | ✔ |

**PHASE 2I COMPLETE.**
