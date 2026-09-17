import '../../../core/database/settings_store.dart';
import '../../../core/settings/specta_setting_keys.dart';

/// Splash launch-flow state helpers.
///
/// The approved launch flow shows the SPECTA branding splash on every launch
/// (Splash → Main App). The persisted flag records that the flow completed so
/// a future preference (for example, a shorter repeat-launch splash) can build
/// on real state instead of inventing its own.
abstract final class SplashState {
  /// Delay before the splash auto-transitions to the main app shell.
  static const Duration autoTransitionDelay = Duration(milliseconds: 2800);

  /// Records that the launch flow completed.
  static Future<void> markSplashSeen(SettingsStore store) {
    return store.write(SpectaSettingKeys.hasSeenSplash, 'true');
  }

  /// Whether the launch flow has completed before.
  static Future<bool> hasSeenSplash(SettingsStore store) async {
    return await store.read(SpectaSettingKeys.hasSeenSplash) == 'true';
  }
}
