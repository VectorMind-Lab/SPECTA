import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/discovery/discovery_coordinator.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart'
    show JsEvalException;

import '../../support/discovery_test_harness.dart';

/// Phase 2K: the Home feed is a `latest(page)` discovery round. These tests pin
/// that it is the SAME pipeline as search — capability-gated, isolated per
/// extension, normalized and deduplicated — and that it is a first-class Core
/// path rather than something the Home surface fakes.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('specta_latest');
    addTearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } on Object catch (_) {}
    });
  });

  test('no enabled extensions yields an empty round, not an error', () async {
    final DiscoveryTestHarness h = DiscoveryTestHarness();

    final DiscoveryResult result = await DiscoveryCoordinator.latest(
      page: 1,
      manager: h.manager,
    );

    expect(result.items, isEmpty);
    expect(result.outcomes, isEmpty);
    expect(result.page, 1);
  });

  test('an extension without the latest capability is skipped', () async {
    final DiscoveryTestHarness h = DiscoveryTestHarness();
    await h.installExtension(
      tempDir,
      'com.test.searchonly',
      capabilities: 'search',
    );

    final DiscoveryResult result = await DiscoveryCoordinator.latest(
      page: 1,
      manager: h.manager,
    );

    expect(result.items, isEmpty);
    expect(result.outcomes.single.isSkipped, isTrue);
  });

  test('latest-capable extensions contribute deduplicated items', () async {
    final DiscoveryTestHarness h =
        DiscoveryTestHarness(sandbox: ScriptedJsSandbox());
    await h.installExtension(tempDir, 'com.test.a');
    (h.sandbox as ScriptedJsSandbox).latestScripts = <Object>[
      searchPayload(<Map<String, Object?>>[
        <String, Object?>{
          'title': 'Shared Title',
          'url': 'https://latest.test/1',
          'type': 'movie',
          'year': 1999,
        },
        <String, Object?>{
          'title': 'Only Here',
          'url': 'https://latest.test/2',
          'type': 'series',
        },
      ]),
    ];

    final DiscoveryResult result = await DiscoveryCoordinator.latest(
      page: 1,
      manager: h.manager,
    );

    expect(result.outcomes.single.isSuccess, isTrue);
    expect(
      result.items.map((DiscoveryItem i) => i.title).toList(),
      <String>['Shared Title', 'Only Here'],
    );
    expect(
      (h.sandbox as ScriptedJsSandbox).latestCallCount,
      1,
      reason: 'exactly one latest call per participating extension',
    );
  });

  test('the same work from two extensions deduplicates into ONE item',
      () async {
    final DiscoveryTestHarness h =
        DiscoveryTestHarness(sandbox: ScriptedJsSandbox());
    await h.installExtension(tempDir, 'com.test.a');
    await h.installExtension(tempDir, 'com.test.b');
    final ScriptedJsSandbox sandbox = h.sandbox as ScriptedJsSandbox;
    // Both extensions answer with the same work (different provider URLs).
    sandbox.latestScripts = <Object>[
      searchPayload(<Map<String, Object?>>[
        <String, Object?>{
          'title': 'Same Work',
          'url': 'https://a.test/x',
          'type': 'movie',
          'year': 2001,
        },
      ]),
      searchPayload(<Map<String, Object?>>[
        <String, Object?>{
          'title': 'Same Work',
          'url': 'https://b.test/y',
          'type': 'movie',
          'year': 2001,
        },
      ]),
    ];

    final DiscoveryResult result = await DiscoveryCoordinator.latest(
      page: 1,
      manager: h.manager,
    );

    expect(result.items.length, 1);
    // Both extensions are recorded as having found it (provenance is kept).
    expect(result.items.single.references.length, 2);
  });

  test('one failing extension does not fail the round', () async {
    final DiscoveryTestHarness h =
        DiscoveryTestHarness(sandbox: ScriptedJsSandbox());
    await h.installExtension(tempDir, 'com.test.good');
    await h.installExtension(tempDir, 'com.test.bad');
    final ScriptedJsSandbox sandbox = h.sandbox as ScriptedJsSandbox;
    sandbox.latestScripts = <Object>[
      searchPayload(<Map<String, Object?>>[
        <String, Object?>{
          'title': 'Survivor',
          'url': 'https://ok.test/1',
          'type': 'movie',
        },
      ]),
      JsEvalException('secret internal detail'),
    ];

    final DiscoveryResult result = await DiscoveryCoordinator.latest(
      page: 1,
      manager: h.manager,
    );

    expect(
      result.items.map((DiscoveryItem i) => i.title).toList(),
      <String>['Survivor'],
    );
    expect(
      result.outcomes.where((ExtensionDiscoveryOutcome o) => o.isFailed).length,
      1,
    );
    // The failure is a controlled SPECTA failure, never a raw JS exception.
    final ExtensionDiscoveryOutcome failed =
        result.outcomes.firstWhere((ExtensionDiscoveryOutcome o) => o.isFailed);
    expect(failed.failure, isA<ExtensionFailure>());
    expect(
      (failed.failure! as ExtensionFailure).message.contains('secret'),
      isFalse,
    );
  });

  test('a hung extension is isolated by the coordinator timeout', () async {
    final DiscoveryTestHarness h =
        DiscoveryTestHarness(sandbox: ScriptedJsSandbox());
    await h.installExtension(tempDir, 'com.test.slow');
    final ScriptedJsSandbox sandbox = h.sandbox as ScriptedJsSandbox;
    sandbox.latestScripts = <Object>[searchPayload(const <Object?>[])];
    sandbox.hangDuration = const Duration(milliseconds: 300);
    sandbox.hangOnCallIndices = <int>{0};

    final DiscoveryResult result = await DiscoveryCoordinator.latest(
      page: 1,
      manager: h.manager,
      perExtensionTimeoutOverride: const Duration(milliseconds: 40),
    );

    expect(result.items, isEmpty);
    final ExtensionDiscoveryOutcome outcome = result.outcomes.single;
    expect(outcome.isFailed, isTrue);
    expect(
      (outcome.failure! as ExtensionFailure).type,
      ExtensionFailureType.timeout,
    );
  });

  test('the operation recorded on the failure is latest, not search', () async {
    final DiscoveryTestHarness h =
        DiscoveryTestHarness(sandbox: ScriptedJsSandbox());
    await h.installExtension(tempDir, 'com.test.broken');
    (h.sandbox as ScriptedJsSandbox).latestScripts = <Object>[
      JsEvalException('boom'),
    ];

    final DiscoveryResult result = await DiscoveryCoordinator.latest(
      page: 3,
      manager: h.manager,
    );

    expect(result.page, 3);
    final ExtensionFailure failure =
        result.outcomes.single.failure! as ExtensionFailure;
    expect(failure.operation, 'latest');
  });

  test('malformed rows never reach the aggregate; valid rows survive',
      () async {
    final DiscoveryTestHarness h =
        DiscoveryTestHarness(sandbox: ScriptedJsSandbox());
    await h.installExtension(tempDir, 'com.test.mixed');
    (h.sandbox as ScriptedJsSandbox).latestScripts = <Object>[
      searchPayload(<Object?>[
        'not an object',
        <String, Object?>{'title': 'No URL'},
        <String, Object?>{
          'title': 'Valid',
          'url': 'https://mixed.test/1',
          'type': 'movie',
        },
      ]),
    ];

    final DiscoveryResult result = await DiscoveryCoordinator.latest(
      page: 1,
      manager: h.manager,
    );

    expect(
      result.items.map((DiscoveryItem i) => i.title).toList(),
      <String>['Valid'],
    );
    // The RUNTIME's result parser is the layer that refuses entries without a
    // title/url (Phase 2B contract), so they never reach the normalizer — the
    // coordinator's own drop counter therefore stays zero. Asserting the item
    // list above is the meaningful guarantee; a non-zero droppedCount here
    // would mean a row survived the parser and was then rejected later.
    expect(result.droppedCount, 0);
  });
}
