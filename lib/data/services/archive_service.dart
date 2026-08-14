import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

/// Stateless service for opening, listing, and extracting archive files
/// from within the encrypted container.
class ArchiveService {
  ArchiveService._();

  /// Extensions recognized as browsable archives.
  static const _supportedExtensions = {'zip'};

  /// Extensions recognized as archives but not yet supported for browsing.
  static const _unsupportedExtensions = {'7z', 'rar'};

  /// All archive extensions (supported + unsupported).
  static const allArchiveExtensions = {'zip', '7z', 'rar', 'tar', 'gz', 'bz2', 'xz'};

  /// Whether the given extension is a supported, browsable archive format.
  static bool isSupported(String ext) =>
      _supportedExtensions.contains(ext.toLowerCase());

  /// Whether the given extension is a known archive but not yet supported.
  static bool isUnsupported(String ext) =>
      _unsupportedExtensions.contains(ext.toLowerCase());

  /// Whether the given extension is any known archive format.
  static bool isArchive(String ext) =>
      allArchiveExtensions.contains(ext.toLowerCase());

  /// Open an archive from the encrypted container for browsing.
  ///
  /// 1. Reads the archive's bytes from the container via chunked reads
  ///    (never staged as a plaintext file on host disk).
  /// 2. Parses the archive in memory.
  /// 3. Returns an [ArchiveContext] for virtual directory browsing.
  ///
  /// Throws if the archive cannot be read or parsed.
  static Future<ArchiveContext> open({
    required MountedContainer container,
    required String archivePathInContainer,
    required int pathStackEntryIndex,
  }) async {
    final bytes = await vaultExplorerApi.readWholeFile(
      container,
      archivePathInContainer,
    );

    if (bytes == null) {
      throw Exception('Failed to read archive from container');
    }

    return ArchiveContext.open(
      archivePathInContainer: archivePathInContainer,
      bytes: bytes,
      pathStackEntryIndex: pathStackEntryIndex,
    );
  }

  /// Extract specific entries from an open archive into the encrypted container.
  ///
  /// [entryPaths] are paths within the archive (e.g. "folder/file.txt").
  /// [targetDirInContainer] is the destination directory inside the container.
  ///
  /// Returns the number of files successfully extracted.
  static Future<int> extractToContainer({
    required MountedContainer container,
    required ArchiveContext archiveContext,
    required List<String> entryPaths,
    required String targetDirInContainer,
  }) async {
    int count = 0;

    for (final entryPath in entryPaths) {
      final bytes = await archiveContext.extractEntry(entryPath);
      if (bytes == null) continue;

      final baseName = p.basename(entryPath);
      final destPath = targetDirInContainer.isEmpty
          ? baseName
          : '$targetDirInContainer/$baseName';

      final ok = await vaultExplorerApi.writeWholeFile(container, destPath, bytes);
      if (ok) count++;
    }

    return count;
  }

  /// Extract all entries (under [subPath] if given) from an archive
  /// into the encrypted container, preserving directory structure.
  ///
  /// Returns the number of files successfully extracted.
  static Future<int> extractAllToContainer({
    required MountedContainer container,
    required ArchiveContext archiveContext,
    required String targetDirInContainer,
    String subPath = '',
    ValueChanged<String>? onProgress,
  }) async {
    int count = 0;

    // First, create all directories
    final subDirs = archiveContext.getSubDirectories(subPath);
    for (final dirPath in subDirs) {
      final relativePath = subPath.isEmpty
          ? dirPath
          : dirPath.substring(subPath.length + 1);
      if (relativePath.isEmpty) continue;

      final destDir = targetDirInContainer.isEmpty
          ? relativePath
          : '$targetDirInContainer/$relativePath';

      await vaultExplorerApi.createDirectory(container, destDir);
    }

    // Then extract all files
    final extracted = await archiveContext.extractAll(subPath: subPath);

    for (final entry in extracted.entries) {
      final archivePath = entry.key;
      final bytes = entry.value;

      final relativePath = subPath.isEmpty
          ? archivePath
          : archivePath.substring(subPath.length + 1);

      final destPath = targetDirInContainer.isEmpty
          ? relativePath
          : '$targetDirInContainer/$relativePath';

      onProgress?.call(p.basename(archivePath));

      final ok = await vaultExplorerApi.writeWholeFile(container, destPath, bytes);
      if (ok) count++;
    }

    return count;
  }
}
