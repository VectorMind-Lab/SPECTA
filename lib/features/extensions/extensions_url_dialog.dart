/// "Install from a link" dialog (Phase D2).
///
/// HTTPS only, and stated plainly in the copy: an `http://` link is refused by
/// policy rather than silently upgraded. Raw GitHub URLs and any other public
/// HTTPS host are accepted, and no GitHub account or token is ever used.
library;

import 'package:flutter/material.dart';
import 'package:specta/app/theme/specta_colors.dart';
import 'package:specta/ui/widgets/specta_button.dart';

class UrlInstallDialog extends StatefulWidget {
  const UrlInstallDialog({
    super.key,
    this.title = 'Install from a link',
    this.fieldLabel = 'Source link',
    this.hint = 'https://.../source.js',
    this.actionLabel = 'Download',
    this.explanation =
        'Only https:// links are accepted. The file is '
        'downloaded, checked and verified exactly like one picked from this '
        'device. Being downloaded from anywhere does not make it trusted.',
  });

  final String title;
  final String fieldLabel;
  final String hint;
  final String actionLabel;
  final String explanation;

  @override
  State<UrlInstallDialog> createState() => _UrlInstallDialogState();
}

class _UrlInstallDialogState extends State<UrlInstallDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String value = _controller.text.trim();
    if (value.isEmpty) return;
    // The dialog reports only the URL. The download, manifest parsing,
    // compatibility check and trust classification all happen in the
    // notifier/manager, never here.
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            onSubmitted: (String _) => _submit(),
            decoration: InputDecoration(
              labelText: widget.fieldLabel,
              hintText: widget.hint,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.explanation,
            style: const TextStyle(fontSize: 12, color: SpectaColors.textMuted),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        SpectaPrimaryButton(label: widget.actionLabel, onPressed: _submit),
      ],
    );
  }
}
