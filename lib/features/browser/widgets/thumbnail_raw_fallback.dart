import 'dart:typed_data';

import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/utils/image_dimensions.dart';
import 'package:vaultexplorer/core/utils/image_preview_exception.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

/// Largest file the thumbnail path will read whole as a stand-in for a native
/// thumbnail.
const int maxRawThumbnailFallbackBytes = 4 * 1024 * 1024;

/// Most pixels the thumbnail path will let Flutter decode from a raw file.
/// A heavily compressed image can be a few MB yet hold hundreds of millions of
/// pixels, and Flutter's decoder materialises (close to) all of them even
/// when the widget asks for a 180 px thumbnail.
const int maxRawThumbnailFallbackPixels = 16 * 1000 * 1000;

/// Headers we can't parse give no pixel count, so only small files get through.
const int _maxUnverifiedRawFallbackBytes = 512 * 1024;

/// The last-resort thumbnail for an image the native decoder produced nothing
/// for: the file's own bytes, handed to `Image.memory`.
///
/// This used to read the whole file unconditionally. When native declined an
/// oversized image (rather than failing on an unsupported codec), the fallback
/// then pulled e.g. 100 MB across the platform channel and let Flutter decode
/// all 857 MP of it -- about 5 GB of native memory, until the kernel's
/// low-memory killer took the app. It now refuses anything big, by bytes or by
/// pixels, by throwing [ImagePreviewUnavailableException]; callers show their
/// normal placeholder.
Future<Uint8List> readRawThumbnailFallback(
  VaultFileIoApi fileIoApi,
  MountedContainer container,
  String path,
) async {
  const tooLarge = ImagePreviewUnavailableException(
    ImagePreviewUnavailableReason.tooLarge,
  );
  final size = await fileIoApi.getFileSize(container, path);
  if (size <= 0) throw Exception('Empty file (size <= 0)');
  if (size > maxRawThumbnailFallbackBytes) throw tooLarge;

  final raw = await fileIoApi.readFileChunk(container, path, 0, size);
  if (raw == null || raw.isEmpty) throw Exception('File chunk read failed');

  final dimensions = extractImageDimensionsFromBytes(raw);
  if (dimensions == null) {
    if (raw.length > _maxUnverifiedRawFallbackBytes) throw tooLarge;
  } else if (dimensions.$1 * dimensions.$2 > maxRawThumbnailFallbackPixels) {
    throw tooLarge;
  }
  return raw;
}
