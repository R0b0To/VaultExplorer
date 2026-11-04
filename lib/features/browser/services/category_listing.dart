import 'package:vaultexplorer/features/browser/services/category_aggregate_scan.dart';

/// Where the folder-structure view of a category currently is.
///
/// [volId] null is the virtual top: with several sources holding matches it
/// lists the sources as folders; with one it is skipped (see
/// [effectiveCategoryLocation]). Otherwise [dirPath] is a real folder of that
/// source ('' is its root).
class CategoryLocation {
  const CategoryLocation(this.volId, this.dirPath);

  static const top = CategoryLocation(null, '');

  final int? volId;
  final String dirPath;

  bool get isTop => volId == null;

  @override
  bool operator ==(Object other) =>
      other is CategoryLocation &&
      other.volId == volId &&
      other.dirPath == dirPath;

  @override
  int get hashCode => Object.hash(volId, dirPath);

  @override
  String toString() => 'CategoryLocation($volId, "$dirPath")';
}

/// [location] with the source level skipped when it would only ever hold one
/// choice: if exactly one source has matches, the top is that source's root.
CategoryLocation effectiveCategoryLocation(
  CategoryAggregateSnapshot snapshot,
  CategoryLocation location,
) {
  if (!location.isTop) return location;
  final sources = snapshot.contributingSources;
  if (sources.length == 1) return CategoryLocation(sources.first, '');
  return location;
}

/// The location one step up from [location], or null when [location] is as
/// high as the folder view goes (so back leaves the view).
CategoryLocation? parentCategoryLocation(
  CategoryAggregateSnapshot snapshot,
  CategoryLocation location,
) {
  if (location.isTop) return null;
  if (location.dirPath.isNotEmpty) {
    return CategoryLocation(location.volId, parentOfPath(location.dirPath));
  }
  // At a source's root: up is the list of sources, if there is one.
  return snapshot.contributingSources.length > 1 ? CategoryLocation.top : null;
}

bool _matchesQuery(String lowercaseName, String lowercaseQuery) =>
    lowercaseQuery.isEmpty || lowercaseName.contains(lowercaseQuery);

/// The flat view: every match of every source as one folder. Each entry is
/// named by its path from its source's root, which keeps same-named files of
/// different folders apart; [CategoryEntry.sourceVolId] keeps different
/// sources apart. When [location] specifies a non-empty directory, only
/// matches inside that directory (and its descendants) are included, named
/// relative to that directory. [query] narrows by name or folder.
List<CategoryEntry> flatCategoryListing(
  CategoryAggregateSnapshot snapshot, {
  CategoryLocation? location,
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  final volId = location?.volId;
  final dir = location?.dirPath ?? '';

  Iterable<CategoryEntry> entries = snapshot.entries;
  if (volId != null) {
    entries = entries.where((e) => e.sourceVolId == volId);
  }
  if (dir.isNotEmpty) {
    final prefix = '$dir/';
    entries = entries.where(
      (e) => e.parentPath == dir || e.path.startsWith(prefix),
    );
  }
  if (q.isNotEmpty) {
    entries = entries.where((e) => _matchesQuery(e.lowercaseName, q));
  }
  return entries.map((e) {
    if (dir.isNotEmpty && e.path.startsWith('$dir/')) {
      final rel = e.path.substring(dir.length + 1);
      return e.renamedForView(rel);
    }
    return e;
  }).toList();
}

/// The folder-structure view at [location]: the folders that lead to a match
/// and the matching files directly in the folder, named like an ordinary
/// folder listing (bare names), so the browser's views resolve them against
/// the folder being shown. [labels] names the sources for the top level.
List<CategoryEntry> folderCategoryListing(
  CategoryAggregateSnapshot snapshot, {
  required CategoryLocation location,
  required Map<int, String> labels,
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  final volId = location.volId;
  if (volId == null) {
    final result = <CategoryEntry>[];
    for (final id in snapshot.contributingSources) {
      final label = labels[id] ?? '$id';
      if (!_matchesQuery(label.toLowerCase(), q)) continue;
      result.add(
        CategoryEntry(
          name: label,
          sourceVolId: id,
          path: '',
          isDir: true,
          sizeBytes: 0,
          modifiedSecs: 0,
          isSourceRoot: true,
        ),
      );
    }
    return result;
  }

  final dir = location.dirPath;
  final result = <CategoryEntry>[];
  for (final folder
      in snapshot.folderPathsBySource[volId] ?? const <String>{}) {
    if (parentOfPath(folder) != dir) continue;
    final name = folder.substring(dir.isEmpty ? 0 : dir.length + 1);
    if (!_matchesQuery(name.toLowerCase(), q)) continue;
    result.add(
      CategoryEntry(
        name: name,
        sourceVolId: volId,
        path: folder,
        isDir: true,
        sizeBytes: 0,
        modifiedSecs: 0,
      ),
    );
  }
  for (final entry in snapshot.entries) {
    if (entry.sourceVolId != volId || entry.parentPath != dir) continue;
    if (!_matchesQuery(entry.baseName.toLowerCase(), q)) continue;
    result.add(entry.renamedForView(entry.baseName));
  }
  return result;
}
