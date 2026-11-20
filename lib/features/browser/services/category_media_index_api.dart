import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';
import 'package:vaultexplorer/features/browser/services/category_walk_policy.dart';

/// Calls one native method with named arguments and returns what it answered.
/// In the app this is the engine's method channel; tests pass a fake.
typedef CategoryIndexInvoker =
    Future<Object?> Function(String method, Map<String, Object?> arguments);

/// What the platform's media index knows under one storage root.
class CategoryMediaIndexRows {
  const CategoryMediaIndexRows({
    required this.entries,
    required this.truncated,
  });

  /// Matching files, each named by its path relative to the queried root.
  final List<RawEntry> entries;

  /// True when the index held more matches than were asked for.
  final bool truncated;
}

/// The platform's own file index (Android's MediaStore), asked for every file
/// of a category under a storage root in one query instead of walking the
/// folders to find them.
///
/// The index only says *which paths exist*: the native side confirms each one
/// on disk and reads its real size and date, so a stale row (a file deleted
/// behind the index's back) never shows up, and what comes back agrees with
/// what a walk would have reported.
class CategoryMediaIndexApi {
  const CategoryMediaIndexApi(this._invoke);

  final CategoryIndexInvoker _invoke;

  /// Every file under [rootPath] whose extension is one of [extensions]
  /// (lower-case, no dot), at most [limit] of them; null when the index
  /// cannot answer (not available here, not permitted, or it failed), which
  /// means the caller has to walk instead.
  Future<CategoryMediaIndexRows?> query({
    required String rootPath,
    required List<String> extensions,
    required int limit,
  }) async {
    try {
      final answer = await _invoke(ChannelMethods.queryCategoryIndex, {
        'rootPath': rootPath,
        'extensions': extensions,
        'limit': limit,
      });
      if (answer is! Map) return null;
      final raw = answer['entries'];
      if (raw is! List) return null;
      final entries = <RawEntry>[];
      for (final line in raw) {
        if (line is! String) continue;
        try {
          entries.add(RawEntry.parse(line));
        } on FormatException {
          // One malformed row is not worth giving up the rest for.
        }
      }
      return CategoryMediaIndexRows(
        entries: entries,
        truncated: answer['truncated'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Applies to [rows] (files named by their path from the storage root) the
/// rules a walk applies as it goes, so an index answer and a walk agree:
///
///  - the file name must satisfy [matches],
///  - no folder on the way may be hidden, unless [showHidden],
///  - no folder on the way may be one [skipDirectory] rejects.
List<RawEntry> filterCategoryIndexRows(
  Iterable<RawEntry> rows, {
  required bool Function(String fileName) matches,
  required bool Function(String name) isHidden,
  required bool showHidden,
  bool Function(String dirPath)? skipDirectory,
}) {
  final verdicts = <String, bool>{};
  final kept = <RawEntry>[];
  for (final row in rows) {
    if (row.isDir) continue;
    final path = row.name;
    final slash = path.lastIndexOf('/');
    final fileName = slash < 0 ? path : path.substring(slash + 1);
    if (!matches(fileName)) continue;
    if (!showHidden && path.split('/').any(isHidden)) continue;
    if (skipDirectory != null &&
        hasSkippedAncestor(path, skipDirectory, verdicts)) {
      continue;
    }
    kept.add(row);
  }
  return kept;
}
