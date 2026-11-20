import 'dart:collection';

import 'package:vaultexplorer/core/utils/raw_entry.dart';

/// A small least-recently-used cache of directory listings, keyed by folder
/// path.
///
/// Used by the file browser to show a folder it has already listed *at once*
/// when the user comes back to it, and then confirm in the background that it
/// still looks the same (stale-while-revalidate). Without it, only the folders
/// on the current breadcrumb were remembered, so every other revisit started
/// from an empty screen and a full native listing.
///
/// Bounded two ways so it cannot grow without limit: by the number of folders
/// ([maxDirectories]) and by the total number of entries across all of them
/// ([maxTotalEntries], which is what actually costs memory).
///
/// The lists handed in and out are shared, not copied: listings are treated as
/// immutable everywhere in the browser (changes build a new list), and sharing
/// the instance is what lets views keyed on list identity be reused.
///
/// Empty listings are never stored. An empty folder is cheap to list again, and
/// showing a stale "empty" for a folder that has since filled up is worse than
/// a brief spinner.
class DirectoryListingCache {
  DirectoryListingCache({
    this.maxDirectories = 24,
    this.maxTotalEntries = 30000,
  }) : assert(maxDirectories > 0),
       assert(maxTotalEntries > 0);

  final int maxDirectories;
  final int maxTotalEntries;

  // Insertion order == recency order: the first key is the least recently used.
  final LinkedHashMap<String, List<RawEntry>> _lru =
      LinkedHashMap<String, List<RawEntry>>();
  int _totalEntries = 0;

  /// Number of folders currently remembered.
  int get length => _lru.length;

  /// Number of entries held across all remembered folders.
  int get totalEntries => _totalEntries;

  /// The remembered listing of [path], marking it most recently used, or null.
  List<RawEntry>? get(String path) {
    final entries = _lru.remove(path);
    if (entries == null) return null;
    _lru[path] = entries;
    return entries;
  }

  /// Whether [path] is remembered (does not change recency).
  bool contains(String path) => _lru.containsKey(path);

  /// Remembers [entries] as the listing of [path], replacing any earlier one.
  void put(String path, List<RawEntry> entries) {
    remove(path);
    if (entries.isEmpty || entries.length > maxTotalEntries) return;
    _lru[path] = entries;
    _totalEntries += entries.length;
    while (_lru.length > maxDirectories || _totalEntries > maxTotalEntries) {
      final oldest = _lru.keys.first;
      remove(oldest);
    }
  }

  /// Forgets [path].
  void remove(String path) {
    final removed = _lru.remove(path);
    if (removed != null) _totalEntries -= removed.length;
  }

  /// Forgets everything.
  void clear() {
    _lru.clear();
    _totalEntries = 0;
  }
}
