import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/specta_failure.dart';
import '../../../core/errors/specta_result.dart';
import '../../../core/extensions/manager/extension_lifecycle_service.dart';
import '../../../core/extensions/manager/extension_providers.dart';
import '../../../core/extensions/manager/extension_record.dart';

/// Lifecycle status of the extension-management surface.
enum ExtensionsStatus {
  /// The installed-extension list is being read.
  loading,

  /// The list was read successfully (it may legitimately be empty).
  ready,

  /// The list could not be read at all.
  failure,
}

/// Immutable snapshot of the extension-management surface.
///
/// It carries only data the screen renders: the installed extensions with
/// their derived health, a busy flag for in-flight mutations, and the last
/// structured error (if any). No raw exceptions ever reach this layer.
final class ExtensionsState {
  const ExtensionsState({
    required this.status,
    this.items = const <ManagedExtension>[],
    this.busy = false,
    this.errorMessage,
  });

  final ExtensionsStatus status;

  /// Installed extensions, deterministically ordered by the service.
  final List<ManagedExtension> items;

  /// Whether an install/enable/disable/uninstall is in flight.
  final bool busy;

  /// User-facing text for the most recent lifecycle failure. Never a raw
  /// exception or extension internals.
  final String? errorMessage;

  static const ExtensionsState initial = ExtensionsState(
    status: ExtensionsStatus.loading,
  );

  ExtensionsState copyWith({
    ExtensionsStatus? status,
    List<ManagedExtension>? items,
    bool? busy,
    Object? errorMessage = _unset,
  }) {
    return ExtensionsState(
      status: status ?? this.status,
      items: items ?? this.items,
      busy: busy ?? this.busy,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

/// Sentinel that lets [ExtensionsState.copyWith] distinguish "leave the
/// message alone" from "clear the message" (null).
const Object _unset = Object();

/// Drives the extension-management surface over the application-level
/// lifecycle service.
///
/// The notifier owns no persistence and no runtime objects: it asks the
/// service, which asks the manager. After any mutation it re-reads the
/// authoritative registry, so the screen always reflects persisted state —
/// including across an application restart, where the first [build] reloads
/// straight from the database.
class ExtensionsNotifier extends Notifier<ExtensionsState> {
  late final ExtensionLifecycleService _service;
  bool _disposed = false;

  @override
  ExtensionsState build() {
    _service = ref.read(extensionLifecycleServiceProvider);
    ref.onDispose(() => _disposed = true);
    unawaited(_load());
    return ExtensionsState.initial;
  }

  /// Re-reads installed extensions from the authoritative registry.
  Future<void> reload() => _load();

  /// Installs (or replaces) an extension from a local `.js` file.
  ///
  /// The returned result carries the structured failure when the file is
  /// rejected — the caller renders it, so a rejection is never silent.
  Future<SpectaResult<ExtensionRecord>> install(String filePath) async {
    state = state.copyWith(busy: true, errorMessage: null);
    final SpectaResult<ExtensionRecord> result = await _service.installFromFile(
      filePath,
    );
    if (_disposed) return result;

    if (result.isErr) {
      state = state.copyWith(
        busy: false,
        errorMessage: result.failureOrNull!.message,
      );
      return result;
    }

    await _load();
    if (_disposed) return result;
    state = state.copyWith(busy: false, errorMessage: null);
    return result;
  }

  /// Enables or disables an extension; the change is persisted immediately.
  Future<SpectaResult<void>> setEnabled(String id, bool enabled) {
    return _mutate(
      id: id,
      operation: enabled ? 'enable' : 'disable',
      action: () => _service.setEnabled(id, enabled),
      failureMessage: enabled
          ? 'The extension could not be enabled.'
          : 'The extension could not be disabled.',
    );
  }

  /// Permanently removes an extension and retires its runtime.
  Future<SpectaResult<void>> uninstall(String id) {
    return _mutate(
      id: id,
      operation: 'uninstall',
      action: () => _service.uninstall(id),
      failureMessage: 'The extension could not be removed.',
    );
  }

  /// Dismisses the current error message.
  void clearError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(errorMessage: null);
  }

  Future<void> _load() async {
    try {
      final List<ManagedExtension> items = await _service.installed();
      if (_disposed) return;
      state = state.copyWith(
        status: ExtensionsStatus.ready,
        items: items,
        errorMessage: null,
      );
    } on Object {
      if (_disposed) return;
      state = ExtensionsState(
        status: ExtensionsStatus.failure,
        items: state.items,
        errorMessage: 'Installed extensions could not be read.',
      );
    }
  }

  Future<SpectaResult<void>> _mutate({
    required String id,
    required String operation,
    required Future<void> Function() action,
    required String failureMessage,
  }) async {
    state = state.copyWith(busy: true, errorMessage: null);
    try {
      await action();
    } on Object {
      if (_disposed) {
        return Err<void>(_localFailure(id, operation, failureMessage));
      }
      state = state.copyWith(busy: false, errorMessage: failureMessage);
      return Err<void>(_localFailure(id, operation, failureMessage));
    }

    await _load();
    if (_disposed) return const Ok<void>(null);
    state = state.copyWith(busy: false, errorMessage: null);
    return const Ok<void>(null);
  }

  ExtensionFailure _localFailure(
    String id,
    String operation,
    String message,
  ) {
    return ExtensionFailure(
      extensionId: id,
      operation: operation,
      type: ExtensionFailureType.runtimeError,
      message: message,
      timestamp: DateTime.now().toUtc(),
    );
  }
}

/// The current extension-management state.
final NotifierProvider<ExtensionsNotifier, ExtensionsState> extensionsProvider =
    NotifierProvider<ExtensionsNotifier, ExtensionsState>(
      ExtensionsNotifier.new,
    );
