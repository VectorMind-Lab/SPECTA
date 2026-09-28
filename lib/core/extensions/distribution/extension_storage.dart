/// App-private storage for downloaded extensions.
///
/// A downloaded extension is written into app-private storage and then handed
/// to `ExtensionManager.importExtension(filePath:)` — the SAME entry point the
/// device picker uses. That is what makes all three installation paths
/// converge on one pipeline instead of two.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';

/// Resolves the directory SPECTA writes downloaded extensions into.
///
/// Abstracted so tests and any headless environment can supply a temporary
/// directory without a platform channel.
abstract interface class ExtensionStorage {
  /// Returns the directory to write into, creating it when necessary.
  Future<SpectaResult<Directory>> resolveDirectory();
}

/// Production storage: `<app support>/extensions`.
///
/// App-private, never external/shared storage, and never surfaced to the user
/// as a browsable location — a downloaded extension is not a user-managed file.
final class AppPrivateExtensionStorage implements ExtensionStorage {
  const AppPrivateExtensionStorage();

  static const String folderName = 'extensions';

  @override
  Future<SpectaResult<Directory>> resolveDirectory() async {
    try {
      final Directory support = await getApplicationSupportDirectory();
      final Directory dir = Directory(
        '${support.path}${Platform.pathSeparator}$folderName',
      );
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return Ok<Directory>(dir);
    } on Object catch (e) {
      return Err<Directory>(
        ExtensionDistributionFailure(
          type: ExtensionDistributionFailureType.storageFailure,
          stage: 'store',
          detail: 'Could not resolve app-private storage: ${e.runtimeType}',
        ),
      );
    }
  }
}

/// Builds a storage failure. Not const: the message is derived from the type.
ExtensionDistributionFailure _storageFailure(String detail) =>
    ExtensionDistributionFailure(
      type: ExtensionDistributionFailureType.storageFailure,
      stage: 'store',
      detail: detail,
    );

/// Writes extension source into a directory under a stable, filesystem-safe
/// name derived from the extension id.
abstract final class ExtensionFileStore {
  /// Writes [sourceCode] and returns the absolute path.
  ///
  /// The name is derived from the extension id, so re-installing the same
  /// extension replaces its previous copy instead of accumulating copies. The
  /// id is sanitised because it is attacker-influenced (it comes from a
  /// downloaded manifest) and must never be able to escape the directory.
  static Future<SpectaResult<String>> write(
    Directory directory,
    String extensionId,
    String sourceCode,
  ) async {
    final String? safeName = sanitizeFileStem(extensionId);
    if (safeName == null) {
      return Err<String>(
        _storageFailure('Extension id is not usable as a file name.'),
      );
    }
    final File file = File(
      '${directory.path}${Platform.pathSeparator}$safeName.js',
    );
    try {
      await file.writeAsString(sourceCode, flush: true);
      return Ok<String>(file.path);
    } on Object catch (e) {
      return Err<String>(
        _storageFailure('Could not write extension file: ${e.runtimeType}'),
      );
    }
  }

  /// Reduces an extension id to a safe file stem, or null when nothing usable
  /// remains.
  ///
  /// Only `[A-Za-z0-9._-]` survives, so `..`, `/`, backslash and absolute
  /// paths are all neutralised. Length is bounded.
  static String? sanitizeFileStem(String extensionId) {
    final StringBuffer buffer = StringBuffer();
    for (final int unit in extensionId.codeUnits) {
      if (unit > 0x7f) continue; // drop non-ASCII
      final String ch = String.fromCharCode(unit);
      final bool safe =
          (ch.compareTo('A') >= 0 && ch.compareTo('Z') <= 0) ||
          (ch.compareTo('a') >= 0 && ch.compareTo('z') <= 0) ||
          (ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0) ||
          ch == '.' ||
          ch == '_' ||
          ch == '-';
      if (safe) buffer.write(ch);
      if (buffer.length >= 64) break;
    }
    String stem = buffer.toString();
    // A stem made only of dots would be `.`, `..` or hidden; never keep those.
    while (stem.startsWith('.')) {
      stem = stem.substring(1);
    }
    if (stem.isEmpty) return null;
    return stem;
  }
}
