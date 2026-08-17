import 'package:test/test.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';

void main() {
  group('construction and defaults', () {
    test('the no-arg constructor matches defaultQuality', () {
      expect(const ThumbnailQuality(), ThumbnailQuality.defaultQuality);
    });

    test('defaultQuality is 80% quality at 180px', () {
      expect(ThumbnailQuality.defaultQuality.quality, 80);
      expect(ThumbnailQuality.defaultQuality.size, 180);
    });
  });

  group('jpegQuality', () {
    test('an in-range quality passes through unchanged', () {
      expect(const ThumbnailQuality(quality: 55).jpegQuality, 55);
    });

    test('clamps below 10 up to 10', () {
      expect(const ThumbnailQuality(quality: 0).jpegQuality, 10);
    });

    test('clamps above 100 down to 100', () {
      expect(const ThumbnailQuality(quality: 500).jpegQuality, 100);
    });
  });

  group('scaledSize', () {
    test('scales proportionally to the 180px baseline', () {
      // size=360 is double the 180 baseline, so a 100px base scales to 200.
      const q = ThumbnailQuality(size: 360);
      expect(q.scaledSize(100), 200);
    });

    test('size equal to the baseline (180) is a no-op scale', () {
      const q = ThumbnailQuality(size: 180);
      expect(q.scaledSize(250), 250);
    });

    test('the result is clamped to a minimum of 40', () {
      const q = ThumbnailQuality(size: 90); // half of baseline
      expect(q.scaledSize(10), 40); // 10 * 0.5 = 5, clamped up to 40
    });

    test('the result is clamped to a maximum of 1000', () {
      const q = ThumbnailQuality(size: 3600); // 20x baseline
      expect(q.scaledSize(1000), 1000); // 1000 * 20 = 20000, clamped down
    });
  });

  group('label', () {
    test('combines size and quality into a display string', () {
      expect(const ThumbnailQuality(quality: 90, size: 280).label, '280px · 90% quality');
    });
  });

  group('copyWith', () {
    test('omitted fields are preserved from the receiver', () {
      const q = ThumbnailQuality(quality: 70, size: 200);
      final copy = q.copyWith();
      expect(copy, q);
    });

    test('provided fields override, clamped to copyWith\'s own ranges', () {
      const q = ThumbnailQuality(quality: 70, size: 200);
      final copy = q.copyWith(quality: 95);
      expect(copy.quality, 95);
      expect(copy.size, 200);
    });

    test('copyWith clamps quality to 10..100, same as the constructor '
        'range', () {
      const q = ThumbnailQuality();
      expect(q.copyWith(quality: 5).quality, 10);
      expect(q.copyWith(quality: 999).quality, 100);
    });

    test('copyWith clamps size to 80..600 — a narrower floor than the '
        'unclamped constructor allows', () {
      const q = ThumbnailQuality();
      expect(q.copyWith(size: 1).size, 80);
      expect(q.copyWith(size: 9999).size, 600);
    });
  });

  group('JSON round-trip', () {
    test('toJson/fromJson round-trips exactly', () {
      const q = ThumbnailQuality(quality: 65, size: 220);
      final restored = ThumbnailQuality.fromJson(q.toJson());
      expect(restored, q);
    });

    test('fromJson(null) returns defaultQuality', () {
      expect(ThumbnailQuality.fromJson(null), ThumbnailQuality.defaultQuality);
    });

    test('fromJson with a partial map fills in defaults for missing keys',
        () {
      final restored = ThumbnailQuality.fromJson({'quality': 50});
      expect(restored.quality, 50);
      expect(restored.size, 180); // default
    });

    test('fromJson tolerates numbers that arrive as double (e.g. from a '
        'JSON decoder)', () {
      final restored = ThumbnailQuality.fromJson({'quality': 50.0, 'size': 200.0});
      expect(restored.quality, 50);
      expect(restored.size, 200);
    });
  });

  group('fromJson — legacy string presets', () {
    test('"low" maps to the documented low-quality preset', () {
      expect(
        ThumbnailQuality.fromJson('low'),
        const ThumbnailQuality(quality: 40, size: 140),
      );
    });

    test('"medium" maps to the same values as defaultQuality', () {
      expect(ThumbnailQuality.fromJson('medium'), ThumbnailQuality.defaultQuality);
    });

    test('"high" and "veryHigh" map to their documented presets', () {
      expect(
        ThumbnailQuality.fromJson('high'),
        const ThumbnailQuality(quality: 90, size: 280),
      );
      expect(
        ThumbnailQuality.fromJson('veryHigh'),
        const ThumbnailQuality(quality: 98, size: 360),
      );
    });

    test('an unrecognized string falls back to defaultQuality', () {
      expect(ThumbnailQuality.fromJson('ultra'), ThumbnailQuality.defaultQuality);
    });
  });

  group('fromJson — unexpected types', () {
    test('a bare number falls back to defaultQuality', () {
      expect(ThumbnailQuality.fromJson(42), ThumbnailQuality.defaultQuality);
    });
  });

  group('equality and hashCode', () {
    test('same quality and size are equal', () {
      expect(const ThumbnailQuality(quality: 1, size: 2), const ThumbnailQuality(quality: 1, size: 2));
    });

    test('differing in either field breaks equality', () {
      expect(
        const ThumbnailQuality(quality: 1, size: 2),
        isNot(const ThumbnailQuality(quality: 1, size: 3)),
      );
    });
  });
}
