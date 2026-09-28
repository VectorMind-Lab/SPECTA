import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:specta/core/settings/specta_setting_keys.dart';
import 'package:specta/core/tmdb/tmdb_config.dart';
import 'package:specta/core/tmdb/tmdb_providers.dart';

const String _key = 'abcdef0123456789abcdef0123456789';

void main() {
  group('TmdbConfig', () {
    test('blank credentials are absent and keys are masked', () {
      expect(const TmdbConfig().isConfigured, isFalse);
      expect(const TmdbConfig(apiKey: '  ').isConfigured, isFalse);
      expect(const TmdbConfig(apiKey: _key).normalizedKey, _key);
      expect(const TmdbConfig(apiKey: _key).maskedKey, '••••••••6789');
      expect(const TmdbConfig(apiKey: _key).maskedKey, isNot(contains(_key)));
    });

    test('accepts supported v3 and v4 credential shapes only', () {
      expect(TmdbConfig.looksLikeApiKey(' $_key '), isTrue);
      expect(
        TmdbConfig.looksLikeApiKey(
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signature',
        ),
        isTrue,
      );
      expect(TmdbConfig.looksLikeApiKey('too-short'), isFalse);
      expect(TmdbConfig.looksLikeApiKey('${_key.substring(1)}g'), isFalse);
      expect(TmdbConfig.looksLikeApiKey('${_key}0'), isFalse);
      expect(TmdbConfig.looksLikeApiKey('eyJtoo-short'), isFalse);
    });

    test('copy and string conversion never expose the key', () {
      final TmdbConfig config = const TmdbConfig(apiKey: _key);
      expect(config.copyWith(clearApiKey: true).apiKey, isNull);
      expect(config.toString(), isNot(contains(_key)));
    });
  });

  group('tmdbConfigProvider — build-time credential only', () {
    test('resolves directly from the compiled-in define, with no notifier', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      // The provider is a plain `Provider`: it has no `.notifier`, so there is
      // no code path in the app that can write a key at runtime. The only
      // source is `appTmdbApiKey`, frozen by `--dart-define` at build time.
      final TmdbConfig config = container.read(tmdbConfigProvider);
      expect(config.isConfigured, appTmdbApiKey.trim().isNotEmpty);
      if (appTmdbApiKey.trim().isNotEmpty) {
        expect(config.normalizedKey, appTmdbApiKey.trim());
      }

      // Same value on every read — the config is immutable by construction.
      expect(
        container.read(tmdbConfigProvider).normalizedKey,
        config.normalizedKey,
      );
    });

    test('the user-facing settings table has no TMDB credential key', () {
      // Guards the removal at the source-of-truth level: the persisted key
      // constant no longer exists, so no code path — present or future — can
      // write a credential into the device settings table.
      const Map<String, Object?> persisted = <String, Object?>{
        SpectaSettingKeys.lastOpenedAt: '',
        SpectaSettingKeys.downloadConcurrency: '',
        SpectaSettingKeys.themePreset: '',
        SpectaSettingKeys.extensionRepoUrl: '',
        SpectaSettingKeys.autoUpdateExtensions: '',
        SpectaSettingKeys.hasSeenSplash: '',
      };

      expect(
        persisted.keys.where(
          (String key) => key.toLowerCase().contains('tmdb'),
        ),
        isEmpty,
      );
    });
  });
}
