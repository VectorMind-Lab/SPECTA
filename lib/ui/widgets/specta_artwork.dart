import 'package:flutter/material.dart';

import '../../app/theme/specta_colors.dart';

/// The single place SPECTA loads remote artwork (C4.6).
///
/// WIDGETS NEVER BUILD ARTWORK URLS. A widget receives an already-resolved URL
/// from the metadata abstraction and only decides how it is displayed, so a
/// provider's CDN shape (TMDB image paths, AniList covers, TVMaze posters,
/// extension-supplied art) is never hard-coded into presentation code.
///
/// Every artwork state is explicit and honest:
/// - a URL is present and loads  -> the image;
/// - a URL is present but fails -> the same neutral placeholder, never a broken
///   image glyph and never a crash;
/// - no URL at all              -> the same neutral placeholder.
///
/// The placeholder is intentionally identical for "no artwork" and "artwork
/// failed to load": SPECTA does not invent a title, and showing a different
/// failure image would imply something about the work that it does not know.
class SpectaArtwork extends StatelessWidget {
  const SpectaArtwork({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 8,
    this.fallbackIcon = Icons.image_outlined,
  });

  /// Absolute artwork URL, already resolved by the metadata layer, or null.
  final String? url;

  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final String? resolved = _clean(url);
    final Widget child = resolved == null
        ? _placeholder()
        : Image.network(
            resolved,
            width: width,
            height: height,
            fit: fit,
            // A failed load must look like "no artwork", not like an error the
            // viewer has to interpret.
            errorBuilder: (
              BuildContext context,
              Object error,
              StackTrace? stack,
            ) => _placeholder(),
            loadingBuilder: (
              BuildContext context,
              Widget child,
              ImageChunkEvent? progress,
            ) => progress == null ? child : _placeholder(),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: width,
        height: height,
        color: SpectaColors.surfaceElevated,
        child: child,
      ),
    );
  }

  Widget _placeholder() => SizedBox(
    width: width,
    height: height,
    child: Center(
      child: Icon(fallbackIcon, color: SpectaColors.textMuted, size: 24),
    ),
  );

  /// Blank and whitespace-only URLs are treated as absent, so a provider that
  /// sends `"poster_path": ""` renders the placeholder instead of a failed
  /// request.
  static String? _clean(String? value) {
    if (value == null) return null;
    final String trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return null;
    }
    return trimmed;
  }
}
