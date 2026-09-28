import 'package:flutter/material.dart';

import '../../app/theme/specta_colors.dart';

/// The app-developer mark: a small green dot, and nothing else.
///
/// ## What makes an extension qualify
///
/// Exactly one thing: a PROVEN [TrustLevel.official]. That requires a valid
/// Ed25519 signature over the manifest, verified against SPECTA's published
/// public key (`ExtensionManager._classifyTrust`, or
/// `lib/core/extensions/verification/signing_protocol.dart` for the scheme).
///
/// Nothing weaker may ever switch this on:
///
/// * **not** an id allowlist — an id is a string the extension chooses for
///   itself, so any extension could claim a listed one;
/// * **not** a repository listing — a catalogue carries no signature by design,
///   so being listed grants nothing;
/// * **not** the download host — GitHub is distribution, not identity.
///
/// A trust mark that an extension can award itself is worse than no mark at
/// all, because it teaches the user a lie. If a future change makes this widget
/// reachable without a verified signature, the change is wrong.
///
/// ## Why it is silent
///
/// The mark carries no label, no tooltip and no semantics announcement: it is
/// deliberately excluded from the accessibility tree with [ExcludeSemantics].
/// It is a private signal, not an explanation, and inventing explanatory copy
/// would defeat the point. Anything that needs explaining belongs in the
/// existing trust badge instead.
class SpectaDeveloperDot extends StatelessWidget {
  const SpectaDeveloperDot({super.key, this.size = 7});

  /// Diameter of the dot in logical pixels. Small by design.
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          // The existing success colour — no new palette entry is introduced
          // for a seven-pixel dot.
          color: SpectaColors.success,
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: SpectaColors.success.withValues(alpha: 0.55),
              blurRadius: 5,
              spreadRadius: 0.5,
            ),
          ],
        ),
      ),
    );
  }
}
