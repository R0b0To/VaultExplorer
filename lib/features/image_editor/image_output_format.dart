/// How the image editor encodes an edited picture when saving.
///
/// `dart:ui` can only encode PNG, and PNG is lossless. Re-encoding a JPEG
/// photo as PNG typically makes it several times larger, so a crop that
/// throws away 75% of the pixels could still make the file *bigger*. The
/// editor therefore saves in the same family as the file it opened: lossy
/// sources (JPEG, WebP) are re-encoded lossy by the platform encoder, and
/// everything else keeps the lossless PNG path.
library;

/// Encoding used for a saved image.
enum ImageOutputFormat { png, jpeg, webp }

/// Starting quality (1-100) for lossy output. High enough to be visually
/// indistinguishable from the source for photos; the native encoder lowers it
/// only if needed to honour a size budget (see [imageSizeBudgetBytes]).
const int kLossyEncodeQuality = 92;

/// Picks the output format for a file with the given (case-insensitive)
/// extension, without the leading dot.
///
/// Anything that is not JPEG or WebP - PNG itself, but also AVIF, GIF, BMP
/// and unknown types - is written as PNG, because that is the only encoder
/// available without the native side.
ImageOutputFormat imageOutputFormatForExtension(String extension) {
  switch (extension.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
      return ImageOutputFormat.jpeg;
    case 'webp':
      return ImageOutputFormat.webp;
    default:
      return ImageOutputFormat.png;
  }
}

/// File extension (no dot, lower case) that matches [format], keeping the
/// user's own `jpeg` spelling when that is what the source used.
String imageOutputExtension(ImageOutputFormat format, String sourceExtension) {
  switch (format) {
    case ImageOutputFormat.png:
      return 'png';
    case ImageOutputFormat.jpeg:
      return sourceExtension.toLowerCase() == 'jpeg' ? 'jpeg' : 'jpg';
    case ImageOutputFormat.webp:
      return 'webp';
  }
}

/// The largest size, in bytes, an edited lossy image should have, or `null`
/// when its size should not be constrained.
///
/// When an edit leaves fewer pixels than the original (a crop), the file
/// should not end up larger than the same share of the original file: keeping
/// a quarter of the pixels should never cost more than a quarter of the
/// bytes. A source that was already heavily compressed could otherwise come
/// out *bigger* per pixel than it went in, because the re-encode starts at
/// [kLossyEncodeQuality].
///
/// Edits that keep every pixel (annotations, or a crop that only trims the
/// rotation padding back to the original size) are not constrained.
int? imageSizeBudgetBytes({
  required int originalBytes,
  required int originalPixels,
  required int newPixels,
}) {
  if (originalBytes <= 0 || originalPixels <= 0 || newPixels <= 0) return null;
  if (newPixels >= originalPixels) return null;
  final budget = originalBytes * newPixels ~/ originalPixels;
  return budget < 1 ? 1 : budget;
}
