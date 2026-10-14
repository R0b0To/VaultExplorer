import 'dart:io';

import 'package:vaultexplorer/core/utils/image_dimensions.dart';

/// A short-lived, app-private copy of an archive entry for viewers that need
/// a seekable file rather than in-memory bytes.
class ArchivePreviewFile {
  /// How much of the file's start is read to find an image's pixel size. Same
  /// window `MediaPrefetchController` uses for playlist items; image headers
  /// (even a JPEG behind a large EXIF block) fit well inside it.
  static const int _headerSniffBytes = 65536;

  final String path;
  bool _discarded = false;

  ArchivePreviewFile.fromNativePath(this.path);

  /// The staged image's pixel size, parsed from its header alone (no decode).
  ///
  /// The media viewer lays an image out from its aspect ratio. For a normal
  /// open that ratio is already known from the folder's thumbnails; an archive
  /// preview has no thumbnails (they are deliberately disabled so nothing from
  /// the archive is written to a cache), so the caller seeds the ratio from
  /// this instead. Returns null if the file is not a recognised image or
  /// cannot be read.
  Future<(int width, int height)?> readImageSize() async {
    RandomAccessFile? file;
    try {
      file = await File(path).open();
      final header = await file.read(_headerSniffBytes);
      if (header.isEmpty) return null;
      return extractImageDimensionsFromBytes(header);
    } catch (_) {
      return null;
    } finally {
      try {
        await file?.close();
      } catch (_) {
        // Nothing useful to do if closing a read-only handle fails.
      }
    }
  }

  /// Deletes this preview. [secureDelete] is supplied by the native archive
  /// bridge, which verifies the cache location and wipes the file first.
  Future<void> discard({
    Future<bool> Function(String path)? secureDelete,
  }) async {
    if (_discarded) return;
    _discarded = true;

    try {
      if (secureDelete != null && await secureDelete(path)) return;
    } catch (_) {
      // Fall through to a normal best-effort delete. The native bridge creates
      // this file in the app-private cache.
    }

    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Startup cleanup will retry any file left behind after a process crash
      // or a transient filesystem failure.
    }
  }
}
