import 'dart:convert';
import 'dart:typed_data';

/// Pure-Dart MD5, returning the same lowercase-hex digest as the native
/// `MessageDigest.getInstance("MD5")` behind `VaultHashApi.hashBytesMd5`.
///
/// Why this exists: `ThumbnailCacheService` derives its on-disk and
/// in-container cache names from `md5(utf8(path))`. That used to be a
/// platform-channel round trip *per lookup* (and a lookup needs two or three
/// of them), so a warm thumbnail cost several channel hops before it even
/// touched the disk. MD5 of a short string is a few microseconds of integer
/// math, so doing it in-process removes those hops entirely.
///
/// This is a cache-key derivation, not a security boundary (see the note on
/// `VaultHashApi.hashBytesMd5`), and it must stay MD5 byte-for-byte so every
/// existing cached thumbnail keeps resolving after an upgrade.

// Per-round left-rotate amounts (RFC 1321).
const List<int> _shifts = <int>[
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, //
  5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, //
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, //
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, //
];

// K[i] = floor(2^32 * abs(sin(i + 1))), precomputed (RFC 1321).
final Uint32List _k = Uint32List.fromList(<int>[
  0xd76aa478,
  0xe8c7b756,
  0x242070db,
  0xc1bdceee,
  0xf57c0faf,
  0x4787c62a,
  0xa8304613,
  0xfd469501,
  0x698098d8,
  0x8b44f7af,
  0xffff5bb1,
  0x895cd7be,
  0x6b901122,
  0xfd987193,
  0xa679438e,
  0x49b40821,
  0xf61e2562,
  0xc040b340,
  0x265e5a51,
  0xe9b6c7aa,
  0xd62f105d,
  0x02441453,
  0xd8a1e681,
  0xe7d3fbc8,
  0x21e1cde6,
  0xc33707d6,
  0xf4d50d87,
  0x455a14ed,
  0xa9e3e905,
  0xfcefa3f8,
  0x676f02d9,
  0x8d2a4c8a,
  0xfffa3942,
  0x8771f681,
  0x6d9d6122,
  0xfde5380c,
  0xa4beea44,
  0x4bdecfa9,
  0xf6bb4b60,
  0xbebfbc70,
  0x289b7ec6,
  0xeaa127fa,
  0xd4ef3085,
  0x04881d05,
  0xd9d4d039,
  0xe6db99e5,
  0x1fa27cf8,
  0xc4ac5665,
  0xf4292244,
  0x432aff97,
  0xab9423a7,
  0xfc93a039,
  0x655b59c3,
  0x8f0ccc92,
  0xffeff47d,
  0x85845dd1,
  0x6fa87e4f,
  0xfe2ce6e0,
  0xa3014314,
  0x4e0811a1,
  0xf7537e82,
  0xbd3af235,
  0x2ad7d2bb,
  0xeb86d391,
]);

const int _mask = 0xFFFFFFFF;
const String _hexDigits = '0123456789abcdef';

/// Lowercase-hex MD5 of the UTF-8 encoding of [input].
String md5HexOfString(String input) => md5Hex(utf8.encode(input));

/// Lowercase-hex MD5 of [input].
String md5Hex(List<int> input) {
  final len = input.length;
  // Message + 0x80 + zero padding + 64-bit length, rounded up to 64 bytes.
  final paddedLen = ((len + 8) ~/ 64 + 1) * 64;
  final buf = Uint8List(paddedLen)
    ..setRange(0, len, input)
    ..[len] = 0x80;
  final view = ByteData.sublistView(buf);
  final bitLen = len * 8;
  view.setUint32(paddedLen - 8, bitLen & _mask, Endian.little);
  view.setUint32(paddedLen - 4, (bitLen >> 32) & _mask, Endian.little);

  var a0 = 0x67452301;
  var b0 = 0xefcdab89;
  var c0 = 0x98badcfe;
  var d0 = 0x10325476;
  final m = Uint32List(16);

  for (var off = 0; off < paddedLen; off += 64) {
    for (var i = 0; i < 16; i++) {
      m[i] = view.getUint32(off + i * 4, Endian.little);
    }
    var a = a0;
    var b = b0;
    var c = c0;
    var d = d0;
    for (var i = 0; i < 64; i++) {
      int f;
      int g;
      if (i < 16) {
        f = (b & c) | (~b & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | (~d & c);
        g = (5 * i + 1) & 15;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) & 15;
      } else {
        f = c ^ (b | (~d & _mask));
        g = (7 * i) & 15;
      }
      f = (f + a + _k[i] + m[g]) & _mask;
      a = d;
      d = c;
      c = b;
      final s = _shifts[i];
      b = (b + (((f << s) | (f >> (32 - s))) & _mask)) & _mask;
    }
    a0 = (a0 + a) & _mask;
    b0 = (b0 + b) & _mask;
    c0 = (c0 + c) & _mask;
    d0 = (d0 + d) & _mask;
  }

  final out = StringBuffer();
  for (final word in <int>[a0, b0, c0, d0]) {
    for (var shift = 0; shift < 32; shift += 8) {
      final byte = (word >> shift) & 0xFF;
      out
        ..write(_hexDigits[byte >> 4])
        ..write(_hexDigits[byte & 15]);
    }
  }
  return out.toString();
}
