import 'dart:collection';
import 'dart:typed_data';

/// Holds recently shown cover pictures in memory only.
///
/// Covers are read out of the vault on demand and never written anywhere. The
/// cache is bounded by bytes, evicts the least recently used picture first,
/// remembers "this file has no usable cover" so a missing one is not re-read on
/// every scroll, and joins concurrent requests for the same picture into one
/// read.
class LibraryCoverCache {
  final int maxBytes;

  LibraryCoverCache({this.maxBytes = 24 * 1024 * 1024});

  final LinkedHashMap<String, Uint8List?> _entries = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _inflight = {};
  int _bytes = 0;
  int _epoch = 0;

  int get byteSize => _bytes;
  int get entryCount => _entries.length;

  bool contains(String key) => _entries.containsKey(key);

  /// The cached picture (null for a remembered miss). Call [contains] first to
  /// tell a miss from "not cached". Marks the entry recently used.
  Uint8List? peek(String key) {
    if (!_entries.containsKey(key)) return null;
    final v = _entries.remove(key);
    _entries[key] = v;
    return v;
  }

  /// Returns the cached picture, or runs [loader] once for all concurrent
  /// callers with the same [key] and caches what it returns.
  Future<Uint8List?> load(String key, Future<Uint8List?> Function() loader) {
    if (_entries.containsKey(key)) return Future.value(peek(key));
    final running = _inflight[key];
    if (running != null) return running;

    final epoch = _epoch;
    final future = () async {
      Uint8List? bytes;
      try {
        bytes = await loader();
      } catch (_) {
        bytes = null;
      }
      // A clear() while this ran means the screen is gone; do not repopulate.
      if (epoch == _epoch) _store(key, bytes);
      return bytes;
    }();
    _inflight[key] = future;
    future.whenComplete(() {
      if (identical(_inflight[key], future)) _inflight.remove(key);
    });
    return future;
  }

  void _store(String key, Uint8List? bytes) {
    final old = _entries.remove(key);
    if (old != null) _bytes -= old.length;
    _entries[key] = bytes;
    if (bytes != null) _bytes += bytes.length;
    while (_bytes > maxBytes && _entries.isNotEmpty) {
      final oldestKey = _entries.keys.first;
      if (oldestKey == key && _entries.length == 1) break;
      final removed = _entries.remove(oldestKey);
      if (removed != null) _bytes -= removed.length;
    }
  }

  /// Drops everything, including results of reads still in flight.
  void clear() {
    _epoch++;
    _entries.clear();
    _inflight.clear();
    _bytes = 0;
  }
}
