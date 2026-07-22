import 'dart:collection';
import 'dart:typed_data';

/// A capacity-by-total-bytes LRU cache, for values whose individual size
/// varies too widely for entry-count capping to make sense (e.g. full
/// decoded/decrypted media files ranging from a few KB to tens of MB).
///
/// Unlike [LruCache] (entry-count based), eviction here is driven by total
/// bytes held, so caching one enormous file doesn't leave room for many
/// small ones, and caching many small files doesn't starve room for one
/// reasonably large one.
class ByteBudgetCache {
  final int maxTotalBytes;
  final LinkedHashMap<String, Uint8List> _map = LinkedHashMap();
  int _currentBytes = 0;

  ByteBudgetCache(this.maxTotalBytes)
      : assert(maxTotalBytes > 0, 'maxTotalBytes must be > 0');

  int get currentBytes => _currentBytes;
  int get length => _map.length;

  /// Returns the cached bytes for [key], promoting it to most-recent, or
  /// null if absent.
  Uint8List? operator [](String key) {
    final val = _map.remove(key);
    if (val == null) return null;
    _map[key] = val; // re-insert at tail = most-recent
    return val;
  }

  bool containsKey(String key) => _map.containsKey(key);

  /// Stores [value] under [key], evicting least-recently-used entries until
  /// the total byte budget is respected. If [value] alone exceeds
  /// [maxTotalBytes], it is not cached (avoids one huge file evicting
  /// everything else for a cache hit it will get only once).
  void operator []=(String key, Uint8List value) {
    final existing = _map.remove(key);
    if (existing != null) _currentBytes -= existing.length;

    if (value.length > maxTotalBytes) {
      // Too large to usefully cache — drop silently rather than thrash
      // the whole cache for a single-use entry.
      return;
    }

    _map[key] = value;
    _currentBytes += value.length;

    while (_currentBytes > maxTotalBytes && _map.isNotEmpty) {
      final oldestKey = _map.keys.first;
      final oldest = _map.remove(oldestKey);
      if (oldest != null) _currentBytes -= oldest.length;
    }
  }

  void remove(String key) {
    final removed = _map.remove(key);
    if (removed != null) _currentBytes -= removed.length;
  }

  void clear() {
    _map.clear();
    _currentBytes = 0;
  }
}
