import 'package:flutter/material.dart';

/// Wraps a widget with Android TV / D-pad focus support and visual feedback.
///
/// Shows a prominent border on focus to ensure visibility from 10ft couch distance.
class SpectaFocusWrapper extends StatefulWidget {
  const SpectaFocusWrapper({
    required this.child,
    super.key,
    this.onTap,
    this.borderRadius = 12,
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double borderRadius;
  final bool autofocus;

  @override
  State<SpectaFocusWrapper> createState() => _SpectaFocusWrapperState();
}

class _SpectaFocusWrapperState extends State<SpectaFocusWrapper> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (bool focused) {
        setState(() => _isFocused = focused);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: _isFocused ? accent : Colors.transparent,
              width: _isFocused ? 2.5 : 0,
            ),
            boxShadow: _isFocused
                ? <BoxShadow>[
                    BoxShadow(
                      color: accent.withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
