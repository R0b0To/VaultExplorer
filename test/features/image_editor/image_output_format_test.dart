import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/image_editor/image_output_format.dart';

void main() {
  group('imageOutputFormatForExtension', () {
    test('saves JPEG photos as JPEG, whatever the case or spelling', () {
      for (final ext in ['jpg', 'jpeg', 'JPG', 'Jpeg']) {
        expect(
          imageOutputFormatForExtension(ext),
          ImageOutputFormat.jpeg,
          reason: ext,
        );
      }
    });

    test('saves WebP as WebP', () {
      expect(imageOutputFormatForExtension('webp'), ImageOutputFormat.webp);
      expect(imageOutputFormatForExtension('WEBP'), ImageOutputFormat.webp);
    });

    test('keeps PNG and anything without a lossy encoder on the PNG path', () {
      for (final ext in ['png', 'avif', 'gif', 'bmp', 'heic', '']) {
        expect(
          imageOutputFormatForExtension(ext),
          ImageOutputFormat.png,
          reason: 'extension "$ext"',
        );
      }
    });
  });

  group('imageOutputExtension', () {
    test('matches the encoded format so the file name never lies', () {
      expect(imageOutputExtension(ImageOutputFormat.png, 'avif'), 'png');
      expect(imageOutputExtension(ImageOutputFormat.webp, 'webp'), 'webp');
    });

    test('keeps the user\'s own jpg / jpeg spelling', () {
      expect(imageOutputExtension(ImageOutputFormat.jpeg, 'jpg'), 'jpg');
      expect(imageOutputExtension(ImageOutputFormat.jpeg, 'jpeg'), 'jpeg');
      expect(imageOutputExtension(ImageOutputFormat.jpeg, 'JPEG'), 'jpeg');
    });
  });

  group('imageSizeBudgetBytes', () {
    test('a quarter-size crop may cost at most a quarter of the bytes', () {
      // 4000x3000 photo, 5 MB, cropped to 2000x1500.
      final budget = imageSizeBudgetBytes(
        originalBytes: 5 * 1024 * 1024,
        originalPixels: 4000 * 3000,
        newPixels: 2000 * 1500,
      );

      expect(budget, 5 * 1024 * 1024 ~/ 4);
      // The reported requirement: at least half the original size.
      expect(budget!, lessThanOrEqualTo(5 * 1024 * 1024 ~/ 2));
    });

    test('scales with how much of the image survives', () {
      final tenth = imageSizeBudgetBytes(
        originalBytes: 1000000,
        originalPixels: 1000,
        newPixels: 100,
      );
      final ninetyPercent = imageSizeBudgetBytes(
        originalBytes: 1000000,
        originalPixels: 1000,
        newPixels: 900,
      );

      expect(tenth, 100000);
      expect(ninetyPercent, 900000);
    });

    test('does not constrain edits that keep every pixel', () {
      expect(
        imageSizeBudgetBytes(
          originalBytes: 1000000,
          originalPixels: 1000,
          newPixels: 1000,
        ),
        isNull,
      );
      expect(
        imageSizeBudgetBytes(
          originalBytes: 1000000,
          originalPixels: 1000,
          newPixels: 1500,
        ),
        isNull,
      );
    });

    test('has no budget when the original size is unknown', () {
      expect(
        imageSizeBudgetBytes(
          originalBytes: 0,
          originalPixels: 1000,
          newPixels: 100,
        ),
        isNull,
      );
      expect(
        imageSizeBudgetBytes(
          originalBytes: 1000000,
          originalPixels: 0,
          newPixels: 100,
        ),
        isNull,
      );
      expect(
        imageSizeBudgetBytes(
          originalBytes: 1000000,
          originalPixels: 1000,
          newPixels: 0,
        ),
        isNull,
      );
    });

    test('never rounds a real budget down to zero', () {
      expect(
        imageSizeBudgetBytes(
          originalBytes: 10,
          originalPixels: 1000000,
          newPixels: 1,
        ),
        1,
      );
    });
  });
}
