import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/contract/extension_source.dart';

/// Quality preference for source ranking (V1 model: Auto / 480p / 720p /
/// 1080p / 4K — no 8K).
enum QualityPreference {
  auto('auto'),
  p480('480p'),
  p720('720p'),
  p1080('1080p'),
  uhd4k('4K');

  const QualityPreference(this.code);
  final String code;

  static QualityPreference fromCode(String? code) {
    if (code == null) return auto;
    for (final QualityPreference p in QualityPreference.values) {
      if (p.code == code) return p;
    }
    return auto;
  }
}

/// How one extension's participation in a source-resolution round ended.
///
/// Every terminal state is data, never an exception — one extension failing
/// must not break the round or the app.
enum SourceOutcomeKind {
  /// The extension returned candidate sources (possibly zero).
  success,

  /// The extension was not queried (disabled, no runtime, no granted
  /// `sources` capability).
  skipped,

  /// The extension was queried and failed (timeout, network, runtime,
  /// malformed output — whatever the runtime/manager classified).
  failed,

  /// The extension answered but no candidate survived SPECTA validation.
  invalid,
}

/// One extension's contribution to a source-resolution round.
final class ExtensionSourceOutcome {
  const ExtensionSourceOutcome._({
    required this.kind,
    required this.extensionId,
    required this.reference,
    this.candidates = const <ExtensionSource>[],
    this.droppedCount = 0,
    this.failure,
  });

  factory ExtensionSourceOutcome.success(
    String extensionId,
    String reference,
    List<ExtensionSource> candidates, {
    int droppedCount = 0,
  }) =>
      ExtensionSourceOutcome._(
        kind: SourceOutcomeKind.success,
        extensionId: extensionId,
        reference: reference,
        candidates: candidates,
        droppedCount: droppedCount,
      );

  factory ExtensionSourceOutcome.skipped(String extensionId, String reference) =>
      ExtensionSourceOutcome._(
        kind: SourceOutcomeKind.skipped,
        extensionId: extensionId,
        reference: reference,
      );

  factory ExtensionSourceOutcome.failed(
    String extensionId,
    String reference,
    SpectaFailure failure,
  ) =>
      ExtensionSourceOutcome._(
        kind: SourceOutcomeKind.failed,
        extensionId: extensionId,
        reference: reference,
        failure: failure,
      );

  factory ExtensionSourceOutcome.invalid(
    String extensionId,
    String reference, {
    int droppedCount = 0,
  }) =>
      ExtensionSourceOutcome._(
        kind: SourceOutcomeKind.invalid,
        extensionId: extensionId,
        reference: reference,
        droppedCount: droppedCount,
      );

  final SourceOutcomeKind kind;
  final String extensionId;

  /// The extension-internal reference this round asked about (identity data
  /// for refresh/fallback; never rendered).
  final String reference;

  /// Validated candidates — only for [SourceOutcomeKind.success].
  final List<ExtensionSource> candidates;

  /// Candidates dropped by validation — success or invalid outcomes only.
  final int droppedCount;

  /// Controlled failure — only for [SourceOutcomeKind.failed].
  final SpectaFailure? failure;

  bool get isSuccess => kind == SourceOutcomeKind.success;
  bool get isSkipped => kind == SourceOutcomeKind.skipped;
  bool get isFailed => kind == SourceOutcomeKind.failed;
  bool get isInvalid => kind == SourceOutcomeKind.invalid;
}
