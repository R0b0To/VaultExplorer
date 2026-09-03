import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/api/vault_archive_api.dart';
import 'package:vaultexplorer/data/models/archive_models.dart';

/// Holds the state for browsing inside an archive file using native indexing.
///
/// Archive contents are indexed on the native C++ layer without decompressing
/// all file payloads into memory. Directory browsing queries the metadata-only
/// virtual directory tree, and individual files are extracted on-demand.
class ArchiveContext {
  /// Path of the archive file inside the encrypted container
  /// (e.g. "Documents/backup.zip"), or the archive's own display name
  /// when it isn't backed by a container at all (decoy-mode browsing of
  /// a real on-device zip).
  final String archivePathInContainer;

  /// Index in `_pathStack` where the archive root segment was pushed.
  /// When the user navigates back past this index, archive mode exits.
  final int pathStackEntryIndex;

  /// Native scan result containing metadata for all entries.
  final ArchiveIndexResult indexResult;

  /// Optional API client to extract entries on-demand.
  final VaultArchiveApi? _api;

  /// Container URI if this archive lives in an encrypted vault.
  final String? vaultFilePath;

  /// Virtual path inside the container if this archive lives in an encrypted vault.
  final String? vaultPath;

  /// Local path or SAF URI if this is an external/local archive.
  final String? localPathOrUri;

  /// Passphrase used to scan / extract entries, if password-protected.
  final String? passphrase;

  /// Pre-computed directory tree: maps each directory path (relative to
  /// archive root, with '/' separator) to its immediate children entries
  /// in RawEntry wire format.
  final Map<String, List<String>> _tree;

  /// Fast lookup from normalized relative path to entry metadata.
  final Map<String, ArchiveEntryInfo> _entryMap;

  ArchiveContext._({
    required this.archivePathInContainer,
    required this.pathStackEntryIndex,
    required this.indexResult,
    VaultArchiveApi? api,
    this.vaultFilePath,
    this.vaultPath,
    this.localPathOrUri,
    this.passphrase,
    required Map<String, List<String>> tree,
    required Map<String, ArchiveEntryInfo> entryMap,
  })  : _api = api,
        _tree = tree,
        _entryMap = entryMap;

  /// Constructs an [ArchiveContext] from a native [ArchiveIndexResult].
  factory ArchiveContext.fromScanResult({
    required String archivePathInContainer,
    required ArchiveIndexResult indexResult,
    required int pathStackEntryIndex,
    VaultArchiveApi? api,
    String? vaultFilePath,
    String? vaultPath,
    String? localPathOrUri,
    String? passphrase,
  }) {
    final tree = <String, Set<String>>{};
    final entryMap = <String, ArchiveEntryInfo>{};
    final knownDirs = <String>{''};

    for (final entry in indexResult.entries) {
      var entryName = entry.path.replaceAll('\\', '/');
      while (entryName.startsWith('/')) {
        entryName = entryName.substring(1);
      }
      if (entryName.endsWith('/')) {
        entryName = entryName.substring(0, entryName.length - 1);
      }
      if (entryName.isEmpty || !_isSafeRelativePath(entryName)) continue;

      entryMap[entryName] = entry;

      final parts = entryName.split('/');
      // Ensure all ancestor directories exist in the tree
      for (int i = 0; i < parts.length - 1; i++) {
        final dirPath = parts.sublist(0, i + 1).join('/');
        final parentPath = i == 0 ? '' : parts.sublist(0, i).join('/');
        if (knownDirs.add(dirPath)) {
          final dirName = parts[i];
          final wireEntry = 'D|0|${entry.modTime.millisecondsSinceEpoch ~/ 1000}|$dirName';
          tree.putIfAbsent(parentPath, () => <String>{}).add(wireEntry);
        }
      }

      final parentDir = parts.length > 1
          ? parts.sublist(0, parts.length - 1).join('/')
          : '';
      final baseName = parts.last;

      if (!entry.isDirectory) {
        final wireEntry = 'F|${entry.uncompressedSize}|${entry.modTime.millisecondsSinceEpoch ~/ 1000}|$baseName';
        tree.putIfAbsent(parentDir, () => <String>{}).add(wireEntry);
      } else {
        if (knownDirs.add(entryName)) {
          final wireEntry = 'D|0|${entry.modTime.millisecondsSinceEpoch ~/ 1000}|$baseName';
          tree.putIfAbsent(parentDir, () => <String>{}).add(wireEntry);
        }
      }
    }

    final treeMap = tree.map((k, v) => MapEntry(k, v.toList()));

    return ArchiveContext._(
      archivePathInContainer: archivePathInContainer,
      pathStackEntryIndex: pathStackEntryIndex,
      indexResult: indexResult,
      api: api,
      vaultFilePath: vaultFilePath,
      vaultPath: vaultPath,
      localPathOrUri: localPathOrUri,
      passphrase: passphrase,
      tree: treeMap,
      entryMap: entryMap,
    );
  }

  /// Whether this archive is a solid archive (e.g. RAR or 7z with multi-file shared blocks).
  bool get isSolid => indexResult.isSolid;

  /// Open status of the archive.
  ArchiveOpenStatus get status => indexResult.status;

  /// List of all entries returned by scan.
  List<ArchiveEntryInfo> get allEntries => indexResult.entries;

  /// Looks up entry metadata for [entryPath].
  ArchiveEntryInfo? findEntry(String entryPath) {
    var clean = entryPath.replaceAll('\\', '/');
    while (clean.startsWith('/')) {
      clean = clean.substring(1);
    }
    if (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    return _entryMap[clean];
  }

  /// List immediate children of [subPath] within the archive.
  /// Returns entries in RawEntry wire format.
  List<String> listDirectory(String subPath) {
    return _tree[subPath] ?? const [];
  }

  /// True if [entryPath] is safe to use as a relative output path.
  static bool _isSafeRelativePath(String entryPath) {
    if (p.isAbsolute(entryPath)) return false;
    final normalized = p.normalize(entryPath);
    if (normalized == '..' || normalized.startsWith('../')) return false;
    return true;
  }

  /// Extracts the raw bytes of a single file entry from the archive on-demand.
  Future<Uint8List?> extractEntry(String entryPath) async {
    if (!_isSafeRelativePath(entryPath)) return null;
    final info = findEntry(entryPath);
    if (info == null || info.isDirectory || _api == null) return null;

    if (vaultFilePath != null && vaultPath != null) {
      return await _api.extractVaultArchiveEntry(
        filePath: vaultFilePath!,
        vaultPath: vaultPath!,
        targetIndex: info.index,
        passphrase: passphrase,
      );
    } else if (localPathOrUri != null) {
      return await _api.extractLocalArchiveEntry(
        pathOrUri: localPathOrUri!,
        targetIndex: info.index,
        passphrase: passphrase,
      );
    }
    return null;
  }

  /// Extracts entries under [subPath] into a map of path -> bytes.
  Future<Map<String, Uint8List>> extractAll({String subPath = ''}) async {
    final results = <String, Uint8List>{};
    for (final entry in _entryMap.entries) {
      final path = entry.key;
      final info = entry.value;
      if (info.isDirectory) continue;
      if (subPath.isNotEmpty && !path.startsWith('$subPath/') && path != subPath) {
        continue;
      }
      final bytes = await extractEntry(path);
      if (bytes != null) {
        results[path] = bytes;
      }
    }
    return results;
  }

  /// Get all directory paths that exist under [subPath].
  List<String> getSubDirectories(String subPath) {
    return _tree.keys
        .where((k) => k.isNotEmpty && (subPath.isEmpty ? true : k.startsWith('$subPath/')))
        .toList();
  }

  void dispose() {}
}
