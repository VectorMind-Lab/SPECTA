import 'package:flutter/material.dart';
import 'package:specta/app/theme/specta_colors.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/extension_lifecycle_service.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/ui/widgets/specta_badge.dart';

/// The details behind a source's info button.
///
/// This is where the source's own name, author, id and version live. They are
/// real, useful facts — and they are the strings a third party chose. Moving
/// them here, one deliberate tap away, is what lets the card itself show only
/// `Node 0` / `Node 1` / `Node A` while nothing is hidden from the user.
///
/// The sheet's title is the NODE LABEL, not the name, so even the modal's
/// heading is name-free.
class ExtensionDetailsSheet extends StatelessWidget {
  const ExtensionDetailsSheet({required this.extension, super.key});

  final ManagedExtension extension;

  /// Shows the sheet as a modal bottom sheet.
  static Future<void> show(BuildContext context, ManagedExtension extension) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) =>
          ExtensionDetailsSheet(extension: extension),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ExtensionRecord record = extension.record;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    extension.nodeLabel ?? 'Node',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: SpectaColors.textPrimary,
                    ),
                  ),
                ),
                SpectaBadge(
                  label: extension.trustLevel == TrustLevel.official
                      ? 'Verified'
                      : 'Unverified',
                  textColor: extension.trustLevel == TrustLevel.official
                      ? SpectaColors.success
                      : SpectaColors.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              extension.trustLevel == TrustLevel.official
                  ? 'Signed by SPECTA. The green mark means who signed this '
                        'file — it is not a quality score.'
                  : 'Not signed by SPECTA. It runs with your permission and its '
                        'requests are still policy-checked.',
              style: const TextStyle(
                fontSize: 12,
                color: SpectaColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _DetailRow(label: 'Name', value: record.name),
            _DetailRow(label: 'Version', value: record.version),
            _DetailRow(label: 'Author', value: record.author),
            _DetailRow(label: 'Identifier', value: record.id),
            _DetailRow(label: 'State', value: record.enabled ? 'On' : 'Off'),
            _DetailRow(
              label: 'Node',
              value: extension.nodeLabel ?? 'unassigned',
            ),
            _DetailRow(
              label: 'Removable',
              value: extension.nodeLocked
                  ? 'No — this is the core source'
                  : 'Yes',
            ),
            _DetailRow(label: 'Content type', value: record.contentType),
            _DetailRow(label: 'API version', value: '${record.apiVersion}'),
            _DetailRow(
              label: 'Installed',
              value: _formatDate(record.installedAt),
            ),
            _DetailRow(label: 'Last updated', value: _formatDate(record.updatedAt)),
            const SizedBox(height: 8),
            // The storage location is deliberately NOT shown. An absolute
            // filesystem path has no meaning to the user, and §16 keeps
            // /sdcard/... out of the UI entirely.
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final DateTime local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: SpectaColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: SpectaColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
