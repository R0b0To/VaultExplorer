import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vaultexplorer/core/engine/desktop/video_thumbnail_logic.dart';

/// A [size] x [size] RGBA image whose pixel at (x, y) is `gray(x, y)` (R = G = B). Samples taken by
/// [isLikelyBlankFrame] land on x, y = 4, 12, 20, ... for a 64 px image, so `x ~/ 8` is the grid cell.
Uint8List _gray(int size, int Function(int x, int y) gray) {
  final out = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final v = gray(x, y);
      final i = (y * size + x) * 4;
      out[i] = v;
      out[i + 1] = v;
      out[i + 2] = v;
      out[i + 3] = 255;
    }
  }
  return out;
}

void main() {
  group('fitWithin', () {
    test('scales the longest edge down to the target', () {
      expect(fitWithin(1920, 1080, 180), (width: 180, height: 101));
      expect(fitWithin(1080, 1920, 180), (width: 101, height: 180));
    });

    test('never scales up', () {
      expect(fitWithin(100, 50, 180), (width: 100, height: 50));
      expect(fitWithin(180, 180, 180), (width: 180, height: 180));
    });

    test('keeps both edges at least one pixel', () {
      expect(fitWithin(10000, 1, 100), (width: 100, height: 1));
    });
  });

  group('frame positions', () {
    test('fractions are clamped to 5%..90%', () {
      expect(clampThumbnailFraction(0), 0.05);
      expect(clampThumbnailFraction(1.5), 0.90);
      expect(clampThumbnailFraction(0.3), 0.3);
      expect(clampThumbnailFraction(double.nan), 0.12);
    });

    test('a blank first frame is retried at the configured position, then 25% and 45%', () {
      expect(blankFrameRetryFractions(0.12), [0.12, 0.25, 0.45]);
      expect(blankFrameRetryFractions(0.25), [0.25, 0.45]);
      expect(blankFrameRetryFractions(0), [0.05, 0.25, 0.45]);
      expect(blankFrameRetryFractions(2), [0.90, 0.25, 0.45]);
    });

    test('timeAtFraction applies the clamped fraction to the duration', () {
      expect(timeAtFraction(const Duration(seconds: 10), 0.12), const Duration(milliseconds: 1200));
      expect(timeAtFraction(const Duration(seconds: 10), 0), const Duration(milliseconds: 500));
      expect(timeAtFraction(const Duration(seconds: 10), 1), const Duration(seconds: 9));
    });
  });

  group('isLikelyBlankFrame', () {
    test('flat colours are blank', () {
      expect(isLikelyBlankFrame(_gray(64, (x, y) => 0), 64, 64), isTrue);
      expect(isLikelyBlankFrame(_gray(64, (x, y) => 255), 64, 64), isTrue);
      expect(isLikelyBlankFrame(_gray(64, (x, y) => 128), 64, 64), isTrue);
    });

    test('a picture with real contrast is not blank', () {
      // Left half black, right half white.
      expect(isLikelyBlankFrame(_gray(64, (x, y) => x < 32 ? 0 : 255), 64, 64), isFalse);
      // Pseudo-random noise over the whole range.
      var seed = 12345;
      final noise = _gray(64, (x, y) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        return (seed >> 16) & 0xff;
      });
      expect(isLikelyBlankFrame(noise, 64, 64), isFalse);
    });

    test('near-black frames are blank even with a little variation', () {
      expect(isLikelyBlankFrame(_gray(64, (x, y) => ((x ~/ 8) + (y ~/ 8)).isEven ? 0 : 30), 64, 64), isTrue);
    });

    test('a slate that is mostly dark background is blank', () {
      // 4 bright cells out of 64, everything else luma 10.
      final slate = _gray(64, (x, y) => (y ~/ 8 == 0 && x ~/ 8 < 4) ? 200 : 10);
      expect(isLikelyBlankFrame(slate, 64, 64), isTrue);
    });

    test('a frame that is almost one flat tone is blank, a clearly structured one is not', () {
      final almostFlat = _gray(64, (x, y) => (x ~/ 8 == 0 && y ~/ 8 == 0) ? 128 : 108);
      expect(isLikelyBlankFrame(almostFlat, 64, 64), isTrue);
      // A third of the frame is clearly lighter: real structure.
      final structured = _gray(64, (x, y) => x < 22 ? 180 : 90);
      expect(isLikelyBlankFrame(structured, 64, 64), isFalse);
    });

    test('unusable input is treated as not blank', () {
      expect(isLikelyBlankFrame(Uint8List(10), 64, 64), isFalse);
      expect(isLikelyBlankFrame(Uint8List(0), 0, 0), isFalse);
    });
  });
}
