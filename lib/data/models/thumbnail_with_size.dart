import 'dart:typed_data';

/// A thumbnail JPEG paired with its *source* frame's pre-downscale
/// width/height, as returned by the native `getImageThumbnailWithSize` /
/// `getVideoThumbnailWithSize` channel methods.
///
/// Native already decodes these bounds while producing the thumbnail (see
/// `handleGetImageThumbnailWithSize` / `handleGetVideoThumbnailWithSize` in
/// MainActivity.kt) — reporting them costs no extra decode or I/O over the
/// byte-only `getImageThumbnail` / `getVideoThumbnail` methods, so callers
/// that need the real content aspect ratio (e.g. masonry layout) should
/// prefer this pair instead of re-deriving it from the JPEG bytes on the
/// Dart side.
class ThumbnailWithSize {
  final Uint8List bytes;
  final int width;
  final int height;

  const ThumbnailWithSize({
    required this.bytes,
    required this.width,
    required this.height,
  });

  /// The source frame's true aspect ratio (width / height). Null if either
  /// dimension is non-positive (shouldn't happen for a successful result,
  /// but guards against a malformed platform response).
  double? get aspectRatio => (width > 0 && height > 0) ? width / height : null;

  /// Parses the `{"bytes": ..., "width": ..., "height": ...}` map returned
  /// by the platform channel. Returns null if the shape doesn't match.
  static ThumbnailWithSize? fromChannelResult(Object? result) {
    if (result is! Map) return null;
    final bytes = result['bytes'];
    final width = result['width'];
    final height = result['height'];
    if (bytes is! Uint8List || width is! int || height is! int) return null;
    return ThumbnailWithSize(bytes: bytes, width: width, height: height);
  }
}
