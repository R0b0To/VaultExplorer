import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_hash_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/api/vault_repair_api.dart';
import 'package:vaultexplorer/core/api/vault_split_join_api.dart';
import 'package:vaultexplorer/core/utils/secure_temp_file.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';

abstract class ContainerToolService {
  Future<void> splitContainer({
    required String sourceUri,
    required String destinationPath,
    String? destinationTreeUri,
    required int chunkSizeBytes,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  });

  Future<void> joinContainer({
    required String firstPartUri,
    required String destinationPath,
    String? destinationTreeUri,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  });

  Future<void> encryptFile({
    required String sourceUri,
    required StandaloneCipher cipher,
    required String passphrase,
    List<String> keyfilePaths = const [],
    bool deleteOriginalAfter = false,
    String? destinationPath,
    String? destinationTreeUri,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  });

  Future<void> decryptFile({
    required String sourceUri,
    required String passphrase,
    List<String> keyfilePaths = const [],
    String? destinationPath,
    String? destinationTreeUri,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  });

  Future<RepairDiagnosis> diagnoseTarget(
    RepairTarget target, {
    void Function(String message)? onLogLine,
  });

  Future<bool> restoreBackupHeader(
    RepairTarget target, {
    String? password,
    void Function(String message)? onLogLine,
  });
  Future<bool> runFilesystemCheck(
    MountedVolumeTarget target, {
    void Function(String message)? onLogLine,
  });

  Future<FolderVaultTarget?> pickFolderVaultForRepair();

  Future<FolderVaultCheckReport> checkFolderVault(
    FolderVaultTarget target, {
    String? password,
    void Function(String message)? onLogLine,
  });

  Future<FolderVaultRepairReport> repairFolderVault(
    FolderVaultTarget target, {
    String? password,
    void Function(String message)? onLogLine,
  });

  // ── Header Backup tool ──────────────────────────────────────────────

  /// Exports [target]'s header/keyslot region (see container_repair.cpp)
  /// into a [HeaderBackupFile], ready for [saveHeaderBackupFile]. Callers
  /// should [diagnoseTarget] first and confirm with the person before
  /// exporting an unhealthy container -- there's no native-side gate
  /// against it, but backing up an already-corrupted header defeats the
  /// tool's purpose.
  Future<HeaderBackupFile> exportContainerHeader(
    UnmountedFileTarget target, {
    void Function(String message)? onLogLine,
  });

  /// Exports [target]'s entire config/masterkey file (gocryptfs.conf /
  /// cryfs.config / masterkey.cryptomator) into a [HeaderBackupFile].
  /// Throws [FolderVaultInvalidException] if that file isn't currently
  /// there to back up.
  Future<HeaderBackupFile> exportFolderVaultConfig(FolderVaultTarget target);

  /// Restores [backup] (which must be a [HeaderBackupKind.containerHeader]
  /// backup) onto [target]. See [VaultRepairApi.restoreContainerHeaderRegion]
  /// for the exceptions this can throw.
  Future<bool> restoreContainerHeader(
    UnmountedFileTarget target,
    HeaderBackupFile backup, {
    String? password,
    void Function(String message)? onLogLine,
  });

  /// Restores [backup] (which must be a [HeaderBackupKind.folderVaultConfig]
  /// backup) onto [target]'s vault root, replacing (or recreating) its
  /// config/masterkey file.
  Future<void> restoreFolderVaultConfig(FolderVaultTarget target, HeaderBackupFile backup);

  /// Reads and fully validates (envelope structure + checksum) the Header
  /// Backup file at [uri]. Throws [HeaderBackupInvalidException] if it
  /// isn't a genuine, intact Header Backup file.
  Future<HeaderBackupFile> loadHeaderBackupFile(String uri);

  /// Encodes [backup] and writes it to [fileName] under the folder
  /// identified by the (path, treeUri) pair from [VaultLifecycleApi.pickExtractFolder].
  Future<void> saveHeaderBackupFile(
    HeaderBackupFile backup, {
    required String? destinationPath,
    required String? destinationTreeUri,
    required String fileName,
  });

  Future<BatchCryptoBatchResult> runBatchFileCrypto({
    required CryptoDirection direction,
    required List<CryptoSourceItem> sources,
    required CryptoDestination destination,
    required StandaloneCipher cipher,
    required String passphrase,
    required List<String> keyfilePaths,
    required bool deleteOriginal,
    void Function(int currentIndex, int totalFiles)? onFileStart,
    void Function(int bytesDone, int bytesTotal)? onFileProgress,
  });
}

class DefaultContainerToolService implements ContainerToolService {
  DefaultContainerToolService({
    this._fileIoApi,
    this._lifecycleApi,
  });

  final VaultFileIoApi? _fileIoApi;
  final VaultLifecycleApi? _lifecycleApi;

  VaultFileIoApi get _fileIo =>
      _fileIoApi ??
      (throw StateError(
        'VaultFileIoApi is required for vault batch-crypto operations.',
      ));

  VaultLifecycleApi get _lifecycle =>
      _lifecycleApi ??
      (throw StateError(
        'VaultLifecycleApi is required for vault batch-crypto operations.',
      ));

  @override
  Future<void> splitContainer({
    required String sourceUri,
    required String destinationPath,
    String? destinationTreeUri,
    required int chunkSizeBytes,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) => throw UnimplementedError('splitContainer is not implemented yet.');

  @override
  Future<void> joinContainer({
    required String firstPartUri,
    required String destinationPath,
    String? destinationTreeUri,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) => throw UnimplementedError('joinContainer is not implemented yet.');

  @override
  Future<void> encryptFile({
    required String sourceUri,
    required StandaloneCipher cipher,
    required String passphrase,
    List<String> keyfilePaths = const [],
    bool deleteOriginalAfter = false,
    String? destinationPath,
    String? destinationTreeUri,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) => throw UnimplementedError('encryptFile is not implemented yet.');

  @override
  Future<void> decryptFile({
    required String sourceUri,
    required String passphrase,
    List<String> keyfilePaths = const [],
    String? destinationPath,
    String? destinationTreeUri,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) => throw UnimplementedError('decryptFile is not implemented yet.');

  @override
  Future<RepairDiagnosis> diagnoseTarget(
    RepairTarget target, {
    void Function(String message)? onLogLine,
  }) => throw UnimplementedError('diagnoseTarget is not implemented yet.');

  @override
  Future<bool> restoreBackupHeader(
    RepairTarget target, {
    String? password,
    void Function(String message)? onLogLine,
  }) => throw UnimplementedError('restoreBackupHeader is not implemented yet.');

  @override
  Future<bool> runFilesystemCheck(
    MountedVolumeTarget target, {
    void Function(String message)? onLogLine,
  }) => throw UnimplementedError('runFilesystemCheck is not implemented yet.');

  @override
  Future<FolderVaultTarget?> pickFolderVaultForRepair() =>
      throw UnimplementedError(
        'pickFolderVaultForRepair is not implemented yet.',
      );

  @override
  Future<FolderVaultCheckReport> checkFolderVault(
    FolderVaultTarget target, {
    String? password,
    void Function(String message)? onLogLine,
  }) => throw UnimplementedError('checkFolderVault is not implemented yet.');

  @override
  Future<FolderVaultRepairReport> repairFolderVault(
    FolderVaultTarget target, {
    String? password,
    void Function(String message)? onLogLine,
  }) => throw UnimplementedError('repairFolderVault is not implemented yet.');

  @override
  Future<HeaderBackupFile> exportContainerHeader(
    UnmountedFileTarget target, {
    void Function(String message)? onLogLine,
  }) => throw UnimplementedError('exportContainerHeader is not implemented yet.');

  @override
  Future<HeaderBackupFile> exportFolderVaultConfig(FolderVaultTarget target) =>
      throw UnimplementedError('exportFolderVaultConfig is not implemented yet.');

  @override
  Future<bool> restoreContainerHeader(
    UnmountedFileTarget target,
    HeaderBackupFile backup, {
    String? password,
    void Function(String message)? onLogLine,
  }) => throw UnimplementedError('restoreContainerHeader is not implemented yet.');

  @override
  Future<void> restoreFolderVaultConfig(FolderVaultTarget target, HeaderBackupFile backup) =>
      throw UnimplementedError('restoreFolderVaultConfig is not implemented yet.');

  @override
  Future<HeaderBackupFile> loadHeaderBackupFile(String uri) =>
      throw UnimplementedError('loadHeaderBackupFile is not implemented yet.');

  @override
  Future<void> saveHeaderBackupFile(
    HeaderBackupFile backup, {
    required String? destinationPath,
    required String? destinationTreeUri,
    required String fileName,
  }) => throw UnimplementedError('saveHeaderBackupFile is not implemented yet.');

  @override
  Future<BatchCryptoBatchResult> runBatchFileCrypto({
    required CryptoDirection direction,
    required List<CryptoSourceItem> sources,
    required CryptoDestination destination,
    required StandaloneCipher cipher,
    required String passphrase,
    required List<String> keyfilePaths,
    required bool deleteOriginal,
    void Function(int currentIndex, int totalFiles)? onFileStart,
    void Function(int bytesDone, int bytesTotal)? onFileProgress,
  }) async {
    final failedNames = <String>[];
    var succeeded = 0;

    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      onFileStart?.call(i + 1, sources.length);

      Directory? tempInDir;
      Directory? tempOutDir;

      try {
        String effectiveSourceUri;

        if (source.isFromVault) {
          tempInDir = await Directory.systemTemp.createTemp('vx_crypto_in_');
          final tempInFile = File(p.join(tempInDir.path, source.displayName));
          final extracted = await _fileIo.decryptFile(
            source.container!,
            source.relativePath!,
            tempInFile.path,
          );
          if (!extracted || !tempInFile.existsSync()) {
            throw Exception('Failed to extract file from source vault');
          }
          effectiveSourceUri = Uri.file(tempInFile.path).toString();
        } else {
          effectiveSourceUri = source.externalUri!;
        }

        String? effectiveDestPath;
        String? effectiveTreeUri;

        if (destination.isVault) {
          tempOutDir = await Directory.systemTemp.createTemp('vx_crypto_out_');
          effectiveDestPath = tempOutDir.path;
          effectiveTreeUri = null;
        } else {
          effectiveDestPath =
              destination.externalPath ?? destination.externalTreeUri;
          effectiveTreeUri = destination.externalTreeUri;
        }

        if (direction == CryptoDirection.encrypt) {
          await encryptFile(
            sourceUri: effectiveSourceUri,
            cipher: cipher,
            passphrase: passphrase,
            keyfilePaths: keyfilePaths,
            deleteOriginalAfter: source.isFromVault ? false : deleteOriginal,
            destinationPath: effectiveDestPath,
            destinationTreeUri: effectiveTreeUri,
            onProgress: onFileProgress,
          );
        } else {
          await decryptFile(
            sourceUri: effectiveSourceUri,
            passphrase: passphrase,
            keyfilePaths: keyfilePaths,
            destinationPath: effectiveDestPath,
            destinationTreeUri: effectiveTreeUri,
            onProgress: onFileProgress,
          );
        }

        if (destination.isVault && tempOutDir != null) {
          final generatedFiles = tempOutDir
              .listSync()
              .whereType<File>()
              .toList();
          if (generatedFiles.isEmpty) {
            throw Exception('No output file generated by crypto engine');
          }
          for (final outFile in generatedFiles) {
            final outFileName = p.basename(outFile.path);
            final vaultPath = destination.relativePath!.isEmpty
                ? outFileName
                : '${destination.relativePath!}/$outFileName';
            final wroteBack = await _fileIo.writeBackFile(
              destination.container!,
              vaultPath,
              outFile.path,
            );
            if (!wroteBack) {
              throw Exception('Failed to write output file to target vault');
            }
            await _lifecycle.finishWrite(destination.container!, vaultPath);
          }
        }

        if (deleteOriginal &&
            direction == CryptoDirection.encrypt &&
            source.isFromVault) {
          await _fileIo.deleteFile(source.container!, source.relativePath!);
        }

        succeeded++;
      } on UnimplementedError {
        return BatchCryptoBatchResult(
          abortReason: BatchCryptoAbortReason.notImplemented,
          succeeded: succeeded,
          totalFiles: sources.length,
          failedNames: failedNames,
        );
      } on PlatformException catch (e) {
        if (e.code == 'AUTH_FAIL') {
          return BatchCryptoBatchResult(
            abortReason: BatchCryptoAbortReason.authFailure,
            succeeded: succeeded,
            totalFiles: sources.length,
            failedNames: failedNames,
          );
        }
        failedNames.add(source.displayName);
      } catch (_) {
        failedNames.add(source.displayName);
      } finally {
        if (tempInDir != null) {
          await SecureTempFile.wipeAndDeleteDir(tempInDir);
        }
        if (tempOutDir != null) {
          await SecureTempFile.wipeAndDeleteDir(tempOutDir);
        }
      }
    }

    return BatchCryptoBatchResult(
      succeeded: succeeded,
      totalFiles: sources.length,
      failedNames: failedNames,
    );
  }
}

class NativeContainerToolService extends DefaultContainerToolService {
  NativeContainerToolService(
    this._engineEvents,
    VaultFileIoApi fileIoApi,
    VaultLifecycleApi lifecycleApi,
    this._splitJoinApi,
    this._repairApi,
    this._hashApi,
  ) : super(fileIoApi: fileIoApi, lifecycleApi: lifecycleApi);

  final VaultEngineEvents _engineEvents;
  final VaultSplitJoinApi _splitJoinApi;
  final VaultRepairApi _repairApi;
  final VaultHashApi _hashApi;

  int _opIdCounter = 0;
  int _nextOpId() => ++_opIdCounter;

  Future<T> _withProgressListener<T>(
    void Function(int bytesDone, int bytesTotal)? onProgress,
    int opId,
    Future<T> Function() body,
  ) async {
    if (onProgress == null) return body();
    void listener(SplitJoinProgress progress) {
      if (progress.opId == opId) {
        onProgress(progress.bytesDone, progress.bytesTotal);
      }
    }

    _engineEvents.addSplitJoinProgressListener(listener);
    try {
      return await body();
    } finally {
      _engineEvents.removeSplitJoinProgressListener(listener);
    }
  }

  Future<T> _withLogListener<T>(
    void Function(String message)? onLogLine,
    int opId,
    Future<T> Function() body,
  ) async {
    if (onLogLine == null) return body();
    void listener(RepairLogLine line) {
      if (line.opId == opId) onLogLine(line.message);
    }

    _engineEvents.addRepairLogListener(listener);
    try {
      return await body();
    } finally {
      _engineEvents.removeRepairLogListener(listener);
    }
  }

  @override
  Future<void> splitContainer({
    required String sourceUri,
    required String destinationPath,
    String? destinationTreeUri,
    required int chunkSizeBytes,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) {
    final opId = _nextOpId();
    return _withProgressListener(onProgress, opId, () {
      return _splitJoinApi.splitContainer(
        sourceUri: sourceUri,
        destinationPath: destinationPath,
        destinationTreeUri: destinationTreeUri,
        chunkSizeBytes: chunkSizeBytes,
        opId: opId,
      );
    });
  }

  @override
  Future<void> joinContainer({
    required String firstPartUri,
    required String destinationPath,
    String? destinationTreeUri,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) {
    final opId = _nextOpId();
    return _withProgressListener(onProgress, opId, () {
      return _splitJoinApi.joinContainer(
        firstPartUri: firstPartUri,
        destinationPath: destinationPath,
        destinationTreeUri: destinationTreeUri,
        opId: opId,
      );
    });
  }

  @override
  Future<void> encryptFile({
    required String sourceUri,
    required StandaloneCipher cipher,
    required String passphrase,
    List<String> keyfilePaths = const [],
    bool deleteOriginalAfter = false,
    String? destinationPath,
    String? destinationTreeUri,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) {
    final opId = _nextOpId();
    return _withProgressListener(onProgress, opId, () {
      return _splitJoinApi.encryptSingleFile(
        sourceUri: sourceUri,
        cipherIndex: cipher.index,
        passphrase: passphrase,
        keyfilePaths: keyfilePaths,
        deleteOriginalAfter: deleteOriginalAfter,
        destinationPath: destinationPath,
        destinationTreeUri: destinationTreeUri,
        opId: opId,
      );
    });
  }

  @override
  Future<void> decryptFile({
    required String sourceUri,
    required String passphrase,
    List<String> keyfilePaths = const [],
    String? destinationPath,
    String? destinationTreeUri,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) {
    final opId = _nextOpId();
    return _withProgressListener(onProgress, opId, () {
      return _splitJoinApi.decryptSingleFile(
        sourceUri: sourceUri,
        passphrase: passphrase,
        keyfilePaths: keyfilePaths,
        destinationPath: destinationPath,
        destinationTreeUri: destinationTreeUri,
        opId: opId,
      );
    });
  }

  RepairDiagnosis _diagnosisFromCode(int code) {
    if (code >= 0 && code < RepairDiagnosis.values.length) {
      return RepairDiagnosis.values[code];
    }
    return RepairDiagnosis.headerCorrupted;
  }

  @override
  Future<RepairDiagnosis> diagnoseTarget(
    RepairTarget target, {
    void Function(String message)? onLogLine,
  }) {
    final opId = _nextOpId();
    return _withLogListener(onLogLine, opId, () async {
      final result = switch (target) {
        UnmountedFileTarget(:final uri) =>
          await _repairApi.diagnoseUnmountedContainerFile(uri, opId: opId),
        MountedVolumeTarget(:final volId) =>
          await _repairApi.diagnoseMountedVolumeFilesystem(volId, opId: opId),
        FolderVaultTarget() => throw UnimplementedError(
          'Folder vaults (gocryptfs/CryFS/Cryptomator) use checkFolderVault, not diagnoseTarget.',
        ),
      };
      return _diagnosisFromCode(result.diagnosisCode);
    });
  }

  @override
  Future<bool> restoreBackupHeader(
    RepairTarget target, {
    String? password,
    void Function(String message)? onLogLine,
  }) {
    if (target is! UnmountedFileTarget) {
      throw const RepairUnsupportedFormatException();
    }
    final opId = _nextOpId();
    return _withLogListener(onLogLine, opId, () {
      return _repairApi.restoreBackupHeaderUnmounted(
        uri: target.uri,
        password: password,
        opId: opId,
      );
    });
  }

  @override
  Future<bool> runFilesystemCheck(
    MountedVolumeTarget target, {
    void Function(String message)? onLogLine,
  }) {
    final opId = _nextOpId();
    return _withLogListener(onLogLine, opId, () {
      return _repairApi.runMountedVolumeFilesystemCheck(
        target.volId,
        opId: opId,
      );
    });
  }

  @override
  Future<FolderVaultTarget?> pickFolderVaultForRepair() async {
    final picked = await _repairApi.pickFolderVaultForRepair();
    if (picked == null) return null;
    if (picked.format == null) {
      throw FolderVaultInvalidException(
        'No gocryptfs.conf, cryfs.config, or masterkey.cryptomator found in "${picked.displayName}".',
      );
    }
    return FolderVaultTarget(
      treeUri: picked.uri,
      displayName: picked.displayName,
      format: picked.format!,
    );
  }

  @override
  Future<FolderVaultCheckReport> checkFolderVault(
    FolderVaultTarget target, {
    String? password,
    void Function(String message)? onLogLine,
  }) {
    final opId = _nextOpId();
    return _withLogListener(onLogLine, opId, () {
      return _repairApi.checkFolderVault(
        target,
        password: password,
        opId: opId,
      );
    });
  }

  @override
  Future<FolderVaultRepairReport> repairFolderVault(
    FolderVaultTarget target, {
    String? password,
    void Function(String message)? onLogLine,
  }) {
    final opId = _nextOpId();
    return _withLogListener(onLogLine, opId, () {
      return _repairApi.repairFolderVault(
        target,
        password: password,
        opId: opId,
      );
    });
  }

  @override
  Future<HeaderBackupFile> exportContainerHeader(
    UnmountedFileTarget target, {
    void Function(String message)? onLogLine,
  }) {
    final opId = _nextOpId();
    return _withLogListener(onLogLine, opId, () async {
      final exported = await _repairApi.exportContainerHeader(target.uri, opId: opId);
      final sha256Hex = await _hashApi.hashBytesSha256(exported.bytes);
      return HeaderBackupFile(
        kind: HeaderBackupKind.containerHeader,
        format: exported.format,
        payload: exported.bytes,
        sha256Hex: sha256Hex,
        containerSizeBytes: null,
        exportedAtMs: DateTime.now().millisecondsSinceEpoch,
        sourceName: target.displayName,
      );
    });
  }

  @override
  Future<HeaderBackupFile> exportFolderVaultConfig(FolderVaultTarget target) async {
    final resolved = await _repairApi.resolveFolderVaultConfigFile(uri: target.treeUri, format: target.format);
    if (!resolved.exists || resolved.uri == null) {
      throw FolderVaultInvalidException(
        'No ${resolved.fileName} found in "${target.displayName}" -- nothing to back up.',
      );
    }
    final bytes = await _hashApi.readExternalFileBytes(resolved.uri!);
    if (bytes == null) {
      throw FolderVaultInvalidException('Could not read ${resolved.fileName}.');
    }
    final sha256Hex = await _hashApi.hashBytesSha256(bytes);
    return HeaderBackupFile(
      kind: HeaderBackupKind.folderVaultConfig,
      format: target.format,
      payload: bytes,
      sha256Hex: sha256Hex,
      containerSizeBytes: null,
      exportedAtMs: DateTime.now().millisecondsSinceEpoch,
      sourceName: target.displayName,
    );
  }

  @override
  Future<bool> restoreContainerHeader(
    UnmountedFileTarget target,
    HeaderBackupFile backup, {
    String? password,
    void Function(String message)? onLogLine,
  }) {
    if (backup.kind != HeaderBackupKind.containerHeader) {
      throw const HeaderBackupInvalidException('This backup file is for a folder vault, not a container.');
    }
    final opId = _nextOpId();
    return _withLogListener(onLogLine, opId, () {
      return _repairApi.restoreContainerHeaderRegion(
        uri: target.uri,
        format: backup.format,
        bytes: backup.payload,
        password: password,
        opId: opId,
      );
    });
  }

  @override
  Future<void> restoreFolderVaultConfig(FolderVaultTarget target, HeaderBackupFile backup) {
    if (backup.kind != HeaderBackupKind.folderVaultConfig) {
      throw const HeaderBackupInvalidException('This backup file is for a container, not a folder vault.');
    }
    return _repairApi.restoreFolderVaultConfig(
      uri: target.treeUri,
      format: backup.format,
      bytes: backup.payload,
    );
  }

  @override
  Future<HeaderBackupFile> loadHeaderBackupFile(String uri) async {
    final raw = await _hashApi.readExternalFileBytes(uri);
    if (raw == null) {
      throw const HeaderBackupInvalidException('Could not read this backup file.');
    }
    final parsed = HeaderBackupFile.decode(raw);
    final actualSha256Hex = await _hashApi.hashBytesSha256(parsed.payload);
    if (actualSha256Hex.toLowerCase() != parsed.sha256Hex.toLowerCase()) {
      throw const HeaderBackupInvalidException('This backup file appears corrupted (checksum mismatch).');
    }
    return parsed;
  }

  @override
  Future<void> saveHeaderBackupFile(
    HeaderBackupFile backup, {
    required String? destinationPath,
    required String? destinationTreeUri,
    required String fileName,
  }) {
    return _hashApi.writeExternalFileBytes(
      destinationPath: destinationPath,
      destinationTreeUri: destinationTreeUri,
      fileName: fileName,
      bytes: backup.encode(),
    );
  }
}