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
import 'source_health_view.dart';
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
          onAddSource: () => _showAddSourceSheet(context, ref),
          onReload: () => ref.read(extensionsProvider.notifier).reload(),
          onCheckUpdates: () => _checkForUpdates(context, ref),
          onOpenHealth: () => _openSourceHealth(context),
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

  /// Opens the "Add Source" sheet (Slice 1).
  ///
  /// This is the single, always-visible entry point for adding a source. It
  /// replaces a cluster of header controls that had to be swiped to reach.
  ///
  /// It lists ONLY routes this build genuinely implements. Nothing is invented
  /// and nothing is offered that cannot be completed:
  ///   * a URL / link           -> `installFromUrl`
  ///   * a JavaScript file      -> `installFromFile` (SAF picker)
  ///   * the official catalogue -> `installFromCatalogueEntry`
  ///   * a repository index     -> the repository sheet
  ///
  /// Every one of those already converges on the single central install
  /// boundary (`ExtensionManager._processManifest`), which re-validates,
  /// classifies trust and registers the node. This sheet is navigation only - it
  /// creates no parallel install path and no second set of gates.
  ///
  /// The sheet scrolls vertically only, so every option stays reachable on a
  /// short screen or at a large text scale, and "Install from a link" is fully
  /// visible rather than clipped.
  Future<void> _showAddSourceSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text(
                    'Add a source',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: SpectaColors.textPrimary,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    'Bring your own source. It is checked, then added as a new '
                    'node you can order and switch off.',
                    style: TextStyle(
                      fontSize: 12,
                      color: SpectaColors.textMuted,
                    ),
                  ),
                ),
                _AddSourceOption(
                  icon: Icons.link_rounded,
                  label: 'Install from a link',
                  detail: 'Paste an https address for a source file',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _installFromUrl(context, ref);
                  },
                ),
                _AddSourceOption(
                  icon: Icons.description_outlined,
                  label: 'Import a JavaScript file',
                  detail: 'Choose a .js file from this device',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _install(context, ref);
                  },
                ),
                _AddSourceOption(
                  icon: Icons.travel_explore_rounded,
                  label: 'Browse the official catalogue',
                  detail: 'Published sources you can install',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _browseCatalogue(context, ref);
                  },
                ),
                _AddSourceOption(
                  icon: Icons.storage_rounded,
                  label: 'Add from a repository',
                  detail: 'Open a source repository index by address',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _browseRepository(context, ref);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Opens Source Health (Slice 7b).
  ///
  /// This is the ONLY way into that screen. Before this existed the screen was
  /// built, tested and shipped - and was unreachable, because nothing in `lib/`
  /// ever constructed it. The route lives here, on the surface the user is
  /// already looking at, so the screen and its tests now describe something a
  /// person can actually reach.
  void _openSourceHealth(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext _) => const SourceHealthPage()),
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

    // A JSON index pasted into "Install from a link" is not a mistake to be
    // merely reported - it is a repository the user clearly meant to open.
    // Offering the action that actually works is better than a dead end, and it
    // costs nothing when the link really was a source file.
    if (result.isErr && isRepositoryIndexUrl(url.trim())) {
      final bool open = await _confirmOpenRepository(context);
      if (open && context.mounted) {
        await _openRepositoryAt(context, ref, url.trim());
      }
      return;
    }
    _reportInstall(context, result);
  }

  /// Whether [url] names a JSON index rather than a single source file.
  ///
  /// A hint based purely on the path, used only to OFFER the repository route.
  /// The decision to install still comes from the manager, so a `.json` file
  /// that is somehow a real source is never diverted by this check alone.
  static bool isRepositoryIndexUrl(String url) {
    final Uri? uri = Uri.tryParse(url.trim());
    final String path = (uri?.path ?? '').toLowerCase();
    return path.endsWith('.json');
  }

  Future<bool> _confirmOpenRepository(BuildContext context) async {
    final bool? answer = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('That link is a source repository'),
        content: const Text(
          'This address points to a JSON index that lists sources, rather '
          'than to a single source file. Open it as a repository to browse '
          'the sources it lists and install them one at a time?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          SpectaPrimaryButton(
            label: 'Open repository',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    return answer ?? false;
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

    await _openRepositoryAt(context, ref, url.trim());
  }

  /// Opens [indexUrl] in the repository sheet and installs a chosen entry.
  ///
  /// Shared by the "Add from a repository" action and by the recovery path taken
  /// when a user pastes a JSON index into "Install from a link", so both routes
  /// end in exactly the same place with the same install action.
  Future<void> _openRepositoryAt(
    BuildContext context,
    WidgetRef ref,
    String indexUrl,
  ) async {
    if (!context.mounted) return;

    final ExtensionCatalogueEntry? entry =
        await showModalBottomSheet<ExtensionCatalogueEntry>(
          context: context,
          isScrollControlled: true,
          builder: (BuildContext sheetContext) => ExtensionsRepositorySheet(
            client: ref.read(extensionCatalogueClientProvider),
            indexUrl: indexUrl,
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
    required this.onAddSource,
    required this.onReload,
    required this.onCheckUpdates,
    required this.onOpenHealth,
  });

  final int count;
  final bool busy;
  final VoidCallback onAddSource;
  final VoidCallback onReload;
  final VoidCallback onCheckUpdates;
  final VoidCallback onOpenHealth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
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
              // Only genuinely low-frequency, non-primary actions live up here,
              // and each is a fixed-size icon button, so this Row cannot overflow
              // on a narrow phone.
              //
              // Slice 1 (2026-09-28) replaced a horizontal
              // `SingleChildScrollView` action cluster that used to live here.
              // It existed because a fixed Row of seven controls overflowed a
              // real phone by 147 px (Phase F), and scrolling was the right
              // minimal fix at the time. But it left "From a link", "Install
              // from file" and Source Health off the right edge, reachable only
              // by a swipe. That is not acceptable for a primary action, so the
              // cluster is gone rather than merely re-tuned.
              IconButton(
                onPressed: busy ? null : onOpenHealth,
                icon: const Icon(Icons.monitor_heart_outlined),
                tooltip: 'Source health',
                color: SpectaColors.textSecondary,
              ),
              IconButton(
                onPressed: busy ? null : onCheckUpdates,
                icon: const Icon(Icons.upgrade_rounded),
                tooltip: 'Check the official catalogue for source updates',
                color: SpectaColors.textSecondary,
              ),
              IconButton(
                onPressed: busy ? null : onReload,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Reload installed sources',
                color: SpectaColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // The one obvious way to add a source: full width, always visible at
          // a normal phone width, never scrolled, clipped or hidden.
          SpectaPrimaryButton(
            label: 'Add Source',
            icon: Icons.add_rounded,
            onPressed: busy ? null : onAddSource,
            fontSize: 14,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ],
      ),
    );
  }
}

/// One row in the "Add Source" sheet: an icon, the route's name, and a plain
/// sentence saying what it does.
///
/// Deliberately a full-width row rather than a button in a grid or a horizontal
/// strip: the label must never be truncated or clipped on a narrow phone, and
/// every option must be reachable by scrolling down only.
class _AddSourceOption extends StatelessWidget {
  const _AddSourceOption({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 22, color: SpectaColors.textSecondary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: SpectaColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 12,
                      color: SpectaColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: SpectaColors.textMuted,
            ),
          ],
        ),
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
      // 8/6 top/bottom instead of the widget's default EdgeInsets.all(16). The
      // card is two dense rows now, so the old 16 px inset was a quarter of the
      // visible content: wasted height, repeated once per installed source.
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ROW 1 - identity and state.
          Row(
            children: <Widget>[
              // The app-developer mark, BEFORE the label. Gated on a VERIFIED
              // trust level only - see SpectaDeveloperDot for why nothing
              // weaker may switch it on. It is a PROVENANCE mark, not a quality
              // score and not a ranking: a green dot says who signed the file
              // and nothing more. It never gates whether a source may be used.
              if (extension.trustLevel == TrustLevel.official) ...<Widget>[
                const SpectaDeveloperDot(),
                const SizedBox(width: 8),
              ],
              // PRIMARY IDENTITY: the node label, and nothing else.
              //
              // The source's own name is deliberately NOT here. It is chosen by
              // whoever wrote the source, so showing it in the most prominent
              // position of the user's source list would hand a third party
              // control of SPECTA's UI and leak a streaming-site name onto a
              // screen the owner reads every day. It lives in the details sheet.
              Flexible(
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
              const SizedBox(width: 8),
              // Health sits on the identity row because it describes the source,
              // not the controls. The `Flexible` above guarantees the badge is
              // never pushed off the edge by a long label.
              Flexible(child: _HealthBadge(extension: extension)),
              // Long-press drag handle. `buildDefaultDragHandles` is off so
              // only this handle starts a drag, leaving taps on the rest of the
              // card working normally.
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 20,
                    color: SpectaColors.textMuted,
                  ),
                ),
              ),
              // Secondary actions live in an overflow menu. Compact does not
              // mean cramming: update, restore, details and remove are all
              // still reachable, one tap deeper, and the card stays two rows.
              //
              // The explicit constraints matter: a PopupMenuButton defaults to
              // a 48 px target, which alone would have kept the identity row
              // as tall as the old card's whole first row. 36 px stays well
              // above the accessible minimum.
              _CardOverflowMenu(
                extension: extension,
                updateVersion: updateVersion,
                canRollback: canRollback,
                busy: busy,
                onDetails: () => _showDetails(context, extension),
                onUpdate: onUpdate,
                onRollback: onRollback,
                onUninstall: onUninstall,
              ),
            ],
          ),
          const SizedBox(height: 2),
          // ROW 2 - ordering and the on/off switch.
          Row(
            children: <Widget>[
              // Reorder controls. Buttons rather than drag-only, so reordering
              // is reachable with a D-pad on a TV and with a screen reader.
              // The first card has no "up" and the last no "down"; Node 0 is
              // NOT exempt from either.
              _MoveButton(
                icon: Icons.keyboard_arrow_up_rounded,
                tooltip: 'Move up',
                onPressed: (busy || onMoveUp == null) ? null : onMoveUp,
              ),
              _MoveButton(
                icon: Icons.keyboard_arrow_down_rounded,
                tooltip: 'Move down',
                onPressed: (busy || onMoveDown == null) ? null : onMoveDown,
              ),
              const SizedBox(width: 4),
              // OFF is not DELETE. The switch disables a source without removing
              // it, without deleting its file and without changing its place in
              // the user's ordering.
              Text(
                extension.enabled ? 'Enabled' : 'Disabled',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: extension.enabled
                      ? SpectaColors.textSecondary
                      : SpectaColors.textMuted,
                ),
              ),
              const Spacer(),
              // A full-size Switch is ~48 px tall and was the tallest thing in
              // the old card. Wrapping it in a FittedBox scales the painted
              // switch down while the surrounding 48 px box keeps the real tap
              // target intact, so it stays easy to hit on a phone.
              SizedBox(
                height: 40,
                width: 52,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Switch(
                    value: extension.enabled,
                    onChanged: busy ? null : onToggle,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A reorder arrow that is visually tight but keeps a real tap target.
///
/// A stock `IconButton` carries default padding and a 48 px minimum height,
/// which is what made the card tall. Pinning `visualDensity` to compact and the
/// constraints to 34 px removes the dead space around the glyph while staying
/// comfortably above the 24 px accessible minimum, and keeping the tooltip so
/// the control stays labelled for a screen reader.
class _MoveButton extends StatelessWidget {
  const _MoveButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      color: SpectaColors.textSecondary,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    );
  }
}

/// Trailing overflow menu for a node card's secondary actions.
///
/// Holds everything that is real but not frequent: details, update, restore and
/// remove. Keeping these out of the two visible rows is what allows the card to
/// stay compact without removing any capability.
///
/// Node 0's remove entry is shown but DISABLED, with the reason in the label,
/// rather than hidden: silently dropping the affordance would leave the user
/// wondering where it went.
class _CardOverflowMenu extends StatelessWidget {
  const _CardOverflowMenu({
    required this.extension,
    required this.updateVersion,
    required this.canRollback,
    required this.busy,
    required this.onDetails,
    required this.onUpdate,
    required this.onRollback,
    required this.onUninstall,
  });

  final ManagedExtension extension;
  final String? updateVersion;
  final bool canRollback;
  final bool busy;
  final VoidCallback onDetails;
  final VoidCallback? onUpdate;
  final VoidCallback? onRollback;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    final bool locked = extension.nodeLocked;
    return PopupMenuButton<String>(
      // A generic "more" glyph names no provider and no site, matching the rest
      // of this surface.
      icon: const Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: SpectaColors.textSecondary,
      ),
      // A stock PopupMenuButton is a 48 px target, which would make the card's
      // identity row as tall as it was before. 36 px keeps it comfortable to
      // tap while letting the card shrink.
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      tooltip: 'More actions for ${extension.nodeLabel ?? 'this source'}',
      onSelected: (String value) {
        switch (value) {
          case 'details':
            onDetails();
          case 'update':
            onUpdate?.call();
          case 'rollback':
            onRollback?.call();
          case 'uninstall':
            onUninstall();
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'details',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.info_outline_rounded, size: 20),
            title: Text('Details'),
          ),
        ),
        if (updateVersion != null)
          PopupMenuItem<String>(
            value: 'update',
            enabled: !busy,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.system_update_rounded, size: 20),
              title: Text('Update to $updateVersion'),
            ),
          ),
        if (canRollback)
          PopupMenuItem<String>(
            value: 'rollback',
            enabled: !busy,
            child: const ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.history_rounded, size: 20),
              title: Text('Restore previous version'),
            ),
          ),
        PopupMenuItem<String>(
          value: 'uninstall',
          enabled: !busy && !locked,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              locked
                  ? Icons.lock_outline_rounded
                  : Icons.delete_outline_rounded,
              size: 20,
              color: locked ? SpectaColors.textMuted : SpectaColors.failure,
            ),
            title: Text(
              locked
                  ? '${extension.nodeLabel} is the core source and cannot be '
                        'removed'
                  : 'Remove source',
              style: TextStyle(
                color: locked
                    ? SpectaColors.textMuted
                    : SpectaColors.failure,
              ),
            ),
          ),
        ),
      ],
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
