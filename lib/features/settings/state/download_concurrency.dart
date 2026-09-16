import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_providers.dart';
import '../../../core/database/settings_store.dart';
import '../../../core/settings/specta_setting_keys.dart';

/// How many downloads may run at the same time.
///
/// Agreed behaviour: the default is 3 concurrent downloads, configurable up to
/// 9. This is the settings foundation only — the download manager that honours
/// the value is implemented in a later phase.
class DownloadConcurrencyNotifier extends Notifier<int> {
  static const int defaultConcurrency = 3;
  static const int minConcurrency = 1;
  static const int maxConcurrency = 9;

  @override
  int build() {
    unawaited(_restore());
    return defaultConcurrency;
  }

  /// Applies the persisted value once the store answers.
  Future<void> _restore() async {
    final SettingsStore store = ref.read(settingsStoreProvider);
    final String? stored = await store.read(
      SpectaSettingKeys.downloadConcurrency,
    );
    final int? parsed = int.tryParse(stored ?? '');
    if (parsed != null && isValidConcurrency(parsed) && parsed != state) {
      state = parsed;
    }
  }

  /// Validates, applies and persists a new value.
  Future<void> set(int value) async {
    if (!isValidConcurrency(value)) {
      throw ArgumentError.value(
        value,
        'value',
        'Download concurrency must be between '
            '$minConcurrency and $maxConcurrency.',
      );
    }
    state = value;
    await ref
        .read(settingsStoreProvider)
        .write(SpectaSettingKeys.downloadConcurrency, '$value');
  }

  static bool isValidConcurrency(int value) =>
      value >= minConcurrency && value <= maxConcurrency;
}

/// Current download concurrency setting.
final NotifierProvider<DownloadConcurrencyNotifier, int>
downloadConcurrencyProvider =
    NotifierProvider<DownloadConcurrencyNotifier, int>(
      DownloadConcurrencyNotifier.new,
    );
