import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/discovery/discovery_coordinator.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/features/home/home_feed.dart';

import '../../support/discovery_test_harness.dart';

SearchResult _movie(String title, String url, {int? year}) =>
    SearchResult(title: title, url: url, type: MediaType.movie, year: year);

ExtensionFailure _failure() => ExtensionFailure(
  extensionId: 'com.test.a',
  operation: 'latest',
  type: ExtensionFailureType.runtimeError,
  message: 'boom',
  timestamp: DateTime.utc(2026),
);

DiscoveryResult _result(List<ExtensionDiscoveryOutcome> outcomes) =>
    DiscoveryResult(
      items: outcomes
          .where((ExtensionDiscoveryOutcome o) => o.isSuccess)
          .expand(
            (ExtensionDiscoveryOutcome o) => o.results.map(
              (SearchResult r) => DiscoveryItem(
                key: r.title,
                title: r.title,
                type: MediaType.movie,
                references: <DiscoveryReference>[
                  DiscoveryReference(extensionId: o.extensionId, url: r.url),
                ],
              ),
            ),
          )
          .toList(growable: false),
      outcomes: outcomes,
      droppedCount: 0,
      page: 1,
    );

void main() {
  group('HomeFeed — classification', () {
    test('a round with items is ready and not partial', () {
      final HomeFeed feed = HomeFeed.from(
        _result(<ExtensionDiscoveryOutcome>[
          ExtensionDiscoveryOutcome.success('com.test.a', <SearchResult>[
            _movie('A', 'https://x/1'),
          ]),
        ]),
      );

      expect(feed.status, HomeFeedStatus.ready);
      expect(feed.items.length, 1);
      expect(feed.isPartial, isFalse);
      expect(feed.hasItems, isTrue);
    });

    test('items plus a failed extension is ready AND partial', () {
      final HomeFeed feed = HomeFeed.from(
        _result(<ExtensionDiscoveryOutcome>[
          ExtensionDiscoveryOutcome.success('com.test.a', <SearchResult>[
            _movie('A', 'https://x/1'),
          ]),
          ExtensionDiscoveryOutcome.failed('com.test.b', _failure()),
        ]),
      );

      expect(feed.status, HomeFeedStatus.ready);
      expect(feed.isPartial, isTrue);
      expect(feed.failedCount, 1);
    });

    test('no outcomes at all means no extensions are installed', () {
      final HomeFeed feed = HomeFeed.from(
        _result(const <ExtensionDiscoveryOutcome>[]),
      );

      expect(feed.status, HomeFeedStatus.noExtensions);
      expect(feed.message, isNotEmpty);
    });

    test('every outcome skipped means no extension provides a Home feed', () {
      final HomeFeed feed = HomeFeed.from(
        _result(<ExtensionDiscoveryOutcome>[
          ExtensionDiscoveryOutcome.skipped('com.test.a'),
          ExtensionDiscoveryOutcome.skipped('com.test.b'),
        ]),
      );

      expect(feed.status, HomeFeedStatus.unsupported);
      expect(feed.message, contains('Search'));
    });

    test('every outcome failed is reported as unreachable', () {
      final HomeFeed feed = HomeFeed.from(
        _result(<ExtensionDiscoveryOutcome>[
          ExtensionDiscoveryOutcome.failed('com.test.a', _failure()),
        ]),
      );

      expect(feed.status, HomeFeedStatus.failure);
      expect(feed.message, contains('could not be reached'));
    });

    test('a success with zero items is empty, not a failure', () {
      final HomeFeed feed = HomeFeed.from(
        _result(<ExtensionDiscoveryOutcome>[
          ExtensionDiscoveryOutcome.success(
            'com.test.a',
            const <SearchResult>[],
          ),
        ]),
      );

      expect(feed.status, HomeFeedStatus.empty);
      expect(feed.message, contains('Nothing new'));
    });

    test(
      'mixed empty success and failure stays empty but counts the failure',
      () {
        final HomeFeed feed = HomeFeed.from(
          _result(<ExtensionDiscoveryOutcome>[
            ExtensionDiscoveryOutcome.success(
              'com.test.a',
              const <SearchResult>[],
            ),
            ExtensionDiscoveryOutcome.failed('com.test.b', _failure()),
          ]),
        );

        expect(feed.status, HomeFeedStatus.empty);
        expect(feed.failedCount, 1);
      },
    );

    test('every non-ready status carries a real explanation', () {
      for (final HomeFeedStatus status in HomeFeedStatus.values) {
        final HomeFeed feed = HomeFeed(status: status);
        expect(
          feed.message.isEmpty,
          status == HomeFeedStatus.ready,
          reason: 'status $status',
        );
      }
    });
  });

  group('homeFeedProvider', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('specta_home_feed');
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } on Object catch (_) {}
      });
    });

    test('runs a real latest round over the enabled extensions', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness(
        sandbox: ScriptedJsSandbox(),
      );
      await h.installExtension(tempDir, 'com.test.home');
      (h.sandbox as ScriptedJsSandbox).latestScripts = <Object>[
        searchPayload(<Map<String, Object?>>[
          <String, Object?>{
            'title': 'Home Feed Title',
            'url': 'https://home.test/1',
            'type': 'movie',
            'year': 2003,
          },
        ]),
      ];

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          discoveryServiceProvider.overrideWith(
            (Ref ref) => DiscoveryService(manager: h.manager),
          ),
        ],
      );
      addTearDown(container.dispose);

      final HomeFeed feed = await container.read(homeFeedProvider.future);

      expect(feed.status, HomeFeedStatus.ready);
      expect(feed.items.single.title, 'Home Feed Title');
      expect(feed.items.single.year, 2003);
    });

    test('no extensions resolves to the honest noExtensions state', () async {
      final DiscoveryTestHarness h = DiscoveryTestHarness();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          discoveryServiceProvider.overrideWith(
            (Ref ref) => DiscoveryService(manager: h.manager),
          ),
        ],
      );
      addTearDown(container.dispose);

      final HomeFeed feed = await container.read(homeFeedProvider.future);

      expect(feed.status, HomeFeedStatus.noExtensions);
      expect(feed.items, isEmpty);
    });
  });
}
