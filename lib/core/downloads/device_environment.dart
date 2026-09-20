import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'download_models.dart';

/// Platform answers SPECTA needs for honest download policy:
///
/// * which network the device is on (a Wi-Fi-only policy cannot be enforced
///   honestly without it), and
/// * how many bytes are free on the volume SPECTA stores media on.
///
/// Both answers come from ONE small platform channel implemented in the host
/// `MainActivity` — no third-party dependency is added for either.
///
/// Limitation reported honestly: the probes return `null` (unknown) rather
/// than guessing. The network policy treats `unknown` conservatively; the
/// storage check skips the size comparison when the free amount is unknown.
abstract interface class DeviceEnvironment {
  /// The current network access kind, or null when the platform could not
  /// answer.
  Future<NetworkAccess?> networkAccess();

  /// Bytes free on the volume holding [path], or null when unknown.
  Future<int?> freeBytes(String path);
}

/// Real implementation over the `net.specta.app/environment` channel.
final class PlatformDeviceEnvironment implements DeviceEnvironment {
  PlatformDeviceEnvironment();

  final MethodChannel _channel = const MethodChannel(
    'net.specta.app/environment',
  );

  @override
  Future<NetworkAccess?> networkAccess() async {
    try {
      final String? code = await _channel.invokeMethod<String>('networkAccess');
      return code == null ? null : NetworkAccess.fromCode(code);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<int?> freeBytes(String path) async {
    try {
      final int? bytes = await _channel.invokeMethod<int>(
        'freeBytes',
        <String, String>{'path': path},
      );
      return (bytes == null || bytes < 0) ? null : bytes;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

/// The device environment binding. Tests override this provider.
final Provider<DeviceEnvironment> deviceEnvironmentProvider =
    Provider<DeviceEnvironment>((Ref ref) => PlatformDeviceEnvironment());
