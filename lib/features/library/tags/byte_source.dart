import 'dart:math' as math;
import 'dart:typed_data';

/// Random-access view of one file's bytes.
///
/// The tag readers never see a path or a platform channel; they only ask for
/// byte ranges. That keeps them testable against in-memory fixtures and lets
/// the caller decide how a range is fetched (vault engine, SAF, plain file).
abstract class ByteSource {
  /// Total size of the file in bytes.
  int get length;

  /// Reads up to [count] bytes starting at [offset].
  ///
  /// May return fewer bytes than asked for (the platform can cap one chunk),
  /// and returns null or an empty list when the range cannot be read.
  Future<Uint8List?> read(int offset, int count);
}

/// A [ByteSource] over bytes already in memory (tests, small buffers).
class MemoryByteSource implements ByteSource {
  final Uint8List bytes;

  MemoryByteSource(this.bytes);

  @override
  int get length => bytes.length;

  @override
  Future<Uint8List?> read(int offset, int count) async {
    if (offset < 0 || offset >= bytes.length || count <= 0) {
      return Uint8List(0);
    }
    final end = math.min(bytes.length, offset + count);
    return Uint8List.sublistView(bytes, offset, end);
  }
}

/// Reads through a [ByteSource] with one forward window, so a run of small
/// reads (frame headers, text frames) costs one round trip instead of one each.
///
/// Reading is the expensive part of indexing a vault: every range is decrypted
/// on demand. Callers walk a file's structure and jump over what they do not
/// need (cover art above all) with [bytes] calls that land past the window; a
/// skipped region is simply never fetched.
class BufferedReader {
  final ByteSource source;

  /// Bytes fetched per refill when the caller asks for less than this.
  final int chunkSize;

  /// Hard cap on source reads for one file, so a malformed structure that
  /// loops cannot turn into an unbounded run of decrypt calls.
  final int maxReads;

  int readCount = 0;
  int bytesFetched = 0;

  /// Set when the source threw while reading. The failure is swallowed so a
  /// transient platform error ends this file's walk instead of crashing it;
  /// callers check this to tell "unreadable" from "has no tags".
  bool readFailed = false;

  Uint8List _buf = Uint8List(0);
  int _bufStart = 0;

  BufferedReader(
    this.source, {
    this.chunkSize = 32 * 1024,
    this.maxReads = 200,
  });

  int get length => source.length;

  /// Exactly [count] bytes at [offset], or null when they are out of range or
  /// the source could not supply them.
  Future<Uint8List?> bytes(int offset, int count) async {
    if (count < 0 || offset < 0 || offset + count > length) return null;
    if (count == 0) return Uint8List(0);
    final end = offset + count;
    if (offset >= _bufStart && end <= _bufStart + _buf.length) {
      return Uint8List.sublistView(_buf, offset - _bufStart, end - _bufStart);
    }
    final want = math.min(math.max(count, chunkSize), length - offset);
    final got = await _fetch(offset, want, atLeast: count);
    if (got == null) return null;
    _buf = got;
    _bufStart = offset;
    return Uint8List.sublistView(got, 0, count);
  }

  /// The last [count] bytes of the file (fewer if the file is shorter).
  Future<Uint8List?> tail(int count) {
    final n = math.min(count, length);
    return bytes(length - n, n);
  }

  Future<Uint8List?> _fetch(
    int offset,
    int want, {
    required int atLeast,
  }) async {
    final builder = BytesBuilder(copy: false);
    var got = 0;
    while (got < want) {
      if (readCount >= maxReads) return null;
      readCount++;
      Uint8List? chunk;
      try {
        chunk = await source.read(offset + got, want - got);
      } catch (_) {
        readFailed = true;
        break;
      }
      if (chunk == null || chunk.isEmpty) break;
      builder.add(chunk);
      got += chunk.length;
      bytesFetched += chunk.length;
    }
    if (got < atLeast) return null;
    return builder.takeBytes();
  }
}

/// Little helpers for reading integers out of a byte list.
class Bytes {
  Bytes._();

  static int u16be(Uint8List b, int o) => (b[o] << 8) | b[o + 1];
  static int u16le(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
  static int u24be(Uint8List b, int o) =>
      (b[o] << 16) | (b[o + 1] << 8) | b[o + 2];
  static int u32be(Uint8List b, int o) =>
      (b[o] * 0x1000000) + ((b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]);
  static int u32le(Uint8List b, int o) =>
      (b[o + 3] * 0x1000000) + ((b[o + 2] << 16) | (b[o + 1] << 8) | b[o]);
  static int u64be(Uint8List b, int o) =>
      u32be(b, o) * 0x100000000 + u32be(b, o + 4);
  static int u64le(Uint8List b, int o) =>
      u32le(b, o + 4) * 0x100000000 + u32le(b, o);

  /// ID3v2 "synchsafe" integer: 7 bits per byte.
  static int syncsafe(Uint8List b, int o) =>
      ((b[o] & 0x7F) << 21) |
      ((b[o + 1] & 0x7F) << 14) |
      ((b[o + 2] & 0x7F) << 7) |
      (b[o + 3] & 0x7F);

  static String ascii(Uint8List b, int start, int end) {
    if (start < 0 || end > b.length || start >= end) return '';
    return String.fromCharCodes(b.sublist(start, end));
  }

  static bool startsWith(Uint8List b, int offset, List<int> pattern) {
    if (offset < 0 || offset + pattern.length > b.length) return false;
    for (var i = 0; i < pattern.length; i++) {
      if (b[offset + i] != pattern[i]) return false;
    }
    return true;
  }
}
