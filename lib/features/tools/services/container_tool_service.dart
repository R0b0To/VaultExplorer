import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';

/// Interface the Tools-tab UI (splitter/join sheet, single-file crypto
/// sheet, repair wizard) calls into to actually perform an operation.
///
/// **None of these are implemented yet.** Per docs/architecture.md §4, the
/// real work belongs behind `FileOperationService`
/// (`lib/data/services/file_operation_service.dart`) or `ioExecutor` via
/// `NativeOpSupport` on the Kotlin side, so it reports progress through
/// `ImportProgressBridge`/`OperationActivityPill` and never blocks the UI
/// thread — and, for calls that touch a mounted `volId`,
/// `ContainerFileSystem.withReadLock`/`withWriteLock`
/// (`lib/app/ContainerFileSystem.kt`, ownership rule §2.8) so they can't
/// race the file browser or background thumbnails. [DefaultContainerToolService]
/// intentionally throws [UnimplementedError] from every method — the UI
/// layer is complete and calls through this interface already; only the
/// bodies need filling in once that native plumbing exists.
///
/// Swap in a real implementation by constructing the widgets below with a
/// different [ContainerToolService], or by replacing
/// [ContainerToolService.instance].
abstract class ContainerToolService {
  static ContainerToolService instance = DefaultContainerToolService();

  // ── Container Splitter / Joiner ──────────────────────────────────────

  /// Splits [sourceUri] into `<name>.001`, `<name>.002`, ... chunks of
  /// [chunkSizeBytes] each, written under [destinationPath].
  /// [onProgress] reports bytes written so far out of the source's total
  /// size.
  Future<void> splitContainer({
    required String sourceUri,
    required String destinationPath,
    required int chunkSizeBytes,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  });

  /// Joins a chunk sequence back into one file, starting from
  /// [firstPartUri] (the `.001`/`.part1` chunk) and locating the rest by
  /// naming convention, written to [destinationPath].
  Future<void> joinContainer({
    required String firstPartUri,
    required String destinationPath,
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
    required int chunkSizeBytes,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) =>
      throw UnimplementedError('splitContainer is not implemented yet.');

  @override
  Future<void> joinContainer({
    required String firstPartUri,
    required String destinationPath,
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
