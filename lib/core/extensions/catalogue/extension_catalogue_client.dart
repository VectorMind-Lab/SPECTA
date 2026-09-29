/// Fetches and parses the official extension catalogue.
///
/// The catalogue is DISCOVERY ONLY. Nothing here grants trust: a successfully
/// fetched catalogue says only which extensions are advertised. Each entry is
/// still downloaded and verified independently by the installation pipeline.
///
/// The parsed document is memoised in memory for [cacheTtl] so browsing does
/// not re-hit the network on every rebuild. No new table and no second cache
/// system is introduced: the catalogue is small, is not media metadata, and is
/// safe to re-fetch when the process restarts.
library;

import 'dart:convert';

import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/catalogue/extension_catalogue.dart';
import 'package:specta/core/extensions/catalogue/extension_repository_index.dart';
import 'package:specta/core/extensions/distribution/dart_io_extension_download_transport.dart';
import 'package:specta/core/extensions/distribution/extension_download_url_policy.dart';
import 'package:specta/core/extensions/distribution/extension_downloader.dart';

/// The conceptual official repository layout (D5).
///
/// ```text
/// VectorMind-Lab/SPECTA-Extensions/
///   repository.json      <- the catalogue document (this is what is fetched)
///   extensions/          <- one .js per extension
///   icons/               <- optional icon assets
///   releases/            <- optional release metadata
/// ```
///
/// SPECTA fetches `repository.json`, then each entry's `downloadUrl`. It does
/// not assume a layout beyond that: entry URLs are explicit, so a repository
/// MAY point anywhere over HTTPS. Nothing is ever installed implicitly — the
/// user chooses each extension individually.
abstract final class OfficialExtensionCatalogue {
  /// Document name at the repository root.
  static const String documentName = 'repository.json';

  /// The expected official repository. Only a DEFAULT: a user may point SPECTA
  /// at any compatible catalogue, and pointing elsewhere grants no trust.
  ///
  /// The owner segment (`VectorMind-Lab`) is REQUIRED and is not cosmetic. A
  /// `raw.githubusercontent.com` path addresses `<owner>/<repo>/<ref>/<path>`,
  /// so a bare `SPECTA-Extensions` has no owner to resolve and returns HTTP 404
  /// - the catalogue silently never loads. Both forms were checked live: the
  /// owner-qualified URL returns 200 with the real `repository.json`, the bare
  /// one returns 404.
  static const String defaultIndexUrl =
      'https://raw.githubusercontent.com/VectorMind-Lab/SPECTA-Extensions/main/$documentName';
}

class ExtensionCatalogueClient {
  ExtensionCatalogueClient({ExtensionDownloadTransport? transport})
    : _transport = transport ?? DartIoExtensionDownloadTransport();

  final ExtensionDownloadTransport _transport;

  /// How long a parsed catalogue is reused before re-fetching.
  static const Duration cacheTtl = Duration(minutes: 30);

  static const Duration _timeout = Duration(seconds: 15);

  ExtensionCatalogue? _cached;
  DateTime? _cachedAt;

  /// Drops the memoised document, so the next [load] re-fetches.
  void invalidate() {
    _cached = null;
    _cachedAt = null;
  }

  /// Returns the catalogue, reusing the in-memory copy while it is fresh.
  Future<SpectaResult<ExtensionCatalogue>> load(
    String indexUrl, {
    bool forceRefresh = false,
    DateTime? now,
  }) async {
    // Memoised in memory so browsing does not re-hit the network on every
    // rebuild. Deliberately not a database table: the catalogue is small, is
    // not media metadata, and is safe to re-fetch when the process restarts.
    final DateTime at = now ?? DateTime.now();
    final ExtensionCatalogue? fresh = _cached;
    final DateTime? cachedAt = _cachedAt;
    if (!forceRefresh &&
        fresh != null &&
        cachedAt != null &&
        at.difference(cachedAt) < cacheTtl) {
      return Ok<ExtensionCatalogue>(fresh);
    }

    final SpectaResult<String> fetched = await _fetch(indexUrl);
    if (fetched.isErr) {
      return Err<ExtensionCatalogue>(
        _asCatalogueFailure(fetched.failureOrNull!),
      );
    }

    final Object? decoded = _decodeOrNull(fetched.valueOrNull!);
    if (decoded == null) {
      return Err<ExtensionCatalogue>(
        ExtensionCatalogueFailure(
          type: ExtensionCatalogueFailureType.parseError,
          detail: 'Malformed JSON.',
        ),
      );
    }

    final ExtensionCatalogue? catalogue = ExtensionCatalogueParser.parse(
      decoded,
    );
    if (catalogue == null) {
      return Err<ExtensionCatalogue>(
        ExtensionCatalogueFailure(
          type: ExtensionCatalogueFailureType.unsupportedSchema,
          detail: 'Unsupported or malformed catalogue document.',
        ),
      );
    }

    _cached = catalogue;
    _cachedAt = at;
    return Ok<ExtensionCatalogue>(catalogue);
  }

  /// Fetches and parses a USER-SUPPLIED repository index.
  ///
  /// Same URL policy, same transport, same failure classification as the
  /// official catalogue — only the document SHAPE is tolerant, because the user
  /// chose this repository and repositories differ in shape. Trust is
  /// unaffected: the result is a list of [ExtensionCatalogueEntry] claims, and
  /// installing one still goes through `ExtensionManager`.
  Future<SpectaResult<ExtensionRepositoryIndex>> loadRepositoryIndex(
    String indexUrl,
  ) async {
    final SpectaResult<String> fetched = await _fetch(indexUrl);
    if (fetched.isErr) {
      return Err<ExtensionRepositoryIndex>(
        _asCatalogueFailure(fetched.failureOrNull!),
      );
    }

    final Uri? base = Uri.tryParse(indexUrl.trim());
    final Object? decoded = _decodeOrNull(fetched.valueOrNull!);
    if (base == null || decoded == null) {
      return Err<ExtensionRepositoryIndex>(
        ExtensionCatalogueFailure(
          type: ExtensionCatalogueFailureType.parseError,
          detail: 'Malformed JSON.',
        ),
      );
    }

    final ExtensionRepositoryIndex? index =
        ExtensionRepositoryIndexParser.parse(decoded, base);
    if (index == null) {
      return Err<ExtensionRepositoryIndex>(
        ExtensionCatalogueFailure(
          type: ExtensionCatalogueFailureType.noInstallableEntries,
          detail: 'No installable JavaScript extensions were listed.',
        ),
      );
    }
    return Ok<ExtensionRepositoryIndex>(index);
  }

  /// Fetches document text, applying the URL policy and classifying every
  /// failure. Shared by the official catalogue and the user-supplied index so
  /// neither can drift from the other.
  Future<SpectaResult<String>> _fetch(String indexUrl) async {
    final SpectaResult<Uri> validated = validateExtensionUrl(
      Uri.tryParse(indexUrl.trim()),
    );
    if (validated.isErr) {
      return Err<String>(
        ExtensionCatalogueFailure(
          type: ExtensionCatalogueFailureType.invalidUrl,
          detail: 'Catalogue URL rejected by policy.',
        ),
      );
    }

    final ExtensionDownloadResponse response = await _transport.get(
      validated.valueOrNull!,
      _timeout,
    );
    if (response.failure != null) {
      final SpectaFailure failure = response.failure!;
      final ExtensionDistributionFailure distribution =
          failure is ExtensionDistributionFailure
          ? failure
          : ExtensionDistributionFailure(
              type: ExtensionDistributionFailureType.networkError,
              stage: 'download',
            );
      return Err<String>(
        ExtensionCatalogueFailure(
          type: _mapFailure(distribution.type),
          statusCode: distribution.statusCode,
          detail: distribution.detail,
        ),
      );
    }

    final int status = response.statusCode ?? 0;
    if (status >= 500) {
      return Err<String>(
        ExtensionCatalogueFailure(
          type: ExtensionCatalogueFailureType.serverError,
          statusCode: status,
        ),
      );
    }
    if (status < 200 || status >= 300) {
      return Err<String>(
        ExtensionCatalogueFailure(
          type: ExtensionCatalogueFailureType.httpError,
          statusCode: status,
        ),
      );
    }

    final String? body = response.body;
    if (body == null || body.trim().isEmpty) {
      return Err<String>(
        ExtensionCatalogueFailure(
          type: ExtensionCatalogueFailureType.parseError,
          detail: 'Empty document body.',
        ),
      );
    }
    return Ok<String>(body);
  }

  /// Decodes JSON, returning null instead of throwing.
  static Object? _decodeOrNull(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  /// Re-wraps a distribution failure as a catalogue failure.
  static ExtensionCatalogueFailure _asCatalogueFailure(SpectaFailure failure) {
    if (failure is ExtensionCatalogueFailure) return failure;
    return ExtensionCatalogueFailure(
      type: ExtensionCatalogueFailureType.networkError,
    );
  }

  static ExtensionCatalogueFailureType _mapFailure(
    ExtensionDistributionFailureType type,
  ) => switch (type) {
    ExtensionDistributionFailureType.timeout =>
      ExtensionCatalogueFailureType.timeout,
    ExtensionDistributionFailureType.serverError =>
      ExtensionCatalogueFailureType.serverError,
    ExtensionDistributionFailureType.httpError =>
      ExtensionCatalogueFailureType.httpError,
    ExtensionDistributionFailureType.invalidUrl =>
      ExtensionCatalogueFailureType.invalidUrl,
    _ => ExtensionCatalogueFailureType.networkError,
  };
}
