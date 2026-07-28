import 'dart:collection';
import 'dart:typed_data';

/// A capacity-by-total-bytes LRU cache, for values whose individual size
/// varies too widely for entry-count capping to make sense (e.g. full
/// decoded/decrypted media files ranging from a few KB to tens of MB, or
/// thumbnails whose byte size scales with a user-adjustable quality
/// setting — see Finding F-01).
///
/// Unlike [LruCache] (entry-count based), eviction here is driven by total
/// bytes held, so caching one enormous file doesn't leave room for many
/// small ones, and caching many small files doesn't starve room for one
/// reasonably large one.
class ByteBudgetCache {
  int _maxTotalBytes;
  final LinkedHashMap<String, Uint8List> _map = LinkedHashMap();
  int _currentBytes = 0;

  ByteBudgetCache(this._maxTotalBytes)
      : assert(_maxTotalBytes > 0, 'maxTotalBytes must be > 0');

  int get maxTotalBytes => _maxTotalBytes;
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

    if (value.length > _maxTotalBytes) {
      // Too large to usefully cache — drop silently rather than thrash
      // the whole cache for a single-use entry.
      return;
    }

    _map[key] = value;
    _currentBytes += value.length;

    _evictToBudget();
  }

  void remove(String key) {
    final removed = _map.remove(key);
    if (removed != null) _currentBytes -= removed.length;
  }

  void clear() {
    _map.clear();
    _currentBytes = 0;
  }

  void _evictToBudget() {
    while (_currentBytes > _maxTotalBytes && _map.isNotEmpty) {
      final oldestKey = _map.keys.first;
      final oldest = _map.remove(oldestKey);
      if (oldest != null) _currentBytes -= oldest.length;
    }
  }

  /// Changes the byte budget in place, evicting oldest-first immediately if
  /// the new budget is smaller than what's currently held. Used by
  /// [DeviceCapabilityProfiler]-driven sizing (ADR-011) and
  /// `CacheCoordinator.trimAll` (ADR-011, ADR-013) — see [LruCache.resize]
  /// for the equivalent entry-count-based primitive and the same "only
  /// these two callers" convention.
  void resize(int newMaxTotalBytes) {
    assert(newMaxTotalBytes > 0, 'maxTotalBytes must be > 0');
    _maxTotalBytes = newMaxTotalBytes;
    _evictToBudget();
  }

  /// Temporarily evicts down to [fraction] (0.0-1.0) of the *current*
  /// budget, without permanently changing [maxTotalBytes]. Used for the
  /// `TrimLevel.moderate` step of `CacheCoordinator.trimAll`.
  void trimToFraction(double fraction) {
    assert(fraction >= 0.0 && fraction <= 1.0);
    final target = (_maxTotalBytes * fraction).round();
    while (_currentBytes > target && _map.isNotEmpty) {
      final oldestKey = _map.keys.first;
      final oldest = _map.remove(oldestKey);
      if (oldest != null) _currentBytes -= oldest.length;
    }
  }
}