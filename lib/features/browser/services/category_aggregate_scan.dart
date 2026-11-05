import 'dart:async';

import 'package:vaultexplorer/core/utils/bounded_semaphore.dart';
import 'package:vaultexplorer/core/utils/cancellation_token.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/models/category_source.dart';
import 'package:vaultexplorer/features/browser/services/category_scan.dart';

/// A file or folder found by a category scan, tagged with where it lives.
///
/// It is a [RawEntry], so the browser's list and grid views, their selection
/// sets and sorting take it unchanged, but it also remembers its [sourceVolId]
/// and its full [path] inside that source. Operations (open, share, rename,
/// delete, copy) always go by those two, never by [name]: [name] is only what
/// the view needs to show and to resolve against the folder it displays, and
/// it differs between the flat view (a path from the source root) and the
/// folder view (a bare name).
class CategoryEntry extends RawEntry {
  CategoryEntry({
    required String name,
    required this.sourceVolId,
    required this.path,
    required super.isDir,
    required super.sizeBytes,
    required super.modifiedSecs,
    this.isSourceRoot = false,
  }) : super(
         name: name,
         lowercaseName: name.toLowerCase(),
         extension: name.contains('.')
             ? name.split('.').last.toLowerCase()
             : '',
       );

  /// The volume id of the source this entry lives in.
  final int sourceVolId;

  /// Full path inside the source ('' is the source's root).
  final String path;

  /// True for the stand-in folder of a whole source, shown at the top of the
  /// folder view when several sources have matches. It is not a real path.
  final bool isSourceRoot;

  /// The folder [path] sits in, within the source.
  String get parentPath => parentOfPath(path);

  /// The last segment of [path].
  String get baseName {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  /// This entry shown under another [name] (same file, same identity).
  CategoryEntry renamedForView(String newName) => CategoryEntry(
    name: newName,
    sourceVolId: sourceVolId,
    path: path,
    isDir: isDir,
    sizeBytes: sizeBytes,
    modifiedSecs: modifiedSecs,
    isSourceRoot: isSourceRoot,
  );

  // Two files with the same path, size and date in different sources are
  // different files; RawEntry's equality alone would merge them in a
  // selection set.
  @override
  bool operator ==(Object other) =>
      other is CategoryEntry &&
      other.sourceVolId == sourceVolId &&
      other.path == path &&
      other.isDir == isDir &&
      other.sizeBytes == sizeBytes &&
      other.modifiedSecs == modifiedSecs &&
      other.isSourceRoot == isSourceRoot;

  @override
  int get hashCode => Object.hash(
    sourceVolId,
    path,
    isDir,
    sizeBytes,
    modifiedSecs,
    isSourceRoot,
  );

  @override
  String toString() => 'CategoryEntry(vol $sourceVolId, $path)';
}

/// The folder part of a '/'-separated [path] ('' for a top-level name).
String parentOfPath(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? '' : path.substring(0, slash);
}

/// What a source's cheap answer to "which files are in this category" holds.
///
/// See [CategoryScanTarget.indexLookup].
class CategoryIndexHit {
  const CategoryIndexHit(this.entries, {this.limitReached = false});

  /// The matching files, each named by its path from the source's root.
  final List<RawEntry> entries;

  /// True when there were more matches than [entries] holds.
  final bool limitReached;
}

/// Answers a source's category from something cheaper than walking it (the
/// platform's own file index), or null when it cannot, which sends the scan
/// down the walk. May throw: that counts as null.
typedef CategoryIndexLookup = Future<CategoryIndexHit?> Function();

/// One source to scan, with the means to list it.
class CategoryScanTarget {
  const CategoryScanTarget({
    required this.source,
    required this.listDirectory,
    this.skipDirectory,
    this.respectNoMedia = false,
    this.indexLookup,
    this.seed,
  });

  final CategorySource source;
  final CategoryDirectoryLister listDirectory;
  final bool Function(String dirPath)? skipDirectory;

  /// See [CategoryScanner.respectNoMedia].
  final bool respectNoMedia;

  /// A way to get this source's matches without visiting its folders. It is
  /// tried first; only when it gives null (or throws) does the source get
  /// walked. A result replaces the [seed] at once and is final: nothing is
  /// listed, so [CategoryAggregateSnapshot.foldersChecked] stays 0 for it.
  final CategoryIndexLookup? indexLookup;

  /// What an earlier scan of this source found (entries named by their path
  /// from the source's root), such as a vault's stored category index.
  ///
  /// It is shown at once, and stays on screen, untouched by the partial
  /// results of the new scan, until that scan finishes and replaces it: the
  /// list neither stays empty while the source is read nor shrinks and regrows
  /// as the scan catches up. It can be out of date, which is why it is only
  /// ever a stand-in for the scan, never a result.
  final List<RawEntry>? seed;
}

/// What a multi-source scan has found so far, or all of it once [finished].
///
/// Like [CategoryScanSnapshot], each snapshot owns its collections and can be
/// kept and compared by identity while the scan carries on.
class CategoryAggregateSnapshot {
  const CategoryAggregateSnapshot({
    required this.entries,
    required this.folderPathsBySource,
    required this.foldersChecked,
    required this.finished,
    required this.limitReached,
    required this.failedSources,
  });

  static const empty = CategoryAggregateSnapshot(
    entries: <CategoryEntry>[],
    folderPathsBySource: <int, Set<String>>{},
    foldersChecked: 0,
    finished: false,
    limitReached: false,
    failedSources: <int>{},
  );

  /// Every match, each named by its path from its source's root.
  final List<CategoryEntry> entries;

  /// Per source: every folder (path from the source root, never '' itself)
  /// that holds a match directly or beneath it.
  final Map<int, Set<String>> folderPathsBySource;

  final int foldersChecked;
  final bool finished;

  /// True when some source stopped at a limit, so the list may be incomplete.
  final bool limitReached;

  /// Sources whose scan failed outright (as opposed to single unreadable
  /// folders, which are skipped silently).
  final Set<int> failedSources;

  /// The volume ids of the sources that have at least one match.
  Set<int> get contributingSources => {for (final e in entries) e.sourceVolId};

  /// This snapshot without the entries of [volId], used the moment a vault is
  /// locked so none of its names stay on screen.
  CategoryAggregateSnapshot withoutSource(int volId) {
    if (!entries.any((e) => e.sourceVolId == volId) &&
        !folderPathsBySource.containsKey(volId)) {
      return this;
    }
    return CategoryAggregateSnapshot(
      entries: entries
          .where((e) => e.sourceVolId != volId)
          .toList(growable: false),
      folderPathsBySource: {
        for (final e in folderPathsBySource.entries)
          if (e.key != volId) e.key: e.value,
      },
      foldersChecked: foldersChecked,
      finished: finished,
      limitReached: limitReached,
      failedSources: failedSources,
    );
  }

  /// This snapshot without the given files (`volId`, `path`), e.g. once they
  /// were deleted; the folder sets are rebuilt from what remains.
  CategoryAggregateSnapshot withoutPaths(Set<(int, String)> removed) {
    if (removed.isEmpty) return this;
    final kept = entries
        .where((e) => !removed.contains((e.sourceVolId, e.path)))
        .toList(growable: false);
    if (kept.length == entries.length) return this;
    final folders = <int, Set<String>>{};
    for (final entry in kept) {
      var dir = entry.parentPath;
      final set = folders.putIfAbsent(entry.sourceVolId, () => <String>{});
      while (dir.isNotEmpty && set.add(dir)) {
        dir = parentOfPath(dir);
      }
    }
    return CategoryAggregateSnapshot(
      entries: kept,
      folderPathsBySource: folders,
      foldersChecked: foldersChecked,
      finished: finished,
      limitReached: limitReached,
      failedSources: failedSources,
    );
  }
}

/// Scans several storage sources for one category and merges the results.
///
/// Each source is walked by its own [CategoryScanner], all sharing one bound
/// on listings in flight, and the merged snapshot is published as results
/// arrive. A file reachable from two raw-path sources (a storage location
/// inside phone storage) is reported once, under the source listed first.
class CategoryAggregateScanner {
  CategoryAggregateScanner({
    required this.targets,
    required this.matches,
    required this.isHidden,
    required this.showHidden,
    this.onError,
    this.maxConcurrency = categoryScanMaxConcurrency,
    this.maxFolders = categoryScanMaxFolders,
    this.maxResults = categoryScanMaxResults,
  });

  final List<CategoryScanTarget> targets;
  final bool Function(String fileName) matches;
  final bool Function(String name) isHidden;
  final bool showHidden;
  final void Function(CategorySource source, String dirPath, Object error)?
  onError;
  final int maxConcurrency;
  final int maxFolders;
  final int maxResults;

  Future<CategoryAggregateSnapshot> scan({
    required CancellationToken token,
    void Function(CategoryAggregateSnapshot snapshot)? onProgress,
    Duration progressInterval = const Duration(milliseconds: 250),
  }) async {
    final semaphore = BoundedSemaphore(maxConcurrency);
    final latest = <int, CategoryScanSnapshot>{};
    final failed = <int>{};
    // Source order is the order of [targets]; it decides which source keeps a
    // duplicate and keeps the merged list stable between snapshots.
    final order = [for (final t in targets) t.source.volId];
    final wrapped = <int, List<CategoryEntry>>{
      for (final id in order) id: <CategoryEntry>[],
    };
    final byVolId = {for (final t in targets) t.source.volId: t.source};
    // Sources whose list is a stand-in from an earlier scan until their own
    // scan finishes.
    final seeded = <int>{};
    final clock = Stopwatch()..start();
    var lastPublishedMs = 0;

    CategoryAggregateSnapshot merge({required bool finished}) {
      final entries = <CategoryEntry>[];
      final folders = <int, Set<String>>{};
      final seenAbsolute = <String>{};
      var foldersChecked = 0;
      var limitReached = false;
      for (final volId in order) {
        final snap = latest[volId];
        if (snap == null) continue;
        foldersChecked += snap.foldersChecked;
        limitReached = limitReached || snap.limitReached;
        // A source's snapshot only ever grows at the end, so what was wrapped
        // before is still right; wrap just the new tail.
        final cache = wrapped[volId]!;
        for (var i = cache.length; i < snap.entries.length; i++) {
          final raw = snap.entries[i];
          cache.add(
            CategoryEntry(
              name: raw.name,
              sourceVolId: volId,
              path: raw.name,
              isDir: raw.isDir,
              sizeBytes: raw.sizeBytes,
              modifiedSecs: raw.modifiedSecs,
            ),
          );
        }
        final root = byVolId[volId]!.dedupeRoot;
        final keptHere = <CategoryEntry>[];
        for (final entry in cache) {
          if (root != null && !seenAbsolute.add('$root/${entry.path}')) {
            continue;
          }
          keptHere.add(entry);
        }
        entries.addAll(keptHere);
        final set = <String>{};
        for (final entry in keptHere) {
          var dir = entry.parentPath;
          while (dir.isNotEmpty && set.add(dir)) {
            dir = parentOfPath(dir);
          }
        }
        if (set.isNotEmpty) folders[volId] = set;
      }
      return CategoryAggregateSnapshot(
        entries: entries,
        folderPathsBySource: folders,
        foldersChecked: foldersChecked,
        finished: finished,
        limitReached: limitReached,
        failedSources: Set<int>.of(failed),
      );
    }

    void publishIfDue() {
      if (onProgress == null || token.isCancelled) return;
      final now = clock.elapsedMilliseconds;
      if (now - lastPublishedMs < progressInterval.inMilliseconds) return;
      lastPublishedMs = now;
      onProgress(merge(finished: false));
    }

    for (final target in targets) {
      final seed = target.seed;
      if (seed == null || seed.isEmpty) continue;
      final seedFolders = <String>{};
      for (final entry in seed) {
        var dir = parentOfPath(entry.name);
        while (dir.isNotEmpty && seedFolders.add(dir)) {
          dir = parentOfPath(dir);
        }
      }
      latest[target.source.volId] = CategoryScanSnapshot(
        entries: List<RawEntry>.of(seed),
        folderPaths: seedFolders,
        foldersChecked: 0,
        finished: false,
        limitReached: false,
      );
      seeded.add(target.source.volId);
    }
    // Show the stand-ins immediately, before anything has been listed.
    if (seeded.isNotEmpty && onProgress != null) {
      onProgress(merge(finished: false));
    }

    await Future.wait(
      targets.map((target) async {
        final volId = target.source.volId;
        final lookup = target.indexLookup;
        if (lookup != null) {
          CategoryIndexHit? hit;
          try {
            hit = await lookup();
          } catch (_) {
            hit = null;
          }
          if (token.isCancelled) return;
          if (hit != null) {
            final folders = <String>{};
            for (final entry in hit.entries) {
              var dir = parentOfPath(entry.name);
              while (dir.isNotEmpty && folders.add(dir)) {
                dir = parentOfPath(dir);
              }
            }
            latest[volId] = CategoryScanSnapshot(
              entries: List<RawEntry>.of(hit.entries),
              folderPaths: folders,
              foldersChecked: 0,
              finished: true,
              limitReached: hit.limitReached,
            );
            // Replaces the stand-in as a whole; see the walk's result below.
            wrapped[volId]!.clear();
            seeded.remove(volId);
            if (onProgress != null) {
              lastPublishedMs = clock.elapsedMilliseconds;
              onProgress(merge(finished: false));
            }
            return;
          }
        }
        final scanner = CategoryScanner(
          listDirectory: target.listDirectory,
          matches: matches,
          isHidden: isHidden,
          showHidden: showHidden,
          skipDirectory: target.skipDirectory,
          respectNoMedia: target.respectNoMedia,
          onError: onError == null
              ? null
              : (dir, error) => onError!(target.source, dir, error),
          sharedSemaphore: semaphore,
          maxFolders: maxFolders,
          maxResults: maxResults,
        );
        try {
          final result = await scanner.scan(
            token: token,
            progressInterval: progressInterval,
            onProgress: (snapshot) {
              if (seeded.contains(volId)) return;
              latest[volId] = snapshot;
              publishIfDue();
            },
          );
          latest[volId] = result;
          // The result replaces the stand-in as a whole, not by growing it, so
          // what was wrapped from the previous list must not be reused.
          wrapped[volId]!.clear();
        } catch (e) {
          failed.add(volId);
          onError?.call(target.source, '', e);
        }
      }),
    );
    return merge(finished: !token.isCancelled);
  }
}
