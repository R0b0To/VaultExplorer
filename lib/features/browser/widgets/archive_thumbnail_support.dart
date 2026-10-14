import 'dart:typed_data';

import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/archive_models.dart';

/// Thrown when a thumbnail is requested for a file inside an archive that
/// doesn't support cheap per-entry access (see [ArchiveContext.isSolid]).
/// Callers should treat this exactly like any other thumbnail-fetch
/// failure -- [AsyncThumbnail] already falls back to the file-type icon on
/// any thrown error, so no special handling is needed at the call site.
class ArchiveThumbnailUnavailable implements Exception {
  final String? message;
  const ArchiveThumbnailUnavailable([this.message]);
  @override
  String toString() =>
      message ??
      'Thumbnails are unavailable inside solid archives (would require '
      'decompressing every preceding entry for each visible tile)';
}

/// Resolves a synthetic on-screen path (the real container path of the open
/// archive, plus however far the user has navigated inside it -- the same
/// string [FileGridView]/[FileMasonryView]/[FileTile] build for every entry,
/// archive or not) down to the path relative to the archive root that
/// [ArchiveContext.extractEntry]/[ArchiveContext.findEntry] expect.
String archiveRelativeSubPath(String fullPath, String archiveRootPath) {
  if (fullPath.length <= archiveRootPath.length) return '';
  var sub = fullPath.substring(archiveRootPath.length);
  if (sub.startsWith('/')) sub = sub.substring(1);
  return sub;
}

/// Maximum uncompressed size of a video entry inside an archive eligible
/// for thumbnail extraction (500 MB). Staging larger files would risk filling
/// the device cache or causing multi-second I/O stalls just for a tile preview.
const int kMaxArchiveVideoThumbnailEntryBytes = 500 * 1024 * 1024;

/// Fetches a size-limited thumbnail of a file inside an open archive.
///
/// Archive entries don't have a real path in the container filesystem, so
/// this streams the entry to a private cache file, then asks Android's native
/// thumbnail decoder to sample and resize it before returning bytes to
/// Flutter. Large image payloads stay off the method channel and avoid a
/// full-resolution Dart-side decode.
///
/// RAR solid archives are skipped because extracting each visible tile can
/// require replaying all preceding entries. 7z entries are allowed through:
/// the browser's 7z support is expected to provide image previews, and the
/// native extractor handles the same on-demand entry path used to open files.
Future<Uint8List> fetchArchiveEntryForThumbnail({
  required ArchiveContext archiveContext,
  required String archiveRootPath,
  required String fullPath,
  required VaultFileIoApi fileIoApi,
  required int targetSize,
  required int quality,
}) async {
  if (archiveContext.isSolid && !archiveContext.isSevenZip) {
    throw const ArchiveThumbnailUnavailable();
  }
  final subPath = archiveRelativeSubPath(fullPath, archiveRootPath);
  final staged = await archiveContext.stageEntryForBrowse(subPath);
  final stagedPath = staged.path;
  if (staged.status != ArchiveOpenStatus.ok || stagedPath == null) {
    throw Exception('Failed to stage archive entry for thumbnail');
  }

  try {
    final bytes = await fileIoApi.getImageThumbnailFromLocalPath(
      stagedPath,
      targetSize: targetSize,
      quality: quality,
    );
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Failed to decode archive entry thumbnail');
    }
    return bytes;
  } finally {
    await archiveContext.discardStagedEntry(stagedPath);
  }
}

/// Fetches a size-limited thumbnail of a video inside an open archive.
Future<Uint8List> fetchArchiveVideoEntryForThumbnail({
  required ArchiveContext archiveContext,
  required String archiveRootPath,
  required String fullPath,
  required VaultFileIoApi fileIoApi,
  required int targetSize,
  required int quality,
}) async {
  if (archiveContext.isSolid && !archiveContext.isSevenZip) {
    throw const ArchiveThumbnailUnavailable();
  }
  final subPath = archiveRelativeSubPath(fullPath, archiveRootPath);
  final entryInfo = archiveContext.findEntry(subPath);
  if (entryInfo != null &&
      entryInfo.uncompressedSize > 0 &&
      entryInfo.uncompressedSize > kMaxArchiveVideoThumbnailEntryBytes) {
    throw const ArchiveThumbnailUnavailable(
      'Video entry exceeds maximum size for archive thumbnail extraction',
    );
  }
  final staged = await archiveContext.stageEntryForBrowse(subPath);
  final stagedPath = staged.path;
  if (staged.status != ArchiveOpenStatus.ok || stagedPath == null) {
    throw Exception('Failed to stage archive video entry for thumbnail');
  }

  try {
    final bytes = await fileIoApi.getVideoThumbnailFromLocalPath(
      stagedPath,
      targetSize: targetSize,
      quality: quality,
    );
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Failed to decode archive entry video thumbnail');
    }
    return bytes;
  } finally {
    await archiveContext.discardStagedEntry(stagedPath);
  }
}

/// Same as [fetchArchiveVideoEntryForThumbnail], but also returns the source
/// frame's pre-downscale width/height for masonry layouts.
Future<(Uint8List, int, int)> fetchArchiveVideoEntryForThumbnailWithSize({
  required ArchiveContext archiveContext,
  required String archiveRootPath,
  required String fullPath,
  required VaultFileIoApi fileIoApi,
  required int targetSize,
  required int quality,
}) async {
  if (archiveContext.isSolid && !archiveContext.isSevenZip) {
    throw const ArchiveThumbnailUnavailable();
  }
  final subPath = archiveRelativeSubPath(fullPath, archiveRootPath);
  final entryInfo = archiveContext.findEntry(subPath);
  if (entryInfo != null &&
      entryInfo.uncompressedSize > 0 &&
      entryInfo.uncompressedSize > kMaxArchiveVideoThumbnailEntryBytes) {
    throw const ArchiveThumbnailUnavailable(
      'Video entry exceeds maximum size for archive thumbnail extraction',
    );
  }
  final staged = await archiveContext.stageEntryForBrowse(subPath);
  final stagedPath = staged.path;
  if (staged.status != ArchiveOpenStatus.ok || stagedPath == null) {
    throw Exception('Failed to stage archive video entry for thumbnail');
  }

  try {
    final thumb = await fileIoApi.getVideoThumbnailFromLocalPathWithSize(
      stagedPath,
      targetSize: targetSize,
      quality: quality,
    );
    final bytes = thumb?.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Failed to decode archive entry video thumbnail');
    }
    return (bytes, thumb!.width, thumb.height);
  } finally {
    await archiveContext.discardStagedEntry(stagedPath);
  }
}
