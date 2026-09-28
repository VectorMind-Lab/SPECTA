/// App-private storage for downloaded extensions.
///
/// A downloaded extension is written into app-private storage and then handed
/// to `ExtensionManager.importExtension(filePath:)` — the SAME entry point the
/// device picker uses. That is what makes all three installation paths
/// converge on one pipeline instead of two.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
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

/// Deletes one source file, if and only if it is inside app-private storage.
///
/// ## Why this exists
///
/// A registry row records an absolute `filePath`. Deleting the row without
/// deleting that file leaves an orphan `.js` in app-private storage forever:
/// nothing refers to it again, and nothing ever cleans it up.
///
/// ## The guard is the point
///
/// `filePath` is persisted data, and persisted data can be wrong, edited or
/// poisoned. A delete driven by it is therefore allowed to touch exactly one
/// directory: SPECTA's own app-private source directory. A path outside it —
/// `/sdcard/...`, a user's own file, anything at all — is reported as
/// "not removed" and left completely alone. Refusing to delete is always the
/// safe answer to an unrecognised path.
abstract interface class SourceFileRemover {
  /// Attempts to delete [path].
  ///
  /// Returns true only when a file was actually removed. A null or empty path,
  /// a path outside SPECTA's source directory, and a file that is already gone
  /// all return false — none of them are errors. An already-absent file is the
  /// desired end state, so treating it as failure would be wrong.
  Future<bool> remove(String? path);
}

/// The production [SourceFileRemover], rooted at app-private storage.
///
/// The directory is resolved lazily per call rather than cached, so a test (or
/// a platform channel that is not ready yet) cannot poison it with a stale
/// value, and so the guard is always evaluated against the directory SPECTA
/// would actually write to right now.
final class AppPrivateSourceFileRemover implements SourceFileRemover {
  const AppPrivateSourceFileRemover({
    this.storage = const AppPrivateExtensionStorage(),
  });

  final ExtensionStorage storage;

  @override
  Future<bool> remove(String? path) async {
    if (path == null || path.trim().isEmpty) return false;
    final Directory? root = (await storage.resolveDirectory()).valueOrNull;
    // An unresolvable root means no claim can be proven, so nothing is deleted.
    if (root == null) return false;
    if (!SourceFileContainment.isInside(root.path, path)) return false;

    final File file = File(path);
    try {
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } on Object {
      // A file we cannot delete is still a file we must not fail the delete
      // over: the row is gone either way, and the caller is told truthfully
      // that the bytes remain.
      return false;
    }
    return false;
  }
}

/// Pure path containment, separated so it can be tested without any I/O.
abstract final class SourceFileContainment {
  /// Whether [candidate] names something strictly inside [root].
  ///
  /// Both sides are made absolute and normalised first, so `..` segments and
  /// redundant separators cannot be used to step outside. The root itself is
  /// NOT "inside" it: deleting a directory wholesale is never a source delete.
  static bool isInside(String root, String candidate) {
    if (root.isEmpty || candidate.isEmpty) return false;
    final String normalizedRoot = p.normalize(p.absolute(root));
    final String normalizedCandidate = p.normalize(p.absolute(candidate));
    if (normalizedCandidate == normalizedRoot) return false;
    return p.isWithin(normalizedRoot, normalizedCandidate);
  }
}

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
