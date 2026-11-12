import 'dart:typed_data';

/// The persisted part of a [MediaIndex]: parallel arrays sorted by hash.
class MediaIndexSnapshot {
  const MediaIndexSnapshot({
    required this.hashes,
    required this.sizes,
    required this.mtimes,
    required this.widths,
    required this.heights,
  });

  static final MediaIndexSnapshot empty = MediaIndexSnapshot(
    hashes: Int64List(0),
    sizes: Int64List(0),
    mtimes: Uint32List(0),
    widths: Uint32List(0),
    heights: Uint32List(0),
  );

  final Int64List hashes;
  final Int64List sizes;
  final Uint32List mtimes;
  final Uint32List widths;
  final Uint32List heights;

  int get length => hashes.length;
}

class _Fresh {
  _Fresh(this.size, this.mtime, this.width, this.height);
  final int size;
  final int mtime;
  final int width;
  final int height;
}

/// Width and height of every media file the gallery has seen in one container,
/// so a folder can be laid out with the right tile shapes before any of its
/// thumbnails exist,
/// which a vault (no media database) has to build itself.
///
/// An entry is valid only for the file it was measured on: it stores the file's
/// size and modified time, and [lookup] ignores it when either differs (the
/// file was edited, replaced, or is a different file that hashed the same).
///
/// Entries are packed into sorted typed arrays (28 bytes each: 200,000 photos
/// are about 5.6 MB) that are searched by binary search. New measurements wait
/// in a small overlay and are merged in by [compact].
class MediaIndex {
  MediaIndex([MediaIndexSnapshot? snapshot]) {
    final s = snapshot ?? MediaIndexSnapshot.empty;
    _hashes = s.hashes;
    _sizes = s.sizes;
    _mtimes = s.mtimes;
    _widths = s.widths;
    _heights = s.heights;
  }

  /// Upper bound on stored entries. Beyond it the oldest-looking entries (an
  /// arbitrary subset of the stored ones, never the fresh ones) are dropped;
  /// they are simply measured again if they are ever needed.
  static const int maxEntries = 400000;

  static const int _mtimeMask = 0xFFFFFFFF;

  late Int64List _hashes;
  late Int64List _sizes;
  late Uint32List _mtimes;
  late Uint32List _widths;
  late Uint32List _heights;
  final Map<int, _Fresh> _overlay = {};

  int _revision = 0;
  int _savedRevision = 0;

  /// Entries held (an entry measured again counts twice until [compact]).
  int get length => _hashes.length + _overlay.length;

  /// Changes made since the last [markSaved].
  bool get hasUnsavedChanges => _revision != _savedRevision;
  int get revision => _revision;

  /// Packed size of the file with [pathHash] if it is known *and still valid*
  /// for a file of [size] bytes modified at [mtimeSecs]; 0 otherwise. Read it
  /// with [widthOf] / [heightOf].
  int lookup(int pathHash, int size, int mtimeSecs) {
    final fresh = _overlay[pathHash];
    if (fresh != null) {
      return fresh.size == size && fresh.mtime == (mtimeSecs & _mtimeMask)
          ? _pack(fresh.width, fresh.height)
          : 0;
    }
    final i = _find(pathHash);
    if (i < 0) return 0;
    if (_sizes[i] != size || _mtimes[i] != (mtimeSecs & _mtimeMask)) return 0;
    return _pack(_widths[i], _heights[i]);
  }

  static int widthOf(int packed) => packed >> 32;
  static int heightOf(int packed) => packed & 0xFFFFFFFF;
  static int _pack(int width, int height) => (width << 32) | height;

  /// Remembers the size of a file. Does nothing (and does not mark the index
  /// changed) when it is already stored as given: tiles report the size of
  /// their thumbnail every time they are built.
  void record(int pathHash, int size, int mtimeSecs, int width, int height) {
    if (width <= 0 || height <= 0 || width > 0x7FFFFFFF) return;
    if (lookup(pathHash, size, mtimeSecs) == _pack(width, height)) return;
    _overlay[pathHash] = _Fresh(size, mtimeSecs & _mtimeMask, width, height);
    _revision++;
  }

  /// Merges everything recorded so far into the sorted arrays and returns
  /// them. The result is what gets written; the arrays are not modified
  /// afterwards (a later [compact] builds new ones).
  MediaIndexSnapshot compact() {
    if (_overlay.isNotEmpty) _mergeOverlay();
    return MediaIndexSnapshot(
      hashes: _hashes,
      sizes: _sizes,
      mtimes: _mtimes,
      widths: _widths,
      heights: _heights,
    );
  }

  /// Declares everything up to [revision] (as read from [revision] before the
  /// snapshot was taken) safely stored.
  void markSaved(int revision) {
    if (revision > _savedRevision) _savedRevision = revision;
  }

  int _find(int hash) {
    var lo = 0;
    var hi = _hashes.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final h = _hashes[mid];
      if (h == hash) return mid;
      if (h < hash) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return -1;
  }

  void _mergeOverlay() {
    final keys = _overlay.keys.toList()..sort();
    final baseLength = _hashes.length;
    // Fresh entries always stay; stored ones make room for them.
    final baseBudget = maxEntries - keys.length;

    final capacity = baseLength + keys.length;
    final hashes = Int64List(capacity);
    final sizes = Int64List(capacity);
    final mtimes = Uint32List(capacity);
    final widths = Uint32List(capacity);
    final heights = Uint32List(capacity);

    var n = 0;
    var kept = 0;
    var b = 0;
    var k = 0;
    while (b < baseLength || k < keys.length) {
      final takeFresh =
          k < keys.length && (b >= baseLength || keys[k] <= _hashes[b]);
      if (takeFresh) {
        final hash = keys[k++];
        final f = _overlay[hash]!;
        if (b < baseLength && _hashes[b] == hash) b++; // replaced
        hashes[n] = hash;
        sizes[n] = f.size;
        mtimes[n] = f.mtime;
        widths[n] = f.width;
        heights[n] = f.height;
        n++;
      } else {
        if (kept < baseBudget) {
          hashes[n] = _hashes[b];
          sizes[n] = _sizes[b];
          mtimes[n] = _mtimes[b];
          widths[n] = _widths[b];
          heights[n] = _heights[b];
          n++;
          kept++;
        }
        b++;
      }
    }
    _hashes = hashes.sublist(0, n);
    _sizes = sizes.sublist(0, n);
    _mtimes = mtimes.sublist(0, n);
    _widths = widths.sublist(0, n);
    _heights = heights.sublist(0, n);
    _overlay.clear();
  }
}
