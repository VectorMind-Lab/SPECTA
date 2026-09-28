/// Downloading extension bytes, with an injectable transport.
///
/// TRUST IS NOT DECIDED HERE. A completed download proves only that bytes
/// arrived from a permitted URL and match the checksum the source published.
/// The manifest signature is still verified by `ExtensionManager` afterwards.
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/distribution/extension_download_url_policy.dart';

/// Hard ceiling for one extension file. Matches the device-import cap so both
/// installation paths are bounded identically.
const int maxExtensionBytes = 10 * 1024 * 1024;

final RegExp _sha256Pattern = RegExp(r'^[0-9a-fA-F]{64}$');

/// One extension's bytes plus where they came from.
final class DownloadedExtension {
  const DownloadedExtension({
    required this.sourceCode,
    required this.sha256,
    required this.sizeBytes,
    required this.resolvedUrl,
  });

  /// Decoded JavaScript source, ready to be written and imported.
  final String sourceCode;

  /// Lowercase hex SHA-256 of the bytes received.
  final String sha256;

  final int sizeBytes;

  /// The URL the body actually came from, after any redirects.
  final String resolvedUrl;
}

/// Raw transport outcome. Implementations must not throw.
final class ExtensionDownloadResponse {
  const ExtensionDownloadResponse({
    this.statusCode,
    this.body,
    this.failure,
    this.resolvedUrl,
  });

  final int? statusCode;
  final String? body;
  final ExtensionDistributionFailure? failure;

  /// Where the body came from. Defaults to the requested URL.
  final String? resolvedUrl;

  bool get isSuccess =>
      statusCode != null && statusCode! >= 200 && statusCode! < 300;
}

/// Injectable transport seam, so URL rules, caps and failures are testable
/// with no network and no real host.
abstract interface class ExtensionDownloadTransport {
  /// Performs the GET. Redirects are followed by the transport and reported
  /// through [ExtensionDownloadResponse.resolvedUrl]; each hop must have been
  /// re-validated against [validateExtensionUrl] first.
  Future<ExtensionDownloadResponse> get(Uri uri, Duration timeout);
}

/// Fetches an extension subject to the HTTPS-only URL policy, a size cap, and
/// an optional published checksum.
class ExtensionDownloader {
  ExtensionDownloader(this._transport);

  final ExtensionDownloadTransport _transport;

  static const Duration timeout = Duration(seconds: 20);

  /// Fetches [url] and returns verified bytes.
  ///
  /// [expectedSha256], when supplied, is a TRANSPORT integrity check published
  /// by the catalogue: it proves the bytes are the ones the catalogue
  /// described. It is explicitly not a trust verdict.
  Future<SpectaResult<DownloadedExtension>> download(
    String url, {
    String? expectedSha256,
    int? expectedSizeBytes,
  }) async {
    final SpectaResult<Uri> validated = validateExtensionUrl(
      Uri.tryParse(url.trim()),
    );
    if (validated.isErr) {
      return Err<DownloadedExtension>(validated.failureOrNull!);
    }

    final ExtensionDownloadResponse response = await _transport.get(
      validated.valueOrNull!,
      timeout,
    );
    if (response.failure != null) {
      return Err<DownloadedExtension>(response.failure!);
    }

    final int status = response.statusCode ?? 0;
    if (status >= 500) {
      return Err<DownloadedExtension>(
        ExtensionDistributionFailure(
          type: ExtensionDistributionFailureType.serverError,
          stage: 'download',
          statusCode: status,
        ),
      );
    }
    if (!response.isSuccess) {
      return Err<DownloadedExtension>(
        ExtensionDistributionFailure(
          type: ExtensionDistributionFailureType.httpError,
          stage: 'download',
          statusCode: status,
        ),
      );
    }

    final String? body = response.body;
    if (body == null || body.trim().isEmpty) {
      // An empty body is not a size problem either; it reported `tooLarge`
      // before, which claimed a cap had been exceeded when nothing arrived.
      return Err<DownloadedExtension>(
        ExtensionDistributionFailure(
          type: ExtensionDistributionFailureType.emptyResponse,
          stage: 'download',
          statusCode: status,
          detail: 'Empty response body.',
        ),
      );
    }

    final int size = utf8.encode(body).length;
    if (size > maxExtensionBytes ||
        (expectedSizeBytes != null && expectedSizeBytes > maxExtensionBytes)) {
      return Err<DownloadedExtension>(
        ExtensionDistributionFailure(
          type: ExtensionDistributionFailureType.tooLarge,
          stage: 'download',
          statusCode: status,
        ),
      );
    }

    final String digest = await sha256Hex(utf8.encode(body));

    if (expectedSha256 != null) {
      if (!_sha256Pattern.hasMatch(expectedSha256)) {
        return Err<DownloadedExtension>(
          ExtensionDistributionFailure(
            type: ExtensionDistributionFailureType.integrityMismatch,
            stage: 'verify',
            detail: 'Published checksum is not a SHA-256 hex digest.',
          ),
        );
      }
      if (expectedSha256.toLowerCase() != digest) {
        return Err<DownloadedExtension>(
          ExtensionDistributionFailure(
            type: ExtensionDistributionFailureType.integrityMismatch,
            stage: 'verify',
          ),
        );
      }
    }

    return Ok<DownloadedExtension>(
      DownloadedExtension(
        sourceCode: body,
        sha256: digest,
        sizeBytes: size,
        resolvedUrl: response.resolvedUrl ?? url,
      ),
    );
  }
}

/// Lowercase hex SHA-256 of [bytes].
Future<String> sha256Hex(List<int> bytes) async {
  final List<int> digest = await Sha256().hash(bytes).then((Hash h) => h.bytes);
  return digest.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
}
