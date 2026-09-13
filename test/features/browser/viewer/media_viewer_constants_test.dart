import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';

void main() {
  group('MediaViewerConstants.hasRealThumbnail', () {
    test('true for a plain image file', () {
      expect(MediaViewerConstants.hasRealThumbnail('vacation.jpg'), isTrue);
    });

    test('true for a plain video file', () {
      expect(MediaViewerConstants.hasRealThumbnail('clip.mp4'), isTrue);
    });

    test('false for a video inside an open archive', () {
      expect(
        MediaViewerConstants.hasRealThumbnail('clip.mp4', insideArchive: true),
        isFalse,
      );
    });

    test('an image inside an open archive is unaffected', () {
      expect(
        MediaViewerConstants.hasRealThumbnail(
          'vacation.jpg',
          insideArchive: true,
        ),
        isTrue,
      );
    });

    test('false for a placeholder image mid-import', () {
      // A placeholder renders as a generic icon with a progress spinner
      // until the transfer finishes, regardless of its eventual type --
      // hiding its name at that point would make it anonymous too.
      expect(
        MediaViewerConstants.hasRealThumbnail(
          'vacation.jpg',
          isPlaceholder: true,
        ),
        isFalse,
      );
    });

    test('false for non-visual document/archive types', () {
      for (final name in ['report.pdf', 'backup.zip', 'notes.docx',
          'song.mp3', 'readme.txt']) {
        expect(
          MediaViewerConstants.hasRealThumbnail(name),
          isFalse,
          reason: '$name should fall back to a generic icon',
        );
      }
    });

    test('false for vault item pseudo-files regardless of extension name', () {
      // Vault items (passwords, cards, etc.) always render with a fixed
      // icon, even though "password" isn't a real file extension.
      expect(
        MediaViewerConstants.hasRealThumbnail('My Bank.password'),
        isFalse,
      );
    });

    test('false for other vault item extensions too', () {
      expect(
        MediaViewerConstants.hasRealThumbnail('Some Card.paymentCard'),
        isFalse,
      );
    });
  });
}