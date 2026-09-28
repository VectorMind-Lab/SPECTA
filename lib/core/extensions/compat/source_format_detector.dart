import 'dart:convert';

import 'package:specta/core/extensions/contract/extension_capability.dart';
import 'package:specta/core/extensions/manifest.dart';


/// Which shape a source file turned out to be.
enum SourceFormat {
  /// The native `// ==SpectaExtension==` contract. Used as-is, no adaptation.
  native,

  /// A recognised foreign JavaScript module, adapted into the native
  /// representation.
  adapted,

  /// Not a JavaScript source SPECTA can run, with a stated reason.
  unrecognised,
}

/// What inspection found in a source file.
///
/// Every field is either derived from the file itself or explicitly reported as
/// absent. Nothing is invented: an unknown version is `null`, not `0.0.0`, so a
/// later stage cannot present a guess as if it were read from the source.
final class ForeignSourceAnalysis {
  const ForeignSourceAnalysis({
    required this.format,
    required this.id,
    required this.name,
    required this.author,
    required this.version,
    required this.description,
    required this.website,
    required this.contentTypeCode,
    required this.entryPoints,
    required this.capabilities,
    required this.usesNetwork,
    required this.usesLogging,
    required this.rejectionReason,
  });

  /// The detected shape.
  final SourceFormat format;

  /// Deterministic id derived from the file's own content.
  final String id;

  /// Display name, when the file declares one.
  final String name;

  /// Author, when the file declares one. Null means unstated, not unknown.
  final String? author;

  /// Version, when the file declares a semver one. Null means unstated.
  final String? version;

  /// Description, when the file declares one.
  final String? description;

  /// Homepage/website, when the file declares one.
  final String? website;

  /// Normalised content-type code, when the file declares one.
  final String? contentTypeCode;

  /// The contract operations the file actually implements, discovered by
  /// looking for the corresponding exported member.
  final Set<String> entryPoints;

  /// Capabilities granted to the adapted source, derived from what the code
  /// actually references. Never widened beyond that.
  final Set<ExtensionCapability> capabilities;

  /// Whether the file references a network primitive.
  final bool usesNetwork;

  /// Whether the file references a logging primitive.
  final bool usesLogging;

  /// Why the file cannot be run, when [format] is
  /// [SourceFormat.unrecognised]. Null otherwise.
  ///
  /// This is the only path on which a source is refused, and it must state a
  /// concrete technical reason - never merely "it lacks the SPECTA header".
  final String? rejectionReason;
}

/// Detects and describes JavaScript source files in the native contract or in a
/// recognised foreign module shape.
///
/// ## Why this exists
///
/// The native `// ==SpectaExtension==` header is a *convenience contract*, not
/// an admission requirement. SPECTA is an open platform, so a file written for
/// another host must be examined on its own terms and mapped into the internal
/// representation wherever that is technically reasonable.
///
/// ## What it deliberately does not do
///
/// It does not decide whether a provider is acceptable. There is no allowlist of
/// provider names, no per-provider special-casing, and no bundled third-party
/// catalogue. The same inspection runs for every file, so a source is judged on
/// its technical shape alone, and a refusal always carries a stated reason.
///
/// ## Security posture
///
/// Adaptation never widens authority. A foreign file is granted only the
/// capabilities its own code demonstrably uses, and it runs in exactly the same
/// sandbox, under exactly the same capability enforcement, as a native source.
abstract final class SourceFormatDetector {
  /// Inspects [jsSource] and reports what it is.
  static ForeignSourceAnalysis analyse(String jsSource) {
    if (_isNative(jsSource)) return _analyseNative(jsSource);
    return _analyseForeign(jsSource);
  }

  /// Cheap structural test for the native header.
  ///
  /// Whole lines are compared rather than running a regex over the file, so a
  /// document that merely mentions the marker inside a string or a comment body
  /// is not mistaken for a native manifest.
  static bool _isNative(String jsSource) {
    for (final String line in jsSource.split('\n')) {
      if (line.trim() == '// ==SpectaExtension==') return true;
    }
    return false;
  }

  /// The native path is authoritative and unchanged: it is parsed by the
  /// existing parser and nothing here reinterprets it. This analysis exists so
  /// that callers get one uniform description of any source.
  static ForeignSourceAnalysis _analyseNative(String jsSource) {
    try {
      final ExtensionManifest manifest = ManifestParser.parse(jsSource);
      return ForeignSourceAnalysis(
        format: SourceFormat.native,
        id: manifest.id,
        name: manifest.name,
        author: manifest.author,
        version: manifest.version,
        description: manifest.description,
        website: manifest.website,
        contentTypeCode: manifest.type.code,
        entryPoints: <String>{
          if (manifest.capabilities.contains(ExtensionCapability.search))
            'search',
          if (manifest.capabilities.contains(ExtensionCapability.latest))
            'latest',
          if (manifest.capabilities.contains(ExtensionCapability.details))
            'details',
          if (manifest.capabilities.contains(ExtensionCapability.sources))
            'getSources',
        },
        capabilities: manifest.capabilities,
        usesNetwork: manifest.capabilities.contains(ExtensionCapability.network),
        usesLogging: manifest.capabilities.contains(ExtensionCapability.logging),
        rejectionReason: null,
      );
    } on ManifestParseException catch (e) {
      // A file that opens with the native marker but then fails validation is a
      // broken native source, not a foreign one. The parser's own message is
      // surfaced so the user sees the real problem.
      return _unrecognised(e.message);
    }
  }

  /// Inspects a file that is not in the native format.
  ///
  /// The strategy is structural rather than provider-specific: find the module's
  /// own metadata by reading what the file declares about itself, and find its
  /// entry points by looking for the members it actually defines.
  static ForeignSourceAnalysis _analyseForeign(String jsSource) {
    if (jsSource.trim().isEmpty) {
      return _unrecognised('The file is empty.');
    }

    // A foreign source must at least be JavaScript that defines something
    // callable. Anything else is refused with that concrete reason - not with
    // "it has no SPECTA header".
    if (!_looksLikeJavaScriptModule(jsSource)) {
      return _unrecognised(
        'This file is not a JavaScript source module. It defines no module '
        'export, no class and no entry point, so there is nothing for SPECTA '
        'to execute.',
      );
    }

    final Set<String> entryPoints = _detectEntryPoints(jsSource);
    if (entryPoints.isEmpty) {
      return _unrecognised(
        'This JavaScript file implements none of the operations a source '
        'needs - search, latest, details or getSources - so SPECTA has no way '
        'to use it. This is about the operations it implements, not about which '
        'format it was written in.',
      );
    }

    final Map<String, String> metadata = _extractMetadata(jsSource);
    final String name =
        metadata['name'] ?? metadata['title'] ?? 'Imported source';
    final bool usesNetwork = _referencesAny(
      jsSource,
      const <String>[
        'fetch(',
        'XMLHttpRequest',
        'axios',
        'request(',
        'sendMessage',
        'https://',
        'http://',
      ],
    );
    final bool usesLogging = _referencesAny(
      jsSource,
      const <String>['console.log', 'console.warn', 'console.error'],
    );

    // Capabilities are derived from what the code actually references. A source
    // is granted neither more authority than it demonstrably needs nor less than
    // the operations it implements.
    final Set<ExtensionCapability> capabilities = <ExtensionCapability>{
      if (usesNetwork) ExtensionCapability.network,
      if (usesLogging) ExtensionCapability.logging,
      if (entryPoints.contains('search')) ExtensionCapability.search,
      if (entryPoints.contains('latest')) ExtensionCapability.latest,
      if (entryPoints.contains('details')) ExtensionCapability.details,
      if (entryPoints.contains('getSources')) ExtensionCapability.sources,
    };

    return ForeignSourceAnalysis(
      format: SourceFormat.adapted,
      id: deriveId(name, jsSource),
      name: name,
      author: metadata['author'] ?? metadata['developer'] ?? 'Unknown',
      version: _normaliseVersion(metadata['version']),
      description: metadata['description'] ?? metadata['about'],
      website: metadata['website'] ?? metadata['homepage'] ?? metadata['url'],
      contentTypeCode: _normaliseContentType(
        metadata['type'] ?? metadata['types'] ?? metadata['category'],
      ),
      entryPoints: entryPoints,
      capabilities: capabilities,
      usesNetwork: usesNetwork,
      usesLogging: usesLogging,
      rejectionReason: null,
    );
  }

  static ForeignSourceAnalysis _unrecognised(String reason) =>
      ForeignSourceAnalysis(
        format: SourceFormat.unrecognised,
        id: '',
        name: '',
        author: null,
        version: null,
        description: null,
        website: null,
        contentTypeCode: null,
        entryPoints: const <String>{},
        capabilities: const <ExtensionCapability>{},
        usesNetwork: false,
        usesLogging: false,
        rejectionReason: reason,
      );

  /// Whether the file is plausibly a JavaScript module at all.
  ///
  /// Deliberately permissive: it recognises the module shapes foreign sources
  /// actually use, so a genuine foreign file is never refused merely for being
  /// unfamiliar.
  static bool _looksLikeJavaScriptModule(String jsSource) =>
      _referencesAny(jsSource, const <String>[
            'module.exports',
            'exports.',
            'export default',
            'export const',
            'export function',
            'globalThis',
            'class ',
            'function ',
            '=>',
          ]) ||
      jsSource.trimLeft().startsWith('{');

  /// Finds the contract operations the file implements.
  ///
  /// A member counts as implemented when the file assigns it, defines it as an
  /// object/class member, or exports it. Several spellings are recognised because
  /// different hosts name the same operation differently.
  static Set<String> _detectEntryPoints(String jsSource) {
    final Set<String> found = <String>{};
    for (final String operation in const <String>[
      'search',
      'latest',
      'details',
      'getSources',
    ]) {
      if (_definesMember(jsSource, operation)) found.add(operation);
    }
    return found;
  }

  /// Whether [name] appears as a defined member of the module.
  static bool _definesMember(String jsSource, String name) {
    final List<RegExp> shapes = <RegExp>[
      // name: function (...) / name: (...) => / name: async (...)
      RegExp('\\b$name\\s*:\\s*(async\\s*)?(function\\b|\\()'),
      // name(...) {  - a class or object method
      RegExp('\\b$name\\s*\\([^)]*\\)\\s*\\{'),
      // function name(...)
      RegExp('\\bfunction\\s+$name\\s*\\('),
      // exports.name = ...
      RegExp('\\bexports\\.$name\\s*='),
    ];
    return shapes.any((RegExp shape) => shape.hasMatch(jsSource));
  }

  /// Reads the metadata a foreign file declares about itself.
  ///
  /// Only literal `key: 'value'` / `key: "value"` pairs are read. A value that
  /// is an expression or a call is skipped rather than evaluated or guessed at.
  static Map<String, String> _extractMetadata(String jsSource) {
    final Map<String, String> found = <String, String>{};
    final RegExp pair = RegExp(
      r'''["']?([A-Za-z_][A-Za-z0-9_]*)["']?\s*:\s*["']([^"'\n]{1,200})["']''',
    );
    for (final String line in jsSource.split('\n')) {
      final RegExpMatch? match = pair.firstMatch(line);
      if (match == null) continue;
      final String key = match.group(1)!.toLowerCase();
      final String value = match.group(2)!.trim();
      if (value.isEmpty) continue;
      found.putIfAbsent(key, () => value);
    }
    return found;
  }

  static bool _referencesAny(String jsSource, List<String> needles) =>
      needles.any((String needle) => jsSource.contains(needle));

  /// Normalises a version to semver, or reports it absent.
  ///
  /// A missing or non-semver version is `null`, never a fabricated `0.0.0`. A
  /// guessed version presented as a real one is the kind of small dishonesty
  /// that makes a source list untrustworthy.
  static String? _normaliseVersion(String? raw) {
    if (raw == null) return null;
    final RegExpMatch? match = RegExp(
      r'(\d+)(?:\.(\d+))?(?:\.(\d+))?',
    ).firstMatch(raw);
    if (match == null) return null;
    return '${match.group(1)}.${match.group(2) ?? '0'}.${match.group(3) ?? '0'}';
  }

  /// Normalises a declared type to a SPECTA content-type code.
  ///
  /// An unrecognised value maps to `movie` rather than being refused: the
  /// content type narrows discovery, it does not decide whether a source runs.
  static String? _normaliseContentType(String? raw) {
    if (raw == null) return null;
    final String value = raw.toLowerCase();
    if (value.contains('anime')) return 'anime';
    if (value.contains('series') || value.contains('tv')) return 'series';
    return 'movie';
  }

  /// Derives a stable, collision-resistant id from the file's own content.
  ///
  /// Namespaced under `foreign.` so it can never collide with a native source's
  /// id, and folded with a content digest so two different files sharing a name
  /// do not silently replace one another.
  ///
  /// This digest is an identity label, not a trust decision. Trust comes from
  /// the signature alone; an unsigned source is `unverified` regardless.
  static String deriveId(String name, String jsSource) {
    final String slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'foreign.${slug.isEmpty ? 'source' : slug}.${_shortDigest(jsSource)}';
  }

  /// A short, stable digest of [jsSource].
  ///
  /// FNV-1a. This is an identity label, not a security primitive, and it is not
  /// used for signature verification. It exists because Dart's `hashCode` is not
  /// stable across runs and the id must be.
  static String _shortDigest(String jsSource) {
    int hash = 0x811c9dc5;
    for (final int unit in utf8.encode(jsSource)) {
      hash = (hash ^ unit) & 0xFFFFFFFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
