import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/archive_context.dart';
import '../models/mounted_container.dart';
import 'vaultexplorer_api.dart';

/// Stateless service for opening, listing, and extracting archive files
/// from within the encrypted container.
///
/// Currently supports ZIP archives via the `archive` Dart package.
/// 7Z and RAR require native C++ integration (future work).
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
  /// 1. Extracts the archive from the container to a temp directory
  /// 2. Parses the archive in memory
  /// 3. Returns an [ArchiveContext] for virtual directory browsing
  ///
  /// Throws if the archive cannot be extracted or parsed.
  static Future<ArchiveContext> open({
    required MountedContainer container,
    required String archivePathInContainer,
    required int pathStackEntryIndex,
  }) async {
    // 1. Extract the archive from the encrypted container to temp storage
    final tempDir = await getTemporaryDirectory();
    final archiveBaseName = p.basename(archivePathInContainer);
    final tempPath = p.join(tempDir.path, 'archive_browse_$archiveBaseName');

    final success = await vaultExplorerApi.decryptFile(
      container,
      archivePathInContainer,
      tempPath,
    );

    if (!success) {
      throw Exception('Failed to extract archive from container');
    }

    // 2. Parse the archive
    try {
      return ArchiveContext.open(
        archivePathInContainer: archivePathInContainer,
        tempFilePath: tempPath,
        pathStackEntryIndex: pathStackEntryIndex,
      );
    } catch (e) {
      // Clean up temp file on parse failure
      try { File(tempPath).deleteSync(); } catch (_) {}
      rethrow;
    }
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
      final tempFile = await archiveContext.extractEntry(entryPath);
      if (tempFile == null) continue;

      try {
        final baseName = p.basename(entryPath);
        final destPath = targetDirInContainer.isEmpty
            ? baseName
            : '$targetDirInContainer/$baseName';

        final ok = await vaultExplorerApi.writeBackFile(
          container,
          destPath,
          tempFile,
        );
        if (ok) count++;
      } finally {
        // Clean up temp file
        try { File(tempFile).deleteSync(); } catch (_) {}
      }
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
      final tempFilePath = entry.value;

      try {
        final relativePath = subPath.isEmpty
            ? archivePath
            : archivePath.substring(subPath.length + 1);

        final destPath = targetDirInContainer.isEmpty
            ? relativePath
            : '$targetDirInContainer/$relativePath';

        onProgress?.call(p.basename(archivePath));

        final ok = await vaultExplorerApi.writeBackFile(
          container,
          destPath,
          tempFilePath,
        );
        if (ok) count++;
      } finally {
        try { File(tempFilePath).deleteSync(); } catch (_) {}
      }
    }

    // Clean up temp extraction directory
    try {
      if (extracted.isNotEmpty) {
        final firstTemp = extracted.values.first;
        // Walk up to the archive_extract_all_ temp dir and delete it
        var dir = Directory(p.dirname(firstTemp));
        while (dir.path.contains('archive_extract_all_')) {
          final parent = dir.parent;
          if (dir.existsSync()) dir.deleteSync(recursive: true);
          dir = parent;
          break;
        }
      }
    } catch (_) {}

    return count;
  }
}
