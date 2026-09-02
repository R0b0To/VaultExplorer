// Extracted from vault_explorer_api_file_io.dart (old _FileIoOps mixin) as part of the Riverpod migration, Phase 2.
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_with_size.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

import 'local_file_io_backend.dart';
import 'vault_engine_types.dart';

/// File CRUD, thumbnails, import/export, and system-level calls.
///
/// Any call whose [MountedContainer] is [kDecoyLocalVolId] (real phone
/// storage, standing in via [buildLocalStorageContainer]) is diverted to
/// [_local] instead of the native channel: there's no vault session
/// registered for that sentinel volId, so a channel call would just fail.
/// [readWholeFile]/[writeWholeFile]/[createEmptyFile] are composed from
/// the primitives below, so patching those primitives is enough to make
/// them work for local storage too, with no changes of their own.
class VaultFileIoApi {
  final MethodChannel _channel;
  static const LocalFileIoBackend _local = LocalFileIoBackend();
  const VaultFileIoApi(this._channel);

  // ── File I/O ──────────────────────────────────────────────────────────────

  Future<bool> openWithApp(
    MountedContainer container,
    String fileName, {
    String? packageName,
    String? mimeType,
  }) async {
    final result = await _channel
        .invokeMethod<bool>(ChannelMethods.openWithApp, {
          'filePath': container.uri,
          'fileName': fileName,
          'packageName': packageName,
          'mimeType': mimeType,
        });
    return result ?? false;
  }

  Future<bool> decryptFile(
    MountedContainer container,
    String fileName,
    String destPath,
  ) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.decryptFile,
      {'filePath': container.uri, 'fileName': fileName, 'destPath': destPath},
    );
    return result ?? false;
  }

  Future<bool> exportFileToStorage(
    MountedContainer container,
    String sourcePath,
  ) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.exportFileToStorage,
      {'filePath': container.uri, 'sourcePath': sourcePath},
    );
    return result ?? false;
  }

  Future<bool> exportAppSettingsFile(String contents, String fileName) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.exportAppSettingsFile,
      {'contents': contents, 'fileName': fileName},
    );
    return result ?? false;
  }

  Future<String?> importAppSettingsFile() async {
    return _channel.invokeMethod<String>(ChannelMethods.importAppSettingsFile);
  }

  Future<int> getFileSize(MountedContainer container, String fileName) async {
    if (container.isLocalStorage) {
      return _local.getFileSize(container.uri, fileName);
    }
    final result = await _channel.invokeMethod<int>(
      ChannelMethods.getFileSize,
      {'filePath': container.uri, 'fileName': fileName},
    );
    return result ?? 0;
  }

  Future<int> getMediaFileSize(
    MountedContainer container,
    String fileName,
  ) async {
    if (container.isLocalStorage) {
      return _local.getFileSize(container.uri, fileName);
    }
    final result = await _channel.invokeMethod<int>(
      ChannelMethods.getMediaFileSize,
      {'filePath': container.uri, 'fileName': fileName},
    );
    return result ?? 0;
  }

  Future<int> getFolderSize(MountedContainer container, String dirPath) async {
    if (container.isLocalStorage) {
      return _local.getFolderSize(container.uri, dirPath);
    }
    final result = await _channel.invokeMethod<int>(
      ChannelMethods.getFolderSize,
      {'filePath': container.uri, 'dirPath': dirPath},
    );
    return result ?? 0;
  }

  Future<Uint8List?> readFileChunk(
    MountedContainer container,
    String fileName,
    int offset,
    int length,
  ) async {
    if (container.isLocalStorage) {
      return _local.readFileChunk(container.uri, fileName, offset, length);
    }
    final result = await _channel
        .invokeMethod<Uint8List>(ChannelMethods.readFileChunk, {
          'filePath': container.uri,
          'fileName': fileName,
          'offset': offset,
          'length': length,
        });
    return result;
  }

  Future<Uint8List?> readMediaFileChunk(
    MountedContainer container,
    String fileName,
    int offset,
    int length,
  ) async {
    if (container.isLocalStorage) {
      return _local.readFileChunk(container.uri, fileName, offset, length);
    }
    final result = await _channel
        .invokeMethod<Uint8List>(ChannelMethods.readMediaFileChunk, {
          'filePath': container.uri,
          'fileName': fileName,
          'offset': offset,
          'length': length,
        });
    return result;
  }

  Future<Uint8List?> getImageThumbnail(
    MountedContainer container,
    String fileName, {
    int targetSize = 180,
    int quality = 70,
  }) async {
    if (container.isLocalStorage) {
      return _local.getImageThumbnail(
        container.uri,
        fileName,
        targetSize: targetSize,
      );
    }
    try {
      final Uint8List? bytes = await _channel
          .invokeMethod<Uint8List>('getImageThumbnail', {
            'filePath': container.uri,
            'fileName': fileName,
            'targetSize': targetSize,
            'quality': quality,
          });
      return bytes;
    } catch (e) {
      logSwallowed('getImageThumbnail', e, expected: true);
      return null;
    }
  }

  /// For local storage, [LocalFileIoBackend.getImageThumbnailWithSize]
  /// reports the real decoded pixel size (same as the native channel
  /// method does for vault content) so masonry-layout tiles size
  /// correctly before the image itself has loaded.
  Future<ThumbnailWithSize?> getImageThumbnailWithSize(
    MountedContainer container,
    String fileName, {
    int targetSize = 180,
    int quality = 70,
  }) async {
    if (container.isLocalStorage) {
      final result = await _local.getImageThumbnailWithSize(
        container.uri,
        fileName,
        targetSize: targetSize,
      );
      return result == null
          ? null
          : ThumbnailWithSize(
              bytes: result.bytes,
              width: result.width,
              height: result.height,
            );
    }
    try {
      final result = await _channel
          .invokeMethod(ChannelMethods.getImageThumbnailWithSize, {
            'filePath': container.uri,
            'fileName': fileName,
            'targetSize': targetSize,
            'quality': quality,
          });
      return ThumbnailWithSize.fromChannelResult(result);
    } catch (e) {
      logSwallowed('getImageThumbnailWithSize', e, expected: true);
      return null;
    }
  }

  Future<List<String>?> listDirectory(
    MountedContainer container,
    String dirPath, {
    bool refresh = false,
  }) async {
    if (container.isLocalStorage) {
      return _local.listDirectory(container.uri, dirPath);
    }
    final result = await _channel.invokeMethod<List<Object?>>(
      ChannelMethods.listDirectory,
      {'filePath': container.uri, 'dirPath': dirPath, 'refresh': refresh},
    );
    return result?.cast<String>();
  }

  Future<bool> createDirectory(
    MountedContainer container,
    String dirPath,
  ) async {
    if (container.isLocalStorage) {
      return _local.createDirectory(container.uri, dirPath);
    }
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.createDirectory,
      {'filePath': container.uri, 'dirPath': dirPath},
    );
    return result ?? false;
  }

  Future<bool> renameFile(
    MountedContainer container,
    String oldPath,
    String newPath,
  ) async {
    if (container.isLocalStorage) {
      return _local.renameFile(container.uri, oldPath, newPath);
    }
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.renameFile,
      {'filePath': container.uri, 'oldPath': oldPath, 'newPath': newPath},
    );
    return result ?? false;
  }

  Future<bool> copyFile(
    MountedContainer src,
    String srcPath,
    MountedContainer dest,
    String destPath, {
    int opId = 0,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>(ChannelMethods.copyFile, {
        'srcUri': src.uri,
        'srcPath': srcPath,
        'destUri': dest.uri,
        'destPath': destPath,
        'opId': opId,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancelCopy(int opId) async {
    try {
      await _channel.invokeMethod(ChannelMethods.cancelCopy, {'opId': opId});
    } catch (e) {
      logSwallowed('cancelCopy', e, expected: true);
    }
  }

  /// Called once a whole copy/move [FileOperation] finishes (success,
  /// failure, or cancellation) -- NOT per file. Clears CopyCancellation
  /// and CopyProgressBridge's native-side state for this opId; clearing
  /// mid-operation would incorrectly "un-cancel" other items still
  /// copying under the same shared opId (see CopyProgressBridge.flushPending
  /// for the per-file equivalent, which copyFile already triggers on its
  /// own after each native call returns).
  Future<void> clearCopyState(int opId) async {
    try {
      await _channel.invokeMethod(ChannelMethods.clearCopyState, {
        'opId': opId,
      });
    } catch (e) {
      logSwallowed('clearCopyState', e, expected: true);
    }
  }

  Future<bool> writeFileChunk(
    MountedContainer container,
    String fileName,
    int offset,
    Uint8List data,
  ) async {
    if (container.isLocalStorage) {
      return _local.writeFileChunk(container.uri, fileName, offset, data);
    }
    final result = await _channel.invokeMethod<bool>('writeFileChunk', {
      'filePath': container.uri,
      'fileName': fileName,
      'offset': offset,
      'data': data,
    });
    return result ?? false;
  }

  /// Commits a completed write sequence. Folder-based vault engines need
  /// this explicit flush; block-based engines treat it as a no-op -- so
  /// does plain local storage, which has nothing to flush either.
  Future<bool> finishWrite(MountedContainer container, String fileName) async {
    if (container.isLocalStorage) return true;
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.finishWrite,
        {'volId': container.volId, 'path': fileName},
      );
      return success ?? true;
    } catch (e) {
      logSwallowed('finishWrite', e);
      return true;
    }
  }

  Future<bool> deleteFile(MountedContainer container, String fileName) async {
    if (container.isLocalStorage) {
      return _local.deleteFile(container.uri, fileName);
    }
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.deleteFile,
      {'filePath': container.uri, 'fileName': fileName},
    );
    return result ?? false;
  }

  Future<bool> setLastModifiedTime(
    MountedContainer container,
    String fileName,
    int epochSeconds,
  ) async {
    if (container.isLocalStorage) {
      return _local.setLastModifiedTime(container.uri, fileName, epochSeconds);
    }
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.setLastModifiedTime,
      {
        'filePath': container.uri,
        'fileName': fileName,
        'epochSeconds': epochSeconds,
      },
    );
    return result ?? false;
  }

  Future<bool> writeBackFile(
    MountedContainer container,
    String fileName,
    String sourcePath,
  ) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.writeBackFile,
      {
        'filePath': container.uri,
        'fileName': fileName,
        'sourcePath': sourcePath,
      },
    );
    return result ?? false;
  }

  Future<bool> createEmptyFile(
    MountedContainer container,
    String fileName,
  ) async {
    final ok = await writeFileChunk(container, fileName, 0, Uint8List(0));
    if (!ok) return false;
    return finishWrite(container, fileName);
  }

  static const int _wholeFileChunkSize = 8 * 1024 * 1024; // 8 MB

  Future<Uint8List?> readWholeFile(
    MountedContainer container,
    String fileName,
  ) async {
    final size = await getFileSize(container, fileName);
    if (size < 0) return null;
    if (size == 0) return Uint8List(0);

    final builder = BytesBuilder(copy: false);
    var offset = 0;
    while (offset < size) {
      final remaining = size - offset;
      final len = remaining > _wholeFileChunkSize
          ? _wholeFileChunkSize
          : remaining;
      final chunk = await readFileChunk(container, fileName, offset, len);
      if (chunk == null || chunk.isEmpty) return null;
      builder.add(chunk);
      offset += chunk.length;
    }
    return builder.takeBytes();
  }

  Future<bool> writeWholeFile(
    MountedContainer container,
    String fileName,
    Uint8List bytes,
  ) async {
    final tmpPath = '$fileName.tmp';
    await deleteFile(container, tmpPath);

    var offset = 0;
    do {
      final remaining = bytes.length - offset;
      final len = remaining > _wholeFileChunkSize
          ? _wholeFileChunkSize
          : remaining;
      final chunk = Uint8List.sublistView(bytes, offset, offset + len);
      final ok = await writeFileChunk(container, tmpPath, offset, chunk);
      if (!ok) {
        await deleteFile(container, tmpPath);
        return false;
      }
      offset += len;
    } while (offset < bytes.length);

    final finished = await finishWrite(container, tmpPath);
    if (!finished) {
      await deleteFile(container, tmpPath);
      return false;
    }

    await deleteFile(container, fileName);
    return renameFile(container, tmpPath, fileName);
  }

  /// No local-storage branch: `dart:io` has no cross-platform way to read
  /// a volume's free/total space, so callers get `null` for real device
  /// storage the same as they would for any other unavailable stat -- the
  /// stats bar already handles a `null` result by simply not showing a
  /// free-space figure.
  Future<List<int>?> getSpaceInfo(MountedContainer container) async {
    if (container.isLocalStorage) return null;
    final result = await _channel.invokeMethod<List<Object?>>(
      ChannelMethods.getSpaceInfo,
      {'filePath': container.uri},
    );
    return result?.cast<int>();
  }

  Future<Map<String, dynamic>?> getVaultInfo(String uri) async {
    return _channel.invokeMapMethod<String, dynamic>(
      ChannelMethods.getVaultInfo,
      {'filePath': uri},
    );
  }

  /// Launches the system multi-file picker and reports back any picked
  /// names that already exist in [targetPath] -- nothing is imported yet.
  /// Returns `null` if the user backed out of the picker without
  /// choosing anything.
  ///
  /// Follow up with [importFiles], passing the returned
  /// [ImportPickResult.pickToken] and a resolution for every conflict, to
  /// actually copy the picked files. If the caller decides not to
  /// proceed (e.g. the person cancels the conflict-resolution sheet),
  /// call [cancelPickedImport] with the same token so native can release
  /// the picked documents instead of holding them until the app process
  /// ends.
  Future<ImportPickResult?> pickFilesForImport(
    MountedContainer container,
    String targetPath,
  ) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      ChannelMethods.pickImportFiles,
      {'filePath': container.uri, 'targetPath': targetPath},
    );
    return _importPickResultFromChannel(result);
  }

  /// Same idea as [pickFilesForImport] but for a single folder chosen via
  /// the system tree picker -- [ImportPickResult.conflicts] has at most
  /// one entry (the folder's own name).
  Future<ImportPickResult?> pickFolderForImport(
    MountedContainer container,
    String targetPath,
  ) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      ChannelMethods.pickImportFolder,
      {'filePath': container.uri, 'targetPath': targetPath},
    );
    return _importPickResultFromChannel(result);
  }

  ImportPickResult? _importPickResultFromChannel(Map<String, dynamic>? result) {
    if (result == null) return null;
    final pickToken = result['pickToken'] as int?;
    if (pickToken == null) return null;
    final rawConflicts = (result['conflicts'] as List?) ?? const [];
    final rawItems = (result['items'] as List?) ?? const [];
    return (
      pickToken: pickToken,
      conflicts: rawConflicts.map((c) {
        final map = c as Map<Object?, Object?>;
        return (
          name: map['name'] as String,
          destIsDir: map['destIsDir'] as bool? ?? false,
        );
      }).toList(),
      items: rawItems.map((item) {
        final map = item as Map<Object?, Object?>;
        return ClipboardItem(
          path: map['name'] as String? ?? '',
          isDir: map['isDir'] as bool? ?? false,
          sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
        );
      }).toList(),
    );
  }

  /// Releases a pick from [pickFilesForImport]/[pickFolderForImport] that
  /// will never be completed by [importFiles]/[importFolder] -- e.g. the
  /// person dismissed the conflict-resolution sheet instead of
  /// continuing. Safe to call with an already-completed or unknown
  /// [pickToken]; native just no-ops.
  Future<void> cancelPickedImport(int pickToken) async {
    try {
      await _channel.invokeMethod(ChannelMethods.cancelPickedImport, {
        'pickToken': pickToken,
      });
    } catch (e) {
      logSwallowed('cancelPickedImport', e, expected: true);
    }
  }

  /// Copies the files picked by an earlier [pickFilesForImport] call
  /// (identified by [pickToken]) into [targetPath]. [conflictPlan] maps
  /// each lowercased colliding name (as reported in that call's
  /// [ImportPickResult.conflicts]) to "skip" / "overwrite" / "keepBoth";
  /// any picked name *not* in [conflictPlan] didn't collide with
  /// anything and is imported as-is (auto-uniquified only if it
  /// happens to collide with another file in the same picked batch).
  Future<int> importFiles(
    MountedContainer container,
    String targetPath,
    int opId,
    int pickToken, {
    Map<String, String> conflictPlan = const {},
  }) async {
    final result = await _channel.invokeMethod<int>(ChannelMethods.importFile, {
      'filePath': container.uri,
      'targetPath': targetPath,
      'opId': opId,
      'pickToken': pickToken,
      'conflictPlan': conflictPlan,
    });
    return result ?? 0;
  }

  Future<int> exportSelectedToFolder(
    MountedContainer container,
    List<Map<String, dynamic>> items, {
    int opId = 0,
  }) async {
    final result = await _channel.invokeMethod<int>(
      ChannelMethods.exportFilesToFolder,
      {'filePath': container.uri, 'items': items, 'opId': opId},
    );
    return result ?? 0;
  }

  Future<void> cancelExport(int opId) async {
    try {
      await _channel.invokeMethod(ChannelMethods.cancelExport, {'opId': opId});
    } catch (e) {
      logSwallowed('cancelExport', e, expected: true);
    }
  }

  /// Copies the folder picked by an earlier [pickFolderForImport] call
  /// (identified by [pickToken]) into [targetPath]. See [importFiles] for
  /// what [conflictPlan] means -- here it has at most one entry, for the
  /// folder's own name.
  Future<int> importFolder(
    MountedContainer container,
    String targetPath,
    int opId,
    int pickToken, {
    Map<String, String> conflictPlan = const {},
  }) async {
    final result = await _channel
        .invokeMethod<int>(ChannelMethods.importFolder, {
          'filePath': container.uri,
          'targetPath': targetPath,
          'opId': opId,
          'pickToken': pickToken,
          'conflictPlan': conflictPlan,
        });
    return result ?? 0;
  }

  Future<void> cancelImport(int opId) async {
    try {
      await _channel.invokeMethod(ChannelMethods.cancelImport, {'opId': opId});
    } catch (e) {
      logSwallowed('cancelImport', e, expected: true);
    }
  }

  Future<int> deleteImportSources(int opId) async {
    try {
      final result = await _channel.invokeMethod<int>(
        ChannelMethods.deleteImportSources,
        {'opId': opId},
      );
      return result ?? 0;
    } catch (e) {
      logSwallowed('deleteImportSources', e, expected: true);
      return 0;
    }
  }

  /// No local-storage branch: extracting a video frame needs either a
  /// codec plugin or native decode support, neither of which is wired up
  /// for local storage (see the doc comment on
  /// [LocalStorageContainerX.isLocalStorage] call sites in this file for
  /// the general local-storage split). Callers already fall back to a
  /// generic file-type icon when this returns `null`.
  Future<Uint8List?> getVideoThumbnail(
    MountedContainer container,
    String fileName, {
    int quality = 60,
    int targetSize = 180,
  }) async {
    if (container.isLocalStorage) return null;
    try {
      final Uint8List? bytes = await _channel
          .invokeMethod<Uint8List>(ChannelMethods.getVideoThumbnail, {
            'filePath': container.uri,
            'fileName': fileName,
            'quality': quality,
            'targetSize': targetSize,
          });
      return bytes;
    } catch (e) {
      logSwallowed('getVideoThumbnail', e, expected: true);
      return null;
    }
  }

  Future<ThumbnailWithSize?> getVideoThumbnailWithSize(
    MountedContainer container,
    String fileName, {
    int quality = 60,
    int targetSize = 180,
  }) async {
    if (container.isLocalStorage) return null;
    try {
      final result = await _channel
          .invokeMethod(ChannelMethods.getVideoThumbnailWithSize, {
            'filePath': container.uri,
            'fileName': fileName,
            'quality': quality,
            'targetSize': targetSize,
          });
      return ThumbnailWithSize.fromChannelResult(result);
    } catch (e) {
      logSwallowed('getVideoThumbnailWithSize', e, expected: true);
      return null;
    }
  }

  Future<void> setPlaybackActive(bool active) async {
    try {
      await _channel.invokeMethod(ChannelMethods.setPlaybackActive, {
        'active': active,
      });
    } catch (e) {
      logSwallowed('setPlaybackActive', e, expected: true);
    }
  }

  Future<bool> setSecureScreen(bool enabled) async {
    try {
      final bool? success = await _channel.invokeMethod<bool>(
        ChannelMethods.setSecureScreen,
        {'enabled': enabled},
      );
      return success ?? false;
    } catch (e) {
      logSwallowed('setSecureScreen', e);
      return false;
    }
  }

  Future<void> setRecentsSnapshotBlocked(bool blocked) async {
    try {
      await _channel.invokeMethod(ChannelMethods.setRecentsSnapshotBlocked, {
        'blocked': blocked,
      });
    } catch (e) {
      logSwallowed('setRecentsSnapshotBlocked', e, expected: true);
    }
  }

  Future<void> notifyResumedFramePainted() async {
    try {
      await _channel.invokeMethod(ChannelMethods.notifyResumedFramePainted);
    } catch (e) {
      logSwallowed('notifyResumedFramePainted', e, expected: true);
    }
  }

  Future<bool> setSensitiveClipboardText(String text) async {
    try {
      final bool? success = await _channel.invokeMethod<bool>(
        ChannelMethods.setSensitiveClipboardText,
        {'text': text},
      );
      return success ?? false;
    } catch (e) {
      logSwallowed('setSensitiveClipboardText', e);
      return false;
    }
  }

  /// Removes the clipboard's primary clip via `clearPrimaryClip()` on the
  /// native side, rather than replacing it with an empty clip, so Android
  /// 13+'s clipboard preview overlay doesn't fire on clear.
  ///
  /// If [expectedText] is given, the native side only clears when the
  /// clipboard still holds exactly that text, so it never clobbers
  /// something the user copied afterward from elsewhere. Returns `false`
  /// (without throwing) if the platform call isn't available (older
  /// Android, or a channel failure) so the caller can fall back.
  Future<bool> clearSensitiveClipboardText({String? expectedText}) async {
    try {
      final bool? success = await _channel.invokeMethod<bool>(
        ChannelMethods.clearSensitiveClipboardText,
        {'expectedText': expectedText},
      );
      return success ?? false;
    } catch (e) {
      logSwallowed('clearSensitiveClipboardText', e);
      return false;
    }
  }

  Future<bool> setKeepScreenOn(bool enabled) async {
    try {
      final bool? success = await _channel.invokeMethod<bool>(
        ChannelMethods.setKeepScreenOn,
        {'enabled': enabled},
      );
      return success ?? false;
    } catch (e) {
      logSwallowed('setKeepScreenOn', e);
      return false;
    }
  }

  /// Starts VaultCameraRecordingService: the foreground service (typed
  /// camera|microphone) that keeps an in-progress video recording alive
  /// after the screen turns off / the app is backgrounded, rather than
  /// the OS tearing down the camera/mic connection. Only called by
  /// CameraCaptureScreen, and only when "lock vaults on screen lock" is
  /// off for the container being recorded into. See that service for the
  /// full rationale.
  Future<void> startBackgroundRecording({
    required int volId,
    required String containerName,
  }) async {
    try {
      await _channel.invokeMethod(ChannelMethods.startBackgroundRecording, {
        'volId': volId,
        'containerName': containerName,
      });
    } catch (e) {
      logSwallowed('startBackgroundRecording', e);
    }
  }

  /// Stops VaultCameraRecordingService (and releases its wake lock).
  /// Safe to call even if it isn't running.
  Future<void> stopBackgroundRecording() async {
    try {
      await _channel.invokeMethod(ChannelMethods.stopBackgroundRecording);
    } catch (e) {
      logSwallowed('stopBackgroundRecording', e);
    }
  }

  /// Mirrors the current "Debug logging" settings toggle to the native
  /// side, so the VeLog-gated verbose logs down in the engine (chunk
  /// read/write path selection, WRITE_BACK_STREAM profiling, etc.) only
  /// fire when explicitly enabled. Call this whenever the toggle changes
  /// and once at startup -- see VaultExplorerApp._resolveMode.
  Future<void> setDebugLogging(bool enabled) async {
    try {
      await _channel.invokeMethod(ChannelMethods.setDebugLogging, {
        'enabled': enabled,
      });
    } catch (e) {
      logSwallowed('setDebugLogging', e, expected: true);
    }
  }

  Future<bool> launchUrl(String url) async {
    try {
      final bool? success = await _channel.invokeMethod<bool>(
        ChannelMethods.launchUrl,
        {'url': url},
      );
      return success ?? false;
    } catch (e) {
      logSwallowed('launchUrl', e);
      return false;
    }
  }

  Future<String> getAppVersion() async {
    try {
      final String? version = await _channel.invokeMethod<String>(
        ChannelMethods.getAppVersion,
      );
      return version ?? '1.0.0';
    } catch (e) {
      logSwallowed('getAppVersion', e);
      return '1.0.0';
    }
  }

  Future<bool> isCryfsVault(String uri) async {
    try {
      final result = await _channel.invokeMethod<bool>('isCryfsVault', {
        'uri': uri,
      });
      return result ?? false;
    } catch (e) {
      logSwallowed('isCryfsVault', e);
      return false;
    }
  }

  Future<void> beginBatchWrite(MountedContainer container) async {
    try {
      await _channel.invokeMethod<bool>(ChannelMethods.beginBatchWrite, {
        'filePath': container.uri,
      });
    } catch (e) {
      logSwallowed('beginBatchWrite', e);
    }
  }

  Future<void> endBatchWrite(MountedContainer container) async {
    try {
      await _channel.invokeMethod<bool>(ChannelMethods.endBatchWrite, {
        'filePath': container.uri,
      });
    } catch (e) {
      logSwallowed('endBatchWrite', e);
    }
  }

  Future<void> beginBatchDelete(MountedContainer container) async {
    try {
      await _channel.invokeMethod<bool>(ChannelMethods.beginBatchDelete, {
        'filePath': container.uri,
      });
    } catch (e) {
      logSwallowed('beginBatchDelete', e);
    }
  }

  Future<void> endBatchDelete(MountedContainer container) async {
    try {
      await _channel.invokeMethod<bool>(ChannelMethods.endBatchDelete, {
        'filePath': container.uri,
      });
    } catch (e) {
      logSwallowed('endBatchDelete', e);
    }
  }
}
