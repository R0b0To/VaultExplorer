import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/video_scrub_progress_bar.dart';

void main() {
  group('scrubMiniBoxSize', () {
    test('16:9 keeps the original 144x81 box', () {
      final size = scrubMiniBoxSize(16 / 9);

      expect(size.width, closeTo(144, 1e-9));
      expect(size.height, closeTo(81, 1e-9));
    });

    test('9:16 portrait gets a tall box instead of a cropped band', () {
      final size = scrubMiniBoxSize(9 / 16);

      expect(size.width, closeTo(81, 1e-9));
      expect(size.height, closeTo(144, 1e-9));
    });

    test('square and 4:3 fit inside the 144px square', () {
      expect(scrubMiniBoxSize(1).width, closeTo(144, 1e-9));
      expect(scrubMiniBoxSize(1).height, closeTo(144, 1e-9));
      expect(scrubMiniBoxSize(4 / 3).width, closeTo(144, 1e-9));
      expect(scrubMiniBoxSize(4 / 3).height, closeTo(108, 1e-9));
    });

    test('the box matches the video shape, so nothing is cropped', () {
      for (final ratio in [0.6, 9 / 16 * 1.1, 0.75, 1.0, 4 / 3, 16 / 9, 2.0]) {
        final size = scrubMiniBoxSize(ratio);
        expect(size.width / size.height, closeTo(ratio, 1e-9), reason: '$ratio');
      }
    });

    test('never exceeds 144px in either direction', () {
      for (final ratio in [0.05, 0.3, 0.5, 9 / 16, 1.0, 16 / 9, 2.4, 3.6, 10.0]) {
        final size = scrubMiniBoxSize(ratio);
        expect(size.width, lessThanOrEqualTo(144 + 1e-9), reason: '$ratio');
        expect(size.height, lessThanOrEqualTo(144 + 1e-9), reason: '$ratio');
      }
    });

    test('extreme ratios are clamped so the timestamp label still fits', () {
      // Narrowest: 1:2 -> 72px wide. Widest: 5:2 -> 57.6px tall.
      expect(scrubMiniBoxSize(0.05).width, closeTo(72, 1e-9));
      expect(scrubMiniBoxSize(0.05).height, closeTo(144, 1e-9));
      expect(scrubMiniBoxSize(10).width, closeTo(144, 1e-9));
      expect(scrubMiniBoxSize(10).height, closeTo(57.6, 1e-9));
    });

    test('a bogus ratio falls back to the old 16:9 box', () {
      for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
        final size = scrubMiniBoxSize(bad);
        expect(size.width, closeTo(144, 1e-9), reason: '$bad');
        expect(size.height, closeTo(81, 1e-9), reason: '$bad');
      }
    });
  });
}
