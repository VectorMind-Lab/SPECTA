# Phase E report — Reference-informed UI/UX enhancement pass

Date: 2026-09-26
Status: **VERIFIED for the three approved items (E1, E2, E3).** Every other
candidate was evaluated against the source and deliberately NOT implemented;
the reason is recorded per item below. No redesign, no new navigation, no
new dependency, no fake setting.

## Method

Each candidate was traced to its SPECTA equivalent before anything was
implemented, and given one of: fits as-is / fits with adaptation / needs
dependency / does not fit. Only items with real backing logic were approved.

## Implemented

### E1 — Settings value display — fits with adaptation
Source: `lib/features/settings/settings_view.dart`.
The Downloads card rendered the concurrency number with no indication of what
it means. It now shows `(default)` when the value equals the real
`DownloadConcurrencyNotifier.defaultConcurrency`, and nothing when it does not.
The auto-update switch now states its current state in words.

### E2 — Settings explanations — fits with adaptation
The auto-update switch is the one control in Settings that changes what SPECTA
does unattended, and it carried no explanation. It gained one plain line:
"On — SPECTA checks for newer versions of your extensions. You choose what to
install." / "Off — extensions stay on the version you installed."
It reports only real state and promises nothing about a specific version.

### E3 — Default labels — fits as-is (terminology already existed)
`settings_view.dart` already labelled the brand theme chip `'${preset.label}
(default)'`. The Downloads card now reuses the identical `(default)` wording
instead of inventing a second term, so the screen has one convention.

## Evaluated and NOT implemented

| Item | Verdict | Reason |
| --- | --- | --- |
| E4 — Wrong-title re-match | **does not fit** | `TmdbProviderMatcher.match` exists and scores title/type/year, but nothing in the app calls it per-item, there is no stored "wrong match" to correct, and the provider enrichment (C3) is automatic. A correction button would need a real override model (user-supplied identity, persistence, re-resolution). Not built. |
| E5 — Add to list / watch status | **does not fit** | `watch_progress` has no status column at all (only `completed` 0/1). "Plan to Watch / Watching / Completed / Paused / Dropped" would require a new column, a migration, and a new model — a persistence feature, not a UI pass. |
| E6 — Genre grid | **does not fit (yet)** | Genres exist in metadata, but there is no genre query, no genre index, and no navigation slot for a browse screen. `SpectaAppShell` has fixed destinations. Building a new screen + nav entry is a navigation change, out of scope for E. |
| E7 — Extension list | **already present** | `extensions_view.dart` already shows name, version, trust level (`${record.trustLevel.code}`), enable/disable, update state and update action (added in Phase D). No gap to fill. |
| E8 — Source/provider display | **needs dependency** | `SourcePool.selected` / `RankedSource.extensionId` already carry provenance, and `SourceSessionState.preference` exists — so the data is available. But the playback view does not currently surface it, and adding a manual override dropdown is **not** supported by the architecture. Reported as a gap, not faked. |
| E9 — Player enhancements | **already present / nothing to wire** | The player already has a speed menu wired to real playback rates and a subtitle selector over real candidate tracks. No unsupported setting was added. |
| E10 — Skip intro/recap/ending | **does not fit** | There is no marker source, no timestamp table, and no detection logic anywhere in the player. Skip controls would be fake buttons. Depends on real marker data or chapter/skip-time detection. |
| E11 — External tracking | **does not fit** | No AniList/MAL/Simkl OAuth or write API integration exists. Adding toggles would be fake settings. |
| E12 — Subtitles | **already present** | `SubtitleTrack`, `availableSubtitles`, `selectedSubtitle` and an Off entry are already implemented in the player. No `.ass` assumption was made and no OpenSubtitles key field was added. |
| E13 — Shaders (Anime4K) | **not approved** | Renderer architecture does not expose a shader pass, and the item is explicitly unapproved. Not implemented. |
| E14 — Encrypted DNS | **does not fit** | SPECTA's networking is per-request HTTPS with its own policy; there is no DNS/DoH routing layer to select. A picker would be UI-only. |
| E15 — Download UI | **preserved, nothing changed** | DownloadManager → DownloadEngine ownership and the authoritative SPECTA DB were left untouched. No torrent UI. |
| E16 — Excluded items | **not implemented** | No torrent, no books/novels/manga, no redesign, no new theme, no new navigation. |

## Files changed

- `lib/features/settings/settings_view.dart` — Downloads default label; auto-update
  value line and explanation.
- `test/features/settings/settings_view_test.dart` — 3 new widget tests.
- `docs/phase_reports/E_report.md` — this report.

## Verification

```text
flutter analyze            -> No issues found!
test/features/settings     -> 12 passed, 0 failed
flutter test (full)        -> 1089 passed, 39 skipped, 0 failed
```

## Security

No credential handled, requested, or displayed. No sandbox change. No new
dependency. No fake setting or unreachable control was added.
