library;

import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/hash_verifier_models.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';

/// What kind of checksum work a run of the File Checksum & Hash Verifier
/// tool represents: individually-picked files, or every file discovered by
/// scanning a whole vault. The two are deliberately different types (not
/// just a flag) so a vault operation stays identifiable as such everywhere
/// it flows through the app, instead of collapsing into a plain
/// `List<CryptoSourceItem>` indistinguishable from a manual selection --
/// see the vault-wide checksum implementation plan, §1-2.
sealed class HashOperation {
  const HashOperation();
}

/// A batch of individually-picked sources -- external/on-device files
/// and/or vault files chosen one at a time in [VaultFilePickerSheet]. This
/// is the Compute tab's existing behavior; it goes straight to
/// [HashVerifierService.computeHashes] without a scanning or confirmation
/// phase (plan §6).
class FileHashOperation extends HashOperation {
  final List<CryptoSourceItem> sources;
  const FileHashOperation(this.sources);
}

/// Every file discovered by recursively scanning [vault] with
/// [VaultFileScanner], rather than selected by hand. Powers the "Check
/// entire vault" workflow (plan §1, §7-11).
class VaultHashOperation extends HashOperation {
  final MountedContainer vault;
  const VaultHashOperation(this.vault);
}

/// Phases a vault-wide checksum run moves through. A [FileHashOperation]
/// has no use for [scanning] or [confirming] -- it goes straight from
/// [selecting] to [hashing] (plan §6).
enum HashOperationPhase {
  selecting,
  scanning,
  confirming,
  hashing,
  completed,
  cancelled,
  failed,
}

/// Structured, UI-agnostic progress for a running [VaultHashOperation] --
/// the widget renders directly off this instead of inferring scan/hash
/// state from a pile of loose booleans and counters (plan §8).
class HashOperationProgress {
  final HashOperationPhase phase;

  final int discoveredFiles;
  final int completedFiles;
  final int failedFiles;

  final int discoveredBytes;
  final int processedBytes;

  final String? currentPath;
  final int? currentFileBytes;
  final int? currentFileProcessedBytes;

  /// Set only when [phase] is [HashOperationPhase.failed] -- an
  /// operation-level problem (vault unmounted mid-scan, traversal gone
  /// unrecoverable), distinct from a per-file [HashComputeResult.error],
  /// which never aborts the run (plan §11).
  final String? failureMessage;

  /// Populated only on the final progress event of the hashing phase, once
  /// [phase] reaches [HashOperationPhase.completed] or
  /// [HashOperationPhase.cancelled] (plan §10).
  final HashOperationAggregateResult? aggregate;

  const HashOperationProgress({
    this.phase = HashOperationPhase.selecting,
    this.discoveredFiles = 0,
    this.completedFiles = 0,
    this.failedFiles = 0,
    this.discoveredBytes = 0,
    this.processedBytes = 0,
    this.currentPath,
    this.currentFileBytes,
    this.currentFileProcessedBytes,
    this.failureMessage,
    this.aggregate,
  });

  /// 0.0-1.0 estimate for the hashing phase's linear progress indicator.
  /// `null` outside the hashing phase, or while [discoveredBytes] isn't
  /// known yet -- callers should fall back to an indeterminate indicator
  /// rather than guess.
  double? get hashingFraction {
    if (phase != HashOperationPhase.hashing || discoveredBytes <= 0) return null;
    return (processedBytes / discoveredBytes).clamp(0.0, 1.0);
  }

  /// 0.0-1.0 estimate for the *current file's* progress bar, for a file
  /// large enough that a sub-progress readout is worth showing. `null`
  /// when either figure isn't known yet.
  double? get currentFileFraction {
    final total = currentFileBytes;
    final done = currentFileProcessedBytes;
    if (total == null || done == null || total <= 0) return null;
    return (done / total).clamp(0.0, 1.0);
  }
}

/// One discovered-and-hashed file's outcome stays a plain
/// [HashComputeResult] -- this wraps the whole batch with totals rather
/// than replacing the per-file results (plan §9-10).
class HashOperationAggregateResult {
  final List<HashComputeResult> fileResults;
  final int filesChecked;
  final int filesSucceeded;
  final int filesFailed;
  final int bytesProcessed;
  final Duration elapsed;

  const HashOperationAggregateResult({
    required this.fileResults,
    required this.filesChecked,
    required this.filesSucceeded,
    required this.filesFailed,
    required this.bytesProcessed,
    required this.elapsed,
  });
}