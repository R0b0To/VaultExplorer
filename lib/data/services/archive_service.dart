import 'package:vaultexplorer/core/filesystem/case_collision.dart';
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

  static const int _maxEntryBytesInMemory = 4 * 1024 * 1024;

  static VaultArchiveApi? _archiveApi;
  static VaultFileIoApi? _fileIoApi;

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
    'lzma',
  };

  static bool isSupported(String ext) =>
      allArchiveExtensions.contains(ext.toLowerCase());

  static bool isUnsupported(String ext) => false;

  static bool isArchive(String ext) =>
      allArchiveExtensions.contains(ext.toLowerCase());

  /// Extensions that are really ZIP containers under a different name.
  ///
  /// The native engine sniffs the format from the bytes (libarchive's
  /// `archive_read_support_format_all`), so these already scan, list and
  /// extract correctly -- they just must not be *auto-routed* to the archive
  /// browser on tap the way [isArchive] extensions are, because tapping one
  /// means something else first (an `.apk` is installed).
  ///
  /// Deliberately kept out of [allArchiveExtensions]: [isArchive] is also
  /// what `isUnsupportedArchiveCarrierName` uses to reject a file as a
  /// composite-container carrier, and an APK is a perfectly valid carrier.
  static const zipLikePackageExtensions = {'apk'};

  static bool isZipLikePackage(String ext) =>
      zipLikePackageExtensions.contains(ext.toLowerCase());

  /// Formats the app can create and the native engine reads (libarchive
  /// detects them from their bytes) that are opened on tap like any archive,
  /// but are deliberately kept out of [allArchiveExtensions] for the same
  /// reason as the APK: [isArchive] also decides which files are rejected as
  /// composite-container carriers, and ISO images are valid carriers.
  static const isoCpioExtensions = {'iso', 'cpio'};

  static bool isIsoOrCpio(String ext) =>
      isoCpioExtensions.contains(ext.toLowerCase());

  /// True when tapping a file with this extension should open the archive
  /// browser: every [isArchive] extension plus ISO and cpio. (Not `.apk`: a
  /// tap installs it; see [zipLikePackageExtensions].)
  static bool opensOnTap(String ext) => isArchive(ext) || isIsoOrCpio(ext);

  /// True when the file can be opened in the archive browser and extracted,
  /// whether or not a tap does that by default: everything that [opensOnTap]
  /// plus the [zipLikePackageExtensions].
  static bool isOpenableAsArchive(String ext) =>
      opensOnTap(ext) || isZipLikePackage(ext);

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

  static Future<int> extractToContainer({
    required MountedContainer container,
    required ArchiveContext archiveContext,
    required List<String> entryPaths,
    required String targetDirInContainer,
  }) async {
    int count = 0;

    for (final entryPath in entryPaths) {
      final baseName = p.basename(entryPath);
      final destPath = targetDirInContainer.isEmpty
          ? baseName
          : '$targetDirInContainer/$baseName';

      final ok = await _extractEntryToContainer(
        container: container,
        archiveContext: archiveContext,
        entryPath: entryPath,
        destPath: destPath,
      );
      if (ok) count++;
    }

    return count;
  }

  static Future<int> extractAllToContainer({
    required MountedContainer container,
    required ArchiveContext archiveContext,
    required String targetDirInContainer,
    String subPath = '',
    ValueChanged<String>? onProgress,
    int? opId,
  }) async {
    if (archiveContext.vaultFilePath != null &&
        archiveContext.vaultPath != null) {
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
      if (subPath.isNotEmpty &&
          !name.startsWith('$subPath/') &&
          name != subPath) {
        continue;
      }

      final relativePath = subPath.isEmpty
          ? name
          : name.substring(subPath.length + 1);

      final destPath = targetDirInContainer.isEmpty
          ? relativePath
          : '$targetDirInContainer/$relativePath';

      onProgress?.call(p.basename(name));

      final ok = await _extractEntryToContainer(
        container: container,
        archiveContext: archiveContext,
        entryPath: name,
        destPath: destPath,
        opId: opId,
      );
      if (ok) count++;
    }

    return count;
  }

  /// Extract specific entries (and any children if directories) from an open archive
  /// into the target directory.
  static Future<int> extractSelectedToContainer({
    required MountedContainer container,
    required ArchiveContext archiveContext,
    required List<String> entryPaths,
    required String targetDirInContainer,
    void Function(int count, String currentPath)? onProgress,
    int? opId,
  }) async {
    int count = 0;
    final Set<String> targetFiles = {};

    for (final selectedPath in entryPaths) {
      final cleanSelected = selectedPath.replaceAll('\\', '/');
      for (final entry in archiveContext.allEntries) {
        if (entry.isDirectory) continue;
        final entryPath = entry.path.replaceAll('\\', '/');
        final cleanEntry = entryPath.startsWith('/')
            ? entryPath.substring(1)
            : entryPath;
        if (cleanEntry == cleanSelected ||
            cleanEntry.startsWith('$cleanSelected/')) {
          targetFiles.add(cleanEntry);
        }
      }
    }

    if (targetFiles.isEmpty) {
      targetFiles.addAll(entryPaths);
    }

    for (final relPath in targetFiles) {
      final destPath = targetDirInContainer.isEmpty
          ? relPath
          : '$targetDirInContainer/$relPath';

      final parentDir = p.dirname(destPath);
      if (parentDir.isNotEmpty && parentDir != '.') {
        await _fileIo.createDirectory(container, parentDir);
      }

      final ok = await _extractEntryToContainer(
        container: container,
        archiveContext: archiveContext,
        entryPath: relPath,
        destPath: destPath,
        opId: opId,
      );
      if (ok) {
        count++;
        onProgress?.call(count, p.basename(destPath));
      }
    }
    return count;
  }

  /// Where extracting [archiveContext] would write each file: archive entry
  /// path -> destination path relative to the target folder. It applies the
  /// same selection and `subPath` stripping [extractSelectedToContainer] /
  /// [extractAllToContainer] do, so a case-collision plan covers exactly
  /// what would land on disk.
  static Map<String, String> extractDestinations(
    ArchiveContext archiveContext, {
    List<String>? selectedEntryPaths,
    String subPath = '',
  }) {
    String clean(String path) {
      final slashed = path.replaceAll('\\', '/');
      return slashed.startsWith('/') ? slashed.substring(1) : slashed;
    }

    final files = archiveContext.allEntries
        .where((e) => !e.isDirectory)
        .map((e) => clean(e.path))
        .toList();

    if (selectedEntryPaths != null && selectedEntryPaths.isNotEmpty) {
      final selected = selectedEntryPaths.map(clean).toList();
      final picked = <String>{
        for (final f in files)
          if (selected.any((s) => f == s || f.startsWith('$s/'))) f,
      };
      // Same fallback as extractSelectedToContainer: nothing matched, so the
      // selection itself is what gets extracted.
      final chosen = picked.isEmpty ? selected : picked.toList();
      return {for (final f in chosen) f: f};
    }

    if (subPath.isEmpty) return {for (final f in files) f: f};
    return {
      for (final f in files)
        if (f.startsWith('$subPath/')) f: f.substring(subPath.length + 1),
    };
  }

  /// The destinations for extracting [archiveContext] onto a
  /// case-insensitive filesystem when some of them would replace one
  /// another ("Notes.txt" and "notes.txt"): archive entry path -> the
  /// destination path to use, with the later of each colliding group renamed
  /// to a unique "name (1).ext". Returns `null` when nothing collides, in
  /// which case the extraction can go ahead unchanged (including the fast
  /// native bulk route). Callers check
  /// `isDestinationCaseSensitive(destination)` first -- on a case-sensitive
  /// destination those entries are legitimately different files.
  static Map<String, String>? caseSafeExtractPlan(
    ArchiveContext archiveContext, {
    List<String>? selectedEntryPaths,
    String subPath = '',
  }) {
    final destinations = extractDestinations(
      archiveContext,
      selectedEntryPaths: selectedEntryPaths,
      subPath: subPath,
    );
    final original = destinations.values.toList();
    final resolved = resolveCaseCollisionPaths(original);
    var changed = false;
    for (var i = 0; i < original.length; i++) {
      if (resolved[i] != original[i]) {
        changed = true;
        break;
      }
    }
    if (!changed) return null;
    final keys = destinations.keys.toList();
    return {for (var i = 0; i < keys.length; i++) keys[i]: resolved[i]};
  }

  /// Extracts exactly the files in [destRelByEntryPath] (archive entry path
  /// -> destination path relative to [targetDirInContainer]) one at a time.
  /// Used instead of the bulk native route when destination names have to
  /// differ from the archive's, i.e. for a [caseSafeExtractPlan]. Empty
  /// folders that the archive lists are not recreated on this route.
  static Future<int> extractMappedToContainer({
    required MountedContainer container,
    required ArchiveContext archiveContext,
    required Map<String, String> destRelByEntryPath,
    required String targetDirInContainer,
    void Function(int count, String currentPath)? onProgress,
    int? opId,
  }) async {
    int count = 0;
    for (final mapping in destRelByEntryPath.entries) {
      final destPath = targetDirInContainer.isEmpty
          ? mapping.value
          : '$targetDirInContainer/${mapping.value}';

      final parentDir = p.dirname(destPath);
      if (parentDir.isNotEmpty && parentDir != '.') {
        await _fileIo.createDirectory(container, parentDir);
      }

      final ok = await _extractEntryToContainer(
        container: container,
        archiveContext: archiveContext,
        entryPath: mapping.key,
        destPath: destPath,
        opId: opId,
      );
      if (ok) {
        count++;
        onProgress?.call(count, p.basename(destPath));
      }
    }
    return count;
  }

  static Future<bool> _extractEntryToContainer({
    required MountedContainer container,
    required ArchiveContext archiveContext,
    required String entryPath,
    required String destPath,
    int? opId,
  }) async {
    final entry = archiveContext.findEntry(entryPath);
    if (entry != null &&
        entry.uncompressedSize > 0 &&
        entry.uncompressedSize <= _maxEntryBytesInMemory) {
      final bytes = await archiveContext.extractEntry(entryPath);
      return bytes != null &&
          await _fileIo.writeWholeFile(container, destPath, bytes);
    }

    final staged = await archiveContext.stageEntryForBrowse(entryPath);
    final stagedPath = staged.path;
    if (staged.status != ArchiveOpenStatus.ok || stagedPath == null) {
      return false;
    }

    try {
      return await _fileIo.writeFileFromLocalPath(
        container,
        destPath,
        stagedPath,
        opId: opId ?? 0,
      );
    } finally {
      await _archive.discardBrowseFile(stagedPath);
    }
  }

  /// Directly calls the archive creation API.
  static Future<bool> createArchive({
    required ArchiveFormatType format,
    required List<String> srcPaths,
    List<String>? entryNames,
    List<int>? modifiedSecs,
    String? srcUri,
    String? destUri,
    String? destVaultPath,
    String? destFilePath,
    String? passphrase,
    bool encryptFilenames = false,
    int? compressionLevel,
    int? compressionMethod,
    int? opId,
  }) {
    return _archive.createArchive(
      format: format,
      srcPaths: srcPaths,
      entryNames: entryNames,
      modifiedSecs: modifiedSecs,
      srcUri: srcUri,
      destUri: destUri,
      destVaultPath: destVaultPath,
      destFilePath: destFilePath,
      passphrase: passphrase,
      encryptFilenames: encryptFilenames,
      compressionLevel: compressionLevel,
      compressionMethod: compressionMethod,
      opId: opId,
    );
  }

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
    final modifiedSecs = <int>[];

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
          modifiedSecs.add(child.modifiedSecs);
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
        modifiedSecs.add(entry.modifiedSecs);
      }
    }

    if (srcPaths.isEmpty) {
      return 0;
    }

    final ok = await createArchive(
      format: format,
      srcPaths: srcPaths,
      entryNames: entryNames,
      modifiedSecs: modifiedSecs,
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
