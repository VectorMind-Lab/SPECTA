import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:specta/core/errors/specta_failure.dart';

/// One raw HTTP exchange outcome from [TmdbTransport].
///
/// Contains status code and raw response body if received, or [failure]
/// if the transport round failed before receiving a full response.
final class TmdbHttpResponse {
  const TmdbHttpResponse({this.statusCode, this.body, this.failure});

  final int? statusCode;
  final String? body;
  final TmdbFailure? failure;

  bool get isSuccess =>
      statusCode != null && statusCode! >= 200 && statusCode! < 300;
}

/// Abstract transport boundary for TMDB HTTP requests.
///
/// Separating transport from [TmdbClient] guarantees:
/// 1. We can test client endpoint handling, status decoding, timeouts, rate
///    limiting and parsing deterministically without any network or live TMDB key.
/// 2. Secret hygiene: The transport handles raw queries/headers, but errors
///    propagating out of the transport MUST NOT include credentials.
abstract interface class TmdbTransport {
  /// Sends an HTTP GET request to [uri] with [headers] within [timeout].
  ///
  /// Must NEVER throw: any [SocketException], [TlsException], [HttpException],
  /// or [TimeoutException] must be captured and returned as a [TmdbHttpResponse]
  /// with a sanitized [TmdbFailure].
  Future<TmdbHttpResponse> get({
    required Uri uri,
    required String endpoint,
    required Map<String, String> headers,
    required Duration timeout,
  });
}

/// Production [TmdbTransport] backed by standard `dart:io` [HttpClient].
final class DartIoTmdbTransport implements TmdbTransport {
  DartIoTmdbTransport({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<TmdbHttpResponse> get({
    required Uri uri,
    required String endpoint,
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    try {
      final HttpClientRequest request = await _client
          .getUrl(uri)
          .timeout(timeout);

      // Set standard headers
      headers.forEach((String key, String value) {
        request.headers.set(key, value);
      });

      final HttpClientResponse response = await request.close().timeout(
        timeout,
      );

      final String body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(timeout);

      return TmdbHttpResponse(statusCode: response.statusCode, body: body);
    } on SocketException catch (e) {
      return TmdbHttpResponse(
        failure: TmdbFailure(
          type: TmdbFailureType.networkError,
          endpoint: endpoint,
          detail: 'Socket error: ${e.osError?.message ?? e.message}',
        ),
      );
    } on TlsException catch (e) {
      return TmdbHttpResponse(
        failure: TmdbFailure(
          type: TmdbFailureType.networkError,
          endpoint: endpoint,
          detail: 'TLS error: ${e.osError?.message ?? e.message}',
        ),
      );
    } on HttpException catch (e) {
      return TmdbHttpResponse(
        failure: TmdbFailure(
          type: TmdbFailureType.networkError,
          endpoint: endpoint,
          detail: 'HTTP error: ${e.message}',
        ),
      );
    } on TimeoutException {
      return TmdbHttpResponse(
        failure: TmdbFailure(
          type: TmdbFailureType.timeout,
          endpoint: endpoint,
          detail: 'Request exceeded deadline (${timeout.inSeconds}s)',
        ),
      );
    } on Object catch (e) {
      return TmdbHttpResponse(
        failure: TmdbFailure(
          type: TmdbFailureType.networkError,
          endpoint: endpoint,
          detail: 'Unexpected transport error: ${e.runtimeType}',
        ),
      );
    }
  }
}
