/// The health vocabulary the extension foundation reports.
///
/// This is a *description*, not a controller. [ExtensionHealthRules.evaluate]
/// classifies an extension from facts SPECTA already holds (enabled flag, API
/// compatibility, recent failure count) and changes nothing. In particular,
/// reaching [temporarilyUnavailable] does **not** disable an extension: the
/// earlier design note that suggested "disable after three failures" is
/// deliberately not implemented, because per-extension failure counts conflate
/// "this extension is broken" with "the site it scrapes is having a bad day",
/// and silently disabling a working source is worse than retrying it.
///
/// A later phase that owns source ranking can consume these states; until then
/// they exist so that health is an explicit, testable value rather than an
/// implicit reading of scattered flags.
enum ExtensionHealth {
  /// Enabled, API-compatible and no recent failures.
  healthy('healthy'),

  /// Enabled and usable, but has failed recently.
  degraded('degraded'),

  /// Enabled, but failing often enough that a caller should prefer another
  /// source. Still reported as enabled and still loadable — never auto-disabled.
  temporarilyUnavailable('temporarily_unavailable'),

  /// Switched off by the user.
  disabled('disabled'),

  /// Declares an extension API version this build cannot run.
  incompatible('incompatible');

  const ExtensionHealth(this.code);

  /// Stable identifier used in diagnostics and persistence.
  final String code;

  /// Whether SPECTA would attempt to execute this extension right now.
  bool get isRunnable =>
      this == ExtensionHealth.healthy ||
      this == ExtensionHealth.degraded ||
      this == ExtensionHealth.temporarilyUnavailable;

  static ExtensionHealth? fromCode(String code) {
    for (final ExtensionHealth health in ExtensionHealth.values) {
      if (health.code == code) return health;
    }
    return null;
  }
}

/// The facts behind a health classification, kept together so a caller can see
/// *why* an extension was classified the way it was.
final class ExtensionHealthState {
  const ExtensionHealthState({
    required this.health,
    required this.recentFailureCount,
    required this.apiVersion,
  });

  final ExtensionHealth health;

  /// Failures recorded inside the health window (24 hours by default).
  final int recentFailureCount;

  /// The API version the extension declares.
  final int apiVersion;

  @override
  String toString() =>
      'ExtensionHealthState(${health.code}, recentFailures: '
      '$recentFailureCount, apiVersion: $apiVersion)';
}

/// Pure classification rules for [ExtensionHealth].
///
/// Kept separate from the manager so the policy is testable without a
/// database, and so the thresholds are stated in exactly one place.
abstract final class ExtensionHealthRules {
  /// Failures after which an enabled extension is reported as [degraded].
  static const int degradedAtFailures = 1;

  /// Failures after which an enabled extension is reported as
  /// [temporarilyUnavailable].
  static const int unavailableAtFailures = 3;

  /// The window failure counts are measured over.
  static const Duration failureWindow = Duration(hours: 24);

  /// Classifies an extension. Pure: it reads its arguments and nothing else.
  ///
  /// Precedence is [ExtensionHealth.incompatible] first, then
  /// [ExtensionHealth.disabled], then the failure count. Incompatibility wins
  /// over the user's flag because it is the stronger statement: an extension
  /// this build cannot run is not merely switched off.
  static ExtensionHealth evaluate({
    required bool enabled,
    required bool apiCompatible,
    required int recentFailureCount,
  }) {
    if (!apiCompatible) return ExtensionHealth.incompatible;
    if (!enabled) return ExtensionHealth.disabled;
    if (recentFailureCount >= unavailableAtFailures) {
      return ExtensionHealth.temporarilyUnavailable;
    }
    if (recentFailureCount >= degradedAtFailures) {
      return ExtensionHealth.degraded;
    }
    return ExtensionHealth.healthy;
  }
}
