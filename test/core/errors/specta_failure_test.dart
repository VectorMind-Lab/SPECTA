import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';

ExtensionFailure _failure(ExtensionFailureType type, {bool? isRetryable}) {
  return ExtensionFailure(
    extensionId: 'happypeople',
    operation: 'getSources',
    type: type,
    message: 'controlled message',
    timestamp: DateTime.utc(2026, 9, 15, 12),
    isRetryable: isRetryable,
  );
}

void main() {
  group('ExtensionFailureType', () {
    test('exposes the agreed canonical codes', () {
      expect(ExtensionFailureType.networkError.code, 'NETWORK_ERROR');
      expect(ExtensionFailureType.timeout.code, 'TIMEOUT');
      expect(ExtensionFailureType.httpError.code, 'HTTP_ERROR');
      expect(ExtensionFailureType.parseError.code, 'PARSE_ERROR');
      expect(ExtensionFailureType.invalidResult.code, 'INVALID_RESULT');
      expect(ExtensionFailureType.unsupported.code, 'UNSUPPORTED');
      expect(ExtensionFailureType.runtimeError.code, 'RUNTIME_ERROR');
      expect(ExtensionFailureType.capabilityError.code, 'CAPABILITY_ERROR');
    });

    test('declares retryability per category', () {
      expect(ExtensionFailureType.networkError.retryable, isTrue);
      expect(ExtensionFailureType.timeout.retryable, isTrue);
      expect(ExtensionFailureType.parseError.retryable, isFalse);
      expect(ExtensionFailureType.capabilityError.retryable, isFalse);
    });
  });

  group('ExtensionFailure', () {
    test('inherits retryability from its category', () {
      expect(_failure(ExtensionFailureType.timeout).isRetryable, isTrue);
      expect(_failure(ExtensionFailureType.invalidResult).isRetryable, isFalse);
    });

    test('can override retryability explicitly', () {
      expect(
        _failure(
          ExtensionFailureType.parseError,
          isRetryable: true,
        ).isRetryable,
        isTrue,
      );
    });

    test('produces a structured diagnostics record', () {
      final ExtensionFailure failure = _failure(ExtensionFailureType.httpError);

      expect(failure.toDiagnostics(), <String, Object?>{
        'extensionId': 'happypeople',
        'operation': 'getSources',
        'errorType': 'HTTP_ERROR',
        'timestamp': '2026-09-15T12:00:00.000Z',
        'message': 'controlled message',
      });
    });

    test('never renders a stack trace in its message', () {
      expect(
        _failure(ExtensionFailureType.runtimeError).toString(),
        'RUNTIME_ERROR [happypeople/getSources] controlled message',
      );
    });
  });

  group('CapabilityFailure', () {
    test('names the undeclared capability', () {
      const CapabilityFailure failure = CapabilityFailure(
        extensionId: 'happypeople',
        capability: 'sources.dash',
      );

      expect(failure.capability, 'sources.dash');
      expect(failure.message, contains('sources.dash'));
      expect(failure.isRetryable, isFalse);
    });
  });

  group('SpectaResult', () {
    test('carries a value when ok', () {
      const SpectaResult<int> result = Ok<int>(7);

      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.valueOrNull, 7);
      expect(result.failureOrNull, isNull);
      expect(
        result.fold(ok: (int value) => 'value $value', err: (_) => 'error'),
        'value 7',
      );
    });

    test('carries a failure when not ok', () {
      final SpectaResult<int> result = Err<int>(
        _failure(ExtensionFailureType.networkError),
      );

      expect(result.isErr, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.failureOrNull, isA<ExtensionFailure>());
      expect(
        result.fold(ok: (_) => 'value', err: (SpectaFailure f) => f.message),
        'controlled message',
      );
    });
  });
}
