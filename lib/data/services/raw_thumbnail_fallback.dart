import 'dart:typed_data';

import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/utils/image_dimensions.dart';
import 'package:vaultexplorer/core/utils/image_preview_exception.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

/// Largest file we will pull across to Dart whole as a stand-in thumbnail.
const int kMaxRawThumbnailFallbackBytes = 2 * 1024 * 1024;

/// Largest declared pixel count we will hand to Flutter's codec as a
/// stand-in thumbnail (~64 MB of RGBA once decoded).
const int kMaxRawThumbnailFallbackPixels = 16 * 1000 * 1000;

/// Last-resort "thumbnail" for an image the native decoder produced nothing
/// for (a format `BitmapFactory` can't read, say): the file's own bytes,
/// which the tile then renders with `Image.memory`.
///
/// That is only safe for *small* images. This used to read the whole file
/// unconditionally, so after native code deliberately refused a huge image
/// (see `ImageDecodeGuard`) the tile read the entire file anyway and Flutter
/// then decoded it at full resolution -- gigabytes of native memory, ending in
/// the low-memory killer's SIGKILL. Both the file size and the pixel size
/// declared in the header are therefore bounded here; beyond either bound this
/// throws [ImagePreviewUnavailableException] so the tile shows its file-type
/// icon instead.
Future<Uint8List> readRawThumbnailFallback(
  VaultFileIoApi fileIoApi,
  MountedContainer container,
  String path,
) async {
  final size = await fileIoApi.getFileSize(container, path);
  if (size <= 0) throw Exception('Empty file (size <= 0)');
  if (size > kMaxRawThumbnailFallbackBytes) {
    throw const ImagePreviewUnavailableException(
      ImagePreviewUnavailableReason.tooLarge,
    );
  }
  final raw = await fileIoApi.readFileChunk(container, path, 0, size);
  if (raw == null || raw.isEmpty) throw Exception('File chunk read failed');
  final dims = extractImageDimensionsFromBytes(raw);
  if (dims != null && dims.$1 * dims.$2 > kMaxRawThumbnailFallbackPixels) {
    throw const ImagePreviewUnavailableException(
      ImagePreviewUnavailableReason.tooLarge,
    );
  }
  return raw;
}
