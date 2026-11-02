import 'dart:async';

import 'package:flutter/services.dart';

import 'package:vaultexplorer/core/api/vault_book_api.dart';
import 'package:vaultexplorer/core/utils/image_preview_exception.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/thumbnail_with_size.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/features/browser/file_open_dispatch.dart'
    show kComicExtensions;

/// Which reader [fileName] opens in, if it is a book whose cover can stand in
/// for its file-type icon; null for every other file.
///
/// Decided from the extension alone, like the image/video checks, so the file
/// views can pick a tile type without any I/O. `.cbr` / `.cb7` / `.cbt` are
/// included because the comic reader tries them as ZIPs (many are); one that is
/// really a RAR or 7z fails fast on the native side and keeps its icon.
BookKind? bookKindForThumbnail(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0) return null;
  final ext = fileName.substring(dot + 1).toLowerCase();
  if (ext == 'epub') return BookKind.epub;
  if (kComicExtensions.contains(ext)) return BookKind.comic;
  return null;
}

/// [bookKindForThumbnail] != null, for call sites that only need the yes/no.
bool isBookWithCover(String fileName) => bookKindForThumbnail(fileName) != null;

/// A book that has no cover to show: it has none (an EPUB that names no cover
/// image, a comic with no pages), it is not a plain ZIP (a real RAR, an
/// encrypted archive), or its cover could not be decoded.
///
/// Callers do not need to catch this: `AsyncThumbnail` falls back to the plain
/// file-type icon on any error from its `fetchFn`. It is a
/// [PermanentThumbnailFailure] so the loader does not retry it.
class BookCoverUnavailable implements PermanentThumbnailFailure {
  final String reason;
  const BookCoverUnavailable(this.reason);
  @override
  String toString() => 'Book cover unavailable: $reason';
}

/// Upper bound on one cover extraction. The native side only reads the ZIP's
/// directory and one image, so even a large book on slow storage is quick; this
/// is a backstop for a stalled provider, after which the tile keeps its icon.
const Duration _extractionTimeout = Duration(seconds: 20);

/// Asks the native side for [filePath]'s cover as a thumbnail.
///
/// Throws [BookCoverUnavailable] when there is nothing to show. Anything that
/// might be transient (out of memory, a stalled provider, a channel hiccup) is
/// rethrown as-is so the loader's normal backoff retry still applies.
Future<ThumbnailWithSize> fetchBookCoverForThumbnail({
  required VaultBookApi bookApi,
  required MountedContainer container,
  required String filePath,
  required int targetSize,
  required int quality,
}) async {
  final kind = bookKindForThumbnail(filePath);
  if (kind == null) throw const BookCoverUnavailable('not a book');
  try {
    return await bookApi
        .getCover(
          container: container,
          path: filePath,
          kind: kind,
          targetSize: targetSize,
          quality: quality,
        )
        .timeout(
          _extractionTimeout,
          onTimeout: () => throw const BookCoverUnavailable('timed out'),
        );
  } on PlatformException catch (e) {
    if (_isPermanent(e.code)) throw BookCoverUnavailable(e.code);
    rethrow;
  }
}

/// Native error codes that mean "this book has no cover" rather than "try
/// again". `OUT_OF_MEMORY` is deliberately absent: it can pass.
bool _isPermanent(String code) {
  switch (code) {
    case 'BOOK_NO_COVER':
    case 'FILE_NOT_FOUND':
    case 'BOOK_NOT_ZIP':
    case 'BOOK_ENCRYPTED':
    case 'BOOK_UNSUPPORTED':
    case 'BOOK_TOO_LARGE':
    case 'BOOK_CORRUPT':
    case 'BOOK_NOT_FOUND':
    case 'BOOK_EMPTY':
    case 'DECODE_FAILED':
    case 'IMAGE_TOO_LARGE':
      return true;
  }
  return false;
}

/// A book's cover thumbnail through the same three-tier [ThumbnailCacheService]
/// image thumbnails use, so a cover is only extracted once and survives past
/// the current browsing session (cache hit: no ZIP is opened at all).
///
/// Shared by the grid, masonry and list tiles, which differ only in how they
/// lay the result out. The result carries the cover's source size (for masonry
/// cell sizing); it is 0x0 only for a cache entry written without one.
///
/// Not for books nested inside an open archive: like an APK there, such a book
/// has no container/local path of its own for the native side to open. Callers
/// only use this when `archiveContext == null`.
Future<ThumbnailWithSize> loadBookCoverThumbnail({
  required ThumbnailCacheService thumbnailCache,
  required VaultBookApi bookApi,
  required MountedContainer container,
  required String path,
  required ThumbnailCacheMode mode,
  required ThumbnailQuality quality,
}) async {
  if (mode != ThumbnailCacheMode.disabled) {
    final cached = await thumbnailCache.fetchWithSize(
      container: container,
      filePath: path,
      mode: mode,
      quality: quality,
    );
    if (cached != null && cached.$1.isNotEmpty) {
      return ThumbnailWithSize(
        bytes: cached.$1,
        width: cached.$2 ?? 0,
        height: cached.$3 ?? 0,
      );
    }
  }
  final thumb = await fetchBookCoverForThumbnail(
    bookApi: bookApi,
    container: container,
    filePath: path,
    targetSize: quality.scaledSize(180),
    quality: quality.jpegQuality,
  );
  thumbnailCache.cacheInMemory(
    container,
    path,
    thumb.bytes,
    quality,
    thumb.width,
    thumb.height,
  );
  if (mode != ThumbnailCacheMode.disabled) {
    unawaited(
      thumbnailCache.store(
        container: container,
        filePath: path,
        data: thumb.bytes,
        mode: mode,
        quality: quality,
        width: thumb.width,
        height: thumb.height,
      ),
    );
  }
  return thumb;
}
