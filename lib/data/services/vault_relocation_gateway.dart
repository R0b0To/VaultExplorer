import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/api/vault_storage_api.dart';
import 'package:vaultexplorer/data/services/vault_relocation_service.dart';

/// Registers a listener for byte-progress of native operations and returns the function that removes it.
/// The relocation shares the Split/Join progress channel, so the listener is told which operation each tick is for.
typedef RelocationProgressSubscribe =
    void Function() Function(
      void Function(int opId, int bytesDone, int bytesTotal) listener,
    );

/// [RelocationGateway] over the platform channel: turns the native calls into the service's vocabulary,
/// forwarding progress for the operation in flight and mapping native error codes to [RelocationFailure].
class VaultRelocationGateway implements RelocationGateway {
  VaultRelocationGateway({
    required VaultStorageApi storage,
    required RelocationProgressSubscribe subscribeProgress,
    required Future<void> Function(int opId) cancelOperation,
  }) : _storage = storage,
       _subscribeProgress = subscribeProgress,
       _cancelOperation = cancelOperation;

  final VaultStorageApi _storage;
  final RelocationProgressSubscribe _subscribeProgress;
  final Future<void> Function(int opId) _cancelOperation;

  @override
  Future<RelocationCopy> copyIn({
    required String sourceUri,
    required bool isFolderVault,
    required String displayName,
    required int opId,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) => _withProgress(opId, onProgress, () async {
    final r = await _storage.relocateToAppStorage(
      sourceUri: sourceUri,
      isFolderVault: isFolderVault,
      displayName: displayName,
      opId: opId,
    );
    return _asCopy(r);
  });

  @override
  Future<RelocationCopy?> copyOut({
    required String sourceUri,
    required bool isFolderVault,
    required String displayName,
    required int opId,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) => _withProgress(opId, onProgress, () async {
    final r = await _storage.relocateFromAppStorage(
      sourceUri: sourceUri,
      isFolderVault: isFolderVault,
      displayName: displayName,
      opId: opId,
    );
    return r == null ? null : _asCopy(r);
  });

  @override
  Future<RelocationFinalize> finalize({
    required String oldUri,
    required String newUri,
    required bool isFolderVault,
    required bool deleteSource,
  }) async {
    try {
      final r = await _storage.finalizeRelocation(
        oldUri: oldUri,
        newUri: newUri,
        isFolderVault: isFolderVault,
        deleteSource: deleteSource,
      );
      return RelocationFinalize(
        sourceDeleted: r.sourceDeleted,
        automationReset: r.automationReset,
        reason: r.reason,
      );
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }
  }

  @override
  Future<void> discardCopy({required String uri, required bool isFolderVault}) async {
    try {
      await _storage.discardRelocationCopy(uri: uri, isFolderVault: isFolderVault);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }
  }

  @override
  Future<void> cancel(int opId) => _cancelOperation(opId);

  Future<T> _withProgress<T>(
    int opId,
    void Function(int bytesDone, int bytesTotal)? onProgress,
    Future<T> Function() body,
  ) async {
    void Function()? unsubscribe;
    if (onProgress != null) {
      unsubscribe = _subscribeProgress((id, done, total) {
        if (id == opId) onProgress(done, total);
      });
    }
    try {
      return await body();
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    } finally {
      unsubscribe?.call();
    }
  }

  RelocationCopy _asCopy(VaultCopyResult r) {
    if (r.uri.isEmpty) {
      throw const RelocationException(
        RelocationFailure.io,
        message: 'The platform returned no location for the copy',
      );
    }
    return RelocationCopy(uri: r.uri, bytes: r.bytes, files: r.files);
  }

  /// Maps a native error to a [RelocationException]. Unknown codes become [RelocationFailure.io].
  static RelocationException mapPlatformException(PlatformException e) {
    final failure = switch (e.code) {
      'VAULT_UNLOCKED' => RelocationFailure.vaultUnlocked,
      'UNSUPPORTED_SOURCE' => RelocationFailure.unsupportedSource,
      'SPLIT_UNSUPPORTED' => RelocationFailure.splitContainer,
      'NOT_A_VAULT_FOLDER' => RelocationFailure.notAVaultFolder,
      'DESTINATION_NOT_EMPTY' => RelocationFailure.destinationNotEmpty,
      'ALREADY_IN_APP_STORAGE' => RelocationFailure.alreadyInAppStorage,
      'NOT_IN_APP_STORAGE' => RelocationFailure.notInAppStorage,
      'SOURCE_MISSING' => RelocationFailure.sourceMissing,
      'INSUFFICIENT_SPACE' => RelocationFailure.insufficientSpace,
      'VERIFY_FAILED' => RelocationFailure.verifyFailed,
      'CANCELLED' => RelocationFailure.cancelled,
      'NO_PICKER' => RelocationFailure.noPicker,
      _ => RelocationFailure.io,
    };
    int? needed;
    int? available;
    final details = e.details;
    if (details is Map) {
      needed = (details['neededBytes'] as num?)?.toInt();
      available = (details['availableBytes'] as num?)?.toInt();
    }
    return RelocationException(
      failure,
      message: e.message,
      neededBytes: needed,
      availableBytes: available,
    );
  }
}
