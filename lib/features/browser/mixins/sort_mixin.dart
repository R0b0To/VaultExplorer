import 'package:vaultexplorer/core/utils/raw_entry.dart';

enum SortBy {
  name,
  size,
  extension,
  date;

  String toJson() => this.name;

  static SortBy fromJson(String? value) => switch (value) {
        'size' => SortBy.size,
        'extension' => SortBy.extension,
        'date' => SortBy.date,
        _ => SortBy.name,
      };
}

/// Compares two entries the same way the file manager's sort toolbar does.
///
/// Shared so any code that flattens a directory listing into a list (the
/// file manager itself, playlist folder scans, recursive media scans, …)
/// produces results in the same order the user picked via [SortBy] /
/// [sortAscending], instead of each call site inventing its own ordering
/// (e.g. hardcoding alphabetical).
int compareEntriesBySort(
  RawEntry ea,
  RawEntry eb, {
  required SortBy sortBy,
  required bool sortAscending,
}) {
  int result;
  switch (sortBy) {
    case SortBy.name:
      result = ea.name.toLowerCase().compareTo(eb.name.toLowerCase());
    case SortBy.size:
      result = ea.sizeBytes.compareTo(eb.sizeBytes);
      if (result == 0) {
        result = ea.name.toLowerCase().compareTo(eb.name.toLowerCase());
      }
    case SortBy.extension:
      String extOf(String name) =>
          name.contains('.') ? name.split('.').last.toLowerCase() : '';
      result = extOf(ea.name).compareTo(extOf(eb.name));
      if (result == 0) {
        result = ea.name.toLowerCase().compareTo(eb.name.toLowerCase());
      }
    case SortBy.date:
      result = ea.modifiedSecs.compareTo(eb.modifiedSecs);
      if (result == 0) {
        result = ea.name.toLowerCase().compareTo(eb.name.toLowerCase());
      }
  }
  return sortAscending ? result : -result;
}

/// Compares two entries taking pinned status into account first, then
/// directories first if specified, then by [sortBy] and [sortAscending].
int compareEntriesWithPinned(
  RawEntry ea,
  RawEntry eb, {
  required SortBy sortBy,
  required bool sortAscending,
  Set<String> pinnedPaths = const {},
  String parentPath = '',
  bool directoriesFirst = false,
}) {
  final aPath = parentPath.isEmpty ? ea.name : '$parentPath/${ea.name}';
  final bPath = parentPath.isEmpty ? eb.name : '$parentPath/${eb.name}';
  final aPinned = pinnedPaths.contains(aPath);
  final bPinned = pinnedPaths.contains(bPath);
  if (aPinned != bPinned) {
    return aPinned ? -1 : 1;
  }
  if (directoriesFirst && ea.isDir != eb.isDir) {
    return ea.isDir ? -1 : 1;
  }
  return compareEntriesBySort(
    ea,
    eb,
    sortBy: sortBy,
    sortAscending: sortAscending,
  );
}

// The mixin that used to live here (`mixin SortMixin<T extends
// StatefulWidget> on State<T>`) was FileBrowserScreen's only consumer --
// see lib/features/browser/controllers/file_browser_sort_controller.dart
// for its Riverpod replacement. SortBy and the comparison functions above
// stay here since playlist_controller.dart and media_viewer_screen.dart
// still use them directly.