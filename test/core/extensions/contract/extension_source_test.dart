import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/contract/extension_source.dart';

/// Pins the V1 source model: MP4 and HLS only, machine-readable type codes, and
/// a tolerant parser for the optional metadata extensions may omit.
void main() {
  group('SourceType', () {
    test('declares only the V1 playback scope', () {
      // DASH is deliberately absent from V1. Adding it here is a scope
      // decision, so this test fails loudly rather than silently widening it.
      expect(SourceType.values.map((SourceType t) => t.code).toList(), <String>[
        'mp4',
        'hls',
      ]);
    });

    test('fromCode is case-insensitive and rejects unknown types', () {
      expect(SourceType.fromCode('MP4'), SourceType.mp4);
      expect(SourceType.fromCode('Hls'), SourceType.hls);
      expect(SourceType.fromCode('dash'), isNull);
      expect(SourceType.fromCode('mkv'), isNull);
    });
  });

  group('ExtensionSource', () {
    test('parses the optional metadata an extension may provide', () {
      final ExtensionSource source = ExtensionSource.fromJson(<String, dynamic>{
        'url': 'https://cdn.example.com/a.m3u8',
        'type': 'hls',
        'quality': '1080p',
        'label': 'Server 1',
        'isAdaptive': true,
        'headers': <String, dynamic>{'referer': 'https://example.com'},
        'audioTracks': <Map<String, dynamic>>[
          <String, dynamic>{'language': 'en', 'label': 'English'},
        ],
        'subtitles': <Map<String, dynamic>>[
          <String, dynamic>{
            'url': 'https://cdn.example.com/en.vtt',
            'language': 'en',
          },
        ],
      });

      expect(source.type, SourceType.hls);
      expect(source.url, 'https://cdn.example.com/a.m3u8');
      expect(source.quality, '1080p');
      expect(source.label, 'Server 1');
      expect(source.isAdaptive, isTrue);
      expect(source.headers, <String, String>{
        'referer': 'https://example.com',
      });
      expect(source.audioTracks!.single.label, 'English');
      expect(source.subtitles!.single.url, 'https://cdn.example.com/en.vtt');
    });

    test('tolerates an extension that omits every optional field', () {
      final ExtensionSource source = ExtensionSource.fromJson(<String, dynamic>{
        'url': 'https://cdn.example.com/a.mp4',
        'type': 'mp4',
      });

      expect(source.quality, isNull);
      expect(source.label, isNull);
      expect(source.isAdaptive, isFalse);
      expect(source.headers, isNull);
      expect(source.audioTracks, isNull);
      expect(source.subtitles, isNull);
    });

    test('rejects a DASH source as out of V1 scope', () {
      expect(
        () => ExtensionSource.fromJson(<String, dynamic>{
          'url': 'https://cdn.example.com/a.mpd',
          'type': 'dash',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an unknown source type', () {
      expect(
        () => ExtensionSource.fromJson(<String, dynamic>{
          'url': 'https://cdn.example.com/a.mkv',
          'type': 'mkv',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('toJson round-trips through fromJson', () {
      const ExtensionSource original = ExtensionSource(
        url: 'https://cdn.example.com/a.mp4',
        type: SourceType.mp4,
        quality: '720p',
        label: 'Server 2',
        headers: <String, String>{'user-agent': 'SPECTA'},
      );

      final ExtensionSource restored = ExtensionSource.fromJson(
        original.toJson(),
      );

      expect(restored.url, original.url);
      expect(restored.type, original.type);
      expect(restored.quality, original.quality);
      expect(restored.label, original.label);
      expect(restored.headers, original.headers);
    });
  });
}
