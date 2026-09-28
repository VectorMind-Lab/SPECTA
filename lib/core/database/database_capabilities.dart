import 'package:flutter/widgets.dart';

/// Whether this process can be trusted to use SPECTA's local database, which the
/// catalogue providers (TMDB, TVMaze, AniList) read and write through.
///
/// Catalogue providers read through the shared `metadata_cache`, which is backed
/// by the local Drift database. That database resolves its storage path through
/// `path_provider` - a platform channel - and it does so ASYNCHRONOUSLY on the
/// first query, inside a future the caller does not await directly.
///
/// Consequences, which this function exists to make explicit:
///
/// - In the running app a binding exists, so the probe passes and the catalogue
///   works normally.
/// - In a headless `ProviderContainer` unit test there is NO binding, so the
///   first cache query fails and the failure surfaces as an UNHANDLED zone error
///   that no `try`/`catch` around the call can suppress.
///
/// So callers check this BEFORE issuing a catalogue request and skip the
/// catalogue step cleanly, rather than letting it poison a round that the
/// extensions have already answered successfully.
///
/// Scope, stated plainly: this verifies that Flutter platform services exist. It
/// does NOT probe the storage plugin, because that channel is unregistered in
/// widget tests and awaiting it there hangs the surface. A test that wants the
/// real catalogue path overrides the provider instead of relying on a probe.
bool catalogueDatabaseUsable() {
  try {
    // Accessing the instance asserts when no binding has been installed, which
    // is exactly the condition being detected, and it throws synchronously so it
    // is safe to catch here.
    WidgetsBinding.instance;
    return true;
  } on Object {
    return false;
  }
}
