/// Phase â€” user-supplied repository index, end to end through the UI layer.
///
/// These prove the thing a user actually sees: a pasted repository link becomes
/// a list of provider cards, refused entries are accounted for rather than
/// shown, and no filesystem path is ever displayed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/catalogue/extension_catalogue_client.dart';
import 'package:specta/core/extensions/distribution/extension_downloader.dart';
import 'package:specta/features/extensions/extensions_repository_sheet.dart';

/// Serves one canned document, so nothing touches the network.
class _CannedTransport implements ExtensionDownloadTransport {
  _CannedTransport(this.body, {this.status = 200});

  final String body;
  final int status;
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

const String repoLink = 'https://example.test/main/index.json';

/// Pumps the sheet and settles the single future it starts.
Future<void> _pumpSheet(WidgetTester tester, _CannedTransport transport) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ExtensionsRepositorySheet(
          client: ExtensionCatalogueClient(transport: transport),
          indexUrl: repoLink,
          installed: const <String, String>{},
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('a pasted repository link renders its providers as cards', (
    WidgetTester tester,
  ) async {
    await _pumpSheet(
      tester,
      _CannedTransport(
        '{"name":"Example Providers",'
        '"description":"A test repository.",'
        '"sources":['
        '{"id":"Alpha","name":"Alpha","version":"1.0.8",'
        '"file":"providers/alpha.js"},'
        '{"id":"uhd","name":"Beta","version":"1.0.3",'
        '"file":"providers/beta.js"}]}',
      ),
    );

    // The repository is named, and the host it came from is shown â€” a web
    // host, never a filesystem location.
    expect(find.text('Example Providers'), findsOneWidget);
    expect(find.text('A test repository.'), findsOneWidget);
    expect(find.text('From example.test'), findsOneWidget);

    // One card per provider, each with the action SPECTA really supports.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('v1.0.8'), findsOneWidget);
    // Each provider carries its own action.
    expect(find.text('Install'), findsNWidgets(2));

    // Real counts, and nothing invented.
    expect(find.text('2 providers'), findsOneWidget);
  });

  testWidgets('refused entries are counted, never shown as installable', (
    WidgetTester tester,
  ) async {
    await _pumpSheet(
      tester,
      _CannedTransport(
        '{"name":"Mixed",'
        '"sources":['
        '{"id":"ok","name":"Runnable","file":"ok.js"},'
        '{"id":"bin","name":"Binary","file":"thing.cs3"}]}',
      ),
    );

    expect(find.text('Runnable'), findsOneWidget);
    // The unrunnable entry is NOT offered as a provider...
    expect(find.text('Binary'), findsNothing);
    // ...and the omission is explained rather than silent.
    // Matched as substrings so the assertion does not depend on the exact
    // separator glyph, which is a presentation detail.
    expect(find.textContaining('1 provider'), findsOneWidget);
    expect(find.textContaining('1 skipped'), findsOneWidget);
  });

  testWidgets('a repository with nothing runnable says so, not "no providers"', (
    WidgetTester tester,
  ) async {
    await _pumpSheet(
      tester,
      _CannedTransport(
        '{"name":"Binaries","sources":[{"id":"a","name":"A","file":"a.cs3"}]}',
      ),
    );

    expect(
      find.textContaining('does not list any JavaScript sources'),
      findsOneWidget,
    );
    expect(find.textContaining('providers'), findsNothing);
  });

  testWidgets('a failure is reported with a retry, and stays a failure', (
    WidgetTester tester,
  ) async {
    await _pumpSheet(tester, _CannedTransport('not json', status: 200));

    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('no filesystem path is ever shown', (WidgetTester tester) async {
    await _pumpSheet(
      tester,
      _CannedTransport(
        '{"name":"Example","sources":[{"id":"a","name":"A","file":"a.js"}]}',
      ),
    );

    // Requirement: the user is never shown /sdcard/..., /data/... etc.
    expect(find.textContaining('/sdcard'), findsNothing);
    expect(find.textContaining('/storage/emulated'), findsNothing);
    expect(find.textContaining('/data/user'), findsNothing);
  });
}
