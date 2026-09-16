import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Owns the on-disk layout of SPECTA's app-private storage.
///
/// SQLite holds structured state only; downloaded media is stored as real
/// files (never inside the database). Everything lives under the app support
/// directory so uninstalling SPECTA removes it, and no user-visible storage
/// permission is required.
class SpectaStorage {
  const SpectaStorage();

  static const String mediaDirectoryName = 'media';
  static const String metadataCacheDirectoryName = 'metadata';

  /// Root of all app-private SPECTA data.
  Future<Directory> appSupportDirectory() => getApplicationSupportDirectory();

  /// Root for downloaded media files.
  Future<Directory> mediaDirectory() => _childDirectory(mediaDirectoryName);

  /// Root for cached metadata. Disposable at any time without data loss.
  Future<Directory> metadataCacheDirectory() =>
      _childDirectory(metadataCacheDirectoryName);

  Future<Directory> _childDirectory(String name) async {
    final Directory support = await getApplicationSupportDirectory();
    final Directory directory = Directory(p.join(support.path, name));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }
}
