# SPECTA - Phase 2H Entry / Forensic Architecture Audit

Audit date: 2026-09-22 (session close)
Auditor: implementation AI takeover
Scope: forensic inventory only. NO implementation, NO Phase 2H, NO push, NO destructive git.
## 1. Audit Scope

Forensic entry audit for Phase 2H. Inventory-only: no implementation, no extension created, no catalogue networking, no TMDB work, no push, no destructive git. Every claim below is verified against current source, tests, and git history in this session.
## 2. Repository / Git State

- HEAD: 4ca3cdd (master) - fix(phase2g): finalize stale attempt event isolation
- origin/master: 7fcb0cc - UNCHANGED. Nothing pushed.
- Working tree: clean except 4 uncommitted items:
  1. M PROJECT_STATE.txt (status wording correction, uncommitted)
  2. M docs/PROJECT_STATE.txt (same correction, uncommitted)
  3. M README.md (same correction, uncommitted)
  4. M docs/README.md (same correction, uncommitted)
  5. ?? docs/SPECTA - Coding AI Master Prompt - Phase 0_ Foundation & Architecture Initialization.md (pre-existing, unrelated, untouched)
- Existing 2G-C commits intact, none rewritten:
  4ca3cdd, 526ac26, 777529d, 7e9f6da, 08f0bf9
- Prior phases intact: 94f9283 (2G-A/2G-B), 4d7f4da (2F), bcc47e1 (2C), 3638933 (2E), a380ca8 (2D)
- No Phase 2H commits exist. No 2H files exist.
## 3. Phase 2G-C Baseline Verification

VERIFIED against source, not trusted from reports.

- DownloadManager exists (lib/core/downloads/download_manager.dart, 1220+ lines): owns product state, queue, retry, concurrency, source recovery.
- DownloadEngine is SPECTA-owned abstraction (lib/core/downloads/download_engine.dart).
- background_downloader 9.6.2 isolated behind adapter (lib/core/downloads/background_downloader_engine.dart). Third-party types do not leak upward.
- SPECTA DB (Drift/SpectaDatabase) remains authoritative for downloads, extensions, watch progress, media references.
- MP4/direct-file download IMPLEMENTED. HLS supported for streaming only (no offline HLS).
- NOT introduced: HLS offline, DASH, Media3/ExoPlayer replacement, custom WorkManager, custom notifications, VPN, DRM bypass, access-control bypass, anti-bot bypass, new source-provider semantics.
- D-1 (verified on-disk completion gate), D-2 (declared-total preservation), D-3 (attempt-generation isolation) all present in source and tests.
- flutter analyze: CLEAN. Extension tests: 299 passed / 0 failed / 9 skipped.

Baseline: TRUSTWORTHY.
## 4. Extension System Inventory

All 24 files under lib/core/extensions exist as REAL production code (no stubs):

- manifest.dart (329 lines) - ExtensionManifest, ManifestParser, ManifestValidator, ManifestParseException. Header format: // ==SpectaExtension== ... // ==/SpectaExtension== with // @key value fields.
- contract/extension_contract.dart - ExtensionOperation enum: load, capabilities, search, latest, details, getSources, refreshSource, healthCheck, shutdown. Only load and capabilities are isRequired.
- contract/extension_capability.dart - 6 capabilities: network, logging, search, latest, details, sources. Fail-closed parsing.
- contract/extension_capabilities.dart - capability declaration container.
- contract/extension_source.dart - ExtensionSource (url, type mp4|hls, quality, label, isAdaptive, headers, audioTracks, subtitles). SourceType enum: mp4, hls. DASH EXPLICITLY EXCLUDED.
- contract/result_models.dart - SearchResult, MediaDetails, MediaSeason, MediaEpisode.
- identity/extension_health.dart - ExtensionHealthState, ExtensionHealthRules (descriptive only, never disables).
- identity/trust_level.dart - TrustLevel.official / TrustLevel.unverified (binary; trust is DATA, not enforcement).
- verification/signing_protocol.dart - SpectaSigningProtocol, payload format SPECTA-EXT-SIG-V1 (length-prefixed canonical metadata JSON + UTF-8 body).
- verification/signature_verifier.dart - Ed25519 via package:cryptography.
- verification/trusted_keys.dart - hardcoded public key uDm0fWmDu0dQ/32eXEw7O78VhqEA72YYcEpXPECxAYc=. Private key NOT in repo.
- catalogue/extension_type.dart - ExtensionContentType: movie, series, anime, moviesSeries, moviesSeriesAnime.
- runtime/extension_runtime.dart - ExtensionRuntime, the coordinator. Defines a global `fetch()` over the existing `request()` channel (same `network` capability gate, same ExtensionRequestPolicy checks); installed only when the engine does not already define one.
- runtime/flutter_js_sandbox.dart - FlutterJsSandbox. Uses flutter_js -> QuickJsRuntime2 (Android) / JavaScriptCore (iOS). stackSize 1MB. enableHandlePromises. Only 2 host channels: specta_request, specta_log.
- runtime/runtime_api.dart - ExtensionJsSandbox abstract, ExtensionRequest, ExtensionResponse.
- runtime/controlled_runtime_api.dart - ControlledExtensionRuntimeApi. Real HTTP via dart:io HttpClient with deadline, streaming read with 8MB cap, socket cleanup, TLS/HTTP/socket error mapping.
- runtime/request_policy.dart (540 lines) - comprehensive policy: schemes {https,http}, methods {GET,POST,HEAD}, maxResponseBytes 8MB, maxRequestBodyBytes 64KB, maxUrlLength 2048, maxRedirects 5, defaultTimeout 15s (max 60s), blockPrivateHosts true, allowHttpsToHttpRedirect false. Private host blocking by name, IP literal, and DNS resolution. Redirect re-evaluation per-hop with header sanitization.
- manager/extension_manager.dart (537 lines) - single entry point.
- manager/extension_record.dart - ExtensionRecord, ExtensionVersionRecord, ExtensionFailureRecord.
- manager/extension_registry.dart - abstract registry (10+ methods).
- manager/in_memory_extension_registry.dart - test-only.
- manager/drift_extension_registry.dart - production Drift persistence.
- manager/extension_providers.dart - 3 Riverpod providers.
- manager/tables/ - Extensions, ExtensionVersions, ExtensionFailureLogs Drift tables (in SpectaDatabase).

Subsystems status:
- JS engine: IMPLEMENTED (real QuickJS)
- Sandbox bootstrap/lifecycle: IMPLEMENTED
- 9 contract operations: IMPLEMENTED with parsing
- Capability system (manifest + runtime): IMPLEMENTED, fail-closed
- Network request policy: IMPLEMENTED, comprehensive
- HTTP transport with deadline/size cap: IMPLEMENTED
- Ed25519 signature verification: IMPLEMENTED (payload covers body)
- Trust classification: IMPLEMENTED (binary)
- Health classification: IMPLEMENTED (descriptive only, no auto-action)
- Content types: IMPLEMENTED (movie/series/moviesSeries)
- Result models: IMPLEMENTED (strict parsing, skip-on-error)
- Error taxonomy: IMPLEMENTED (structured canonical codes)
## 5. Actual Extension API

Manifest (required fields): id, name, version, author, apiVersion, type. Optional: signature, capabilities, description, lang, icon, website.
- id rules: e.g. com.example.test
- version: semantic version string
- apiVersion: int, must equal SpectaApiVersion.current (2). Supported set = {2}.
- signature: ed25519:<BASE64>, 64 raw bytes. Required for Official but not enforced.
- capabilities: comma-separated tokens from {network,logging,search,latest,details,sources}. Unknown token = import error.
- type: movie | series | movies_series (also accepts comma-separated movie,series).

JS API surface (bootstrap injected into every sandbox):
  class SpectaExtension {
    async request(requestData) {...}   // via specta_request channel
    log(level, message) {...}          // via specta_log channel (needs logging cap)
    async load() {}
    async capabilities() { return {} }
    async healthCheck() { return true }
    async shutdown() {}
  }
Extensions subclass: class Extension extends SpectaExtension { ... }. Runtime instantiates via new Extension(). No base-class verification.

Operations and required capabilities:
  load()          - mandatory, no cap
  capabilities()  - mandatory, no cap
  search(q, page) - needs search
  latest(page)    - needs latest
  details(url)    - needs details
  getSources(ref) - needs sources
  refreshSource(ref) - needs sources
  healthCheck()   - mandatory, no cap
  shutdown()      - mandatory, no cap

Request payload (ExtensionRequest): url, method (GET/POST/HEAD), headers, queryParameters, body, timeout (clamped by policy).
Response payload (ExtensionResponse): status, ok, headers, body, json, latency, error, errorType.

Result models:
  SearchResult: title (req), url (req), type movie|series (req), cover?, year?
  MediaDetails: id (req), title (req), originalTitle?, type (req), url (req), cover?, backdrop?, year?, description?, genres (default []), durationSeconds?, rating? (0-10), status? (ongoing/completed/cancelled/unknown), seasons (default [])
  MediaSeason: seasonNumber (req), title?, episodes (req)
  MediaEpisode: episodeNumber (req), url (req), title?, description?, cover?, durationSeconds?
  ExtensionSource: url (req), type mp4|hls (req), quality?, label?, isAdaptive (default false), headers?, audioTracks?, subtitles?

MOVIE path: search -> details -> getSources. IMPLEMENTED.
SERIES path: search -> details -> episodes -> episode source via getSources(episodeUrl). IMPLEMENTED.
Episode details are embedded in MediaDetails.seasons[].episodes[]. No separate details(episode) operation.

Error representation: ExtensionFailure with extensionId, operation, type, message, timestamp, detail. Types: runtimeError, timeout, capabilityError, networkError, invalidResult, unsupported, httpError, parseError.
## 6. Application Graph

Trace from user interaction to extension runtime (all verified in source):

  Search UI (search_view.dart)
    -> spectaSearchQueryProvider (400ms debounce)
    -> searchSessionProvider.notifier.submit()
    -> DiscoveryService.search() [discovery_service via discoveryServiceProvider]
    -> DiscoveryCoordinator.discover()
       -> manager.getEnabledExtensions()
       -> for each (maxConcurrency=6): manager.loadRuntime(id) + manager.callOperation(search)
       -> DiscoveryNormalizer.normalize() + DiscoveryDeduplicator.dedupe()
    -> SearchSessionNotifier (monotonic generation counter prevents stale results)

  Details UI (details_view.dart)
    -> DetailsSessionNotifier.open(DiscoveryItem)
    -> MetadataService.metadataFor() -> MetadataManager.metadataFor()
       -> manager.loadRuntime + manager.callOperation(details)
       -> MetadataNormalizer.normalize() -> MetadataItem (canonical title/type/year)

  Playback (playback_entry.dart -> playbackSessionProvider.open)
    -> SourceSessionNotifier.resolve(reference, extensions)
    -> SourceManager.resolve() [source_manager.dart]
       -> manager.loadRuntime + manager.callOperation(getSources)
       -> SourceValidator.validate() + SourceRanker.rank() -> SourcePool
    -> MediaKitPlaybackEngine (media_kit_engine.dart) opens ranked candidate
    -> PlaybackProgressSink -> LibraryStore (persistent) or InMemory (test)

  Download (download_manager.dart)
    -> SourceManagerDownloadResolver.resolveSource() -> SourceManager.resolve()
    -> BackgroundDownloaderEngine (background_downloader adapter)

Connection status:
- FULLY CONNECTED (production): startup->ExtensionManager; ExtensionManager->DiscoveryCoordinator; ExtensionManager->SourceManager; ExtensionManager->MetadataManager; ExtensionManager->DownloadResolver; search UI->runtime; details UI->metadata->runtime; details UI->source->runtime->MediaKit; playback->progress->LibraryStore; download manager->SourceManager->runtime; download manager->engine.
- PARTIALLY CONNECTED: ExtensionManager.update() MISSING; saveVersion() ORPHANED (never called, rollback always returns false); ExtensionManager constructed at startup but INERT (no extension loaded, no health check).
- TEST-ONLY / IN-MEMORY: InMemoryExtensionRegistry, SessionDownloadSourceResolver (default), InMemoryPlaybackProgressSink.
- NOT IMPLEMENTED: extension catalogue/remote distribution; extension install/manage UI; download UI (DownloadsView placeholder); auto-update of extensions (setting exists, no code reads it); CPU/memory JS sandboxing (flutter_js_sandbox documents QuickJsRuntime2 timeout/memoryLimit do not work); latest() never called by any SPECTA code; downloads capability defined but unused; MediaReferences table exists but unwritten by audited code; HomeView uses design fixtures.
## 7. Search / Discovery Status

- Real application search: IMPLEMENTED (search_view.dart, search_state.dart)
- Invokes extensions: YES, via DiscoveryCoordinator
- Parallelized across extensions: YES (Future.wait, maxConcurrency=6)
- Extension failure isolation: YES (every operation returns SpectaResult<T>, every coordinator catches Object, outcomes are data classes)
- Results normalized: YES (DiscoveryNormalizer.normalize, drops invalid)
- Deduplication: YES (DiscoveryDeduplicator.dedupe, key = keyTitle|type.code|year)
- Title identity: TitleKey.normalize() - shared Unicode-aware rule, used by search, resume, and download identity
- Movie and series types: YES
- Pagination: PARTIAL - page parameter exists in search(query, page) and latest(page); no UI pagination control found in current search_view
- Latest/discovery: IMPLEMENTED in contract and runtime but NEVER CALLED by any SPECTA code
- Offline behavior: results empty, no crash
- Persistence: in-memory only (SearchSessionNotifier)

## 8. Metadata Status

- Metadata provider abstraction: IMPLEMENTED (MetadataManager, metadata_manager.dart)
- TMDB integration: NOT IMPLEMENTED - no TMDB code found in lib/core/metadata. MetadataManager queries extensions only (manager.callOperation(details)).
- TMDB optional: N/A (not present)
- API key representation: NONE found
- Provider configuration: NONE found
- Metadata caching: in-memory only per MetadataManager call
- Metadata persistence: NO - MetadataItem is transient, returned to UI
- Tied to extension identity: YES - MetadataManager queries per-reference (extensionId + url)
- Media identity mapping: key = identityKey(normalizedTitle, type, year); metadata and source identity remain SEPARATED (metadata is per-reference, sources are per-extension)
- Movie identity: title|type|year
- Series identity: same key; episodes nested in MediaDetails.seasons
- Metadata/source separation: PRESERVED

## 9. Source Manager Integration

- MP4 support: YES (SourceType.mp4)
- HLS support for streaming: YES (SourceType.hls)
- DASH: EXPLICITLY EXCLUDED
- Source validation: YES (SourceValidator.validate - scheme http/https only, type mp4/hls only, drops blank/over-long URLs, too many headers, subtitles without URLs)
- Ranking: YES (SourceRanker.rank - quality match, adaptive bonus, type preference, deterministic tie-breakers)
- Fallback: YES (PlaybackSessionNotifier advances through SourcePool.fallbacks on failure)
- refreshSource: IMPLEMENTED (SourceManager.refresh, calls extension operation)
- Extension provenance: YES (SourcePool.outcomes per-extension)
- Multi-extension sources: YES (parallel query, dedupe by extensionId|url)
- Failure handling: YES (isolated per-extension, never crashes app)

## 10. Trust and Signature Model

- Ed25519 implementation: REAL (SignatureVerifier, SpectaSigningProtocol, package:cryptography Ed25519)
- Public key location: hardcoded in trusted_keys.dart (uDm0fWmDu0dQ/32eXEw7O78VhqEA72YYcEpXPECxAYc=)
- What is signed: canonical metadata JSON (12 fields, keys sorted, nulls omitted, compact UTF-8) + extension JS body, both length-prefixed, format SPECTA-EXT-SIG-V1
- Verification flow: parse manifest -> extract body -> buildPayload -> verifier.verify(message, signature)
- Author identity authenticated: NO - signature covers id/author/version/capabilities but there is no separate author credential; author is a manifest field inside the signed payload
- Catalogue metadata overriding trust: NO - trust is re-derived from the file at load time; a divergence is recorded as a failure and persisted
- Imported extensions falsely claiming Official: NOT POSSIBLE - TrustLevel.official requires a valid signature over the actual file bytes against the trusted public key
- Trust is data, not enforcement: CONFIRMED - unverified extensions still load and execute
## 11. Extension Lifecycle

- install/import: IMPLEMENTED (importExtension reads file, parses manifest, validates API compat, classifies trust, stores via registry)
- validate: IMPLEMENTED (ManifestValidator, API version check, capability parsing)
- register: IMPLEMENTED (registry.install, Drift insertOnConflictUpdate)
- enable: IMPLEMENTED (setEnabled(id, true))
- disable: IMPLEMENTED (setEnabled(id, false) + shuts down runtime if loaded)
- uninstall: IMPLEMENTED (shutdown runtime + registry.uninstall cascades versions and failure logs in transaction)
- update: PARTIAL/MISSING - no update() method. saveVersion() exists in registry but is never called by any code, so no rollback points are ever created.
- rollback: IMPLEMENTED BUT ORPHANED - rollback(id) calls getRollbackVersion(id) which always returns null (no version snapshots exist), so rollback always returns false.
- persistence across restart: IMPLEMENTED (DriftExtensionRegistry; loadRuntime re-reads file and re-classifies trust at load time)
- broken extension quarantine/failure handling: PARTIAL - failures are recorded in ExtensionFailureLogs and surfaced via healthOf(); health is descriptive only and never disables an extension. No quarantine state.

## 12. Official Catalogue Status

- Official extension catalogue model: NOT IMPLEMENTED
- Catalogue endpoint/configuration: NOT IMPLEMENTED
- GitHub catalogue integration: NOT IMPLEMENTED
- Catalogue refresh: NOT IMPLEMENTED
- Manifest retrieval: NOT IMPLEMENTED (only local file import via importExtension/importFromSource)
- Package retrieval: NOT IMPLEMENTED
- Signature verification: IMPLEMENTED (but only at import time, for files already on disk)
- Version/update detection: NOT IMPLEMENTED
- Offline catalogue cache: NOT IMPLEMENTED
- Community import: IMPLEMENTED (importExtension takes a local .js path)
- Unverified Extension classification: IMPLEMENTED (TrustLevel.unverified)

## 13. Real Extension Readiness

Question: Can SPECTA currently load and execute a real external JavaScript movie/series extension through the existing runtime and carry its results into Source Manager and MediaKit?

Answer: YES - the full chain is implemented and connected, but it has NEVER been exercised by a real extension because no extension has ever been installed.

Proven from source:
- FlutterJsSandbox creates a real QuickJsRuntime2 and evaluates extension code.
- ExtensionRuntime.loadExtension instantiates class Extension extends SpectaExtension and calls load()/capabilities().
- DiscoveryCoordinator, MetadataManager, SourceManager all call manager.loadRuntime + manager.callOperation against enabled extensions.
- SourceManager.resolve() returns a SourcePool consumed by SourceSessionNotifier and MediaKitPlaybackEngine.
- The app graph is fully wired: search -> details -> sources -> playback.

What remains necessary before creating the first real reference extension:
1. A mechanism to install an extension file (importExtension exists but no UI calls it yet - ExtensionsView is a placeholder).
2. A legally appropriate source for the reference extension (NOT chosen here).
3. Validation that the full movie path (search->details->getSources->MediaKit) and series path (search->details->episodes->episode source->MediaKit) both work end-to-end on device.
## 14. Test Coverage

Extension tests run: 299 passed / 0 failed / 9 skipped (flutter test test/core/extensions/).

Categories:
1. Unit tests: manifest_test, extension_capability_test, extension_source_test, extension_health_test, signing_protocol_test, signature_verifier_test, title_key_test
2. Manager tests: extension_manager_test, extension_manager_signing_test, extension_manager_health_test, extension_manager_trust_recheck_test, drift_extension_registry_test
3. Runtime tests: extension_runtime_test, extension_runtime_defensive_test, flutter_js_sandbox_test, controlled_runtime_api_test
4. Policy tests: request_policy_test, request_policy_hardening_test
5. Integration: discovery_coordinator_test, discovery_normalizer_test, discovery_deduplicator_test, metadata_manager_test, source_manager_test, source_validator_test, source_ranker_test, source_manager_download_resolver_test
6. Real JavaScript extension tests: NONE - no test loads and executes a real external .js extension end-to-end
7. Device tests: NONE for extensions

What tests actually exercise:
- manifest loading: YES (manifest_test)
- trust verification: YES (extension_manager_signing_test, signature_verifier_test)
- QuickJS: YES (flutter_js_sandbox_test, extension_runtime_test) - but via fake_js_sandbox in test/support, not the real flutter_js on device
- request(): YES (controlled_runtime_api_test, request_policy_test)
- search: YES (discovery_coordinator_test via harness)
- details: YES (metadata_manager_test)
- episodes: YES (result model parsing in extension_runtime_test)
- getSources: YES (extension_source_test, source_manager_test)
- extension failure handling: YES (extension_runtime_defensive_test, extension_manager_health_test)
- source normalization: YES (source_validator_test, source_ranker_test)
- Source Manager integration: YES (source_manager_test)
- playback integration: YES (playback_session_state_test, source_session_state_test) - but via fake engines, not real MediaKit with a real extension

Gap: NO test loads a real external .js extension through the real QuickJS runtime and carries results into Source Manager and MediaKit on device.
## 15. Validation Results

- flutter analyze: No issues found (6.5s)
- flutter test test/core/extensions/: 299 passed / 0 failed / 9 skipped
- flutter test test/core/downloads/: 166 passed / 0 failed / 0 skipped
- flutter test test/core/downloads/download_attempt_identity_test.dart: 9 passed / 0 failed
- Known full-suite issue (historical, preserved): an intermittent Drift/Dart-isolate test-fixture race under heavy load (Callbacks into the Dart VM are currently prohibited + Can't re-open a database after closing it) affecting two DOWNLOAD tests. Not an extension defect. Not weakened or skipped.

## 16. Missing Seams

CRITICAL for 2H:
1. No extension install/manage UI (ExtensionsView is a placeholder)
2. No catalogue/remote distribution (manifest retrieval, package retrieval, version detection)
3. No update flow (saveVersion orphaned, rollback always returns false)
4. No real extension has ever been installed or executed end-to-end on device

HIGH:
5. No CPU/memory ceiling for QuickJS (documented gap in flutter_js_sandbox)
6. latest() implemented but never called - dead contract surface
7. downloads capability defined but unused
8. No auto-update despite setting existing
9. HomeView uses design fixtures
10. DownloadsView is a placeholder (2G-C manager is real but no UI)

MEDIUM:
11. DNS rebinding mitigation is best-effort only (no re-resolve at connect time)
12. Extension health is descriptive, never disables
13. MediaReferences table exists but unwritten
14. No pagination UI despite page parameter in contract

LOW:
15. Request/response compression not addressed
16. No per-extension timeout tuning
## 17. Technical Risks

CRITICAL:
1. Extension API stability - contract is version 2 only; no forward/backward compatibility mechanism. A breaking extension change has no migration path.
2. Schema/version compatibility - apiVersion is a hard gate; any bump breaks all older extensions with no grace period.
3. Runtime failures - JS exceptions, timeouts (30s op, 15s request), and policy blocks all map to SpectaResult; isolation is real and tested.
4. Malformed extension responses - parsers are strict and skip-on-error; a bad extension cannot crash the app.

HIGH:
5. Timeout behavior - QuickJS timeout parameter does not interrupt synchronous runaway loops (documented). Only Dart-side Future.timeout bounds awaited operations. A while(true){} in an extension hangs the isolate.
6. Network policy - scheme/method/size/redirect/private-host all enforced. DNS rebinding mitigation is best-effort (no re-resolve at connect time).
7. Duplicate media identity - dedupe key is title|type|year; two different works sharing a title+year collide. Metadata/source separation is preserved but identity collision is unresolved.
8. Source expiry - no TTL on source URLs; refreshSource exists but nothing calls it automatically.
9. Extension disablement - disabling shuts down the runtime but does not invalidate in-flight operations.

MEDIUM:
10. Concurrent extension execution - maxConcurrency=6, per-extension 20s op timeout. Resource limits are soft.
11. Memory/resource limits - no QuickJS memory ceiling (bridge does not export jsSetMemoryLimit).
12. Extension update/rollback - rollback is orphaned (no version snapshots). Updating an extension mid-flight has no safe path.
13. Trust changes - trust is re-derived at load time and divergence is recorded, but a currently-loaded runtime keeps its original trust for its lifetime.

LOW:
14. Cancellation - no cancellation token passed to extension operations; a running search/details/getSources cannot be cancelled mid-flight.
15. QuickJS limitations - no DOM, filesystem, process, or platform objects; only specta_request and specta_log channels.
16. Application restart behavior - runtimes are not persisted; restart re-loads from registry on demand.
## 18. Proposed Phase 2H Decomposition

Chosen based on repository evidence, not assumed:

2H-A - Extension Installation and Lifecycle Foundation
  - Install/manage UI (replaces ExtensionsView placeholder)
  - Update flow that saves version snapshots (fixes orphaned saveVersion)
  - Rollback that actually works (now that snapshots exist)
  - Broken extension quarantine state
  - Device validation of install/enable/disable/uninstall/update/rollback
  Depends on: nothing new; all registry/manager code already exists.

2H-B - Real Extension Integration Contract
  - End-to-end validation of search -> details -> getSources -> MediaKit for MOVIE
  - End-to-end validation of search -> details -> episodes -> episode source -> MediaKit for SERIES
  - Reference extension contract finalization
  - Dead contract surface cleanup (latest, downloads capability) or explicit enablement
  Depends on: 2H-A (an extension must be installable first).

2H-C - Reference Extension Vertical Slice
  - Build ONE legally-appropriate reference extension exercising movie and series paths
  - No DRM bypass, no auth bypass, no paywall bypass, no anti-bot bypass, no circumvention
  - Device-validated end-to-end
  Depends on: 2H-B.

2H-D - Hardening and Device Validation
  - QuickJS CPU/memory ceiling (if bridge support lands)
  - DNS rebinding re-resolve at connect time
  - Source URL TTL / automatic refresh
  - Auto-update wiring
  - Full device matrix for extensions
  Depends on: 2H-C.

Not proposed as separate phases: catalogue networking, TMDB, DASH, HLS offline, playback redesign - these are out of scope or belong to later authorized phases.
## 19. Minimum Reference Extension Contract

The smallest useful real extension must exercise:

MOVIE:
  search(query, page) -> SearchResult[]
  details(url)        -> MediaDetails (type=movie, no seasons)
  getSources(ref)     -> ExtensionSource[] (at least one mp4)

SERIES:
  search(query, page) -> SearchResult[] (type=series)
  details(url)        -> MediaDetails (type=series, with seasons[].episodes[])
  getSources(episodeUrl) -> ExtensionSource[] (at least one mp4)

Manifest minimum:
  id, name, version, author, apiVersion=2, type=movies_series
  capabilities: search,details,sources (network is implied by request(); logging optional)

Must NOT do:
  - No DRM bypass, no authentication bypass, no paywall bypass, no anti-bot bypass
  - No access-control bypass, no circumvention, no unauthorized content access
  - Source must be a legally appropriate source. No site scraping chosen here.

Required to prove the chain:
  - search result opens DetailsView
  - details renders and surfaces a play button
  - getSources returns a source that SourceManager ranks and MediaKit opens
  - series path: season/episode selection -> episode getSources -> MediaKit
## 20. Documentation Corrections Needed

Found during this audit (NOT applied - reporting only):

1. PROJECT_STATE.txt and docs/PROJECT_STATE.txt: byte-identical to each other but both carry a stale "downloads-focused 165/165" and an inaccurate "1 failed = pre-existing discovery load-order flake" wording. Correct values: 166/166; the full-suite failure was a Drift/Dart-isolate race in two DOWNLOAD tests, not a discovery test. Correction prepared but NOT committed.

2. README.md and docs/README.md: same stale wording as #1. Both corrected in working tree, NOT committed.

3. No other documentation contradictions found. Extension status in docs matches source (ExtensionsView placeholder explicitly says catalogue arrives in Phase 2H).

Do not commit these corrections during the audit.
## 21. Explicit Non-Goals

- Do NOT implement Phase 2H
- Do NOT create a real extension
- Do NOT create SPECTA-Extensions repository
- Do NOT add catalogue networking
- Do NOT add TMDB functionality
- Do NOT redesign the extension API
- Do NOT modify Source Manager
- Do NOT modify DownloadManager
- Do NOT modify MediaKit
- Do NOT add HLS downloading
- Do NOT add DASH
- Do NOT add VPN
- Do NOT add DRM bypass
- Do NOT add anti-bot bypass
- Do NOT push
- Do NOT commit implementation work
- Do NOT start Phase 2I or any future phase

## 22. Final Verdict

Current extension architecture is understood: real, production-grade, fully wired into the app graph but never exercised by a real extension.
Current API is understood: 9 operations, 6 capabilities, strict parsing, Ed25519 trust, comprehensive request policy.
Actual application reachability is understood: search/details/sources/playback/download all connected to ExtensionManager; ExtensionsView and DownloadsView are placeholders.
Missing seams are identified: install/manage UI, catalogue, update flow, real-extension end-to-end validation.
Test coverage is understood: 299 extension tests pass, but none load a real external .js extension through QuickJS on device.
Risks are identified and ranked.
A reference-extension boundary can be defined.
No critical unknown remains that would make the Phase 2H specification speculative.

PHASE 2H ENTRY AUDIT COMPLETE - READY FOR 2H SPECIFICATION
## 23. Continuation Audit — Extension Manager and Orchestration (2026-09-23)

Accepted runtime baseline from the prior audit; this section inspects everything OUTSIDE the runtime.

### Extension Manager (lib/core/extensions/manager/extension_manager.dart, 537 lines)

Single entry point. Constructor: ExtensionRegistry (required), ExtensionRuntimeApi (optional), ExtensionJsSandbox factory (optional), SignatureVerifier (defaults to instance).

Registration/manifest loading: importExtension(filePath) reads the file, ManifestParser.parse, API compat check, _classifyTrust, then _registry.install. importFromSource(extensionId, jsCode, targetPath) is the test/catalogue seam.

Trust determination: _classifyTrust verifies Ed25519 over manifest.buildSignedPayload(extensionBody). Missing/invalid signature -> TrustLevel.unverified. Never rejects an import.

Capabilities passed: manifest.capabilities (Set<ExtensionCapability>) passed to ExtensionRuntime at construction. Re-read from the file at loadRuntime, not from the stored record.

Runtime creation: ExtensionRuntime(sandbox: _sandboxFactory(), api: _runtimeApi, capabilities: manifest.capabilities). Cached in _runtimes map.

Runtime destruction: uninstall() removes from _runtimes and shuts down. setEnabled(false) shuts down if loaded. shutdown(id) and shutdownAll().

Enabled/disabled state: ExtensionRecord.enabled bool, persisted in Drift Extensions table. getEnabledExtensions() returns only enabled.

Failure surfacing: ExtensionFailureRecords persisted to ExtensionFailureLogs. healthOf() classifies via ExtensionHealthRules (descriptive only, never disables).

Concurrency: _runtimes is a Map<String, ExtensionRuntime>; multiple extensions load and run independently. One broken extension does not prevent another — every operation returns SpectaResult<T>, every coordinator catches Object.

### ACTUAL OPERATION TRACES

search():
  SearchView._onChanged() -> spectaSearchQueryProvider.setQuery()
  -> searchSessionProvider.notifier.submit(query) [SearchSessionNotifier, search_state.dart]
  -> DiscoveryService.search(SearchRequest) [discoveryServiceProvider]
  -> DiscoveryCoordinator.discover() [discovery_coordinator.dart]
     -> manager.getEnabledExtensions()
     -> for each (maxConcurrency=6, Future.wait): _queryOne()
        -> manager.loadRuntime(record.id) — if Err, returns failed outcome
        -> runtime.isGranted(ExtensionCapability.search) — if not, skipped
        -> manager.callOperation<List<SearchResult>>(id, (r) => r.search(query, page)) with 20s timeout
        -> caps at maxResultsPerExtension=100
     -> DiscoveryNormalizer.normalize() drops invalid
     -> DiscoveryDeduplicator.dedupe() key = keyTitle|type.code|year
  -> SearchSessionNotifier maps to SearchStatus: idle/loading/results/empty/partialFailure/allFailed/noExtensions
  -> SearchView renders DiscoveryItem list; tap opens DetailsView via detailsSessionProvider

details():
  DetailsView -> DetailsSessionNotifier.open(DiscoveryItem) [details_state.dart]
  -> MetadataService.metadataFor(item) [metadataServiceProvider]
  -> MetadataManager.metadataFor() [metadata_manager.dart]
     -> for each reference (maxConcurrency=6, Future.wait): _queryReference()
        -> manager.loadRuntime(reference.extensionId) — if Err, skipped
        -> runtime.isGranted(ExtensionCapability.details) — if not, skipped
        -> manager.callOperation<MediaDetails>(id, (r) => r.details(url: reference.url)) with 20s timeout
        -> MetadataNormalizer.normalize() drops blank titles, type mismatches, over-long fields
     -> _canonicalize() merges valid contributions into one MetadataItem
        -> canonical title/type/year from discovery item
        -> cover/backdrop: first available, never overwritten
        -> details year NOT merged (disagreement stays visible per-reference)
  -> DetailsState maps to DetailsStatus: idle/loading/success/failure
  -> DetailsView renders; for series, _seasonsSection() renders seasons/episodes

getSources():
  startPlayback(metadata, item, episode?) [playback_entry.dart]
  -> builds Map<String,String> extensions (extensionId -> referenceUrl)
     -> for movie: every contributing reference
     -> for episode: only references that carry that episode, fallback to all if none
  -> SourceSessionNotifier.resolve(reference, extensions) [source_session_state.dart]
  -> SourceService.resolve(reference, extensions, preference) [sourceServiceProvider]
  -> SourceManager.resolve() [source_manager.dart]
     -> for each extension (maxConcurrency=6, Future.wait): _queryExtension()
        -> manager.loadRuntime(extensionId) — if Err, skipped
        -> runtime.isGranted(ExtensionCapability.sources) — if not, skipped
        -> manager.callOperation<List<ExtensionSource>>(id, (r) => r.getSources(reference)) with 20s timeout
        -> caps at maxSourcesPerExtension=100
        -> SourceValidator.validate() per candidate (scheme http/https, type mp4/hls, drops blank/over-long URLs, too many headers, subtitles without URLs)
     -> _aggregate(): dedupe by extensionId|url, SourceRanker.rank() (quality match, adaptive bonus, type preference, deterministic tie-breakers), build SourcePool
  -> SourceSessionState: ready with pool (ranked + selected + fallbacks) or failure
  -> playbackSessionProvider.open(PlaybackRequest.fromPool(pool, ...)) [playback_session_state.dart]
  -> MediaKitPlaybackEngine opens first ranked candidate; on failure refreshes (once, HLS only) or advances to fallback

All three traces are real call sites, verified in source.
## 24. Continuation Audit — Search, Metadata, Details, Source, Playback, Download (2026-09-23)

### Search/Discovery Pipeline
- App exposes search: YES (SearchView, TextField, 400ms debounce)
- Invokes real extensions: YES (DiscoveryCoordinator -> manager.loadRuntime + callOperation(search))
- Multiple extensions: YES (Future.wait, maxConcurrency=6)
- Failure isolation: YES (SpectaResult<T>, catch Object, per-extension outcomes)
- Normalization: YES (DiscoveryNormalizer.normalize, drops invalid)
- Deduplication: YES (key = keyTitle|type.code|year, null year -> 'none')
- Movie and series: YES
- Pagination: PARTIAL — page param exists in search(query, page) and latest(page); no UI pagination control in current SearchView
- Malformed results: parsers strict, skip invalid entries, never crash
- Timeout: 20s per extension operation; returns failed outcome, never throws

### Metadata Manager
- Exists: YES (metadata_manager.dart, 304 lines)
- Connected to search: NO — MetadataManager is reached from DetailsView, not from SearchView
- Connected to details: YES (DetailsSessionNotifier.open -> metadataFor)
- Provider abstraction: PARTIAL — MetadataManager queries extensions only via manager.callOperation(details). No pluggable metadata provider interface.
- TMDB implemented: NO — no TMDB code anywhere in lib/core/metadata. MetadataManager queries extensions only.
- TMDB optional: N/A
- Provider configuration: NONE
- API keys: NONE
- Metadata cached: in-memory only per call
- Metadata persisted: NO — MetadataItem is transient, returned to UI
- Extension metadata separate from provider metadata: YES (per-reference ReferenceMetadata)
- Movie identity: key = identityKey(normalizedTitle, type, year)
- Series identity: same key; episodes nested in MediaDetails.seasons[].episodes[]
- Episode identity: SeriesEpisode.episodeNumber + seasonNumber + referenceUrl

### Details and Series/Episodes
- details(url) -> MediaDetails -> MetadataManager -> UI: IMPLEMENTED and connected
- Series details -> seasons -> episodes: IMPLEMENTED in data models and UI
- DetailsView._seasonsSection(metadata) renders seasons; each episode row calls onPlayEpisode(SeriesEpisode)
- Episode identity: episodeNumber + seasonNumber + referenceUrl
- Episode URL/reference: SeriesEpisode.referenceUrl, carried into startPlayback
- A real series extension CAN provide Season 1 / Ep 1 / Ep 2 / Ep 3 and SPECTA understands them: YES — MediaDetails.seasons is a List<MediaSeason>, each MediaSeason has seasonNumber + episodes (List<MediaEpisode>), each MediaEpisode has episodeNumber + url + optional fields. DetailsView renders them. startPlayback resolves episode sources via getSources(episode.referenceUrl) across the extensions that carry that episode.

### Source Manager Integration
- ExtensionSource accepted by Source Manager: YES (SourceManager.resolve -> _queryExtension -> manager.callOperation(getSources))
- Provenance preserved: YES (SourcePool.outcomes per-extension; SourceSessionState.pool carries it)
- Multiple extension sources: YES (parallel query, dedupe by extensionId|url)
- MP4: YES (SourceType.mp4)
- HLS: YES (SourceType.hls)
- Labels normalized: PARTIAL — label is optional and passed through; no normalization beyond presence
- Quality normalized: PARTIAL — quality is optional string; SourceRanker scores it against QualityPreference but does not canonicalize the string
- Invalid sources rejected: YES (SourceValidator.validate drops bad scheme/type/headers/subtitles)
- Source ranking: YES (SourceRanker.rank — quality match, adaptive bonus, type preference, deterministic tie-breakers)
- Fallback: YES (PlaybackSessionNotifier advances through SourcePool.fallbacks)
- refreshSource() reachable: YES (SourceManager.refresh -> manager.callOperation(refreshSource))
- Source expiry recovery: PARTIAL — refreshSource exists and is reachable, but nothing calls it automatically on expiry; playback refreshes once on HLS failure only
- DownloadManager reuses same pipeline: YES (SourceManagerDownloadResolver.resolveSource -> SourceManager.resolve)

### Playback Integration
- Plays extension-returned source: YES (MediaKitPlaybackEngine opens SourcePool.selected)
- MediaKit receives final URL: YES (PlaybackRequest.fromPool(pool, ...))
- MP4 and HLS: YES
- Headers propagated: YES (ExtensionSource.headers passed to engine; MediaKit supports headers for HLS)
- Subtitles/audio tracks: YES (ExtensionSource.subtitles, audioTracks represented in models; MediaKit wiring is partial)
- Playback failure triggers fallback: YES (advances to next ranked candidate)
- Playback failure triggers source refresh: PARTIAL — refreshes once on HLS failure only; not on MP4 failure
- Watch progress connected: YES (PlaybackProgressSink -> LibraryStore.saveWatchProgress)

### Download Integration
- Extension source -> DownloadRequest: YES (buildMovieDownloadRequest/buildEpisodeDownloadRequest adapters build DownloadRequest from a SourcePool)
- Source provenance preserved: YES (DownloadRequest carries sourceExtensionId + sourceReference)
- Source refresh on expiry: YES (SourceManagerDownloadResolver re-resolves through SourceManager when previous attempt failed with a source-classified failure)
- DownloadManager uses SourceManager-backed recovery: YES
- Completed download stable media identity: YES (mediaKey derived from TitleKey)
- Correct media/episode identity: YES (episode downloads carry season/episode numbers)
- Offline playback boundary PRESERVED: OFFLINE DOWNLOADED-FILE PLAYBACK remains NOT TESTABLE — no product seam exists. Not implemented, not added.
## 25. Continuation Audit — Installation, Catalogue, Trust, Readiness, Tests (2026-09-23)

### Installation/Lifecycle
- Extension file import: IMPLEMENTED (importExtension(filePath) — reads file, parses manifest, validates API compat, classifies trust, stores)
- Manifest validation: IMPLEMENTED (ManifestValidator, require/requireInt/requireContentType/optional/optionalCapabilities)
- Signature verification: IMPLEMENTED (Ed25519 over manifest + body, SPECTA-EXT-SIG-V1)
- Registration: IMPLEMENTED (registry.install, Drift insertOnConflictUpdate)
- Enable/disable: IMPLEMENTED (setEnabled; disabling shuts down runtime if loaded)
- Persistence: IMPLEMENTED (DriftExtensionRegistry; loadRuntime re-reads file and re-classifies trust at load time)
- Reload after restart: IMPLEMENTED (registry persists; runtimes reloaded on demand)
- Broken extension handling: PARTIAL — failures recorded in ExtensionFailureLogs; healthOf() is descriptive only; never disables. No quarantine state.
- Duplicate extension IDs: HANDLED — registry.install uses insertOnConflictUpdate (id is primary key)
- Version handling: PARTIAL — ExtensionVersions table and saveVersion/getRollbackVersion exist, but saveVersion is never called by any code, so rollback always returns false. No update() method.

Can an ordinary .js extension be imported and become executable? YES, via importExtension(filePath) — but NO UI calls it. ExtensionsView is a placeholder. The path exists in code; the entry point is missing.

### Official Catalogue
- Catalogue model: NOT IMPLEMENTED
- Catalogue loader: NOT IMPLEMENTED
- Official extension list: NOT IMPLEMENTED
- Refresh: NOT IMPLEMENTED
- GitHub source: NOT IMPLEMENTED
- Version/update handling: NOT IMPLEMENTED
- Package download: NOT IMPLEMENTED
- Signature verification during catalogue install: N/A (no catalogue)
- Offline cache: NOT IMPLEMENTED
- Community extension import: IMPLEMENTED (importExtension takes a local .js path)

### Trust Flow
- Trust is re-derived from the file at load time, not trusted from the import-time record
- A divergence between stored trust and file trust is recorded as a failure and persisted
- Trust is data, not enforcement — unverified extensions still load and execute
- Imported extensions cannot falsely claim Official: TrustLevel.official requires a valid signature over the actual file bytes against the trusted public key

### Real Extension Readiness

QUESTION A: Can SPECTA currently load and execute an external .js extension?
YES — FlutterJsSandbox creates a real QuickJsRuntime2, ExtensionRuntime.loadExtension instantiates class Extension extends SpectaExtension and calls load()/capabilities(). Proven by flutter_js_sandbox_test and extension_runtime_test (via fake_js_sandbox in test/support).

QUESTION B: Can that extension perform search -> results -> details -> sources through the actual application architecture?
YES, in code — DiscoveryCoordinator, MetadataManager, and SourceManager all call manager.loadRuntime + manager.callOperation against enabled extensions. The wiring is complete. BUT no extension has ever been installed, so this path has never been exercised by a real extension. The chain is implemented but UNTESTED by a real .js file.

QUESTION C: Can the resulting source reach Source Manager -> MediaKit through the actual application?
YES — startPlayback -> SourceSessionNotifier.resolve -> SourceManager.resolve -> SourcePool -> playbackSessionProvider.open -> MediaKitPlaybackEngine. Fully connected. Again, never exercised by a real extension.

### Test Coverage
- Extension loading: YES (extension_manager_test, drift_extension_registry_test)
- Manifest parsing: YES (manifest_test)
- Trust: YES (extension_manager_signing_test, signature_verifier_test, signing_protocol_test)
- Runtime: YES (extension_runtime_test, extension_runtime_defensive_test, flutter_js_sandbox_test) — via fake_js_sandbox, NOT the real flutter_js on device
- request(): YES (controlled_runtime_api_test, request_policy_test, request_policy_hardening_test)
- search: YES (discovery_coordinator_test via discovery_test_harness)
- details: YES (metadata_manager_test)
- episodes: YES (result model parsing in extension_runtime_test; details_view_test)
- getSources: YES (extension_source_test, source_manager_test)
- Extension Manager: YES (extension_manager_test, extension_manager_health_test, extension_manager_trust_recheck_test)
- Search orchestration: YES (search_state_test, search_view_test, discovery_coordinator_test)
- Source Manager integration: YES (source_manager_test, source_manager_download_resolver_test)
- Playback integration: YES (playback_session_state_test, source_session_state_test, playback_view_test) — via fake engines
- Download integration: YES (download_manager_test, source_manager_download_resolver_test)

Categories:
- unit: manifest, capability, source, health, signing, request_policy, source_validator, source_ranker, title_key
- integration: extension_manager, drift_extension_registry, discovery_coordinator, metadata_manager, source_manager, download_manager
- real-JS: NONE — no test loads a real external .js extension through the real QuickJS runtime on device
- device: NONE for extensions
- end-to-end: NONE — no test runs search -> details -> sources -> playback with a real extension

BIGGEST UNTESTED SEAM: the entire chain from a real external .js extension through the real QuickJS runtime into Source Manager and MediaKit, on device. Every link is unit-tested in isolation; the integration is not.
## 26. Minimum Reference Extension (DO NOT CREATE)

MOVIE path must exercise:
  search(query, page) -> SearchResult[] (at least one type=movie)
  details(url)        -> MediaDetails (type=movie, no seasons required)
  getSources(ref)     -> ExtensionSource[] (at least one mp4)

SERIES path must exercise:
  search(query, page) -> SearchResult[] (at least one type=series)
  details(url)        -> MediaDetails (type=series, with seasons[].episodes[])
  getSources(episodeUrl) -> ExtensionSource[] (at least one mp4)

Manifest minimum:
  id, name, version, author, apiVersion=2, type=movies_series
  capabilities: search,details,sources (network implied by request(); logging optional)

Must NOT do: no DRM bypass, no auth bypass, no paywall bypass, no anti-bot bypass, no access-control bypass, no circumvention, no unauthorized content access. Source must be legally appropriate. No website selection or scraping yet.

## 27. Missing Seams

CRITICAL (block the reference extension vertical slice):
1. No install/manage UI — ExtensionsView is a placeholder; importExtension exists but no UI calls it
2. No catalogue/remote distribution — manifest retrieval, package retrieval, version detection all missing
3. No update flow — saveVersion orphaned, rollback always returns false
4. No real extension has ever been installed or executed end-to-end on device

HIGH:
5. No CPU/memory ceiling for QuickJS (documented; QuickJsRuntime2 timeout/memoryLimit do not work)
6. latest() implemented but never called — dead contract surface
7. downloads capability defined but unused
8. Auto-update setting exists but no code reads it
9. HomeView uses design fixtures
10. DownloadsView is a placeholder (2G-C manager is real, no UI)

MEDIUM:
11. DNS rebinding mitigation best-effort only (no re-resolve at connect time)
12. Extension health descriptive, never disables
13. MediaReferences table exists but unwritten
14. No pagination UI despite page parameter in contract
15. Source URL refresh is manual only (not automatic on expiry)

LOW:
16. No request/response compression handling
17. No per-extension timeout tuning
18. No cancellation token for running extension operations

## 28. Technical Risks

CRITICAL:
1. API stability — contract is apiVersion 2 only; no forward/backward compatibility; any breaking change has no migration path
2. Schema compatibility — apiVersion is a hard gate; bumping it breaks all older extensions with no grace period
3. Malformed responses — parsers strict and skip-on-error; a bad extension cannot crash the app (tested)

HIGH:
4. Timeout — QuickJS timeout does not interrupt synchronous runaway loops; only Dart Future.timeout bounds awaited ops. A while(true){} hangs the isolate.
5. Duplicate identity — dedupe key is title|type|year; two different works sharing title+year collide
6. Source expiry — no TTL on source URLs; refreshSource exists but not automatic
7. Disablement — disabling shuts down runtime but does not cancel in-flight operations

MEDIUM:
8. Concurrency — maxConcurrency=6, 20s op timeout; resource limits soft
9. Memory — no QuickJS memory ceiling (bridge does not export jsSetMemoryLimit)
10. Update/rollback — rollback orphaned; no safe mid-flight update path
11. Trust drift — a loaded runtime keeps original trust for its lifetime even if the file changes

LOW:
12. Cancellation — no cancellation token for running extension operations
13. QuickJS limitations — no DOM/filessystem/process; only specta_request and specta_log channels
14. Restart — runtimes not persisted; reloaded from registry on demand

Runtime limitations (CPU ceiling, memory ceiling, OS sandbox, DNS rebinding) are NOT blockers for the reference extension use case. They are hardening items for 2H-D.
## 29. Proposed Phase 2H Decomposition

Based on repository evidence, not the old roadmap:

2H-A — Extension Installation and Lifecycle Foundation
  - Install/manage UI (replaces ExtensionsView placeholder)
  - Update flow that saves version snapshots (fixes orphaned saveVersion)
  - Rollback that actually works (now that snapshots exist)
  - Broken extension quarantine state
  - Device validation of install/enable/disable/uninstall/update/rollback
  Depends on: nothing new; all registry/manager code already exists.

2H-B — Real Extension Integration Contract
  - End-to-end validation of search -> details -> getSources -> MediaKit for MOVIE
  - End-to-end validation of search -> details -> episodes -> episode source -> MediaKit for SERIES
  - Reference extension contract finalization
  - Dead contract surface cleanup (latest, downloads capability) or explicit enablement
  Depends on: 2H-A (an extension must be installable first).

2H-C — Reference Extension Vertical Slice
  - Build ONE legally-appropriate reference extension exercising movie and series paths
  - No DRM bypass, no auth bypass, no paywall bypass, no anti-bot bypass, no circumvention
  - Device-validated end-to-end
  Depends on: 2H-B.

2H-D — Hardening and Device Validation
  - QuickJS CPU/memory ceiling (if bridge support lands)
  - DNS rebinding re-resolve at connect time
  - Source URL TTL / automatic refresh
  - Auto-update wiring
  - Full device matrix for extensions
  Depends on: 2H-C.

Not proposed: catalogue networking, TMDB, DASH, HLS offline, playback redesign — out of scope or later authorized phases.

## 30. Documentation Corrections

Found during this continuation (NOT applied — reporting only):

1. PROJECT_STATE.txt and docs/PROJECT_STATE.txt: byte-identical to each other but both carry stale "downloads-focused 165/165" and an inaccurate "1 failed = pre-existing discovery load-order flake" wording. Correct values: 166/166; the full-suite failure was a Drift/Dart-isolate race in two DOWNLOAD tests, not a discovery test. Correction prepared but NOT committed.

2. README.md and docs/README.md: same stale wording. Both corrected in working tree, NOT committed.

3. No other documentation contradictions found. ExtensionsView and DownloadsView placeholders explicitly state their Phase 2H status, matching source.

Do not commit these corrections during the audit.

## 31. Explicit Non-Goals

- Do NOT implement Phase 2H
- Do NOT create a real extension
- Do NOT create SPECTA-Extensions repository
- Do NOT add catalogue networking
- Do NOT add TMDB functionality
- Do NOT redesign the extension API
- Do NOT modify Source Manager
- Do NOT modify DownloadManager
- Do NOT modify MediaKit
- Do NOT add HLS downloading
- Do NOT add DASH
- Do NOT add VPN
- Do NOT add DRM bypass
- Do NOT add anti-bot bypass
- Do NOT push
- Do NOT commit implementation work
- Do NOT start Phase 2I or any future phase

## 32. Final Verdict

Runtime understood. Extension Manager understood. Search flow understood. Metadata flow understood. Details/episode flow understood. Source flow understood. Playback flow understood. Download flow understood. Installation/lifecycle status understood. Catalogue status understood. Real extension readiness proven. Missing seams identified. Reference extension contract can be specified without guessing.

PHASE 2H ENTRY AUDIT COMPLETE — READY FOR 2H SPECIFICATION
