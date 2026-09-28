import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/platform/file_picker.dart';
import '../../app/theme/specta_colors.dart';
import '../../core/errors/specta_result.dart';
import '../../core/extensions/catalogue/extension_catalogue.dart';
import '../../core/extensions/catalogue/extension_catalogue_client.dart';
import '../../core/extensions/identity/extension_health.dart';
import '../../core/extensions/identity/trust_level.dart';
import '../../ui/widgets/specta_developer_dot.dart';
import '../../core/extensions/manager/extension_lifecycle_service.dart';
import '../../core/extensions/manager/extension_providers.dart';
import '../../core/extensions/manager/extension_record.dart';
import '../../ui/widgets/specta_badge.dart';
import '../../ui/widgets/specta_button.dart';
import '../../ui/widgets/specta_card.dart';
import '../../ui/widgets/specta_empty_state.dart';
import 'extensions_catalogue_sheet.dart';
import 'extensions_repository_sheet.dart';
import 'extensions_url_dialog.dart';
import 'state/extensions_state.dart';

/// Extension Manager: the install/manage surface for SPECTA extensions.
///
/// Phase 2H establishes the application-level lifecycle foundation this screen
/// exposes: install a local extension file, and enable, disable or remove an
/// installed one. Every control is backed by the real registry — the list is
/// read from the database on open (so it survives an application restart) and
/// re-read after every mutation.
///
/// The remote official catalogue is deliberately NOT part of this phase, and
/// there is no network here: installing means handing SPECTA a `.js` file that
/// it parses, validates, verifies and only then registers.
class ExtensionsView extends ConsumerWidget {
  const ExtensionsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExtensionsState state = ref.watch(extensionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Header(
          count: state.items.length,
          busy: state.busy,
          onInstall: () => _install(context, ref),
          onInstallFromUrl: () => _installFromUrl(context, ref),
          onBrowseCatalogue: () => _browseCatalogue(context, ref),
          onBrowseRepository: () => _browseRepository(context, ref),
          onReload: () => ref.read(extensionsProvider.notifier).reload(),
          onCheckUpdates: () => _checkForUpdates(context, ref),
        ),
        Expanded(
          child: switch (state.status) {
            ExtensionsStatus.loading => const Center(
              child: CircularProgressIndicator(),
            ),
            ExtensionsStatus.failure => SpectaEmptyState(
              icon: Icons.error_outline_rounded,
              message:
                  state.errorMessage ??
                  'Installed extensions could not be read.',
              action: () => ref.read(extensionsProvider.notifier).reload(),
              actionLabel: 'Try again',
            ),
            ExtensionsStatus.ready when state.items.isEmpty => SpectaEmptyState(
              icon: Icons.extension_outlined,
              message:
                  'No extensions are installed.\nInstall an extension '
                  'file to add discovery sources.',
              action: () => _install(context, ref),
              actionLabel: 'Install extension',
            ),
            ExtensionsStatus.ready => ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: state.items.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) {
                return _ExtensionCard(
                  extension: state.items[index],
                  busy: state.busy,
                  updateVersion: state.updatesAvailable[state.items[index].id],
                  canRollback: state.rollbackAvailable.contains(
                    state.items[index].id,
                  ),
                  onToggle: (bool enabled) =>
                      _setEnabled(context, ref, state.items[index].id, enabled),
                  onUpdate: () => _update(context, ref, state.items[index]),
                  onRollback: () => _rollback(context, ref, state.items[index]),
                  onUninstall: () =>
                      _uninstall(context, ref, state.items[index]),
                );
              },
            ),
          },
        ),
      ],
    );
  }

  Future<void> _install(BuildContext context, WidgetRef ref) async {
    final String? path = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _InstallDialog(picker: ref.read(filePickerProvider)),
    );
    if (path == null || path.trim().isEmpty || !context.mounted) return;

    final SpectaResult<ExtensionRecord> result = await ref
        .read(extensionsProvider.notifier)
        .install(path.trim());
    if (!context.mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (result.isOk) {
      final ExtensionRecord record = result.valueOrNull!;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Installed ${record.name} ${record.version} '
            '(${record.trustLevel.code}).',
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(result.failureOrNull!.message)),
      );
    }
  }

  /// Installs an extension from an HTTPS link (D2).
  ///
  /// Reuses the same confirmation path as a device import and the same
  /// lifecycle notifier, so the bytes still travel through the Extension
  /// Manager's manifest/compatibility/trust pipeline.
  Future<void> _installFromUrl(BuildContext context, WidgetRef ref) async {
    final String? url = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => const UrlInstallDialog(),
    );
    if (url == null || url.trim().isEmpty || !context.mounted) return;

    final SpectaResult<ExtensionRecord> result = await ref
        .read(extensionsProvider.notifier)
        .installFromUrl(url.trim());
    if (!context.mounted) return;
    _reportInstall(context, result);
  }

  /// Browses the official catalogue and installs one entry at a time (D6).
  ///
  /// The catalogue is DISCOVERY only: nothing is installed automatically, and
  /// being listed grants no trust — the chosen entry still goes through the
  /// full install pipeline and is reported with the trust level it earned.
  Future<void> _browseCatalogue(BuildContext context, WidgetRef ref) async {
    final ExtensionCatalogueEntry? entry =
        await showModalBottomSheet<ExtensionCatalogueEntry>(
          context: context,
          isScrollControlled: true,
          builder: (BuildContext sheetContext) => ExtensionsCatalogueSheet(
            client: ref.read(extensionCatalogueClientProvider),
            installed: <String, String>{
              for (final ManagedExtension e
                  in ref.read(extensionsProvider).items)
                e.id: e.version,
            },
          ),
        );
    if (entry == null || !context.mounted) return;

    final SpectaResult<ExtensionRecord> result = await ref
        .read(extensionsProvider.notifier)
        .installCatalogueEntry(entry);
    if (!context.mounted) return;
    _reportInstall(context, result);
  }

  /// Opens a user-supplied repository index and installs one provider at a
  /// time (requirement D).
  ///
  /// The repository is DISCOVERY only, exactly like the official catalogue:
  /// nothing installs automatically, and being listed grants no trust. The
  /// chosen entry goes through the same `installCatalogueEntry` the official
  /// catalogue uses, so it converges on the identical ExtensionManager
  /// boundary — there is no second installation pipeline.
  Future<void> _browseRepository(BuildContext context, WidgetRef ref) async {
    final String? url = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => const UrlInstallDialog(
        title: 'Open a repository',
        fieldLabel: 'Repository index link',
        hint: 'https://.../index.json',
        actionLabel: 'Open',
        explanation:
            'Paste a link to a provider index such as index.json. '
            'SPECTA reads the providers it lists and installs them one at a '
            'time, through the same checks as any other extension. Being '
            'listed in a repository does not make a provider trusted.',
      ),
    );
    if (url == null || url.trim().isEmpty || !context.mounted) return;

    final ExtensionCatalogueEntry? entry =
        await showModalBottomSheet<ExtensionCatalogueEntry>(
          context: context,
          isScrollControlled: true,
          builder: (BuildContext sheetContext) => ExtensionsRepositorySheet(
            client: ref.read(extensionCatalogueClientProvider),
            indexUrl: url.trim(),
            installed: <String, String>{
              for (final ManagedExtension e
                  in ref.read(extensionsProvider).items)
                e.id: e.version,
            },
          ),
        );
    if (entry == null || !context.mounted) return;

    final SpectaResult<ExtensionRecord> result = await ref
        .read(extensionsProvider.notifier)
        .installCatalogueEntry(entry);
    if (!context.mounted) return;
    _reportInstall(context, result);
  }

  /// One confirmation path for every install route, so a rejection is never
  /// silent and a success always names the trust level actually earned.
  void _reportInstall(
    BuildContext context,
    SpectaResult<ExtensionRecord> result,
  ) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (result.isOk) {
      final ExtensionRecord record = result.valueOrNull!;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Installed ${record.name} ${record.version} '
            '(${record.trustLevel.code}).',
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(result.failureOrNull!.message)),
      );
    }
  }

  /// Checks the official catalogue for newer published versions (D7).
  ///
  /// Never installs anything by itself: it only reports what is newer, and the
  /// user then chooses to update a specific extension.
  Future<void> _checkForUpdates(BuildContext context, WidgetRef ref) async {
    final ExtensionsNotifier notifier = ref.read(extensionsProvider.notifier);
    await notifier.checkForUpdates();
    if (!context.mounted) return;

    final ExtensionsState state = ref.read(extensionsProvider);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (!state.updateCheckDone) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          state.updatesAvailable.isEmpty
              ? 'All installed extensions are up to date.'
              : '${state.updatesAvailable.length} extension'
                    '${state.updatesAvailable.length == 1 ? '' : 's'} can be updated.',
        ),
      ),
    );
  }

  /// Applies an available update to one extension (D7).
  ///
  /// The update is NOT a special path: it re-opens the catalogue and installs
  /// the newer entry exactly like any other install, so the manifest,
  /// compatibility and signature/trust gates all still run. The manager
  /// snapshots the outgoing version, which is what makes a later restore
  /// possible, and it preserves the user's enabled/disabled choice.
  Future<void> _update(
    BuildContext context,
    WidgetRef ref,
    ManagedExtension extension,
  ) async {
    final SpectaResult<ExtensionCatalogue> catalogue = await ref
        .read(extensionCatalogueClientProvider)
        .load(OfficialExtensionCatalogue.defaultIndexUrl, forceRefresh: true);
    if (catalogue.isErr) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(catalogue.failureOrNull!.message)));
      return;
    }

    ExtensionCatalogueEntry? entry;
    for (final ExtensionCatalogueEntry candidate
        in catalogue.valueOrNull!.entries) {
      if (candidate.id == extension.id) {
        entry = candidate;
        break;
      }
    }
    if (entry == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That extension is no longer in the catalogue.'),
        ),
      );
      return;
    }

    final SpectaResult<ExtensionRecord> result = await ref
        .read(extensionsProvider.notifier)
        .installCatalogueEntry(entry);
    if (!context.mounted) return;
    _reportInstall(context, result);

    // The list changed, so a fresh check is what refreshes the update/rollback
    // affordances rather than guessing at them here.
    if (result.isOk) {
      await ref.read(extensionsProvider.notifier).checkForUpdates();
    }
  }

  /// Restores the previous known-good version of one extension (D7).
  Future<void> _rollback(
    BuildContext context,
    WidgetRef ref,
    ManagedExtension extension,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Restore previous version'),
        content: Text(
          'Replace "${extension.name}" ${extension.version} with the version '
          'it was upgraded from? The current version is kept as a snapshot.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final bool restored = await ref
        .read(extensionsProvider.notifier)
        .rollback(extension.id);
    if (!context.mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          restored
              ? 'Restored the previous version of ${extension.name}.'
              : 'There is no earlier version to restore.',
        ),
      ),
    );
  }

  Future<void> _setEnabled(
    BuildContext context,
    WidgetRef ref,
    String id,
    bool enabled,
  ) async {
    final SpectaResult<void> result = await ref
        .read(extensionsProvider.notifier)
        .setEnabled(id, enabled);
    if (result.isOk || !context.mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.failureOrNull!.message)));
  }

  Future<void> _uninstall(
    BuildContext context,
    WidgetRef ref,
    ManagedExtension extension,
  ) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('Remove extension'),
            content: Text(
              'Remove "${extension.name}"? Its saved state on this device is '
              'deleted. You can install it again at any time.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;

    final SpectaResult<void> result = await ref
        .read(extensionsProvider.notifier)
        .uninstall(extension.id);
    if (result.isOk || !context.mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.failureOrNull!.message)));
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.busy,
    required this.onInstall,
    required this.onInstallFromUrl,
    required this.onBrowseCatalogue,
    required this.onBrowseRepository,
    required this.onReload,
    required this.onCheckUpdates,
  });

  final int count;
  final bool busy;
  final VoidCallback onInstall;
  final VoidCallback onInstallFromUrl;
  final VoidCallback onBrowseCatalogue;
  final VoidCallback onBrowseRepository;
  final VoidCallback onReload;
  final VoidCallback onCheckUpdates;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Extensions',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: SpectaColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count == 1 ? '1 installed' : '$count installed',
                  style: const TextStyle(
                    fontSize: 12,
                    color: SpectaColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          // The action cluster is wider than a phone screen. Found on a REAL
          // device (Phase F): a fixed Row overflowed by 147 px once the
          // install-from-link and catalogue actions were added. The cluster
          // scrolls sideways so every action stays reachable on a narrow
          // screen. `Flexible` is required: a scroll view inside a Row is
          // otherwise given unbounded width and overflows anyway.
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: busy ? null : onReload,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Reload installed extensions',
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: busy ? null : onCheckUpdates,
                    icon: const Icon(Icons.upgrade_rounded),
                    tooltip:
                        'Check the official catalogue for extension updates',
                  ),
                  const SizedBox(width: 8),
                  SpectaSecondaryButton(
                    label: 'From a link',
                    icon: Icons.link_rounded,
                    onPressed: busy ? null : onInstallFromUrl,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    fontSize: 13,
                  ),
                  const SizedBox(width: 8),
                  SpectaSecondaryButton(
                    label: 'Repository',
                    icon: Icons.storage_rounded,
                    onPressed: busy ? null : onBrowseRepository,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    fontSize: 13,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: busy ? null : onBrowseCatalogue,
                    icon: const Icon(Icons.travel_explore_rounded),
                    tooltip: 'Browse the official extension catalogue',
                  ),
                  const SizedBox(width: 8),
                  SpectaSecondaryButton(
                    label: 'Install',
                    icon: Icons.add_rounded,
                    onPressed: busy ? null : onInstall,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    fontSize: 13,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One installed extension: identity, provenance, state and its controls.
class _ExtensionCard extends StatelessWidget {
  const _ExtensionCard({
    required this.extension,
    required this.busy,
    required this.onToggle,
    required this.onUninstall,
    this.updateVersion,
    this.canRollback = false,
    this.onUpdate,
    this.onRollback,
  });

  final ManagedExtension extension;
  final bool busy;

  /// Newer version the catalogue advertises, when a check has found one.
  final String? updateVersion;

  /// Whether a previous version is available to restore.
  final bool canRollback;

  final ValueChanged<bool> onToggle;
  final VoidCallback onUninstall;
  final VoidCallback? onUpdate;
  final VoidCallback? onRollback;

  @override
  Widget build(BuildContext context) {
    return SpectaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        extension.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: SpectaColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // The app-developer mark. Gated on a VERIFIED trust level
                    // only — see SpectaDeveloperDot for why nothing weaker may
                    // switch it on. It sits after the flexible name so a
                    // truncated title can never hide it, and stays outside the
                    // trust badge so the two are independently readable.
                    if (extension.trustLevel ==
                        TrustLevel.official) ...<Widget>[
                      const SizedBox(width: 7),
                      const SpectaDeveloperDot(),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _TrustBadge(trust: extension.trustLevel),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            <String>[extension.version, extension.author].join('  ·  '),
            style: const TextStyle(
              fontSize: 12,
              color: SpectaColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            extension.id,
            style: const TextStyle(fontSize: 11, color: SpectaColors.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          // Update / restore row. Shown only when there is genuinely something
          // to do, so the card stays identical for an up-to-date extension.
          if (updateVersion != null || canRollback) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                if (updateVersion != null) ...<Widget>[
                  SpectaSecondaryButton(
                    label: 'Update to $updateVersion',
                    icon: Icons.system_update_rounded,
                    onPressed: busy ? null : onUpdate,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    fontSize: 12,
                  ),
                  const SizedBox(width: 8),
                ],
                if (canRollback)
                  SpectaSecondaryButton(
                    label: 'Restore previous',
                    icon: Icons.history_rounded,
                    onPressed: busy ? null : onRollback,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    fontSize: 12,
                  ),
              ],
            ),
          ],
          Row(
            children: <Widget>[
              _HealthBadge(extension: extension),
              const Spacer(),
              Text(
                extension.enabled ? 'Enabled' : 'Disabled',
                style: const TextStyle(
                  fontSize: 12,
                  color: SpectaColors.textSecondary,
                ),
              ),
              Switch(
                value: extension.enabled,
                onChanged: busy ? null : onToggle,
              ),
              IconButton(
                onPressed: busy ? null : onUninstall,
                icon: const Icon(Icons.delete_outline_rounded),
                color: SpectaColors.failure,
                tooltip: 'Remove extension',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Official vs unverified, derived from signature verification only.
class _TrustBadge extends StatelessWidget {
  const _TrustBadge({required this.trust});

  final TrustLevel trust;

  @override
  Widget build(BuildContext context) {
    final bool official = trust == TrustLevel.official;
    return SpectaBadge(
      label: official ? 'Official' : 'Unverified',
      backgroundColor: official
          ? SpectaColors.success.withValues(alpha: 0.14)
          : SpectaColors.warning.withValues(alpha: 0.14),
      borderColor: official
          ? SpectaColors.success.withValues(alpha: 0.5)
          : SpectaColors.warning.withValues(alpha: 0.5),
      textColor: official ? SpectaColors.success : SpectaColors.warning,
    );
  }
}

/// The extension's current lifecycle state, from the manager's own facts.
class _HealthBadge extends StatelessWidget {
  const _HealthBadge({required this.extension});

  final ManagedExtension extension;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (extension.healthState) {
      ExtensionHealth.healthy => ('Ready', SpectaColors.success),
      ExtensionHealth.degraded => ('Degraded', SpectaColors.warning),
      ExtensionHealth.temporarilyUnavailable => (
        'Unavailable',
        SpectaColors.warning,
      ),
      ExtensionHealth.disabled => ('Disabled', SpectaColors.textMuted),
      ExtensionHealth.incompatible => ('Incompatible', SpectaColors.failure),
    };

    // An extension the user switched off is disabled regardless of what its
    // health facts say — never label a switched-off extension "Ready".
    final bool disabled = !extension.enabled;
    final String effectiveLabel = disabled ? 'Disabled' : label;
    final Color effectiveColor = disabled ? SpectaColors.textMuted : color;

    return SpectaBadge(
      label: effectiveLabel,
      backgroundColor: effectiveColor.withValues(alpha: 0.14),
      borderColor: effectiveColor.withValues(alpha: 0.5),
      textColor: effectiveColor,
    );
  }
}

/// Collects a local extension file path.
///
/// Two input paths: type a path directly (works on every platform, including
/// tests and desktop), or press **Browse…** to pick a document through the
/// platform's Storage Access Framework picker. Either way this dialog only
/// gathers a path — the manager does all validation, verification and
/// installation, and a picked file must still pass its SHA-256 copy check and
/// the Ed25519 signature check before it can be trusted.
class _InstallDialog extends StatefulWidget {
  const _InstallDialog({required this.picker});

  final FilePicker picker;

  @override
  State<_InstallDialog> createState() => _InstallDialogState();
}

class _InstallDialogState extends State<_InstallDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _browsing = false;
  bool _showManualEntry = false;
  String? _browseError;

  /// The verified app-private copy. Held here, never rendered: the user sees
  /// only [PickedFile.displayName] (PRE-F §15).
  PickedFile? _picked;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// What the dialog hands back to the installer.
  String? get _installable {
    if (_picked != null) return _picked!.path;
    // Manual entry is a last-resort fallback for platforms with no picker.
    final String typed = _controller.text.trim();
    return typed.isEmpty ? null : typed;
  }

  Future<void> _browse() async {
    setState(() {
      _browsing = true;
      _browseError = null;
    });
    final FilePickResult result = await widget.picker.pick();
    if (!mounted) return;
    setState(() {
      _browsing = false;
      switch (result) {
        case FilePicked(:final PickedFile file):
          _picked = file;
        case FilePickCancelled():
          // The user backed out: say nothing, change nothing.
          break;
        case FilePickUnsupported():
          _browseError =
              'Browsing is not available on this device. '
              'Type the file path instead.';
          _showManualEntry = true;
        case FilePickFailed(:final String message):
          _browseError = message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Install extension'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // PRE-F §15: the primary flow is "choose a file". No filesystem path
          // is ever displayed — the user sees the document's own name.
          FilledButton.icon(
            onPressed: _browsing ? null : _browse,
            icon: _browsing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_open_rounded, size: 18),
            label: Text(
              _picked == null
                  ? 'Choose a .js file…'
                  : 'Choose a different file…',
            ),
          ),
          if (_picked != null) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.description_outlined,
                  size: 18,
                  color: SpectaColors.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _picked!.displayName,
                    // The name, never the app-private path behind it.
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _formatBytes(_picked!.sizeBytes),
                  style: const TextStyle(
                    fontSize: 11,
                    color: SpectaColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
          if (_showManualEntry) ...<Widget>[
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'File path',
                helperText: 'Only needed when no file picker is available.',
              ),
              onSubmitted: (String value) =>
                  Navigator.of(context).pop(_installable),
            ),
          ],
          if (_browseError != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _browseError!,
              style: const TextStyle(fontSize: 11, color: SpectaColors.failure),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'The file is copied into app-private storage and checked byte-for-'
            'byte before it is parsed, validated and signature-checked. A file '
            'that claims to be Official without a valid signature is installed '
            'as Unverified.',
            style: TextStyle(fontSize: 11, color: SpectaColors.textMuted),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _installable == null
              ? null
              : () => Navigator.of(context).pop(_installable),
          child: const Text('Install'),
        ),
      ],
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final double kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}
