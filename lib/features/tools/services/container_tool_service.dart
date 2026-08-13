import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/utils/secure_temp_file.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';

abstract class ContainerToolService {
  static ContainerToolService instance = NativeContainerToolService();

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

  Future<RepairDiagnosis> diagnoseTarget(RepairTarget target, {void Function(String message)? onLogLine});

  /// [password] is only consulted for a VeraCrypt/TrueCrypt
  /// [UnmountedFileTarget] -- pass it null on the first call and catch
  /// [RepairPasswordRequiredException] to know whether one is actually
  /// needed; other formats (currently just LUKS2) never throw it. Throws
  /// [RepairIncorrectPasswordException] if [password] was supplied but
  /// didn't verify, and [RepairUnsupportedFormatException] for formats
  /// with no restore path implemented (LUKS1, BitLocker) or for a
  /// [MountedVolumeTarget] (restoring a header only makes sense for an
  /// unmounted file -- a volume with a bad header couldn't have mounted in
  /// the first place).
  Future<bool> restoreBackupHeader(RepairTarget target, {String? password, void Function(String message)? onLogLine});
  Future<bool> runFilesystemCheck(MountedVolumeTarget target, {void Function(String message)? onLogLine});

  /// Runs [encryptFile]/[decryptFile] across a batch of [sources], staging
  /// vault-sourced input through a temp file and vault-destined output
  /// through a temp directory that gets written back via
  /// [VaultExplorerApi.writeBackFile]. Temp files/dirs are always cleaned
  /// up, even on failure.
  ///
  /// Per-file failures are collected into [BatchCryptoBatchResult.failedNames]
  /// and the batch continues; an [UnimplementedError] or an `AUTH_FAIL`
  /// [PlatformException] aborts the whole batch immediately (see
  /// [BatchCryptoBatchResult.abortReason]).
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
  @override
  Future<void> splitContainer({
    required String sourceUri,
    required String destinationPath,
    String? destinationTreeUri,
    required int chunkSizeBytes,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) =>
      throw UnimplementedError('splitContainer is not implemented yet.');

  @override
  Future<void> joinContainer({
    required String firstPartUri,
    required String destinationPath,
    String? destinationTreeUri,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) =>
      throw UnimplementedError('joinContainer is not implemented yet.');

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
  }) =>
      throw UnimplementedError('encryptFile is not implemented yet.');

  @override
  Future<void> decryptFile({
    required String sourceUri,
    required String passphrase,
    List<String> keyfilePaths = const [],
    String? destinationPath,
    String? destinationTreeUri,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) =>
      throw UnimplementedError('decryptFile is not implemented yet.');

  @override
  Future<RepairDiagnosis> diagnoseTarget(RepairTarget target, {void Function(String message)? onLogLine}) =>
      throw UnimplementedError('diagnoseTarget is not implemented yet.');

  @override
  Future<bool> restoreBackupHeader(RepairTarget target, {String? password, void Function(String message)? onLogLine}) =>
      throw UnimplementedError('restoreBackupHeader is not implemented yet.');

  @override
  Future<bool> runFilesystemCheck(MountedVolumeTarget target, {void Function(String message)? onLogLine}) =>
      throw UnimplementedError('runFilesystemCheck is not implemented yet.');

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
        // 1. Prepare input file path/URI
        //
        // Category D (see docs/temp-file-audit.md, finding TF-08): the
        // native encrypt/decrypt engines invoked below (VeraCrypt/LUKS/gocryptfs-style
        // ciphers, see encryptFile/decryptFile overrides) read and write
        // real files, not Dart streams -- there's no stream/pipe hook to
        // give them instead. When the source lives in a vault, its
        // plaintext genuinely has to land on host disk for the native
        // engine to read it. We keep that surface as small as possible
        // (a private, per-operation temp dir) and always zero-fill +
        // delete it via SecureTempFile in the `finally` below, on every
        // exit path -- success, thrown exception, or auth failure.
        String effectiveSourceUri;

        if (source.isFromVault) {
          tempInDir = await Directory.systemTemp.createTemp('vx_crypto_in_');
          final tempInFile = File(p.join(tempInDir.path, source.displayName));
          final extracted = await vaultExplorerApi.decryptFile(
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

        // 2. Prepare destination path
        //
        // Same Category D constraint in the other direction: the native
        // engine writes its output (plaintext when decrypting, ciphertext
        // when encrypting) to a real path here too.
        String? effectiveDestPath;
        String? effectiveTreeUri;

        if (destination.isVault) {
          tempOutDir = await Directory.systemTemp.createTemp('vx_crypto_out_');
          effectiveDestPath = tempOutDir.path;
          effectiveTreeUri = null;
        } else {
          effectiveDestPath = destination.externalPath;
          effectiveTreeUri = destination.externalTreeUri;
        }

        // 3. Execute crypto operation
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

        // 4. If destination is a vault, copy generated output file(s) into target vault
        if (destination.isVault && tempOutDir != null) {
          final generatedFiles = tempOutDir.listSync().whereType<File>().toList();
          if (generatedFiles.isEmpty) {
            throw Exception('No output file generated by crypto engine');
          }
          for (final outFile in generatedFiles) {
            final outFileName = p.basename(outFile.path);
            final vaultPath = destination.relativePath!.isEmpty
                ? outFileName
                : '${destination.relativePath!}/$outFileName';
            final wroteBack = await vaultExplorerApi.writeBackFile(
              destination.container!,
              vaultPath,
              outFile.path,
            );
            if (!wroteBack) {
              throw Exception('Failed to write output file to target vault');
            }
            await vaultExplorerApi.finishWriteIfCryptomator(
              destination.container!,
              vaultPath,
            );
          }
        }

        // 5. Delete source from vault if requested
        if (deleteOriginal && direction == CryptoDirection.encrypt && source.isFromVault) {
          await vaultExplorerApi.deleteFile(source.container!, source.relativePath!);
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
        // Zero-fill + delete rather than a plain delete -- see the
        // Category D note above. Both are no-ops if the dir was never
        // created (e.g. an external-to-external run touches neither).
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
  int _opIdCounter = 0;
  int _nextOpId() => ++_opIdCounter;

  Future<T> _withProgressListener<T>(
    void Function(int bytesDone, int bytesTotal)? onProgress,
    int opId,
    Future<T> Function() body,
  ) async {
    if (onProgress == null) return body();
    void listener(SplitJoinProgress progress) {
      if (progress.opId == opId) onProgress(progress.bytesDone, progress.bytesTotal);
    }
    VaultExplorerApi.addSplitJoinProgressListener(listener);
    try {
      return await body();
    } finally {
      VaultExplorerApi.removeSplitJoinProgressListener(listener);
    }
  }

  /// Mirrors [_withProgressListener] for the Check & Repair tool's live log
  /// panel -- see RepairLogBridge.kt/reportRepairLog in container_repair.cpp
  /// for where these lines originate.
  Future<T> _withLogListener<T>(
    void Function(String message)? onLogLine,
    int opId,
    Future<T> Function() body,
  ) async {
    if (onLogLine == null) return body();
    void listener(RepairLogLine line) {
      if (line.opId == opId) onLogLine(line.message);
    }
    VaultExplorerApi.addRepairLogListener(listener);
    try {
      return await body();
    } finally {
      VaultExplorerApi.removeRepairLogListener(listener);
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
      return vaultExplorerApi.splitContainer(
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
      return vaultExplorerApi.joinContainer(
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
      return vaultExplorerApi.encryptSingleFile(
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
      return vaultExplorerApi.decryptSingleFile(
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
  Future<RepairDiagnosis> diagnoseTarget(RepairTarget target, {void Function(String message)? onLogLine}) {
    final opId = _nextOpId();
    return _withLogListener(onLogLine, opId, () async {
      final result = switch (target) {
        UnmountedFileTarget(:final uri) =>
          await vaultExplorerApi.diagnoseUnmountedContainerFile(uri, opId: opId),
        MountedVolumeTarget(:final volId) =>
          await vaultExplorerApi.diagnoseMountedVolumeFilesystem(volId, opId: opId),
      };
      return _diagnosisFromCode(result.diagnosisCode);
    });
  }

  @override
  Future<bool> restoreBackupHeader(RepairTarget target, {String? password, void Function(String message)? onLogLine}) {
    if (target is! UnmountedFileTarget) {
      throw const RepairUnsupportedFormatException();
    }
    final opId = _nextOpId();
    return _withLogListener(onLogLine, opId, () {
      return vaultExplorerApi.restoreBackupHeaderUnmounted(
        uri: target.uri,
        password: password,
        opId: opId,
      );
    });
  }

  @override
  Future<bool> runFilesystemCheck(MountedVolumeTarget target, {void Function(String message)? onLogLine}) {
    final opId = _nextOpId();
    return _withLogListener(onLogLine, opId, () {
      return vaultExplorerApi.runMountedVolumeFilesystemCheck(target.volId, opId: opId);
    });
  }
}