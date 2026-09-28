import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/app/platform/file_picker.dart';

/// Guards the wire contract between Dart and `MainActivity.kt`.
///
/// These two channel names once drifted (native `net.specta.app/file_picker`,
/// Dart `net.specta.app.file_picker`). The only visible symptom on hardware was
/// the UI reporting "browsing is not available on this device", so the whole
/// Android import path looked dead even though SAF works perfectly.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The literal `MainActivity.kt` registers as `FILE_PICKER_CHANNEL`.
  const String nativeChannelName = 'net.specta.app/file_picker';

  /// The name it wrongly used before, kept so the regression is explicit.
  const String driftedChannelName = 'net.specta.app.file_picker';

  final List<MethodCall> calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(nativeChannelName), (
          MethodCall call,
        ) async {
          calls.add(call);
          // A distinctive error, so the Dart side proves it reached a handler
          // instead of getting MissingPluginException.
          throw PlatformException(
            code: 'copy_failed',
            message: 'native reached',
          );
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(nativeChannelName), null);
  });

  test('the Dart channel name is the native FILE_PICKER_CHANNEL literal', () {
    expect(nativeChannelName, 'net.specta.app/file_picker');
    expect(nativeChannelName, isNot(driftedChannelName));
  });

  test(
    'picking reaches the native handler instead of MissingPluginException',
    () async {
      final FilePickResult result = await const PlatformFilePicker().pick();

      // A name mismatch yields FilePickUnsupported, which the UI renders as
      // "browsing is not available on this device".
      expect(result, isA<FilePickFailed>());
      expect(result, isNot(isA<FilePickUnsupported>()));
      expect(calls.single.method, 'pickFile');
      expect(
        (calls.single.arguments as Map<Object?, Object?>)['mimeTypes'],
        isA<List<Object?>>(),
      );
    },
  );

  test('a native cancel is reported as cancelled, not as a failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(nativeChannelName),
          (MethodCall call) async => null,
        );

    expect(await const PlatformFilePicker().pick(), isA<FilePickCancelled>());
  });

  test(
    'an unreadable native reply fails loudly rather than silently',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(nativeChannelName),
            (MethodCall call) async => 'not-a-map',
          );

      expect(await const PlatformFilePicker().pick(), isA<FilePickFailed>());
    },
  );
}
