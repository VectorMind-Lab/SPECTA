/// The OFFICIAL EXTENSION CATALOGUE contract (Phase D).
///
/// ## What the catalogue IS
/// A discovery/distribution document: which extensions exist, where their
/// bytes come from, and what they claim to be.
///
/// ## What the catalogue is NOT
/// It is NOT the extension manifest, and it is NOT a trust authority.
///
/// * It carries NO signature field, by design. Adding one would invite exactly
///   the wrong inference: that "listed officially" means "trusted".
/// * An official-catalogue entry does NOT make an extension Official. Trust is
///   `TrustLevel`, derived solely from the extension's OWN manifest signature
///   verified against SPECTA's published key.
/// * A raw GitHub URL does NOT make an extension Official either. GitHub is
///   distribution; it is not an identity authority.
///
/// A catalogue can therefore be wrong, tampered with, or entirely hostile
/// without granting any trust: every entry is still downloaded, size-checked,
/// manifest-parsed, contract-checked and signature-verified by the same code
/// path a device import uses.
///
/// The one integrity field it may carry is `sha256`, which is TRANSPORT
/// integrity ("these are the bytes I described"), never authenticity.
library;

import 'package:specta/core/extensions/catalogue/extension_type.dart';

/// Schema versions of the catalogue document this build understands.
abstract final class ExtensionCatalogueSchema {
  /// The catalogue format version implemented here.
  static const int current = 1;

  static bool isSupported(int? version) => version == current;
}

/// One extension as the catalogue DESCRIBES it.
///
/// Every field is a claim by the catalogue, not a verified fact. Verified facts
/// come from the extension's own manifest after download.
final class ExtensionCatalogueEntry {
  const ExtensionCatalogueEntry({
    required this.id,
    required this.name,
    required this.version,
    required this.apiVersion,
    required this.downloadUrl,
    this.description,
    this.author,
    this.contractVersion,
    this.contentTypes = const <ExtensionContentType>[],
    this.iconUrl,
    this.homepage,
    this.sha256,
    this.sizeBytes,
    this.updatedAt,
  });

  /// Extension id, which must match the manifest id in the downloaded file.
  final String id;

  final String name;

  /// Semantic version the catalogue claims. An update is only offered when
  /// this is genuinely newer than the installed version.
  final String version;

  /// Contract API major version the catalogue claims. Used to hide entries this
  /// build cannot run — never to skip the manager's own compatibility check.
  final int apiVersion;

  /// Optional additive contract revision, e.g. `2.1.0`.
  final String? contractVersion;

  /// HTTPS URL the bytes are fetched from. May be a raw GitHub URL; no GitHub
  /// authentication is used, required, or embedded.
  final String downloadUrl;

  final String? description;
  final String? author;

  /// Content scopes the catalogue claims. Advisory, for display only.
  final List<ExtensionContentType> contentTypes;

  /// Optional HTTPS icon URL for catalogue display.
  final String? iconUrl;

  final String? homepage;

  /// Optional SHA-256 of the expected bytes. Transport integrity only.
  final String? sha256;

  /// Optional expected size, used to fail fast on an implausibly large file.
  final int? sizeBytes;

  /// Optional ISO-8601 publication date.
  final DateTime? updatedAt;

  /// Whether this build's contract major version can run the entry.
  bool get apiSupported => apiVersion == 2;

  @override
  String toString() => 'ExtensionCatalogueEntry($id, $version)';
}

/// A parsed catalogue document (`repository.json`).
final class ExtensionCatalogue {
  const ExtensionCatalogue({
    required this.schemaVersion,
    required this.repositoryId,
    required this.entries,
    this.name,
    this.description,
    this.homepage,
  });

  final int schemaVersion;

  /// Stable identity of the repository, e.g. `net.specta.official`.
  final String repositoryId;

  final String? name;
  final String? description;
  final String? homepage;

  /// Entries that parsed. A malformed individual entry is skipped rather than
  /// discarding the whole catalogue.
  final List<ExtensionCatalogueEntry> entries;

  /// Entries this build can actually run, in a stable order.
  List<ExtensionCatalogueEntry> get supportedEntries {
    final List<ExtensionCatalogueEntry> result = entries
        .where((ExtensionCatalogueEntry e) => e.apiSupported)
        .toList();
    result.sort((ExtensionCatalogueEntry a, ExtensionCatalogueEntry b) {
      final int byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    return result;
  }

  ExtensionCatalogueEntry? entryById(String id) {
    for (final ExtensionCatalogueEntry entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }
}

/// Semantic version comparison for update decisions.
///
/// Negative when [a] is older than [b], zero when equal, positive when [a] is
/// newer. Never used to skip the manager's own validation.
int compareExtensionVersions(String a, String b) {
  final List<int> left = _versionParts(a);
  final List<int> right = _versionParts(b);
  for (int i = 0; i < 3; i++) {
    final int diff = left[i] - right[i];
    if (diff != 0) return diff;
  }
  return 0;
}

List<int> _versionParts(String version) {
  final RegExpMatch? match = RegExp(r'^(\d+)\.(\d+)\.(\d+)')
      .firstMatch(version.trim());
  if (match == null) return <int>[0, 0, 0];
  return <int>[
    int.tryParse(match.group(1)!) ?? 0,
    int.tryParse(match.group(2)!) ?? 0,
    int.tryParse(match.group(3)!) ?? 0,
  ];
}

/// Whether [candidate] is strictly newer than [installed].
bool isExtensionUpdateAvailable({
  required String installed,
  required String candidate,
}) => compareExtensionVersions(candidate, installed) > 0;

/// Defensive parser for the catalogue document.
///
/// Every field is type-checked and length-bounded. A wrong-typed or oversized
/// value degrades to null or skips that entry; it never throws into the UI.
abstract final class ExtensionCatalogueParser {
  /// Maximum entries accepted from one document, so a hostile catalogue cannot
  /// make the UI build an unbounded list.
  static const int maxEntries = 500;

  /// Maximum length of any single string field.
  static const int maxFieldLength = 2048;

  static String? _string(Object? value) {
    if (value is! String) return null;
    final String trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > maxFieldLength) return null;
    return trimmed;
  }

  /// Parses a decoded JSON map. Returns null when the document is unusable.
  static ExtensionCatalogue? parse(Object? decoded) {
    if (decoded is! Map) return null;
    final Object? rawSchema = decoded['schemaVersion'];
    final int? schemaVersion = rawSchema is int
        ? rawSchema
        : int.tryParse('$rawSchema');
    if (!ExtensionCatalogueSchema.isSupported(schemaVersion)) return null;

    final String? repositoryId = _string(decoded['repositoryId']);
    if (repositoryId == null) return null;

    final Object? rawEntries = decoded['extensions'];
    if (rawEntries is! List) return null;

    final List<ExtensionCatalogueEntry> entries = <ExtensionCatalogueEntry>[];
    for (final Object? raw in rawEntries.take(maxEntries)) {
      final ExtensionCatalogueEntry? entry = _parseEntry(raw);
      // A malformed entry is skipped, never fatal: one bad record must not
      // hide every other extension in the catalogue.
      if (entry != null) entries.add(entry);
    }

    return ExtensionCatalogue(
      schemaVersion: schemaVersion!,
      repositoryId: repositoryId,
      name: _string(decoded['name']),
      description: _string(decoded['description']),
      homepage: _string(decoded['homepage']),
      entries: entries,
    );
  }

  static ExtensionCatalogueEntry? _parseEntry(Object? raw) {
    if (raw is! Map) return null;
    final String? id = _string(raw['id']);
    final String? name = _string(raw['name']);
    final String? version = _string(raw['version']);
    final String? downloadUrl = _string(raw['downloadUrl']);
    final Object? apiVersion = raw['apiVersion'];

    // The fields without which an entry cannot be acted on at all.
    if (id == null ||
        name == null ||
        version == null ||
        downloadUrl == null ||
        apiVersion is! int) {
      return null;
    }
    // Must look like semver, so a malformed value can never be compared as if
    // it were a real release.
    if (!RegExp(r'^\d+\.\d+\.\d+([-+][0-9A-Za-z.\-]+)?$').hasMatch(version)) {
      return null;
    }

    final List<ExtensionContentType> types = <ExtensionContentType>[];
    final Object? rawTypes = raw['contentTypes'];
    if (rawTypes is List) {
      for (final Object? code in rawTypes.take(maxEntries)) {
        if (code is! String) continue;
        final ExtensionContentType? type = ExtensionContentType.fromCode(code);
        if (type != null) types.add(type);
      }
    }

    final Object? size = raw['sizeBytes'];
    final String? updated = _string(raw['updatedAt']);

    return ExtensionCatalogueEntry(
      id: id,
      name: name,
      version: version,
      apiVersion: apiVersion,
      contractVersion: _string(raw['contractVersion']),
      downloadUrl: downloadUrl,
      description: _string(raw['description']),
      author: _string(raw['author']),
      contentTypes: types,
      iconUrl: _string(raw['iconUrl']),
      homepage: _string(raw['homepage']),
      sha256: _string(raw['sha256']),
      sizeBytes: size is int && size > 0 ? size : null,
      updatedAt: updated == null ? null : DateTime.tryParse(updated),
    );
  }
}
