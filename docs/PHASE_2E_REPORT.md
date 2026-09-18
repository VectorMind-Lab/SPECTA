# SPECTA — Phase 2E Report: Player Integration

**Date:** 2026-09-19
**Sub-stage:** Phase 2E — PLAYER INTEGRATION ONLY
**Predecessor state:** Phase 1 COMPLETE (device verified); 2A (`4249ad9`), 2B
(`baceadb`), 2C (`bcc47e1`), 2D (`a380ca8`) COMPLETE.
**Recovery context:** the previous session implemented most of this sub-stage
and then ended without documenting, committing or device-verifying it. This
session performed a read-only recovery audit first (state **C**: implementation
present, verification green, documentation/commit missing), then fixed defects,
verified on a real device, and documented. Nothing was deleted or restarted.

Nothing from Phase 2F–2H was started. No database schema change. No new
dependency. No `SPECTA-Extensions` repository. No second source model.

---

## 1. SCOPE

Implemented: the playback layer of the approved pipeline —

```
Metadata/episode reference (2C/2D provenance)
        ↓
SourceManager → SourcePool (selected + ranked fallbacks)
        ↓
PlaybackSession (ordered attempt → failure → fallback → refresh-once → retry)
        ↓
PlaybackEngine seam  →  MediaKitPlaybackEngine  →  MediaKit (mpv)
        ↓
PlaybackSnapshot (honest status)  →  SPECTA player surface (phone + TV)
        ↓
PlaybackProgressSink (in-memory 2E seam for 2F)
```

NOT implemented (hard boundaries honored): persistent watch progress and the
library/history schema (2F), downloads (2G), the extension catalogue and
`SPECTA-Extensions` (2H), real scraper extensions, TMDB or any external
metadata provider, DASH, DRM/access-control/anti-bot/authentication bypass.

## 2. FILES CHANGED

Created (this sub-stage):

- `lib/core/playback/playback_engine.dart` — transport-agnostic engine
  contract + sealed `PlaybackEngineEvent` set. The only seam between the
  session and MediaKit, so the session is testable without native code.
- `lib/core/playback/media_kit_engine.dart` — the MediaKit implementation.
- `lib/core/playback/playback_progress_sink.dart` — `PlaybackProgressSink`
  plus the in-memory 2E implementation (deliberately no persistence).
- `lib/features/playback/playback_models.dart` — `PlaybackStatus`,
  `PlaybackCandidate`, `PlaybackAttempt`, `PlaybackAttemptRecord`,
  `PlaybackSnapshot` (+ `copyWith`). Re-exports the Phase 1 `SubtitleTrack`.
- `lib/features/playback/playback_session_state.dart` — `PlaybackRequest`,
  `PlaybackSessionNotifier` + providers (engine factory, open/stall timeouts,
  progress sink).
- `lib/features/playback/playback_view.dart` — player surface, controls,
  focus handling.
- `lib/features/playback/playback_entry.dart` — details → source resolution →
  player coordinator.
- `test/features/playback/playback_session_state_test.dart` (34 tests).
- `integration_test/phase2e_device_verification_test.dart` (5 device tests).
- `docs/evidence_p2e_device_run_2026-09-19.log` — raw device run output.

Modified:

- `lib/core/errors/specta_failure.dart` — added `PlaybackFailureType` and
  `PlaybackFailure` (structured playback failure as data).
- `lib/features/details/details_view.dart` — Play button (movie), per-episode
  play targets, `startPlayback` wiring.
- `lib/main.dart` — guarded `MediaKit.ensureInitialized()` at startup.
- `README.md` + `docs/README.md` — corrected stale Phase-1 claims (see §10).

`lib/features/playback/source_session_state.dart` (and its test) are **2D**
work, committed in `a380ca8`; 2E consumes them unchanged.

## 3. SOURCE PIPELINE (how playback consumes Phase 2D)

The player never resolves, ranks or validates anything itself.

1. `startPlayback` (details) asks the existing 2D seam
   (`SourceSessionNotifier.resolve`) for a pool. Reference selection is
   provenance-driven: an episode resolves only across the extensions that
   actually reported that episode, falling back to every contributing
   reference; a movie resolves across all contributing references.
2. `PlaybackRequest.fromPool(pool)` takes `pool.ranked` **in 2D's order** —
   `selected` first, then `fallbacks`. The player never re-sorts, and no
   second ranking algorithm exists.
3. Each attempt keeps its provenance (`extensionId` + `reference`) inside
   `PlaybackCandidate`/`RankedSource` and in every recorded failure.
4. Quality preference stays 2D's decision: to change it, the pool is resolved
   again through the source manager — the player has no quality logic.

## 4. PLAYER STATE

`PlaybackStatus`: `idle`, `loading`, `playing`, `paused`, `buffering`,
`switchingSource`, `completed`, `failed`. Honest transitions only:

- `playing` requires **measured media flow** — a progress tick with
  `position > 0`. MediaKit reports `playing=true` *optimistically* at open
  (observed on device: it does so even for a URL that cannot connect), so that
  signal alone can never be promoted to a playable state.
- The open timer (45 s) fails a candidate that never becomes playable; the
  stall timer (30 s) fails a candidate that stalls mid-playback.
- A mid-stream `EngineErrored` is treated as a **recoverable stall**
  (`buffering`), not an immediate death: MediaKit surfaces non-fatal transport
  errors that playback recovers from. Recovery resumes; a real interruption
  times out and falls through.
- Every state write is generation-guarded: a stale open, a stale fallback or a
  post-disposal write is rejected (same discipline as 2B/2C/2D).

## 5. FALLBACK

```
selected
  ↓ fail → record ordered PlaybackAttempt (provenance preserved)
refreshSource(reference) — at most ONCE per session, HLS candidates only
  ↓ refreshed  → re-attempt the SAME candidate with the validated source
  ↓ null/error → next candidate
next candidate (2D's order) … → success
  ↓ all exhausted
failed (SOURCES_EXHAUSTED) — never "no sources available" while candidates remain
```

Evidence (real device, `docs/evidence_p2e_device_run_2026-09-19.log`):

```
STATE: loading      attempt:0/3 failures:[]
ENGINE: EngineErrored (Failed to open http://127.0.0.1:1/dead.mp4.)
STATE: switchingSource attempt:2/3 failures:[SOURCE_OPEN_FAILURE]
STATE: playing      attempt:2/3 failures:[SOURCE_OPEN_FAILURE]
fallback OK — playing extLive after 1 failure(s); attempted 2/3
```

## 6. REFRESH

Reuses the Phase 1/2D `refreshSource(reference)` contract through
`sourceServiceProvider.refresh` — no `refreshUrl`, no second refresh API. It is
attempted at most once per session, only for candidates whose type can plausibly
go stale (HLS playlists; MP4 URLs are static files), and only after a failure.
A refreshed source is used only if the manager returns a validated
`ExtensionSource`; `null`/an escaping error falls through to the next candidate.
Refresh never plays an unvalidated URL.

## 7. ENGINE SEAM & DEFECTS FIXED

The session talks to `PlaybackEngine` (open/pause/play/seek/setRate/setVolume/
setSubtitle/stop/dispose + an event stream), never to MediaKit directly. That
seam is what makes the whole state machine testable without native code.

Defects found and fixed:

1. **Episode identity dropped on the terminal failure snapshot.** `_snapshot`
   assigned `_subtitleLine = subtitleLine` unconditionally, so the exhausted
   path (which supplies no line) wiped `Season 1 · Episode 2`. Now preserved;
   covered by a test.
2. **`MediaKitPlaybackEngine` violated its own documented contract**: after
   `dispose()`, methods were not inert and `dispose()` was not idempotent,
   which produced a real on-device assertion —
   `Assertion failed: "[Player] has been disposed"` raised from
   `MediaKitPlaybackEngine.stop` during provider teardown. Every method is now
   a no-op after disposal and `dispose()` is idempotent.
3. **A stray late engine failure could restart playback after `completed`.**
   `_onCandidateFailed` had no terminal guard, so a late event could open a
   fallback behind the user's back. Guarded; covered by a test.
4. **Retry lost the session identity.** The terminal screen's "Try again"
   re-opened a bare candidate list, dropping the progress key, title and
   episode line (and disabling progress reporting). `retry()` now replays the
   original order with the same identity; covered by a test.
5. **`startPlayback` could throw `StateError`** on `item.references.first` when
   a discovery item carried no references — an exception escaping into the UI,
   which Phase 2E's own error model forbids. Now an honest refusal.
6. **`_PlayMovieButton` re-read metadata with a null assertion** (`metadata!`)
   instead of using the metadata the content block had already validated.
7. **Dead code removed**: `PlaybackObservation` was declared but never
   referenced (the session records `PlaybackAttemptRecord` instead).
8. **Hardening (defensible, not device-forced):** candidate transitions now
   settle the previous load with its events suppressed (`_suppressing`) and
   every `open` settles the previous load first. The session asks for the next
   candidate the instant a failure surfaces, so the old load can still be
   mid-teardown and its late `error`/`buffering` events could otherwise be
   attributed to the candidate being opened. No device failure was traced to
   their absence; they are documented as hardening, not as a measured fix.

Cleanup: `PlaybackSnapshot.copyWith` (with an `unset` sentinel so an explicit
`null` clears a field) replaced ~50 lines of hand-copied snapshot fields —
which is how defect 1 and a stale-progress-key path existed at all.

## 8. PLAYER UI (phone + TV, existing design language)

One surface, no separate TV architecture. Uses the existing theme, colours,
typography and focus widgets (`SpectaColors`, `SpectaMetrics`).

- Phone: entering playback pins landscape + immersive; leaving restores
  portrait/edge-to-edge. Controls are touch-first and auto-hide after 4 s.
- TV: D-pad focusable controls with a visible focus ring at 10-ft distance;
  the primary action is auto-focused so the remote always has an anchor; the
  auto-hide timer is disabled.
- Controls: back, title/episode line, play/pause, seek bar with position and
  duration, subtitle selector over the candidate's own track list (off by
  default), playback speed (0.5×–2×), buffering indicator, "Trying source N
  of M" during fallback, and an honest Retry on a terminal state.
- Failures render as structured messages; raw engine text is never shown.
- `Video` uses `NoVideoControls` — SPECTA owns the controls.

## 9. WATCH PROGRESS / DOWNLOAD / CATALOGUE BOUNDARIES

- **2F boundary:** `PlaybackProgressSink` is the only seam. 2E binds the
  in-memory implementation; nothing is persisted, no Drift table or schema
  migration was added. `PlaybackAttemptRecord` observations are descriptive
  measurements (including real measured `timeToPlayable`) — never a ranking
  algorithm and never a permanent disable.
- **2G boundary:** no download queue, worker, storage manager or download
  table exists.
- **2H boundary:** no catalogue, no `repository.json`, no runtime GitHub
  access, no extension marketplace.
- **Security:** the extension sandbox, capability gate and request policy are
  untouched. Playback URLs originate only from the approved source pipeline.

## 10. DOCUMENTATION CORRECTION

`README.md` (and its byte-identical copy `docs/README.md`) still carried
pre-Phase-1-closure claims that the Phase 1 closure had already superseded:
"Extension runtime code is not shipped (unreachable from `main.dart`)",
"`FlutterJsSandbox` is untested", "The signing protocol is provisional",
"No capability enforcement, no request policy, no concrete
`ExtensionRuntimeApi`", and a "Not implemented yet" list that claimed the
metadata manager, source resolution/ranking and search UI did not exist. All of
these are false as of Phase 1 closure and 2B/2C/2D. They were corrected in
place; the historical phase reports were **not** rewritten. Both README copies
are byte-identical again.

No separate `DOCUMENTATION_CORRECTION_REPORT.md` was created: the correction is
concise and belongs in the README itself.

## 11. TESTS

```
flutter analyze   → No issues found
flutter test      → 446 passed, 9 skipped (real-engine group: no JS bridge
                    on PATH), 0 failed
```

Focused Phase 2E coverage (34 tests) — player state transitions (honest `playing`,
no premature playable state), selected-source open, MP4 handling, HLS handling
(headers forwarded), source failure isolation, fallback to the second source,
fallback exhaustion, exhaustion preserving the session identity line, `retry()`
replaying 2D's order, engine failure after a newer open being ignored, provider
disposal (engine stopped, late events swallowed), a stray failure after
completion not restarting playback, subtitle select/clear, controls
(pause/resume, rate/volume), mid-stream stall recovery vs. real interruption,
empty-candidate honest failure, progress-sink recording/bounding, and the 2D
source session's race guard.

No existing test was modified to make a new one pass.

## 12. DEVICE VERIFICATION — PASS (5/5)

```
Device        Samsung SM-A065F (Galaxy A06), arm64-v8a
OS            Android 16 (API 36), One UI
Connection    USB (adb device id R83L20FRDFM)
Harness       flutter test integration_test/phase2e_device_verification_test.dart -d R83L20FRDFM
Result        5 passed, 0 failed, 0 skipped — run 2026-09-19
Raw evidence  docs/evidence_p2e_device_run_2026-09-19.log
```

| # | Test | Result |
| --- | --- | --- |
| P2E-1 | MediaKit native library loads; engine constructs and disposes | PASS |
| P2E-2 | Real MP4 playback reaches a playable state (measured 322 ms to first frame) | PASS |
| P2E-3 | Real HLS playback reaches a playable state; `setRate(1.25)` applied | PASS |
| P2E-4 | Ordered fallback on the real engine: dead candidate fails, session lands on the live source | PASS |
| P2E-5 | Progress sink receives a report during real playback | PASS |

This runs the **real** MediaKit engine inside the real app process (no fakes)
over the device's own network stack, so it is not equivalent to the widget
tests: it is the only evidence that the engine seam, fallback and controls work
against actual mpv.

### 12.1 An honest record of the first three device runs

The first three runs failed **P2E-4**, and the cause is worth recording
precisely rather than hiding:

- Candidate 1 (a deliberately dead URL) failed as designed and the session
  advanced — the fallback *logic* was correct in every run.
- Candidate 2 stalled: mpv reported `playing`/`buffering` and then delivered no
  media at all, so the session's honest "playable" rule refused to call it
  playing and failed it at the 45 s open limit
  (`failures:[SOURCE_OPEN_FAILURE, BUFFERING_FAILURE]`).
- The stalled candidate was the **same third-party MP4 (and host) that P2E-2
  had just streamed moments earlier**. A native-player recreation was tried and
  did **not** help, which ruled out a wedged player; the session and engine
  bridging were also ruled out by the event trace. The test was at fault, not
  the player.
- Fix: the fallback candidate now uses an **independent origin** (W3C's public
  MP4), and a third candidate (HLS on another host) proves that an unusable
  fallback still advances instead of becoming "no sources available". This is
  also a more correct test design — a fallback candidate should be a genuinely
  different source. P2E-4 has passed since.
- The speculative player-recreation change was **reverted**: the evidence did
  not support it, and it is not shipped.

The investigation was not wasted: it is what surfaced defect 2 in §7 (the
post-dispose contract violation), which was reproduced on device as a real
teardown assertion.

**Known test-media limitation:** a stream host that *stalls* rather than
*errors* is failed by the open timeout and the session falls through to the
next candidate. The dead-candidate path is a localhost port-1 URL and is
dependency-free; the live candidates depend on public third-party test streams.

## 13. BUILD — PASS

```
flutter build apk --debug  → EXIT 0 (Gradle task 'assembleDebug' 149.7 s)
                           → build/app/outputs/flutter-apk/app-debug.apk
                             277,459,792 bytes, 2026-09-19 02:01
```

Run after every Phase 2E change. (`flutter analyze` PASS and a Dart test PASS
are different verification levels from an Android build PASS; all three were
run, and the device suite additionally installed and ran this app on hardware.)
An earlier APK had already been produced by the interrupted session
(Gradle 1109.8 s); it predates this session's changes and is superseded.

## 14. KNOWN LIMITATIONS

- No `MediaKitPlaybackEngine` unit test: the real engine needs native code, so
  it is covered by device tests instead of the Dart suite (stated plainly
  rather than faked).
- Device verification for 2B/2C/2D remains unit/widget-level only (unchanged
  from those reports).
- Embedded (in-container) audio/subtitle track selection is not surfaced yet;
  external subtitle tracks supplied by the source are. `EngineTracksChanged`
  and `EngineSubtitleChanged` are deliberately no-ops in the session.
- Quality selection is 2D's ranking decision; the player does not second-guess
  it, and no guarantee is made that every device decodes 4K smoothly.
- A stall that never times out cannot be detected; the open/stall timeouts are
  the mechanism (45 s / 30 s, provider-overridable).
- Watch progress is in-memory for this process lifetime only (2F owns
  persistence).

## 15. PHASE BOUNDARY

Stopped at Phase 2E. 2F (persistence/library), 2G (downloads) and 2H
(catalogue / `SPECTA-Extensions`) were NOT started. No database schema change,
no new dependency, no second source model, no duplicate extension contract, no
repository created, no repository visibility change.
