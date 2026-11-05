import 'dart:async';

import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/services/category_aggregate_scan.dart';
import 'package:vaultexplorer/features/browser/services/category_media_index_api.dart';
import 'package:vaultexplorer/features/browser/services/category_scan.dart';
import 'package:vaultexplorer/features/browser/services/device_category_index_store.dart';

/// Identifies one remembered answer: a category of one phone-storage root.
///
/// [showHidden] is part of the identity because it changes which files a scan
/// reports; a list gathered with hidden files shown must never stand in for
/// one gathered without.
class DeviceCategoryIndexKey {
  const DeviceCategoryIndexKey({
    required this.rootPath,
    required this.categoryKey,
    required this.showHidden,
  });

  final String rootPath;
  final String categoryKey;
  final bool showHidden;

  String get id => '$categoryKey|${showHidden ? 1 : 0}|$rootPath';
}

/// Remembers what category scans of phone storage found, and answers them
/// without walking the folders whenever it can.
///
/// Opening a category (or gallery mode) of phone storage used to start a scan
/// from nothing every time: an empty screen, then a walk over up to thousands
/// of folders. Three things now sit in front of that walk, cheapest first:
///
///  1. **What was found last time** ([seed]): kept in memory for the life of
///     the app and, encrypted, on disk across restarts. Shown the moment the
///     view opens, and replaced when a fresh answer arrives, so the screen is
///     never empty and never flickers.
///  2. **The platform's file index** ([lookup]): one query for every match
///     under the root, no folders visited. This is the fresh answer on a
///     normal open.
///  3. **The walk**, now pruned and cheap per folder (see
///     `CategoryScanner.respectNoMedia`, `rawLocalCategoryLister` and
///     `category_walk_policy.dart`): only when the index cannot answer, or
///     when the person asks for a full rescan (pull to refresh).
///
/// [remember] records a finished scan for the next open.
class DeviceCategoryIndex {
  DeviceCategoryIndex({
    this.media,
    this.store,
    this.maxResults = categoryScanMaxResults,
  });

  /// The platform's file index; null where there is none (the walk is used).
  final CategoryMediaIndexApi? media;

  /// Where results survive a restart; null keeps them in memory only.
  final DeviceCategoryIndexStore? store;

  /// Same bound as the walk's: past it a list is cut and flagged.
  final int maxResults;

  final Map<String, List<RawEntry>> _memory = {};
  final Map<String, int> _signatures = {};

  /// What the last scan of [key] found, to show at once, or null if nothing
  /// is known. Never slow: memory first, then at most one small file.
  Future<List<RawEntry>?> seed(DeviceCategoryIndexKey key) async {
    final remembered = _memory[key.id];
    if (remembered != null) return remembered;
    final persisted = store;
    if (persisted == null) return null;
    try {
      final loaded = await persisted.load(key.id);
      if (loaded != null) {
        _memory[key.id] = loaded;
        _signatures[key.id] = _signature(loaded);
      }
      return loaded;
    } catch (_) {
      return null;
    }
  }

  /// The matches of the category under [key]'s root straight from the
  /// platform's file index, with the same visibility rules a walk applies
  /// ([isHidden], [skipDirectory]); null when the walk has to do it.
  ///
  /// Null is also the answer when the index finds nothing or when hidden files
  /// are shown: an empty answer is far more often "the index does not cover
  /// these files" than "there are none", and the index knows nothing about
  /// hidden-folder rules, so in both cases only a walk can be trusted.
  Future<CategoryIndexHit?> lookup(
    DeviceCategoryIndexKey key, {
    required List<String> extensions,
    required bool Function(String fileName) matches,
    required bool Function(String name) isHidden,
    bool Function(String dirPath)? skipDirectory,
  }) async {
    final api = media;
    if (api == null || key.showHidden) return null;
    final rows = await api.query(
      rootPath: key.rootPath,
      extensions: extensions,
      // One more than allowed, to tell "exactly the limit" from "more".
      limit: maxResults + 1,
    );
    if (rows == null) return null;
    final entries = filterCategoryIndexRows(
      rows.entries,
      matches: matches,
      isHidden: isHidden,
      showHidden: false,
      skipDirectory: skipDirectory,
    );
    if (entries.isEmpty) return null;
    final over = rows.truncated || entries.length > maxResults;
    return CategoryIndexHit(
      over ? entries.sublist(0, maxResults) : entries,
      limitReached: over,
    );
  }

  /// Records [entries] as what [key]'s category holds now. Keeps nothing for
  /// an empty list, so a category that was emptied is not brought back as a
  /// stale stand-in. Writes to disk only when the list actually changed.
  Future<void> remember(
    DeviceCategoryIndexKey key,
    List<RawEntry> entries,
  ) async {
    if (entries.isEmpty) {
      _memory.remove(key.id);
      _signatures.remove(key.id);
      try {
        await store?.delete(key.id);
      } catch (_) {
        // A file that cannot be removed is overwritten by the next save.
      }
      return;
    }
    final snapshot = List<RawEntry>.unmodifiable(entries);
    final signature = _signature(snapshot);
    final unchanged =
        _signatures[key.id] == signature &&
        _memory[key.id]?.length == snapshot.length;
    _memory[key.id] = snapshot;
    _signatures[key.id] = signature;
    if (unchanged) return;
    try {
      await store?.save(key.id, snapshot);
    } catch (_) {
      // The next scan simply starts without a stored stand-in.
    }
  }

  /// Forgets everything, in memory and on disk.
  Future<void> clear() async {
    _memory.clear();
    _signatures.clear();
    try {
      await store?.clear();
    } catch (_) {
      // Whatever stays on disk is unreadable once the key changes and is
      // replaced by the next scan; there is nothing better to do here.
    }
  }

  /// Order-independent fingerprint of a list, so two scans that found the
  /// same files in a different order count as the same result.
  static int _signature(List<RawEntry> entries) => Object.hash(
    entries.length,
    Object.hashAllUnordered([
      for (final e in entries) Object.hash(e.name, e.sizeBytes, e.modifiedSecs),
    ]),
  );
}
