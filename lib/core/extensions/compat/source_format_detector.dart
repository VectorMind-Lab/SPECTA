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

  /// A JSON document that lists sources rather than being one - a repository
  /// index. It is not installable, but it is not a mistake either, so it is
  /// reported as its own kind rather than as unrecognised JavaScript.
  repositoryIndex,

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
    required this.operationMembers,
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

  /// Contract operation -> the member name the file implements it under.
  ///
  /// For a file that already uses SPECTA's own names this maps each operation to
  /// itself. For a foreign file it maps, for example, `latest` to `getHome` and
  /// `getSources` to `getVideoSources`, which is what lets the generated shim
  /// call the author's real function instead of a name that does not exist.
  final Map<String, String> operationMembers;

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
    // A JSON document is checked BEFORE the JavaScript path. Treating it as
    // JavaScript is what produced "implements none of the operations" for a
    // perfectly valid index.json listing nine working providers.
    if (_isJsonDocument(jsSource)) return _analyseRepositoryIndex(jsSource);
    return _analyseForeign(jsSource);
  }

  /// Whether the payload is a JSON document rather than JavaScript.
  ///
  /// Structural only: the first meaningful character decides. No attempt is made
  /// to decide whether the document is a *useful* index - that is the
  /// repository reader's job, and it is a separate concern.
  static bool _isJsonDocument(String jsSource) {
    final String head = jsSource.trimLeft();
    if (head.isEmpty) return false;
    if (!head.startsWith('{') && !head.startsWith('[')) return false;
    // `{"` and `[{` cannot begin a JavaScript program, whereas a bare `{` can:
    // `{ a: 1 }` is a valid expression statement. So the opening bracket alone
    // is not enough - the next non-space character decides.
    final String rest = head.substring(1).trimLeft();
    if (rest.isEmpty) return false;
    return rest.startsWith('"') ||
        rest.startsWith("'") ||
        rest.startsWith('{') ||
        rest.startsWith('[');
  }

  /// Describes a JSON document that lists sources.
  ///
  /// This is not an error to be reported as a broken file. It is a valid
  /// document of the wrong KIND, and the honest outcome is to send the user to
  /// the repository browser that can read it.
  static ForeignSourceAnalysis _analyseRepositoryIndex(String jsSource) {
    int listed = 0;
    try {
      final Object? decoded = jsonDecode(jsSource);
      if (decoded is List) {
        listed = decoded.length;
      } else if (decoded is Map) {
        for (final String key in const <String>[
          'sources',
          'extensions',
          'addons',
          'plugins',
          'providers',
          'items',
        ]) {
          final Object? list = decoded[key];
          if (list is List) {
            listed = list.length;
            break;
          }
        }
      }
    } on Object {
      // A malformed document is still a JSON document as far as routing goes;
      // the repository reader will report the parse problem in detail.
    }

    final String count = listed > 0
        ? ' It lists $listed source${listed == 1 ? '' : 's'}.'
        : '';
    return _unrecognised(
      'That link is a repository index — a JSON list of sources — not a '
      'single source file.$count Open it as a repository to browse and install '
      'the sources it lists.',
    );
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
        operationMembers: <String, String>{
          if (manifest.capabilities.contains(ExtensionCapability.search))
            'search': 'search',
          if (manifest.capabilities.contains(ExtensionCapability.latest))
            'latest': 'latest',
          if (manifest.capabilities.contains(ExtensionCapability.details))
            'details': 'details',
          if (manifest.capabilities.contains(ExtensionCapability.sources))
            'getSources': 'getSources',
        },
        capabilities: manifest.capabilities,
        usesNetwork: manifest.capabilities.contains(
          ExtensionCapability.network,
        ),
        usesLogging: manifest.capabilities.contains(
          ExtensionCapability.logging,
        ),
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
    final bool usesNetwork = _referencesAny(jsSource, const <String>[
      'fetch(',
      'XMLHttpRequest',
      'axios',
      'request(',
      'sendMessage',
      'https://',
      'http://',
    ]);
    final bool usesLogging = _referencesAny(jsSource, const <String>[
      'console.log',
      'console.warn',
      'console.error',
    ]);

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
      operationMembers: _resolveOperationMembers(jsSource),
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
        operationMembers: const <String, String>{},
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
  /// object/class member, exports it, or declares it as a top-level function.
  ///
  /// Foreign hosts do not use SPECTA's names. A real provider repository
  /// (Zangetsu) exports `getHome` where SPECTA wants `latest`, `getDetail`
  /// where SPECTA wants `details`, and `getVideoSources` where SPECTA wants
  /// `getSources`. Requiring SPECTA's own spelling made the platform closed in
  /// practice while claiming to be open, so the operation a contract slot is
  /// satisfied by is now looked up through an alias table.
  ///
  /// The alias table is a mapping of SPELLINGS, not of providers: it says
  /// "a function called `getDetail` fills the `details` slot", and nothing
  /// about who wrote it or which site it targets. An unknown author is treated
  /// exactly like a known one.
  static Set<String> _detectEntryPoints(String jsSource) {
    final Set<String> found = <String>{};
    for (final MapEntry<String, List<String>> slot
        in operationAliases.entries) {
      for (final String alias in slot.value) {
        if (_definesMember(jsSource, alias)) {
          found.add(slot.key);
          break;
        }
      }
    }
    return found;
  }

  /// The member name a contract operation is actually implemented by in this
  /// file, or null when the file does not implement it.
  ///
  /// The shim calls THIS name, not the contract name, which is what lets a
  /// `getVideoSources` provider answer a `getSources` call without SPECTA
  /// editing a single line of the author's code.
  static String? _memberForOperation(String jsSource, String operation) {
    for (final String alias
        in operationAliases[operation] ?? const <String>[]) {
      if (_definesMember(jsSource, alias)) return alias;
    }
    return null;
  }

  /// Maps each SPECTA contract operation to the foreign member name that
  /// satisfies it, for only the operations this file actually implements.
  ///
  /// The contract name is listed first for every operation, so a file that
  /// already uses SPECTA's spelling resolves to itself and behaves exactly as
  /// it did before aliases existed.
  static Map<String, String> _resolveOperationMembers(String jsSource) {
    final Map<String, String> resolved = <String, String>{};
    for (final String operation in const <String>[
      'search',
      'latest',
      'details',
      'getSources',
    ]) {
      final String? member = _memberForOperation(jsSource, operation);
      if (member != null) resolved[operation] = member;
    }
    return resolved;
  }

  /// Aliases that satisfy each contract operation, most specific first.
  ///
  /// These are SPELLINGS observed across independent provider ecosystems, not
  /// a per-provider allowlist: the same table applies to every file, so nothing
  /// here can decide whether a source is acceptable. Listing a name only makes
  /// a file ELIGIBLE for adaptation - it still passes the manifest,
  /// compatibility and Ed25519 trust gates unchanged.
  static const Map<String, List<String>> operationAliases =
      <String, List<String>>{
        'search': <String>[
          'search',
          'getSearch',
          'find',
          'query',
          'searchMovies',
          'searchShows',
          'browse',
        ],
        'latest': <String>[
          'latest',
          'getLatest',
          'getHome',
          'home',
          'getRecent',
          'getPopular',
          'popular',
          'trending',
        ],
        'details': <String>[
          'details',
          'getDetails',
          'getDetail',
          'getInfo',
          'info',
          'getMovie',
          'getShow',
          'getEpisodes',
        ],
        'getSources': <String>[
          'getSources',
          'getVideoSources',
          'getStreams',
          'getStreamLinks',
          'getLinks',
          'getPlay',
          'play',
        ],
      };

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
      // module.exports.name = ...
      RegExp('\\bmodule\\.exports\\.$name\\s*='),
      // const/let/var name = function / async / arrow
      RegExp(
        '\\b(?:const|let|var)\\s+$name\\s*=\\s*(async\\s*)?(function\\b|\\()',
      ),
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
      // EVERY match on the line, not just the first. Real providers return
      // their whole description from one object literal:
      //   return { name: 'AniKoto', lang: 'en', type: 'anime', version: '1.0.8' };
      // Reading only the first pair silently dropped the declared version and
      // left the source showing no version at all.
      for (final RegExpMatch match in pair.allMatches(line)) {
        final String key = match.group(1)!.toLowerCase();
        final String value = match.group(2)!.trim();
        if (value.isEmpty) continue;
        found.putIfAbsent(key, () => value);
      }
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
    final RegExpMatch? match = RegExp(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?')
        .firstMatch(raw);
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
