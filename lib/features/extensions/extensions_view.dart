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
import 'extensions_details_sheet.dart';
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
                  'Installed sources could not be read.',
              action: () => ref.read(extensionsProvider.notifier).reload(),
              actionLabel: 'Try again',
            ),
            ExtensionsStatus.ready when state.items.isEmpty => SpectaEmptyState(
              icon: Icons.extension_outlined,
              message:
                  'No sources are installed.\nInstall a source '
                  'file to add discovery sources.',
              action: () => _install(context, ref),
              actionLabel: 'Install source',
            ),
            ExtensionsStatus.ready => ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              buildDefaultDragHandles: false,
              itemCount: state.items.length,
              // onReorderItem, not onReorder: it already corrects newIndex for
              // the removed item, so no manual off-by-one is needed (and adding
              // one here would double-apply it).
              onReorderItem: (int oldIndex, int newIndex) {
                ref
                    .read(extensionsProvider.notifier)
                    .reorder(state.items[oldIndex].id, newIndex);
              },
              itemBuilder: (BuildContext context, int index) {
                return Padding(
                  // The key belongs on the widget ReorderableListView actually
                  // builds, which is this Padding - not on the card inside it.
                  key: ValueKey<String>(state.items[index].id),
                  padding: EdgeInsets.only(
                    bottom: index == state.items.length - 1 ? 0 : 8,
                  ),
                  child: _ExtensionCard(
                  extension: state.items[index],
                  busy: state.busy,
                  index: index,
                  isFirst: index == 0,
                  isLast: index == state.items.length - 1,
                  updateVersion: state.updatesAvailable[state.items[index].id],
                  canRollback: state.rollbackAvailable.contains(
                    state.items[index].id,
                  ),
                  onMoveUp: index == 0
                      ? null
                      : () => _reorder(context, ref, state.items[index], index - 1),
                  onMoveDown: index == state.items.length - 1
                      ? null
                      : () => _reorder(context, ref, state.items[index], index + 1),
                  onToggle: (bool enabled) =>
                      _setEnabled(context, ref, state.items[index].id, enabled),
                  onUpdate: () => _update(context, ref, state.items[index]),
                  onRollback: () => _rollback(context, ref, state.items[index]),
                  onUninstall: () =>
                      _uninstall(context, ref, state.items[index]),
                  ),
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
            'SPECTA reads the sources it lists and installs them one at a '
            'time, through the same checks as any other source. Being '
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
              ? 'All installed sources are up to date.'
              : '${state.updatesAvailable.length} source'
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
          content: Text('That source is no longer in the catalogue.'),
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

  Future<void> _reorder(
    BuildContext context,
    WidgetRef ref,
    ManagedExtension extension,
    int target,
  ) async {
    final SpectaResult<void> result = await ref
        .read(extensionsProvider.notifier)
        .reorder(extension.id, target);
    if (result.isOk || !context.mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.failureOrNull!.message)));
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
            title: const Text('Remove source'),
            // The NODE LABEL, not the source's name. The confirmation is the
            // most-read dialog in a destructive flow, so it must not print a
            // streaming-site name the provider chose.
            content: Text(
              'Remove ${extension.nodeLabel ?? 'this source'}? Its saved state '
              'on this device is deleted. You can install it again at any time.',
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
                  'Sources',
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
                    tooltip: 'Reload installed sources',
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: busy ? null : onCheckUpdates,
                    icon: const Icon(Icons.upgrade_rounded),
                    tooltip:
                        'Check the official catalogue for source updates',
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
                    tooltip: 'Browse the official source catalogue',
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
    required this.index,
    required this.isFirst,
    required this.isLast,
    required this.onToggle,
    required this.onUninstall,
    this.onMoveUp,
    this.onMoveDown,
    this.updateVersion,
    this.canRollback = false,
    this.onUpdate,
    this.onRollback,
  });

  final ManagedExtension extension;
  final bool busy;

  /// Position in the visible list, for the drag handle's index.
  final int index;

  /// Whether this card is at either end of the list, which disables the
  /// corresponding move control.
  final bool isFirst;
  final bool isLast;

  /// Newer version the catalogue advertises, when a check has found one.
  final String? updateVersion;

  /// Whether a previous version is available to restore.
  final bool canRollback;

  final ValueChanged<bool> onToggle;
  final VoidCallback onUninstall;
  final VoidCallback? onUpdate;
  final VoidCallback? onRollback;

  /// Move controls. Null at the corresponding end of the list.
  ///
  /// There is deliberately no "locked nodes cannot move" rule: Node 0 reorders
  /// like anything else and stays undeletable wherever it lands (A4/Q5).
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  void _showDetails(BuildContext context, ManagedExtension extension) {
    ExtensionDetailsSheet.show(context, extension);
  }

  @override
  Widget build(BuildContext context) {
    return SpectaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // PRIMARY LINE: the node label, and nothing else.
              //
              // The source's own name is deliberately NOT here. It is chosen by
              // whoever wrote the extension, so showing it in the most prominent
              // position of the user's source list would hand a third party
              // control of SPECTA's UI and leak a streaming-site name onto a
              // screen the owner reads every day. It lives in the details sheet.
              Expanded(
                child: Text(
                  extension.nodeLabel ?? 'Node',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: SpectaColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // The app-developer mark. Gated on a VERIFIED trust level only —
              // see SpectaDeveloperDot for why nothing weaker may switch it on.
              // It is a PROVENANCE mark, not a quality score and not a ranking:
              // a green dot says who signed the file, nothing more. It sits
              // after the flexible label so a truncated label can never hide it.
              if (extension.trustLevel == TrustLevel.official) ...<Widget>[
                const SizedBox(width: 7),
                const SpectaDeveloperDot(),
              ],
              const SizedBox(width: 4),
              // Long-press drag handle. `buildDefaultDragHandles` is off so
              // only this handle starts a drag, leaving taps on the rest of the
              // card working normally.
              ReorderableDragStartListener(
                index: index,
                child: const Icon(
                  Icons.drag_indicator_rounded,
                  color: SpectaColors.textMuted,
                ),
              ),
              IconButton(
                onPressed: () => _showDetails(context, extension),
                icon: const Icon(Icons.info_outline_rounded),
                color: SpectaColors.textSecondary,
                tooltip: 'Details',
              ),
            ],
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
              // Reorder controls. Buttons rather than drag-only, so reordering
              // is reachable with a D-pad on a TV and with a screen reader.
              // The first card has no "up" and the last no "down"; Node 0 is
              // NOT exempt from either.
              IconButton(
                onPressed: (busy || onMoveUp == null) ? null : onMoveUp,
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                color: SpectaColors.textSecondary,
                tooltip: 'Move up',
              ),
              IconButton(
                onPressed: (busy || onMoveDown == null) ? null : onMoveDown,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                color: SpectaColors.textSecondary,
                tooltip: 'Move down',
              ),
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
                // Node 0 is undeletable. The control is DISABLED rather than
                // hidden, and the tooltip says why: silently removing the
                // affordance would leave the user wondering where it went,
                // while letting them tap it would only produce a refusal.
                onPressed: (busy || extension.nodeLocked)
                    ? null
                    : onUninstall,
                icon: Icon(
                  extension.nodeLocked
                      ? Icons.lock_outline_rounded
                      : Icons.delete_outline_rounded,
                ),
                color: SpectaColors.failure,
                tooltip: extension.nodeLocked
                    ? '${extension.nodeLabel} is the core source and cannot be '
                          'removed'
                    : 'Remove source',
              ),
            ],
          ),
        ],
      ),
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
      title: const Text('Install source'),
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
