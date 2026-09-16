import 'specta_failure.dart';

/// Outcome of an operation that is allowed to fail without throwing.
///
/// Used at boundaries where a failure is expected and must stay isolated —
/// extension calls, source resolution, downloads — so a single failure can
/// never take the application down.
sealed class SpectaResult<T> {
  const SpectaResult();

  bool get isOk => this is Ok<T>;

  bool get isErr => this is Err<T>;

  /// Value when successful, otherwise null.
  T? get valueOrNull => switch (this) {
    Ok<T>(:final T value) => value,
    Err<T>() => null,
  };

  /// Failure when unsuccessful, otherwise null.
  SpectaFailure? get failureOrNull => switch (this) {
    Ok<T>() => null,
    Err<T>(:final SpectaFailure failure) => failure,
  };

  /// Collapses both cases into a single value.
  R fold<R>({
    required R Function(T value) ok,
    required R Function(SpectaFailure failure) err,
  }) => switch (this) {
    Ok<T>(:final T value) => ok(value),
    Err<T>(:final SpectaFailure failure) => err(failure),
  };
}

final class Ok<T> extends SpectaResult<T> {
  const Ok(this.value);

  final T value;
}

final class Err<T> extends SpectaResult<T> {
  const Err(this.failure);

  final SpectaFailure failure;
}
