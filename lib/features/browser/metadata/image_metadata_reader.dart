import 'dart:convert';
import 'dart:io' show zlib;
import 'dart:math' as math;
import 'dart:typed_data';

import 'exif_tag_names.dart';
import 'metadata_source.dart';

/// One name/value pair of a metadata directory.
class MetadataTag {
  const MetadataTag(this.name, this.value);
  final String name;
  final String value;
}

/// A group of tags that live together in a file: `Exif IFD0`, `GPS`, `XMP`...
class MetadataDirectory {
  const MetadataDirectory(this.name, this.tags);
  final String name;
  final List<MetadataTag> tags;
}

/// Reads metadata from JPEG, PNG, WebP and HEIF files, grouped by where it
/// is stored, for the "all metadata" view. Never throws: whatever cannot be
/// read is left out.
class ImageMetadataReader {
  const ImageMetadataReader._();

  static const Set<String> readableExtensions = {
    'jpg',
    'jpeg',
    'jpe',
    'jfif',
    'png',
    'webp',
    'heic',
    'heif',
    'avif',
  };

  static bool canRead(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot >= 0 &&
        readableExtensions.contains(fileName.substring(dot + 1).toLowerCase());
  }

  /// Whether parsed XMP identifies the file as a Google/Android Motion Photo.
  ///
  /// This deliberately checks the legacy MicroVideo properties as well as
  /// the current MotionPhoto flag so editors can protect the appended video
  /// before changing the JPEG's metadata segments.
  static bool isMotionPhoto(Iterable<MetadataDirectory> directories) {
    for (final directory in directories) {
      if (directory.name.toLowerCase() != 'xmp') continue;
      for (final tag in directory.tags) {
        final key = tag.name.toLowerCase().split(':').last;
        final value = tag.value.trim().toLowerCase();
        if ((key == 'motionphoto' || key == 'microvideo') &&
            (value == '1' || value == 'true' || value == 'yes')) {
          return true;
        }
        if ((key == 'microvideooffset' || key == 'motionphotooffset') &&
            (double.tryParse(value) ?? 0) > 0) {
          return true;
        }
      }
    }
    return false;
  }

  static bool hasExtendedXmp(Iterable<MetadataDirectory> directories) =>
      directories.any((directory) => directory.name == 'XMP Extension');

  static Future<List<MetadataDirectory>> read(MetadataSource source) async {
    final s = BufferedMetadataSource(source);
    final dirs = <MetadataDirectory>[];
    try {
      final head = await s.read(0, 12);
      if (head.length >= 3 && head[0] == 0xFF && head[1] == 0xD8) {
        await _readJpeg(s, dirs);
      } else if (head.length >= 8 && head[0] == 0x89 && head[1] == 0x50) {
        await _readPng(s, dirs);
      } else if (head.length >= 12 && head[0] == 0x52 && head[8] == 0x57) {
        await _readWebp(s, dirs);
      } else if (head.length >= 12 &&
          String.fromCharCodes(head, 4, 8) == 'ftyp') {
        await _readIsoBmff(s, dirs);
      }
    } catch (_) {
      // A damaged file shows what was read before the damage.
    }
    return dirs;
  }

  // ── JPEG ─────────────────────────────────────────────────────────────────

  static Future<void> _readJpeg(
    MetadataSource s,
    List<MetadataDirectory> dirs,
  ) async {
    var o = 2;
    final frame = <MetadataTag>[];
    final comments = <MetadataTag>[];
    final pending = <MetadataDirectory>[];
    while (true) {
      final head = await s.read(o, 4);
      if (head.length < 2 || head[0] != 0xFF) break;
      final marker = head[1];
      if (marker == 0xFF) {
        o++;
        continue;
      }
      if (marker == 0xDA || marker == 0xD9) break;
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        o += 2;
        continue;
      }
      if (head.length < 4) break;
      final length = (head[2] << 8) | head[3];
      if (length < 2 || o + 2 + length > s.length) break;
      final start = o + 4;
      final end = o + 2 + length;
      if (marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC &&
          frame.isEmpty) {
        final d = await s.read(start, 6);
        if (d.length >= 6) {
          frame
            ..add(MetadataTag('Compression Type', _sofName(marker)))
            ..add(MetadataTag('Data Precision', '${d[0]} bits'))
            ..add(MetadataTag('Image Height', '${(d[1] << 8) | d[2]}'))
            ..add(MetadataTag('Image Width', '${(d[3] << 8) | d[4]}'))
            ..add(MetadataTag('Components', '${d[5]}'));
        }
      } else if (marker == 0xFE) {
        final d = await s.read(start, end - start);
        comments.add(
          MetadataTag(
            'JPEG Comment',
            utf8.decode(d, allowMalformed: true).trim(),
          ),
        );
      } else if (marker == 0xE0 ||
          marker == 0xE1 ||
          marker == 0xE2 ||
          marker == 0xED ||
          marker == 0xEE) {
        final d = await s.read(start, end - start);
        _jpegApp(marker, d, pending);
      }
      o = end;
    }
    if (frame.isNotEmpty) dirs.add(MetadataDirectory('JPEG', frame));
    dirs.addAll(pending);
    if (comments.isNotEmpty) dirs.add(MetadataDirectory('Comment', comments));
  }

  static final List<int> _exifId = [0x45, 0x78, 0x69, 0x66, 0, 0];
  static final List<int> _xmpId = ascii.encode(
    'http://ns.adobe.com/xap/1.0/\u0000',
  );
  static final List<int> _xmpExtId = ascii.encode(
    'http://ns.adobe.com/xmp/extension/\u0000',
  );
  static final List<int> _iccId = ascii.encode('ICC_PROFILE\u0000');
  static final List<int> _psId = ascii.encode('Photoshop 3.0\u0000');
  static final List<int> _jfifId = ascii.encode('JFIF\u0000');
  static final List<int> _adobeId = ascii.encode('Adobe');

  static void _jpegApp(int marker, Uint8List d, List<MetadataDirectory> out) {
    if (marker == 0xE0 && _starts(d, _jfifId) && d.length >= 14) {
      const units = [
        'None (aspect ratio)',
        'Pixels per inch',
        'Pixels per centimetre',
      ];
      out.add(
        MetadataDirectory('JFIF', [
          MetadataTag('Version', '${d[5]}.${d[6].toString().padLeft(2, '0')}'),
          MetadataTag(
            'Resolution Unit',
            d[7] < units.length ? units[d[7]] : '${d[7]}',
          ),
          MetadataTag('X Resolution', '${(d[8] << 8) | d[9]}'),
          MetadataTag('Y Resolution', '${(d[10] << 8) | d[11]}'),
        ]),
      );
    } else if (marker == 0xE1 && _starts(d, _exifId)) {
      _readTiff(Uint8List.sublistView(d, _exifId.length), out);
    } else if (marker == 0xE1 && _starts(d, _xmpId)) {
      _readXmp(
        utf8.decode(
          Uint8List.sublistView(d, _xmpId.length),
          allowMalformed: true,
        ),
        out,
      );
    } else if (marker == 0xE1 && _starts(d, _xmpExtId)) {
      out.add(
        MetadataDirectory('XMP Extension', [
          const MetadataTag('Extended packet', 'Present'),
        ]),
      );
    } else if (marker == 0xE2 && _starts(d, _iccId)) {
      // Only the first chunk: the header and tag table are in it.
      _readIcc(Uint8List.sublistView(d, _iccId.length + 2), out);
    } else if (marker == 0xED && _starts(d, _psId)) {
      _readPhotoshop(Uint8List.sublistView(d, _psId.length), out);
    } else if (marker == 0xEE && _starts(d, _adobeId) && d.length >= 12) {
      const transform = ['Unknown (RGB or CMYK)', 'YCbCr', 'YCCK'];
      out.add(
        MetadataDirectory('Adobe JPEG', [
          MetadataTag('DCT Encode Version', '${(d[5] << 8) | d[6]}'),
          MetadataTag(
            'Color Transform',
            d[11] < transform.length ? transform[d[11]] : '${d[11]}',
          ),
        ]),
      );
    }
  }

  static String _sofName(int m) => switch (m) {
    0xC0 => 'Baseline',
    0xC1 => 'Extended sequential, Huffman',
    0xC2 => 'Progressive, Huffman',
    0xC3 => 'Lossless, Huffman',
    _ => 'Baseline',
  };

  static bool _starts(List<int> b, List<int> prefix) {
    if (b.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (b[i] != prefix[i]) return false;
    }
    return true;
  }

  // ── PNG ──────────────────────────────────────────────────────────────────

  static Future<void> _readPng(
    MetadataSource s,
    List<MetadataDirectory> dirs,
  ) async {
    var o = 8;
    final text = <MetadataTag>[];
    final other = <MetadataDirectory>[];
    final header = <MetadataTag>[];
    while (o + 12 <= s.length) {
      final head = await s.read(o, 8);
      if (head.length < 8) break;
      final len = (head[0] << 24) | (head[1] << 16) | (head[2] << 8) | head[3];
      final type = String.fromCharCodes(head, 4, 8);
      final end = o + 12 + len;
      if (len < 0 || end > s.length || type == 'IEND') break;
      if (type == 'IDAT') {
        // Pixel data: jump over the run of IDAT chunks without reading them.
        o = end;
        continue;
      }
      // Big chunks that are not metadata are skipped unread.
      final readable = len <= 4 * 1024 * 1024;
      final data = readable ? await s.read(o + 8, len) : Uint8List(0);
      switch (type) {
        case 'IHDR':
          if (data.length >= 13) {
            const colour = {
              0: 'Greyscale',
              2: 'RGB',
              3: 'Palette',
              4: 'Greyscale + alpha',
              6: 'RGB + alpha',
            };
            header
              ..add(MetadataTag('Image Width', '${_be32(data, 0)}'))
              ..add(MetadataTag('Image Height', '${_be32(data, 4)}'))
              ..add(MetadataTag('Bit Depth', '${data[8]}'))
              ..add(MetadataTag('Colour Type', colour[data[9]] ?? '${data[9]}'))
              ..add(MetadataTag('Interlace', data[12] == 0 ? 'None' : 'Adam7'));
          }
        case 'pHYs':
          if (data.length >= 9) {
            final unit = data[8] == 1 ? 'pixels per metre' : '(unit unknown)';
            other.add(
              MetadataDirectory('PNG Physical', [
                MetadataTag('Pixels Per Unit X', '${_be32(data, 0)} $unit'),
                MetadataTag('Pixels Per Unit Y', '${_be32(data, 4)} $unit'),
              ]),
            );
          }
        case 'gAMA':
          if (data.length >= 4) {
            other.add(
              MetadataDirectory('PNG Gamma', [
                MetadataTag(
                  'Gamma',
                  (100000 / _be32(data, 0)).toStringAsFixed(2),
                ),
              ]),
            );
          }
        case 'sRGB':
          if (data.isNotEmpty) {
            const intents = [
              'Perceptual',
              'Relative colorimetric',
              'Saturation',
              'Absolute colorimetric',
            ];
            other.add(
              MetadataDirectory('PNG sRGB', [
                MetadataTag(
                  'Rendering Intent',
                  data[0] < intents.length ? intents[data[0]] : '${data[0]}',
                ),
              ]),
            );
          }
        case 'tIME':
          if (data.length >= 7) {
            String two(int n) => n.toString().padLeft(2, '0');
            other.add(
              MetadataDirectory('PNG Time', [
                MetadataTag(
                  'Last Modification Time',
                  '${(data[0] << 8) | data[1]}:${two(data[2])}:${two(data[3])} ${two(data[4])}:${two(data[5])}:${two(data[6])}',
                ),
              ]),
            );
          }
        case 'eXIf':
          _readTiff(data, other);
        case 'iCCP':
          final nul = data.indexOf(0);
          if (nul > 0 && data.length > nul + 2) {
            try {
              final profile = Uint8List.fromList(
                zlib.decode(data.sublist(nul + 2)),
              );
              _readIcc(profile, other);
            } on FormatException {
              other.add(
                MetadataDirectory('ICC Profile', [
                  MetadataTag(
                    'Profile Name',
                    latin1.decode(data.sublist(0, nul)),
                  ),
                ]),
              );
            }
          }
        case 'tEXt':
          final nul = data.indexOf(0);
          if (nul > 0) {
            text.add(
              MetadataTag(
                latin1.decode(data.sublist(0, nul)),
                latin1.decode(data.sublist(nul + 1)),
              ),
            );
          }
        case 'zTXt':
          final nul = data.indexOf(0);
          if (nul > 0 && data.length > nul + 2) {
            try {
              text.add(
                MetadataTag(
                  latin1.decode(data.sublist(0, nul)),
                  latin1.decode(zlib.decode(data.sublist(nul + 2))),
                ),
              );
            } on FormatException {
              // Damaged compressed text is left out.
            }
          }
        case 'iTXt':
          final nul = data.indexOf(0);
          if (nul > 0 && data.length > nul + 5) {
            final keyword = latin1.decode(data.sublist(0, nul));
            final compressed = data[nul + 1] == 1;
            final langEnd = data.indexOf(0, nul + 3);
            final transEnd = langEnd < 0 ? -1 : data.indexOf(0, langEnd + 1);
            if (transEnd >= 0) {
              var body = Uint8List.sublistView(data, transEnd + 1);
              if (compressed) {
                try {
                  body = Uint8List.fromList(zlib.decode(body));
                } on FormatException {
                  break;
                }
              }
              final value = utf8.decode(body, allowMalformed: true);
              if (keyword == 'XML:com.adobe.xmp') {
                _readXmp(value, other);
              } else {
                text.add(MetadataTag(keyword, value));
              }
            }
          }
      }
      o = end;
    }
    if (header.isNotEmpty) dirs.add(MetadataDirectory('PNG', header));
    dirs.addAll(other);
    if (text.isNotEmpty) dirs.add(MetadataDirectory('PNG Text', text));
  }

  static int _be32(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  // ── WebP ─────────────────────────────────────────────────────────────────

  static Future<void> _readWebp(
    MetadataSource s,
    List<MetadataDirectory> dirs,
  ) async {
    var o = 12;
    final info = <MetadataTag>[];
    final other = <MetadataDirectory>[];
    while (o + 8 <= s.length) {
      final head = await s.read(o, 8);
      if (head.length < 8) break;
      final fourcc = String.fromCharCodes(head, 0, 4);
      final len = head[4] | (head[5] << 8) | (head[6] << 16) | (head[7] << 24);
      if (o + 8 + len > s.length) break;
      if (fourcc == 'VP8X' && len >= 10) {
        final d = await s.read(o + 8, 10);
        info
          ..add(
            MetadataTag(
              'Canvas Width',
              '${1 + (d[4] | (d[5] << 8) | (d[6] << 16))}',
            ),
          )
          ..add(
            MetadataTag(
              'Canvas Height',
              '${1 + (d[7] | (d[8] << 8) | (d[9] << 16))}',
            ),
          )
          ..add(MetadataTag('Animation', (d[0] & 0x02) != 0 ? 'Yes' : 'No'))
          ..add(MetadataTag('Alpha', (d[0] & 0x10) != 0 ? 'Yes' : 'No'));
      } else if (fourcc == 'EXIF' && len <= 4 * 1024 * 1024) {
        var d = await s.read(o + 8, len);
        if (_starts(d, _exifId)) d = Uint8List.sublistView(d, 6);
        _readTiff(d, other);
      } else if (fourcc == 'XMP ' && len <= 4 * 1024 * 1024) {
        _readXmp(
          utf8.decode(await s.read(o + 8, len), allowMalformed: true),
          other,
        );
      } else if (fourcc == 'ICCP' && len <= 4 * 1024 * 1024) {
        _readIcc(await s.read(o + 8, len), other);
      }
      o += 8 + len + (len & 1);
    }
    if (info.isNotEmpty) dirs.add(MetadataDirectory('WebP', info));
    dirs.addAll(other);
  }

  // ── HEIF / ISO-BMFF ─────────────────────────────────────────────────────

  static const int _maxHeifMetadataBytes = 8 * 1024 * 1024;

  static Future<void> _readIsoBmff(
    BufferedMetadataSource s,
    List<MetadataDirectory> dirs,
  ) async {
    _BmffBox? meta;
    for (final box in await _readBoxes(s, 0, s.length)) {
      if (box.type == 'meta') {
        meta = box;
        break;
      }
    }
    if (meta == null || meta.end - meta.payloadStart < 4) return;

    // The MetaBox starts with version and flags before its child boxes.
    final children = await _readBoxes(s, meta.payloadStart + 4, meta.end);
    final iinf = children.where((box) => box.type == 'iinf').firstOrNull;
    final iloc = children.where((box) => box.type == 'iloc').firstOrNull;
    final idat = children.where((box) => box.type == 'idat').firstOrNull;
    if (iinf == null || iloc == null) return;

    final itemTypes = await _readHeifItemTypes(s, iinf);
    final locations = await _readHeifItemLocations(s, iloc);
    final other = <MetadataDirectory>[];

    for (final entry in itemTypes.entries) {
      final location = locations[entry.key];
      if (location == null) continue;
      final data = await _readHeifItemData(s, location, idat);
      if (data == null || data.isEmpty) continue;

      if (entry.value == 'Exif') {
        final tiff = _heifTiff(data);
        if (tiff != null) _readTiff(tiff, other);
      } else if (entry.value == 'XMP') {
        _readXmp(utf8.decode(data, allowMalformed: true), other);
      }
    }
    dirs.addAll(other);
  }

  static Future<List<_BmffBox>> _readBoxes(
    MetadataSource s,
    int start,
    int end,
  ) async {
    final boxes = <_BmffBox>[];
    var offset = start;
    while (offset + 8 <= end && boxes.length < 4096) {
      final box = await _readBox(s, offset, end);
      if (box == null || box.end <= offset) break;
      boxes.add(box);
      offset = box.end;
    }
    return boxes;
  }

  static Future<_BmffBox?> _readBox(
    MetadataSource s,
    int offset,
    int parentEnd,
  ) async {
    if (offset < 0 || parentEnd - offset < 8) return null;
    final head = await s.read(offset, 16);
    if (head.length < 8) return null;

    final size32 = _be32(head, 0);
    final type = String.fromCharCodes(head, 4, 8);
    var headerSize = 8;
    var boxSize = size32;
    if (size32 == 1) {
      if (head.length < 16) return null;
      boxSize = ByteData.sublistView(head, 8, 16).getUint64(0, Endian.big);
      headerSize = 16;
    } else if (size32 == 0) {
      boxSize = parentEnd - offset;
    }
    if (boxSize < headerSize || boxSize > parentEnd - offset) return null;
    return _BmffBox(type, offset + headerSize, offset + boxSize);
  }

  static Future<Map<int, String>> _readHeifItemTypes(
    MetadataSource s,
    _BmffBox iinf,
  ) async {
    final prefix = await s.read(iinf.payloadStart, 8);
    if (prefix.length < 6) return const {};
    final version = prefix[0];
    final entryCount = version == 0
        ? ((prefix[4] << 8) | prefix[5])
        : prefix.length >= 8
        ? _be32(prefix, 4)
        : 0;
    if (entryCount <= 0) return const {};

    var offset = iinf.payloadStart + (version == 0 ? 6 : 8);
    final items = <int, String>{};
    for (var i = 0; i < entryCount && i < 10000; i++) {
      final box = await _readBox(s, offset, iinf.end);
      if (box == null) break;
      offset = box.end;
      if (box.type != 'infe') continue;

      final length = math.min(4096, box.end - box.payloadStart);
      final data = await s.read(box.payloadStart, length);
      if (data.length < 12) continue;
      final itemVersion = data[0];
      final itemIdLength = switch (itemVersion) {
        2 => 2,
        3 => 4,
        _ => 0,
      };
      if (itemIdLength == 0) continue;
      final itemId = itemIdLength == 2
          ? (data[4] << 8) | data[5]
          : _be32(data, 4);
      final typeOffset = 4 + itemIdLength + 2;
      if (typeOffset + 4 > data.length) continue;
      final itemType = String.fromCharCodes(data, typeOffset, typeOffset + 4);
      if (itemType == 'Exif') {
        items[itemId] = 'Exif';
        continue;
      }
      if (itemType != 'mime') continue;

      final nameStart = typeOffset + 4;
      final nameEnd = _zeroByteAt(data, nameStart);
      if (nameEnd < 0) continue;
      final contentStart = nameEnd + 1;
      final contentEnd = _zeroByteAt(data, contentStart);
      if (contentEnd < 0) continue;
      final contentType = latin1.decode(
        Uint8List.sublistView(data, contentStart, contentEnd),
      );
      if (contentType.toLowerCase() == 'application/rdf+xml') {
        items[itemId] = 'XMP';
      }
    }
    return items;
  }

  static int _zeroByteAt(Uint8List bytes, int start) {
    for (var i = start; i < bytes.length; i++) {
      if (bytes[i] == 0) return i;
    }
    return -1;
  }

  static Future<Map<int, _HeifItemLocation>> _readHeifItemLocations(
    MetadataSource s,
    _BmffBox iloc,
  ) async {
    final length = math.min(1 << 20, iloc.end - iloc.payloadStart);
    final data = await s.read(iloc.payloadStart, length);
    if (data.length < 8) return const {};

    final version = data[0];
    final offsetSize = data[4] >> 4;
    final lengthSize = data[4] & 0x0F;
    final baseOffsetSize = data[5] >> 4;
    final indexSize = version == 0 ? 0 : data[5] & 0x0F;
    var cursor = 6;

    int? readUnsigned(int size) {
      if (size < 0 || size > 8 || cursor + size > data.length) return null;
      var value = 0;
      for (var i = 0; i < size; i++) {
        value = (value << 8) | data[cursor++];
      }
      return value < 0 ? null : value;
    }

    final itemCount = readUnsigned(version < 2 ? 2 : 4);
    if (itemCount == null || itemCount > 10000) return const {};
    final locations = <int, _HeifItemLocation>{};

    for (var i = 0; i < itemCount; i++) {
      final itemId = readUnsigned(version < 2 ? 2 : 4);
      if (itemId == null) break;
      var constructionMethod = 0;
      if (version == 1 || version == 2) {
        final method = readUnsigned(2);
        if (method == null) break;
        constructionMethod = method & 0x0F;
      }
      final dataReferenceIndex = readUnsigned(2);
      final baseOffset = readUnsigned(baseOffsetSize);
      final extentCount = readUnsigned(2);
      if (dataReferenceIndex == null ||
          baseOffset == null ||
          extentCount == null ||
          extentCount > 256) {
        break;
      }

      final extents = <_HeifExtent>[];
      var malformed = false;
      for (var j = 0; j < extentCount; j++) {
        if ((version == 1 || version == 2) && indexSize > 0) {
          if (readUnsigned(indexSize) == null) {
            malformed = true;
            break;
          }
        }
        final extentOffset = readUnsigned(offsetSize);
        final extentLength = readUnsigned(lengthSize);
        if (extentOffset == null || extentLength == null) {
          malformed = true;
          break;
        }
        extents.add(_HeifExtent(extentOffset, extentLength));
      }
      if (malformed) break;
      locations[itemId] = _HeifItemLocation(
        constructionMethod: constructionMethod,
        dataReferenceIndex: dataReferenceIndex,
        baseOffset: baseOffset,
        extents: extents,
      );
    }
    return locations;
  }

  static Future<Uint8List?> _readHeifItemData(
    MetadataSource s,
    _HeifItemLocation item,
    _BmffBox? idat,
  ) async {
    if (item.dataReferenceIndex != 0 ||
        (item.constructionMethod != 0 && item.constructionMethod != 1) ||
        item.extents.isEmpty) {
      return null;
    }
    if (item.constructionMethod == 1 && idat == null) return null;

    final builder = BytesBuilder(copy: false);
    var total = 0;
    for (final extent in item.extents) {
      final dataStart = item.constructionMethod == 1 ? idat!.payloadStart : 0;
      final dataEnd = item.constructionMethod == 1 ? idat!.end : s.length;
      final start = dataStart + item.baseOffset + extent.offset;
      if (start < dataStart || start > dataEnd) return null;
      final length = extent.length == 0 ? dataEnd - start : extent.length;
      if (length < 0 ||
          start + length > dataEnd ||
          total + length > _maxHeifMetadataBytes) {
        return null;
      }
      final bytes = await s.read(start, length);
      if (bytes.length != length) return null;
      builder.add(bytes);
      total += length;
    }
    return builder.takeBytes();
  }

  static Uint8List? _heifTiff(Uint8List item) {
    if (item.length >= 8 &&
        ((item[0] == 0x49 && item[1] == 0x49) ||
            (item[0] == 0x4D && item[1] == 0x4D))) {
      return item;
    }
    if (item.length < 4) return null;
    final offset = _be32(item, 0);
    final start = 4 + offset;
    if (start < 4 || start + 8 > item.length) return null;
    var tiff = Uint8List.sublistView(item, start);
    if (_starts(tiff, _exifId)) {
      tiff = Uint8List.sublistView(tiff, _exifId.length);
    }
    return tiff;
  }
  // ── Exif / TIFF ──────────────────────────────────────────────────────────

  static void _readTiff(Uint8List t, List<MetadataDirectory> out) {
    if (t.length < 8) return;
    final le = t[0] == 0x49 && t[1] == 0x49;
    if (!le && !(t[0] == 0x4D && t[1] == 0x4D)) return;
    final r = _Tiff(t, le);
    final visited = <int>{};

    void walk(
      int offset,
      String name,
      String Function(int) tagName,
      int depth,
    ) {
      if (depth > 4 ||
          offset < 8 ||
          offset + 2 > t.length ||
          !visited.add(offset))
        return;
      final n = r.u16(offset);
      final tags = <MetadataTag>[];
      var exif = 0;
      var gps = 0;
      var interop = 0;
      for (var i = 0; i < n; i++) {
        final p = offset + 2 + i * 12;
        if (p + 12 > t.length) break;
        final tag = r.u16(p);
        if (tag == 0x8769 && name != 'GPS') {
          exif = r.u32(p + 8);
          continue;
        }
        if (tag == 0x8825 && name != 'GPS') {
          gps = r.u32(p + 8);
          continue;
        }
        if (tag == 0xA005) {
          interop = r.u32(p + 8);
          continue;
        }
        final value = _formatTiffValue(r, p, name, tag);
        if (value == null) continue;
        tags.add(MetadataTag(tagName(tag), value));
      }
      if (tags.isNotEmpty) out.add(MetadataDirectory(name, tags));
      if (exif != 0) walk(exif, 'Exif', ExifTagNames.exif, depth + 1);
      if (gps != 0) walk(gps, 'GPS', ExifTagNames.gps, depth + 1);
      if (interop != 0)
        walk(interop, 'Interoperability', ExifTagNames.interop, depth + 1);
      if (name == 'Exif IFD0') {
        final nextAt = offset + 2 + n * 12;
        if (nextAt + 4 <= t.length) {
          final next = r.u32(nextAt);
          if (next != 0)
            walk(next, 'Exif Thumbnail', ExifTagNames.ifd0, depth + 1);
        }
      }
    }

    walk(r.u32(4), 'Exif IFD0', ExifTagNames.ifd0, 0);
  }

  static String? _formatTiffValue(_Tiff r, int entry, String dir, int tag) {
    final type = r.u16(entry + 2);
    final count = r.u32(entry + 4);
    final size = _Tiff.typeSize(type) * count;
    if (size <= 0 || count > 1 << 20) return null;
    final at = size <= 4 ? entry + 8 : r.u32(entry + 8);
    if (at < 0 || at + size > r.t.length) return null;

    final isGps = dir == 'GPS';
    if (type == 2) {
      var end = at + count;
      for (var i = at; i < at + count; i++) {
        if (r.t[i] == 0) {
          end = i;
          break;
        }
      }
      return utf8
          .decode(Uint8List.sublistView(r.t, at, end), allowMalformed: true)
          .trim();
    }
    if (type == 7 || type == 1) {
      if (!isGps && tag == 0x927C) return '($count bytes)';
      if (tag == 0x9000 || tag == 0xA000 || (isGps && tag == 0)) {
        if (tag == 0x9000 || tag == 0xA000) {
          final v = String.fromCharCodes(r.t, at, at + math.min(4, count));
          return v.length == 4 ? '${v.substring(0, 2)}.${v.substring(2)}' : v;
        }
        return Uint8List.sublistView(r.t, at, at + count).join('.');
      }
      if (tag == 0x9286)
        return _userComment(Uint8List.sublistView(r.t, at, at + count));
      if (tag == 0x9101) {
        const names = {
          0: '-',
          1: 'Y',
          2: 'Cb',
          3: 'Cr',
          4: 'R',
          5: 'G',
          6: 'B',
        };
        return List.generate(count, (i) => names[r.t[at + i]] ?? '?').join(',');
      }
      if (tag == 0xA300 && count == 1)
        return r.t[at] == 3 ? 'Digital Camera' : '${r.t[at]}';
      if (tag == 0xA301 && count == 1)
        return r.t[at] == 1 ? 'Directly photographed' : '${r.t[at]}';
      if (count > 16) return '($count bytes)';
      if (count == 1) return _enumValue(dir, tag, r.t[at]) ?? '${r.t[at]}';
      return List.generate(count, (i) => r.t[at + i]).join(', ');
    }
    // Windows XP tags are UTF-16LE strings stored as bytes (type 1) handled
    // above only when short; their ids are listed here for the common case.
    if (tag >= 0x9C9B && tag <= 0x9C9F) return null;

    final values = <num>[];
    final shown = math.min(count, 16);
    for (var i = 0; i < shown; i++) {
      final p = at + i * _Tiff.typeSize(type);
      values.add(switch (type) {
        3 => r.u16(p),
        4 => r.u32(p),
        6 => r.t[p] > 127 ? r.t[p] - 256 : r.t[p],
        8 => _signed(r.u16(p), 16),
        9 => _signed(r.u32(p), 32),
        5 => r.u32(p + 4) == 0 ? 0.0 : r.u32(p) / r.u32(p + 4),
        10 =>
          r.u32(p + 4) == 0
              ? 0.0
              : _signed(r.u32(p), 32) / _signed(r.u32(p + 4), 32),
        11 => _float32(r, p),
        12 => _float64(r, p),
        _ => 0,
      });
    }
    if (values.isEmpty) return null;
    final rational = type == 5 || type == 10;

    if (count == 1) {
      final v = values.first;
      final special = _formatSingle(dir, tag, v);
      if (special != null) return special;
      if (rational) return _trim(v.toDouble());
      return '${v is double ? _trim(v) : v}';
    }
    if (isGps &&
        (tag == 0x02 || tag == 0x04 || tag == 0x14 || tag == 0x16) &&
        values.length >= 3) {
      return _dms(
        values[0].toDouble(),
        values[1].toDouble(),
        values[2].toDouble(),
      );
    }
    if (isGps && tag == 0x07 && values.length >= 3) {
      String two(num v) => v.toInt().toString().padLeft(2, '0');
      return '${two(values[0])}:${two(values[1])}:${two(values[2])} UTC';
    }
    final text = values.map((v) => v is double ? _trim(v) : '$v').join(', ');
    return count > shown ? '$text, ...' : text;
  }

  static String? _formatSingle(String dir, int tag, num v) {
    final isGps = dir == 'GPS';
    if (isGps) {
      switch (tag) {
        case 0x06:
          return '${_trim(v.toDouble())} m';
        case 0x05:
          return v == 0 ? 'Above sea level' : 'Below sea level';
        case 0x0B:
          return _trim(v.toDouble());
        case 0x0D:
          return _trim(v.toDouble());
        case 0x11:
          return '${_trim(v.toDouble())}°';
      }
      return null;
    }
    switch (tag) {
      case 0x829A:
        final d = v.toDouble();
        if (d <= 0) return '0 s';
        return d < 1 ? '1/${(1 / d).round()} s' : '${_trim(d)} s';
      case 0x829D:
        return 'f/${_trim(v.toDouble())}';
      case 0x920A:
        return '${_trim(v.toDouble())} mm';
      case 0xA405:
        return '${v.toInt()} mm';
      case 0x9204:
        final d = v.toDouble();
        return '${d > 0 ? '+' : ''}${_trim(d)} EV';
      case 0x9202:
      case 0x9205:
        return 'f/${_trim(math.pow(2, v.toDouble() / 2).toDouble())}';
      case 0x9201:
        final t = math.pow(2, -v.toDouble()).toDouble();
        return t < 1 ? '1/${(1 / t).round()} s' : '${_trim(t)} s';
      case 0x9206:
        return '${_trim(v.toDouble())} m';
      case 0x011A:
      case 0x011B:
        return _trim(v.toDouble());
      case 0x8827:
        return '${v.toInt()}';
    }
    return _enumValue(dir, tag, v.toInt());
  }

  static String? _enumValue(String dir, int tag, int v) {
    String? pick(Map<int, String> m) => m[v];
    switch (tag) {
      case 0x0112:
        return pick(const {
          1: 'Top-left (normal)',
          2: 'Top-right (mirrored)',
          3: 'Bottom-right (rotate 180°)',
          4: 'Bottom-left (flipped)',
          5: 'Left-top (mirrored, rotate 270° CW)',
          6: 'Right-top (rotate 90° CW)',
          7: 'Right-bottom (mirrored, rotate 90° CW)',
          8: 'Left-bottom (rotate 270° CW)',
        });
      case 0x0128:
      case 0xA210:
        return pick(const {1: 'None', 2: 'Inches', 3: 'Centimetres'});
      case 0x0103:
        return pick(const {
          1: 'Uncompressed',
          6: 'JPEG (old-style)',
          7: 'JPEG',
        });
      case 0x0106:
        return pick(const {1: 'BlackIsZero', 2: 'RGB', 6: 'YCbCr'});
      case 0x0213:
        return pick(const {1: 'Centered', 2: 'Co-sited'});
      case 0x8822:
        return pick(const {
          0: 'Not defined',
          1: 'Manual',
          2: 'Program AE',
          3: 'Aperture priority',
          4: 'Shutter priority',
          5: 'Creative program',
          6: 'Action program',
          7: 'Portrait mode',
          8: 'Landscape mode',
        });
      case 0x9207:
        return pick(const {
          0: 'Unknown',
          1: 'Average',
          2: 'Center-weighted average',
          3: 'Spot',
          4: 'Multi-spot',
          5: 'Multi-segment',
          6: 'Partial',
          255: 'Other',
        });
      case 0x9208:
        return pick(const {
          0: 'Unknown',
          1: 'Daylight',
          2: 'Fluorescent',
          3: 'Tungsten',
          4: 'Flash',
          9: 'Fine weather',
          10: 'Cloudy',
          11: 'Shade',
          12: 'Daylight fluorescent',
          17: 'Standard light A',
          18: 'Standard light B',
          19: 'Standard light C',
          20: 'D55',
          21: 'D65',
          22: 'D75',
          255: 'Other',
        });
      case 0x9209:
        final fired = (v & 1) != 0 ? 'Flash fired' : 'Flash did not fire';
        final mode = switch ((v >> 3) & 3) {
          1 => ', compulsory',
          2 => ', suppressed',
          3 => ', auto',
          _ => '',
        };
        return '$fired$mode';
      case 0xA001:
        return pick(const {1: 'sRGB', 2: 'Adobe RGB', 0xFFFF: 'Uncalibrated'});
      case 0xA217:
        return pick(const {
          1: 'Not defined',
          2: 'One-chip colour area',
          3: 'Two-chip colour area',
          4: 'Three-chip colour area',
          5: 'Colour sequential area',
          7: 'Trilinear',
          8: 'Colour sequential linear',
        });
      case 0xA401:
        return pick(const {0: 'Normal', 1: 'Custom'});
      case 0xA402:
        return pick(const {0: 'Auto', 1: 'Manual', 2: 'Auto bracket'});
      case 0xA403:
        return pick(const {0: 'Auto', 1: 'Manual'});
      case 0xA406:
        return pick(const {
          0: 'Standard',
          1: 'Landscape',
          2: 'Portrait',
          3: 'Night scene',
        });
      case 0xA407:
        return pick(const {
          0: 'None',
          1: 'Low gain up',
          2: 'High gain up',
          3: 'Low gain down',
          4: 'High gain down',
        });
      case 0xA408:
        return pick(const {0: 'Normal', 1: 'Low', 2: 'High'});
      case 0xA409:
        return pick(const {0: 'Normal', 1: 'Low', 2: 'High'});
      case 0xA40A:
        return pick(const {0: 'Normal', 1: 'Soft', 2: 'Hard'});
      case 0xA40C:
        return pick(const {
          0: 'Unknown',
          1: 'Macro',
          2: 'Close view',
          3: 'Distant view',
        });
    }
    return null;
  }

  static String _userComment(Uint8List b) {
    if (b.length <= 8) return '';
    final body = Uint8List.sublistView(b, 8);
    return utf8
        .decode(body, allowMalformed: true)
        .replaceAll('\u0000', '')
        .trim();
  }

  static String _dms(double d, double m, double s) =>
      "${d.toInt()}° ${m.toInt()}' ${s.toStringAsFixed(2)}\"";

  static int _signed(int v, int bits) =>
      v >= (1 << (bits - 1)) ? v - (1 << bits) : v;

  static double _float32(_Tiff r, int p) => ByteData.sublistView(
    r.t,
    p,
    p + 4,
  ).getFloat32(0, r.little ? Endian.little : Endian.big);
  static double _float64(_Tiff r, int p) => ByteData.sublistView(
    r.t,
    p,
    p + 8,
  ).getFloat64(0, r.little ? Endian.little : Endian.big);

  static String _trim(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    var s = v.toStringAsFixed(4);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
  }

  // ── XMP ──────────────────────────────────────────────────────────────────

  static void _readXmp(String xmp, List<MetadataDirectory> out) {
    final tags = <MetadataTag>[];
    final skip = RegExp(r'^(xmlns(:|$)|rdf:about$)');

    // Properties written as attributes of rdf:Description.
    for (final d in RegExp(r'<rdf:Description\b([^>]*?)/?>').allMatches(xmp)) {
      for (final a in RegExp(
        r'''([\w.\-]+:[\w.\-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
      ).allMatches(d[1]!)) {
        final name = a[1]!;
        if (skip.hasMatch(name)) continue;
        tags.add(MetadataTag(name, _unescape(a[2] ?? a[3] ?? '')));
      }
    }
    // Properties written as elements: simple values and rdf lists. Each
    // rdf:Description is read on its own; the pattern for "an element" must
    // not swallow the next Description.
    final prop = RegExp(
      r'<((?!rdf:)[\w.\-]+:[\w.\-]+)\b[^>]*?(?:/>|>(.*?)</\1>)',
      dotAll: true,
    );
    for (final d in RegExp(
      r'<rdf:Description\b[^>]*?[^/]>(.*?)</rdf:Description>',
      dotAll: true,
    ).allMatches(xmp)) {
      for (final m in prop.allMatches(d[1]!)) {
        final name = m[1]!;
        final content = m[2] ?? '';
        final items = RegExp(r'<rdf:li[^>]*>(.*?)</rdf:li>', dotAll: true)
            .allMatches(content)
            .map(
              (l) => _unescape(l[1]!.replaceAll(RegExp(r'<[^>]+>'), '').trim()),
            )
            .where((v) => v.isNotEmpty)
            .toList();
        final value = items.isNotEmpty
            ? items.join(', ')
            : _unescape(
                content
                    .replaceAll(RegExp(r'<[^>]+>'), ' ')
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .trim(),
              );
        if (value.isEmpty) continue;
        tags.add(
          MetadataTag(
            name,
            value.length > 400 ? '${value.substring(0, 400)}…' : value,
          ),
        );
      }
    }
    if (tags.isNotEmpty) out.add(MetadataDirectory('XMP', tags));
  }

  static String _unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  // ── ICC profile ──────────────────────────────────────────────────────────

  static void _readIcc(Uint8List p, List<MetadataDirectory> out) {
    if (p.length < 132) return;
    String four(int o) => String.fromCharCodes(p, o, o + 4).trim();
    final tags = <MetadataTag>[
      MetadataTag('Profile Size', '${_be32(p, 0)} bytes'),
      if (four(4).isNotEmpty) MetadataTag('Preferred CMM', four(4)),
      MetadataTag('Profile Version', '${p[8]}.${p[9] >> 4}.${p[9] & 0xF}'),
      MetadataTag('Profile Class', _iccClass(four(12))),
      MetadataTag('Colour Space', four(16)),
      MetadataTag('Connection Space', four(20)),
      MetadataTag(
        'Created',
        '${(p[24] << 8) | p[25]}:${_two((p[26] << 8) | p[27])}:${_two((p[28] << 8) | p[29])}',
      ),
    ];
    // Profile description: tag 'desc' in the tag table.
    final count = _be32(p, 128);
    for (var i = 0; i < count && 132 + i * 12 + 12 <= p.length; i++) {
      final e = 132 + i * 12;
      if (String.fromCharCodes(p, e, e + 4) != 'desc') continue;
      final off = _be32(p, e + 4);
      final size = _be32(p, e + 8);
      if (off + size > p.length || size < 12) break;
      final sig = String.fromCharCodes(p, off, off + 4);
      if (sig == 'desc') {
        final len = _be32(p, off + 8);
        if (off + 12 + len <= p.length && len > 1) {
          tags.add(
            MetadataTag(
              'Profile Description',
              ascii.decode(
                p.sublist(off + 12, off + 12 + len - 1),
                allowInvalid: true,
              ),
            ),
          );
        }
      } else if (sig == 'mluc' && size >= 28) {
        final len = _be32(p, off + 20);
        final strOff = _be32(p, off + 24);
        if (off + strOff + len <= p.length) {
          final units = <int>[];
          for (var k = 0; k + 1 < len; k += 2) {
            units.add((p[off + strOff + k] << 8) | p[off + strOff + k + 1]);
          }
          tags.add(
            MetadataTag('Profile Description', String.fromCharCodes(units)),
          );
        }
      }
      break;
    }
    out.add(MetadataDirectory('ICC Profile', tags));
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _iccClass(String c) => switch (c) {
    'scnr' => 'Input device',
    'mntr' => 'Display device',
    'prtr' => 'Output device',
    'link' => 'Device link',
    'abst' => 'Abstract',
    'spac' => 'Colour space',
    'nmcl' => 'Named colour',
    _ => c,
  };

  // ── Photoshop resources / IPTC ───────────────────────────────────────────

  static void _readPhotoshop(Uint8List d, List<MetadataDirectory> out) {
    var o = 0;
    while (o + 12 <= d.length && String.fromCharCodes(d, o, o + 4) == '8BIM') {
      final id = (d[o + 4] << 8) | d[o + 5];
      final nameLen = d[o + 6];
      // The Pascal-string name is padded so that it takes an even size.
      final p = o + 6 + ((1 + nameLen) + ((1 + nameLen) & 1));
      if (p + 4 > d.length) break;
      final size = _be32(d, p);
      final start = p + 4;
      if (start + size > d.length) break;
      if (id == 0x0404)
        _readIptc(Uint8List.sublistView(d, start, start + size), out);
      o = start + size + (size & 1);
    }
  }

  static const Map<int, String> _iptcNames = {
    5: 'Object Name',
    7: 'Edit Status',
    10: 'Urgency',
    15: 'Category',
    20: 'Supplemental Categories',
    25: 'Keywords',
    40: 'Special Instructions',
    55: 'Date Created',
    60: 'Time Created',
    62: 'Digital Creation Date',
    63: 'Digital Creation Time',
    80: 'By-line',
    85: 'By-line Title',
    90: 'City',
    92: 'Sub-location',
    95: 'Province/State',
    100: 'Country Code',
    101: 'Country Name',
    103: 'Original Transmission Reference',
    105: 'Headline',
    110: 'Credit',
    115: 'Source',
    116: 'Copyright Notice',
    120: 'Caption/Abstract',
    122: 'Writer/Editor',
  };

  static void _readIptc(Uint8List d, List<MetadataDirectory> out) {
    final tags = <MetadataTag>[];
    var o = 0;
    while (o + 5 <= d.length && d[o] == 0x1C) {
      final record = d[o + 1];
      final dataset = d[o + 2];
      final size = (d[o + 3] << 8) | d[o + 4];
      final start = o + 5;
      if (size & 0x8000 != 0 || start + size > d.length) break;
      if (record == 2) {
        final name = _iptcNames[dataset];
        if (name != null) {
          tags.add(
            MetadataTag(
              name,
              utf8
                  .decode(
                    Uint8List.sublistView(d, start, start + size),
                    allowMalformed: true,
                  )
                  .trim(),
            ),
          );
        }
      }
      o = start + size;
    }
    if (tags.isNotEmpty) out.add(MetadataDirectory('IPTC', tags));
  }
}

class _BmffBox {
  const _BmffBox(this.type, this.payloadStart, this.end);

  final String type;
  final int payloadStart;
  final int end;
}

class _HeifExtent {
  const _HeifExtent(this.offset, this.length);

  final int offset;
  final int length;
}

class _HeifItemLocation {
  const _HeifItemLocation({
    required this.constructionMethod,
    required this.dataReferenceIndex,
    required this.baseOffset,
    required this.extents,
  });

  final int constructionMethod;
  final int dataReferenceIndex;
  final int baseOffset;
  final List<_HeifExtent> extents;
}

class _Tiff {
  _Tiff(this.t, this.little);
  final Uint8List t;
  final bool little;

  int u16(int o) {
    if (o < 0 || o + 2 > t.length) return 0;
    return little ? (t[o] | (t[o + 1] << 8)) : ((t[o] << 8) | t[o + 1]);
  }

  int u32(int o) {
    if (o < 0 || o + 4 > t.length) return 0;
    return little
        ? (t[o] | (t[o + 1] << 8) | (t[o + 2] << 16) | (t[o + 3] << 24))
        : ((t[o] << 24) | (t[o + 1] << 16) | (t[o + 2] << 8) | t[o + 3]);
  }

  static int typeSize(int type) => switch (type) {
    1 || 2 || 6 || 7 => 1,
    3 || 8 => 2,
    4 || 9 || 11 => 4,
    5 || 10 || 12 => 8,
    _ => 0,
  };
}
