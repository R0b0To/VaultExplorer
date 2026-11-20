import 'dart:isolate';
import 'dart:typed_data';

import 'media_index.dart';

/// The on-disk form of a [MediaIndexSnapshot] (`/.vaultexplorer/media_index.bin`).
///
/// ```
/// header (16 B, little-endian)
///   "VXMI" | version u16 | flags u16 | count u32 | crc32-of-body u32
/// body, five parallel arrays of `count` entries, sorted by hash
///   hash i64[] | size i64[] | mtime u32[] | width u32[] | height u32[]
/// ```
///
/// Everything is validated on read (magic, version, exact length, checksum,
/// ascending hashes): a torn or damaged file is not an error, it is simply "no
/// index", and the next save replaces it. The index is a cache; the worst case
/// is measuring the folder again.
abstract final class MediaIndexCodec {
  static const int version = 1;
  static const int headerSize = 16;
  static const int entrySize = 8 + 8 + 4 + 4 + 4;

  /// At this many entries the work runs in a background isolate, so saving or
  /// loading a big index never costs a frame.
  static const int isolateThreshold = 20000;

  static Uint8List encode(MediaIndexSnapshot s) {
    final n = s.length;
    final bytes = Uint8List(headerSize + n * entrySize);
    final data = ByteData.sublistView(bytes);
    var o = headerSize;
    for (var i = 0; i < n; i++, o += 8) {
      data.setInt64(o, s.hashes[i], Endian.little);
    }
    for (var i = 0; i < n; i++, o += 8) {
      data.setInt64(o, s.sizes[i], Endian.little);
    }
    for (var i = 0; i < n; i++, o += 4) {
      data.setUint32(o, s.mtimes[i], Endian.little);
    }
    for (var i = 0; i < n; i++, o += 4) {
      data.setUint32(o, s.widths[i], Endian.little);
    }
    for (var i = 0; i < n; i++, o += 4) {
      data.setUint32(o, s.heights[i], Endian.little);
    }
    bytes[0] = 0x56; // V
    bytes[1] = 0x58; // X
    bytes[2] = 0x4d; // M
    bytes[3] = 0x49; // I
    data.setUint16(4, version, Endian.little);
    data.setUint16(6, 0, Endian.little);
    data.setUint32(8, n, Endian.little);
    data.setUint32(12, crc32(bytes, headerSize, bytes.length), Endian.little);
    return bytes;
  }

  /// The snapshot stored in [bytes], or null if it is not a valid index.
  static MediaIndexSnapshot? decode(Uint8List bytes) {
    if (bytes.length < headerSize) return null;
    if (bytes[0] != 0x56 || bytes[1] != 0x58 || bytes[2] != 0x4d || bytes[3] != 0x49) {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    if (data.getUint16(4, Endian.little) != version) return null;
    final n = data.getUint32(8, Endian.little);
    if (n > MediaIndex.maxEntries * 2) return null;
    if (bytes.length != headerSize + n * entrySize) return null;
    if (data.getUint32(12, Endian.little) != crc32(bytes, headerSize, bytes.length)) {
      return null;
    }

    final hashes = Int64List(n);
    final sizes = Int64List(n);
    final mtimes = Uint32List(n);
    final widths = Uint32List(n);
    final heights = Uint32List(n);
    var o = headerSize;
    for (var i = 0; i < n; i++, o += 8) {
      hashes[i] = data.getInt64(o, Endian.little);
    }
    for (var i = 0; i < n; i++, o += 8) {
      sizes[i] = data.getInt64(o, Endian.little);
    }
    for (var i = 0; i < n; i++, o += 4) {
      mtimes[i] = data.getUint32(o, Endian.little);
    }
    for (var i = 0; i < n; i++, o += 4) {
      widths[i] = data.getUint32(o, Endian.little);
    }
    for (var i = 0; i < n; i++, o += 4) {
      heights[i] = data.getUint32(o, Endian.little);
    }
    for (var i = 1; i < n; i++) {
      if (hashes[i - 1] >= hashes[i]) return null; // not sorted / duplicates
    }
    return MediaIndexSnapshot(
      hashes: hashes,
      sizes: sizes,
      mtimes: mtimes,
      widths: widths,
      heights: heights,
    );
  }

  /// [encode], off the UI isolate when it is big enough to matter.
  static Future<Uint8List> encodeAsync(MediaIndexSnapshot s) {
    if (s.length < isolateThreshold) return Future.value(encode(s));
    return Isolate.run(() => encode(s));
  }

  /// [decode], off the UI isolate when it is big enough to matter.
  static Future<MediaIndexSnapshot?> decodeAsync(Uint8List bytes) {
    final n = bytes.length ~/ entrySize;
    if (n < isolateThreshold) return Future.value(decode(bytes));
    return Isolate.run(() => decode(bytes));
  }

  static final Uint32List _crcTable = () {
    final table = Uint32List(256);
    for (var i = 0; i < 256; i++) {
      var c = i;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      table[i] = c;
    }
    return table;
  }();

  /// CRC-32 (IEEE) of `bytes[start..end)`.
  static int crc32(Uint8List bytes, int start, int end) {
    var c = 0xFFFFFFFF;
    for (var i = start; i < end; i++) {
      c = _crcTable[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
