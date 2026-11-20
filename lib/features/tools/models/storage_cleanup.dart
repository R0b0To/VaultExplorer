// "What could I reasonably delete?" -- the part of the analyzer that turns a
// picture of usage into a short list of things worth acting on.
//
// These are *suggestions to review*, never automatic: files inside an
// encrypted vault are deleted for good (there is no recycle bin), so nothing
// here is pre-selected or removed without the person looking at it first. The
// rules lean conservative for the same reason -- a missed suggestion costs
// nothing, a wrong one costs a file.
library;

import 'package:vaultexplorer/features/tools/models/storage_tree.dart';

enum CleanupKind {
  /// The biggest files, by a threshold that scales with the volume.
  largeFiles,

  /// Sizeable files nobody has touched in a year.
  staleFiles,

  /// Download leftovers, editor backups and OS thumbnail caches.
  tempFiles,

  /// Folders with nothing in them.
  emptyFolders,
}

class CleanupSuggestion {
  const CleanupSuggestion({
    required this.kind,
    required this.nodes,
    required this.bytes,
  });

  final CleanupKind kind;

  /// Largest first (folders by name). Capped at [CleanupAnalyzer.maxItemsPerKind].
  final List<StorageNode> nodes;

  /// What deleting every one of [nodes] would free.
  final int bytes;

  int get count => nodes.length;
}

abstract final class CleanupAnalyzer {
  static const maxItemsPerKind = 500;

  static const _mib = 1024 * 1024;

  /// A file counts as "large" from this size, or from 2% of the volume if that
  /// is smaller -- but never below [minLarge]. So a 40 MB vault still surfaces
  /// its few big files, and a 2 TB one does not call every 150 MB video large.
  static const minLarge = 5 * _mib;
  static const maxLarge = 100 * _mib;

  /// Stale files smaller than this are not worth the reviewer's attention.
  static const staleMinBytes = _mib;
  static const staleAgeSeconds = 365 * 24 * 60 * 60;

  static int largeFileThreshold(int totalBytes) {
    final scaled = totalBytes ~/ 50;
    if (scaled < minLarge) return minLarge;
    if (scaled > maxLarge) return maxLarge;
    return scaled;
  }

  static const _tempNames = {
    'thumbs.db',
    'ehthumbs.db',
    'desktop.ini',
    '.ds_store',
  };
  static const _tempExt = {
    'tmp',
    'temp',
    'crdownload',
    'part',
    'partial',
    'swp',
    'swo',
  };

  /// Whether [name] looks like leftover cache or scratch data.
  ///
  /// `.nomedia` is deliberately *not* here: it is an empty file that Android
  /// reads to hide a folder from the gallery, so deleting it changes behaviour.
  static bool isTempName(String name) {
    final n = name.toLowerCase();
    if (_tempNames.contains(n)) return true;
    if (n.endsWith('~')) return true;
    if (n.startsWith('.trashed-')) return true; // Android's soft-deleted files
    final dot = n.lastIndexOf('.');
    if (dot > 0 && dot < n.length - 1) {
      return _tempExt.contains(n.substring(dot + 1));
    }
    return false;
  }

  // Folders a filesystem or OS manages. `lost+found` in particular is empty by
  // design on ext2/3/4 and is where fsck puts recovered files.
  static bool _isProtectedFolder(String name) {
    final n = name.toLowerCase();
    return n == 'lost+found' ||
        n == 'system volume information' ||
        n.startsWith(r'$') ||
        n.startsWith('.');
  }

  /// All suggestions for [tree] that have something to show, in the order the
  /// UI lists them. [nowSecs] is injectable for testing.
  static List<CleanupSuggestion> analyze(
    StorageTree tree, {
    required int nowSecs,
  }) {
    final largeMin = largeFileThreshold(tree.totalBytes);
    final staleBefore = nowSecs - staleAgeSeconds;

    final large = <StorageNode>[];
    final stale = <StorageNode>[];
    final temp = <StorageNode>[];
    for (final f in tree.descendants(filesOnly: true)) {
      if (f.sizeBytes >= largeMin) large.add(f);
      if (f.modifiedSecs > 0 &&
          f.modifiedSecs <= staleBefore &&
          f.sizeBytes >= staleMinBytes) {
        stale.add(f);
      }
      if (isTempName(f.name)) temp.add(f);
    }
    final empty = _topEmptyFolders(tree.root);

    final result = <CleanupSuggestion>[];
    void add(CleanupKind kind, List<StorageNode> nodes) {
      if (nodes.isEmpty) return;
      final sorted = kind == CleanupKind.emptyFolders
          ? (nodes..sort((a, b) => a.path.compareTo(b.path)))
          : (nodes..sort(StorageNode.bySizeDesc));
      final shown = sorted.length > maxItemsPerKind
          ? sorted.sublist(0, maxItemsPerKind)
          : sorted;
      var bytes = 0;
      for (final n in shown) {
        bytes += n.sizeBytes;
      }
      result.add(CleanupSuggestion(kind: kind, nodes: shown, bytes: bytes));
    }

    add(CleanupKind.largeFiles, large);
    add(CleanupKind.staleFiles, stale);
    add(CleanupKind.tempFiles, temp);
    add(CleanupKind.emptyFolders, empty);
    return result;
  }

  // The highest empty folders only: if `a/` holds nothing but empty `b/` and
  // `c/`, report `a/` once -- deleting it takes the rest with it.
  static List<StorageNode> _topEmptyFolders(StorageNode root) {
    final found = <StorageNode>[];
    final stack = <StorageNode>[root];
    while (stack.isNotEmpty) {
      final dir = stack.removeLast();
      for (final c in dir.children) {
        if (!c.isDir) continue;
        if (c.isEmptyFolder) {
          if (!_subtreeHasProtectedFolder(c)) found.add(c);
        } else {
          stack.add(c);
        }
      }
    }
    return found;
  }

  static bool _subtreeHasProtectedFolder(StorageNode dir) {
    final stack = <StorageNode>[dir];
    while (stack.isNotEmpty) {
      final d = stack.removeLast();
      if (_isProtectedFolder(d.name)) return true;
      for (final c in d.children) {
        if (c.isDir) stack.add(c);
      }
    }
    return false;
  }
}
