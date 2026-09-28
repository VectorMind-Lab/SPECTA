# Phase C1 environment and status

Date: 2026-09-25

## Verified toolchain

The Flutter SDK is installed outside `PATH` and is verified at:

```text
H:\\flutter\\bin\\flutter.bat
```

Verified versions:

```text
Flutter 3.47.4 • channel stable
Dart 3.13.3
```

Direct Dart executable:

```text
H:\\flutter\\bin\\cache\\dart-sdk\\bin\\dart.exe
```

The SDK is usable for this project. The earlier C1 toolchain blocker is resolved.
A second Flutter directory exists at `H:\\Projects\\App sdk and tools\\flutter`, but
it is not the toolchain used by this phase.

## C1 state

C1 is in progress. No AniList networking, Home/Search/Details wiring, or C2 work
is part of this phase. Generated Drift code must be regenerated from the table
definitions with build_runner; it is never hand-edited.

The worktree contains pre-existing uncommitted changes. They must be preserved.
No reset, stash, clean, commit, or push is authorized for this phase.
