/// Operations defined by the SPECTA extension contract.
///
/// Each operation corresponds to a JavaScript function an extension may
/// implement.  The runtime calls these via the JS sandbox and converts
/// results/errors into [SpectaResult] / [ExtensionFailure].
///
/// Not every extension must implement every optional operation; capabilities
/// are declared explicitly through [ExtensionCapabilities].
enum ExtensionOperation {
  /// Called once when the extension is first loaded into the runtime.
  load,

  /// Returns the extension's declared capabilities.
  capabilities,

  /// Search for media: `search(query, page)`.
  search,

  /// Latest additions: `latest(page)`.
  latest,

  /// Full details for a media item: `details(url)`.
  details,

  /// Resolve playback sources: `getSources(reference)`.
  getSources,

  /// Refresh a stale source URL: `refreshSource(reference)`.
  refreshSource,

  /// Lightweight liveness check: `healthCheck()`.
  healthCheck,

  /// Called when the extension is about to be unloaded.
  shutdown;

  /// Whether this operation is required for every extension.
  ///
  /// Only [load] and [capabilities] are mandatory in Phase 1.
  bool get isRequired =>
      this == ExtensionOperation.load ||
      this == ExtensionOperation.capabilities;
}
