import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';

/// Interface the Tools-tab UI (splitter/join sheet, single-file crypto
/// sheet, repair wizard) calls into to actually perform an operation.
///
/// Split/Join is wired up: [NativeContainerToolService] (the default
/// [instance]) calls through to `SplitJoinHandlers` on the Kotlin side via
/// [VaultExplorerApi.splitContainer]/[VaultExplorerApi.joinContainer].
/// Splitting/joining an unmounted container file never touches a `volId`
/// or the crypto engine at all — it only ever moves ciphertext bytes
/// around exactly as they sit on disk — so, unlike the methods below, it
/// doesn't go through `ContainerFileSystem.withReadLock`/`withWriteLock`
/// (`lib/app/ContainerFileSystem.kt`, ownership rule §2.8); there's no
/// mounted volume to lock. It does follow the same shape as import/export
/// otherwise: runs on the native `ioExecutor` off the UI thread and
/// reports progress by opId (`FileOperation.id`) rather than blocking on
/// it, exactly like `importFile`/`importFolder`'s
/// `ImportProgressBridge`-based progress.
///
/// **Single-File Encrypt/Decrypt and Container Check & Repair are not
/// implemented yet.** Per docs/architecture.md §4, that work belongs
/// behind `FileOperationService`
/// (`lib/data/services/file_operation_service.dart`) or `ioExecutor` via
/// `NativeOpSupport` on the Kotlin side, and — for calls that touch a
/// mounted `volId` — `ContainerFileSystem.withReadLock`/`withWriteLock`
/// so they can't race the file browser or background thumbnails.
/// [NativeContainerToolService] inherits [DefaultContainerToolService]'s
/// [UnimplementedError] bodies for all of those; only their bodies need
/// filling in once that native plumbing exists, the same way
/// splitContainer/joinContainer's just were.
///
/// Swap in a real implementation by constructing the widgets below with a
/// different [ContainerToolService], or by replacing
/// [ContainerToolService.instance].
abstract class ContainerToolService {
  static ContainerToolService instance = NativeContainerToolService();

  // ── Container Splitter / Joiner ──────────────────────────────────────

  /// Splits [sourceUri] into `<name>.001`, `<name>.002`, ... chunks of
  /// [chunkSizeBytes] each, written under [destinationPath].
  /// [onProgress] reports bytes written so far out of the source's total
  /// size.
  ///
  /// [destinationTreeUri] should be the destination folder's `treeUri`
  /// from [VaultExplorerApi.pickExtractFolder] whenever the caller has
  /// one -- it lets native fall back to a SAF write when [destinationPath]
  /// turns out not to be directly writable (no "All files access").
  Future<void> splitContainer({
    required String sourceUri,
    required String destinationPath,
    String? destinationTreeUri,
    required int chunkSizeBytes,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  });

  /// Joins a chunk sequence back into one file, starting from
  /// [firstPartUri] (the `.001`/`.part1` chunk) and locating the rest by
  /// naming convention, written to [destinationPath]. [destinationTreeUri]
  /// carries the same SAF-write fallback as [splitContainer]'s.
  Future<void> joinContainer({
    required String firstPartUri,
    required String destinationPath,
    String? destinationTreeUri,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  });

  // ── Single-File Encrypt / Decrypt ────────────────────────────────────

  /// Encrypts [sourceUri] into a standalone AEAD container using
  /// [cipher], a passphrase, and optional keyfiles. Deletes the original
  /// afterward when [deleteOriginalAfter] is true.
  Future<void> encryptFile({
    required String sourceUri,
    required StandaloneCipher cipher,
    required String passphrase,
    List<String> keyfilePaths = const [],
    bool deleteOriginalAfter = false,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  });

  /// Decrypts a standalone AEAD container previously produced by
  /// [encryptFile] back into a plaintext file.
  Future<void> decryptFile({
    required String sourceUri,
    required String passphrase,
    List<String> keyfilePaths = const [],
    void Function(int bytesDone, int bytesTotal)? onProgress,
  });

  // ── Container Check & Repair ─────────────────────────────────────────

  /// Runs the diagnostic scan step: header signature, primary-vs-backup
  /// header parity for unmounted block-container files, or filesystem
  /// superblock/clean-unmount checks for [target]s that resolve to an
  /// on-disk filesystem.
  Future<RepairDiagnosis> diagnoseTarget(RepairTarget target);

  /// Restores the embedded VeraCrypt/LUKS backup header, per
  /// `session_prepare.cpp`'s backup header offset.
  Future<bool> restoreBackupHeader(RepairTarget target);

  /// Runs the native filesystem check-and-fix pass
  /// (`fatfs_chk`/`ntfsfix`/`e2fsck`, dispatched by filesystem type)
  /// against a mounted volume.
  Future<bool> runFilesystemCheck(MountedVolumeTarget target);

  // ── Storage Analyzer ─────────────────────────────────────────────────
  // Storage Analyzer reads real data today via VaultExplorerApi's
  // existing getSpaceInfo/listDirectory calls (see
  // StorageAnalyzerScreen._walkMountedVolume) rather than through this
  // service — there's nothing new to implement there.
}

/// Default [ContainerToolService]: every method throws
/// [UnimplementedError]. See the interface doc comment above for why, and
/// what to wire each method into.
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
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) =>
      throw UnimplementedError('encryptFile is not implemented yet.');

  @override
  Future<void> decryptFile({
    required String sourceUri,
    required String passphrase,
    List<String> keyfilePaths = const [],
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) =>
      throw UnimplementedError('decryptFile is not implemented yet.');

  @override
  Future<RepairDiagnosis> diagnoseTarget(RepairTarget target) =>
      throw UnimplementedError('diagnoseTarget is not implemented yet.');

  @override
  Future<bool> restoreBackupHeader(RepairTarget target) =>
      throw UnimplementedError('restoreBackupHeader is not implemented yet.');

  @override
  Future<bool> runFilesystemCheck(MountedVolumeTarget target) =>
      throw UnimplementedError('runFilesystemCheck is not implemented yet.');
}

/// Real [ContainerToolService] for Split/Join; every other method falls
/// through to [DefaultContainerToolService]'s [UnimplementedError] bodies
/// unchanged. See the interface doc comment above for the full picture.
class NativeContainerToolService extends DefaultContainerToolService {
  int _opIdCounter = 0;
  int _nextOpId() => ++_opIdCounter;

  /// Bridges the opId-keyed, channel-wide [VaultExplorerApi]
  /// split/join-progress event stream into a single call's plain
  /// `void Function(int bytesDone, int bytesTotal)` callback for the
  /// duration of [body], then always unregisters -- the try/finally here
  /// is what stops listeners from piling up across repeated
  /// split/join runs.
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
}