import 'package:flutter/foundation.dart';
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
    if (query.isNotEmpty && !item.name.toLowerCase().contains(query)) {
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
/// are.
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
    return deepSearchResults
        .where((item) => visible(item, skipQueryCheck: true))
        .toList();
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

BrowserListing buildBrowserListing(BrowserListingInputs inputs) {
  final visibleCurrent = inputs.items.where(
    (e) => !inputs.pendingDeletedNames.contains(e.name),
  );
  final existingNamesLower = visibleCurrent.map((e) => e.lowercaseName).toSet();
  final uniquePlaceholders = inputs.placeholders.where(
    (p) => !existingNamesLower.contains(p.lowercaseName),
  );
  final combined = [...visibleCurrent, ...uniquePlaceholders];

  final items = searchAwareVisibleItems(
    combined,
    query: inputs.query,
    searchActive: inputs.searchActive,
    deepSearch: inputs.deepSearch,
    deepSearchResults: inputs.deepSearchResults,
    showHidden: inputs.showHidden,
    typeFilter: inputs.typeFilter,
  )..sort(
      (ea, eb) => compareBrowserEntries(
        ea,
        eb,
        currentDirPath: inputs.currentDirPath,
        pinnedPaths: inputs.pinnedPaths,
        sortBy: inputs.sortBy,
        sortAscending: inputs.sortAscending,
      ),
    );

  var dirCount = 0;
  for (final item in items) {
    if (item.isDir) dirCount++;
  }
  return BrowserListing(
    items: items,
    dirCount: dirCount,
    fileCount: items.length - dirCount,
  );
}

/// Remembers the last listing so a rebuild that changed nothing relevant (a
/// scroll tick, a thumbnail arriving) does not sort the directory again.
class BrowserListingCache {
  BrowserListingInputs? _inputs;
  BrowserListing? _listing;

  BrowserListing resolve(BrowserListingInputs inputs) {
    final cached = _listing;
    final previous = _inputs;
    if (cached != null && previous != null && previous.sameListingAs(inputs)) {
      return cached;
    }
    final listing = buildBrowserListing(inputs);
    _inputs = inputs;
    _listing = listing;
    return listing;
  }
}
