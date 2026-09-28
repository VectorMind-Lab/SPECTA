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

/// What the Source Health screen shows for one node.
///
/// ## The percentage is a DISPLAY MAPPING, not a computed score
///
/// SPECTA has no basis for a real "reliability score": it does not know how
/// many times a source was asked, only how many attempts failed. A percentage
/// derived from that would be arithmetic theatre — it would read as a
/// measurement while being an invention.
///
/// So the number is a small, fixed vocabulary mapped from facts that really
/// exist, and it is only ever shown next to the words that explain it. The
/// mapping is deliberately coarse: 100% does not claim perfection, it claims
/// "working, with nothing recorded against it".
///
/// | Real state                              | Display     |
/// |-----------------------------------------|-------------|
/// | never completed anything                | No data yet |
/// | healthy, 0 recent failures              | 100%        |
/// | degraded, 1-2 recent failures           | 50%         |
/// | unavailable, 3+ recent failures         | 10%         |
/// | disabled                                | 0%          |
/// | incompatible                            | 0%          |
///
/// This type is DISPLAY ONLY. It never feeds ranking, never reorders the
/// source list, and never disables anything: `source_ranker.dart` and
/// `source_manager.dart` are untouched by design, because priority must never
/// override quality ranking.
enum SourceHealthDisplay {
  /// No successful activity has ever been recorded, so there is nothing to
  /// report. Shown as words, never as a number — a percentage here would be a
  /// fabricated measurement.
  noDataYet('No data yet'),

  /// Working, with nothing recorded against it in the window.
  working('100%'),

  /// Usable, but has failed recently.
  degraded('50%'),

  /// Failing often enough that another source should be preferred.
  unavailable('10%'),

  /// Switched off by the user. The user's own decision, not a fault.
  off('0%'),

  /// This build cannot run it, whatever the user would prefer.
  unsupported('0%');

  const SourceHealthDisplay(this.label);

  /// The exact string shown to the user. Never a bare number without a state.
  final String label;
}

/// Pure mapping from recorded facts to what the health screen displays.
///
/// Separated from the widget so the mapping can be tested exhaustively with no
/// Flutter binding, and so the rules are stated in exactly one place.
abstract final class SourceHealthMapping {
  /// Maps a node's real state to its display.
  ///
  /// [hasRecordedActivity] is the fact that separates "never tried" from
  /// "working": it is true only after a real success has been recorded. It is
  /// NOT derived from the failure count, because zero failures reads the same
  /// for a source nobody has run and a source that works perfectly.
  ///
  /// A disabled node reads as OFF regardless of how healthy it would otherwise
  /// look. The user switched it off, and reporting its health facts as though
  /// it were serving traffic would misdescribe what SPECTA is doing.
  static SourceHealthDisplay of({
    required ExtensionHealth health,
    required bool hasRecordedActivity,
  }) {
    switch (health) {
      case ExtensionHealth.incompatible:
        return SourceHealthDisplay.unsupported;
      case ExtensionHealth.disabled:
        return SourceHealthDisplay.off;
      case ExtensionHealth.healthy:
        return hasRecordedActivity
            ? SourceHealthDisplay.working
            : SourceHealthDisplay.noDataYet;
      case ExtensionHealth.degraded:
        return SourceHealthDisplay.degraded;
      case ExtensionHealth.temporarilyUnavailable:
        return SourceHealthDisplay.unavailable;
    }
  }

  /// The plain-language state, used as the heading above the percentage.
  static String describe(ExtensionHealth health) => switch (health) {
        ExtensionHealth.healthy => 'Ready',
        ExtensionHealth.degraded => 'Working with problems',
        ExtensionHealth.temporarilyUnavailable => 'Having trouble',
        ExtensionHealth.disabled => 'Off',
        ExtensionHealth.incompatible => 'Not supported by this version',
      };
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
