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

    test('true for a video inside an open archive', () {
      expect(
        MediaViewerConstants.hasRealThumbnail('clip.mp4', insideArchive: true),
        isTrue,
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

    test('false for an APK, which renders as a centred icon', () {
      // An APK does get a thumbnail -- its own launcher icon -- but it's
      // drawn at icon size inside the cell rather than filling it, so it
      // needs its name label for the same reason a PDF does.
      expect(MediaViewerConstants.hasRealThumbnail('signal.apk'), isFalse);
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

  group('extension lookups', () {
    test('are case-insensitive and use only the text after the last dot', () {
      expect(MediaViewerConstants.isImage('Holiday.JPG'), isTrue);
      expect(MediaViewerConstants.isVideo('clip.final.MkV'), isTrue);
      expect(MediaViewerConstants.isAudio('a.b.FLAC'), isTrue);
      expect(MediaViewerConstants.isImage('photo.jpg.txt'), isFalse);
      expect(MediaViewerConstants.isVideo('movie.mp4.'), isFalse);
      expect(MediaViewerConstants.isSupported('notes.pdf'), isFalse);
      expect(MediaViewerConstants.isSupported('song.mp3'), isTrue);
    });

    test('a folder with a dot in its name does not give a bare file an extension', () {
      expect(MediaViewerConstants.isImage('v1.jpg/readme'), isFalse);
    });

    test('hasRealThumbnail still compares vault-item extensions case-sensitively', () {
      expect(MediaViewerConstants.hasRealThumbnail('photo.jpg'), isTrue);
      expect(MediaViewerConstants.hasRealThumbnail('Photo.PNG'), isTrue);
      expect(MediaViewerConstants.hasRealThumbnail('a.password'), isFalse);
      expect(MediaViewerConstants.hasRealThumbnail('doc.pdf'), isFalse);
      expect(MediaViewerConstants.hasRealThumbnail('photo.jpg', isPlaceholder: true), isFalse);
    });
  });
}
