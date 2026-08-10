import 'package:vaultexplorer/data/models/mounted_container.dart';
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