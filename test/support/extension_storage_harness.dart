/// Real-filesystem test helpers for the extension subsystem.
library;

import 'dart:io';

import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/distribution/extension_storage.dart';

/// An [ExtensionStorage] rooted at a test-owned temporary directory.
///
/// Replaces the production `getApplicationSupportDirectory()` platform channel
/// so a test can create and delete real files under a real app-private root.
final class FixedRootExtensionStorage implements ExtensionStorage {
  FixedRootExtensionStorage(this.root);

  final Directory root;

  @override
  Future<SpectaResult<Directory>> resolveDirectory() async {
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return Ok<Directory>(root);
  }
}

/// A [SourceFileRemover] that always refuses, for asserting that no file is
/// touched when a delete is refused.
final class NeverRemovingSourceFileRemover implements SourceFileRemover {
  const NeverRemovingSourceFileRemover();

  @override
  Future<bool> remove(String? path) async => false;
}
