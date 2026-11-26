import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/core/utils/natural_sort.dart';
import 'package:vaultexplorer/core/utils/perf_trace.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/file_browser_predicates.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';

/// Pure logic behind a directory listing: which entries are shown and in what
/// order. Nothing here knows about widgets, providers or the vault, so it is
/// tested directly and every call site that needs "what is visible" shares one
/// definition.

/// Total order used everywhere a listing is sorted: pinned entries first, then
/// folders, then by the chosen sort field and direction.
int compareBrowserEntries(
  RawEntry ea,
  RawEntry eb, {
  required String currentDirPath,
  required Set<String> pinnedPaths,
  required SortBy sortBy,
  required bool sortAscending,
}) {
  if (pinnedPaths.isNotEmpty) {
    final aPinned = isPinned(ea, currentDirPath, pinnedPaths);
    final bPinned = isPinned(eb, currentDirPath, pinnedPaths);
    if (aPinned != bPinned) return aPinned ? -1 : 1;
  }
  return _compareDirsThenSort(
    ea,
    eb,
    sortBy: sortBy,
    sortAscending: sortAscending,
  );
}

/// The part of [compareBrowserEntries] after the pinned check: folders
/// first, then the chosen sort field. Shared so the cached sort in
/// [buildBrowserListing] cannot drift from it.
int _compareDirsThenSort(
  RawEntry ea,
  RawEntry eb, {
  required SortBy sortBy,
  required bool sortAscending,
}) {
  if (ea.isDir != eb.isDir) return ea.isDir ? -1 : 1;
  return compareEntriesBySort(
    ea,
    eb,
    sortBy: sortBy,
    sortAscending: sortAscending,
  );
}

/// Whether [item] belongs in the listing: respects the hidden-files toggle,
/// the search [query] (already trimmed and lower-cased) and the type filter.
///
/// [skipQueryCheck] is for entries that come from the search scan itself. The
/// scan already matched them, by name or, for an Item Vault entry, by a field
/// such as username or email, so re-checking the name would wrongly drop a
/// content-only match. Hidden files and the type filter still apply.
bool isVisibleInListing(
  RawEntry item, {
  required String query,
  required bool showHidden,
  required String? typeFilter,
  bool skipQueryCheck = false,
}) {
  if (!showHidden && isHiddenEntryName(item.name)) return false;
  if (!skipQueryCheck) {
    if (query.isNotEmpty && !item.lowercaseName.contains(query)) {
      return false;
    }
  }
  if (item.isDir) {
    if (query.isEmpty && typeFilter != null) return false;
    return true;
  }
  return matchesFilter(item.name, typeFilter);
}

/// Search-aware view of [localItems] (the directory's own entries, already
/// merged with placeholders and pending deletes where the caller does that).
///
/// A plain name search filters [localItems] instantly. The scan's results only
/// add what that pass could not find (an Item Vault entry matched by username
/// or email), so a name search never waits on the scan. In deep-search mode
/// the scan results already span every matched folder and are used as they
/// are, with the matches in the folder itself (already loaded) shown at once
/// rather than after the scan: it takes a moment, and an empty list while it
/// runs reads as "nothing found".
List<RawEntry> searchAwareVisibleItems(
  List<RawEntry> localItems, {
  required String query,
  required bool searchActive,
  required bool deepSearch,
  required List<RawEntry> deepSearchResults,
  required bool showHidden,
  required String? typeFilter,
}) {
  bool visible(RawEntry item, {bool skipQueryCheck = false}) =>
      isVisibleInListing(
        item,
        query: query,
        showHidden: showHidden,
        typeFilter: typeFilter,
        skipQueryCheck: skipQueryCheck,
      );

  if (!searchActive || query.isEmpty) {
    return localItems.where(visible).toList();
  }
  if (deepSearch) {
    final scanned = deepSearchResults
        .where((item) => visible(item, skipQueryCheck: true))
        .toList();
    // The scan lists this folder too, so what it already returned for it is
    // not shown a second time. Its entries from subfolders carry a relative
    // path (`sub/name`) and never clash with the folder's own names.
    final scannedHere = <String>{
      for (final item in scanned)
        if (!item.name.contains('/')) item.lowercaseName,
    };
    final instant = localItems.where(
      (item) => visible(item) && !scannedHere.contains(item.lowercaseName),
    );
    return [...instant, ...scanned];
  }
  final instant = localItems.where(visible).toList();
  final instantLowerNames = instant.map((e) => e.lowercaseName).toSet();
  final contentOnlyMatches = deepSearchResults.where(
    (item) =>
        !instantLowerNames.contains(item.lowercaseName) &&
        visible(item, skipQueryCheck: true),
  );
  return [...instant, ...contentOnlyMatches];
}

/// Everything that decides what a listing shows. Two inputs that
/// [sameListingAs] each other always produce the same [BrowserListing].
@immutable
class BrowserListingInputs {
  const BrowserListingInputs({
    required this.items,
    this.preSortedByNameAsc = false,
    required this.placeholders,
    required this.pendingDeletedNames,
    required this.query,
    required this.searchActive,
    required this.deepSearch,
    required this.deepSearchResults,
    required this.showHidden,
    required this.typeFilter,
    required this.currentDirPath,
    required this.pinnedPaths,
    required this.sortBy,
    required this.sortAscending,
  });

  /// The directory's own entries.
  final List<RawEntry> items;
  final bool preSortedByNameAsc;

  /// Entries that stand in for transfers still in progress.
  final List<RawEntry> placeholders;
  final Set<String> pendingDeletedNames;

  /// Trimmed and lower-cased.
  final String query;
  final bool searchActive;
  final bool deepSearch;
  final List<RawEntry> deepSearchResults;
  final bool showHidden;
  final String? typeFilter;
  final String currentDirPath;
  final Set<String> pinnedPaths;
  final SortBy sortBy;
  final bool sortAscending;

  /// Whether [other] would produce the same listing. The big lists are
  /// compared by identity (they are replaced, not edited, when they change);
  /// the small ones by content, so swapping one pinned path or placeholder for
  /// another of the same count is still noticed.
  ///
  /// Placeholders are compared by what they stand for (name and kind), not by
  /// every field: their size and time move with the transfer's progress, and
  /// re-sorting the directory on every progress tick would be wasted work.
  bool sameListingAs(BrowserListingInputs other) =>
      identical(items, other.items) &&
      preSortedByNameAsc == other.preSortedByNameAsc &&
      identical(deepSearchResults, other.deepSearchResults) &&
      currentDirPath == other.currentDirPath &&
      query == other.query &&
      searchActive == other.searchActive &&
      deepSearch == other.deepSearch &&
      typeFilter == other.typeFilter &&
      showHidden == other.showHidden &&
      sortBy == other.sortBy &&
      sortAscending == other.sortAscending &&
      _samePlaceholders(placeholders, other.placeholders) &&
      setEquals(pendingDeletedNames, other.pendingDeletedNames) &&
      (identical(pinnedPaths, other.pinnedPaths) ||
          setEquals(pinnedPaths, other.pinnedPaths));
}

bool _samePlaceholders(List<RawEntry> a, List<RawEntry> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].name != b[i].name || a[i].isDir != b[i].isDir) return false;
  }
  return true;
}

/// The visible entries in display order, with their folder and file counts.
@immutable
class BrowserListing {
  const BrowserListing({
    required this.items,
    required this.dirCount,
    required this.fileCount,
  });

  final List<RawEntry> items;
  final int dirCount;
  final int fileCount;
}

Comparator<RawEntry> _comparatorFor(SortBy sortBy, bool asc) {
  switch (sortBy) {
    case SortBy.name:
      return asc
          ? (ea, eb) => naturalCompare(ea.lowercaseName, eb.lowercaseName)
          : (ea, eb) => naturalCompare(eb.lowercaseName, ea.lowercaseName);
    case SortBy.size:
      return (ea, eb) {
        var r = ea.sizeBytes.compareTo(eb.sizeBytes);
        if (r == 0) r = naturalCompare(ea.lowercaseName, eb.lowercaseName);
        return asc ? r : -r;
      };
    case SortBy.extension:
      return (ea, eb) {
        var r = ea.extension.compareTo(eb.extension);
        if (r == 0) r = naturalCompare(ea.lowercaseName, eb.lowercaseName);
        return asc ? r : -r;
      };
    case SortBy.date:
      return (ea, eb) {
        var r = ea.modifiedSecs.compareTo(eb.modifiedSecs);
        if (r == 0) r = naturalCompare(ea.lowercaseName, eb.lowercaseName);
        return asc ? r : -r;
      };
  }
}

BrowserListing buildBrowserListing(BrowserListingInputs inputs) {
  final hasPlaceholders = inputs.placeholders.isNotEmpty;
  final hasPendingDeletes = inputs.pendingDeletedNames.isNotEmpty;
  final hasQuery = inputs.searchActive && inputs.query.isNotEmpty;
  final comparator = _comparatorFor(inputs.sortBy, inputs.sortAscending);

  Set<String>? pinnedNamesInDir;
  if (inputs.pinnedPaths.isNotEmpty) {
    final prefix =
        inputs.currentDirPath.isEmpty ? '' : '${inputs.currentDirPath}/';
    for (final path in inputs.pinnedPaths) {
      if (prefix.isEmpty) {
        if (!path.contains('/')) (pinnedNamesInDir ??= <String>{}).add(path);
      } else if (path.startsWith(prefix)) {
        final rest = path.substring(prefix.length);
        if (!rest.contains('/')) (pinnedNamesInDir ??= <String>{}).add(rest);
      }
    }
  }

  final List<RawEntry> visible;
  if (!hasPlaceholders &&
      !hasPendingDeletes &&
      !hasQuery &&
      inputs.typeFilter == null) {
    if (inputs.preSortedByNameAsc &&
        inputs.sortBy == SortBy.name &&
        inputs.sortAscending &&
        pinnedNamesInDir == null) {
      if (inputs.showHidden) {
        var dirCount = 0;
        while (dirCount < inputs.items.length && inputs.items[dirCount].isDir) {
          dirCount++;
        }
        return BrowserListing(
          items: inputs.items,
          dirCount: dirCount,
          fileCount: inputs.items.length - dirCount,
        );
      }
      var dirCount = 0;
      var skippedAny = false;
      for (final item in inputs.items) {
        if (isHiddenEntryName(item.name)) {
          skippedAny = true;
          continue;
        }
        if (item.isDir) dirCount++;
      }
      final result = skippedAny
          ? [
              for (final item in inputs.items)
                if (!isHiddenEntryName(item.name)) item,
            ]
          : inputs.items;
      return BrowserListing(
        items: result,
        dirCount: dirCount,
        fileCount: result.length - dirCount,
      );
    }
    if (inputs.showHidden && pinnedNamesInDir == null) {
      visible = inputs.items;
    } else if (!inputs.showHidden && pinnedNamesInDir == null) {
      var dirCount = 0;
      var seenFile = false;
      var alreadyPartitionedAndSorted = true;
      var skippedAny = false;
      RawEntry? prev;
      for (final item in inputs.items) {
        if (isHiddenEntryName(item.name)) {
          skippedAny = true;
          continue;
        }
        if (item.isDir) {
          if (seenFile) {
            alreadyPartitionedAndSorted = false;
            break;
          }
          dirCount++;
          if (prev != null && comparator(prev, item) > 0) {
            alreadyPartitionedAndSorted = false;
            break;
          }
        } else {
          if (!seenFile) {
            seenFile = true;
            prev = null;
          }
          if (prev != null && comparator(prev, item) > 0) {
            alreadyPartitionedAndSorted = false;
            break;
          }
        }
        prev = item;
      }
      if (alreadyPartitionedAndSorted) {
        final result = skippedAny
            ? [
                for (final item in inputs.items)
                  if (!isHiddenEntryName(item.name)) item,
              ]
            : inputs.items;
        return BrowserListing(
          items: result,
          dirCount: dirCount,
          fileCount: result.length - dirCount,
        );
      }
      visible = inputs.items
          .where((item) => !isHiddenEntryName(item.name))
          .toList();
    } else {
      visible = inputs.showHidden
          ? inputs.items
          : inputs.items
              .where((item) => !isHiddenEntryName(item.name))
              .toList();
    }
  } else {
    final Iterable<RawEntry> visibleCurrent = hasPendingDeletes
        ? inputs.items.where((e) => !inputs.pendingDeletedNames.contains(e.name))
        : inputs.items;

    final List<RawEntry> combined;
    if (!hasPlaceholders) {
      combined = visibleCurrent is List<RawEntry>
          ? visibleCurrent
          : visibleCurrent.toList();
    } else {
      final existingNamesLower =
          visibleCurrent.map((e) => e.lowercaseName).toSet();
      final uniquePlaceholders = inputs.placeholders.where(
        (p) => !existingNamesLower.contains(p.lowercaseName),
      );
      combined = [...visibleCurrent, ...uniquePlaceholders];
    }

    visible = searchAwareVisibleItems(
      combined,
      query: inputs.query,
      searchActive: inputs.searchActive,
      deepSearch: inputs.deepSearch,
      deepSearchResults: inputs.deepSearchResults,
      showHidden: inputs.showHidden,
      typeFilter: inputs.typeFilter,
    );
  }

  final dirs = <RawEntry>[];
  final files = <RawEntry>[];

  bool isSorted(List<RawEntry> list) {
    for (var i = 1; i < list.length; i++) {
      if (comparator(list[i - 1], list[i]) > 0) return false;
    }
    return true;
  }

  if (pinnedNamesInDir == null) {
    var dirCount = 0;
    var seenFile = false;
    var alreadyPartitionedAndSorted = true;
    RawEntry? prev;
    for (final item in visible) {
      if (item.isDir) {
        if (seenFile) {
          alreadyPartitionedAndSorted = false;
          break;
        }
        dirCount++;
        if (prev != null && comparator(prev, item) > 0) {
          alreadyPartitionedAndSorted = false;
          break;
        }
      } else {
        if (!seenFile) {
          seenFile = true;
          prev = null;
        }
        if (prev != null && comparator(prev, item) > 0) {
          alreadyPartitionedAndSorted = false;
          break;
        }
      }
      prev = item;
    }
    if (alreadyPartitionedAndSorted) {
      return BrowserListing(
        items: visible,
        dirCount: dirCount,
        fileCount: visible.length - dirCount,
      );
    }

    for (final item in visible) {
      if (item.isDir) {
        dirs.add(item);
      } else {
        files.add(item);
      }
    }
    if (dirs.length > 1 && !isSorted(dirs)) dirs.sort(comparator);
    if (files.length > 1 && !isSorted(files)) files.sort(comparator);
    final items = dirs.isEmpty
        ? files
        : (files.isEmpty ? dirs : <RawEntry>[...dirs, ...files]);
    return BrowserListing(
      items: items,
      dirCount: dirs.length,
      fileCount: files.length,
    );
  }

  final pinnedDirs = <RawEntry>[];
  final pinnedFiles = <RawEntry>[];
  for (final item in visible) {
    if (pinnedNamesInDir.contains(item.name)) {
      if (item.isDir) {
        pinnedDirs.add(item);
      } else {
        pinnedFiles.add(item);
      }
    } else if (item.isDir) {
      dirs.add(item);
    } else {
      files.add(item);
    }
  }
  if (pinnedDirs.length > 1 && !isSorted(pinnedDirs)) {
    pinnedDirs.sort(comparator);
  }
  if (pinnedFiles.length > 1 && !isSorted(pinnedFiles)) {
    pinnedFiles.sort(comparator);
  }
  if (dirs.length > 1 && !isSorted(dirs)) dirs.sort(comparator);
  if (files.length > 1 && !isSorted(files)) files.sort(comparator);
  final items = <RawEntry>[...pinnedDirs, ...pinnedFiles, ...dirs, ...files];
  final dirCount = pinnedDirs.length + dirs.length;
  return BrowserListing(
    items: items,
    dirCount: dirCount,
    fileCount: items.length - dirCount,
  );
}

/// Remembers recent listings so a rebuild or folder/tab switch that changed
/// nothing relevant does not sort the directory again.
class BrowserListingCache {
  static const int _maxEntries = 6;
  final List<({BrowserListingInputs inputs, BrowserListing listing})> _entries =
      [];

  BrowserListing resolve(BrowserListingInputs inputs) {
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      if (entry.inputs.sameListingAs(inputs)) {
        if (i != 0) {
          _entries.removeAt(i);
          _entries.insert(0, entry);
        }
        return entry.listing;
      }
    }
    final perfT0 = PerfTrace.begin();
    final listing = buildBrowserListing(inputs);
    PerfTrace.end('browser.listing.build', perfT0, slowMs: 16);
    _entries.insert(0, (inputs: inputs, listing: listing));
    if (_entries.length > _maxEntries) _entries.removeLast();
    return listing;
  }
}
