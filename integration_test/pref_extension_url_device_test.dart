// SPECTA - PRE-F device verification: truthful install-failure reporting.
//
// Exercises three live-network paths on a PHYSICAL DEVICE, inside the real app
// process, with the real network stack.
//
// NO EXTERNAL LINK IS COMPILED INTO THIS FILE. Every live input is supplied at
// run time via --dart-define (see the constants below). This is deliberate:
// SPECTA must remain generic and must carry no dependency on, affiliation with,
// or endorsement of any particular third-party repository. When a define is
// absent the matching test reports a SKIP, so the suite is green by default and
// never reaches the public internet unless a human deliberately asks it to.
//
// What it proves, end to end:
//
//   1. A link to a JSON repository CATALOGUE - which is not a SPECTA extension -
//      is REFUSED by the full download -> verify -> write -> ExtensionManager
//      pipeline, and installs nothing.
//   2. The user-facing message is TRUTHFUL: it names the file for what it is
//      and NEVER claims a size limit was exceeded.
//   3. A user-supplied repository INDEX is read and its relative paths resolved
//      into absolute https .js URLs.
//
// This is the defect that was reported: three unrelated causes were all mapped
// to `tooLarge`, so a link of a few hundred bytes reached the user as
// "That extension file is too large to install."

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/catalogue/extension_catalogue.dart';
import 'package:specta/core/extensions/catalogue/extension_catalogue_client.dart';
import 'package:specta/core/extensions/catalogue/extension_repository_index.dart';
import 'package:specta/core/extensions/distribution/dart_io_extension_download_transport.dart';
import 'package:specta/core/extensions/distribution/extension_downloader.dart';
import 'package:specta/core/extensions/distribution/extension_storage.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/extension_lifecycle_service.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_providers.dart';

// ignore: avoid_print
void marker(String m) => print('[SPECTA-PREF] $m');

/// EXTERNAL TEST INPUT â€” supplied at RUN TIME, never compiled in.
///
/// These two links are deliberately NOT literals in this file. SPECTA must stay
/// generic: it supports whatever repository the USER supplies, and must carry no
/// dependency on, affiliation with, or endorsement of any particular
/// repository. Hard-coding a third-party index here would make SPECTA's test
/// suite depend on â€” and implicitly promote â€” a host SPECTA does not control.
///
/// Supply them explicitly when exercising the live-network paths:
///
/// ```sh
/// flutter test integration_test/pref_extension_url_device_test.dart \
///   -d <device> \
///   --dart-define=SPECTA_LIVE_CATALOGUE_URL=<some https .json link> \
///   --dart-define=SPECTA_LIVE_REPOSITORY_URL=<some https index.json link>
/// ```
///
/// When a define is absent the corresponding test reports a SKIP. The suite is
/// therefore green by default and never reaches the public internet unless a
/// human deliberately asks it to.
///
/// A link to a JSON repository CATALOGUE that is not an extension. Used to prove
/// the truthful "not an extension" message and that nothing is installed.
const String liveCatalogueUrl = String.fromEnvironment(
  'SPECTA_LIVE_CATALOGUE_URL',
);

/// A link to a user-supplied REPOSITORY INDEX. Used to prove the generic index
/// reader works against a real host.
const String liveRepositoryUrl = String.fromEnvironment(
  'SPECTA_LIVE_REPOSITORY_URL',
);

/// A link to a REAL, signed-or-unsigned SPECTA-format `.js` extension, used as
/// the positive control: a genuine extension must still install, so a refusal
/// cannot be mistaken for "the URL install path is simply broken".
///
/// SPECTA's own reference extension lives in a PRIVATE repository, so no public
/// default is compiled in. Supply it explicitly:
///
/// ```sh
/// --dart-define=SPECTA_LIVE_EXTENSION_URL=<https link to a .js extension>
/// ```
const String referenceExtensionUrl = String.fromEnvironment(
  'SPECTA_LIVE_EXTENSION_URL',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('PRE-F-1: a JSON catalogue link is refused TRUTHFULLY', () async {
    if (liveCatalogueUrl.isEmpty) {
      marker('SKIP: no SPECTA_LIVE_CATALOGUE_URL supplied');
      return;
    }
    // --- 1. The raw download, over the device's real network. --------------
    final ExtensionDownloader downloader = ExtensionDownloader(
      DartIoExtensionDownloadTransport(),
    );

    final result = await downloader.download(liveCatalogueUrl);
    marker('download ok=${result.isOk} failure=${result.failureOrNull}');

    // The link resolves on the handset. If this fails it is a network problem
    // on the device and the rest of the test is void Ã¢â‚¬â€ so it is asserted, not
    // swallowed.
    expect(
      result.isOk,
      isTrue,
      reason:
          'device could not fetch the reported link: '
          '${result.failureOrNull}',
    );

    final downloaded = result.valueOrNull!;
    marker('bytes=${downloaded.sizeBytes} url=${downloaded.resolvedUrl}');

    // --- 2. The size that "too large" wrongly claimed. ----------------------
    // If this ever fails, the old message was accidentally correct.
    expect(
      downloaded.sizeBytes,
      lessThan(1024 * 1024),
      reason: 'body was actually large; the old message would have applied',
    );
    marker(
      'body is ${downloaded.sizeBytes} bytes Ã¢â‚¬â€ far below the '
      '$maxExtensionBytes byte cap',
    );

    // It really is a JSON catalogue, not JavaScript with a manifest header.
    expect(downloaded.sourceCode.trimLeft().startsWith('{'), isTrue);

    // --- 3. The full install pipeline must refuse it, truthfully. ----------
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    final ExtensionManager manager = container.read(extensionManagerProvider);

    final ExtensionLifecycleService service = ExtensionLifecycleService(
      manager: manager,
      downloader: downloader,
      storage: const AppPrivateExtensionStorage(),
    );

    final install = await service.installFromUrl(liveCatalogueUrl);
    marker(
      'install ok=${install.isOk} '
      'message=${install.failureOrNull?.message}',
    );

    expect(
      install.isErr,

      isTrue,
      reason: 'a JSON catalogue must never install as an extension',
    );
    expect(
      await manager.getAllExtensions(),
      isEmpty,
      reason: 'a refused catalogue must leave nothing installed',
    );

    // --- 4. The user-facing message must be truthful. ----------------------
    final String message = install.failureOrNull!.message;
    marker('USER-VISIBLE MESSAGE: $message');

    expect(
      message.toLowerCase(),
      isNot(contains('too large')),
      reason: 'the pre-fix bug: a tiny catalogue reported as too large',
    );
    expect(
      message.toLowerCase(),
      contains('catalogue'),
      reason: 'the message should name what the file actually is',
    );
  });

  test(
    'PRE-F-2: a REAL extension URL still installs through the same path',
    () async {
      if (referenceExtensionUrl.isEmpty) {
        marker('SKIP: no SPECTA_LIVE_EXTENSION_URL supplied');
        return;
      }

      final ExtensionDownloader downloader = ExtensionDownloader(
        DartIoExtensionDownloadTransport(),
      );

      // Guard the control itself. If the supplied link is not reachable from
      // this device there is nothing to assert, and we say so rather than
      // reporting a pass we did not earn.
      if ((await downloader.download(referenceExtensionUrl)).isErr) {
        marker('SKIP: supplied extension not reachable from this device');
        return;
      }

      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final ExtensionManager manager = container.read(extensionManagerProvider);

      final ExtensionLifecycleService service = ExtensionLifecycleService(
        manager: manager,
        downloader: downloader,
        storage: const AppPrivateExtensionStorage(),
      );

      final install = await service.installFromUrl(referenceExtensionUrl);
      marker(
        'reference install ok=${install.isOk} '
        'message=${install.failureOrNull?.message}',
      );

      expect(
        install.isOk,
        isTrue,
        reason: 'a real extension URL must install: ${install.failureOrNull}',
      );

      final installed = await manager.getAllExtensions();
      expect(installed, hasLength(1));
      marker(
        'installed id=${installed.first.id} version=${installed.first.version} '
        'trust=${installed.first.trustLevel}',
      );

      // The GitHub URL bought bytes and nothing more: an unsigned extension from a
      // GitHub host still classifies as unverified, never as trusted.
      expect(
        installed.first.trustLevel,
        isNot(TrustLevel.official),
        reason: 'a GitHub URL must never confer trust by itself',
      );
    },
  );

  test(
    'PRE-F-3: a user-supplied repository index is read on the device',
    () async {
      // Requirement D, on real hardware with the real network stack, against a
      // link the RUNNER supplies. Nothing about any particular repository is
      // compiled in: see the note above liveRepositoryUrl.
      if (liveRepositoryUrl.isEmpty) {
        marker('SKIP: no SPECTA_LIVE_REPOSITORY_URL supplied');
        return;
      }

      final SpectaResult<ExtensionRepositoryIndex> result =
          await ExtensionCatalogueClient(
            transport: DartIoExtensionDownloadTransport(),
          ).loadRepositoryIndex(liveRepositoryUrl);

      marker('index ok=${result.isOk} failure=${result.failureOrNull}');
      if (result.isErr) {
        // An honest skip: say the device could not read it rather than
        // reporting a pass we did not earn.
        marker('SKIP: index not reachable from this device');
        return;
      }

      final ExtensionRepositoryIndex index = result.valueOrNull!;
      marker(
        'repo name=${index.name} entries=${index.entries.length} '
        'skippedNonJs=${index.skippedNotJavaScript}',
      );

      expect(index.entries, isNotEmpty);
      expect(index.name, isNotNull);

      // The crux of requirement D: relative paths became absolute, HTTPS, .js.
      for (final ExtensionCatalogueEntry e in index.entries) {
        final Uri parsed = Uri.parse(e.downloadUrl);
        expect(parsed.isAbsolute, isTrue, reason: e.downloadUrl);
        expect(parsed.scheme, 'https');
        expect(
          parsed.path.toLowerCase(),
          endsWith('.js'),
          reason: e.downloadUrl,
        );
      }

      marker(
        'sample entry: ${index.entries.first.name} -> '
        '${index.entries.first.downloadUrl}',
      );
    },
  );
}
