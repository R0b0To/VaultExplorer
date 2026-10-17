import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/models/archive_models.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';
import 'vault_engine_types.dart';

class VaultArchiveApi {
  final MethodChannel _channel;
  const VaultArchiveApi(this._channel);

  /// Scans an archive located inside an unlocked encrypted vault without
  /// decompressing entry payloads.
  Future<ArchiveIndexResult> scanVaultArchive({
    required String filePath,
    required String vaultPath,
    String? passphrase,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        ChannelMethods.archiveScanVault,
        {
          'filePath': filePath,
          'vaultPath': vaultPath,
          'passphrase': ?passphrase,
        },
      );
      if (res == null) {
        return const ArchiveIndexResult(
          status: ArchiveOpenStatus.ioError,
          entries: [],
          isSolid: false,
          errorMessage: 'Failed to scan vault archive',
        );
      }
      return ArchiveIndexResult.fromMap(res);
    } on PlatformException {
      rethrow;
    } catch (e) {
      logSwallowed('scanVaultArchive', e);
      return ArchiveIndexResult(
        status: ArchiveOpenStatus.ioError,
        entries: const [],
        isSolid: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Extracts a single target entry from an in-vault archive on-demand directly into memory.
  Future<ArchiveEntryExtractResult> extractVaultArchiveEntry({
    required String filePath,
    required String vaultPath,
    required int targetIndex,
    String? passphrase,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        ChannelMethods.archiveExtractVaultEntry,
        {
          'filePath': filePath,
          'vaultPath': vaultPath,
          'targetIndex': targetIndex,
          'passphrase': ?passphrase,
        },
      );
      if (res == null) {
        return ArchiveEntryExtractResult.ioError(
          'Failed to extract vault archive entry',
        );
      }
      return ArchiveEntryExtractResult.fromMap(res);
    } on PlatformException catch (e) {
      if (e.code == 'OUT_OF_MEMORY') {
        return ArchiveEntryExtractResult.ioError(
          'Archive entry is too large to load into memory',
        );
      }
      rethrow;
    } catch (e) {
      logSwallowed('extractVaultArchiveEntry', e);
      return ArchiveEntryExtractResult.ioError(e.toString());
    }
  }

  /// Bulk extracts an archive (in-vault or local) directly into an unlocked vault directory.
  Future<ArchiveBulkExtractResult> extractVaultArchiveAll({
    required String filePath,
    String? vaultPath,
    String? destUri,
    required String destDirPath,
    String? subPath,
    String? passphrase,
    int? opId,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        ChannelMethods.archiveExtractVaultAll,
        {
          'filePath': filePath,
          'vaultPath': ?vaultPath,
          'destUri': ?destUri,
          'destDirPath': destDirPath,
          'subPath': ?subPath,
          'passphrase': ?passphrase,
          'opId': ?opId,
        },
      );
      if (res == null) {
        return const ArchiveBulkExtractResult(
          status: ArchiveOpenStatus.ioError,
          extractedCount: 0,
          errorMessage: 'Failed to extract archive',
        );
      }
      return ArchiveBulkExtractResult.fromMap(res);
    } on PlatformException {
      rethrow;
    } catch (e) {
      logSwallowed('extractVaultArchiveAll', e);
      return ArchiveBulkExtractResult(
        status: ArchiveOpenStatus.ioError,
        extractedCount: 0,
        errorMessage: e.toString(),
      );
    }
  }

  /// Scans a local/external archive file on device storage via file path or SAF URI.
  Future<ArchiveIndexResult> scanLocalArchive({
    required String pathOrUri,
    String? passphrase,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        ChannelMethods.archiveScanLocal,
        {'filePath': pathOrUri, 'passphrase': ?passphrase},
      );
      if (res == null) {
        return const ArchiveIndexResult(
          status: ArchiveOpenStatus.ioError,
          entries: [],
          isSolid: false,
          errorMessage: 'Failed to scan local archive',
        );
      }
      return ArchiveIndexResult.fromMap(res);
    } on PlatformException {
      rethrow;
    } catch (e) {
      logSwallowed('scanLocalArchive', e);
      return ArchiveIndexResult(
        status: ArchiveOpenStatus.ioError,
        entries: const [],
        isSolid: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Extracts a single target entry from a local archive on-demand.
  Future<ArchiveEntryExtractResult> extractLocalArchiveEntry({
    required String pathOrUri,
    required int targetIndex,
    String? passphrase,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        ChannelMethods.archiveExtractLocalEntry,
        {
          'filePath': pathOrUri,
          'targetIndex': targetIndex,
          'passphrase': ?passphrase,
        },
      );
      if (res == null) {
        return ArchiveEntryExtractResult.ioError(
          'Failed to extract local archive entry',
        );
      }
      return ArchiveEntryExtractResult.fromMap(res);
    } on PlatformException catch (e) {
      if (e.code == 'OUT_OF_MEMORY') {
        return ArchiveEntryExtractResult.ioError(
          'Archive entry is too large to load into memory',
        );
      }
      rethrow;
    } catch (e) {
      logSwallowed('extractLocalArchiveEntry', e);
      return ArchiveEntryExtractResult.ioError(e.toString());
    }
  }

  /// Securely discards an app-private, temporary archive-preview file.
  ///
  /// Native code accepts only `archive_browse_` files immediately under this
  /// app's cache directory, so this cannot remove an arbitrary local file.
  Future<bool> discardBrowseFile(String path) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        ChannelMethods.archiveDiscardBrowseFile,
        {'path': path},
      );
      return ok ?? false;
    } on PlatformException {
      rethrow;
    } catch (e) {
      logSwallowed('discardBrowseFile', e);
      return false;
    }
  }

  /// Streams an archive entry into a short-lived, private cache file for an
  /// in-app preview or a large-file extraction transfer, preserving
  /// passphrase errors for retry.
  Future<ArchiveEntryStageResult> stageBrowseEntry({
    required String filePath,
    String? vaultPath,
    required int targetIndex,
    required String entryName,
    String? passphrase,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        ChannelMethods.archiveStageBrowseEntry,
        {
          'filePath': filePath,
          'vaultPath': ?vaultPath,
          'targetIndex': targetIndex,
          'entryName': entryName,
          'passphrase': ?passphrase,
        },
      );
      if (res == null) {
        return ArchiveEntryStageResult.ioError('Failed to stage archive entry');
      }
      return ArchiveEntryStageResult.fromMap(res);
    } on PlatformException {
      rethrow;
    } catch (e) {
      logSwallowed('stageBrowseEntry', e);
      return ArchiveEntryStageResult.ioError(e.toString());
    }
  }

  /// Creates/compresses an archive with optional AES-256 encryption.
  ///
  /// [encryptFilenames] (7z with a passphrase only) also encrypts the archive
  /// header, so file names, sizes and dates can't be read without the
  /// passphrase. A request that can't be honoured makes the call fail rather
  /// than produce an archive whose names are readable.
  Future<bool> createArchive({
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
    int? opId,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        ChannelMethods.archiveCreate,
        {
          'format': format.code,
          'srcPaths': srcPaths,
          'entryNames': ?entryNames,
          'modifiedSecs': modifiedSecs ?? List<int>.filled(srcPaths.length, 0),
          'srcUri': ?srcUri,
          'destUri': ?destUri,
          'destVaultPath': ?destVaultPath,
          'destFilePath': ?destFilePath,
          if (passphrase != null && passphrase.isNotEmpty)
            'passphrase': passphrase,
          if (encryptFilenames) 'encryptFilenames': true,
          'compressionLevel': ?compressionLevel,
          'opId': ?opId,
        },
      );
      return ok ?? false;
    } on PlatformException {
      rethrow;
    } catch (e) {
      logSwallowed('createArchive', e);
      return false;
    }
  }
}
