import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/pip/picture_in_picture_bridge.dart';

void main() {
  group('pictureInPictureRatio', () {
    test('turns an aspect ratio into an integer pair', () {
      expect(pictureInPictureRatio(1.0), (width: 1000, height: 1000));
      expect(pictureInPictureRatio(2.0), (width: 2000, height: 1000));
      expect(pictureInPictureRatio(16 / 9), (width: 1778, height: 1000));
    });

    test('keeps portrait video portrait', () {
      final ratio = pictureInPictureRatio(9 / 16);
      expect(ratio.width, lessThan(ratio.height));
    });

    test('never produces a zero width', () {
      expect(pictureInPictureRatio(0).width, 1);
    });
  });
}
