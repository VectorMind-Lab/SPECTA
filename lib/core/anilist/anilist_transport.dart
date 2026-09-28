import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:specta/core/errors/specta_failure.dart';

/// Raw AniList GraphQL transport outcome. It never throws.
final class AniListHttpResponse {
  const AniListHttpResponse({this.statusCode, this.body, this.failure});

  final int? statusCode;
  final String? body;
  final AniListFailure? failure;

  bool get isSuccess =>
      statusCode != null && statusCode! >= 200 && statusCode! < 300;
}

/// Injectable transport boundary for AniList GraphQL POST requests.
abstract interface class AniListTransport {
  Future<AniListHttpResponse> post({
    required Uri uri,
    required String body,
    required Map<String, String> headers,
    required Duration timeout,
  });
}

/// Production transport using the standard dart:io HttpClient.
final class DartIoAniListTransport implements AniListTransport {
  DartIoAniListTransport({HttpClient? client})
    : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<AniListHttpResponse> post({
    required Uri uri,
    required String body,
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    try {
      final HttpClientRequest request = await _client
          .postUrl(uri)
          .timeout(timeout);
      headers.forEach(request.headers.set);
      request.write(body);
      final HttpClientResponse response = await request.close().timeout(
        timeout,
      );
      final String text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(timeout);
      return AniListHttpResponse(statusCode: response.statusCode, body: text);
    } on SocketException catch (e) {
      return AniListHttpResponse(
        failure: AniListFailure(
          type: AniListFailureType.networkError,
          detail: 'Socket error: ${e.osError?.message ?? e.message}',
        ),
      );
    } on TlsException catch (e) {
      return AniListHttpResponse(
        failure: AniListFailure(
          type: AniListFailureType.networkError,
          detail: 'TLS error: ${e.osError?.message ?? e.message}',
        ),
      );
    } on HttpException catch (e) {
      return AniListHttpResponse(
        failure: AniListFailure(
          type: AniListFailureType.networkError,
          detail: 'HTTP error: ${e.message}',
        ),
      );
    } on TimeoutException {
      return AniListHttpResponse(
        failure: AniListFailure(
          type: AniListFailureType.timeout,
          detail: 'Request exceeded deadline (${timeout.inSeconds}s)',
        ),
      );
    } on Object catch (e) {
      return AniListHttpResponse(
        failure: AniListFailure(
          type: AniListFailureType.networkError,
          detail: 'Unexpected transport error: ${e.runtimeType}',
        ),
      );
    }
  }
}
