import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/specta_failure.dart';
import '../../../core/errors/specta_result.dart';
import '../../../core/extensions/catalogue/extension_catalogue.dart';
import '../../../core/extensions/catalogue/extension_catalogue_client.dart';
import '../../../core/extensions/manager/extension_lifecycle_service.dart';
import '../../../core/extensions/manager/extension_manager.dart';
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
    this.updatesAvailable = const <String, String>{},
    this.rollbackAvailable = const <String>{},
    this.updateCheckDone = false,
  });

  final ExtensionsStatus status;

  /// Installed extensions, deterministically ordered by the service.
  final List<ManagedExtension> items;

  /// Whether an install/enable/disable/uninstall is in flight.
  final bool busy;

  /// User-facing text for the most recent lifecycle failure. Never a raw
  /// exception or extension internals.
  final String? errorMessage;

  /// Extension id -> the newer version the official catalogue advertises.
  ///
  /// Populated only by an explicit user-initiated check. Nothing here is
  /// applied automatically: an update still goes through the same install
  /// pipeline, and the user still chooses to run it.
  final Map<String, String> updatesAvailable;

  /// Extension ids that have a rollback point from a previous update.
  final Set<String> rollbackAvailable;

  /// Whether an update check has run at least once, so the UI can tell
  /// "checked, nothing newer" apart from "never checked".
  final bool updateCheckDone;

  static const ExtensionsState initial = ExtensionsState(
    status: ExtensionsStatus.loading,
  );

  ExtensionsState copyWith({
    ExtensionsStatus? status,
    List<ManagedExtension>? items,
    bool? busy,
    Object? errorMessage = _unset,
    Map<String, String>? updatesAvailable,
    Set<String>? rollbackAvailable,
    bool? updateCheckDone,
  }) {
    return ExtensionsState(
      status: status ?? this.status,
      items: items ?? this.items,
      busy: busy ?? this.busy,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      updatesAvailable: updatesAvailable ?? this.updatesAvailable,
      rollbackAvailable: rollbackAvailable ?? this.rollbackAvailable,
      updateCheckDone: updateCheckDone ?? this.updateCheckDone,
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
  late final ExtensionCatalogueClient _catalogue;
  bool _disposed = false;

  @override
  ExtensionsState build() {
    _service = ref.read(extensionLifecycleServiceProvider);
    _catalogue = ref.read(extensionCatalogueClientProvider);
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

  /// Installs (or replaces) an extension from an HTTPS URL.
  ///
  /// Converges on the same manager pipeline as [install]; only the way the
  /// bytes arrive differs. A rejected URL, an unreachable host, an oversized
  /// body, a bad manifest or an unsupported contract all surface as the same
  /// structured failure the caller renders.
  Future<SpectaResult<ExtensionRecord>> installFromUrl(String url) async {
    final String clean = url.trim();
    if (clean.isEmpty) {
      state = state.copyWith(errorMessage: 'Enter a source link.');
      return Err<ExtensionRecord>(
        ExtensionDistributionFailure(
          type: ExtensionDistributionFailureType.invalidUrl,
          stage: 'validate',
          detail: 'Empty URL.',
        ),
      );
    }
    state = state.copyWith(busy: true, errorMessage: null);
    final SpectaResult<ExtensionRecord> result = await _service.installFromUrl(
      clean,
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

  /// Installs one official-catalogue entry.
  ///
  /// The entry supplies only a URL and an optional checksum. Trust is still
  /// decided by the manager's own signature verification.
  Future<SpectaResult<ExtensionRecord>> installCatalogueEntry(
    ExtensionCatalogueEntry entry,
  ) async {
    state = state.copyWith(busy: true, errorMessage: null);
    final SpectaResult<ExtensionRecord> result = await _service
        .installFromCatalogueEntry(entry);
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
          ? 'The source could not be enabled.'
          : 'The source could not be disabled.',
    );
  }

  /// Permanently removes an extension, retires its runtime and deletes its file.
  ///
  /// The manager's own structured failure is surfaced verbatim, so the user is
  /// told *why* a delete was refused ("Node 0 is the core source") instead of
  /// the generic "could not be removed" that [setEnabled] can get away with.
  /// A refusal leaves the list untouched: the node is still installed.
  Future<SpectaResult<void>> uninstall(String id) async {
    state = state.copyWith(busy: true, errorMessage: null);
    final SpectaResult<UninstallOutcome> result = await _service.uninstall(id);
    if (_disposed) {
      return result.isOk ? const Ok<void>(null) : Err<void>(result.failureOrNull!);
    }

    if (result.isErr) {
      // No reload: nothing changed, and re-reading would only hide the reason.
      final SpectaFailure failure = result.failureOrNull!;
      state = state.copyWith(busy: false, errorMessage: failure.message);
      return Err<void>(failure);
    }

    await _load();
    if (_disposed) return const Ok<void>(null);
    state = state.copyWith(busy: false, errorMessage: null);
    return const Ok<void>(null);
  }

  /// Checks the official catalogue for newer published versions (D7).
  ///
  /// User-initiated only, and deliberately non-destructive: it records which
  /// installed extensions have a newer version and refreshes which ones have a
  /// rollback point. It NEVER installs anything by itself — an update still
  /// has to be chosen by the user, and then it travels the same
  /// download → manifest → compatibility → trust pipeline as any install.
  ///
  /// A catalogue that cannot be reached is not an error: the list simply
  /// reports that nothing newer is known, and the message explains why.
  Future<void> checkForUpdates() async {
    if (_disposed || state.busy) return;
    state = state.copyWith(busy: true, errorMessage: null);

    final SpectaResult<ExtensionCatalogue> catalogue = await _catalogue.load(
      OfficialExtensionCatalogue.defaultIndexUrl,
      forceRefresh: true,
    );
    if (_disposed) return;

    final Map<String, String> updates = <String, String>{};
    if (catalogue.isOk) {
      for (final ManagedExtension installed in state.items) {
        for (final ExtensionCatalogueEntry entry
            in catalogue.valueOrNull!.entries) {
          if (entry.id != installed.id) continue;
          if (isExtensionUpdateAvailable(
            installed: installed.version,
            candidate: entry.version,
          )) {
            updates[installed.id] = entry.version;
          }
          break;
        }
      }
    }

    // Rollback availability is local, so it is refreshed even when the
    // catalogue could not be reached.
    final Set<String> rollback = <String>{};
    for (final ManagedExtension installed in state.items) {
      if (await _service.isRollbackAvailable(installed.id)) {
        rollback.add(installed.id);
      }
    }
    if (_disposed) return;

    state = state.copyWith(
      busy: false,
      updatesAvailable: updates,
      rollbackAvailable: rollback,
      updateCheckDone: true,
      errorMessage: catalogue.isOk
          ? null
          : 'The source catalogue could not be reached. '
                'Installed sources are unaffected.',
    );
  }

  /// Restores the previous known-good version of an extension (D7).
  ///
  /// Returns true when a rollback point existed and was restored. A false
  /// result is reported honestly rather than silently ignored, because the
  /// common cause is "nothing to roll back to", not a crash.
  Future<bool> rollback(String id) async {
    if (_disposed || state.busy) return false;
    state = state.copyWith(busy: true, errorMessage: null);

    final bool restored = await _service.rollback(id);
    if (_disposed) return restored;

    if (!restored) {
      state = state.copyWith(
        busy: false,
        errorMessage: 'There is no earlier version to restore.',
      );
      return false;
    }

    // Re-read the authoritative list, and recompute which controls are still
    // genuinely available rather than assuming what the restore consumed.
    await _load();
    if (_disposed) return true;

    final Set<String> rollback = <String>{};
    for (final ManagedExtension installed in state.items) {
      if (await _service.isRollbackAvailable(installed.id)) {
        rollback.add(installed.id);
      }
    }
    if (_disposed) return true;

    state = state.copyWith(
      busy: false,
      rollbackAvailable: rollback,
      updatesAvailable: <String, String>{},
      errorMessage: null,
    );
    return true;
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
        errorMessage: 'Installed sources could not be read.',
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

  ExtensionFailure _localFailure(String id, String operation, String message) {
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
