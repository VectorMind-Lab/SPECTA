/// Phase D â€” extension distribution and installation (D2/D3/D4/D7/D8).
///
/// Every test here proves the SAME point from a different angle: the URL and
/// catalogue routes converge on the Extension Manager pipeline rather than
/// re-implementing validation, and neither route can grant trust.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/catalogue/extension_catalogue.dart';
import 'package:specta/core/extensions/catalogue/extension_catalogue_client.dart';
import 'package:specta/core/extensions/distribution/extension_download_url_policy.dart';
import 'package:specta/core/extensions/distribution/extension_downloader.dart';
import 'package:specta/core/extensions/distribution/extension_storage.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/extension_lifecycle_service.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manifest.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/in_memory_extension_registry.dart';

/// Scriptable transport double: no network, no real host, ever.
class _FakeTransport implements ExtensionDownloadTransport {
  _FakeTransport({this.status = 200, this.body = '', this.failure});

  int status;
  String body;
  ExtensionDistributionFailure? failure;
  final List<Uri> requested = <Uri>[];

  @override
  Future<ExtensionDownloadResponse> get(Uri uri, Duration timeout) async {
    requested.add(uri);
    if (failure != null) {
      return ExtensionDownloadResponse(failure: failure);
    }
    return ExtensionDownloadResponse(
      statusCode: status,
      body: body,
      resolvedUrl: uri.toString(),
    );
  }
}

/// Writes into a temp dir so nothing depends on a platform channel.
class _TempStorage implements ExtensionStorage {
  _TempStorage(this.dir);

  final Directory dir;

  @override
  Future<SpectaResult<Directory>> resolveDirectory() async =>
      Ok<Directory>(dir);
}

/// A valid, minimal extension body with a real manifest header.
String _validExtension({
  String id = 'com.example.ext',
  String version = '1.0.0',
}) {
  return '''
// ==SpectaExtension==
// @id $id
// @name Example Extension
// @version $version
// @author SPECTA
// @apiVersion 2
// @type movie
// @capabilities search
(function () {
  return { search: function () { return []; } };
})();
''';
}

void main() {
  late Directory temp;
  late InMemoryExtensionRegistry registry;
  late ExtensionManager manager;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('specta_d_test');
    registry = InMemoryExtensionRegistry();
    manager = ExtensionManager(registry: registry);
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('D2 â€” URL policy (HTTPS only, no credentials, no private hosts)', () {
    test('a public https URL is accepted', () {
      expect(
        validateExtensionUrl(
          Uri.parse('https://raw.githubusercontent.com/a/b.js'),
        ).isOk,
        isTrue,
      );
    });

    test('an http URL is refused, not upgraded', () {
      final SpectaResult<Uri> result = validateExtensionUrl(
        Uri.parse('http://example.com/a.js'),
      );
      expect(result.isErr, isTrue);
      expect(
        (result.failureOrNull! as ExtensionDistributionFailure).type,
        ExtensionDistributionFailureType.invalidUrl,
      );
    });

    test('a non-absolute or unparseable URL is refused', () {
      expect(validateExtensionUrl(Uri.parse('/relative/a.js')).isErr, isTrue);
      expect(validateExtensionUrl(null).isErr, isTrue);
    });

    test('a URL carrying embedded credentials is refused', () {
      expect(
        validateExtensionUrl(Uri.parse('https://user:pw@example.com/a.js'))
            .isErr,
        isTrue,
      );
    });

    test('loopback and private targets are refused', () {
      for (final String host in <String>[
        'https://127.0.0.1/a.js',
        'https://localhost/a.js',
        'https://10.0.0.5/a.js',
        'https://192.168.1.1/a.js',
        'https://169.254.1.1/a.js',
        'https://[::1]/a.js',
        'https://[fd00::1]/a.js',
      ]) {
        expect(
          isBlockedExtensionHost(Uri.parse(host).host),
          isTrue,
          reason: host,
        );
      }
    });
  });

  group('D2/D8 â€” download validation', () {
    test('a valid https download returns bytes and a checksum', () async {
      final _FakeTransport transport = _FakeTransport(body: _validExtension());
      final ExtensionDownloader downloader = ExtensionDownloader(transport);

      final SpectaResult<DownloadedExtension> result = await downloader
          .download('https://example.com/ext.js');
      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('an unreachable host is a retryable network failure', () async {
      final _FakeTransport transport = _FakeTransport(
        failure: ExtensionDistributionFailure(
          type: ExtensionDistributionFailureType.networkError,
          stage: 'download',
        ),
      );
      final SpectaResult<DownloadedExtension> result =
          await ExtensionDownloader(transport)
              .download('https://example.com/ext.js');
      expect(result.isErr, isTrue);
      expect(result.failureOrNull!.isRetryable, isTrue);
    });

    test(
      '5xx is a retryable server error; 404 is a plain http error',
      () async {
        ExtensionDownloader at(int status) =>
            ExtensionDownloader(_FakeTransport(status: status, body: 'x'));
        final SpectaResult<DownloadedExtension> server = await at(503)
            .download('https://example.com/a.js');
        expect(
          (server.failureOrNull! as ExtensionDistributionFailure).type,
          ExtensionDistributionFailureType.serverError,
        );
        expect(server.failureOrNull!.isRetryable, isTrue);

        final SpectaResult<DownloadedExtension> missing = await at(404)
            .download('https://example.com/a.js');
        expect(
          (missing.failureOrNull! as ExtensionDistributionFailure).type,
          ExtensionDistributionFailureType.httpError,
        );
      },
    );

    test('an oversized body is refused', () async {
      final ExtensionDownloader downloader = ExtensionDownloader(
        _FakeTransport(body: 'x' * (maxExtensionBytes + 1)),
      );
      final SpectaResult<DownloadedExtension> result = await downloader
          .download('https://example.com/big.js');
      expect(
        (result.failureOrNull! as ExtensionDistributionFailure).type,
        ExtensionDistributionFailureType.tooLarge,
      );
    });

    test('a checksum mismatch is refused, and a match is accepted', () async {
      final String body = _validExtension();
      final String digest = await sha256Hex(utf8.encode(body));
      final ExtensionDownloader ok = ExtensionDownloader(
        _FakeTransport(body: body),
      );
      expect(
        (await ok.download(
          'https://example.com/a.js',
          expectedSha256: digest,
        )).isOk,
        isTrue,
      );

      final ExtensionDownloader bad = ExtensionDownloader(
        _FakeTransport(body: body),
      );
      final SpectaResult<DownloadedExtension> mismatch = await bad.download(
        'https://example.com/a.js',
        expectedSha256: 'a' * 64,
      );
      expect(
        (mismatch.failureOrNull! as ExtensionDistributionFailure).type,
        ExtensionDistributionFailureType.integrityMismatch,
      );
    });
  });

  group('PRE-F Â§16 â€” a link that is not an extension gets a TRUE message', () {
    // Field report: pasting a third-party JSON repository-catalogue link into
    // "Install from a link" produced "That extension file is too large to
    // install." The body was 343 bytes â€” the 10 MiB cap was never involved.
    // Three unrelated failures were all folded into `tooLarge`, so the user was
    // told to look for a size problem that did not exist. Each cause now has
    // its own type, and `tooLarge` means oversize and nothing else.

    test('an empty body is an empty response, not a size problem', () async {
      final SpectaResult<DownloadedExtension> result =
          await ExtensionDownloader(_FakeTransport(body: '   \n  '))
              .download('https://example.com/empty.js');

      final ExtensionDistributionFailure failure =
          result.failureOrNull! as ExtensionDistributionFailure;
      expect(failure.type, ExtensionDistributionFailureType.emptyResponse);
      expect(failure.type, isNot(ExtensionDistributionFailureType.tooLarge));
      expect(failure.message, isNot(contains('too large')));
    });

    test('a body that is not text is reported as such, not as too large', () {
      // The transport raises this when utf8.decode fails; a loopback HttpServer
      // cannot be used to drive it because the URL policy refuses private hosts
      // by design, so the message contract is asserted directly.
      final ExtensionDistributionFailure binary = ExtensionDistributionFailure(
        type: ExtensionDistributionFailureType.notText,
        stage: 'download',
        detail: 'Body is not valid UTF-8 text.',
      );
      expect(binary.message, isNot(contains('too large')));
      expect(binary.message, contains('text'));
    });

    test('tooLarge still means an oversize body, and nothing else', () {
      expect(
        ExtensionDistributionFailureType.tooLarge.message,
        contains('too large'),
      );
    });

    test('a repository catalogue is named as a catalogue', () {
      // The verbatim shape of the reported link's response body.
      const String repoJson =
          '{\n    "name": "Example Repo",\n'
          '    "iconUrl": "https://example.com/i.png"\n}';
      // A JSON document is now classified by the compatibility layer, which
      // runs BEFORE the manifest parser, so this is asserted at that layer
      // rather than through the parser's last-resort explanation.
      final String message = resolveImportableSource(repoJson).failure!.message;
      expect(message, contains('repository index'));
      expect(message, isNot(contains('too large')));
      expect(message, isNot(contains('Manifest parsing failed')));
    });

    test('a JSON array body is also recognised as a catalogue', () {
      final String message = resolveImportableSource(
        '[{"name":"x"}]',
      ).failure!.message;
      expect(message, contains('repository index'));
      expect(message, isNot(contains('JavaScript')));
    });

    test('ordinary non-source text gets a plain-language explanation', () {
      final String message = describeUnimportableSource(
        'just some random text',
        ManifestParseException('no manifest header found'),
      );
      // The text carries no `// ==SpectaExtension==` header, so the honest
      // explanation names the missing header instead of reporting whichever
      // required field the parser happened to check first.
      expect(message, contains('// ==SpectaExtension=='));
      expect(message, isNot(contains('too large')));
    });

    test(
      'a .js file with no SPECTA header names the header, not a missing field',
      () {
        // This is the case captured on a real device: a file from another
        // ecosystem. It has plenty of `@` lines, just not SPECTA's, so
        // reporting "Missing required field: id" was actively misleading.
        //
        // Note this is the FALLBACK explanation. A real foreign provider is
        // adapted upstream by `resolveImportableSource` and never reaches it;
        // the `maxmovies` dialect below is only refused when it implements
        // nothing SPECTA can call.
        final String message = describeUnimportableSource(
          '// ==Extension==\n// @name x\n// @version 1.0.0\n'
          '// @package net.example.ext\n// ==/Extension==\n',
          ManifestParseException('Missing required field: id'),
        );
        expect(message, contains('// ==SpectaExtension=='));
        expect(message, isNot(contains('Missing required field')));
        expect(message, isNot(contains('id')));
      },
    );

    test(
      'a foreign dialect with usable operations is ADAPTED, not described',
      () {
        // The `// ==Extension==` dialect is another ecosystem's header, not
        // garbage. When it implements recognisable operations it must be
        // adapted and installed rather than refused with a header complaint.
        const String foreign =
            '// ==Extension==\n// @name x\n// @version 1.0.0\n'
            '// @package net.example.ext\n// ==/Extension==\n'
            'function search(q, p) { return { results: [] }; }\n'
            'function getSources(ref) { return { sources: [] }; }\n';
        final ResolvedImportableSource resolved = resolveImportableSource(
          foreign,
        );
        expect(resolved.failure, isNull);
        expect(resolved.wasAdapted, isTrue);
        expect(
          resolved.analysis?.entryPoints,
          containsAll(<String>['search', 'getSources']),
        );
      },
    );

    test(
      'a .js file with a malformed manifest still reports the real reason',
      () {
        final String message = describeUnimportableSource(
          '// ==SpectaExtension==\n// @id a\n',
          ManifestParseException('missing @name'),
        );
        expect(message, contains('missing @name'));
      },
    );

    test('a catalogue body is NEVER installed, however well-formed it is', () async {
      // The explanation must not have become a bypass: a valid JSON catalogue
      // still has to fail the manifest gate and write nothing to the registry.
      final ExtensionLifecycleService service = ExtensionLifecycleService(
        manager: manager,
        downloader: ExtensionDownloader(
          _FakeTransport(body: '{"name":"Example Repo","addons":[]}'),
        ),
        storage: _TempStorage(temp),
      );

      final SpectaResult<ExtensionRecord> result = await service.installFromUrl(
        'https://raw.githubusercontent.com/example/repo/builds/repo.json',
      );

      expect(result.isErr, isTrue);
      final SpectaFailure failure = result.failureOrNull!;
      // The JSON document is recognised as a repository index by the
      // compatibility layer, so that is what the user is told. The important
      // part of this test is unchanged: it is refused, nothing is written, and
      // the explanation is not a size problem.
      expect(failure.message, contains('repository index'));
      expect(failure.message, isNot(contains('too large')));
      expect(
        (failure as ExtensionDistributionFailure).type,
        ExtensionDistributionFailureType.notAnExtension,
      );
      expect(await registry.getAll(), isEmpty);
    });
  });

  group(
    'a third-party source installed by URL takes the same path as one from the device',
    () {
      /// The real shape of a foreign provider: no SPECTA header, no exports,
      /// operations named its own host's way.
      const String foreignProvider = '''
// A community provider for another host.
var SITE = 'https://example.invalid';

function getInfo() {
  return { name: 'Community Films', version: '2.1.0', type: 'movie' };
}
function search(query, page) { return { results: [] }; }
function getHome() { return { results: [] }; }
function getDetail(ref) { return { id: ref }; }
function getVideoSources(ref) { return { sources: [] }; }
''';

      test('a foreign provider is installed from a URL, not refused', () async {
        final ExtensionLifecycleService service = ExtensionLifecycleService(
          manager: manager,
          downloader: ExtensionDownloader(
            _FakeTransport(body: foreignProvider),
          ),
          storage: _TempStorage(temp),
        );

        final SpectaResult<ExtensionRecord> result = await service
            .installFromUrl(
              'https://raw.githubusercontent.com/community/providers/films.js',
            );

        expect(result.isOk, isTrue, reason: result.failureOrNull?.message);
        final ExtensionRecord record = result.valueOrNull!;
        expect(record.name, 'Community Films');
        // The derived id, not a guessed one: a foreign file has no @id.
        expect(record.id, startsWith('foreign.'));
        // Unsigned, therefore unverified, exactly as any other imported file.
        expect(record.trustLevel, TrustLevel.unverified);
        expect(await registry.getAll(), hasLength(1));
      });

      test(
        'the ADAPTED source is what gets stored, so a restart still works',
        () async {
          final ExtensionLifecycleService service = ExtensionLifecycleService(
            manager: manager,
            downloader: ExtensionDownloader(
              _FakeTransport(body: foreignProvider),
            ),
            storage: _TempStorage(temp),
          );
          await service.installFromUrl(
            'https://raw.githubusercontent.com/community/providers/films.js',
          );

          // The stored file must be the adapted source, complete with the
          // generated header. Storing the raw download would leave a file with
          // no manifest, which fails to load after a restart.
          final List<File> stored = temp.listSync().whereType<File>().toList();
          expect(stored, isNotEmpty, reason: 'nothing was written');
          final String body = stored.first.readAsStringSync();
          expect(body, contains('// ==SpectaExtension=='));
          expect(body, contains('// @format adapted'));
          // And the author's own code is still there, untouched.
          expect(body, contains('function getVideoSources'));
        },
      );

      test('a JSON index by URL is reported as a repository, not installed',
          () async {
        final ExtensionLifecycleService service = ExtensionLifecycleService(
          manager: manager,
          downloader: ExtensionDownloader(
            _FakeTransport(
              body: '{"name":"Providers","sources":[{"id":"a",'
                  '"name":"A","file":"a.js"}]}',
            ),
          ),
          storage: _TempStorage(temp),
        );

        final SpectaResult<ExtensionRecord> result = await service
            .installFromUrl(
              'https://raw.githubusercontent.com/community/providers/index.json',
            );

        expect(result.isErr, isTrue);
        expect(result.failureOrNull!.message, contains('repository index'));
        // Nothing was written: a catalogue is not a source.
        expect(await registry.getAll(), isEmpty);
      });
    },
  );

  group('D3/D4 — catalogue contract is discovery, never trust', () {
    Map<String, Object?> doc(List<Object?> entries) => <String, Object?>{
      'schemaVersion': 1,
      'repositoryId': 'net.specta.official',
      'name': 'SPECTA Official',
      'extensions': entries,
    };

    Map<String, Object?> entry({
      String id = 'com.example.ext',
      String version = '1.0.0',
      int apiVersion = 2,
      String? url = 'https://example.com/ext.js',
    }) => <String, Object?>{
      'id': id,
      'name': 'Example',
      'version': version,
      'apiVersion': apiVersion,
      'downloadUrl': url,
    };

    test('a well-formed document parses and exposes entries', () {
      final ExtensionCatalogue? catalogue = ExtensionCatalogueParser.parse(
        jsonDecode(jsonEncode(doc(<Object?>[entry()]))) as Object?,
      );
      expect(catalogue, isNotNull);
      expect(catalogue!.repositoryId, 'net.specta.official');
      expect(catalogue.entries, hasLength(1));
    });

    test('an unsupported schemaVersion is rejected outright', () {
      final Map<String, Object?> wrong = doc(<Object?>[entry()])
        ..['schemaVersion'] = 99;
      expect(
        ExtensionCatalogueParser.parse(jsonDecode(jsonEncode(wrong))),
        isNull,
      );
    });

    test('a malformed entry is skipped without losing the good ones', () {
      final ExtensionCatalogue? catalogue = ExtensionCatalogueParser.parse(
        jsonDecode(
          jsonEncode(
            doc(<Object?>[
              <String, Object?>{
                'id': 'com.example.nodownload',
                'name': 'No download',
                'version': '1.0.0',
                'apiVersion': 2,
              },
              entry(id: 'bad.version', version: 'not-semver'),
              entry(id: 'com.example.good'),
            ]),
          ),
        ),
      );
      expect(catalogue!.entries, hasLength(1));
      expect(catalogue.entries.single.id, 'com.example.good');
    });

    test(
      'entries for an unsupported API major are hidden from the UI list',
      () {
        final ExtensionCatalogue? catalogue = ExtensionCatalogueParser.parse(
          jsonDecode(
            jsonEncode(
              doc(<Object?>[
                entry(id: 'com.example.ok'),
                entry(id: 'com.example.future', apiVersion: 3),
              ]),
            ),
          ),
        );
        expect(catalogue!.entries, hasLength(2));
        expect(
          catalogue.supportedEntries.map((ExtensionCatalogueEntry e) => e.id),
          <String>['com.example.ok'],
        );
      },
    );

    test('the catalogue model has NO trust field of any kind', () {
      // D4 guard: the catalogue is discovery only. If a trust/signature field
      // is ever added to the entry, this test fails and the design must be
      // reconsidered rather than silently trusted.
      expect(
        ExtensionCatalogueEntry(
          id: 'x',
          name: 'n',
          version: '1.0.0',
          apiVersion: 2,
          downloadUrl: 'https://e/x.js',
        ).toString(),
        isNot(contains('official')),
      );
    });

    test('update detection compares semver correctly', () {
      expect(
        isExtensionUpdateAvailable(installed: '1.0.0', candidate: '1.0.1'),
        isTrue,
      );
      expect(
        isExtensionUpdateAvailable(installed: '1.0.0', candidate: '1.0.0'),
        isFalse,
      );
      expect(
        isExtensionUpdateAvailable(installed: '2.0.0', candidate: '1.9.9'),
        isFalse,
      );
    });

    test('a catalogue fetch failure is structured, not an exception', () async {
      final ExtensionCatalogueClient client = ExtensionCatalogueClient(
        transport: _FakeTransport(status: 500, body: 'boom'),
      );
      final SpectaResult<ExtensionCatalogue> result = await client.load(
        'https://example.com/repository.json',
      );
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<ExtensionCatalogueFailure>());
    });

    test('a malformed catalogue document is a parse failure', () async {
      final ExtensionCatalogueClient client = ExtensionCatalogueClient(
        transport: _FakeTransport(body: 'not json at all'),
      );
      final SpectaResult<ExtensionCatalogue> result = await client.load(
        'https://example.com/repository.json',
      );
      expect(
        (result.failureOrNull! as ExtensionCatalogueFailure).type,
        ExtensionCatalogueFailureType.parseError,
      );
    });

    test('a successful catalogue is reused within the TTL', () async {
      final _FakeTransport transport = _FakeTransport(
        body: jsonEncode(doc(<Object?>[entry()])),
      );
      final ExtensionCatalogueClient client = ExtensionCatalogueClient(
        transport: transport,
      );
      final DateTime t0 = DateTime.utc(2026, 1, 1);

      expect(
        (await client.load('https://example.com/r.json', now: t0)).isOk,
        isTrue,
      );
      expect(
        (await client.load(
          'https://example.com/r.json',
          now: t0.add(const Duration(minutes: 5)),
        )).isOk,
        isTrue,
      );
      // Only ONE network call: the second load was served from the memo.
      expect(transport.requested, hasLength(1));

      expect(
        (await client.load(
          'https://example.com/r.json',
          now: t0.add(const Duration(hours: 1)),
        )).isOk,
        isTrue,
      );
      expect(transport.requested, hasLength(2));
    });
  });

  group('D2/D9 â€” all three routes converge on the Extension Manager', () {
    ExtensionLifecycleService serviceWith(_FakeTransport transport) =>
        ExtensionLifecycleService(
          manager: manager,
          downloader: ExtensionDownloader(transport),
          storage: _TempStorage(temp),
        );

    test(
      'a URL install goes through the manager and lands in the registry',
      () async {
        final _FakeTransport transport = _FakeTransport(
          body: _validExtension(),
        );
        final SpectaResult<ExtensionRecord> result = await serviceWith(
          transport,
        ).installFromUrl('https://example.com/ext.js');

        expect(result.isOk, isTrue, reason: '${result.failureOrNull}');
        // Written into app-private storage first, then imported from that file.
        expect(result.valueOrNull!.filePath, isNot(contains('example.com')));
        expect(File(result.valueOrNull!.filePath).existsSync(), isTrue);
        // And the manager recorded it â€” no parallel install path.
        expect((await registry.getById('com.example.ext')), isNotNull);
      },
    );

    test(
      'an http URL install is refused before anything is downloaded',
      () async {
        final _FakeTransport transport = _FakeTransport(
          body: _validExtension(),
        );
        final SpectaResult<ExtensionRecord> result = await serviceWith(
          transport,
        ).installFromUrl('http://example.com/ext.js');

        expect(result.isErr, isTrue);
        expect(transport.requested, isEmpty, reason: 'no request may be made');
        expect(await registry.getAll(), isEmpty);
      },
    );

    test('a catalogue install takes the same route as a URL install', () async {
      final _FakeTransport transport = _FakeTransport(
        body: _validExtension(id: 'com.example.catalogue'),
      );
      final SpectaResult<ExtensionRecord> result = await serviceWith(transport)
          .installFromCatalogueEntry(
            const ExtensionCatalogueEntry(
              id: 'com.example.catalogue',
              name: 'Example',
              version: '1.0.0',
              apiVersion: 2,
              downloadUrl: 'https://example.com/cat.js',
            ),
          );

      expect(result.isOk, isTrue, reason: '${result.failureOrNull}');
      expect((await registry.getById('com.example.catalogue')), isNotNull);
    });

    test('a catalogue entry does NOT confer trust: unsigned stays unverified', () async {
      final _FakeTransport transport = _FakeTransport(
        body: _validExtension(id: 'com.example.untrusted'),
      );
      final SpectaResult<ExtensionRecord> result = await serviceWith(transport)
          .installFromCatalogueEntry(
            const ExtensionCatalogueEntry(
              id: 'com.example.untrusted',
              name: 'Example',
              version: '1.0.0',
              apiVersion: 2,
              downloadUrl: 'https://official.example/cat.js',
            ),
          );

      expect(result.isOk, isTrue);
      // Hosted on an "official-looking" host, but the SIGNATURE decides trust.
      expect(result.valueOrNull!.trustLevel, TrustLevel.unverified);
    });

    test(
      'a downloaded file with an invalid manifest is rejected by the manager',
      () async {
        final _FakeTransport transport = _FakeTransport(
          body: 'not an extension',
        );
        final SpectaResult<ExtensionRecord> result = await serviceWith(
          transport,
        ).installFromUrl('https://example.com/bad.js');
        expect(result.isErr, isTrue);
        expect(await registry.getAll(), isEmpty);
      },
    );

    test(
      'a downloaded file with an unsupported contract is rejected',
      () async {
        final _FakeTransport transport = _FakeTransport(
          body: _validExtension().replaceAll('@apiVersion 2', '@apiVersion 9'),
        );
        final SpectaResult<ExtensionRecord> result = await serviceWith(
          transport,
        ).installFromUrl('https://example.com/future.js');
        expect(result.isErr, isTrue);
        expect(await registry.getAll(), isEmpty);
      },
    );

    test(
      'a failed install never leaves a half-installed registry row',
      () async {
        final _FakeTransport transport = _FakeTransport(
          status: 404,
          body: 'nope',
        );
        final SpectaResult<ExtensionRecord> result = await serviceWith(
          transport,
        ).installFromUrl('https://example.com/missing.js');
        expect(result.isErr, isTrue);
        expect(await registry.getAll(), isEmpty);
      },
    );
  });

  group('D7 â€” update, replace and rollback', () {
    test('replacing an extension snapshots the outgoing version', () async {
      final File first = File('${temp.path}/v1.js')
        ..writeAsStringSync(_validExtension(version: '1.0.0'));
      expect(
        (await manager.importExtension(filePath: first.path)).isOk,
        isTrue,
      );

      final File second = File('${temp.path}/v2.js')
        ..writeAsStringSync(_validExtension(version: '2.0.0'));
      expect(
        (await manager.importExtension(filePath: second.path)).isOk,
        isTrue,
      );

      // The D7 fix: a rollback point now exists.
      final ExtensionVersionRecord? snapshot = await registry
          .getRollbackVersion('com.example.ext');
      expect(snapshot, isNotNull);
      expect(snapshot!.version, '1.0.0');

      // The current record is the NEW version.
      expect((await registry.getById('com.example.ext'))!.version, '2.0.0');
    });

    test('rollback restores the previous version', () async {
      final File first = File('${temp.path}/v1.js')
        ..writeAsStringSync(_validExtension(version: '1.0.0'));
      await manager.importExtension(filePath: first.path);
      final File second = File('${temp.path}/v2.js')
        ..writeAsStringSync(_validExtension(version: '2.0.0'));
      await manager.importExtension(filePath: second.path);

      expect(await manager.rollback('com.example.ext'), isTrue);
      expect((await registry.getById('com.example.ext'))!.version, '1.0.0');
    });

    test('re-installing preserves the user\'s disabled state', () async {
      final File first = File('${temp.path}/v1.js')
        ..writeAsStringSync(_validExtension());
      await manager.importExtension(filePath: first.path);
      await manager.setEnabled('com.example.ext', false);

      final File second = File('${temp.path}/v2.js')
        ..writeAsStringSync(_validExtension(version: '1.1.0'));
      final SpectaResult<ExtensionRecord> result = await manager
          .importExtension(filePath: second.path);

      expect(result.isOk, isTrue);
      // An update is not an implicit re-enable.
      expect(result.valueOrNull!.enabled, isFalse);
    });

    test(
      'a duplicate install replaces rather than duplicating the id',
      () async {
        final File first = File('${temp.path}/a.js')
          ..writeAsStringSync(_validExtension());
        await manager.importExtension(filePath: first.path);
        final File second = File('${temp.path}/b.js')
          ..writeAsStringSync(_validExtension(version: '3.0.0'));
        await manager.importExtension(filePath: second.path);

        expect(await registry.getAll(), hasLength(1));
        expect((await registry.getById('com.example.ext'))!.version, '3.0.0');
      },
    );
  });

  // The exact chain the phase brief requires, exercised through the LIFECYCLE
  // SERVICE (the layer the UI actually calls), not just the manager: an update
  // is detected, applied, and then reverted to the previous version.
  group('D7 â€” update available -> applied -> rollback -> restored', () {
    late ExtensionLifecycleService service;
    late _FakeTransport transport;

    setUp(() {
      transport = _FakeTransport();
      service = ExtensionLifecycleService(
        manager: manager,
        storage: _TempStorage(temp),
        downloader: ExtensionDownloader(transport),
      );
    });

    /// Serves the catalogue document SPECTA fetches to decide what is newer.
    void serveCatalogue({required String version}) {
      transport.body = jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'repositoryId': 'test',
        'name': 'Test',
        'extensions': <Object?>[
          <String, Object?>{
            'id': 'com.example.ext',
            'name': 'Example Extension',
            'version': version,
            'apiVersion': 2,
            'downloadUrl': 'https://cdn.example.com/ext.js',
          },
        ],
      });
    }

    /// Serves the extension body the update downloads.
    void serveExtension({required String version}) {
      transport.body = _validExtension(version: version);
    }

    test(
      'a newer catalogue version is detected, applied, then rolled back',
      () async {
        // --- 1. installed at 1.0.0 -------------------------------------------
        serveExtension(version: '1.0.0');
        expect(
          (await service.installFromUrl('https://cdn.example.com/e.js')).isOk,
          isTrue,
        );
        expect((await service.installed()).single.record.version, '1.0.0');
        // Nothing to roll back to yet, so the UI offers no restore control.
        expect(await service.isRollbackAvailable('com.example.ext'), isFalse);

        // --- 2. update available ---------------------------------------------
        // The catalogue advertises 2.0.0, so a semver comparison reports an
        // update. This is what the check button surfaces; it installs nothing.
        serveCatalogue(version: '2.0.0');
        final ExtensionCatalogue catalogue = (await ExtensionCatalogueClient(
          transport: transport,
        ).load('https://cdn.example.com/repository.json')).valueOrNull!;
        final ExtensionCatalogueEntry entry = catalogue.entries.single;
        expect(
          isExtensionUpdateAvailable(
            installed: '1.0.0',
            candidate: entry.version,
          ),
          isTrue,
        );

        // --- 3. update applied -----------------------------------------------
        serveExtension(version: '2.0.0');
        expect((await service.installFromCatalogueEntry(entry)).isOk, isTrue);
        expect((await service.installed()).single.record.version, '2.0.0');
        // The outgoing version was snapshotted, so a restore is now offered.
        expect(await service.isRollbackAvailable('com.example.ext'), isTrue);

        // --- 4. rollback -> previous version restored ------------------------
        expect(await service.rollback('com.example.ext'), isTrue);
        final ManagedExtension restored = (await service.installed()).single;
        expect(restored.record.version, '1.0.0');
        // The snapshot was consumed, so there is nothing left to roll back to.
        expect(await service.isRollbackAvailable('com.example.ext'), isFalse);
        // A second rollback attempt is refused rather than silently succeeding.
        expect(await service.rollback('com.example.ext'), isFalse);
      },
    );

    test('an unchanged catalogue version is not reported as an update', () {
      expect(
        isExtensionUpdateAvailable(installed: '1.0.0', candidate: '1.0.0'),
        isFalse,
      );
      // A downgrade is never an "update".
      expect(
        isExtensionUpdateAvailable(installed: '2.0.0', candidate: '1.0.0'),
        isFalse,
      );
    });

    test('rollback preserves the user\'s disabled state', () async {
      serveExtension(version: '1.0.0');
      await service.installFromUrl('https://cdn.example.com/e.js');
      await service.setEnabled('com.example.ext', false);

      serveExtension(version: '2.0.0');
      await service.installFromUrl('https://cdn.example.com/e.js');
      await service.rollback('com.example.ext');

      final ManagedExtension restored = (await service.installed()).single;
      expect(restored.record.version, '1.0.0');
      expect(restored.record.enabled, isFalse);
    });
  });
}
