import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/in_memory_extension_registry.dart';
import 'package:specta/core/extensions/manifest.dart';
import 'package:specta/core/extensions/verification/signature_verifier.dart';
import 'package:specta/core/extensions/verification/signing_protocol.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';

import '../../../support/fake_js_sandbox.dart';

/// 2G-C pre-flight §36.5: trust is re-classified from the FILE at load time.
///
/// Before the fix, `loadRuntime` re-read the file and re-derived CAPABILITIES
/// from it, but kept the import-time trust level — a file that changed after
/// import still ran under `official`. These tests pin the corrected behavior.
const String _body = '''
class Extension extends SpectaExtension {
  async search(query) { return []; }
}
''';

String _source({
  String id = 'com.example.signed',
  String name = 'Signed Extension',
  String capabilities = 'network,search',
  String? signature,
  String body = _body,
}) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('// ==SpectaExtension==')
    ..writeln('// @id $id')
    ..writeln('// @name $name')
    ..writeln('// @version 1.0.0')
    ..writeln('// @author Test Author')
    ..writeln('// @apiVersion 2')
    ..writeln('// @type movies_series');
  if (capabilities.isNotEmpty) {
    buffer.writeln('// @capabilities $capabilities');
  }
  if (signature != null) {
    buffer.writeln('// @signature $signature');
  }
  buffer
    ..writeln('// ==/SpectaExtension==')
    ..write(body);
  return buffer.toString();
}

Future<String> _sign(String source, KeyPair keyPair) async {
  final ExtensionManifest manifest = ManifestParser.parse(source);
  final List<int> payload = manifest.buildSignedPayload(
    extensionBody: ManifestParser.extractBody(source),
  );
  final Signature signature = await Ed25519().sign(payload, keyPair: keyPair);
  return source.replaceFirst(
    '// ==/SpectaExtension==',
    '// @signature '
        '${SpectaSigningProtocol.encodeSignature(signature.bytes)}\n'
        '// ==/SpectaExtension==',
  );
}

void main() {
  late Directory workspace;
  late InMemoryExtensionRegistry registry;
  late KeyPair keyPair;
  late ExtensionManager manager;
  late String filePath;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('specta_trust_test');
    registry = InMemoryExtensionRegistry();
    keyPair = await Ed25519().newKeyPair();
    manager = ExtensionManager(
      registry: registry,
      // A real (faked) API + sandbox: the enabled/configuration checks come
      // first in loadRuntime, so without these the load would return early
      // and never reach the trust re-check.
      runtimeApi: _LoadFakeApi(),
      sandboxFactory: FakeJsSandbox.new,
      verifier: SignatureVerifier.withPublicKey(
        (await (keyPair.extractPublicKey() as Future<SimplePublicKey>)).bytes,
      ),
    );
    filePath = '${workspace.path}${Platform.pathSeparator}ext.js';
  });

  tearDown(() async {
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  /// Imports a SIGNED extension from a real file (not from source), so the
  /// manager's record points at a file that can be modified afterwards.
  Future<ExtensionRecord> importSignedToFile({required String source}) async {
    await File(filePath).writeAsString(source, flush: true);
    final SpectaResult<ExtensionRecord> result = await manager.importExtension(
      filePath: filePath,
    );
    expect(result.isOk, isTrue, reason: result.failureOrNull?.message);
    return result.valueOrNull!;
  }

  /// Reads the persisted record + failure log after a load attempt.
  Future<(ExtensionRecord, List<ExtensionFailureRecord>)> state() async {
    final ExtensionRecord? record = await registry.getById(
      'com.example.signed',
    );
    final List<ExtensionFailureRecord> failures = await registry.getFailures(
      'com.example.signed',
    );
    return (record!, failures);
  }

  test('a tampered file downgrades the stored trust at load time', () async {
    // Import: official.
    final ExtensionRecord imported = await importSignedToFile(
      source: await _sign(_source(), keyPair),
    );
    expect(imported.trustLevel, TrustLevel.official);

    // Tamper AFTER import: the signature no longer covers this body.
    await File(filePath).writeAsString(
      (await File(filePath).readAsString()).replaceFirst(
        'return [];',
        'return []; // exfiltrate();',
      ),
      flush: true,
    );

    // Attempt a load. The runtime construction itself may fail (no API
    // configured in this test), but the trust re-check runs first and must
    // have downgraded the persisted record.
    await manager.loadRuntime('com.example.signed');

    final (ExtensionRecord record, List<ExtensionFailureRecord> failures) =
        await state();
    expect(
      record.trustLevel,
      TrustLevel.unverified,
      reason:
          'the file changed after import; stored "official" must not '
          'survive a load',
    );
    expect(
      failures.where(
        (ExtensionFailureRecord f) =>
            f.message.contains('Trust level re-classified'),
      ),
      isNotEmpty,
      reason: 'the divergence must be recorded, never silent',
    );
  });

  test('an untouched file keeps official through a load attempt', () async {
    final ExtensionRecord imported = await importSignedToFile(
      source: await _sign(_source(), keyPair),
    );
    expect(imported.trustLevel, TrustLevel.official);

    await manager.loadRuntime('com.example.signed');

    final (ExtensionRecord record, List<ExtensionFailureRecord> failures) =
        await state();
    expect(
      record.trustLevel,
      TrustLevel.official,
      reason: 'nothing changed; trust must not be downgraded spuriously',
    );
    expect(
      failures.where(
        (ExtensionFailureRecord f) =>
            f.message.contains('Trust level re-classified'),
      ),
      isEmpty,
    );
  });

  test('the failure record names both levels for diagnostics', () async {
    await importSignedToFile(source: await _sign(_source(), keyPair));
    await File(filePath).writeAsString(
      (await File(
        filePath,
      ).readAsString()).replaceFirst('return [];', 'return []; // tampered'),
      flush: true,
    );

    await manager.loadRuntime('com.example.signed');

    final (ExtensionRecord _, List<ExtensionFailureRecord> failures) =
        await state();
    final ExtensionFailureRecord? entry = failures
        .where(
          (ExtensionFailureRecord f) =>
              f.message.contains('Trust level re-classified'),
        )
        .firstOrNull;
    expect(entry, isNotNull);
    expect(entry!.message, contains('official'));
    expect(entry.message, contains('unverified'));
    expect(entry.operation, 'load');
  });
}

/// Minimal runtime API for load-flow tests: requests succeed, logs are
/// ignored. The trust re-check does not depend on either.
class _LoadFakeApi implements ExtensionRuntimeApi {
  @override
  Future<ExtensionResponse> request(ExtensionRequest request) async {
    return ExtensionResponse(status: 200, ok: true, body: '{}');
  }

  @override
  void log(ExtensionLogLevel level, String message) {}
}
