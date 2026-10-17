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
    this._api,
    this.vaultFilePath,
    this.vaultPath,
    this.localPathOrUri,
    this.passphrase,
    required this._tree,
    required this._entryMap,
  });

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
      // The archive's own root record ("." / "./", written by ISO 9660 and
      // cpio) is the listing itself, not an item inside it.
      if (entryName == '.') continue;
      if (entryName.isEmpty || !_isSafeRelativePath(entryName)) continue;

      entryMap[entryName] = entry;

      final parts = entryName.split('/');
      // Ensure all ancestor directories exist in the tree
      for (int i = 0; i < parts.length - 1; i++) {
        final dirPath = parts.sublist(0, i + 1).join('/');
        final parentPath = i == 0 ? '' : parts.sublist(0, i).join('/');
        if (knownDirs.add(dirPath)) {
          final dirName = parts[i];
          final wireEntry =
              'D|0|${entry.modTime.millisecondsSinceEpoch ~/ 1000}|$dirName';
          tree.putIfAbsent(parentPath, () => <String>{}).add(wireEntry);
        }
      }

      final parentDir = parts.length > 1
          ? parts.sublist(0, parts.length - 1).join('/')
          : '';
      final baseName = parts.last;

      if (!entry.isDirectory) {
        final wireEntry =
            'F|${entry.uncompressedSize}|${entry.modTime.millisecondsSinceEpoch ~/ 1000}|$baseName';
        tree.putIfAbsent(parentDir, () => <String>{}).add(wireEntry);
      } else {
        if (knownDirs.add(entryName)) {
          final wireEntry =
              'D|0|${entry.modTime.millisecondsSinceEpoch ~/ 1000}|$baseName';
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

  /// Whether this archive uses the 7-Zip format. 7z archives may be solid,
  /// but individual image entries can still be extracted for thumbnails.
  bool get isSevenZip => indexResult.isSevenZip;

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

  /// Largest entry [extractEntryResult] will load into memory.
  ///
  /// An extracted entry crosses the platform channel as one byte array, and
  /// the channel codec then copies it into a buffer that doubles as it grows:
  /// a ~100 MB entry needs a ~210 MB allocation against the app's 256 MB Java
  /// heap limit, and the resulting `OutOfMemoryError` used to take the whole
  /// app down. Anything bigger must be streamed with [stageEntryForBrowse].
  static const int maxInMemoryEntryBytes = 16 * 1024 * 1024;

  /// Extracts the raw bytes of a single file entry from the archive on-demand.
  ///
  /// Convenience wrapper over [extractEntryResult] for callers that need a
  /// small entry's contents in memory and don't need to react to *why* it
  /// failed. Large files should use [stageEntryForBrowse] instead.
  Future<Uint8List?> extractEntry(String entryPath) async {
    final res = await extractEntryResult(entryPath);
    return res.status == ArchiveOpenStatus.ok ? res.data : null;
  }

  /// Extracts a single file entry, preserving the native engine's status so
  /// callers can distinguish a wrong/missing passphrase from a genuine I/O
  /// error (and, e.g., re-prompt for a password) instead of seeing a bare
  /// null for every failure mode.
  Future<ArchiveEntryExtractResult> extractEntryResult(String entryPath) async {
    if (!_isSafeRelativePath(entryPath)) {
      return const ArchiveEntryExtractResult(
        status: ArchiveOpenStatus.ioError,
        data: null,
        errorMessage: 'Unsafe entry path',
      );
    }
    final info = findEntry(entryPath);
    if (info == null || info.isDirectory || _api == null) {
      return const ArchiveEntryExtractResult(
        status: ArchiveOpenStatus.ioError,
        data: null,
        errorMessage: 'Entry not found',
      );
    }

    if (info.uncompressedSize > maxInMemoryEntryBytes) {
      return ArchiveEntryExtractResult.ioError(
        'Entry is too large to load into memory '
        '(${info.uncompressedSize} bytes); stream it with stageEntryForBrowse',
      );
    }

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
    return const ArchiveEntryExtractResult(
      status: ArchiveOpenStatus.ioError,
      data: null,
      errorMessage: 'Archive has no backing source',
    );
  }

  /// Streams an entry directly into an app-private temporary file. Unlike
  /// [extractEntry], this never creates a full Dart-side byte array, so it is
  /// appropriate for large media previews and extraction transfers.
  Future<ArchiveEntryStageResult> stageEntryForBrowse(String entryPath) async {
    if (!_isSafeRelativePath(entryPath)) {
      return ArchiveEntryStageResult.ioError('Unsafe entry path');
    }
    final info = findEntry(entryPath);
    if (info == null || info.isDirectory || _api == null) {
      return ArchiveEntryStageResult.ioError('Entry not found');
    }

    if (vaultFilePath != null && vaultPath != null) {
      return _api.stageBrowseEntry(
        filePath: vaultFilePath!,
        vaultPath: vaultPath,
        targetIndex: info.index,
        entryName: info.path,
        passphrase: passphrase,
      );
    }
    if (localPathOrUri != null) {
      return _api.stageBrowseEntry(
        filePath: localPathOrUri!,
        targetIndex: info.index,
        entryName: info.path,
        passphrase: passphrase,
      );
    }
    return ArchiveEntryStageResult.ioError('Archive has no backing source');
  }

  /// Removes a temporary file created by [stageEntryForBrowse].
  Future<bool> discardStagedEntry(String path) async {
    final api = _api;
    if (api == null) return false;
    return api.discardBrowseFile(path);
  }

  /// Returns a copy of this context that will use [newPassphrase] for
  /// subsequent entry extraction, without re-scanning the archive -- for
  /// retrying a single [extractEntryResult] call after a
  /// [ArchiveOpenStatus.passphraseRequired]/[wrongPassphrase] result.
  ArchiveContext withPassphrase(String newPassphrase) {
    return ArchiveContext._(
      archivePathInContainer: archivePathInContainer,
      pathStackEntryIndex: pathStackEntryIndex,
      indexResult: indexResult,
      api: _api,
      vaultFilePath: vaultFilePath,
      vaultPath: vaultPath,
      localPathOrUri: localPathOrUri,
      passphrase: newPassphrase,
      tree: _tree,
      entryMap: _entryMap,
    );
  }

  /// Re-scans the archive with [newPassphrase]. For 7-Zip archives whose
  /// filenames are visible without a password, passing a candidate password
  /// asks the native scan to verify it against the first encrypted entry.
  Future<ArchiveContext> rescanWithPassphrase(String newPassphrase) async {
    final api = _api;
    final ArchiveIndexResult result;
    if (api == null) {
      result = const ArchiveIndexResult(
        status: ArchiveOpenStatus.ioError,
        entries: [],
        isSolid: false,
        errorMessage: 'Archive API is unavailable',
      );
    } else if (vaultFilePath != null && vaultPath != null) {
      result = await api.scanVaultArchive(
        filePath: vaultFilePath!,
        vaultPath: vaultPath!,
        passphrase: newPassphrase,
      );
    } else if (localPathOrUri != null) {
      result = await api.scanLocalArchive(
        pathOrUri: localPathOrUri!,
        passphrase: newPassphrase,
      );
    } else {
      result = const ArchiveIndexResult(
        status: ArchiveOpenStatus.ioError,
        entries: [],
        isSolid: false,
        errorMessage: 'Archive has no backing source',
      );
    }

    return ArchiveContext.fromScanResult(
      archivePathInContainer: archivePathInContainer,
      indexResult: result,
      pathStackEntryIndex: pathStackEntryIndex,
      api: api,
      vaultFilePath: vaultFilePath,
      vaultPath: vaultPath,
      localPathOrUri: localPathOrUri,
      passphrase: newPassphrase,
    );
  }

  /// Extracts entries under [subPath] into a map of path -> bytes.
  Future<Map<String, Uint8List>> extractAll({String subPath = ''}) async {
    final results = <String, Uint8List>{};
    for (final entry in _entryMap.entries) {
      final path = entry.key;
      final info = entry.value;
      if (info.isDirectory) continue;
      if (subPath.isNotEmpty &&
          !path.startsWith('$subPath/') &&
          path != subPath) {
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
        .where(
          (k) =>
              k.isNotEmpty &&
              (subPath.isEmpty ? true : k.startsWith('$subPath/')),
        )
        .toList();
  }

  void dispose() {}
}
