import 'package:specta/core/extensions/catalogue/extension_type.dart';
import 'package:specta/core/extensions/contract/extension_capability.dart';
import 'package:specta/core/extensions/verification/signing_protocol.dart';

/// SPECTA extension API versions supported by this build of the application.
///
/// Extensions declare an `@apiVersion` in their manifest.  An extension whose
/// API version is not in [supported] is rejected with a controlled
/// [ExtensionFailureType.unsupported] error before it is ever executed.
abstract final class SpectaApiVersion {
  /// The current extension contract version this build implements.
  static const int current = 2;

  /// Set of API major versions this build can run.
  static const Set<int> supported = <int>{current};

  /// Returns true when [version] is supported by this build.
  static bool isCompatible(int version) => supported.contains(version);
}

/// Strongly typed extension manifest parsed from the `// ==SpectaExtension==`
/// header block at the top of an extension `.js` file.
///
/// Required fields:
///   id, name, version, author, apiVersion, type
///
/// Optional metadata:
///   signature, capabilities, description, lang, icon, website
///
/// `signature` is required for Official classification but may be null
/// (which yields TrustLevel.unverified).
///
/// `capabilities` defaults to the empty set: an extension that declares nothing
/// is granted nothing. See [ExtensionCapability].
final class ExtensionManifest {
  ExtensionManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.author,
    required this.apiVersion,
    required this.type,
    required this.signature,
    this.capabilities = const <ExtensionCapability>{},
    this.description,
    this.language,
    this.icon,
    this.website,
  });

  /// Unique identifier for the extension (e.g. `com.example.test`).
  final String id;

  /// Human-readable display name.
  final String name;

  /// Semantic version string (e.g. `1.0.0`).
  final String version;

  /// Author name.
  final String author;

  /// Extension contract API major version declared by the extension.
  final int apiVersion;

  /// Content type the extension provides.
  final ExtensionContentType type;

  /// Raw signature string from the manifest (e.g. `ed25519:MEU...`).
  /// May be null for unsigned extensions.
  final String? signature;

  /// Capabilities the extension declared in `// @capabilities`.
  ///
  /// Empty means none; the runtime grants nothing by default.
  final Set<ExtensionCapability> capabilities;

  /// Optional human-readable description.
  final String? description;

  /// Optional language code (e.g. `en`).
  final String? language;

  /// Optional icon URL.
  final String? icon;

  /// Optional website URL.
  final String? website;

  /// Whether this build of SPECTA supports the manifest's API version.
  bool get isApiCompatible => SpectaApiVersion.isCompatible(apiVersion);

  /// Whether the manifest carries a signature (pre-requisite for Official).
  bool get hasSignature => signature != null && signature!.isNotEmpty;

  /// Whether the extension declared [capability].
  bool hasCapability(ExtensionCapability capability) =>
      capabilities.contains(capability);

  /// The manifest fields that participate in the signed payload.
  ///
  /// The `signature` field itself is excluded (a signature cannot sign itself).
  /// `capabilities` IS included: what an extension is permitted to do must not
  /// be editable without invalidating its signature.
  Map<String, dynamic> signedMetadata() => <String, dynamic>{
    'apiVersion': apiVersion,
    'author': author,
    if (capabilities.isNotEmpty)
      'capabilities': ExtensionCapability.encodeDeclaration(capabilities),
    'id': id,
    'name': name,
    'type': type.code,
    'version': version,
    if (description != null) 'description': description,
    if (language != null) 'lang': language,
    if (icon != null) 'icon': icon,
    if (website != null) 'website': website,
  };

  /// Canonical, deterministic JSON of [signedMetadata].
  ///
  /// This is the metadata half of the signed payload — an intermediate value,
  /// not the payload itself. [buildSignedPayload] produces the bytes that are
  /// actually signed.
  String canonicalMetadataJson() =>
      SpectaSigningProtocol.canonicalMetadataJson(signedMetadata());

  /// The exact bytes a SPECTA signature covers, per
  /// [SpectaSigningProtocol]: canonical metadata JSON plus the extension's
  /// JavaScript body, both UTF-8, both length-prefixed.
  ///
  /// [extensionBody] is the source after the manifest header block, as returned
  /// by [ManifestParser.extractBody].
  List<int> buildSignedPayload({required String extensionBody}) =>
      SpectaSigningProtocol.buildPayload(
        metadata: signedMetadata(),
        extensionBody: extensionBody,
      );

  /// Full human-readable representation for diagnostics.
  @override
  String toString() =>
      'ExtensionManifest(id: $id, name: $name, version: $version, '
      'apiVersion: $apiVersion, trust: ${hasSignature ? "signed" : "unsigned"})';
}

/// Parses the `// ==SpectaExtension==` userscript-style header from extension
/// JavaScript source.
final class ManifestParser {
  ManifestParser._();

  static const String _startMarker = '// ==SpectaExtension==';
  static const String _endMarker = '// ==/SpectaExtension==';
  static const String _fieldPrefix = '// @';

  /// Extracts the raw key/value pairs from the manifest header block.
  ///
  /// Returns an empty map if no header block is present.
  static Map<String, String> extractHeader(String jsSource) {
    final List<String> lines = jsSource.split('\n');
    final List<String> headerLines = <String>[];
    bool inHeader = false;

    for (final String line in lines) {
      if (line.trim() == _startMarker) {
        inHeader = true;
        continue;
      }
      if (line.trim() == _endMarker) {
        inHeader = false;
        continue;
      }
      if (inHeader) {
        headerLines.add(line);
      }
    }

    final Map<String, String> fields = <String, String>{};
    for (final String line in headerLines) {
      final String trimmed = line.trim();
      if (!trimmed.startsWith(_fieldPrefix)) continue;

      final String content = trimmed.substring(_fieldPrefix.length);
      final int spaceIndex = content.indexOf(' ');
      if (spaceIndex == -1) continue;

      final String key = content.substring(0, spaceIndex).trim();
      final String value = content.substring(spaceIndex + 1).trim();
      if (key.isNotEmpty) {
        fields[key] = value;
      }
    }
    return fields;
  }

  /// Parses [jsSource] into a validated [ExtensionManifest].
  ///
  /// Throws [ManifestParseException] when required fields are missing or
  /// invalid.
  static ExtensionManifest parse(String jsSource) {
    final Map<String, String> fields = extractHeader(jsSource);

    final ManifestValidator validator = ManifestValidator(fields);

    return ExtensionManifest(
      id: validator.require('id'),
      name: validator.require('name'),
      version: validator.require('version'),
      author: validator.require('author'),
      apiVersion: validator.requireInt('apiVersion'),
      type: validator.requireContentType('type'),
      signature: validator.optional('signature'),
      capabilities: validator.optionalCapabilities('capabilities'),
      description: validator.optional('description'),
      language: validator.optional('lang'),
      icon: validator.optional('icon'),
      website: validator.optional('website'),
    );
  }

  /// Extracts the extension's JavaScript body: everything after the line that
  /// closes the manifest header block.
  ///
  /// This is the executable half of the signed payload, so the rule is stated
  /// in exactly one place and is byte-stable: the body begins immediately after
  /// the newline terminating the closing marker line, with no trimming. It uses
  /// the same line-matching rule as the header parser (a line whose trimmed
  /// content equals the marker), so the two can never disagree about where the
  /// header ends. If the source has no closing marker at all, the whole source
  /// is treated as the body; such a file fails manifest validation before that
  /// matters.
  static String extractBody(String jsSource) {
    final List<String> lines = jsSource.split('\n');
    int offset = 0;
    for (final String line in lines) {
      final int nextOffset = offset + line.length + 1;
      if (line.trim() == _endMarker) {
        return nextOffset <= jsSource.length
            ? jsSource.substring(nextOffset)
            : '';
      }
      offset = nextOffset;
    }
    return jsSource;
  }
}

/// Validates raw manifest header fields and produces descriptive errors.
final class ManifestValidator {
  ManifestValidator(this._fields);

  final Map<String, String> _fields;

  String require(String key) {
    final String? value = _fields[key];
    if (value == null || value.isEmpty) {
      throw ManifestParseException('Missing required field: $key');
    }
    return value;
  }

  int requireInt(String key) {
    final String value = require(key);
    final int? parsed = int.tryParse(value);
    if (parsed == null) {
      throw ManifestParseException('Field $key is not a valid integer: $value');
    }
    if (parsed <= 0) {
      throw ManifestParseException(
        'Field $key must be a positive integer, got: $parsed',
      );
    }
    return parsed;
  }

  ExtensionContentType requireContentType(String key) {
    final String rawValue = require(key);
    // Accept both the long-form code (movies_series) and comma-separated
    // short-form tokens (movies,series).
    final ExtensionContentType? resolved =
        ExtensionContentType.fromCode(rawValue) ??
        ExtensionContentType.fromManifestType(rawValue);

    if (resolved == null) {
      throw ManifestParseException(
        'Unsupported content type "$rawValue". SPECTA Phase 1 supports '
        'movie, series, and movies_series.',
      );
    }
    return resolved;
  }

  String? optional(String key) {
    final String? value = _fields[key];
    if (value == null || value.isEmpty) return null;
    return value;
  }

  /// Parses the optional `capabilities` declaration.
  ///
  /// Absent or blank means "no capabilities". A declaration naming anything
  /// SPECTA does not implement is an error rather than a silent subset: an
  /// extension must not appear to hold permissions it was not granted, and a
  /// typo must not quietly downgrade it.
  Set<ExtensionCapability> optionalCapabilities(String key) {
    final String? value = optional(key);
    if (value == null) return const <ExtensionCapability>{};

    final Set<ExtensionCapability>? parsed =
        ExtensionCapability.parseDeclaration(value);
    if (parsed == null) {
      throw ManifestParseException(
        'Unsupported capability in "$value". Supported capabilities: '
        '${ExtensionCapability.values.map((ExtensionCapability c) => c.code).join(', ')}.',
      );
    }
    return parsed;
  }
}

/// Thrown when a manifest is missing required fields or has invalid values.
final class ManifestParseException implements Exception {
  ManifestParseException(this.message);

  final String message;

  @override
  String toString() => 'ManifestParseException: $message';
}
