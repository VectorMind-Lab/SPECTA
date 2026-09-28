@TestOn('vm')
library;

import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/drift_extension_registry.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manifest.dart';
import 'package:specta/core/extensions/runtime/extension_runtime.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';
import 'package:specta/core/extensions/verification/signature_verifier.dart';
import 'package:specta/core/extensions/verification/signing_protocol.dart';

import '../../../support/fake_js_sandbox.dart';

/// Proves the Phase 2H persistence guarantee with a REAL on-disk SQLite file:
/// installed extensions, their enable/disable state and their trust
/// classification must all survive closing and reopening the database — which
/// is what an application restart does.
///
/// Each "process" is represented by a fresh [SpectaDatabase] opened over the
/// same file, a fresh registry and a fresh manager. Nothing is cached between
/// them.

void main() {
  late Directory dir;
  late File dbFile;
  late KeyPair keyPair;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('specta_ext_restart');
    dbFile = File('${dir.path}/specta.sqlite');
    keyPair = await Ed25519().newKeyPair();
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on Object catch (_) {
      // Windows may briefly hold a file handle; cleanup must not fail a test.
    }
  });

  /// Opens a fresh database over the shared file and wires a real manager over
  /// it, bound to the throwaway signing key generated for this test.
  Future<_App> startApp() async {
    final SpectaDatabase database = SpectaDatabase(NativeDatabase(dbFile));
    final SimplePublicKey publicKey =
        await keyPair.extractPublicKey() as SimplePublicKey;
    final ExtensionManager manager = ExtensionManager(
      registry: DriftExtensionRegistry(database),
      runtimeApi: _NoopRuntimeApi(),
      sandboxFactory: FakeJsSandbox.new,
      verifier: SignatureVerifier.withPublicKey(publicKey.bytes),
    );
    return _App(database: database, manager: manager);
  }

  Future<File> writeFile(String name, String source) async {
    final File file = File('${dir.path}/$name');
    await file.writeAsString(source);
    return file;
  }

  test(
    'installed extensions, enable/disable state and trust survive a restart',
    () async {
      // --- First "process": install, verify trust, disable one extension. ---
      final _App first = await startApp();

      final File signedFile = await writeFile(
        'signed.js',
        await _signedSource(keyPair),
      );
      final File plainFile = await writeFile(
        'plain.js',
        _source(id: 'com.test.plain', name: 'Plain Extension'),
      );

      final SpectaResult<ExtensionRecord> signedInstall = await first.manager
          .importExtension(filePath: signedFile.path);
      final SpectaResult<ExtensionRecord> plainInstall = await first.manager
          .importExtension(filePath: plainFile.path);

      expect(
        signedInstall.isOk,
        isTrue,
        reason: signedInstall.failureOrNull?.message,
      );
      expect(
        plainInstall.isOk,
        isTrue,
        reason: plainInstall.failureOrNull?.message,
      );
      expect(signedInstall.valueOrNull!.trustLevel, TrustLevel.official);
      expect(plainInstall.valueOrNull!.trustLevel, TrustLevel.unverified);

      await first.manager.setEnabled('com.test.plain', false);
      await first.manager.shutdownAll();
      await first.database.close();

      // --- Second "process": reopen the same database file. ---
      final _App second = await startApp();

      final ExtensionRecord? signedRecord = await second.manager.getExtension(
        'com.test.signed',
      );
      final ExtensionRecord? plainRecord = await second.manager.getExtension(
        'com.test.plain',
      );

      expect(signedRecord, isNotNull);
      expect(plainRecord, isNotNull);
      expect(signedRecord!.trustLevel, TrustLevel.official);
      expect(plainRecord!.trustLevel, TrustLevel.unverified);
      expect(signedRecord.enabled, isTrue);
      expect(
        plainRecord.enabled,
        isFalse,
        reason: 'the disabled flag must survive the restart',
      );
      expect(signedRecord.version, '1.0.0');
      expect(signedRecord.author, 'SPECTA Tests');

      // The enabled view excludes the extension the user switched off.
      final List<ExtensionRecord> enabled = await second.manager
          .getEnabledExtensions();
      expect(enabled.length, 1);
      expect(enabled.single.id, 'com.test.signed');

      // A disabled extension stays unusable after the restart.
      final SpectaResult<ExtensionRuntime> disabledLoad = await second.manager
          .loadRuntime('com.test.plain');
      expect(disabledLoad.isErr, isTrue);

      // The trusted extension loads, and its trust is RE-DERIVED from the file
      // on disk — still Official, so the reconstruction is genuine and not a
      // stale copy of the stored value.
      final SpectaResult<ExtensionRuntime> signedLoad = await second.manager
          .loadRuntime('com.test.signed');
      expect(
        signedLoad.isOk,
        isTrue,
        reason: signedLoad.failureOrNull?.message,
      );
      expect(
        (await second.manager.getExtension('com.test.signed'))!.trustLevel,
        TrustLevel.official,
      );

      await second.manager.shutdownAll();
      await second.database.close();
    },
  );

  test('a malformed file never becomes a persisted extension', () async {
    final _App first = await startApp();
    final File broken = await writeFile('broken.js', 'not a manifest at all');
    final SpectaResult<ExtensionRecord> result = await first.manager
        .importExtension(filePath: broken.path);
    expect(result.isErr, isTrue);
    await first.database.close();

    final _App second = await startApp();
    expect(await second.manager.getAllExtensions(), isEmpty);
    await second.database.close();
  });

  test('reinstalling after a restart keeps the extension disabled', () async {
    final _App first = await startApp();
    final File file = await writeFile(
      'dup.js',
      _source(id: 'com.test.dup', name: 'Dup'),
    );
    await first.manager.importExtension(filePath: file.path);
    await first.manager.setEnabled('com.test.dup', false);
    await first.database.close();

    final _App second = await startApp();
    await second.manager.importExtension(filePath: file.path);

    expect(
      (await second.manager.getExtension('com.test.dup'))!.enabled,
      isFalse,
    );
    await second.database.close();
  });
}

/// A database + manager pair representing one application process.
final class _App {
  const _App({required this.database, required this.manager});

  final SpectaDatabase database;
  final ExtensionManager manager;
}

String _source({
  String id = 'com.test.signed',
  String name = 'Signed Extension',
  String version = '1.0.0',
  String capabilities = 'search,details,sources',
  String? signature,
  String body = 'class Extension extends SpectaExtension {}',
}) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('// ==SpectaExtension==')
    ..writeln('// @id $id')
    ..writeln('// @name $name')
    ..writeln('// @version $version')
    ..writeln('// @author SPECTA Tests')
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

/// Signs the source exactly as an external signing tool would, with a throwaway
/// key pair generated per test. No production key is involved.
Future<String> _signedSource(KeyPair keyPair) async {
  final String source = _source();
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

/// A no-op host API: these tests load runtimes but never make requests.
class _NoopRuntimeApi implements ExtensionRuntimeApi {
  @override
  Future<ExtensionResponse> request(ExtensionRequest request) async =>
      const ExtensionResponse(status: 200, ok: true, body: '{}');

  @override
  void log(ExtensionLogLevel level, String message) {}
}
