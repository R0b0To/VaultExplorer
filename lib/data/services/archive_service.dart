import 'package:vaultexplorer/core/filesystem/case_collision.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:vaultexplorer/core/api/vault_archive_api.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
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

  // ── Split archives ──────────────────────────────────────────────────────

  static final RegExp _numberedPartName = RegExp(
    r'^.+\.(7z|zip)\.\d{3,}$',
    caseSensitive: false,
  );
  static final RegExp _spannedPartName = RegExp(
    r'^.+\.z\d{2,}$',
    caseSensitive: false,
  );

  /// True for a file named like one part of a split archive:
  /// `name.7z.001`, `name.zip.001` or `name.z01` (the last ZIP part is a plain
  /// `name.zip`; the native engine finds the other parts from it).
  static bool isSplitArchivePart(String fileName) =>
      _numberedPartName.hasMatch(fileName) ||
      _spannedPartName.hasMatch(fileName);

  /// The extension to route a file by, when it is a split archive part
  /// (`'7z'` / `'zip'`), else null. A part's real extension (`001`, `z01`) is
  /// not an archive extension on its own; `001` in particular is also what
  /// the file splitter writes for arbitrary files.
  static String? splitPartExtension(String fileName) {
    if (!isSplitArchivePart(fileName)) return null;
    return fileName.toLowerCase().contains('.7z.') ? '7z' : 'zip';
  }

  /// The first existing name that would collide with the parts of a split
  /// archive called [archiveName] ("name.zip" -> name.z01, name.z02, ...;
  /// "name.7z" -> name.7z.001, ...), or null. Parts are never overwritten.
  static String? existingSplitPartName(
    String archiveName,
    ArchiveFormatType format,
    Iterable<String> existingNames,
  ) {
    final lower = archiveName.toLowerCase();
    final String pattern;
    if (format == ArchiveFormatType.zip) {
      final stem = lower.endsWith('.zip')
          ? lower.substring(0, lower.length - 4)
          : lower;
      pattern = '^${RegExp.escape(stem)}\\.z\\d{2,}\$';
    } else {
      pattern = '^${RegExp.escape(lower)}\\.\\d{3,}\$';
    }
    final re = RegExp(pattern);
    for (final name in existingNames) {
      if (re.hasMatch(name.toLowerCase())) return name;
    }
    return null;
  }

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
    // The native bulk extractor writes to a regular filesystem path or a
    // mounted vault, but it cannot address a SAF tree URI as a destination.
    // Sidebar storage locations can be SAF-backed even though they represent
    // ordinary local folders, so use the per-entry file-IO path for them.
    if (!container.isSafStorage) {
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
    }

    int count = 0;
    final ensuredDirs = <String>{};

    final subDirs = archiveContext.getSubDirectories(subPath);
    for (final dirPath in subDirs) {
      final relativePath = subPath.isEmpty
          ? dirPath
          : dirPath.substring(subPath.length + 1);
      if (relativePath.isEmpty) continue;

      final destDir = targetDirInContainer.isEmpty
          ? relativePath
          : '$targetDirInContainer/$relativePath';

      await _ensureDirectory(container, destDir, ensuredDirs);
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

      await _ensureDirectory(container, p.posix.dirname(destPath), ensuredDirs);

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
    final selectedDestinations = _selectedExtractDestinations(
      archiveContext.allEntries
          .where((entry) => !entry.isDirectory)
          .map((entry) => _cleanArchiveEntryPath(entry.path)),
      entryPaths,
    );

    final ensuredDirs = <String>{};
    for (final mapping in selectedDestinations.entries) {
      final destPath = targetDirInContainer.isEmpty
          ? mapping.value
          : '$targetDirInContainer/${mapping.value}';

      await _ensureDirectory(container, p.posix.dirname(destPath), ensuredDirs);

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

  /// Maps each selected archive entry path to its copy destination path.
  /// Archive paths are rooted at the archive root, while a copied selection
  /// should retain only the selected item's name and its descendants. For
  /// example, selecting `sub/sub1/sub2` maps
  /// `sub/sub1/sub2/file.txt` to `sub2/file.txt`.
  static Map<String, String> _selectedExtractDestinations(
    Iterable<String> entryPaths,
    List<String> selectedEntryPaths,
  ) {
    final files = entryPaths.toList();
    final destinations = <String, String>{};

    for (final rawSelectedPath in selectedEntryPaths) {
      final selectedPath = _cleanArchiveEntryPath(rawSelectedPath);
      if (selectedPath.isEmpty) continue;

      final matches = files.where(
        (filePath) =>
            filePath == selectedPath || filePath.startsWith('$selectedPath/'),
      );
      final selectedName = p.posix.basename(selectedPath);

      for (final filePath in matches) {
        final relativePath = filePath == selectedPath
            ? ''
            : filePath.substring(selectedPath.length + 1);
        final destinationPath = relativePath.isEmpty
            ? selectedName
            : p.posix.join(selectedName, relativePath);
        destinations.putIfAbsent(filePath, () => destinationPath);
      }
    }

    // Keep the previous best-effort behavior when a selected path doesn't
    // match the scan result; ArchiveContext will report the missing entry.
    if (destinations.isEmpty) {
      for (final rawSelectedPath in selectedEntryPaths) {
        final selectedPath = _cleanArchiveEntryPath(rawSelectedPath);
        if (selectedPath.isNotEmpty) {
          destinations.putIfAbsent(
            selectedPath,
            () => p.posix.basename(selectedPath),
          );
        }
      }
    }

    return destinations;
  }

  static String _cleanArchiveEntryPath(String path) {
    var clean = path.replaceAll('\\', '/');
    while (clean.startsWith('/')) {
      clean = clean.substring(1);
    }
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    return clean;
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
    final files = archiveContext.allEntries
        .where((e) => !e.isDirectory)
        .map((e) => _cleanArchiveEntryPath(e.path))
        .toList();

    if (selectedEntryPaths != null && selectedEntryPaths.isNotEmpty) {
      return _selectedExtractDestinations(files, selectedEntryPaths);
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
    final ensuredDirs = <String>{};
    for (final mapping in destRelByEntryPath.entries) {
      final destPath = targetDirInContainer.isEmpty
          ? mapping.value
          : '$targetDirInContainer/${mapping.value}';

      await _ensureDirectory(container, p.posix.dirname(destPath), ensuredDirs);

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

  /// Creates [dirPath] and every missing ancestor inside [container],
  /// parents first.
  ///
  /// `createDirectory` is **not** recursive on vaults (Cryptomator, gocryptfs,
  /// CryFS), disk-image volumes or SAF folders: it fails when the parent
  /// folder doesn't exist yet. Plain device storage only appears to be
  /// recursive because its file writes create missing parents themselves.
  /// So extracting `sub1/sub2/a.txt` has to create `sub1` before `sub1/sub2`
  /// (and the destination folder itself, e.g. when "extract into subfolder"
  /// targets a folder that doesn't exist yet), rather than only the file's
  /// immediate parent.
  ///
  /// [ensured] remembers the folders already handled during one extraction,
  /// so each folder costs a single call instead of one per file inside it.
  /// The result of `createDirectory` is deliberately ignored: "already
  /// exists" reports failure on some backends, and a folder that really
  /// couldn't be created surfaces as the file write failing right after.
  static Future<void> _ensureDirectory(
    MountedContainer container,
    String dirPath,
    Set<String> ensured,
  ) async {
    var current = '';
    for (final segment in dirPath.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      current = current.isEmpty ? segment : '$current/$segment';
      if (!ensured.add(current)) continue;
      await _fileIo.createDirectory(container, current);
    }
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
    int? splitSizeBytes,
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
      splitSizeBytes: splitSizeBytes,
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
          srcPaths.add(
            container.isRawLocal
                ? p.join(container.uri, childContainerPath)
                : childContainerPath,
          );
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
        srcPaths.add(
          container.isRawLocal
              ? p.join(container.uri, containerPath)
              : containerPath,
        );
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
      destFilePath: container.isRawLocal
          ? p.join(container.uri, destPathInContainer)
          : null,
      passphrase: passphrase,
      opId: opId,
    );

    if (!ok) {
      throw Exception('Failed to create archive');
    }
    return srcPaths.length;
  }
}
