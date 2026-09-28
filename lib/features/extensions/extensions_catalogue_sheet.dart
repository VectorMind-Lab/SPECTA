/// Official catalogue browser (Phase D6).
///
/// Lists advertised extensions and lets the user pick ONE. Nothing is ever
/// installed automatically. Every row is a catalogue CLAIM, and the sheet says
/// so plainly: listing is not trust, and the chosen entry still travels through
/// the full Extension Manager pipeline.
library;

import 'package:flutter/material.dart';
import 'package:specta/app/theme/specta_colors.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/catalogue/extension_catalogue.dart';
import 'package:specta/core/extensions/catalogue/extension_catalogue_client.dart';
import 'package:specta/ui/widgets/specta_button.dart';

class ExtensionsCatalogueSheet extends StatefulWidget {
  const ExtensionsCatalogueSheet({
    required this.client,
    required this.installed,
    super.key,
  });

  final ExtensionCatalogueClient client;

  /// Already-installed id -> installed version, used to label updates.
  final Map<String, String> installed;

  @override
  State<ExtensionsCatalogueSheet> createState() =>
      _ExtensionsCatalogueSheetState();
}

class _ExtensionsCatalogueSheetState extends State<ExtensionsCatalogueSheet> {
  late Future<SpectaResult<ExtensionCatalogue>> _future = _load();

  Future<SpectaResult<ExtensionCatalogue>> _load({bool refresh = false}) {
    return widget.client.load(
      OfficialExtensionCatalogue.defaultIndexUrl,
      forceRefresh: refresh,
    );
  }

  void _retry() {
    setState(() => _future = _load(refresh: true));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Official catalogue',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: SpectaColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Reload the catalogue',
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Listing is not trust. Every extension is downloaded and '
              'verified before it can run.',
              style: TextStyle(fontSize: 12, color: SpectaColors.textMuted),
            ),
            const SizedBox(height: 12),
            Flexible(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    return FutureBuilder<SpectaResult<ExtensionCatalogue>>(
      future: _future,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<SpectaResult<ExtensionCatalogue>> snapshot,
          ) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final SpectaResult<ExtensionCatalogue> result = snapshot.data!;
            if (result.isErr) {
              return _CatalogueMessage(
                message: result.failureOrNull!.message,
                actionLabel: 'Try again',
                onAction: _retry,
              );
            }
            final List<ExtensionCatalogueEntry> entries =
                result.valueOrNull!.supportedEntries;
            if (entries.isEmpty) {
              return const _CatalogueMessage(
                message: 'This catalogue lists no extensions yet.',
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              itemCount: entries.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) {
                final ExtensionCatalogueEntry entry = entries[index];
                return _CatalogueEntryTile(
                  entry: entry,
                  installedVersion: widget.installed[entry.id],
                  onInstall: () => Navigator.of(context).pop(entry),
                );
              },
            );
          },
    );
  }
}

class _CatalogueMessage extends StatelessWidget {
  const _CatalogueMessage({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.extension_off_rounded,
            color: SpectaColors.textMuted,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: SpectaColors.textMuted),
          ),
          if (actionLabel != null) ...<Widget>[
            const SizedBox(height: 12),
            SpectaSecondaryButton(
              label: actionLabel!,
              onPressed: onAction,
              fontSize: 13,
            ),
          ],
        ],
      ),
    );
  }
}

/// One catalogue entry: what the catalogue claims, and the single action.
class _CatalogueEntryTile extends StatelessWidget {
  const _CatalogueEntryTile({
    required this.entry,
    required this.installedVersion,
    required this.onInstall,
  });

  final ExtensionCatalogueEntry entry;
  final String? installedVersion;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final bool isUpdate =
        installedVersion != null &&
        isExtensionUpdateAvailable(
          installed: installedVersion!,
          candidate: entry.version,
        );
    final String actionLabel = installedVersion == null
        ? 'Install'
        : isUpdate
        ? 'Update'
        : 'Reinstall';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SpectaColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SpectaColors.outline),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  entry.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: SpectaColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  <String?>[
                    'v${entry.version}',
                    entry.author,
                    if (isUpdate) 'update from $installedVersion',
                  ].whereType<String>().join(' · '),
                  style: const TextStyle(
                    fontSize: 12,
                    color: SpectaColors.textMuted,
                  ),
                ),
                if (entry.description != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    entry.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: SpectaColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          SpectaSecondaryButton(
            label: actionLabel,
            onPressed: onInstall,
            fontSize: 13,
          ),
        ],
      ),
    );
  }
}
