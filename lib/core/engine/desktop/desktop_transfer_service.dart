import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:ve_desktop_transfer/ve_desktop_transfer.dart';
import 'package:vaultexplorer/core/api/local_file_io_backend.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_staging_manager.dart';
import 'package:vaultexplorer/core/engine/desktop/ve_native.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/full_res_image_cache.dart';

/// Item descriptor passed to [DesktopTransferService] when initiating an
/// outbound drag or OS clipboard file copy.
class DesktopTransferEntry {
  const DesktopTransferEntry({
    required this.container,
    required this.vaultPath,
    required this.name,
    required this.isDir,
    required this.sizeBytes,
    required this.modifiedSecs,
  });

  final MountedContainer container;
  final String vaultPath;
  final String name;
  final bool isDir;
  final int sizeBytes;
  final int modifiedSecs;
}

/// High-level coordinator bridging VaultExplorer's encrypted VFS/storage model
/// with [DesktopStagingManager] and the native [VeDesktopTransfer] plugin on
/// Windows and Linux.
class DesktopTransferService {
  DesktopTransferService._({
    DesktopStagingManager? staging,
    VeDesktopTransfer? plugin,
  }) : staging = staging ?? DesktopStagingManager(),
       _plugin = plugin ?? VeDesktopTransfer.instance;

  /// Creates an isolated instance for unit tests.
  @visibleForTesting
  factory DesktopTransferService.forTesting({
    required DesktopStagingManager staging,
    VeDesktopTransfer? plugin,
  }) => DesktopTransferService._(staging: staging, plugin: plugin);

  static final DesktopTransferService instance = DesktopTransferService._();

  static const LocalFileIoBackend _localBackend = LocalFileIoBackend();

  final DesktopStagingManager staging;
  final VeDesktopTransfer _plugin;

  bool _hooksBound = false;
  Future<bool>? _initFuture;
  String? _activeClipboardBatchId;
  int? _clipboardImageVolId;
  Timer? _clipboardImageTimer;
  String? _nonOsCopyWatermark;
  ({int volId, String sourceDir, String stagingDir, DateTime at})?
  _recentOutboundDrag;
  final Map<String, int> _pinnedImportDirs = <String, int>{};

  bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  bool get isSupported => _plugin.isSupportedPlatform && _plugin.isSupported;

  String get backend => _plugin.backend;

  /// Binds staging/cleanup callbacks and initializes the native plugin. Safe
  /// to call repeatedly or concurrently.
  Future<bool> ensureInitialized() {
    if (!isSupportedPlatform) return Future<bool>.value(false);
    _bindCallbacksOnce();
    if (_plugin.isInitialized) {
      return Future<bool>.value(_plugin.isSupported);
    }
    return _initFuture ??= _doInitialize();
  }

  void _bindCallbacksOnce() {
    if (_hooksBound) return;
    _hooksBound = true;

    _plugin.onBatchRealized = (batchId, _) {
      final batch = staging.batchOf(batchId);
      if (batch == null) return;
      staging.markRealized(batchId, isDrag: !batch.isClipboard);
    };

    _plugin.onBatchTransferFinished = (batchId, _, immediateIfUnused) {
      unawaited(
        staging.onDragTransferFinished(
          batchId,
          immediateIfUnused: immediateIfUnused,
        ),
      );
    };

    _plugin.onClipboardOwnershipLost = (batchId) {
      if (_activeClipboardBatchId == batchId) {
        _activeClipboardBatchId = null;
      }
      unawaited(staging.onClipboardOwnershipLost(batchId));
    };

    staging.configurePlatformHooks(
      isBatchInUse: (dirPath) async {
        if (isStagingDirPinned(dirPath)) return true;
        return _plugin.isStagingBatchInUse(dirPath);
      },
      hardenDir: _plugin.hardenStagingDir,
      cancelNativeBatch: _plugin.cancelBatch,
      releaseClipboardBatch: (batchId) async {
        if (_activeClipboardBatchId == batchId) {
          _activeClipboardBatchId = null;
        }
        await _plugin.clearClipboardIfBatch(batchId: batchId);
      },
    );
  }

  Future<bool> _doInitialize() async {
    final enginePath = VeNative.resolveExistingLibraryPath();
    final ok = await _plugin.initialize(engineLibraryPath: enginePath);
    if (!ok) {
      _initFuture = null;
    }
    return ok;
  }

  /// Purges leftover un-locked staging directories from crashed sessions.
  Future<int> purgeStaleAtStartup() async {
    if (!isSupportedPlatform) return 0;
    await ensureInitialized();
    return staging.purgeStaleAtStartup();
  }

  /// Immediately clears OS clipboard references and securely wipes any staged
  /// scratch files belonging to [volId] when the vault locks.
  Future<void> onVolumeLocked(int volId) async {
    if (!isSupportedPlatform) return;
    final clearImage = _clipboardImageVolId == volId;
    if (clearImage) {
      _clearClipboardImageTimer();
      _clipboardImageVolId = null;
    }
    await _plugin.clearClipboardIfBatch(volId: volId, clearImage: clearImage);
    await staging.cleanupVolume(volId);
  }

  /// Immediately clears all active staging directories on application exit.
  Future<void> dispose() async {
    _clearClipboardImageTimer();
    _clipboardImageVolId = null;
    _activeClipboardBatchId = null;
    if (!isSupportedPlatform) return;
    await staging.cleanupAll();
  }

  /// Builds a lazy [TransferManifest] from [entries]. Encrypted vault entries
  /// allocate an empty [StagingBatch] with zero decryption; plain LocalStorage
  /// entries use host paths directly with zero staging.
  @visibleForTesting
  Future<({TransferManifest manifest, StagingBatch? batch})?> createManifest({
    required List<DesktopTransferEntry> items,
    required bool isClipboard,
    bool preferVirtualStream = false,
    Duration? clipboardTimeout,
  }) async {
    if (items.isEmpty) return null;

    // A native transfer batch targets one engine slot (or LocalStorage).
    final primary = items.first.container;
    final scoped = items
        .where((e) => e.container.volId == primary.volId)
        .toList(growable: false);
    if (scoped.isEmpty) return null;

    final isLocal = primary.isLocalStorage;
    if (isLocal && !primary.isRawLocal) {
      return null;
    }

    StagingBatch? batch;
    if (!isLocal) {
      batch = await staging.createBatch(
        volId: primary.volId,
        isClipboard: isClipboard,
        clipboardTimeout: clipboardTimeout,
      );
    }

    final batchId = batch?.batchId ??
        'local_${DateTime.now().microsecondsSinceEpoch}';
    final manifestItems = <TransferManifestItem>[
      for (final item in scoped)
        TransferManifestItem(
          vaultPath: item.vaultPath,
          name: _leafName(item.name, item.vaultPath),
          isDir: item.isDir,
          sizeBytes: item.isDir ? 0 : item.sizeBytes,
          modifiedSecs: item.modifiedSecs,
          localPath: isLocal
              ? p.normalize(_localBackend.resolve(primary.uri, item.vaultPath))
              : null,
        ),
    ];

    return (
      manifest: TransferManifest(
        batchId: batchId,
        volId: isLocal ? -1 : primary.volId,
        stagingDir: batch?.dirPath ?? '',
        items: manifestItems,
        preferVirtualStream: !isLocal && preferVirtualStream,
        isSensitive: !isLocal,
      ),
      batch: batch,
    );
  }

  /// Starts a native OS drag-and-drop operation for [items] from [viewId].
  /// Returns `"copied"`, `"cancelled"`, `"error"`, or `"unsupported"`.
  Future<String> startOutboundDrag({
    required int viewId,
    required List<DesktopTransferEntry> items,
    bool preferVirtualStream = false,
  }) async {
    if (!isSupportedPlatform || items.isEmpty) return 'unsupported';
    if (!await ensureInitialized()) return 'unsupported';

    final built = await createManifest(
      items: items,
      isClipboard: false,
      preferVirtualStream: preferVirtualStream,
    );
    if (built == null) return 'unsupported';

    final sourceDir = items.first.vaultPath.contains('/')
        ? items.first.vaultPath.substring(
            0,
            items.first.vaultPath.lastIndexOf('/'),
          )
        : '';
    if (built.batch != null) {
      _recentOutboundDrag = (
        volId: items.first.container.volId,
        sourceDir: sourceDir,
        stagingDir: built.batch!.dirPath,
        at: DateTime.now(),
      );
    }

    final result = await _plugin.startDrag(
      viewId: viewId,
      manifest: built.manifest,
    );

    final batch = built.batch;
    if (batch != null) {
      _recentOutboundDrag = (
        volId: items.first.container.volId,
        sourceDir: sourceDir,
        stagingDir: batch.dirPath,
        at: DateTime.now(),
      );
      if (!batch.disposed &&
          (result == 'cancelled' ||
              result == 'error' ||
              result == 'unsupported')) {
        await staging.onDragTransferFinished(
          batch.batchId,
          immediateIfUnused: true,
        );
      }
    }
    return result;
  }

  /// Returns `true` when [paths] came from an active/recent OS drag that
  /// originated in the exact same vault volume and folder (e.g. a user nudged
  /// past a window edge then dropped back on the same list).
  bool isSameOriginDrop(
    List<String> paths, {
    required int destVolId,
    required String destDirPath,
  }) {
    final recent = _recentOutboundDrag;
    if (recent == null) return false;
    if (DateTime.now().difference(recent.at) > const Duration(minutes: 2)) {
      _recentOutboundDrag = null;
      return false;
    }
    if (recent.volId != destVolId || recent.sourceDir != destDirPath) {
      return false;
    }
    if (paths.isEmpty) return false;
    return paths.every((path) => p.isWithin(recent.stagingDir, path));
  }

  /// Returns `true` when any path in [paths] points inside an active staging
  /// directory or VaultExplorer's staging prefix.
  bool containsStagedPath(List<String> paths) {
    if (paths.isEmpty) return false;
    final rootPrefix = p.join(
      staging.resolveStagingRoot().path,
      DesktopStagingManager.batchDirPrefix,
    );
    for (final raw in paths) {
      final path = p.normalize(raw);
      for (final batch in staging.activeBatches) {
        if (p.equals(batch.dirPath, path) || p.isWithin(batch.dirPath, path)) {
          return true;
        }
      }
      if (path.startsWith(rootPrefix)) return true;
    }
    return false;
  }

  /// Prevents staged batches containing [paths] from being wiped by the
  /// background grace-period cleaner while an internal drop import or conflict
  /// prompt is active. Returns the pinned batch directory keys to pass to
  /// [releaseImportPaths].
  List<String> retainImportPaths(List<String> paths) {
    if (paths.isEmpty || staging.activeBatches.isEmpty) return const [];
    final matched = <String>{};
    for (final raw in paths) {
      final path = p.normalize(raw);
      for (final batch in staging.activeBatches) {
        if (p.equals(batch.dirPath, path) || p.isWithin(batch.dirPath, path)) {
          matched.add(batch.dirPath);
        }
      }
    }
    for (final dirPath in matched) {
      _pinnedImportDirs[dirPath] = (_pinnedImportDirs[dirPath] ?? 0) + 1;
    }
    return matched.toList(growable: false);
  }

  /// Releases staging directory pins acquired by [retainImportPaths].
  void releaseImportPaths(List<String> pinnedDirs) {
    for (final dirPath in pinnedDirs) {
      final current = _pinnedImportDirs[dirPath];
      if (current == null || current <= 1) {
        _pinnedImportDirs.remove(dirPath);
      } else {
        _pinnedImportDirs[dirPath] = current - 1;
      }
    }
  }

  /// Whether an active in-app drop import is pinning [dirPath].
  @visibleForTesting
  bool isStagingDirPinned(String dirPath) =>
      (_pinnedImportDirs[dirPath] ?? 0) > 0;

  /// Populates the OS clipboard with lazy file references for [items].
  Future<bool> copyFilesToOsClipboard({
    required List<DesktopTransferEntry> items,
    Duration? autoClearTimeout,
  }) async {
    if (!isSupportedPlatform || items.isEmpty) return false;
    if (!await ensureInitialized()) return false;

    final previousBatchId = _activeClipboardBatchId;
    _activeClipboardBatchId = null;
    _clearClipboardImageTimer();
    _clipboardImageVolId = null;

    final built = await createManifest(
      items: items,
      isClipboard: true,
      clipboardTimeout: autoClearTimeout,
    );
    if (built == null) return false;

    final ok = await _plugin.setClipboardFiles(manifest: built.manifest);
    if (!ok) {
      if (built.batch != null) {
        await staging.cleanupBatch(built.batch!.batchId);
      }
      return false;
    }

    if (built.batch != null) {
      _activeClipboardBatchId = built.batch!.batchId;
    }
    if (previousBatchId != null && previousBatchId != _activeClipboardBatchId) {
      unawaited(staging.onClipboardOwnershipLost(previousBatchId));
    }
    return true;
  }

  /// Decodes an encrypted or local image fully in memory and places both PNG
  /// and DIB/RGBA representations on the OS clipboard without temp disk files.
  Future<bool> copyImageToOsClipboard({
    required MountedContainer container,
    required String vaultPath,
    required VaultFileIoApi fileIoApi,
    Duration? autoClearTimeout,
    bool? sensitiveOverride,
  }) async {
    if (!isSupportedPlatform) return false;
    if (!await ensureInitialized()) return false;

    Uint8List? rawBytes;
    if (!FullResImageCache.isLargeImagePreview(container, vaultPath)) {
      rawBytes = FullResImageCache.get(container, vaultPath);
    }
    rawBytes ??= await fileIoApi.readWholeFile(container, vaultPath);
    if (rawBytes == null || rawBytes.isEmpty) return false;

    final sensitive = sensitiveOverride ?? !container.isLocalStorage;
    final payload = await encodeClipboardImagePayload(
      rawBytes,
      sensitive: sensitive,
    );
    if (payload == null) return false;

    final previousBatchId = _activeClipboardBatchId;
    _activeClipboardBatchId = null;
    _clearClipboardImageTimer();

    final ok = await _plugin.setClipboardImage(payload);
    if (!ok) return false;

    if (previousBatchId != null) {
      unawaited(staging.onClipboardOwnershipLost(previousBatchId));
    }

    if (sensitive) {
      final volId = container.volId;
      _clipboardImageVolId = volId;
      final timeout = autoClearTimeout ?? staging.defaultClipboardTimeout;
      if (timeout > Duration.zero) {
        _clipboardImageTimer = Timer(timeout, () {
          if (_clipboardImageVolId == volId) {
            _clipboardImageVolId = null;
            unawaited(
              _plugin.clearClipboardIfBatch(volId: volId, clearImage: true),
            );
          }
        });
      }
    } else {
      _clipboardImageVolId = null;
    }
    return true;
  }

  /// Decodes compressed image bytes into an in-memory [ClipboardImagePayload]
  /// containing both PNG and 32-bit RGBA pixel data.
  @visibleForTesting
  static Future<ClipboardImagePayload?> encodeClipboardImagePayload(
    Uint8List encodedBytes, {
    bool sensitive = true,
  }) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(encodedBytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        final codec = await descriptor.instantiateCodec();
        try {
          final frame = await codec.getNextFrame();
          try {
            final image = frame.image;
            final rgbaData = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            if (rgbaData == null) return null;

            Uint8List pngBytes;
            if (_looksLikePng(encodedBytes)) {
              pngBytes = encodedBytes;
            } else {
              final pngData = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              if (pngData == null) return null;
              pngBytes = pngData.buffer.asUint8List(
                pngData.offsetInBytes,
                pngData.lengthInBytes,
              );
            }

            return ClipboardImagePayload(
              pngBytes: pngBytes,
              rgbaBytes: rgbaData.buffer.asUint8List(
                rgbaData.offsetInBytes,
                rgbaData.lengthInBytes,
              ),
              width: image.width,
              height: image.height,
              sensitive: sensitive,
            );
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } catch (e) {
      debugPrint('[desktop-transfer] image encode failed: $e');
      return null;
    } finally {
      buffer.dispose();
    }
  }

  static bool _looksLikePng(Uint8List bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A;

  void _clearClipboardImageTimer() {
    _clipboardImageTimer?.cancel();
    _clipboardImageTimer = null;
  }

  /// Records the external OS clipboard fingerprint at the time an internal-only
  /// VaultExplorer clipboard operation (`Ctrl+X` cut or archive stage) ran so a
  /// subsequent `Ctrl+V` can detect whether an external app copied new items in
  /// the meantime.
  Future<void> markInternalNonOsClipboard() async {
    if (!isSupportedPlatform) return;
    if (!await ensureInitialized()) {
      _nonOsCopyWatermark = null;
      return;
    }
    final info = await _plugin.inspectClipboard();
    _nonOsCopyWatermark = _fingerprint(info);
  }

  /// Returns `true` if the current OS clipboard differs from the external
  /// snapshot captured when [markInternalNonOsClipboard] was called.
  bool hasExternalClipboardChangedSinceWatermark(ClipboardInspectResult info) {
    if (info.isOwnFiles) return false;
    final current = _fingerprint(info);
    if (_nonOsCopyWatermark == null) {
      return info.hasFiles || info.hasImage;
    }
    return current != _nonOsCopyWatermark && (info.hasFiles || info.hasImage);
  }

  static String _fingerprint(ClipboardInspectResult info) {
    if (info.isOwnFiles) return 'own:${info.ownBatchId ?? ""}';
    if (info.hasFiles) return 'files:${info.filePaths.join("\n")}';
    if (info.hasImage) return 'image';
    return 'none';
  }

  /// Inspects the OS clipboard for external files or images.
  Future<ClipboardInspectResult> inspectOsClipboard() async {
    if (!isSupportedPlatform) {
      return const ClipboardInspectResult(
        hasFiles: false,
        isOwnFiles: false,
        ownBatchId: null,
        filePaths: <String>[],
        hasImage: false,
      );
    }
    if (!await ensureInitialized()) {
      return const ClipboardInspectResult(
        hasFiles: false,
        isOwnFiles: false,
        ownBatchId: null,
        filePaths: <String>[],
        hasImage: false,
      );
    }
    return _plugin.inspectClipboard();
  }

  /// Returns `true` if the OS clipboard currently contains external files or an
  /// image suitable for pasting into VaultExplorer.
  Future<bool> hasOsPasteableContent() async {
    final info = await inspectOsClipboard();
    return (info.hasFiles && !info.isOwnFiles && info.filePaths.isNotEmpty) ||
        info.hasImage;
  }

  /// Reads raw clipboard image data normalized to PNG bytes, or `null`.
  Future<Uint8List?> readClipboardImagePng() async {
    if (!isSupportedPlatform) return null;
    if (!await ensureInitialized()) return null;
    return _plugin.readClipboardImagePng();
  }

  /// Writes PNG image bytes from the OS clipboard into [targetDirPath] inside
  /// [container] using a collision-free timestamped `.png` name, returning the
  /// created filename on success or `null` on failure.
  Future<String?> pasteImagePngToContainer({
    required MountedContainer container,
    required String targetDirPath,
    required VaultFileIoApi fileIoApi,
    required Uint8List pngBytes,
  }) async {
    if (pngBytes.isEmpty || container.readOnly) return null;
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stem =
        'pasted_image_${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}';

    String? fileName;
    String? targetPath;
    for (var suffix = 0; suffix < 100; suffix++) {
      final candidate = suffix == 0 ? '$stem.png' : '${stem}_${suffix + 1}.png';
      final full =
          targetDirPath.isEmpty ? candidate : '$targetDirPath/$candidate';
      final exists = await fileIoApi.entryExists(
        container,
        full,
        isDir: false,
      );
      if (!exists) {
        fileName = candidate;
        targetPath = full;
        break;
      }
    }
    if (fileName == null || targetPath == null) return null;

    const chunkSize = 4 * 1024 * 1024;
    var offset = 0;
    while (offset < pngBytes.length) {
      final end = (offset + chunkSize).clamp(0, pngBytes.length);
      final slice = Uint8List.sublistView(pngBytes, offset, end);
      if (!await fileIoApi.writeFileChunk(
        container,
        targetPath,
        offset,
        slice,
      )) {
        return null;
      }
      offset = end;
    }
    if (!await fileIoApi.finishWrite(container, targetPath)) {
      return null;
    }
    return fileName;
  }

  /// Places sensitive text on the OS clipboard with history/cloud exclusion
  /// hints.
  Future<bool> setSensitiveClipboardText(String text) async {
    if (!isSupportedPlatform) return false;
    if (!await ensureInitialized()) return false;
    return _plugin.setSensitiveClipboardText(text);
  }

  /// Clears sensitive text if it still matches [expectedText] (when provided).
  Future<bool> clearSensitiveClipboardText({String? expectedText}) async {
    if (!isSupportedPlatform) return false;
    if (!await ensureInitialized()) return false;
    return _plugin.clearSensitiveClipboardText(expectedText: expectedText);
  }

  static String _leafName(String name, String vaultPath) {
    if (name.isNotEmpty) return name;
    final norm = vaultPath.replaceAll('\\', '/');
    return p.posix.basename(norm);
  }
}
