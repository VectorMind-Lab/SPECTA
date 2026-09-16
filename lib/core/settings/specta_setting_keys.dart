/// Canonical persisted setting keys.
///
/// These strings are written into the settings table on users' devices, so
/// renaming one is a data migration, never a refactor.
abstract final class SpectaSettingKeys {
  /// Timestamp of the most recent successful application start.
  static const String lastOpenedAt = 'app.lastOpenedAt';

  /// Number of downloads allowed to run at the same time.
  static const String downloadConcurrency = 'downloads.concurrency';

  /// Selected UI theme preset name (cyanTeal, emeraldGreen, etc.).
  static const String themePreset = 'ui.themePreset';

  /// TMDB personal API key for metadata resolution. Stored locally.
  static const String tmdbApiKey = 'api.tmdbApiKey';

  /// Extension repository catalogue URL for remote discovery.
  static const String extensionRepoUrl = 'extensions.repositoryUrl';

  /// Whether extensions and sources should auto-update.
  static const String autoUpdateExtensions = 'extensions.autoUpdate';

  /// Whether the user has seen the launch introduction.
  static const String hasSeenSplash = 'app.hasSeenSplash';
}
