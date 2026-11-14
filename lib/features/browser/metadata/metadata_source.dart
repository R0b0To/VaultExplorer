import 'dart:math' as math;
import 'dart:typed_data';

/// Random read access to one file's bytes.
///
/// The metadata reader and editor never touch the vault themselves: they ask
/// a [MetadataSource] for byte ranges, so the same code runs against a vault
/// file, phone storage or a plain list in a test.
abstract interface class MetadataSource {
  /// Total size of the file in bytes.
  int get length;

  /// Up to [count] bytes starting at [offset]. Fewer are returned only at the
  /// end of the file; an offset at or past the end gives an empty list.
  Future<Uint8List> read(int offset, int count);
}

/// A [MetadataSource] over bytes already in memory.
class MemoryMetadataSource implements MetadataSource {
  MemoryMetadataSource(this.bytes);

  final Uint8List bytes;

  @override
  int get length => bytes.length;

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (offset < 0 || offset >= bytes.length || count <= 0) return Uint8List(0);
    final end = math.min(bytes.length, offset + count);
    return Uint8List.sublistView(bytes, offset, end);
  }
}

/// Wraps a slow source (a vault read crosses a platform channel) with one
/// read-ahead block, so walking hundreds of small chunk headers costs a few
/// reads instead of hundreds.
class BufferedMetadataSource implements MetadataSource {
  BufferedMetadataSource(this._inner, {this.blockSize = 1 << 20});

  final MetadataSource _inner;

  /// Bytes fetched at once when a read misses the cached block.
  final int blockSize;

  Uint8List _block = Uint8List(0);
  int _blockStart = 0;

  @override
  int get length => _inner.length;

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (offset < 0 || offset >= length || count <= 0) return Uint8List(0);
    final wanted = math.min(count, length - offset);
    final blockEnd = _blockStart + _block.length;
    if (offset >= _blockStart && offset + wanted <= blockEnd) {
      return Uint8List.sublistView(
        _block,
        offset - _blockStart,
        offset - _blockStart + wanted,
      );
    }
    // Larger than a block: no point caching it, hand it straight through.
    if (wanted > blockSize) return _inner.read(offset, wanted);
    _block = await _inner.read(offset, blockSize);
    _blockStart = offset;
    final got = math.min(wanted, _block.length);
    return Uint8List.sublistView(_block, 0, got);
  }
}

/// One part of an edited file: either new bytes or a range of the original.
sealed class EditPiece {
  const EditPiece();
}

/// Bytes that did not exist in the original (or that replace some).
class LiteralPiece extends EditPiece {
  const LiteralPiece(this.bytes);
  final Uint8List bytes;
}

/// A byte range `[start, end)` of the original, copied unchanged.
class CopyPiece extends EditPiece {
  const CopyPiece(this.start, this.end);
  final int start;
  final int end;
}

/// How to build an edited file out of the original: the pieces, in order.
///
/// Nearly every edit changes only a few header segments, so the plan says
/// "copy bytes 0..N, write these new bytes, copy M..end" and the pixel data
/// (the bulk of the file) is streamed through without ever being held in
/// memory as a whole.
class MetadataEditPlan {
  MetadataEditPlan(List<EditPiece> pieces) : pieces = _merge(pieces);

  final List<EditPiece> pieces;

  /// Size of the edited file.
  int get outputLength {
    var total = 0;
    for (final p in pieces) {
      total += switch (p) {
        LiteralPiece(:final bytes) => bytes.length,
        CopyPiece(:final start, :final end) => end - start,
      };
    }
    return total;
  }

  /// Joins neighbouring copies and drops empty pieces.
  static List<EditPiece> _merge(List<EditPiece> input) {
    final out = <EditPiece>[];
    for (final p in input) {
      switch (p) {
        case LiteralPiece(:final bytes):
          if (bytes.isEmpty) continue;
          if (out.isNotEmpty && out.last is LiteralPiece) {
            final prev = (out.removeLast() as LiteralPiece).bytes;
            out.add(
              LiteralPiece(
                (BytesBuilder(copy: false)
                      ..add(prev)
                      ..add(bytes))
                    .takeBytes(),
              ),
            );
          } else {
            out.add(p);
          }
        case CopyPiece(:final start, :final end):
          if (end <= start) continue;
          if (out.isNotEmpty && out.last is CopyPiece) {
            final prev = out.last as CopyPiece;
            if (prev.end == start) {
              out[out.length - 1] = CopyPiece(prev.start, end);
              continue;
            }
          }
          out.add(p);
      }
    }
    return out;
  }

  /// Materialises the whole edited file. For tests and small files; the app
  /// streams instead (see [stream]).
  Future<Uint8List> toBytes(MetadataSource source) async {
    final b = BytesBuilder(copy: false);
    await for (final chunk in stream(source)) {
      b.add(chunk);
    }
    return b.takeBytes();
  }

  /// The edited file as a sequence of chunks of at most [chunkSize] bytes,
  /// read from [source] as they are needed.
  Stream<Uint8List> stream(
    MetadataSource source, {
    int chunkSize = 4 * 1024 * 1024,
  }) async* {
    for (final p in pieces) {
      switch (p) {
        case LiteralPiece(:final bytes):
          yield bytes;
        case CopyPiece(:final start, :final end):
          var at = start;
          while (at < end) {
            final n = math.min(chunkSize, end - at);
            final data = await source.read(at, n);
            if (data.isEmpty) {
              throw StateError('Source ended at $at, expected data up to $end');
            }
            yield data;
            at += data.length;
          }
      }
    }
  }
}

/// Why a metadata edit could not be planned.
class MetadataEditException implements Exception {
  const MetadataEditException(this.reason, [this.detail]);

  final MetadataEditFailure reason;
  final String? detail;

  @override
  String toString() => 'MetadataEditException($reason${detail == null ? '' : ': $detail'})';
}

enum MetadataEditFailure {
  /// The file is not a JPEG, PNG or WebP (the formats whose metadata is
  /// edited here).
  unsupportedFormat,

  /// The file's structure is damaged or not what its extension says.
  malformed,

  /// The edited metadata would not fit the format's size limit.
  tooLarge,

  /// The file's own Exif block is built in a way that cannot be changed
  /// safely.
  unreadableExif,
}
