/// Production extension-download transport over `dart:io` HttpClient.
///
/// Mirrors the sandboxed request policy's transport decisions that matter for
/// distribution: a bounded deadline, redirects re-validated on EVERY hop, and
/// a byte cap enforced while streaming rather than after buffering.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/distribution/extension_download_url_policy.dart';
import 'package:specta/core/extensions/distribution/extension_downloader.dart';

final class DartIoExtensionDownloadTransport
    implements ExtensionDownloadTransport {
  DartIoExtensionDownloadTransport({HttpClient? client, this.maxRedirects = 4})
    : _client = client ?? HttpClient();

  final HttpClient _client;
  final int maxRedirects;

  /// True for statuses that carry a `Location` to follow.
  static bool isRedirect(int? status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  @override
  Future<ExtensionDownloadResponse> get(Uri uri, Duration timeout) async {
    Uri current = uri;
    for (int hop = 0; hop <= maxRedirects; hop++) {
      try {
        final HttpClientResponse response = await _send(current, timeout);

        if (isRedirect(response.statusCode)) {
          final String? location = response.headers.value('location');
          if (location == null || location.isEmpty) {
            return ExtensionDownloadResponse(
              statusCode: response.statusCode,
              failure: ExtensionDistributionFailure(
                type: ExtensionDistributionFailureType.redirectRefused,
                stage: 'download',
                statusCode: response.statusCode,
                detail: 'Redirect without a Location header.',
              ),
            );
          }
          // A redirect may not widen the policy: a public https URL that
          // redirects to http, to loopback, or to a credential-bearing URL is
          // refused, not followed.
          final Uri next = current.resolve(location);
          if (isBlockedExtensionHost(next.host) ||
              next.scheme.toLowerCase() != 'https' ||
              next.userInfo.isNotEmpty) {
            return _refused('Redirect left the allowed https policy.');
          }
          current = next;
          continue;
        }

        return ExtensionDownloadResponse(
          statusCode: response.statusCode,
          body: await _readCapped(response, timeout),
          resolvedUrl: current.toString(),
        );
      } on ExtensionDistributionFailure catch (failure) {
        return ExtensionDownloadResponse(failure: failure);
      } on SocketException catch (e) {
        return _network('Socket error: ${e.osError?.message ?? e.message}');
      } on TlsException catch (e) {
        return _network('TLS error: ${e.osError?.message ?? e.message}');
      } on HttpException catch (e) {
        return _network('HTTP error: ${e.message}');
      } on TimeoutException {
        return ExtensionDownloadResponse(
          failure: ExtensionDistributionFailure(
            type: ExtensionDistributionFailureType.timeout,
            stage: 'download',
            detail: 'Exceeded ${timeout.inSeconds}s deadline.',
          ),
        );
      } on Object catch (e) {
        return _network('Unexpected transport error: ${e.runtimeType}');
      }
    }
    return _refused('Exceeded $maxRedirects redirects.');
  }

  Future<HttpClientResponse> _send(Uri uri, Duration timeout) {
    return _client.getUrl(uri).timeout(timeout).then((
      HttpClientRequest request,
    ) {
      // Redirects are followed manually so each hop can be re-validated.
      request.followRedirects = false;
      return request.close().timeout(timeout);
    });
  }

  /// Reads at most [maxExtensionBytes], aborting the moment the cap is passed
  /// so an oversized or endless body is never fully buffered.
  Future<String> _readCapped(
    HttpClientResponse response,
    Duration timeout,
  ) async {
    if (response.contentLength > maxExtensionBytes) {
      throw ExtensionDistributionFailure(
        type: ExtensionDistributionFailureType.tooLarge,
        stage: 'download',
        statusCode: response.statusCode,
        detail: 'Content-Length ${response.contentLength} exceeds the cap.',
      );
    }
    final BytesBuilder builder = BytesBuilder(copy: false);
    int total = 0;
    await for (final List<int> chunk in response.timeout(timeout)) {
      total += chunk.length;
      if (total > maxExtensionBytes) {
        throw ExtensionDistributionFailure(
          type: ExtensionDistributionFailureType.tooLarge,
          stage: 'download',
          statusCode: response.statusCode,
          detail: 'Body exceeded the cap mid-stream.',
        );
      }
      builder.add(chunk);
    }
    try {
      return utf8.decode(builder.takeBytes());
    } on FormatException {
      // NOT a size problem. This used to report `tooLarge`, so a binary or
      // mis-encoded body was announced to the user as "That extension file is
      // too large to install" — pointing at a size limit that was never hit.
      throw ExtensionDistributionFailure(
        type: ExtensionDistributionFailureType.notText,
        stage: 'download',
        statusCode: response.statusCode,
        detail: 'Body is not valid UTF-8 text.',
      );
    }
  }

  ExtensionDownloadResponse _refused(String detail) =>
      ExtensionDownloadResponse(
        failure: ExtensionDistributionFailure(
          type: ExtensionDistributionFailureType.redirectRefused,
          stage: 'download',
          detail: detail,
        ),
      );

  ExtensionDownloadResponse _network(String detail) =>
      ExtensionDownloadResponse(
        failure: ExtensionDistributionFailure(
          type: ExtensionDistributionFailureType.networkError,
          stage: 'download',
          detail: detail,
        ),
      );
}
