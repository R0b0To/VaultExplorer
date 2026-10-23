// The bookmarks and pins of one container, as plain immutable data.
//
// Deliberately free of Flutter/Riverpod imports: everything here is a pure
// function of its inputs, so the rules (dedupe, delete cleanup, rename
// remapping, ordering) are unit-testable without an app, and the same value
// can be handed to any storage backend (see VaultMarksStore).
//
// Paths follow the file browser's convention: container-relative, '/'
// separated, no leading slash ('Photos/2024/a.jpg'). The container root is ''
// and cannot be bookmarked.

/// A bookmarked file or folder.
///
/// The kind is stored with the path. It used to be guessed from the name
/// ("no dot means folder"), which misclassifies `Makefile`, `README`, or a
/// folder called `v1.2`. The directory listing already knows the real type, so
/// whoever creates a bookmark records it.
class VaultBookmark {
  final String path;
  final bool isDir;

  const VaultBookmark(this.path, {required this.isDir});

  /// Last path segment (what the bar and drawer show).
  String get name {
    final trimmed = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    final i = trimmed.lastIndexOf('/');
    return i < 0 ? trimmed : trimmed.substring(i + 1);
  }

  /// Folder that contains this entry ('' for the container root).
  String get parentPath {
    final trimmed = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    final i = trimmed.lastIndexOf('/');
    return i < 0 ? '' : trimmed.substring(0, i);
  }

  /// Where to *land* when opening this bookmark: the folder itself, or the
  /// folder that holds the file.
  String get containingFolder => isDir ? path : parentPath;

  VaultBookmark withPath(String newPath) =>
      VaultBookmark(newPath, isDir: isDir);

  Map<String, Object?> toJson() => {'path': path, 'dir': isDir};

  /// Returns null for anything that is not a well-formed entry, so one bad
  /// element cannot throw away the rest of the list.
  static VaultBookmark? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    final dir = raw['dir'];
    if (path is! String || path.isEmpty || dir is! bool) return null;
    return VaultBookmark(path, isDir: dir);
  }

  @override
  bool operator ==(Object other) =>
      other is VaultBookmark && other.path == path && other.isDir == isDir;

  @override
  int get hashCode => Object.hash(path, isDir);

  @override
  String toString() => 'VaultBookmark($path, isDir: $isDir)';
}

/// Everything a container remembers about which entries matter to the person:
/// ordered bookmarks and unordered pins.
class VaultMarks {
  /// Bumped only if the file layout changes incompatibly.
  static const int schemaVersion = 1;

  /// In display order.
  final List<VaultBookmark> bookmarks;
  final Set<String> pinnedPaths;

  /// [bookmarks]' paths, computed once so per-tile membership checks in the
  /// file list don't rebuild a list for every row.
  final List<String> bookmarkPaths;
  final Set<String> _bookmarkPathSet;

  VaultMarks({
    Iterable<VaultBookmark> bookmarks = const [],
    Iterable<String> pinnedPaths = const {},
  }) : this._(
         List.unmodifiable(bookmarks),
         Set.unmodifiable(pinnedPaths),
       );

  VaultMarks._(this.bookmarks, this.pinnedPaths)
    : bookmarkPaths = List.unmodifiable([for (final b in bookmarks) b.path]),
      _bookmarkPathSet = {for (final b in bookmarks) b.path};

  static final VaultMarks empty = VaultMarks();

  bool get isEmpty => bookmarks.isEmpty && pinnedPaths.isEmpty;

  bool isBookmarked(String path) => _bookmarkPathSet.contains(path);

  // ── Changes ──────────────────────────────────────────────────────────────
  // Every method returns a new value; `identical(a, b)` is not relied on, but
  // an unchanged result compares == to the receiver.

  /// Appends the given bookmarks, skipping paths that are already bookmarked.
  VaultMarks withBookmarks(Iterable<VaultBookmark> added) {
    final next = [...bookmarks];
    final seen = {..._bookmarkPathSet};
    for (final b in added) {
      if (b.path.isEmpty || !seen.add(b.path)) continue;
      next.add(b);
    }
    return VaultMarks(bookmarks: next, pinnedPaths: pinnedPaths);
  }

  VaultMarks withoutBookmarks(Iterable<String> paths) {
    final gone = paths.toSet();
    return VaultMarks(
      bookmarks: bookmarks.where((b) => !gone.contains(b.path)),
      pinnedPaths: pinnedPaths,
    );
  }

  VaultMarks withPinned(Iterable<String> paths) =>
      VaultMarks(bookmarks: bookmarks, pinnedPaths: {...pinnedPaths, ...paths});

  VaultMarks withoutPinned(Iterable<String> paths) {
    final gone = paths.toSet();
    return VaultMarks(
      bookmarks: bookmarks,
      pinnedPaths: pinnedPaths.where((p) => !gone.contains(p)),
    );
  }

  /// Moves one bookmark. Uses the same index convention as Flutter's
  /// `ReorderableListView.onReorderItem`: [newIndex] is the position *after*
  /// the item has been taken out of the list.
  VaultMarks reordered(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= bookmarks.length) return this;
    final next = [...bookmarks];
    final moved = next.removeAt(oldIndex);
    final target = newIndex.clamp(0, next.length);
    next.insert(target, moved);
    return VaultMarks(bookmarks: next, pinnedPaths: pinnedPaths);
  }

  /// Drops every mark on a deleted entry *and everything beneath it*: deleting
  /// a folder also deletes the files inside, so bookmarks on those are dead
  /// too.
  VaultMarks withoutDeleted(Iterable<String> deletedPaths) {
    final deleted = deletedPaths.where((p) => p.isNotEmpty).toList();
    if (deleted.isEmpty) return this;
    bool dead(String p) => deleted.any((d) => p == d || p.startsWith('$d/'));
    return VaultMarks(
      bookmarks: bookmarks.where((b) => !dead(b.path)),
      pinnedPaths: pinnedPaths.where((p) => !dead(p)),
    );
  }

  /// Follows renames/moves. [moves] maps an old path to its new path; a
  /// mark on the entry itself or anywhere beneath it is rewritten. All moves
  /// apply to the *original* paths at once, and when several match, the most
  /// specific (longest) old path wins, so a batch that swaps two names, or
  /// renames a folder and a file inside it, doesn't chain.
  VaultMarks withMoves(Map<String, String> moves) {
    if (moves.isEmpty) return this;
    final olds = moves.keys.where((k) => k.isNotEmpty).toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    String remap(String path) {
      for (final old in olds) {
        if (path == old) return moves[old]!;
        if (path.startsWith('$old/')) {
          return moves[old]! + path.substring(old.length);
        }
      }
      return path;
    }

    final seen = <String>{};
    final nextBookmarks = <VaultBookmark>[];
    for (final b in bookmarks) {
      final path = remap(b.path);
      if (seen.add(path)) nextBookmarks.add(b.withPath(path));
    }
    return VaultMarks(
      bookmarks: nextBookmarks,
      pinnedPaths: pinnedPaths.map(remap),
    );
  }

  // ── Serialization ────────────────────────────────────────────────────────

  Map<String, Object?> toJson() => {
    'version': schemaVersion,
    'bookmarks': [for (final b in bookmarks) b.toJson()],
    'pinned': pinnedPaths.toList()..sort(),
  };

  /// Lenient about content (malformed entries are skipped), strict about
  /// shape: a root that is not an object is a [FormatException], so callers
  /// can tell "unreadable" from "empty" and don't overwrite a file they merely
  /// failed to understand.
  factory VaultMarks.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('marks: not a JSON object');
    }
    final rawBookmarks = json['bookmarks'];
    final rawPinned = json['pinned'];
    final seen = <String>{};
    return VaultMarks(
      bookmarks: [
        if (rawBookmarks is List)
          for (final raw in rawBookmarks)
            if (VaultBookmark.tryFromJson(raw) case final b?)
              if (seen.add(b.path)) b,
      ],
      pinnedPaths: [
        if (rawPinned is List)
          for (final p in rawPinned)
            if (p is String && p.isNotEmpty) p,
      ],
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! VaultMarks) return false;
    if (bookmarks.length != other.bookmarks.length ||
        pinnedPaths.length != other.pinnedPaths.length) {
      return false;
    }
    for (var i = 0; i < bookmarks.length; i++) {
      if (bookmarks[i] != other.bookmarks[i]) return false;
    }
    return pinnedPaths.containsAll(other.pinnedPaths);
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(bookmarks), Object.hashAllUnordered(pinnedPaths));

  @override
  String toString() =>
      'VaultMarks(bookmarks: $bookmarks, pinned: ${pinnedPaths.length})';
}
