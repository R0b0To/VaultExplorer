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
          if (passphrase != null) 'passphrase': passphrase,
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
          if (passphrase != null) 'passphrase': passphrase,
        },
      );
      if (res == null) {
        return ArchiveEntryExtractResult.ioError('Failed to extract vault archive entry');
      }
      return ArchiveEntryExtractResult.fromMap(res);
    } on PlatformException {
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
          if (vaultPath != null) 'vaultPath': vaultPath,
          if (destUri != null) 'destUri': destUri,
          'destDirPath': destDirPath,
          if (subPath != null) 'subPath': subPath,
          if (passphrase != null) 'passphrase': passphrase,
          if (opId != null) 'opId': opId,
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
        {
          'filePath': pathOrUri,
          if (passphrase != null) 'passphrase': passphrase,
        },
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
          if (passphrase != null) 'passphrase': passphrase,
        },
      );
      if (res == null) {
        return ArchiveEntryExtractResult.ioError('Failed to extract local archive entry');
      }
      return ArchiveEntryExtractResult.fromMap(res);
    } on PlatformException {
      rethrow;
    } catch (e) {
      logSwallowed('extractLocalArchiveEntry', e);
      return ArchiveEntryExtractResult.ioError(e.toString());
    }
  }

  /// Creates/compresses an archive with optional AES-256 encryption.
  Future<bool> createArchive({
    required ArchiveFormatType format,
    required List<String> srcPaths,
    List<String>? entryNames,
    String? srcUri,
    String? destUri,
    String? destVaultPath,
    String? destFilePath,
    String? passphrase,
    int? opId,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        ChannelMethods.archiveCreate,
        {
          'format': format.code,
          'srcPaths': srcPaths,
          if (entryNames != null) 'entryNames': entryNames,
          if (srcUri != null) 'srcUri': srcUri,
          if (destUri != null) 'destUri': destUri,
          if (destVaultPath != null) 'destVaultPath': destVaultPath,
          if (destFilePath != null) 'destFilePath': destFilePath,
          if (passphrase != null && passphrase.isNotEmpty) 'passphrase': passphrase,
          if (opId != null) 'opId': opId,
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