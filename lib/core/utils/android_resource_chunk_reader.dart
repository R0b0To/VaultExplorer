library;

import 'dart:convert';
import 'dart:typed_data';

/// Low-level reader for the chunk-based binary container format aapt/aapt2
/// compiles both `AndroidManifest.xml` (binary XML, "AXML") and
/// `resources.arsc` (the resource table) into.
///
/// Both formats share the same envelope -- a `ResChunk_header` (type,
/// headerSize, size) opening every chunk, and the same `ResStringPool`
/// layout for every string table either format embeds -- so the low-level
/// reading lives here once instead of being duplicated between
/// [findApplicationIconResourceId] (`android_manifest_icon_parser.dart`)
/// and [resolveIconResourcePath] (`android_resource_table_parser.dart`).
///
/// This is a deliberately partial reimplementation of the format AOSP
/// documents in `frameworks/base/libs/androidfw/include/androidfw/ResourceTypes.h`
/// -- just enough to resolve `android:icon` on `<application>` down to a
/// file path inside the APK. It is not a general-purpose AXML/ARSC parser.
///
/// Every entry point that takes raw bytes from an untrusted APK validates
/// bounds before reading and is expected to be wrapped in a try/catch by
/// its caller ([AndroidChunkReader.readU8]/etc. throw [RangeError] on a
/// truncated/malformed chunk rather than reading out of bounds) -- a
/// corrupt or adversarially-crafted APK should fail this parse gracefully,
/// never crash the app.


/// Chunk type constants from `ResourceTypes.h`. Only the ones this
/// feature's two parsers actually branch on are named; every other chunk
/// type is skipped by advancing past its `size` unread.
class AndroidChunkType {
  static const resStringPool = 0x0001;
  static const resTable = 0x0002;
  static const resXml = 0x0003;
  static const resXmlStartElement = 0x0102;
  static const resXmlEndElement = 0x0103;
  static const resXmlResourceMap = 0x0180;
  static const resTablePackage = 0x0200;
  static const resTableType = 0x0201;

  const AndroidChunkType._();
}

/// `Res_value.dataType` constants this feature cares about.
class AndroidResValueType {
  static const typeReference = 0x01;
  static const typeString = 0x03;
  static const typeDynamicReference = 0x07;

  const AndroidResValueType._();
}

/// A parsed `ResChunk_header`: `{u16 type; u16 headerSize; u32 size;}`.
class AndroidChunkHeader {
  final int type;
  final int headerSize;
  final int size;
  const AndroidChunkHeader(this.type, this.headerSize, this.size);
}

/// Thin wrapper over a [ByteData] view of one file's bytes (an
/// `AndroidManifest.xml` or `resources.arsc` extracted from an APK), with
/// little-endian fixed-width reads and the one piece of variable-length
/// structure both formats share: the string pool.
class AndroidChunkReader {
  final Uint8List bytes;
  final ByteData data;
  final int length;

  AndroidChunkReader(this.bytes)
      : data = ByteData.sublistView(bytes),
        length = bytes.length;

  int readU8(int offset) => data.getUint8(offset);
  int readU16(int offset) => data.getUint16(offset, Endian.little);
  int readU32(int offset) => data.getUint32(offset, Endian.little);

  AndroidChunkHeader readChunkHeader(int offset) => AndroidChunkHeader(
        readU16(offset),
        readU16(offset + 2),
        readU32(offset + 4),
      );

  /// Parses a `ResStringPool` chunk (`ResourceTypes.h`'s
  /// `ResStringPool_header` + its offset/data regions) starting at
  /// [chunkOffset], returning every string it holds in index order.
  ///
  /// Each string's start is looked up independently via the offsets array
  /// (`chunkOffset + headerSize + 4*i`), so unlike a real streaming
  /// decoder this doesn't need to track a moving cursor across entries --
  /// only [flags]'s `UTF8_FLAG` (bit 0x100) to know which of the two
  /// length-prefix encodings apply.
  List<String> parseStringPool(int chunkOffset) {
    final header = readChunkHeader(chunkOffset);
    if (header.type != AndroidChunkType.resStringPool) {
      throw const FormatException('Expected a string pool chunk');
    }
    final stringCount = readU32(chunkOffset + 8);
    final flags = readU32(chunkOffset + 16);
    final stringsStart = readU32(chunkOffset + 20);
    final isUtf8 = (flags & 0x100) != 0;
    final base = chunkOffset + stringsStart;

    final strings = List<String>.filled(stringCount, '');
    for (var i = 0; i < stringCount; i++) {
      final entryOffset = readU32(chunkOffset + 28 + 4 * i);
      var pos = base + entryOffset;
      if (isUtf8) {
        // Leading "UTF-16 length" prefix (character count) -- not needed
        // to decode the UTF-8 bytes that follow, but must still be
        // skipped: 1 byte, or 2 if the high bit of the first is set.
        final b0 = readU8(pos);
        pos += (b0 & 0x80) != 0 ? 2 : 1;
        // "UTF-8 length" prefix (byte count) -- same variable-width
        // encoding, this one we actually need.
        final b1 = readU8(pos);
        int byteLen;
        if ((b1 & 0x80) != 0) {
          byteLen = ((b1 & 0x7F) << 8) | readU8(pos + 1);
          pos += 2;
        } else {
          byteLen = b1;
          pos += 1;
        }
        strings[i] = utf8DecodeLenient(
          Uint8List.sublistView(bytes, pos, pos + byteLen),
        );
      } else {
        final u = readU16(pos);
        int charLen;
        if ((u & 0x8000) != 0) {
          charLen = ((u & 0x7FFF) << 16) | readU16(pos + 2);
          pos += 4;
        } else {
          charLen = u;
          pos += 2;
        }
        strings[i] = _decodeUtf16Le(pos, charLen);
      }
    }
    return strings;
  }

  String _decodeUtf16Le(int byteOffset, int charLen) {
    final units = Uint16List(charLen);
    for (var i = 0; i < charLen; i++) {
      units[i] = readU16(byteOffset + i * 2);
    }
    return String.fromCharCodes(units);
  }
}

/// Lenient UTF-8 decode that never throws on malformed input -- an APK is
/// untrusted input, and a single bad string (e.g. in a resource this
/// feature doesn't even end up using) shouldn't abort the whole parse.
String utf8DecodeLenient(Uint8List bytes) {
  try {
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return '';
  }
}
