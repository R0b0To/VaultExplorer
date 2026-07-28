import 'dart:collection';

/// A capacity-bounded cache that evicts the least-recently-used entry when
/// full.
///
/// Backed by a [LinkedHashMap] whose insertion order tracks recency.
/// Every [operator []] call that hits promotes the entry to most-recent.
///
/// Capacity is mutable (see [resize]) rather than `final` so that
/// [DeviceCapabilityProfiler]-driven sizing (ADR-011) and
/// [CacheCoordinator.trimAll] (ADR-011 §"memory-pressure response",
/// ADR-013) can adjust it after construction — every other part of this
/// codebase should still treat capacity as fixed for the lifetime of a
/// given cache instance and only call [resize] via those two sanctioned
/// paths, not as a general-purpose setter sprinkled through call sites.
class LruCache<K, V> {
  int _capacity;
  final _map = <K, V>{};

  LruCache(this._capacity) : assert(_capacity > 0, 'capacity must be > 0');

  int get capacity => _capacity;

  /// Returns the value for [key], promoting it to most-recent, or null if absent.
  V? operator [](K key) {
    if (!_map.containsKey(key)) return null;
    // Remove and re-insert to promote to tail (most-recent).
    final val = _map.remove(key) as V;
    _map[key] = val;
    return val;
  }

  /// Stores [value] under [key], evicting the oldest entry if over capacity.
  void operator []=(K key, V value) {
    _map.remove(key); // remove first so re-insertion lands at tail
    _map[key] = value;
    while (_map.length > _capacity) {
      _map.remove(_map.keys.first); // evict head (= least recent)
    }
  }

  bool containsKey(K key) => _map.containsKey(key);

  void remove(K key) => _map.remove(key);

  void clear() => _map.clear();

  int get length => _map.length;

  /// Changes the capacity in place, evicting from the head (least-recent)
  /// immediately if the new capacity is smaller than the current entry
  /// count. See the class doc for who's allowed to call this.
  void resize(int newCapacity) {
    assert(newCapacity > 0, 'capacity must be > 0');
    _capacity = newCapacity;
    while (_map.length > _capacity) {
      _map.remove(_map.keys.first);
    }
  }

  /// Evicts the least-recently-used [fraction] (0.0-1.0) of entries right
  /// now, without permanently changing [capacity]. Used for the
  /// `TrimLevel.moderate` step of `CacheCoordinator.trimAll` — a temporary
  /// shrink under memory pressure that doesn't require the caller to also
  /// remember to restore the original capacity afterwards.
  void trimToFraction(double fraction) {
    assert(fraction >= 0.0 && fraction <= 1.0);
    final targetLength = (_map.length * (1.0 - fraction)).round();
    while (_map.length > targetLength) {
      _map.remove(_map.keys.first);
    }
  }
}