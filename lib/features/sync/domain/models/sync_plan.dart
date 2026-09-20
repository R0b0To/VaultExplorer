import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_state_record.dart';

enum SyncSide { vault, target }

extension SyncSideX on SyncSide {
  SyncSide get other => this == SyncSide.vault ? SyncSide.target : SyncSide.vault;
}

enum SyncActionKind {
  /// Vault -> target (creates the file or replaces the target's copy).
  copyToTarget,

  /// Target -> vault.
  copyToVault,

  deleteOnTarget,
  deleteOnVault,

  /// Both sides changed the same file and neither may silently win: the
  /// loser's version is preserved as a "(... Conflict <timestamp>)" copy
  /// and the winner keeps the original name. See [SyncAction.winner].
  keepBoth,

  /// Both sides already hold the same content: only the ledger row is
  /// written, nothing is transferred.
  adopt,

  /// Gone from both sides: drop the ledger row.
  forget,

  /// Deliberately left alone; see [SyncAction.skipReason].
  skip,
}

enum SyncSkipReason {
  /// The rule's direction forbids writing to the side that would change.
  directionBlocked,

  /// A deletion that `deleteOrphans == false` says not to propagate.
  deletionsDisabled,

  /// A deletion held back by the mass-deletion guard.
  massDeleteGuard,

  /// A file on one side, a folder on the other.
  typeMismatch,

  /// The path sits under a folder that could not be listed.
  unreadableSubtree,
}

@immutable
class SyncAction {
  final SyncActionKind kind;
  final String relPath;

  /// State each side had when the plan was made. The *source* side's state
  /// is what gets recorded as its baseline after a transfer, so a file
  /// edited mid-copy is noticed next run instead of being papered over.
  final SyncSideState? vaultState;
  final SyncSideState? targetState;

  /// Whether the destination already has a file at [relPath] (a replace
  /// rather than a create).
  final bool replacesExisting;

  /// [SyncActionKind.keepBoth] only: the side whose version keeps
  /// [relPath].
  final SyncSide? winner;

  /// [SyncActionKind.keepBoth] only: where the loser's version is kept,
  /// on the loser's side.
  final String? conflictCopyPath;

  /// [SyncActionKind.keepBoth] only: also copy the conflict copy to the
  /// winner's side (two-way rules) so both sides converge.
  final bool propagateConflictCopy;

  final SyncSkipReason? skipReason;

  const SyncAction({
    required this.kind,
    required this.relPath,
    this.vaultState,
    this.targetState,
    this.replacesExisting = false,
    this.winner,
    this.conflictCopyPath,
    this.propagateConflictCopy = false,
    this.skipReason,
  });

  /// Bytes this action will move, for progress reporting.
  int get transferBytes => switch (kind) {
    SyncActionKind.copyToTarget => vaultState?.size ?? 0,
    SyncActionKind.copyToVault => targetState?.size ?? 0,
    SyncActionKind.keepBoth =>
      (winner == SyncSide.vault ? vaultState?.size : targetState?.size) ?? 0,
    _ => 0,
  };

  bool get isDelete =>
      kind == SyncActionKind.deleteOnTarget ||
      kind == SyncActionKind.deleteOnVault;

  bool get movesData =>
      kind == SyncActionKind.copyToTarget ||
      kind == SyncActionKind.copyToVault ||
      kind == SyncActionKind.keepBoth;

  @override
  String toString() =>
      'SyncAction($kind, $relPath${skipReason == null ? '' : ', $skipReason'})';
}

/// Everything one reconciliation decided, in a stable order.
@immutable
class SyncPlan {
  final String ruleId;
  final List<SyncAction> actions;

  /// True when the mass-deletion guard held deletions back. The caller
  /// should tell the user rather than retry silently.
  final bool deletionsBlocked;

  const SyncPlan({
    required this.ruleId,
    required this.actions,
    this.deletionsBlocked = false,
  });

  /// Actions that change something (everything except [SyncActionKind.skip]).
  Iterable<SyncAction> get work =>
      actions.where((a) => a.kind != SyncActionKind.skip);

  int countOf(SyncActionKind kind) =>
      actions.where((a) => a.kind == kind).length;

  int get skippedCount => countOf(SyncActionKind.skip);

  bool get isEmpty => work.isEmpty;
}

/// Progress snapshot while a plan executes.
@immutable
class SyncProgress {
  final String ruleId;
  final int totalActions;
  final int doneActions;
  final int failedActions;
  final String? currentPath;

  const SyncProgress({
    required this.ruleId,
    required this.totalActions,
    required this.doneActions,
    required this.failedActions,
    this.currentPath,
  });
}

/// Outcome of executing one plan.
@immutable
class SyncRunReport {
  final String ruleId;
  final int copied;
  final int deleted;
  final int conflictsKeptBoth;
  final int adopted;
  final int skipped;
  final int failed;
  final bool cancelled;
  final bool deletionsBlocked;

  /// The scan could not read part of a side, so some paths were left
  /// alone this run.
  final bool incompleteScan;

  const SyncRunReport({
    required this.ruleId,
    this.copied = 0,
    this.deleted = 0,
    this.conflictsKeptBoth = 0,
    this.adopted = 0,
    this.skipped = 0,
    this.failed = 0,
    this.cancelled = false,
    this.deletionsBlocked = false,
    this.incompleteScan = false,
  });

  /// Whether it is reasonable to stamp `lastSyncedAt`: nothing failed and
  /// the run was neither cancelled nor partial.
  bool get completedCleanly =>
      !cancelled && failed == 0 && !incompleteScan && !deletionsBlocked;

  /// Whether the run changed anything (files, or what the ledger knows).
  /// A run that only confirmed everything is in step is not "work" -- live
  /// watching runs often, and shouldn't rewrite the config each time.
  bool get didWork => copied + deleted + conflictsKeptBoth + adopted > 0;

  /// Something the user may want to look at: a file failed, part of a side
  /// couldn't be read, or deletions were held back as suspicious.
  bool get needsAttention =>
      !cancelled && (failed > 0 || incompleteScan || deletionsBlocked);
}
