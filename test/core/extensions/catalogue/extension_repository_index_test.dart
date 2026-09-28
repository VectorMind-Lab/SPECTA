/// Phase â€” user-supplied repository index (requirement D).
///
/// The point of these tests is that a repository the USER supplies â€” in whatever
/// shape that author published â€” is readable, and that making it readable never
/// weakens a single security property.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/catalogue/extension_catalogue_client.dart';
import 'package:specta/core/extensions/catalogue/extension_repository_index.dart';
import 'package:specta/core/extensions/distribution/extension_downloader.dart';

final Uri indexUrl = Uri.parse(
  'https://raw.githubusercontent.com/example/providers/main/index.json',
);

/// A transport double, so nothing here touches the network.
class _FakeTransport implements ExtensionDownloadTransport {
  _FakeTransport({this.status = 200, this.body = ''});

  int status;
  String body;
  final List<Uri> requested = <Uri>[];

  @override
  Future<ExtensionDownloadResponse> get(Uri uri, Duration timeout) async {
    requested.add(uri);
    return ExtensionDownloadResponse(
      statusCode: status,
      body: body,
      resolvedUrl: uri.toString(),
    );
  }
}

void main() {
  group('D â€” a user-supplied repository index is readable', () {
    test('the common "sources" + relative "file" shape resolves to .js URLs', () {
      // This mirrors the shape real provider repositories publish: a `sources`
      // array whose entries carry a RELATIVE path, with no schemaVersion.
      final Object decoded = jsonDecode(
        jsonEncode(<String, Object?>{
          'name': 'Example Providers',
          'description': 'A test repository.',
          'sources': <Object?>[
            <String, Object?>{
              'id': 'Alpha',
              'name': 'Alpha',
              'version': '1.0.8',
              'type': 'anime',
              'file': 'providers/Alpha.js',
              'logo': 'icons/Alpha.png',
            },
            <String, Object?>{
              'id': 'beta',
              'name': 'Beta',
              'version': '1.0.3',
              'file': 'providers/beta.js',
            },
          ],
        }),
      );

      final ExtensionRepositoryIndex? index =
          ExtensionRepositoryIndexParser.parse(decoded, indexUrl);

      expect(index, isNotNull);
      expect(index!.name, 'Example Providers');
      expect(index.description, 'A test repository.');
      expect(index.entries, hasLength(2));
      expect(index.skippedNotJavaScript, 0);

      // The relative path is resolved against the index's own DIRECTORY, not
      // against the host root.
      expect(
        index.entries.first.downloadUrl,
        'https://raw.githubusercontent.com/example/providers/main/providers/Alpha.js',
      );
      expect(index.entries.first.iconUrl, endsWith('/main/icons/Alpha.png'));
      expect(index.entries.first.version, '1.0.8');
    });

    test('an absolute downloadUrl is passed through unchanged', () {
      const String absolute =
          'https://raw.githubusercontent.com/other/repo/main/thing.js';
      final ExtensionRepositoryIndex? index =
          ExtensionRepositoryIndexParser.parse(
            jsonDecode(
              jsonEncode(<String, Object?>{
                'extensions': <Object?>[
                  <String, Object?>{
                    'id': 'a',
                    'name': 'A',
                    'downloadUrl': absolute,
                  },
                ],
              }),
            ),
            indexUrl,
          );
      expect(index!.entries.single.downloadUrl, absolute);
    });

    test('a bare top-level array is accepted', () {
      final ExtensionRepositoryIndex? index =
          ExtensionRepositoryIndexParser.parse(
            jsonDecode(
              jsonEncode(<Object?>[
                <String, Object?>{'id': 'a', 'name': 'A', 'file': 'a.js'},
              ]),
            ),
            indexUrl,
          );
      expect(index!.entries, hasLength(1));
      expect(index.entries.single.downloadUrl, endsWith('/main/a.js'));
    });

    test('"addons" and "plugins" are accepted as root keys', () {
      for (final String key in <String>['addons', 'plugins', 'providers']) {
        final ExtensionRepositoryIndex? index =
            ExtensionRepositoryIndexParser.parse(
              jsonDecode(
                jsonEncode(<String, Object?>{
                  key: <Object?>[
                    <String, Object?>{'id': 'a', 'name': 'A', 'file': 'a.js'},
                  ],
                }),
              ),
              indexUrl,
            );
        expect(index, isNotNull, reason: 'root key "$key" should be accepted');
        expect(index!.entries, hasLength(1));
      }
    });
  });

  group('D â€” the reader refuses to pretend non-extensions are installable', () {
    test('a non-JavaScript entry is skipped and COUNTED, not listed', () {
      // A binary/compiled provider plugin can never install in SPECTA. Offering
      // an install button for it would be a guaranteed failure, so it is
      // dropped â€” and the count is surfaced so the UI can say why.
      final ExtensionRepositoryIndex? index =
          ExtensionRepositoryIndexParser.parse(
            jsonDecode(
              jsonEncode(<String, Object?>{
                'plugins': <Object?>[
                  <String, Object?>{'id': 'a', 'file': 'binary.cs3'},
                  <String, Object?>{'id': 'b', 'file': 'providers/ok.js'},
                  <String, Object?>{'id': 'c', 'file': 'thing.zip'},
                ],
              }),
            ),
            indexUrl,
          );

      expect(index, isNotNull);
      expect(index!.entries, hasLength(1));
      expect(index.entries.single.id, 'b');
      expect(index.skippedNotJavaScript, 2);
    });

    test('a query string does not disguise a non-JS file', () {
      expect(
        ExtensionRepositoryIndexParser.looksLikeJavaScript(
          Uri.parse('https://host/x.js?v=2#frag'),
        ),
        isTrue,
      );
      expect(
        ExtensionRepositoryIndexParser.looksLikeJavaScript(
          Uri.parse('https://host/x.cs3?v=2'),
        ),
        isFalse,
      );
    });

    test('an entry with no usable id is skipped, not half-listed', () {
      final ExtensionRepositoryIndex? index =
          ExtensionRepositoryIndexParser.parse(
            jsonDecode(
              jsonEncode(<String, Object?>{
                'extensions': <Object?>[
                  <String, Object?>{'name': 'No Id', 'file': 'a.js'},
                  <String, Object?>{'id': 'ok', 'file': 'b.js'},
                ],
              }),
            ),
            indexUrl,
          );
      expect(index!.entries, hasLength(1));
      expect(index.skippedUnusable, 1);
    });

    test(
      'a document with nothing installable returns null, not an empty list',
      () {
        // An empty catalogue would render an empty browser and read as "this
        // repository has no providers" rather than "none of this is runnable".
        expect(
          ExtensionRepositoryIndexParser.parse(
            jsonDecode(
              jsonEncode(<String, Object?>{
                'name': 'Binaries only',
                'plugins': <Object?>[
                  <String, Object?>{'id': 'a', 'file': 'a.cs3'},
                ],
              }),
            ),
            indexUrl,
          ),
          isNull,
        );
      },
    );

    test('a hostile document is bounded, not rendered unbounded', () {
      final List<Object?> many = List<Object?>.generate(
        900,
        (int i) => <String, Object?>{'id': 'e$i', 'file': 'e$i.js'},
      );
      final ExtensionRepositoryIndex? index =
          ExtensionRepositoryIndexParser.parse(
            jsonDecode(jsonEncode(<String, Object?>{'extensions': many})),
            indexUrl,
          );
      expect(index!.entries.length, lessThanOrEqualTo(500));
    });

    test('an oversized string field is dropped, not passed through', () {
      final ExtensionRepositoryIndex? index =
          ExtensionRepositoryIndexParser.parse(
            jsonDecode(
              jsonEncode(<String, Object?>{
                'extensions': <Object?>[
                  <String, Object?>{
                    'id': 'a',
                    'file': 'a.js',
                    'description': 'x' * 5000,
                  },
                ],
              }),
            ),
            indexUrl,
          );
      expect(index!.entries.single.description, isNull);
    });
  });

  group('D â€” discovery is still not trust', () {
    test('a sha256- prefixed hash is normalised to bare hex', () {
      const String hex =
          '71188bfe509c9ab32f643801aa46c261f69b2790a7537ed85be8e24f2de4dc8f';
      final ExtensionRepositoryIndex? index =
          ExtensionRepositoryIndexParser.parse(
            jsonDecode(
              jsonEncode(<String, Object?>{
                'extensions': <Object?>[
                  <String, Object?>{
                    'id': 'a',
                    'file': 'a.js',
                    'fileHash': 'sha256-$hex',
                  },
                ],
              }),
            ),
            indexUrl,
          );
      expect(index!.entries.single.sha256, hex);
    });

    test('a malformed hash is discarded rather than trusted', () {
      final ExtensionRepositoryIndex? index =
          ExtensionRepositoryIndexParser.parse(
            jsonDecode(
              jsonEncode(<String, Object?>{
                'extensions': <Object?>[
                  <String, Object?>{
                    'id': 'a',
                    'file': 'a.js',
                    'sha256': 'nope',
                  },
                ],
              }),
            ),
            indexUrl,
          );
      expect(index!.entries.single.sha256, isNull);
    });

    test('an index cannot talk the host into an older contract', () {
      // The index is a claim. Reporting API 1 hides nothing: ExtensionManager
      // still refuses an incompatible extension on the real manifest.
      final ExtensionRepositoryIndex? index =
          ExtensionRepositoryIndexParser.parse(
            jsonDecode(
              jsonEncode(<String, Object?>{
                'extensions': <Object?>[
                  <String, Object?>{'id': 'a', 'file': 'a.js', 'apiVersion': 1},
                ],
              }),
            ),
            indexUrl,
          );
      expect(index!.entries.single.apiVersion, 1);
    });

    test('a missing apiVersion defaults to the host current, not zero', () {
      final ExtensionRepositoryIndex? index =
          ExtensionRepositoryIndexParser.parse(
            jsonDecode(
              jsonEncode(<String, Object?>{
                'extensions': <Object?>[
                  <String, Object?>{'id': 'a', 'file': 'a.js'},
                ],
              }),
            ),
            indexUrl,
          );
      expect(index!.entries.single.apiVersion, 2);
    });
  });

  group('D â€” the client fetches a user index under the same URL policy', () {
    test('a user index is fetched over https and parsed', () async {
      final _FakeTransport transport = _FakeTransport(
        body: jsonEncode(<String, Object?>{
          'name': 'Example',
          'sources': <Object?>[
            <String, Object?>{'id': 'a', 'name': 'A', 'file': 'providers/a.js'},
          ],
        }),
      );
      final SpectaResult<ExtensionRepositoryIndex> result =
          await ExtensionCatalogueClient(transport: transport)
              .loadRepositoryIndex(indexUrl.toString());

      expect(result.isOk, isTrue, reason: '${result.failureOrNull}');
      expect(result.valueOrNull!.name, 'Example');
      expect(result.valueOrNull!.entries.single.downloadUrl, endsWith('/a.js'));
      expect(transport.requested.single, indexUrl);
    });

    test('an http index URL is refused by policy, never upgraded', () async {
      final _FakeTransport transport = _FakeTransport(body: '{}');
      final SpectaResult<ExtensionRepositoryIndex> result =
          await ExtensionCatalogueClient(transport: transport)
              .loadRepositoryIndex('http://example.com/index.json');

      expect(result.isErr, isTrue);
      expect(
        (result.failureOrNull! as ExtensionCatalogueFailure).type,
        ExtensionCatalogueFailureType.invalidUrl,
      );
      expect(transport.requested, isEmpty);
    });

    test('a loopback index URL is refused before any request', () async {
      final _FakeTransport transport = _FakeTransport(body: '{}');
      final SpectaResult<ExtensionRepositoryIndex> result =
          await ExtensionCatalogueClient(transport: transport)
              .loadRepositoryIndex('https://127.0.0.1/index.json');

      expect(result.isErr, isTrue);
      expect(transport.requested, isEmpty);
    });

    test('a 404 is a structured catalogue failure, not a crash', () async {
      final SpectaResult<ExtensionRepositoryIndex> result =
          await ExtensionCatalogueClient(
            transport: _FakeTransport(status: 404, body: 'nope'),
          ).loadRepositoryIndex(indexUrl.toString());

      expect(result.isErr, isTrue);
      expect(
        (result.failureOrNull! as ExtensionCatalogueFailure).type,
        ExtensionCatalogueFailureType.httpError,
      );
    });

    test('malformed JSON is a parse failure, not a crash', () async {
      final SpectaResult<ExtensionRepositoryIndex> result =
          await ExtensionCatalogueClient(
            transport: _FakeTransport(body: 'not json at all'),
          ).loadRepositoryIndex(indexUrl.toString());

      expect(result.isErr, isTrue);
      expect(
        (result.failureOrNull! as ExtensionCatalogueFailure).type,
        ExtensionCatalogueFailureType.parseError,
      );
    });
  });
}
