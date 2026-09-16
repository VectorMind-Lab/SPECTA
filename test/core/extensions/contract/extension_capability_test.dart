import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/contract/extension_capability.dart';

void main() {
  group('ExtensionCapability', () {
    test('is a closed vocabulary with no host-permission style entries', () {
      expect(
        ExtensionCapability.values
            .map((ExtensionCapability c) => c.code)
            .toList(),
        <String>[
          'network',
          'logging',
          'search',
          'latest',
          'details',
          'sources',
        ],
      );
      // Nothing in the vocabulary grants filesystem, contacts, SMS, photos,
      // device identifiers, database or arbitrary native code.
      for (final String forbidden in <String>[
        'filesystem',
        'contacts',
        'sms',
        'photos',
        'device_id',
        'database',
        'native',
      ]) {
        expect(ExtensionCapability.fromCode(forbidden), isNull);
      }
    });

    test('separates runtime capabilities from contract operations', () {
      expect(ExtensionCapability.network.isRuntimeCapability, isTrue);
      expect(ExtensionCapability.logging.isRuntimeCapability, isTrue);
      expect(ExtensionCapability.search.isRuntimeCapability, isFalse);
      expect(ExtensionCapability.sources.isRuntimeCapability, isFalse);
    });

    test('fromCode trims and ignores case', () {
      expect(
        ExtensionCapability.fromCode(' NETWORK '),
        ExtensionCapability.network,
      );
      expect(
        ExtensionCapability.fromCode('LoGgInG'),
        ExtensionCapability.logging,
      );
    });

    test('parseDeclaration accepts whitespace and mixed case', () {
      expect(
        ExtensionCapability.parseDeclaration(' network , LOGGING , search '),
        <ExtensionCapability>{
          ExtensionCapability.network,
          ExtensionCapability.logging,
          ExtensionCapability.search,
        },
      );
    });

    test('an empty or blank declaration means no capabilities', () {
      expect(ExtensionCapability.parseDeclaration(''), isEmpty);
      expect(ExtensionCapability.parseDeclaration('  ,  '), isEmpty);
    });

    test('an unrecognised token is rejected instead of silently dropped', () {
      // Silently narrowing the request would let an extension appear to hold
      // permissions it was never granted.
      expect(ExtensionCapability.parseDeclaration('network,bogus'), isNull);
      expect(ExtensionCapability.parseDeclaration('filesystem'), isNull);
    });

    test('encodeDeclaration is stable and sorted', () {
      expect(
        ExtensionCapability.encodeDeclaration(<ExtensionCapability>{
          ExtensionCapability.sources,
          ExtensionCapability.network,
          ExtensionCapability.logging,
        }),
        'logging,network,sources',
      );
      expect(
        ExtensionCapability.encodeDeclaration(const <ExtensionCapability>{}),
        '',
      );
    });
  });

  group('capabilityDeniedFailure', () {
    test('is a structured CapabilityFailure carrying the capability name', () {
      final CapabilityFailure failure = capabilityDeniedFailure(
        extensionId: 'com.example.a',
        capability: ExtensionCapability.network,
        operation: 'search',
      );

      expect(failure.extensionId, 'com.example.a');
      expect(failure.capability, 'network');
      expect(failure.message, contains('network'));
      expect(failure.message, contains('search'));
      // Not retryable: retrying cannot make an undeclared capability declared.
      expect(failure.isRetryable, isFalse);
    });
  });
}
