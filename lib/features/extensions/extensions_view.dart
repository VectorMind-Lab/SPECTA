import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/specta_colors.dart';
import '../../core/errors/specta_result.dart';
import '../../core/extensions/identity/extension_health.dart';
import '../../core/extensions/identity/trust_level.dart';
import '../../core/extensions/manager/extension_lifecycle_service.dart';
import '../../core/extensions/manager/extension_record.dart';
import '../../ui/widgets/specta_badge.dart';
import '../../ui/widgets/specta_button.dart';
import '../../ui/widgets/specta_card.dart';
import '../../ui/widgets/specta_empty_state.dart';
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
          onReload: () => ref.read(extensionsProvider.notifier).reload(),
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
            ExtensionsStatus.ready when state.items.isEmpty =>
              SpectaEmptyState(
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
                  onToggle: (bool enabled) => _setEnabled(
                    context,
                    ref,
                    state.items[index].id,
                    enabled,
                  ),
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
      builder: (BuildContext dialogContext) => const _InstallDialog(),
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.failureOrNull!.message)),
    );
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.failureOrNull!.message)),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.busy,
    required this.onInstall,
    required this.onReload,
  });

  final int count;
  final bool busy;
  final VoidCallback onInstall;
  final VoidCallback onReload;

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
          IconButton(
            onPressed: busy ? null : onReload,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload installed extensions',
          ),
          const SizedBox(width: 8),
          SpectaSecondaryButton(
            label: 'Install',
            icon: Icons.add_rounded,
            onPressed: busy ? null : onInstall,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            fontSize: 13,
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
  });

  final ManagedExtension extension;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    return SpectaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
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
              _TrustBadge(trust: extension.trustLevel),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            <String>[
              extension.version,
              extension.author,
            ].join('  ·  '),
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
/// SPECTA itself has no file picker dependency yet, so the path is typed. This
/// is honest about what exists: the dialog only gathers a path, and the manager
/// does all validation, verification and installation.
class _InstallDialog extends StatefulWidget {
  const _InstallDialog();

  @override
  State<_InstallDialog> createState() => _InstallDialogState();
}

class _InstallDialogState extends State<_InstallDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Install extension'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '/sdcard/Download/example.js',
              labelText: 'Extension file path',
            ),
            onSubmitted: (String value) =>
                Navigator.of(context).pop(value),
          ),
          const SizedBox(height: 10),
          const Text(
            'The file is parsed, validated and signature-checked before it is '
            'installed. A file that claims to be Official without a valid '
            'signature is installed as Unverified.',
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
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Install'),
        ),
      ],
    );
  }
}
