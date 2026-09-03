import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:vaultexplorer/core/api/vault_archive_api.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/archive_models.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

/// Stateless service for opening, listing, extracting, and creating archive files
/// backed by native C++ libarchive engine.
class ArchiveService {
  ArchiveService._();

  static VaultArchiveApi? _archiveApi;
  static VaultFileIoApi? _fileIoApi;

  /// Wires this static archive utility to the Riverpod engine APIs.
  static void configure(
    VaultFileIoApi fileIoApi, [
    VaultArchiveApi? archiveApi,
  ]) {
    _fileIoApi = fileIoApi;
    if (archiveApi != null) {
      _archiveApi = archiveApi;
    }
  }

  static void configureWithArchiveApi({
    required VaultArchiveApi archiveApi,
    required VaultFileIoApi fileIoApi,
  }) {
    _archiveApi = archiveApi;
    _fileIoApi = fileIoApi;
  }

  static VaultArchiveApi get _archive =>
      _archiveApi ??
      (throw StateError(
        'ArchiveService must be configured with VaultArchiveApi during app startup.',
      ));

  static VaultFileIoApi get _fileIo =>
      _fileIoApi ??
      (throw StateError(
        'ArchiveService must be configured with VaultFileIoApi during app startup.',
      ));

  /// All archive extensions recognized and supported by the native engine.
  static const allArchiveExtensions = {
    'zip',
    '7z',
    'rar',
    'tar',
    'gz',
    'bz2',
    'xz',
    'zst',
    'zstd',
  };

  /// Whether the given extension is a supported, browsable archive format.
  static bool isSupported(String ext) =>
      allArchiveExtensions.contains(ext.toLowerCase());

  /// Retained for backwards-compatibility; no formats are unsupported now.
  static bool isUnsupported(String ext) => false;

  /// Whether the given extension is any known archive format.
  static bool isArchive(String ext) =>
      allArchiveExtensions.contains(ext.toLowerCase());

  /// Open an archive from the encrypted container for metadata-only browsing.
  static Future<ArchiveContext> open({
    required MountedContainer container,
    required String archivePathInContainer,
    required int pathStackEntryIndex,
    String? passphrase,
  }) async {
    final result = await _archive.scanVaultArchive(
      filePath: container.uri,
      vaultPath: archivePathInContainer,
      passphrase: passphrase,
    );

    if (result.status != ArchiveOpenStatus.ok &&
        result.status != ArchiveOpenStatus.passphraseRequired &&
        result.status != ArchiveOpenStatus.wrongPassphrase) {
      throw Exception(
        result.errorMessage.isNotEmpty
            ? result.errorMessage
            : 'Failed to scan archive',
      );
    }

    return ArchiveContext.fromScanResult(
      archivePathInContainer: archivePathInContainer,
      indexResult: result,
      pathStackEntryIndex: pathStackEntryIndex,
      api: _archive,
      vaultFilePath: container.uri,
      vaultPath: archivePathInContainer,
      passphrase: passphrase,
    );
  }

  /// Open a local/external archive file on device storage.
  static Future<ArchiveContext> openLocal({
    required String pathOrUri,
    required String archiveName,
    int pathStackEntryIndex = 0,
    String? passphrase,
  }) async {
    final result = await _archive.scanLocalArchive(
      pathOrUri: pathOrUri,
      passphrase: passphrase,
    );

    if (result.status != ArchiveOpenStatus.ok &&
        result.status != ArchiveOpenStatus.passphraseRequired &&
        result.status != ArchiveOpenStatus.wrongPassphrase) {
      throw Exception(
        result.errorMessage.isNotEmpty
            ? result.errorMessage
            : 'Failed to scan local archive',
      );
    }

    return ArchiveContext.fromScanResult(
      archivePathInContainer: archiveName,
      indexResult: result,
      pathStackEntryIndex: pathStackEntryIndex,
      api: _archive,
      localPathOrUri: pathOrUri,
      passphrase: passphrase,
    );
  }

  /// Extract specific entries from an open archive into the encrypted container.
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

      final ok = await _fileIo.writeWholeFile(container, destPath, bytes);
      if (ok) count++;
    }

    return count;
  }

  /// Extract all entries (under [subPath] if given) from an archive
  /// into the encrypted container.
  ///
  /// Uses native bulk extraction when possible for high performance.
  static Future<int> extractAllToContainer({
    required MountedContainer container,
    required ArchiveContext archiveContext,
    required String targetDirInContainer,
    String subPath = '',
    ValueChanged<String>? onProgress,
    int? opId,
  }) async {
    // Attempt native bulk extraction first
    if (archiveContext.vaultFilePath != null && archiveContext.vaultPath != null) {
      final bulkRes = await _archive.extractVaultArchiveAll(
        filePath: archiveContext.vaultFilePath!,
        vaultPath: archiveContext.vaultPath!,
        destUri: container.uri,
        destDirPath: targetDirInContainer,
        subPath: subPath.isNotEmpty ? subPath : null,
        passphrase: archiveContext.passphrase,
        opId: opId,
      );
      if (bulkRes.status == ArchiveOpenStatus.ok) {
        return bulkRes.extractedCount;
      }
    } else if (archiveContext.localPathOrUri != null) {
      final bulkRes = await _archive.extractVaultArchiveAll(
        filePath: archiveContext.localPathOrUri!,
        vaultPath: null,
        destUri: container.uri,
        destDirPath: targetDirInContainer,
        subPath: subPath.isNotEmpty ? subPath : null,
        passphrase: archiveContext.passphrase,
        opId: opId,
      );
      if (bulkRes.status == ArchiveOpenStatus.ok) {
        return bulkRes.extractedCount;
      }
    }

    // Fallback: per-entry extraction
    int count = 0;

    final subDirs = archiveContext.getSubDirectories(subPath);
    for (final dirPath in subDirs) {
      final relativePath = subPath.isEmpty
          ? dirPath
          : dirPath.substring(subPath.length + 1);
      if (relativePath.isEmpty) continue;

      final destDir = targetDirInContainer.isEmpty
          ? relativePath
          : '$targetDirInContainer/$relativePath';

      await _fileIo.createDirectory(container, destDir);
    }

    final allFiles = archiveContext.allEntries.where((e) => !e.isDirectory);
    for (final entry in allFiles) {
      final name = entry.path.replaceAll('\\', '/');
      if (subPath.isNotEmpty && !name.startsWith('$subPath/') && name != subPath) {
        continue;
      }

      final relativePath = subPath.isEmpty
          ? name
          : name.substring(subPath.length + 1);

      final destPath = targetDirInContainer.isEmpty
          ? relativePath
          : '$targetDirInContainer/$relativePath';

      onProgress?.call(p.basename(name));

      final bytes = await archiveContext.extractEntry(name);
      if (bytes != null) {
        final ok = await _fileIo.writeWholeFile(container, destPath, bytes);
        if (ok) count++;
      }
    }

    return count;
  }

  /// Compresses [entries] into a new archive written to [destPathInContainer].
  static Future<int> compressToContainer({
    required MountedContainer container,
    required List<RawEntry> entries,
    required String currentDirPath,
    required String destPathInContainer,
    ArchiveFormatType format = ArchiveFormatType.zip,
    String? passphrase,
    int? opId,
  }) async {
    final srcPaths = <String>[];
    final entryNames = <String>[];

    Future<void> collect(String containerPath, String archivePath) async {
      final rawList = await _fileIo.listDirectory(container, containerPath);
      final children = RawEntry.parseAll(rawList ?? const []);
      for (final child in children) {
        final childContainerPath = '$containerPath/${child.name}';
        final childArchivePath = '$archivePath/${child.name}';
        if (child.isDir) {
          await collect(childContainerPath, childArchivePath);
        } else {
          srcPaths.add(childContainerPath);
          entryNames.add(childArchivePath);
        }
      }
    }

    for (final entry in entries) {
      final containerPath = currentDirPath.isEmpty
          ? entry.name
          : '$currentDirPath/${entry.name}';
      if (entry.isDir) {
        await collect(containerPath, entry.name);
      } else {
        srcPaths.add(containerPath);
        entryNames.add(entry.name);
      }
    }

    if (srcPaths.isEmpty) {
      return 0;
    }

    final ok = await _archive.createArchive(
      format: format,
      srcPaths: srcPaths,
      entryNames: entryNames,
      srcUri: container.uri,
      destUri: container.uri,
      destVaultPath: destPathInContainer,
      passphrase: passphrase,
      opId: opId,
    );

    if (!ok) {
      throw Exception('Failed to create archive');
    }
    return srcPaths.length;
  }
}
