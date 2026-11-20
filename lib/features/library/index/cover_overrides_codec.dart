import 'dart:convert';
import 'dart:typed_data';

/// Serializes the covers a person chose by hand (album or artist key -> image
/// bytes) into one blob.
///
/// Layout: the four bytes `VEC1`, a u32 count, then per entry a u16 key length,
/// the UTF-8 key, a u32 image length and the image bytes (all big-endian).
/// [decode] checks every length against the data and throws [FormatException]
/// on any mismatch, so a damaged blob is treated as "no custom covers".
class CoverOverridesCodec {
  CoverOverridesCodec._();

  static const List<int> _magic = [0x56, 0x45, 0x43, 0x31]; // 'VEC1'

  /// Upper bound on one image: guards against a corrupt length asking for a
  /// huge allocation. Covers are stored already shrunk, far below this.
  static const int maxImageBytes = 8 * 1024 * 1024;

  static Uint8List encode(Map<String, Uint8List> covers) {
    final out = BytesBuilder(copy: false);
    out.add(_magic);
    out.add(_u32(covers.length));
    covers.forEach((key, data) {
      final k = utf8.encode(key);
      out.add([(k.length >> 8) & 0xFF, k.length & 0xFF]);
      out.add(k);
      out.add(_u32(data.length));
      out.add(data);
    });
    return out.takeBytes();
  }

  static Map<String, Uint8List> decode(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    var p = 0;

    void need(int n) {
      if (p + n > bytes.length) throw const FormatException('truncated cover blob');
    }

    need(8);
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != _magic[i]) throw const FormatException('not a cover blob');
    }
    p = 4;
    final count = data.getUint32(p);
    p += 4;
    if (count > 100000) throw const FormatException('implausible cover count');

    final out = <String, Uint8List>{};
    for (var i = 0; i < count; i++) {
      need(2);
      final keyLen = data.getUint16(p);
      p += 2;
      need(keyLen);
      final key = utf8.decode(bytes.sublist(p, p + keyLen));
      p += keyLen;
      need(4);
      final len = data.getUint32(p);
      p += 4;
      if (len > maxImageBytes) throw const FormatException('implausible image size');
      need(len);
      out[key] = Uint8List.sublistView(bytes, p, p + len);
      p += len;
    }
    if (p != bytes.length) throw const FormatException('trailing bytes in cover blob');
    return out;
  }

  static List<int> _u32(int v) =>
      [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
}
