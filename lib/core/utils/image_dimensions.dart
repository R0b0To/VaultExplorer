import 'dart:typed_data';

/// Reads an image's pixel width/height directly from its own header bytes
/// -- no codec, no decode, just parsing the handful of bytes each format
/// stores its dimensions in (JPEG's SOF marker, PNG's IHDR chunk, GIF's
/// logical screen descriptor, WebP's VP8/VP8L/VP8X chunk).
///
/// [bytes] only needs to cover the file's leading header -- for JPEG that
/// can be a little further in behind a large embedded EXIF thumbnail or
/// ICC profile, but never anywhere near the whole file. Returns null if
/// [bytes] isn't a recognized format or doesn't contain enough of the
/// header to find the dimensions.
///
/// Extracted from `ImagePageItem`'s own (formerly private,
/// widget-state-scoped) copy so `MediaPrefetchController` can run the same
/// parsing directly against a small chunk read from the original file --
/// letting the continuous-scroll playlist learn real aspect ratios on a
/// genuinely cold open (nothing decoded or cached yet anywhere), rather
/// than only once each item has actually had a thumbnail generated for it.
(int width, int height)? extractImageDimensionsFromBytes(Uint8List bytes) {
  if (bytes.length < 4) return null;
  // JPEG SOF and EXIF Orientation parser
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
    int i = 2;
    int orientation = 1;
    (int, int)? dims;

    while (i < bytes.length - 1) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      while (i < bytes.length && bytes[i] == 0xFF) {
        i++;
      }
      if (i >= bytes.length) break;
      final marker = bytes[i];
      i++;

      // Standalone markers without payload
      if (marker == 0xD8 || marker == 0xD9 || (marker >= 0xD0 && marker <= 0xD7) || marker == 0x01) {
        continue;
      }
      // SOS: Start of Scan (compressed image data follows, stop metadata parsing)
      if (marker == 0xDA) break;

      if (i + 1 >= bytes.length) break;
      final len = (bytes[i] << 8) | bytes[i + 1];
      if (len < 2) break;

      final isSof = (marker >= 0xC0 && marker <= 0xC3) ||
          (marker >= 0xC5 && marker <= 0xC7) ||
          (marker >= 0xC9 && marker <= 0xCB) ||
          (marker >= 0xCD && marker <= 0xCF);
      if (isSof && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
        if (i + 6 < bytes.length) {
          final h = (bytes[i + 3] << 8) | bytes[i + 4];
          final w = (bytes[i + 5] << 8) | bytes[i + 6];
          if (w > 0 && h > 0) {
            dims = (w, h);
          }
        }
      } else if (marker == 0xE1 && i + 8 <= bytes.length) {
        // Exif in APP1
        if (bytes[i + 2] == 0x45 &&
            bytes[i + 3] == 0x78 &&
            bytes[i + 4] == 0x69 &&
            bytes[i + 5] == 0x66 &&
            bytes[i + 6] == 0x00 &&
            bytes[i + 7] == 0x00) {
          final exifStart = i + 8;
          if (exifStart + 8 <= bytes.length) {
            final isLittleEndian = bytes[exifStart] == 0x49 && bytes[exifStart + 1] == 0x49;
            final isBigEndian = bytes[exifStart] == 0x4D && bytes[exifStart + 1] == 0x4D;
            if (isLittleEndian || isBigEndian) {
              int readUint16(int offset) {
                if (offset + 1 >= bytes.length) return 0;
                return isLittleEndian
                    ? bytes[offset] | (bytes[offset + 1] << 8)
                    : (bytes[offset] << 8) | bytes[offset + 1];
              }
              int readUint32(int offset) {
                if (offset + 3 >= bytes.length) return 0;
                return isLittleEndian
                    ? bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)
                    : (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
              }

              final firstIfdOffset = readUint32(exifStart + 4);
              final ifd0Start = exifStart + firstIfdOffset;
              if (ifd0Start >= exifStart && ifd0Start + 2 <= bytes.length) {
                final entryCount = readUint16(ifd0Start);
                for (int e = 0; e < entryCount; e++) {
                  final entryOffset = ifd0Start + 2 + e * 12;
                  if (entryOffset + 10 > bytes.length) break;
                  final tag = readUint16(entryOffset);
                  if (tag == 0x0112) {
                    orientation = readUint16(entryOffset + 8);
                    break;
                  }
                }
              }
            }
          }
        }
      }

      if (dims != null && orientation != 1) {
        break;
      }
      i += len;
    }

    if (dims != null) {
      if (orientation >= 5 && orientation <= 8) {
        return (dims.$2, dims.$1);
      }
      return dims;
    }
  }
  // PNG header parser
  if (bytes.length >= 24 &&
      bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
    final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
    final h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
    if (w > 0 && h > 0) return (w, h);
  }
  // GIF header parser
  if (bytes.length >= 10 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    final w = bytes[6] | (bytes[7] << 8);
    final h = bytes[8] | (bytes[9] << 8);
    if (w > 0 && h > 0) return (w, h);
  }
  // WebP (RIFF....WEBP)
  if (bytes.length >= 30 &&
      bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
      bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
    // VP8 (lossy)
    if (bytes[12] == 0x56 && bytes[13] == 0x50 && bytes[14] == 0x38 && bytes[15] == 0x20) {
      final w = ((bytes[27] & 0x3F) << 8) | bytes[26];
      final h = ((bytes[29] & 0x3F) << 8) | bytes[28];
      if (w > 0 && h > 0) return (w, h);
    }
    // VP8L (lossless)
    if (bytes.length >= 25 &&
        bytes[12] == 0x56 && bytes[13] == 0x50 && bytes[14] == 0x38 && bytes[15] == 0x4C) {
      if (bytes[16] == 0x2F) {
        final w = 1 + (((bytes[18] & 0x3F) << 8) | bytes[17]);
        final h = 1 + (((bytes[20] & 0x0F) << 10) | (bytes[19] << 2) | ((bytes[18] & 0xC0) >> 6));
        if (w > 0 && h > 0) return (w, h);
      }
    }
    // VP8X (extended)
    if (bytes[12] == 0x56 && bytes[13] == 0x50 && bytes[14] == 0x38 && bytes[15] == 0x58) {
      final w = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
      final h = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
      if (w > 0 && h > 0) return (w, h);
    }
  }
  // AVIF / HEIC (ISOBMFF with 'ispe' box)
  if (bytes.length >= 16 &&
      bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) {
    for (int j = 0; j <= bytes.length - 16; j++) {
      if (bytes[j] == 0x69 && bytes[j + 1] == 0x73 && bytes[j + 2] == 0x70 && bytes[j + 3] == 0x65) {
        final w = (bytes[j + 8] << 24) | (bytes[j + 9] << 16) | (bytes[j + 10] << 8) | bytes[j + 11];
        final h = (bytes[j + 12] << 24) | (bytes[j + 13] << 16) | (bytes[j + 14] << 8) | bytes[j + 15];
        if (w > 0 && h > 0 && w < 100000 && h < 100000) {
          return (w, h);
        }
      }
    }
  }
  return null;
}
