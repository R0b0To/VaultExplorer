import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';

void main() {
  group('isAppEncryptedFileName', () {
    test('recognizes the native .vxenc extension', () {
      expect(isAppEncryptedFileName('secret.vxenc'), isTrue);
    });

    test('recognizes the AES Crypt-compatible .aes extension', () {
      expect(isAppEncryptedFileName('secret.aes'), isTrue);
    });

    test('is case-insensitive', () {
      expect(isAppEncryptedFileName('SECRET.VXENC'), isTrue);
      expect(isAppEncryptedFileName('Secret.Aes'), isTrue);
    });

    test('rejects unrelated extensions', () {
      expect(isAppEncryptedFileName('notes.txt'), isFalse);
      expect(isAppEncryptedFileName('archive.zip'), isFalse);
      expect(isAppEncryptedFileName('no-extension'), isFalse);
    });
  });

  group('iconForFile', () {
    test('maps known extensions to their category icon', () {
      expect(iconForFile('report.pdf'), Icons.picture_as_pdf_outlined);
      expect(iconForFile('photo.jpg'), Icons.image_outlined);
      expect(iconForFile('photo.PNG'), Icons.image_outlined); // case-insensitive
      expect(iconForFile('clip.mp4'), Icons.ondemand_video_outlined);
      expect(iconForFile('song.mp3'), Icons.audio_file_outlined);
      expect(iconForFile('notes.txt'), Icons.article_outlined);
      expect(iconForFile('page.html'), Icons.language_rounded);
      expect(iconForFile('bundle.zip'), Icons.archive_outlined);
    });

    test('falls back to a generic file icon for unknown extensions', () {
      expect(iconForFile('data.xyz'), Icons.insert_drive_file_outlined);
    });

    test('falls back to a generic file icon for names with no extension',
        () {
      expect(iconForFile('README'), Icons.insert_drive_file_outlined);
    });
  });

  group('colorForFile', () {
    test('known categories get distinct accent colors from the default',
        () {
      final defaultColor = colorForFile('README');
      expect(colorForFile('report.pdf'), isNot(defaultColor));
      expect(colorForFile('photo.jpg'), isNot(defaultColor));
      expect(colorForFile('clip.mp4'), isNot(defaultColor));
    });

    test('is case-insensitive on the extension', () {
      expect(colorForFile('report.PDF'), colorForFile('report.pdf'));
    });

    test('unknown extensions and no-extension names share the same '
        'default color', () {
      expect(colorForFile('data.xyz'), colorForFile('README'));
    });
  });

  group('vaultIconForExt / vaultColorForExt', () {
    const knownTypes = [
      'password',
      'paymentCard',
      'identity',
      'secureNote',
      'bankAccount',
      'softwareLicense',
    ];

    test('every known vault item type has both an icon and a color', () {
      for (final ext in knownTypes) {
        expect(vaultIconForExt(ext), isNotNull, reason: ext);
        expect(vaultColorForExt(ext), isNotNull, reason: ext);
      }
    });

    test('an unrecognized extension returns null for both, not a '
        'fallback', () {
      expect(vaultIconForExt('unknownType'), isNull);
      expect(vaultColorForExt('unknownType'), isNull);
    });

    test('each known type maps to a visually distinct icon', () {
      final icons = knownTypes.map(vaultIconForExt).toSet();
      expect(icons, hasLength(knownTypes.length));
    });
  });
}
