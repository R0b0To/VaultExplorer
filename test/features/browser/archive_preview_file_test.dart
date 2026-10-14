import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/archive_preview_file.dart';

void main() {
  group('ArchivePreviewFile.readImageSize', () {
    // Just enough of a PNG for its header to be parsed: signature, IHDR chunk
    // length and type, then width (300) and height (200).
    final pngHeader = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
      0x00, 0x00, 0x00, 0x0D, // IHDR length
      0x49, 0x48, 0x44, 0x52, // 'IHDR'
      0x00, 0x00, 0x01, 0x2C, // width 300
      0x00, 0x00, 0x00, 0xC8, // height 200
      0x08, 0x02, 0x00, 0x00, 0x00,
    ]);

    test('reads the size from the staged image header', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'archive_preview_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}archive_browse_pic.png',
      )..writeAsBytesSync(pngHeader);

      final size = await ArchivePreviewFile.fromNativePath(
        file.path,
      ).readImageSize();

      expect(size, (300, 200));
    });

    test('returns null when the file is not a recognised image', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'archive_preview_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}archive_browse_note.txt',
      )..writeAsBytesSync([1, 2, 3, 4, 5, 6, 7, 8]);

      final size = await ArchivePreviewFile.fromNativePath(
        file.path,
      ).readImageSize();

      expect(size, isNull);
    });

    test('returns null instead of throwing when the file is gone', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'archive_preview_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final size = await ArchivePreviewFile.fromNativePath(
        '${tempDir.path}${Platform.pathSeparator}archive_browse_missing.png',
      ).readImageSize();

      expect(size, isNull);
    });
  });

  group('ArchivePreviewFile', () {
    test('uses the native-staged temporary path unchanged', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'archive_preview_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}archive_browse_video.mp4',
      )..writeAsBytesSync([1, 2, 3]);

      final preview = ArchivePreviewFile.fromNativePath(file.path);

      expect(preview.path, file.path);
      expect(await File(preview.path).readAsBytes(), [1, 2, 3]);
    });

    test('uses the secure-discard callback at most once', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'archive_preview_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}archive_browse_song.flac',
      )..writeAsBytesSync([1]);
      final preview = ArchivePreviewFile.fromNativePath(file.path);
      var calls = 0;

      Future<bool> secureDelete(String path) async {
        calls++;
        expect(path, preview.path);
        await File(path).delete();
        return true;
      }

      await preview.discard(secureDelete: secureDelete);
      await preview.discard(secureDelete: secureDelete);

      expect(calls, 1);
      expect(await File(preview.path).exists(), isFalse);
    });
  });
}
