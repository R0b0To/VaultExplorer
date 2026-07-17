import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Holds the state for browsing inside an archive file.
///
/// When the user taps a .zip (or other supported archive) in the file
/// browser, the archive is extracted to a temp path, parsed in memory,
/// and an [ArchiveContext] is created. All subsequent directory listing
/// calls within the archive read from [_archive] instead of the native
/// encrypted volume API.
class ArchiveContext {
  /// Path of the archive file inside the encrypted container
  /// (e.g. "Documents/backup.zip").
  final String archivePathInContainer;

  /// Local temp file path where the archive was extracted from the container.
  final String tempFilePath;

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
    required this.tempFilePath,
    required Archive archive,
    required this.pathStackEntryIndex,
    required Map<String, List<String>> tree,
  })  : _archive = archive,
        _tree = tree;

  /// Parse an archive from a local [tempFilePath] and build the virtual
  /// directory tree.
  factory ArchiveContext.open({
    required String archivePathInContainer,
    required String tempFilePath,
    required int pathStackEntryIndex,
  }) {
    final bytes = File(tempFilePath).readAsBytesSync();
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
          final wireEntry = '[DIR] $dirName|0|${entry.lastModTime ~/ 1000}';
          tree.putIfAbsent(parentPath, () => <String>{}).add(wireEntry);
        }
      }

      // Add this entry to its parent directory
      final parentDir = parts.length > 1
          ? parts.sublist(0, parts.length - 1).join('/')
          : '';
      final baseName = parts.last;

      if (entry.isFile) {
        final wireEntry = '$baseName|${entry.size}|${entry.lastModTime ~/ 1000}';
        tree.putIfAbsent(parentDir, () => <String>{}).add(wireEntry);
      } else {
        // Explicit directory entry
        if (knownDirs.add(entryName)) {
          final wireEntry = '[DIR] $baseName|0|${entry.lastModTime ~/ 1000}';
          tree.putIfAbsent(parentDir, () => <String>{}).add(wireEntry);
        }
      }
    }

    // Convert sets to lists for stable ordering
    final treeMap = tree.map((k, v) => MapEntry(k, v.toList()));

    return ArchiveContext._(
      archivePathInContainer: archivePathInContainer,
      tempFilePath: tempFilePath,
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

  /// Extract a single file entry from the archive to a temp file.
  /// Returns the path to the temp file, or null if the entry was not found.
  Future<String?> extractEntry(String entryPath) async {
    for (final file in _archive.files) {
      var name = file.name;
      if (name.endsWith('/')) name = name.substring(0, name.length - 1);
      if (name == entryPath && file.isFile) {
        final tempDir = await Directory.systemTemp.createTemp('archive_extract_');
        final baseName = p.basename(entryPath);
        final outPath = p.join(tempDir.path, baseName);
        final outFile = File(outPath);
        await outFile.writeAsBytes(file.content as List<int>);
        return outPath;
      }
    }
    return null;
  }

  /// Extract all files under [subPath] (or all if empty) to a temp directory.
  /// Returns a map of { archiveEntryPath → tempFilePath }.
  Future<Map<String, String>> extractAll({String subPath = ''}) async {
    final tempDir = await Directory.systemTemp.createTemp('archive_extract_all_');
    final results = <String, String>{};

    for (final file in _archive.files) {
      if (!file.isFile) continue;
      var name = file.name;
      if (name.endsWith('/')) name = name.substring(0, name.length - 1);

      // Filter by subPath if specified
      if (subPath.isNotEmpty && !name.startsWith('$subPath/') && name != subPath) {
        continue;
      }

      final outPath = p.join(tempDir.path, name);
      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(file.content as List<int>);
      results[name] = outPath;
    }

    return results;
  }

  /// Get all directory paths that exist under [subPath].
  List<String> getSubDirectories(String subPath) {
    return _tree.keys
        .where((k) => k.isNotEmpty && (subPath.isEmpty ? true : k.startsWith('$subPath/')))
        .toList();
  }

  /// Clean up the temp file extracted from the container.
  void dispose() {
    try {
      final file = File(tempFilePath);
      if (file.existsSync()) file.deleteSync();
      // Also clean up the parent temp directory if it's empty
      final parent = file.parent;
      if (parent.existsSync() && parent.listSync().isEmpty) {
        parent.deleteSync();
      }
    } catch (_) {
      // Best effort cleanup
    }
  }
}
