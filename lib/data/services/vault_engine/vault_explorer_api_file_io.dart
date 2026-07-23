part of 'vault_explorer_api.dart';

/// File CRUD, thumbnails, import/export, and the remaining small
/// system-level calls (secure-screen toggle, gocryptfs-vault detection)
/// that don't warrant their own part file.
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

  Future<int> getFileSize(MountedContainer container, String fileName) async {
    final result = await _channel.invokeMethod<int>(
      ChannelMethods.getFileSize,
      {'filePath': container.uri, 'fileName': fileName},
    );
    return result ?? 0;
  }

  /// Same native call as [getFileSize], routed to a dedicated native thread
  /// pool reserved for the Media Viewer's full-resolution reads (see
  /// [ChannelMethods.getMediaFileSize]). Use only from
  /// [FullResImageCache]'s fetch path -- everything else should keep using
  /// [getFileSize].
  Future<int> getMediaFileSize(MountedContainer container, String fileName) async {
    final result = await _channel.invokeMethod<int>(
      ChannelMethods.getMediaFileSize,
      {'filePath': container.uri, 'fileName': fileName},
    );
    return result ?? 0;
  }

  /// Returns the recursive byte total of all files inside [dirPath].
  ///
  /// This is a potentially slow operation for large directory trees; callers
  /// should invoke it on a background-triggered path (e.g. from
  /// [SelectionMixin.fetchFolderSizes]) rather than on every build cycle.
  ///
  /// Returns 0 if the container is not mounted or the directory is empty.
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

  /// Same native call as [readFileChunk], routed to a dedicated native
  /// thread pool reserved for the Media Viewer's full-resolution reads
  /// (see [ChannelMethods.readMediaFileChunk]). Use only from
  /// [FullResImageCache]'s fetch path -- everything else should keep using
  /// [readFileChunk].
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

  /// Requests a scaled image thumbnail from the native Android JPEG pipeline.
  /// Returns null on failure — callers will display a standard file fallback.
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

  /// Triggers thumbnail generation and encryption entirely on native threads,
  /// bypassing Dart and saving directly to local App Cache [ThumbnailCacheMode.appCache].
  Future<void> generateAndCacheThumbnail({
    required MountedContainer container,
    required String filePath,
    required List<int> keyBytes,
    int quality = 70,
    int targetSize = 180,
  }) async {
    try {
      await _channel.invokeMethod<void>('generateAndCacheThumbnail', {
        'filePath': container.uri,
        'fileName': filePath,
        'keyBytes': Uint8List.fromList(keyBytes),
        'quality': quality,
        'targetSize': targetSize,
      });
    } catch (e) {
      _logSwallowed('generateAndCacheThumbnail', e, expected: true);
    }
  }

  Future<List<String>?> listDirectory(
    MountedContainer container,
    String dirPath,
  ) async {
    final result = await _channel.invokeMethod<List<Object?>>(
      ChannelMethods.listDirectory,
      {'filePath': container.uri, 'dirPath': dirPath},
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
    final tmpDir = await getTemporaryDirectory();
    final tempFile = File(
      '${tmpDir.path}/cb_empty_${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await tempFile.create(recursive: true);
      return await writeBackFile(container, fileName, tempFile.path);
    } finally {
      if (await tempFile.exists()) await tempFile.delete();
    }
  }

  Future<List<int>?> getSpaceInfo(MountedContainer container) async {
    final result = await _channel.invokeMethod<List<Object?>>(
      ChannelMethods.getSpaceInfo,
      {'filePath': container.uri},
    );
    return result?.cast<int>();
  }

  /// [opId] is the caller's [FileOperation.id] — native echoes it back on
  /// every "onImportProgress" push and matches it against
  /// [cancelImport] requests.
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

  /// [opId] is the caller's [FileOperation.id] — native echoes it back on
  /// every "onImportProgress" push and matches it against
  /// [cancelImport] requests.
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

  /// Asks native to abort the in-flight import identified by [opId] (the
  /// [FileOperation.id] originally passed into [importFiles]/[importFolder]).
  ///
  /// Fire-and-forget and best-effort: this doesn't itself throw or resolve
  /// the pending import — that call will still complete on its own shortly
  /// after, but with a `PlatformException(code: 'CANCELLED')` instead of a
  /// result, once native notices the request between files. Files already
  /// written before that point stay in place. Safe to call more than once,
  /// or after the import has already finished.
  Future<void> cancelImport(int opId) async {
    try {
      await _channel.invokeMethod(ChannelMethods.cancelImport, {'opId': opId});
    } catch (e) {
      // Best-effort — the pending import call resolves on its own regardless.
      _logSwallowed('cancelImport', e, expected: true);
    }
  }

  /// Requests a scaled video thumbnail from the native layer.
  /// Returns null on any error — callers should show a fallback icon.
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

  /// Checks if the folder at [uri] contains a "gocryptfs.conf" file.
  Future<bool> isGocryptfsVault(String uri) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'isGocryptfsVault',
        {'uri': uri},
      );
      return result ?? false;
    } catch (e) {
      _logSwallowed('isGocryptfsVault', e);
      return false;
    }
  }

  /// Checks if the folder at [uri] contains a "cryfs.config" file.
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

}
