import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/catalogue/extension_type.dart';
import 'package:specta/core/extensions/manifest.dart';

void main() {
  group('ManifestParser', () {
    test('parses a valid manifest with optional fields', () {
      final ExtensionManifest manifest = ManifestParser.parse(_validManifest);
      expect(manifest.id, 'com.example.test');
      expect(manifest.name, 'Test Extension');
      expect(manifest.version, '1.0.0');
      expect(manifest.author, 'Test Author');
      expect(manifest.apiVersion, 2);
      expect(manifest.type, ExtensionContentType.moviesSeries);
      expect(manifest.signature, 'ed25519:dGVzdA==');
      expect(manifest.description, 'A test extension');
      expect(manifest.language, 'en');
      expect(manifest.isApiCompatible, isTrue);
      expect(manifest.hasSignature, isTrue);
    });

    test('parses a manifest without optional fields', () {
      final ExtensionManifest manifest = ManifestParser.parse(_minimalManifest);
      expect(manifest.id, 'com.example.minimal');
      expect(manifest.signature, isNull);
      expect(manifest.hasSignature, isFalse);
    });

    test('throws on missing required field', () {
      expect(
        () => ManifestParser.parse(_manifestMissingField('author')),
        throwsA(isA<ManifestParseException>()),
      );
    });

    test('throws on missing apiVersion field', () {
      expect(
        () => ManifestParser.parse(_manifestMissingField('apiVersion')),
        throwsA(isA<ManifestParseException>()),
      );
    });

    test('throws on invalid apiVersion (non-integer)', () {
      expect(
        () => ManifestParser.parse(_manifestWithApiVersion('notanumber')),
        throwsA(isA<ManifestParseException>()),
      );
    });

    test('throws on apiVersion <= 0', () {
      expect(
        () => ManifestParser.parse(_manifestWithApiVersion('0')),
        throwsA(isA<ManifestParseException>()),
      );
    });

    test('unsupported API version is marked incompatible', () {
      final ExtensionManifest manifest = ManifestParser.parse(
        _manifestWithApiVersion('3'),
      );
      expect(manifest.isApiCompatible, isFalse);
      expect(manifest.apiVersion, 3);
    });

    test('accepts anime content type', () {
      final ExtensionManifest manifest = ManifestParser.parse(
        _manifestWithType('anime'),
      );
      expect(manifest.type, ExtensionContentType.anime);
    });

    test('parses an explicit anime contract revision', () {
      final ExtensionManifest manifest = ManifestParser.parse(_animeManifest);
      expect(manifest.type, ExtensionContentType.anime);
      expect(manifest.contractVersion, '2.1.0');
      expect(manifest.effectiveContractVersion, '2.1.0');
      expect(manifest.isCompatible, isTrue);
    });

    test('a legacy anime manifest without contractVersion is incompatible', () {
      final ExtensionManifest manifest = ManifestParser.parse(
        _manifestWithType('anime'),
      );
      expect(manifest.contractVersion, isNull);
      expect(manifest.effectiveContractVersion, '2.0.0');
      expect(manifest.isCompatible, isFalse);
    });

    test('parses comma-separated content type (movies,series)', () {
      final ExtensionManifest manifest = ManifestParser.parse(
        _manifestWithType('movies,series'),
      );
      expect(manifest.type, ExtensionContentType.moviesSeries);
    });

    test('parses single-token short-form content type (movie)', () {
      final ExtensionManifest manifest = ManifestParser.parse(
        _manifestWithType('movie'),
      );
      expect(manifest.type, ExtensionContentType.movie);
    });

    test('throws on a malformed contract revision', () {
      expect(
        () => ManifestParser.parse(_manifestWithContractVersion('2.1')),
        throwsA(isA<ManifestParseException>()),
      );
    });

    test('rejects an unsupported future contract revision', () {
      final ExtensionManifest manifest = ManifestParser.parse(
        _manifestWithContractVersion('2.9.0'),
      );
      expect(manifest.isCompatible, isFalse);
    });

    test('throws on malformed manifest (no header block)', () {
      expect(
        () => ManifestParser.parse('console.log("hello");'),
        throwsA(isA<ManifestParseException>()),
      );
    });

    test('canonicalMetadataJson is deterministic and order-independent', () {
      final ExtensionManifest manifest1 = ManifestParser.parse(
        _manifestWithType('movies_series'),
      );
      final ExtensionManifest manifest2 = ManifestParser.parse(
        _manifestWithReorderedFields,
      );
      expect(
        manifest1.canonicalMetadataJson(),
        manifest2.canonicalMetadataJson(),
      );
      expect(manifest1.canonicalMetadataJson(), contains('"apiVersion":2'));
    });

    test('extractHeader returns empty map when no header block', () {
      final Map<String, String> fields = ManifestParser.extractHeader(
        'var x = 1;',
      );
      expect(fields, isEmpty);
    });
  });
}

const String _manifestHeaderStart = '// ==SpectaExtension==';
const String _manifestHeaderEnd = '// ==/SpectaExtension==';

const String _validManifest =
    '$_manifestHeaderStart\n'
    '// @id com.example.test\n'
    '// @name Test Extension\n'
    '// @version 1.0.0\n'
    '// @author Test Author\n'
    '// @apiVersion 2\n'
    '// @type movies_series\n'
    '// @signature ed25519:dGVzdA==\n'
    '// @description A test extension\n'
    '// @lang en\n'
    '$_manifestHeaderEnd\n'
    'console.log("hello");\n';

const String _minimalManifest =
    '$_manifestHeaderStart\n'
    '// @id com.example.minimal\n'
    '// @name Minimal\n'
    '// @version 0.1.0\n'
    '// @author Dev\n'
    '// @apiVersion 2\n'
    '// @type movie\n'
    '$_manifestHeaderEnd\n';

String _manifestMissingField(String field) {
  const String fields =
      '// @id com.example.test\n'
      '// @name Test Extension\n'
      '// @version 1.0.0\n'
      '// @author Test Author\n'
      '// @apiVersion 2\n'
      '// @type movies_series\n';
  final List<String> lines = fields.split('\n')
    ..removeWhere((String line) => line.contains('@$field '));
  return '$_manifestHeaderStart\n${lines.join('\n')}\n$_manifestHeaderEnd\n';
}

String _manifestWithApiVersion(String version) =>
    '$_manifestHeaderStart\n'
    '// @id com.example.test\n'
    '// @name Test Extension\n'
    '// @version 1.0.0\n'
    '// @author Test Author\n'
    '// @apiVersion $version\n'
    '// @type movies_series\n'
    '$_manifestHeaderEnd\n';

const String _animeManifest =
    '$_manifestHeaderStart\n'
    '// @id com.example.anime\n'
    '// @name Anime Extension\n'
    '// @version 1.0.0\n'
    '// @author Test Author\n'
    '// @apiVersion 2\n'
    '// @contractVersion 2.1.0\n'
    '// @type anime\n'
    '$_manifestHeaderEnd\n'
    'console.log("hello");\n';

String _manifestWithContractVersion(String version) =>
    '$_manifestHeaderStart\n'
    '// @id com.example.test\n'
    '// @name Test Extension\n'
    '// @version 1.0.0\n'
    '// @author Test Author\n'
    '// @apiVersion 2\n'
    '// @contractVersion $version\n'
    '// @type movie\n'
    '$_manifestHeaderEnd\n';

String _manifestWithType(String type) =>
    '$_manifestHeaderStart\n'
    '// @id com.example.test\n'
    '// @name Test Extension\n'
    '// @version 1.0.0\n'
    '// @author Test Author\n'
    '// @apiVersion 2\n'
    '// @type $type\n'
    '$_manifestHeaderEnd\n';

const String _manifestWithReorderedFields =
    '$_manifestHeaderStart\n'
    '// @apiVersion 2\n'
    '// @author Test Author\n'
    '// @id com.example.test\n'
    '// @name Test Extension\n'
    '// @type movies_series\n'
    '// @version 1.0.0\n'
    '$_manifestHeaderEnd\n';
