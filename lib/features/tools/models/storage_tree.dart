// The Storage Analyzer's data model: a tree of folders and files whose folder
// nodes carry exact recursive totals.
//
// This used to be a flat list of the 5,000 first files found, which is enough
// for a "heaviest files" list but cannot answer "which *folder* is eating my
// space?", cannot be drilled into, and cannot be updated after a delete
// without walking the whole vault again. A tree can do all three.
//
// Deliberately free of Flutter imports so the logic can be unit-tested (and
// reasoned about) without a widget tree. Sizes are bytes of file *content*, as
// reported by the directory listing -- not on-disk allocation.
library;

/// File-type buckets used for colouring and the by-type breakdown.
///
/// Plain string keys (rather than an enum) because they are also the keys of
/// [StorageCategoryBreakdown.category], which the UI maps to localised labels.
abstract final class StorageCategory {
  static const images = 'images';
  static const videos = 'videos';
  static const audio = 'audio';
  static const documents = 'documents';
  static const archives = 'archives';
  static const other = 'other';

  /// Palette / legend order.
  static const all = <String>[
    images,
    videos,
    audio,
    documents,
    archives,
    other,
  ];

  static const _imageExt = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'avif', //
    'svg', 'tif', 'tiff', 'ico',
  };
  static const _videoExt = {
    'mp4',
    'mov',
    'mkv',
    'avi',
    'webm',
    'm4v',
    '3gp',
    'wmv',
    'flv',
    'mpg',
    'mpeg',
  };
  static const _audioExt = {
    'mp3',
    'wav',
    'flac',
    'aac',
    'ogg',
    'm4a',
    'wma',
    'opus',
    'amr',
  };
  static const _documentExt = {
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'txt',
    'md',
    'odt',
    'ods',
    'odp',
    'csv',
    'rtf',
    'epub',
  };
  static const _archiveExt = {
    'zip',
    'rar',
    '7z',
    'tar',
    'gz',
    'bz2',
    'bz',
    'xz',
    'tgz',
    'tbz',
    'tbz2',
    'txz',
    'tzst',
    'zst',
    'lzma',
    'tlz',
    'lz',
    'cab',
    'iso',
    'z',
  };

  /// The bucket for a file called [fileName], from its extension alone.
  static String of(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return other;
    final ext = fileName.substring(dot + 1).toLowerCase();
    if (_imageExt.contains(ext)) return images;
    if (_videoExt.contains(ext)) return videos;
    if (_audioExt.contains(ext)) return audio;
    if (_documentExt.contains(ext)) return documents;
    if (_archiveExt.contains(ext)) return archives;
    return other;
  }
}

/// One folder or file in the analysed volume.
///
/// Paths are relative to the volume root and `/`-separated; the root's path is
/// the empty string. That is the same convention every file-I/O API in the app
/// uses, so [path] can be handed straight to them.
class StorageNode {
  StorageNode.file({
    required this.name,
    required this.path,
    required this.sizeBytes,
    this.modifiedSecs = 0,
  }) : isDir = false,
       fileCount = 1,
       category = StorageCategory.of(name),
       children = const <StorageNode>[];

  StorageNode.dir({
    required this.name,
    required this.path,
    this.modifiedSecs = 0,
  }) : isDir = true,
       sizeBytes = 0,
       fileCount = 0,
       category = '',
       children = <StorageNode>[];

  final String name;
  final String path;
  final bool isDir;

  /// A [StorageCategory] key for files; empty for folders.
  final String category;

  StorageNode? parent;

  /// A file's own size, or the sum of everything beneath a folder.
  int sizeBytes;

  /// 1 for a file; the number of files (not folders) beneath a folder.
  int fileCount;

  /// Unix seconds, 0 when unknown. For a folder: the newest file beneath it
  /// (falling back to the folder's own timestamp when it holds no dated file),
  /// because a folder's own timestamp only moves when its direct children are
  /// added or removed, which says little about when its contents last changed.
  int modifiedSecs;

  /// Folder contents, largest first once [recomputeTotals] has run.
  /// Always empty (and unmodifiable) for a file.
  final List<StorageNode> children;

  /// A folder with no file anywhere beneath it. It may still contain other
  /// (equally empty) folders.
  bool get isEmptyFolder => isDir && fileCount == 0;

  int get depth {
    var d = 0;
    for (var n = parent; n != null; n = n.parent) {
      d++;
    }
    return d;
  }

  /// Path of the folder containing this node ('' at the root level).
  String get parentPath => parent?.path ?? '';

  bool isAncestorOf(StorageNode other) {
    for (var n = other.parent; n != null; n = n.parent) {
      if (identical(n, this)) return true;
    }
    return false;
  }

  void addChild(StorageNode child) {
    assert(isDir, 'only folders can have children');
    child.parent = this;
    children.add(child);
  }

  /// Largest first; ties broken by name so the order is stable from run to run.
  static int bySizeDesc(StorageNode a, StorageNode b) {
    final c = b.sizeBytes.compareTo(a.sizeBytes);
    if (c != 0) return c;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  /// Re-derives size, file count and timestamp bottom-up and sorts every
  /// folder's children largest-first. Call once after building a subtree.
  void recomputeTotals() {
    if (!isDir) return;
    var size = 0;
    var count = 0;
    var latest = 0;
    for (final c in children) {
      if (c.isDir) c.recomputeTotals();
      size += c.sizeBytes;
      count += c.fileCount;
      if (c.modifiedSecs > latest) latest = c.modifiedSecs;
    }
    children.sort(bySizeDesc);
    sizeBytes = size;
    fileCount = count;
    if (latest > 0) modifiedSecs = latest;
  }

  @override
  String toString() =>
      'StorageNode(${isDir ? 'dir' : 'file'} "$path" $sizeBytes B, $fileCount files)';
}

/// How a folder's contents are ordered in the list view.
enum StorageSort {
  /// Biggest first (the default).
  size,

  /// Folders first, then A-Z.
  name,

  /// Most files first.
  files,

  /// Most recently modified first; undated items last.
  date;

  /// Orders two nodes of the same folder.
  int compare(StorageNode a, StorageNode b) {
    switch (this) {
      case StorageSort.size:
        return StorageNode.bySizeDesc(a, b);
      case StorageSort.name:
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return c != 0 ? c : a.name.compareTo(b.name);
      case StorageSort.files:
        final c = b.fileCount.compareTo(a.fileCount);
        return c != 0 ? c : StorageNode.bySizeDesc(a, b);
      case StorageSort.date:
        final c = b.modifiedSecs.compareTo(a.modifiedSecs);
        return c != 0 ? c : StorageNode.bySizeDesc(a, b);
    }
  }
}

/// Bytes and file count for one [StorageCategory].
class StorageCategoryTotal {
  int bytes = 0;
  int count = 0;
}

/// What a set of selected paths amounts to once nested picks are collapsed.
class StorageSelection {
  const StorageSelection({
    required this.nodes,
    required this.bytes,
    required this.files,
    required this.folders,
  });

  static const empty = StorageSelection(
    nodes: <StorageNode>[],
    bytes: 0,
    files: 0,
    folders: 0,
  );

  /// The top-most selected nodes. A selected folder swallows any selected
  /// descendant, so nothing is counted -- or deleted -- twice.
  final List<StorageNode> nodes;

  /// Bytes that removing [nodes] would free.
  final int bytes;

  /// Files that would be removed, including those inside selected folders.
  final int files;

  /// How many of [nodes] are folders.
  final int folders;

  bool get isEmpty => nodes.isEmpty;
  bool get hasFolder => folders > 0;
}

/// A scanned volume.
class StorageTree {
  StorageTree({
    required this.root,
    this.truncated = false,
    this.unreadableDirs = 0,
    this.incompleteDirs = 0,
  });

  final StorageNode root;

  /// The walk stopped at its entry or depth limit, so totals are lower bounds.
  bool truncated;

  /// Folders whose listing failed outright.
  int unreadableDirs;

  /// Folders the engine listed only partly (too many children to return).
  int incompleteDirs;

  int get totalBytes => root.sizeBytes;
  int get fileCount => root.fileCount;

  /// True when every figure in the tree is exact.
  bool get isComplete =>
      !truncated && unreadableDirs == 0 && incompleteDirs == 0;

  /// The node at [path] ('' is the root), or null if there is none.
  StorageNode? find(String path) {
    if (path.isEmpty) return root;
    var node = root;
    for (final segment in path.split('/')) {
      StorageNode? next;
      for (final c in node.children) {
        if (c.name == segment) {
          next = c;
          break;
        }
      }
      if (next == null) return null;
      node = next;
    }
    return node;
  }

  /// Every node beneath the root (the root itself excluded), in no particular
  /// order. Iterative, so a deep tree cannot overflow the stack.
  Iterable<StorageNode> descendants({bool filesOnly = false}) sync* {
    final stack = <StorageNode>[root];
    while (stack.isNotEmpty) {
      final n = stack.removeLast();
      if (n.isDir) {
        stack.addAll(n.children);
        if (!identical(n, root) && !filesOnly) yield n;
      } else {
        yield n;
      }
    }
  }

  /// The [limit] biggest files (optionally only those passing [where]),
  /// largest first. Keeps a bounded sorted shortlist instead of sorting every
  /// file, so it stays cheap on a six-figure tree.
  List<StorageNode> largestFiles(
    int limit, {
    bool Function(StorageNode file)? where,
  }) {
    if (limit <= 0) return <StorageNode>[];
    final top = <StorageNode>[];
    for (final f in descendants(filesOnly: true)) {
      if (where != null && !where(f)) continue;
      if (top.length >= limit && f.sizeBytes <= top.last.sizeBytes) continue;
      var lo = 0;
      var hi = top.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (top[mid].sizeBytes >= f.sizeBytes) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      top.insert(lo, f);
      if (top.length > limit) top.removeLast();
    }
    return top;
  }

  /// Bytes and file count per [StorageCategory] across the whole volume.
  Map<String, StorageCategoryTotal> categoryTotals() => categoryTotalsOf(root);

  /// Same, restricted to [node] and everything beneath it.
  static Map<String, StorageCategoryTotal> categoryTotalsOf(StorageNode node) {
    final totals = <String, StorageCategoryTotal>{};
    final stack = <StorageNode>[node];
    while (stack.isNotEmpty) {
      final n = stack.removeLast();
      if (n.isDir) {
        stack.addAll(n.children);
      } else {
        final t = totals.putIfAbsent(n.category, StorageCategoryTotal.new);
        t.bytes += n.sizeBytes;
        t.count += 1;
      }
    }
    return totals;
  }

  /// Takes [node] out of the tree and subtracts its totals from every
  /// ancestor. Returns false for the root or a node that is already detached.
  bool remove(StorageNode node) {
    final p = node.parent;
    if (p == null) return false;
    final idx = p.children.indexOf(node);
    if (idx < 0) {
      node.parent = null;
      return false;
    }
    p.children.removeAt(idx);
    node.parent = null;
    _propagate(p, -node.sizeBytes, -node.fileCount);
    return true;
  }

  /// Swaps [old] for a freshly scanned [fresh] of the same name, re-totalling
  /// every ancestor by the difference. Returns false if [old] is not in the
  /// tree (or is the root).
  bool replace(StorageNode old, StorageNode fresh) {
    final p = old.parent;
    if (p == null) return false;
    final idx = p.children.indexOf(old);
    if (idx < 0) return false;
    p.children[idx] = fresh;
    fresh.parent = p;
    old.parent = null;
    _propagate(
      p,
      fresh.sizeBytes - old.sizeBytes,
      fresh.fileCount - old.fileCount,
    );
    return true;
  }

  // Applies a size/count delta to [start] and every ancestor, then restores the
  // invariants that depend on it: each folder's children stay largest-first
  // (a changed child may now rank differently) and each folder's timestamp
  // follows its newest remaining file.
  void _propagate(StorageNode start, int dSize, int dCount) {
    for (StorageNode? n = start; n != null; n = n.parent) {
      n.sizeBytes += dSize;
      n.fileCount += dCount;
      n.children.sort(StorageNode.bySizeDesc);
      var latest = 0;
      for (final c in n.children) {
        if (c.modifiedSecs > latest) latest = c.modifiedSecs;
      }
      if (latest > 0) n.modifiedSecs = latest;
    }
  }

  /// Collapses [paths] into the nodes that would really be acted on: unknown
  /// paths and the root are ignored, and any path with a selected ancestor is
  /// dropped (selecting a folder already covers what is inside it).
  StorageSelection resolveSelection(Iterable<String> paths) {
    final wanted = paths.toSet();
    final nodes = <StorageNode>[];
    for (final path in wanted) {
      final node = find(path);
      if (node == null || identical(node, root)) continue;
      var covered = false;
      for (var a = node.parent; a != null; a = a.parent) {
        if (!identical(a, root) && wanted.contains(a.path)) {
          covered = true;
          break;
        }
      }
      if (!covered) nodes.add(node);
    }
    if (nodes.isEmpty) return StorageSelection.empty;
    nodes.sort((a, b) => a.path.compareTo(b.path));
    var bytes = 0;
    var files = 0;
    var folders = 0;
    for (final n in nodes) {
      bytes += n.sizeBytes;
      files += n.fileCount;
      if (n.isDir) folders++;
    }
    return StorageSelection(
      nodes: nodes,
      bytes: bytes,
      files: files,
      folders: folders,
    );
  }
}
