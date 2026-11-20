// Walks a volume's directory listings into a [StorageTree].
//
// The listing function is injected, so this knows nothing about platform
// channels, vaults or SAF -- the analyzer passes `fileIoApi.listDirectory`, the
// tests pass a map.
//
// The old analyzer's walk had three quiet failure modes that this one reports
// instead, because a storage tool that shows confident-looking numbers it did
// not fully earn is worse than one that says "incomplete":
//
//  * a folder that failed to list was skipped without a trace;
//  * a folder the engine listed only partly (the `System:TRUNCATED` sentinel)
//    had its missing children ignored;
//  * a malformed listing line threw out of the whole scan, leaving the screen
//    spinning forever.
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/tools/models/storage_tree.dart';

/// Lists one folder: raw wire strings (see [RawEntry]), or null if it cannot be
/// read. May throw.
typedef StorageListDirectory = Future<List<String>?> Function(String dirPath);

/// A running tally, reported after every folder.
class StorageScanProgress {
  const StorageScanProgress({
    required this.files,
    required this.dirs,
    required this.bytes,
    required this.path,
  });

  final int files;
  final int dirs;
  final int bytes;

  /// The folder most recently read.
  final String path;
}

/// A freshly scanned subtree plus how trustworthy it is.
class StorageScanOutcome {
  const StorageScanOutcome({
    required this.node,
    required this.truncated,
    required this.unreadableDirs,
    required this.incompleteDirs,
  });

  final StorageNode node;
  final bool truncated;
  final int unreadableDirs;
  final int incompleteDirs;
}

class StorageScanner {
  StorageScanner({
    required this.listDirectory,
    this.maxEntries = defaultMaxEntries,
    this.maxDepth = defaultMaxDepth,
    this.onProgress,
    this.isCancelled,
  });

  /// Files and folders together. Large enough for a very full vault, small
  /// enough that the tree stays comfortably in memory.
  static const defaultMaxEntries = 250000;

  /// Deeper than any sane folder structure; a guard, not a working limit.
  static const defaultMaxDepth = 32;

  final StorageListDirectory listDirectory;
  final int maxEntries;
  final int maxDepth;
  final void Function(StorageScanProgress progress)? onProgress;

  /// Polled between folders; return true to stop. A stopped scan returns what
  /// it had so far, flagged as truncated.
  final bool Function()? isCancelled;

  /// Scans the whole volume.
  Future<StorageTree> scan() async {
    final outcome = await scanFolder(name: '', path: '');
    return StorageTree(
      root: outcome.node,
      truncated: outcome.truncated,
      unreadableDirs: outcome.unreadableDirs,
      incompleteDirs: outcome.incompleteDirs,
    );
  }

  /// Scans the folder at [path] into a new, detached node. The caller decides
  /// where it goes (see [StorageTree.replace]).
  Future<StorageScanOutcome> scanFolder({
    required String name,
    required String path,
    int modifiedSecs = 0,
  }) async {
    final run = _Run();
    final node = StorageNode.dir(
      name: name,
      path: path,
      modifiedSecs: modifiedSecs,
    );
    await _walk(node, 0, run);
    node.recomputeTotals();
    return StorageScanOutcome(
      node: node,
      truncated: run.truncated,
      unreadableDirs: run.unreadable,
      incompleteDirs: run.incomplete,
    );
  }

  Future<void> _walk(StorageNode dir, int depth, _Run run) async {
    if (run.truncated) return;
    if (isCancelled?.call() ?? false) {
      run.truncated = true;
      return;
    }

    List<RawEntry> entries;
    try {
      final raw = await listDirectory(dir.path);
      if (raw == null) {
        run.unreadable++;
        return;
      }
      if (raw.any((line) => line.startsWith('System:'))) run.incomplete++;
      entries = RawEntry.parseAll(raw);
    } catch (_) {
      // One unreadable or malformed folder must not sink the whole scan; it is
      // counted and surfaced as "results may be incomplete" instead.
      run.unreadable++;
      return;
    }

    run.dirs++;
    final subdirs = <StorageNode>[];
    for (final e in entries) {
      if (run.entries >= maxEntries) {
        run.truncated = true;
        break;
      }
      run.entries++;
      final childPath = dir.path.isEmpty ? e.name : '${dir.path}/${e.name}';
      if (e.isDir) {
        final child = StorageNode.dir(
          name: e.name,
          path: childPath,
          modifiedSecs: e.modifiedSecs,
        );
        dir.addChild(child);
        subdirs.add(child);
      } else {
        dir.addChild(
          StorageNode.file(
            name: e.name,
            path: childPath,
            sizeBytes: e.sizeBytes,
            modifiedSecs: e.modifiedSecs,
          ),
        );
        run.files++;
        run.bytes += e.sizeBytes;
      }
    }

    onProgress?.call(
      StorageScanProgress(
        files: run.files,
        dirs: run.dirs,
        bytes: run.bytes,
        path: dir.path,
      ),
    );

    for (final child in subdirs) {
      if (run.truncated) break;
      if (depth + 1 > maxDepth) {
        // Content below this point is not counted, so say so.
        run.truncated = true;
        break;
      }
      await _walk(child, depth + 1, run);
    }
  }
}

class _Run {
  int entries = 0;
  int files = 0;
  int dirs = 0;
  int bytes = 0;
  int unreadable = 0;
  int incomplete = 0;
  bool truncated = false;
}
