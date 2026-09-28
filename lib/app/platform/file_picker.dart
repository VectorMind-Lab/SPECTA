import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// MIME types SPECTA offers when browsing for a file to import.
///
/// The list is advisory: platform document pickers report `.js` files
/// inconsistently (`application/javascript`, `text/plain`,
/// `application/octet-stream`, depending on the file manager), so all common
/// spellings are included. The import path validates the *content* — the
/// manifest parser decides whether a file is a valid extension, never the
/// MIME type.
const List<String> defaultMimeTypes = <String>[
  'application/javascript',
  'text/javascript',
  'application/x-javascript',
  'text/plain',
  'application/octet-stream',
];

/// Upper bound for one picked file, enforced natively (the copy stops) AND
/// re-checked here so a lying or buggy platform reply can never make Dart
/// read an unbounded file.
const int maxPickedFileBytes = 10 * 1024 * 1024;

final RegExp _sha256Pattern = RegExp(r'^[0-9a-fA-F]{64}$');

/// Outcome of one pick request. Sealed so the UI must handle every case
/// instead of guessing what happened.
sealed class FilePickResult {
  const FilePickResult();
}

/// The document was copied into app-private storage and the copy passed
/// byte-for-byte verification.
final class FilePicked extends FilePickResult {
  const FilePicked(this.file);

  final PickedFile file;
}

/// The user closed the picker without choosing anything. Not an error.
final class FilePickCancelled extends FilePickResult {
  const FilePickCancelled();
}

/// The platform has no file picker (desktop, tests, a channel nobody
/// implements). The caller should fall back to manual path entry rather than
/// pretend a file was chosen.
final class FilePickUnsupported extends FilePickResult {
  const FilePickUnsupported();
}

/// The pick failed, or — importantly — the copied file did not match what the
/// platform claimed. A rejected copy is deleted so it can never be imported
/// later from a stale path.
final class FilePickFailed extends FilePickResult {
  const FilePickFailed(this.message);

  /// User-facing, credential-free summary.
  final String message;
}

/// One picked document: an app-private copy whose bytes were verified.
final class PickedFile {
  const PickedFile({
    required this.path,
    required this.displayName,
    required this.sizeBytes,
    required this.sha256,
  });

  /// Absolute path of the verified copy inside app-private storage.
  final String path;

  /// Original display name from the document provider (never a path).
  final String displayName;

  /// Byte length of the verified copy.
  final int sizeBytes;

  /// Lowercase hex SHA-256 of the verified copy.
  final String sha256;
}

/// Platform document picker seam.
///
/// Tests override [filePickerProvider]; production uses [PlatformFilePicker].
abstract interface class FilePicker {
  /// Asks the platform to let the user pick one document.
  ///
  /// Never throws: every outcome — success, cancel, missing platform support
  /// or a failed verification — is a [FilePickResult].
  Future<FilePickResult> pick({List<String> mimeTypes = defaultMimeTypes});
}

/// Real implementation over the `net.specta.app/file_picker` channel.
///
/// Contract with the native side (SAF on Android):
///
/// * native launches `ACTION_OPEN_DOCUMENT` and streams the chosen document
///   into app-private storage while computing SHA-256, returning
///   `{path, displayName, sizeBytes, sha256}` — or `null` when cancelled;
/// * **this side never trusts that reply blindly**: it re-reads the copied
///   file and independently recomputes size and SHA-256. A mismatch means the
///   copy is not byte-identical to what the platform hashed, so the file is
///   deleted and a failure is returned — an unverified file must never reach
///   the import path;
/// * the import path then runs the existing Ed25519 signature verification,
///   so only a validly signed file can ever classify as Official.
const FilePicker platformFilePicker = PlatformFilePicker();

final class PlatformFilePicker implements FilePicker {
  const PlatformFilePicker();

  /// Channel name, kept byte-identical to `FILE_PICKER_CHANNEL` in
  /// `MainActivity.kt` (`net.specta.app/file_picker`).
  ///
  /// These two strings drifted apart once: the native side used a slash and
  /// this side used a dot, so every `pickFile` call threw
  /// `MissingPluginException` and the UI correctly reported "browsing is not
  /// available on this device" on hardware where SAF works perfectly. A channel
  /// name is a wire contract like any other.
  static const MethodChannel _channel = MethodChannel(
    'net.specta.app/file_picker',
  );

  @override
  Future<FilePickResult> pick({
    List<String> mimeTypes = defaultMimeTypes,
  }) async {
    final Object? reply;
    try {
      reply = await _channel.invokeMethod<Object>('pickFile', <String, Object>{
        'mimeTypes': mimeTypes,
      });
    } on MissingPluginException {
      // No native handler: be honest that browsing is unavailable instead of
      // silently reporting a cancel the user never performed.
      return const FilePickUnsupported();
    } on PlatformException catch (error) {
      return FilePickFailed(_platformMessage(error));
    }
    if (reply == null) {
      return const FilePickCancelled();
    }
    if (reply is! Map) {
      return const FilePickFailed(
        'The file picker returned an unreadable response.',
      );
    }
    return _verifyCopy(reply);
  }

  /// Re-reads the file the platform claims to have copied and proves it is
  /// byte-identical (size + SHA-256) before any caller may use the path.
  Future<FilePickResult> _verifyCopy(Map<Object?, Object?> reply) async {
    final Object? path = reply['path'];
    final Object? name = reply['displayName'];
    final Object? size = reply['sizeBytes'];
    final Object? digest = reply['sha256'];

    if (path is! String || path.isEmpty) {
      return const FilePickFailed(
        'The file picker did not return a usable file path.',
      );
    }
    if (size is! int || size < 0) {
      return const FilePickFailed(
        'The file picker returned an invalid file size.',
      );
    }
    if (digest is! String || !_sha256Pattern.hasMatch(digest)) {
      return const FilePickFailed(
        'The file picker returned an invalid integrity digest.',
      );
    }
    if (size > maxPickedFileBytes) {
      return const FilePickFailed('That file is too large to import.');
    }

    final String expectedSha256 = digest.toLowerCase();
    final File file = File(path);
    try {
      if (!await file.exists()) {
        return const FilePickFailed(
          'The picked file is missing after the copy.',
        );
      }
      final int actualSize = await file.length();
      if (actualSize != size) {
        await _deleteRejectedCopy(file);
        return const FilePickFailed('The copied file failed its size check.');
      }
      final List<int> bytes = await file.readAsBytes();
      final Hash hash = await Sha256().hash(bytes);
      if (_toHex(hash.bytes) != expectedSha256) {
        await _deleteRejectedCopy(file);
        return const FilePickFailed(
          'The copied file failed its integrity check.',
        );
      }
      return FilePicked(
        PickedFile(
          path: path,
          displayName: (name is String && name.trim().isNotEmpty)
              ? name.trim()
              : _fallbackName(path),
          sizeBytes: size,
          sha256: expectedSha256,
        ),
      );
    } on Object {
      // Any I/O failure during verification is a verification failure: never
      // hand an unverified path to the import path.
      return const FilePickFailed(
        'The copied file could not be verified on this device.',
      );
    }
  }

  /// A copy that failed verification must not linger for a later import.
  static Future<void> _deleteRejectedCopy(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on Object {
      // Best effort: the path never escapes this class on failure anyway.
    }
  }

  static String _fallbackName(String path) {
    final String base = path.split(Platform.pathSeparator).last.trim();
    return base.isEmpty ? 'picked.file' : base;
  }

  static String _platformMessage(PlatformException error) {
    final String? message = error.message?.trim();
    if (message != null && message.isNotEmpty) return message;
    return 'The file picker failed (code ${error.code}).';
  }

  static String _toHex(List<int> bytes) {
    final StringBuffer buffer = StringBuffer();
    for (final int byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}

/// The file-picker binding. Tests override this provider.
final Provider<FilePicker> filePickerProvider = Provider<FilePicker>(
  (Ref ref) => platformFilePicker,
);
