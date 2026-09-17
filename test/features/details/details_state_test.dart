import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart' as t;

import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/metadata/metadata_manager.dart';
import 'package:specta/features/details/details_state.dart';

import '../../support/discovery_test_harness.dart';

String _moviePayload(String url) => jsonEncode(<String, Object?>{
      'id': 'm1',
      'title': 'Test Movie',
      'type': 'movie',
      'url': url,
      'year': 2020,
    });

DiscoveryItem _movieItem(String extensionId, String url) => DiscoveryItem(
      key: 'test|movie|2020',
      title: 'Test Movie',
      type: MediaType.movie,
      year: 2020,
      references: <DiscoveryReference>[
        DiscoveryReference(extensionId: extensionId, url: url),
      ],
    );

Future<void> _waitFor(
  bool Function() test, {
  String reason = 'condition not met in time',
}) async {
  final Stopwatch sw = Stopwatch()..start();
  while (!test()) {
    if (sw.elapsed > const Duration(seconds: 5)) {
      t.fail(reason);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

ProviderContainer _container(DiscoveryTestHarness h) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      metadataServiceProvider.overrideWith(
        (Ref ref) => MetadataService(manager: h.manager),
      ),
    ],
  );
  t.addTearDown(container.dispose);
  return container;
}

void main() {
  late Directory tempDir;

  t.setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('specta_details_state');
    t.addTearDown(() => tempDir.delete(recursive: true));
  });

  t.group('DetailsSessionNotifier — statuses', () {
    t.test('starts idle', () {
      final ProviderContainer container = _container(DiscoveryTestHarness());
      t.expect(
        container.read(detailsSessionProvider).status,
        DetailsStatus.idle,
      );
    });

    t.test('successful open ends in success with canonical metadata',
        () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,details');
      const String url = 'https://example.com/movie/1';
      h.sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.details("$url"))',
        _moviePayload(url),
      );

      final ProviderContainer container = _container(h);
      await container
          .read(detailsSessionProvider.notifier)
          .open(_movieItem('extA', url));

      final DetailsState state = container.read(detailsSessionProvider);
      t.expect(state.status, DetailsStatus.success);
      t.expect(state.metadata, t.isNotNull);
      t.expect(state.metadata!.title, 'Test Movie');
      t.expect(state.metadata!.details.single.extensionId, 'extA');
      t.expect(state.isPartial, t.isFalse);
    });

    t.test('open shows discovery data immediately while loading', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,details');
      const String url = 'https://example.com/movie/1';
      h.sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.details("$url"))',
        _moviePayload(url),
      );
      h.sandbox.delay = const Duration(milliseconds: 120);

      final ProviderContainer container = _container(h);
      final Future<void> opening = container
          .read(detailsSessionProvider.notifier)
          .open(_movieItem('extA', url));

      await _waitFor(
        () => container.read(detailsSessionProvider).status ==
            DetailsStatus.loading,
        reason: 'loading state never appeared',
      );
      final DetailsState loading = container.read(detailsSessionProvider);
      // Discovery-observed data is available during loading; nothing invented.
      t.expect(loading.item!.title, 'Test Movie');
      t.expect(loading.metadata, t.isNull);

      await opening;
      t.expect(container.read(detailsSessionProvider).status,
          DetailsStatus.success);
    });

    t.test('all references failing ends in failure with reference ids',
        () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,details');
      const String url = 'https://example.com/movie/1';
      h.sandbox.setAsyncError(
        'JSON.stringify(await _spectaInstance.details("$url"))',
        'down',
      );

      final ProviderContainer container = _container(h);
      await container
          .read(detailsSessionProvider.notifier)
          .open(_movieItem('extA', url));

      final DetailsState state = container.read(detailsSessionProvider);
      t.expect(state.status, DetailsStatus.failure);
      t.expect(state.metadata, t.isNull);
      t.expect(state.failedReferences, <String>['extA']);
    });

    t.test('one reference failing among two is an honest partial success',
        () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,details');
      await h.installExtension(tempDir, 'extB', capabilities: 'search,details');

      const String urlA = 'https://example.com/a/movie/1';
      const String urlB = 'https://example.com/b/movie/1';
      h.sandbox.setAsyncError(
        'JSON.stringify(await _spectaInstance.details("$urlA"))',
        'down',
      );
      h.sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.details("$urlB"))',
        _moviePayload(urlB),
      );

      final DiscoveryItem item = DiscoveryItem(
        key: 'test|movie|2020',
        title: 'Test Movie',
        type: MediaType.movie,
        year: 2020,
        references: <DiscoveryReference>[
          const DiscoveryReference(extensionId: 'extA', url: urlA),
          const DiscoveryReference(extensionId: 'extB', url: urlB),
        ],
      );

      final ProviderContainer container = _container(h);
      await container.read(detailsSessionProvider.notifier).open(item);

      final DetailsState state = container.read(detailsSessionProvider);
      t.expect(state.status, DetailsStatus.success);
      t.expect(state.isPartial, t.isTrue);
      t.expect(state.failedReferences, t.contains('extA'));
      t.expect(state.metadata!.details.single.extensionId, 'extB');
    });

    t.test('reset returns to idle and rejects in-flight requests', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,details');
      const String url = 'https://example.com/movie/1';
      h.sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.details("$url"))',
        _moviePayload(url),
      );
      h.sandbox.delay = const Duration(milliseconds: 120);

      final ProviderContainer container = _container(h);
      final Future<void> opening = container
          .read(detailsSessionProvider.notifier)
          .open(_movieItem('extA', url));
      await _waitFor(
        () => container.read(detailsSessionProvider).status ==
            DetailsStatus.loading,
        reason: 'loading state never appeared',
      );

      container.read(detailsSessionProvider.notifier).reset();
      t.expect(
        container.read(detailsSessionProvider).status,
        DetailsStatus.idle,
      );

      await opening;
      // The stale response must not have overwritten the idle reset.
      t.expect(
        container.read(detailsSessionProvider).status,
        DetailsStatus.idle,
      );
    });

    t.test('a stale slow open cannot overwrite a newer open (A then B)',
        () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      await h.installExtension(tempDir, 'extA', capabilities: 'search,details');
      await h.installExtension(tempDir, 'extB', capabilities: 'search,details');

      const String urlA = 'https://example.com/a/movie/1';
      const String urlB = 'https://example.com/b/movie/1';

      // A responds slowly with a DISTINCT title; B responds fast.
      final String payloadA = jsonEncode(<String, Object?>{
        'id': 'mA',
        'title': 'Slow Movie A',
        'type': 'movie',
        'url': urlA,
      });
      final String payloadB = jsonEncode(<String, Object?>{
        'id': 'mB',
        'title': 'Fast Movie B',
        'type': 'movie',
        'url': urlB,
      });

      h.sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.details("$urlA"))',
        payloadA,
      );
      h.sandbox.setAsyncResult(
        'JSON.stringify(await _spectaInstance.details("$urlB"))',
        payloadB,
      );
      h.sandbox.delay = const Duration(milliseconds: 150);

      final ProviderContainer container = _container(h);
      final DetailsSessionNotifier notifier =
          container.read(detailsSessionProvider.notifier);

      final Future<void> openA = notifier.open(_movieItem('extA', urlA));
      await _waitFor(
        () => container.read(detailsSessionProvider).status ==
            DetailsStatus.loading,
        reason: 'A never reached loading',
      );
      h.sandbox.delay = Duration.zero; // B answers immediately

      await notifier.open(_movieItem('extB', urlB));
      await openA; // A lands late — must be rejected

      final DetailsState state = container.read(detailsSessionProvider);
      t.expect(state.status, DetailsStatus.success);
      t.expect(state.metadata!.title, 'Fast Movie B');
    });
  });
}
