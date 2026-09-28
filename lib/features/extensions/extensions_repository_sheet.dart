/// Browser for a USER-SUPPLIED repository index (requirement D).
///
/// Reads the hierarchy the Sources area is organised around:
///
/// ```text
/// Sources
///   -> Repository   (the link the user supplied, named from the document)
///     -> Provider  (one card per listed extension, with its real state)
/// ```
///
/// Everything shown is real data taken from the index and from what is already
/// installed. Nothing is invented: there are no fake counts, no placeholder
/// providers, and no status that SPECTA does not actually track.
///
/// Two deliberate restraints:
/// * Listing is not trust. The header says so, and every Install button routes
///   to the same `installCatalogueEntry` the official catalogue uses, which
///   converges on `ExtensionManager`.
/// * Entries the reader refused (not JavaScript, or malformed) are reported as
///   a COUNT with the reason, rather than hidden or rendered as a broken
///   install button.
library;

import 'package:flutter/material.dart';
import 'package:specta/app/theme/specta_colors.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/catalogue/extension_catalogue.dart';
import 'package:specta/core/extensions/catalogue/extension_catalogue_client.dart';
import 'package:specta/core/extensions/catalogue/extension_repository_index.dart';
import 'package:specta/ui/widgets/specta_button.dart';
import 'package:specta/ui/widgets/specta_empty_state.dart';

class ExtensionsRepositorySheet extends StatefulWidget {
  const ExtensionsRepositorySheet({
    required this.client,
    required this.indexUrl,
    required this.installed,
    super.key,
  });

  final ExtensionCatalogueClient client;

  /// The repository link the user supplied.
  final String indexUrl;

  /// Already-installed id -> installed version, used to label updates.
  final Map<String, String> installed;

  @override
  State<ExtensionsRepositorySheet> createState() =>
      _ExtensionsRepositorySheetState();
}

class _ExtensionsRepositorySheetState extends State<ExtensionsRepositorySheet> {
  late Future<SpectaResult<ExtensionRepositoryIndex>> _future = _load();

  Future<SpectaResult<ExtensionRepositoryIndex>> _load({bool refresh = false}) {
    return widget.client.loadRepositoryIndex(widget.indexUrl);
  }

  void _retry() {
    setState(() => _future = _load(refresh: true));
  }

  /// The host the repository was read from. This is a web host, never a
  /// filesystem path — requirement: no `/sdcard/...` style location is shown.
  String get _host {
    final Uri? uri = Uri.tryParse(widget.indexUrl.trim());
    return uri?.host.isNotEmpty == true ? uri!.host : 'the supplied link';
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
                    'Repository',
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
                  tooltip: 'Reload the repository',
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'From $_host',
              style: const TextStyle(
                fontSize: 12,
                color: SpectaColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Listing is not trust. Every provider is downloaded and verified '
              'before it can run.',
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
    return FutureBuilder<SpectaResult<ExtensionRepositoryIndex>>(
      future: _future,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<SpectaResult<ExtensionRepositoryIndex>> snapshot,
          ) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final SpectaResult<ExtensionRepositoryIndex> result =
                snapshot.data!;
            if (result.isErr) {
              return SpectaEmptyState(
                icon: Icons.cloud_off_rounded,
                message: result.failureOrNull!.message,
                actionLabel: 'Try again',
                action: _retry,
              );
            }

            final ExtensionRepositoryIndex index = result.valueOrNull!;
            return ListView(
              shrinkWrap: true,
              children: <Widget>[
                if (index.name != null) ...<Widget>[
                  Text(
                    index.name!,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: SpectaColors.textPrimary,
                    ),
                  ),
                  if (index.description != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        index.description!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: SpectaColors.textMuted,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                ],
                // Real counts only: what the reader accepted, and what it
                // refused. A repository that lists 40 binary plugins and no
                // runnable providers must not look like 40 providers.
                Text(
                  '${index.entries.length} '
                  '${index.entries.length == 1 ? 'provider' : 'providers'}'
                  '${_skippedSuffix(index)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: SpectaColors.textMuted,
                  ),
                ),
                const SizedBox(height: 10),
                for (final ExtensionCatalogueEntry entry in index.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ProviderCard(
                      entry: entry,
                      installedVersion: widget.installed[entry.id],
                      onInstall: () => Navigator.of(context).pop(entry),
                    ),
                  ),
              ],
            );
          },
    );
  }

  /// Honest accounting of what the reader refused, when it refused anything.
  static String _skippedSuffix(ExtensionRepositoryIndex index) {
    final int total = index.skippedNotJavaScript + index.skippedUnusable;
    if (total == 0) return '';
    return ' · $total skipped';
  }
}

/// One provider, as the repository describes it, with the action SPECTA really
/// supports. No invented status, no invented counts.
class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
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
                    if (installedVersion != null) 'installed',
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
