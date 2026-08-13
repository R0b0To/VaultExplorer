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

  /// Lets the user pick a destination via the system document picker and
  /// writes [contents] to it as UTF-8 text. Unlike [exportFileToStorage],
  /// this isn't scoped to a mounted container -- it's the plain
  /// app-settings export/import round trip (Settings -> Export/Import).
  /// Returns false if the user cancelled or the write failed.
  Future<bool> exportAppSettingsFile(String contents, String fileName) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.exportAppSettingsFile,
      {'contents': contents, 'fileName': fileName},
    );
    return result ?? false;
  }

  /// Opens the system document picker and returns the picked file's text
  /// content, or null if the user cancelled.
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

  /// Same thumbnail as [getImageThumbnail], plus the source image's true
  /// pre-downscale width/height (see [ThumbnailWithSize]). Native already
  /// decodes these bounds to pick a sample size before scaling, so this
  /// costs no extra decode over [getImageThumbnail] — prefer this variant
  /// whenever the caller needs the real content aspect ratio (e.g. masonry
  /// layout) instead of re-deriving it from the JPEG bytes on the Dart side.
  /// Returns null on failure — callers will display a standard file fallback.
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
    // A zero-byte file has no content to protect, but there's also no
    // reason to round-trip through host disk to create one: write an
    // empty chunk directly. writeBackFile's native implementation calls
    // finishWrite internally for backends that need their write buffer
    // flushed (Cryptomator, gocryptfs); writeFileChunk alone does not, so
    // we call finishWriteIfCryptomator explicitly here too -- otherwise
    // this is a silent no-op on those backends. See docs/temp-file-audit.md,
    // finding TF-05.
    final ok = await writeFileChunk(container, fileName, 0, Uint8List(0));
    if (!ok) return false;
    // finishWriteIfCryptomator lives in the _ContainerLifecycleOps mixin,
    // not this one -- call it through the composed singleton rather than
    // unqualified, same as VaultItemsService.saveItem does.
    return vaultExplorerApi.finishWriteIfCryptomator(container, fileName);
  }

  /// Adaptive chunk size for [readWholeFile]/[writeWholeFile] below. Kept
  /// comfortably under the native MAX_CHUNK_BYTES cap (64 MB, see
  /// FileOperationHandlers.kt) so a single platform-channel call never
  /// gets close to that ceiling, while still being large enough that a
  /// multi-MB file only takes a handful of calls.
  static const int _wholeFileChunkSize = 8 * 1024 * 1024; // 8 MB

  /// Reads an entire vault file into memory by looping [readFileChunk]
  /// calls, instead of asking native to decrypt it out to a plaintext
  /// scratch file on host disk first (the old `decryptFile(destPath)` +
  /// `File(destPath).readAsBytes()` pattern -- see docs/temp-file-audit.md,
  /// findings TF-01/TF-02). Returns null if the file doesn't exist or a
  /// chunk read fails partway through.
  ///
  /// This is a Memory-First (Category A) helper: it's intended for files
  /// a caller needs to fully materialize in memory anyway (text editing,
  /// archive parsing, small-to-medium document viewers). Callers dealing
  /// in genuinely large payloads (full-res photos, video) should keep
  /// streaming via [readFileChunk]/[readMediaFileChunk] directly rather
  /// than holding the whole thing in a Dart heap buffer.
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

  /// Writes [bytes] to [fileName] inside the vault as a single atomic
  /// operation, entirely from memory: stages into a sibling `<fileName>.tmp`
  /// path with chunked [writeFileChunk] calls, commits it, then swaps it
  /// into place with [deleteFile] + [renameFile]. Mirrors the pattern
  /// [VaultItemsService.saveItem] already uses for its small JSON payloads,
  /// generalized here (with chunking) so every other in-memory writer --
  /// the text editor, archive extraction, etc. -- gets the same atomic
  /// write guarantee instead of writing a plaintext file to host disk
  /// purely to hand [writeBackFile] a source path.
  ///
  /// The `.tmp` staging path lives *inside* the encrypted container, so
  /// it's ciphertext at rest (Category B: encrypted staging), never a
  /// plaintext file on host disk. Returns false, and best-effort cleans
  /// up the staging path, on any failure.
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

    // finishWriteIfCryptomator lives in the _ContainerLifecycleOps mixin,
    // not this one -- call it through the composed singleton rather than
    // unqualified.
    final finished = await vaultExplorerApi.finishWriteIfCryptomator(container, tmpPath);
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

  /// Deletes the original device-storage files/folder that were picked
  /// during the import identified by [opId] (the same [FileOperation.id]
  /// passed into [importFiles]/[importFolder]). Returns the number of
  /// items deleted. Best-effort — failures are swallowed and reported as 0.
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

  /// Same thumbnail as [getVideoThumbnail], plus the extracted frame's true
  /// pre-scale width/height (see [ThumbnailWithSize]). Costs no extra work
  /// over [getVideoThumbnail] — native already has the frame's own
  /// dimensions in hand before `scaledToFit` touches it. Prefer this variant
  /// whenever the caller needs the real content aspect ratio (e.g. masonry
  /// layout). Returns null on any error — callers should show a fallback icon.
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

  /// Notifies the native layer whether video playback is active so native
  /// background video thumbnail extractions yield immediately to ExoPlayer.
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

  /// Copies [text] to the primary clip marked as sensitive on API 33+
  /// (excluded from clipboard preview / history). Falls back to `false` on
  /// failure so callers can fall back to a plain [Clipboard.setData].
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