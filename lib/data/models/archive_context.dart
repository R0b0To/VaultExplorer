import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Holds the state for browsing inside an archive file.
///
/// When the user taps a .zip (or other supported archive) in the file
/// browser, its bytes are read into memory and parsed, and an
/// [ArchiveContext] is created. All subsequent directory listing calls
/// within the archive read from [_archive] instead of the native
/// encrypted volume API.
class ArchiveContext {
  /// Path of the archive file inside the encrypted container
  /// (e.g. "Documents/backup.zip"), or the archive's own display name
  /// when it isn't backed by a container at all (decoy-mode browsing of
  /// a real on-device zip).
  final String archivePathInContainer;

  /// Parsed in-memory archive.
  final Archive _archive;

  /// Index in `_pathStack` where the archive root segment was pushed.
  /// When the user navigates back past this index, archive mode exits.
  final int pathStackEntryIndex;

  /// Pre-computed directory tree: maps each directory path (relative to
  /// archive root, with '/' separator) to its immediate children entries
  /// in RawEntry wire format.
  final Map<String, List<String>> _tree;

  ArchiveContext._({
    required this.archivePathInContainer,
    required Archive archive,
    required this.pathStackEntryIndex,
    required Map<String, List<String>> tree,
  })  : _archive = archive,
        _tree = tree;

  /// Parse an archive from in-memory [bytes] and build the virtual
  /// directory tree. [bytes] should already be the archive's full
  /// content -- callers read it from wherever it actually lives (a
  /// mounted vault via chunked reads, or a real on-device file) before
  /// calling this; `ArchiveContext` itself never touches a file path.
  factory ArchiveContext.open({
    required String archivePathInContainer,
    required Uint8List bytes,
    required int pathStackEntryIndex,
  }) {
    final archive = ZipDecoder().decodeBytes(bytes);

    // Build a tree: directory path → list of immediate children in wire format.
    final tree = <String, Set<String>>{};
    // Track which directories we've already synthesized.
    final knownDirs = <String>{''};

    for (final entry in archive.files) {
      // Normalize the entry name (remove trailing '/')
      var entryName = entry.name;
      if (entryName.endsWith('/')) {
        entryName = entryName.substring(0, entryName.length - 1);
      }
      if (entryName.isEmpty) continue;

      // Ensure all ancestor directories exist in the tree
      final parts = entryName.split('/');
      for (int i = 0; i < parts.length - 1; i++) {
        final dirPath = parts.sublist(0, i + 1).join('/');
        final parentPath = i == 0 ? '' : parts.sublist(0, i).join('/');
        if (knownDirs.add(dirPath)) {
          // Synthesize this directory entry in its parent
          final dirName = parts[i];
          final wireEntry = 'D|0|${entry.lastModTime ~/ 1000}|$dirName';
          tree.putIfAbsent(parentPath, () => <String>{}).add(wireEntry);
        }
      }

      // Add this entry to its parent directory
      final parentDir = parts.length > 1
          ? parts.sublist(0, parts.length - 1).join('/')
          : '';
      final baseName = parts.last;

      if (entry.isFile) {
        final wireEntry = 'F|${entry.size}|${entry.lastModTime ~/ 1000}|$baseName';
        tree.putIfAbsent(parentDir, () => <String>{}).add(wireEntry);
      } else {
        // Explicit directory entry
        if (knownDirs.add(entryName)) {
          final wireEntry = 'D|0|${entry.lastModTime ~/ 1000}|$baseName';
          tree.putIfAbsent(parentDir, () => <String>{}).add(wireEntry);
        }
      }
    }

    // Convert sets to lists for stable ordering
    final treeMap = tree.map((k, v) => MapEntry(k, v.toList()));

    return ArchiveContext._(
      archivePathInContainer: archivePathInContainer,
      archive: archive,
      pathStackEntryIndex: pathStackEntryIndex,
      tree: treeMap,
    );
  }

  /// List immediate children of [subPath] within the archive.
  /// Returns entries in RawEntry wire format.
  List<String> listDirectory(String subPath) {
    return _tree[subPath] ?? [];
  }

  /// True if [entryPath] is safe to use as a relative output path (no
  /// `..` traversal segments, not absolute). Archive entry names are
  /// attacker-controlled data -- a "zip-slip" entry like
  /// `../../etc/whatever` must never be honored when a caller later
  /// joins the name onto a real destination directory (see
  /// decoy_archive_extract.dart) or a vault path.
  static bool _isSafeRelativePath(String entryPath) {
    if (p.isAbsolute(entryPath)) return false;
    final normalized = p.normalize(entryPath);
    if (normalized == '..' || normalized.startsWith('../')) return false;
    return true;
  }

  /// Returns the raw bytes of a single file entry from the archive, or
  /// null if the entry wasn't found (or its path fails the traversal
  /// check above). The bytes already live in [_archive] in memory --
  /// this just hands the caller a reference/copy, it never touches disk.
  Future<Uint8List?> extractEntry(String entryPath) async {
    if (!_isSafeRelativePath(entryPath)) return null;
    for (final file in _archive.files) {
      var name = file.name;
      if (name.endsWith('/')) name = name.substring(0, name.length - 1);
      if (name == entryPath && file.isFile) {
        return _asUint8List(file.content);
      }
    }
    return null;
  }

  /// Returns the bytes of every file entry under [subPath] (or all, if
  /// empty), keyed by their path relative to the archive root. Entirely
  /// in memory -- see [extractEntry].
  Future<Map<String, Uint8List>> extractAll({String subPath = ''}) async {
    final results = <String, Uint8List>{};

    for (final file in _archive.files) {
      if (!file.isFile) continue;
      var name = file.name;
      if (name.endsWith('/')) name = name.substring(0, name.length - 1);
      if (!_isSafeRelativePath(name)) continue;

      // Filter by subPath if specified
      if (subPath.isNotEmpty && !name.startsWith('$subPath/') && name != subPath) {
        continue;
      }

      results[name] = _asUint8List(file.content);
    }

    return results;
  }

  static Uint8List _asUint8List(Object? content) {
    if (content is Uint8List) return content;
    if (content is List<int>) return Uint8List.fromList(content);
    return Uint8List(0);
  }

  /// Get all directory paths that exist under [subPath].
  List<String> getSubDirectories(String subPath) {
    return _tree.keys
        .where((k) => k.isNotEmpty && (subPath.isEmpty ? true : k.startsWith('$subPath/')))
        .toList();
  }

  /// No-op, kept for API stability. Earlier versions of [ArchiveContext]
  /// staged the archive and each extracted entry as plaintext files on
  /// host disk and used [dispose] to delete them; now that everything is
  /// in-memory there's nothing left to clean up. Existing call sites can
  /// keep calling this unconditionally.
  void dispose() {}
}
