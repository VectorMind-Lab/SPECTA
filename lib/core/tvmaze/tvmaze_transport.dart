import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:specta/core/errors/specta_failure.dart';

/// One raw HTTP exchange outcome from [TvmazeTransport].
///
/// Contains the status code and raw body when a full response arrived, or
/// [failure] when the round failed first. Never throws.
final class TvmazeHttpResponse {
  const TvmazeHttpResponse({this.statusCode, this.body, this.failure});

  final int? statusCode;
  final String? body;
  final TvmazeFailure? failure;

  bool get isSuccess =>
      statusCode != null && statusCode! >= 200 && statusCode! < 300;
}

/// Abstract transport boundary for TVMaze HTTP requests.
///
/// Separating transport from `TvmazeClient` makes endpoint handling, status
/// decoding, timeouts and parsing deterministically testable with no network
/// and no credential of any kind — TVMaze requires none.
abstract interface class TvmazeTransport {
  /// Sends an HTTP GET request to [uri] within [timeout].
  ///
  /// Must NEVER throw: any [SocketException], [TlsException], [HttpException]
  /// or [TimeoutException] must be captured and returned as a
  /// [TvmazeHttpResponse] carrying a sanitized [TvmazeFailure].
  Future<TvmazeHttpResponse> get({
    required Uri uri,
    required String endpoint,
    required Map<String, String> headers,
    required Duration timeout,
  });
}

/// Production [TvmazeTransport] backed by `dart:io` [HttpClient].
final class DartIoTvmazeTransport implements TvmazeTransport {
  DartIoTvmazeTransport({HttpClient? client})
    : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<TvmazeHttpResponse> get({
    required Uri uri,
    required String endpoint,
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    try {
      final HttpClientRequest request = await _client
          .getUrl(uri)
          .timeout(timeout);

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

      return TvmazeHttpResponse(statusCode: response.statusCode, body: body);
    } on SocketException catch (e) {
      return TvmazeHttpResponse(
        failure: TvmazeFailure(
          type: TvmazeFailureType.networkError,
          endpoint: endpoint,
          detail: 'Socket error: ${e.osError?.message ?? e.message}',
        ),
      );
    } on TlsException catch (e) {
      return TvmazeHttpResponse(
        failure: TvmazeFailure(
          type: TvmazeFailureType.networkError,
          endpoint: endpoint,
          detail: 'TLS error: ${e.osError?.message ?? e.message}',
        ),
      );
    } on HttpException catch (e) {
      return TvmazeHttpResponse(
        failure: TvmazeFailure(
          type: TvmazeFailureType.networkError,
          endpoint: endpoint,
          detail: 'HTTP error: ${e.message}',
        ),
      );
    } on TimeoutException {
      return TvmazeHttpResponse(
        failure: TvmazeFailure(
          type: TvmazeFailureType.timeout,
          endpoint: endpoint,
          detail: 'Request exceeded deadline (${timeout.inSeconds}s)',
        ),
      );
    } on Object catch (e) {
      return TvmazeHttpResponse(
        failure: TvmazeFailure(
          type: TvmazeFailureType.networkError,
          endpoint: endpoint,
          detail: 'Unexpected transport error: ${e.runtimeType}',
        ),
      );
    }
  }
}
