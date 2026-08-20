part of 'vault_explorer_api.dart';

/// File CRUD, thumbnails, import/export, and system-level calls.
mixin _FileIoOps {
  // ── File I/O ──────────────────────────────────────────────────────────────

  Future<bool> openWithApp(
    MountedContainer container,
    String fileName, {
    String? packageName,
    String? mimeType,
  }) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.openWithApp,
      {
        'filePath': container.uri,
        'fileName': fileName,
        'packageName': packageName,
        'mimeType': mimeType,
      },
    );
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
    return _channel.invokeMethod<String>(
      ChannelMethods.importAppSettingsFile,
    );
  }

  Future<int> getFileSize(MountedContainer container, String fileName) async {
    final result = await _channel.invokeMethod<int>(
      ChannelMethods.getFileSize,
      {'filePath': container.uri, 'fileName': fileName},
    );
    return result ?? 0;
  }

  Future<int> getMediaFileSize(MountedContainer container, String fileName) async {
    final result = await _channel.invokeMethod<int>(
      ChannelMethods.getMediaFileSize,
      {'filePath': container.uri, 'fileName': fileName},
    );
    return result ?? 0;
  }

  Future<int> getFolderSize(MountedContainer container, String dirPath) async {
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
    final result = await _channel.invokeMethod<Uint8List>(
      ChannelMethods.readFileChunk,
      {
        'filePath': container.uri,
        'fileName': fileName,
        'offset': offset,
        'length': length,
      },
    );
    return result;
  }

  Future<Uint8List?> readMediaFileChunk(
    MountedContainer container,
    String fileName,
    int offset,
    int length,
  ) async {
    final result = await _channel.invokeMethod<Uint8List>(
      ChannelMethods.readMediaFileChunk,
      {
        'filePath': container.uri,
        'fileName': fileName,
        'offset': offset,
        'length': length,
      },
    );
    return result;
  }

  Future<Uint8List?> getImageThumbnail(
    MountedContainer container,
    String fileName, {
    int targetSize = 180,
    int quality = 70,
  }) async {
    try {
      final Uint8List? bytes = await _channel.invokeMethod<Uint8List>(
        'getImageThumbnail',
        {
          'filePath': container.uri,
          'fileName': fileName,
          'targetSize': targetSize,
          'quality': quality,
        },
      );
      return bytes;
    } catch (e) {
      _logSwallowed('getImageThumbnail', e, expected: true);
      return null;
    }
  }

  Future<ThumbnailWithSize?> getImageThumbnailWithSize(
    MountedContainer container,
    String fileName, {
    int targetSize = 180,
    int quality = 70,
  }) async {
    try {
      final result = await _channel.invokeMethod(
        ChannelMethods.getImageThumbnailWithSize,
        {
          'filePath': container.uri,
          'fileName': fileName,
          'targetSize': targetSize,
          'quality': quality,
        },
      );
      return ThumbnailWithSize.fromChannelResult(result);
    } catch (e) {
      _logSwallowed('getImageThumbnailWithSize', e, expected: true);
      return null;
    }
  }

  Future<List<String>?> listDirectory(
    MountedContainer container,
    String dirPath, {
    bool refresh = false,
  }) async {
    final result = await _channel.invokeMethod<List<Object?>>(
      ChannelMethods.listDirectory,
      {
        'filePath': container.uri,
        'dirPath': dirPath,
        'refresh': refresh,
      },
    );
    return result?.cast<String>();
  }

  Future<bool> createDirectory(
    MountedContainer container,
    String dirPath,
  ) async {
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
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.renameFile,
      {'filePath': container.uri, 'oldPath': oldPath, 'newPath': newPath},
    );
    return result ?? false;
  }

  Future<bool> writeFileChunk(
    MountedContainer container,
    String fileName,
    int offset,
    Uint8List data,
  ) async {
    final result = await _channel.invokeMethod<bool>('writeFileChunk', {
      'filePath': container.uri,
      'fileName': fileName,
      'offset': offset,
      'data': data,
    });
    return result ?? false;
  }

  Future<bool> deleteFile(MountedContainer container, String fileName) async {
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
    return vaultExplorerApi.finishWrite(container, fileName);
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
      final len = remaining > _wholeFileChunkSize ? _wholeFileChunkSize : remaining;
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
      final len = remaining > _wholeFileChunkSize ? _wholeFileChunkSize : remaining;
      final chunk = Uint8List.sublistView(bytes, offset, offset + len);
      final ok = await writeFileChunk(container, tmpPath, offset, chunk);
      if (!ok) {
        await deleteFile(container, tmpPath);
        return false;
      }
      offset += len;
    } while (offset < bytes.length);

    final finished = await vaultExplorerApi.finishWrite(container, tmpPath);
    if (!finished) {
      await deleteFile(container, tmpPath);
      return false;
    }

    await deleteFile(container, fileName);
    return renameFile(container, tmpPath, fileName);
  }

  Future<List<int>?> getSpaceInfo(MountedContainer container) async {
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

  Future<int> importFiles(
    MountedContainer container,
    String targetPath,
    int opId,
  ) async {
    final result = await _channel.invokeMethod<int>(ChannelMethods.importFile, {
      'filePath': container.uri,
      'targetPath': targetPath,
      'opId': opId,
    });
    return result ?? 0;
  }

  Future<int> exportSelectedToFolder(
    MountedContainer container,
    List<Map<String, dynamic>> items,
  ) async {
    final result = await _channel.invokeMethod<int>(
      ChannelMethods.exportFilesToFolder,
      {'filePath': container.uri, 'items': items},
    );
    return result ?? 0;
  }

  Future<int> importFolder(
    MountedContainer container,
    String targetPath,
    int opId,
  ) async {
    final result = await _channel.invokeMethod<int>(
      ChannelMethods.importFolder,
      {'filePath': container.uri, 'targetPath': targetPath, 'opId': opId},
    );
    return result ?? 0;
  }

  Future<void> cancelImport(int opId) async {
    try {
      await _channel.invokeMethod(ChannelMethods.cancelImport, {'opId': opId});
    } catch (e) {
      _logSwallowed('cancelImport', e, expected: true);
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
      _logSwallowed('deleteImportSources', e, expected: true);
      return 0;
    }
  }

  Future<Uint8List?> getVideoThumbnail(
    MountedContainer container,
    String fileName, {
    int quality = 60,
    int targetSize = 180,
  }) async {
    try {
      final Uint8List? bytes = await _channel.invokeMethod<Uint8List>(
        ChannelMethods.getVideoThumbnail,
        {
          'filePath': container.uri,
          'fileName': fileName,
          'quality': quality,
          'targetSize': targetSize,
        },
      );
      return bytes;
    } catch (e) {
      _logSwallowed('getVideoThumbnail', e, expected: true);
      return null;
    }
  }

  Future<ThumbnailWithSize?> getVideoThumbnailWithSize(
    MountedContainer container,
    String fileName, {
    int quality = 60,
    int targetSize = 180,
  }) async {
    try {
      final result = await _channel.invokeMethod(
        ChannelMethods.getVideoThumbnailWithSize,
        {
          'filePath': container.uri,
          'fileName': fileName,
          'quality': quality,
          'targetSize': targetSize,
        },
      );
      return ThumbnailWithSize.fromChannelResult(result);
    } catch (e) {
      _logSwallowed('getVideoThumbnailWithSize', e, expected: true);
      return null;
    }
  }

  Future<void> setPlaybackActive(bool active) async {
    try {
      await _channel.invokeMethod(
        ChannelMethods.setPlaybackActive,
        {'active': active},
      );
    } catch (e) {
      _logSwallowed('setPlaybackActive', e, expected: true);
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
      _logSwallowed('setSecureScreen', e);
      return false;
    }
  }

  Future<void> setRecentsSnapshotBlocked(bool blocked) async {
    try {
      await _channel.invokeMethod(
        ChannelMethods.setRecentsSnapshotBlocked,
        {'blocked': blocked},
      );
    } catch (e) {
      _logSwallowed('setRecentsSnapshotBlocked', e, expected: true);
    }
  }

  Future<void> notifyResumedFramePainted() async {
    try {
      await _channel.invokeMethod(ChannelMethods.notifyResumedFramePainted);
    } catch (e) {
      _logSwallowed('notifyResumedFramePainted', e, expected: true);
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
      _logSwallowed('setSensitiveClipboardText', e);
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
      _logSwallowed('setKeepScreenOn', e);
      return false;
    }
  }

  /// Mirrors the current "Debug logging" settings toggle to the native
  /// side, so the VeLog-gated verbose logs down in the engine (chunk
  /// read/write path selection, WRITE_BACK_STREAM profiling, etc.) only
  /// fire when explicitly enabled. Call this whenever the toggle changes
  /// and once at startup -- see VaultExplorerApp._resolveMode.
  Future<void> setDebugLogging(bool enabled) async {
    try {
      await _channel.invokeMethod(
        ChannelMethods.setDebugLogging,
        {'enabled': enabled},
      );
    } catch (e) {
      _logSwallowed('setDebugLogging', e, expected: true);
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
      _logSwallowed('launchUrl', e);
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
      _logSwallowed('getAppVersion', e);
      return '1.0.0';
    }
  }

  Future<bool> isCryfsVault(String uri) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'isCryfsVault',
        {'uri': uri},
      );
      return result ?? false;
    } catch (e) {
      _logSwallowed('isCryfsVault', e);
      return false;
    }
  }

  Future<void> beginBatchWrite(MountedContainer container) async {
    try {
      await _channel.invokeMethod<bool>(
        ChannelMethods.beginBatchWrite,
        {'filePath': container.uri},
      );
    } catch (e) {
      _logSwallowed('beginBatchWrite', e);
    }
  }

  Future<void> endBatchWrite(MountedContainer container) async {
    try {
      await _channel.invokeMethod<bool>(
        ChannelMethods.endBatchWrite,
        {'filePath': container.uri},
      );
    } catch (e) {
      _logSwallowed('endBatchWrite', e);
    }
  }
}