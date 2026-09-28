/// Reading a USER-SUPPLIED REPOSITORY INDEX.
///
/// SPECTA's own catalogue document (`repository.json`, schemaVersion 1) is
/// deliberately strict. That is correct for an official catalogue, but the
/// requirement is that the USER supplies the repository, and provider
/// repositories in the wild are published by many authors in several shapes:
/// a root object with `extensions` / `sources` / `addons` / `plugins`, a bare
/// top-level array, absolute URLs (`downloadUrl`, `url`) or RELATIVE paths
/// (`file`), `iconUrl` / `logo` / `icon`, a single `type` string instead of a
/// `contentTypes` list, or no `schemaVersion` at all.
///
/// This reader accepts those shapes and normalises them into the SAME
/// [ExtensionCatalogueEntry] the official catalogue produces, so the UI, the
/// install action and the trust rules keep exactly one code path.
///
/// TWO RULES ARE LOAD-BEARING AND ARE NOT NEGOTIABLE:
///
/// 1. **Discovery is not trust.** Nothing here grants trust, and being listed
///    changes nothing. Every entry still travels through the full
///    `ExtensionManager` pipeline: download, size cap, manifest parse,
///    compatibility, and Ed25519 signature verification. A GitHub URL is
///    distribution, never identity.
/// 2. **A relative path is resolved, never trusted blindly.** Resolution is
///    purely mechanical (RFC 3986 resolution against the index URL), and the
///    result still faces the ordinary HTTPS-only URL policy when it is fetched.
///
/// Entries that cannot possibly be installed — most importantly anything that
/// is not a `.js` file, such as a compiled or binary provider plugin — are
/// SKIPPED and COUNTED rather than shown as if they were installable. Offering
/// an install button that is guaranteed to fail is worse than saying so.
library;

import 'package:specta/core/extensions/catalogue/extension_catalogue.dart';
import 'package:specta/core/extensions/manifest.dart';

/// A parsed user-supplied repository index.
final class ExtensionRepositoryIndex {
  const ExtensionRepositoryIndex({
    required this.entries,
    this.name,
    this.description,
    this.skippedNotJavaScript = 0,
    this.skippedUnusable = 0,
    this.indexUrl,
  });

  /// Repository name, when the document declared one.
  final String? name;

  final String? description;

  /// Installable entries, in document order.
  final List<ExtensionCatalogueEntry> entries;

  /// Entries dropped because they are not a `.js` file. SPECTA executes
  /// JavaScript only, so these can never install.
  final int skippedNotJavaScript;

  /// Entries dropped because a required field was missing or malformed.
  final int skippedUnusable;

  /// Where this index was read from, for display.
  final Uri? indexUrl;

  bool get isEmpty => entries.isEmpty;
}

abstract final class ExtensionRepositoryIndexParser {
  /// Same bound as the official catalogue, so a hostile index cannot make the
  /// UI build an unbounded list.
  static const int maxEntries = 500;

  static const int maxFieldLength = 2048;

  /// Root keys that may hold the entry list, in priority order.
  static const List<String> entryArrayKeys = <String>[
    'extensions',
    'sources',
    'addons',
    'plugins',
    'providers',
    'items',
  ];

  /// Keys that may hold the extension file, absolute or relative.
  static const List<String> fileKeys = <String>[
    'downloadUrl',
    'file',
    'url',
    'path',
    'download',
  ];

  static const List<String> iconKeys = <String>[
    'iconUrl',
    'logo',
    'icon',
    'image',
  ];

  static const List<String> idKeys = <String>['id', 'internalName', 'slug'];

  static const List<String> nameKeys = <String>['name', 'title', 'displayName'];

  static const List<String> descriptionKeys = <String>['description', 'lang'];

  static const List<String> authorKeys = <String>['author', 'authors', 'owner'];

  static const List<String> homepageKeys = <String>[
    'homepage',
    'website',
    'repositoryUrl',
  ];

  static const List<String> hashKeys = <String>['sha256', 'fileHash', 'hash'];

  static String? _string(Object? value) {
    if (value is! String) return null;
    final String trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > maxFieldLength) return null;
    return trimmed;
  }

  /// True when [uri] points at a `.js` file.
  ///
  /// Query strings and fragments are ignored, so `x.js?v=2` still counts.
  static bool looksLikeJavaScript(Uri uri) =>
      uri.path.toLowerCase().endsWith('.js');

  /// Parses a decoded document. Returns null only when nothing usable was
  /// found, which the caller reports as a structural failure.
  static ExtensionRepositoryIndex? parse(Object? decoded, Uri indexUrl) {
    String? repoName;
    String? repoDescription;
    List<Object?> rawEntries = const <Object?>[];

    if (decoded is List) {
      rawEntries = decoded;
    } else if (decoded is Map) {
      repoName = _string(decoded['name']);
      repoDescription = _string(decoded['description']);
      for (final String key in entryArrayKeys) {
        final Object? candidate = decoded[key];
        if (candidate is List) {
          rawEntries = candidate;
          break;
        }
      }
    } else {
      return null;
    }

    if (rawEntries.length > maxEntries) {
      rawEntries = rawEntries.sublist(0, maxEntries);
    }

    final List<ExtensionCatalogueEntry> entries = <ExtensionCatalogueEntry>[];
    int skippedNotJavaScript = 0;
    int skippedUnusable = 0;

    for (final Object? raw in rawEntries) {
      if (raw is! Map) {
        skippedUnusable++;
        continue;
      }

      final String? rawFile = _firstString(raw, fileKeys);
      if (rawFile == null) {
        skippedUnusable++;
        continue;
      }

      // Mechanical RFC 3986 resolution: an absolute URL is unchanged, a relative
      // path resolves against the index's own directory. The result is NOT
      // trusted here — it still faces the URL policy when it is fetched.
      final Uri? parsedFile = Uri.tryParse(rawFile);
      final Uri resolved = (parsedFile != null && parsedFile.isAbsolute)
          ? parsedFile
          : indexUrl.resolve(rawFile);
      if (!resolved.isAbsolute) {
        skippedUnusable++;
        continue;
      }

      if (!looksLikeJavaScript(resolved)) {
        skippedNotJavaScript++;
        continue;
      }

      final String? id = _firstString(raw, idKeys);
      final String? name = _firstString(raw, nameKeys) ?? id;
      final String version =
          _firstString(raw, const <String>['version']) ?? '0.0.0';
      if (id == null || name == null) {
        skippedUnusable++;
        continue;
      }

      // An index is a discovery document and does not get to choose the host's
      // contract version. A missing value is reported as the current major so
      // the UI can show something; `ExtensionManager` still runs its own
      // compatibility check on the real manifest, so a lying index cannot make
      // an incompatible extension load.
      final Object? rawApi = raw['apiVersion'];
      final int apiVersion = rawApi is int ? rawApi : SpectaApiVersion.current;

      entries.add(
        ExtensionCatalogueEntry(
          id: id,
          name: name,
          version: version,
          apiVersion: apiVersion,
          downloadUrl: resolved.toString(),
          description: _firstString(raw, descriptionKeys),
          author: _firstString(raw, authorKeys),
          iconUrl: _resolveOptional(_firstString(raw, iconKeys), indexUrl),
          homepage: _firstString(raw, homepageKeys),
          sha256: _normaliseHash(_firstString(raw, hashKeys)),
        ),
      );
    }

    if (entries.isEmpty) return null;

    return ExtensionRepositoryIndex(
      entries: entries,
      name: repoName,
      description: repoDescription,
      skippedNotJavaScript: skippedNotJavaScript,
      skippedUnusable: skippedUnusable,
      indexUrl: indexUrl,
    );
  }

  static String? _firstString(Map<Object?, Object?> map, List<String> keys) {
    for (final String key in keys) {
      final String? value = _string(map[key]);
      if (value != null) return value;
    }
    return null;
  }

  static String? _resolveOptional(String? value, Uri indexUrl) {
    if (value == null) return null;
    final Uri? parsed = Uri.tryParse(value);
    if (parsed == null) return null;
    if (parsed.isAbsolute) return parsed.toString();
    return indexUrl.resolve(value).toString();
  }

  /// Normalises `sha256-<hex>` / `<hex>` to bare lowercase hex.
  ///
  /// TRANSPORT INTEGRITY ONLY — "these are the bytes I described", never
  /// authenticity. Trust remains the extension's own manifest signature.
  static String? _normaliseHash(String? value) {
    if (value == null) return null;
    final String bare = value
        .replaceFirst(RegExp('^sha-?256[:=-]?', caseSensitive: false), '')
        .trim()
        .toLowerCase();
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(bare) ? bare : null;
  }
}
