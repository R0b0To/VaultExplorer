import 'dart:typed_data';

import 'package:vaultexplorer/data/models/archive_context.dart';

/// Thrown when a thumbnail is requested for a file inside an archive that
/// doesn't support cheap per-entry access (see [ArchiveContext.isSolid]).
/// Callers should treat this exactly like any other thumbnail-fetch
/// failure -- [AsyncThumbnail] already falls back to the file-type icon on
/// any thrown error, so no special handling is needed at the call site.
class ArchiveThumbnailUnavailable implements Exception {
  const ArchiveThumbnailUnavailable();
  @override
  String toString() =>
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

/// Fetches the raw bytes of a file inside an open archive, for use as a
/// thumbnail source.
///
/// There is no native thumbnail generation for archive entries -- files
/// inside an archive don't correspond to any real path in the container's
/// filesystem, so the ordinary `getImageThumbnail`/`readFileChunk` native
/// calls can never resolve them. Instead this decrypts+decompresses the
/// single entry in full via the same on-demand extraction path used when
/// the user taps a file to view it ([ArchiveContext.extractEntry]), and the
/// caller displays it directly (`Image.memory` with `cacheHeight` already
/// downsamples at decode time, so this doesn't need a separate native
/// resize step the way a real container thumbnail does).
///
/// This is only attempted for archives that support cheap direct access to
/// an individual entry ([ArchiveContext.isSolid] == false). Solid archives
/// (RAR/7z with shared compression blocks) require decompressing every
/// entry before the target one to extract it at all -- the existing
/// "opening files may be slower, especially near the end" warning already
/// sets that expectation for opening a single file, but doing the same
/// decompression-from-the-start work for every visible grid tile at once
/// would make browsing a large solid archive unusably slow. For those, this
/// throws immediately so the tile falls back to its plain file-type icon
/// instead of hanging or churning the CPU -- the "disable it" half of the
/// fix, as opposed to the "make it work" half for direct-access archives.
Future<Uint8List> fetchArchiveEntryForThumbnail({
  required ArchiveContext archiveContext,
  required String archiveRootPath,
  required String fullPath,
}) async {
  if (archiveContext.isSolid) {
    throw const ArchiveThumbnailUnavailable();
  }
  final subPath = archiveRelativeSubPath(fullPath, archiveRootPath);
  final bytes = await archiveContext.extractEntry(subPath);
  if (bytes == null || bytes.isEmpty) {
    throw Exception('Failed to extract archive entry for thumbnail');
  }
  return bytes;
}
