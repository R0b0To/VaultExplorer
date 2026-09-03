import 'package:archive/archive.dart' show Archive, ArchiveFile, ZipEncoder;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

/// Stateless service for opening, listing, and extracting archive files
/// from within the encrypted container.
class ArchiveService {
  ArchiveService._();

  static VaultFileIoApi? _fileIoApi;

  /// Wires this static archive utility to the root Riverpod engine API.
  /// It retains the existing static surface because archive mode is entered
  /// from both controller and legacy browser paths during the transition.
  static void configure(VaultFileIoApi fileIoApi) {
    _fileIoApi = fileIoApi;
  }

  static VaultFileIoApi get _api =>
      _fileIoApi ??
      (throw StateError(
        'ArchiveService must be configured during app startup.',
      ));

  /// Extensions recognized as browsable archives.
  static const _supportedExtensions = {'zip'};

  /// Extensions recognized as archives but not yet supported for browsing.
  static const _unsupportedExtensions = {'7z', 'rar'};

  /// All archive extensions (supported + unsupported).
  static const allArchiveExtensions = {
    'zip',
    '7z',
    'rar',
    'tar',
    'gz',
    'bz2',
    'xz',
  };

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
    final bytes = await _api.readWholeFile(container, archivePathInContainer);

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

      final ok = await _api.writeWholeFile(container, destPath, bytes);
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

      await _api.createDirectory(container, destDir);
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

      final ok = await _api.writeWholeFile(container, destPath, bytes);
      if (ok) count++;
    }

    return count;
  }

  /// Compress [entries] (files and/or folders already listed under
  /// [currentDirPath]) into a new zip archive written to
  /// [destPathInContainer].
  ///
  /// Folders are walked recursively via [VaultFileIoApi.listDirectory]; an
  /// empty folder is still preserved as an explicit directory entry so it
  /// round-trips through [extractAllToContainer] intact rather than
  /// silently vanishing. The archive is built entirely in memory before the
  /// single [VaultFileIoApi.writeWholeFile] call, so a failure partway
  /// through never leaves a partial file behind in the container.
  ///
  /// Returns the number of files written into the archive (directory-only
  /// entries for empty folders aren't counted).
  static Future<int> compressToContainer({
    required MountedContainer container,
    required List<RawEntry> entries,
    required String currentDirPath,
    required String destPathInContainer,
  }) async {
    final archive = Archive();
    var fileCount = 0;

    Future<void> addFile(String containerPath, String archivePath) async {
      final bytes = await _api.readWholeFile(container, containerPath);
      if (bytes == null) return;
      archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));
      fileCount++;
    }

    Future<void> addDir(String containerPath, String archivePath) async {
      final rawList = await _api.listDirectory(container, containerPath);
      final children = RawEntry.parseAll(rawList ?? const []);
      if (children.isEmpty) {
        archive.addFile(ArchiveFile.directory(archivePath));
        return;
      }
      for (final child in children) {
        final childContainerPath = '$containerPath/${child.name}';
        final childArchivePath = '$archivePath/${child.name}';
        if (child.isDir) {
          await addDir(childContainerPath, childArchivePath);
        } else {
          await addFile(childContainerPath, childArchivePath);
        }
      }
    }

    for (final entry in entries) {
      final containerPath = currentDirPath.isEmpty
          ? entry.name
          : '$currentDirPath/${entry.name}';
      if (entry.isDir) {
        await addDir(containerPath, entry.name);
      } else {
        await addFile(containerPath, entry.name);
      }
    }

    final bytes = ZipEncoder().encodeBytes(archive);
    final ok = await _api.writeWholeFile(container, destPathInContainer, bytes);
    if (!ok) {
      throw Exception('Failed to write archive to container');
    }
    return fileCount;
  }
}