import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/contract/extension_source.dart';
import 'package:specta/core/sources/source_models.dart';
import 'package:specta/core/sources/source_pool.dart';
import 'package:specta/core/sources/source_ranker.dart';

RankedSource _cand(
  String url, {
  String? quality,
  SourceType type = SourceType.mp4,
  bool adaptive = false,
  String extensionId = 'extA',
}) => RankedSource(
  source: ExtensionSource(
    url: url,
    type: type,
    quality: quality,
    isAdaptive: adaptive,
  ),
  extensionId: extensionId,
  reference: 'ref',
  score: 0,
);

void main() {
  group('SourceRanker — quality preference', () {
    test('exact preference match beats higher quality (not highest-first)', () {
      final List<RankedSource> ranked = SourceRanker.rank(<RankedSource>[
        _cand('https://a/4k', quality: '4K'),
        _cand('https://a/1080', quality: '1080p'),
        _cand('https://a/720', quality: '720p'),
      ], QualityPreference.p720);

      expect(ranked.first.source.url, 'https://a/720');
    });

    test('near quality beats far quality deterministically', () {
      final List<RankedSource> ranked = SourceRanker.rank(<RankedSource>[
        _cand('https://a/480', quality: '480p'),
        _cand('https://a/1080', quality: '1080p'),
      ], QualityPreference.p720);

      expect(ranked.first.source.url, 'https://a/1080');
    });

    test('auto prefers higher native quality', () {
      final List<RankedSource> ranked = SourceRanker.rank(<RankedSource>[
        _cand('https://a/480', quality: '480p'),
        _cand('https://a/1080', quality: '1080p'),
      ], QualityPreference.auto);

      expect(ranked.first.source.url, 'https://a/1080');
    });

    test(
      'missing quality is never ranked above a known resolution under auto',
      () {
        final List<RankedSource> ranked = SourceRanker.rank(<RankedSource>[
          _cand('https://a/unknown', quality: null),
          _cand('https://a/480', quality: '480p'),
        ], QualityPreference.auto);

        expect(ranked.first.source.url, 'https://a/480');
        // And the unknown candidate is still usable (not discarded).
        expect(ranked, hasLength(2));
      },
    );

    test(
      'under a concrete preference, unknown quality is a fallback, not a win',
      () {
        final List<RankedSource> ranked = SourceRanker.rank(<RankedSource>[
          _cand('https://a/unknown', quality: null),
          _cand('https://a/1080', quality: '1080p'),
        ], QualityPreference.p1080);

        expect(ranked.first.source.url, 'https://a/1080');
      },
    );

    test('adaptive is rewarded under auto', () {
      final List<RankedSource> ranked = SourceRanker.rank(<RankedSource>[
        _cand('https://a/fixed-hls', quality: '720p', type: SourceType.hls),
        _cand(
          'https://a/adaptive-hls',
          quality: '720p',
          type: SourceType.hls,
          adaptive: true,
        ),
      ], QualityPreference.auto);

      expect(ranked.first.source.url, 'https://a/adaptive-hls');
    });
  });

  group('SourceRanker — determinism', () {
    test('identical candidates keep a stable order across runs', () {
      final List<RankedSource> pool = <RankedSource>[
        _cand('https://b/same', quality: '720p', extensionId: 'extB'),
        _cand('https://a/same', quality: '720p', extensionId: 'extA'),
      ];

      final List<RankedSource> run1 = SourceRanker.rank(
        pool,
        QualityPreference.p720,
      );
      final List<RankedSource> run2 = SourceRanker.rank(
        pool,
        QualityPreference.p720,
      );

      expect(
        run1.map((RankedSource r) => r.source.url).toList(),
        run2.map((RankedSource r) => r.source.url).toList(),
      );
      // URL tie-break: a before b regardless of input order.
      expect(run1.first.source.url, 'https://a/same');
    });

    test('quality tier is the tie-breaker before URL', () {
      final List<RankedSource> ranked = SourceRanker.rank(<RankedSource>[
        _cand('https://a/480', quality: '480p'),
        _cand('https://b/480', quality: '480p'),
      ], QualityPreference.auto);

      // Equal score + equal tier + different URLs -> URL order.
      expect(ranked.first.source.url, 'https://a/480');
    });
  });
}
