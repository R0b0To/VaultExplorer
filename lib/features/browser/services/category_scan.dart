import 'dart:async';

import 'package:vaultexplorer/core/utils/bounded_semaphore.dart';
import 'package:vaultexplorer/core/utils/cancellation_token.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';

/// Recursion-depth guard for [CategoryScanner].
const categoryScanMaxDepth = 32;

/// Directory listings in flight at once. Same bound the media scan and the
/// deep search use: an unbounded fan-out over a wide tree is what froze the
/// app there.
const categoryScanMaxConcurrency = 6;

/// Hard cap on folders visited, so a storage with an enormous tree cannot turn
/// one tap into an endless walk.
const categoryScanMaxFolders = 30000;

/// Cap on collected files. A category view is meant to list "everything", so
/// this is far above the media scan's, but it still bounds memory.
const categoryScanMaxResults = 50000;

/// The file whose presence marks a folder (and everything below it) as not
/// meant for browsing; see [CategoryScanner.respectNoMedia].
const kNoMediaMarkerName = '.nomedia';

/// Lists one folder of the scanned storage in the directory-entry wire format
/// (see [RawEntry]); null when the folder cannot be listed.
typedef CategoryDirectoryLister = Future<List<String>?> Function(
  String dirPath,
);

/// What a scan has found so far, or all of it once [finished].
///
/// Every snapshot owns fresh collections, so one can be kept and compared by
/// identity (the browser's listing cache does) while the scan carries on.
class CategoryScanSnapshot {
  const CategoryScanSnapshot({
    required this.entries,
    required this.folderPaths,
    required this.foldersChecked,
    required this.finished,
    required this.limitReached,
  });

  static const empty = CategoryScanSnapshot(
    entries: <RawEntry>[],
    folderPaths: <String>{},
    foldersChecked: 0,
    finished: false,
    limitReached: false,
  );

  /// Matching files. Each entry's name is its path relative to the folder the
  /// scan started from (`DCIM/Camera/IMG_1.jpg`), so it addresses the file the
  /// same way a deep-search result does.
  final List<RawEntry> entries;

  /// Every folder, as a path relative to the scan root, that holds a match
  /// directly or somewhere beneath it. The root itself ('') is not included.
  /// This is what lets the browser show the original folder structure with
  /// only the folders that lead to something in the category.
  final Set<String> folderPaths;

  final int foldersChecked;

  /// False while the walk is still running.
  final bool finished;

  /// True when the walk stopped at a limit rather than running out of folders,
  /// so the list may be missing files.
  final bool limitReached;

  CategoryScanSnapshot withoutPaths(Set<String> removedFullPaths) {
    if (removedFullPaths.isEmpty) return this;
    final kept = entries
        .where((e) => !removedFullPaths.contains(e.name))
        .toList(growable: false);
    if (kept.length == entries.length) return this;
    final folders = <String>{};
    for (final entry in kept) {
      _addAncestors(folders, _parentOf(entry.name));
    }
    return CategoryScanSnapshot(
      entries: kept,
      folderPaths: folders,
      foldersChecked: foldersChecked,
      finished: finished,
      limitReached: limitReached,
    );
  }
}

String _parentOf(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? '' : path.substring(0, slash);
}

/// Adds [dirPath] and each of its ancestors (never the root) to [folders].
void _addAncestors(Set<String> folders, String dirPath) {
  var path = dirPath;
  // `add` is false once a folder is already known, and its ancestors were
  // added together with it, so the climb can stop there.
  while (path.isNotEmpty && folders.add(path)) {
    path = _parentOf(path);
  }
}

/// Walks a storage's folder tree and collects every file [matches] accepts.
///
/// It knows nothing about vaults, SAF or widgets: listing goes through
/// [listDirectory], so the same walk serves a vault, phone storage and an
/// external location, and it can be tested with a map standing in for a disk.
class CategoryScanner {
  CategoryScanner({
    required this.listDirectory,
    required this.matches,
    required this.isHidden,
    required this.showHidden,
    this.skipDirectory,
    this.respectNoMedia = false,
    this.onError,
    this.sharedSemaphore,
    this.maxDepth = categoryScanMaxDepth,
    this.maxConcurrency = categoryScanMaxConcurrency,
    this.maxFolders = categoryScanMaxFolders,
    this.maxResults = categoryScanMaxResults,
  });

  final CategoryDirectoryLister listDirectory;

  /// Whether a file name belongs to the category.
  final bool Function(String fileName) matches;

  /// Whether a name is a hidden file or folder (skipped unless [showHidden]).
  final bool Function(String name) isHidden;
  final bool showHidden;

  /// Folders (given by their path from the scan root) not worth descending
  /// into, e.g. ones the OS never lets the app list.
  final bool Function(String dirPath)? skipDirectory;

  /// Treat a folder holding a `.nomedia` file as off limits, together with
  /// everything beneath it: the convention Android's media scanner and every
  /// gallery app follow for "nothing in here is for browsing".
  ///
  /// The marker is read from the listing that was fetched anyway, so honouring
  /// it costs nothing and spares the whole subtree. It is not applied to the
  /// scan root (a storage someone chose to open is never pruned away), and not
  /// while [showHidden] is on, since that is asking to see what is normally
  /// left out. A lister has to report the marker (see
  /// [kNoMediaMarkerName]); it is hidden by name, so [matches] never sees it.
  final bool respectNoMedia;

  /// Called when one folder could not be listed. The walk carries on.
  final void Function(String dirPath, Object error)? onError;

  /// Bounds listings in flight across several scanners running side by side
  /// (one per storage source); when null each scan gets its own, sized
  /// [maxConcurrency].
  final BoundedSemaphore? sharedSemaphore;

  final int maxDepth;
  final int maxConcurrency;
  final int maxFolders;
  final int maxResults;

  /// Scans from the storage root. [onProgress] gets a snapshot at most about
  /// every [progressInterval] while the walk runs, so a caller can show files
  /// as they turn up; the returned snapshot is the final one.
  Future<CategoryScanSnapshot> scan({
    required CancellationToken token,
    void Function(CategoryScanSnapshot snapshot)? onProgress,
    Duration progressInterval = const Duration(milliseconds: 250),
  }) async {
    final entries = <RawEntry>[];
    final folders = <String>{};
    var foldersChecked = 0;
    var limitReached = false;
    final semaphore = sharedSemaphore ?? BoundedSemaphore(maxConcurrency);
    final clock = Stopwatch()..start();
    var lastPublishedMs = 0;

    CategoryScanSnapshot snapshot({required bool finished}) =>
        CategoryScanSnapshot(
          entries: List<RawEntry>.of(entries),
          folderPaths: Set<String>.of(folders),
          foldersChecked: foldersChecked,
          finished: finished,
          limitReached: limitReached,
        );

    void publishIfDue() {
      if (onProgress == null || token.isCancelled) return;
      final now = clock.elapsedMilliseconds;
      if (now - lastPublishedMs < progressInterval.inMilliseconds) return;
      lastPublishedMs = now;
      onProgress(snapshot(finished: false));
    }

    bool shouldStop() {
      if (token.isCancelled) return true;
      if (foldersChecked >= maxFolders || entries.length >= maxResults) {
        limitReached = true;
        return true;
      }
      return false;
    }

    Future<void> walk(String dirPath, int depth) async {
      if (shouldStop()) return;
      List<String>? raw;
      await semaphore.acquire();
      try {
        // A folder queued behind the others can reach the front long after the
        // scan it belonged to was cancelled; don't spend a listing on it.
        if (shouldStop()) return;
        raw = await listDirectory(dirPath);
      } catch (e) {
        onError?.call(dirPath, e);
      } finally {
        // Released before descending, not after: holding the slot for the whole
        // subtree would leave the others idle on a deep tree.
        semaphore.release();
      }
      foldersChecked++;
      if (raw == null || token.isCancelled) return;

      final subdirs = <String>[];
      try {
        final listed = RawEntry.parseAll(raw);
        if (respectNoMedia && !showHidden && depth > 0) {
          for (final entry in listed) {
            if (!entry.isDir && entry.name == kNoMediaMarkerName) {
              publishIfDue();
              return;
            }
          }
        }
        for (final entry in listed) {
          if (!showHidden && isHidden(entry.name)) continue;
          final path = dirPath.isEmpty ? entry.name : '$dirPath/${entry.name}';
          if (entry.isDir) {
            if (depth < maxDepth && !(skipDirectory?.call(path) ?? false)) {
              subdirs.add(path);
            }
          } else if (matches(entry.name)) {
            if (entries.length >= maxResults) {
              limitReached = true;
              break;
            }
            entries.add(entry.withName(path));
            _addAncestors(folders, dirPath);
          }
        }
      } catch (e) {
        onError?.call(dirPath, e);
      }
      publishIfDue();

      if (subdirs.isEmpty || shouldStop()) return;
      await Future.wait(subdirs.map((path) => walk(path, depth + 1)));
    }

    await walk('', 0);
    return snapshot(finished: !token.isCancelled);
  }
}
