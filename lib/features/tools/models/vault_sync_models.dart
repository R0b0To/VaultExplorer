library;

import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

/// One side of a Vault Sync comparison: a mounted container plus the
/// folder within it being compared. [relativePath] is `''` for the
/// container's root -- same convention as [VaultFileIoApi.listDirectory].
@immutable
class VaultSyncSide {
  final MountedContainer container;
  final String relativePath;

  const VaultSyncSide({required this.container, required this.relativePath});

  /// Short "Vault / Folder" label for display, e.g. "Backups / photos".
  /// Falls back to just the vault name when [relativePath] is the root.
  String get displayLabel {
    if (relativePath.isEmpty) return container.displayName;
    return '${container.displayName} / ${relativePath.split('/').last}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaultSyncSide &&
          other.container.volId == container.volId &&
          other.relativePath == relativePath;

  @override
  int get hashCode => Object.hash(container.volId, relativePath);

  @override
  String toString() => 'VaultSyncSide(${container.displayName}:$relativePath)';
}

/// How a single relative path compares between the left and right side of
/// a [VaultSyncSide] scan.
enum VaultDiffStatus {
  /// Exists on the left side only.
  onlyLeft,

  /// Exists on the right side only.
  onlyRight,

  /// Exists on both sides; the left copy has a newer modified time.
  leftNewer,

  /// Exists on both sides; the right copy has a newer modified time.
  rightNewer,

  /// Exists on both sides but can't be resolved automatically -- either
  /// the same modified time with a different size, or a file on one side
  /// and a folder on the other (see [VaultDiffEntry.typeMismatch]).
  conflicted,
}

/// Which side a sync run should copy a [VaultDiffEntry] to, or whether it's
/// left untouched. Chosen per-entry, either from a [SyncDirection] default
/// or an explicit user override.
enum EntryAction { copyToLeft, copyToRight, skip }

/// The scope of a one-click Vault Sync run.
enum SyncDirection {
  /// Copy each entry to whichever side is missing it or holds an older copy.
  twoWay,

  /// Only push changes from the left side to the right side; the left side
  /// is never modified.
  leftToRight,

  /// Only push changes from the right side to the left side; the right
  /// side is never modified.
  rightToLeft,
}

/// One differing path discovered by `VaultSyncService.scanDiff`. Identical
/// files (same size and modified time on both sides) never become an
/// entry -- only paths that need attention do.
@immutable
class VaultDiffEntry {
  /// Path relative to both compared roots, e.g. "photos/2024/beach.jpg".
  final String relativePath;

  /// Basename of [relativePath].
  final String name;

  final bool isDir;
  final VaultDiffStatus status;

  /// True when the same [relativePath] is a file on one side and a folder
  /// on the other. Copying can't safely replace one with the other, so
  /// these are always excluded from automatic sync plans and left for the
  /// user to resolve by hand in the file browser.
  final bool typeMismatch;

  /// Size / modified time on the left side; null when absent there.
  final int? leftSizeBytes;
  final int? leftModifiedSecs;

  /// Size / modified time on the right side; null when absent there.
  final int? rightSizeBytes;
  final int? rightModifiedSecs;

  const VaultDiffEntry({
    required this.relativePath,
    required this.name,
    required this.isDir,
    required this.status,
    this.typeMismatch = false,
    this.leftSizeBytes,
    this.leftModifiedSecs,
    this.rightSizeBytes,
    this.rightModifiedSecs,
  });

  /// Stable identity for this path within one scan -- used as the map key
  /// for per-entry action overrides and the resolved sync plan.
  String get id => relativePath;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaultDiffEntry && other.relativePath == relativePath;

  @override
  int get hashCode => relativePath.hashCode;

  @override
  String toString() => 'VaultDiffEntry($relativePath, $status)';
}

/// Stages of a `VaultSyncService.scanDiff` run.
enum VaultSyncScanStage { idle, comparing, complete, cancelled }

/// Snapshot of live scan progress emitted while comparing two sides.
@immutable
class VaultSyncScanProgress {
  final VaultSyncScanStage stage;
  final int dirsScanned;
  final int entriesCompared;
  final String? currentPath;

  const VaultSyncScanProgress({
    required this.stage,
    this.dirsScanned = 0,
    this.entriesCompared = 0,
    this.currentPath,
  });
}

/// One update emitted while `VaultSyncService.scanDiff` walks both sides.
@immutable
class VaultSyncScanUpdate {
  final VaultSyncScanProgress progress;
  final List<VaultDiffEntry> entries;

  /// Files found on both sides with matching size and modified time --
  /// already in sync, so they're never included in [entries].
  final int identicalCount;

  const VaultSyncScanUpdate({
    required this.progress,
    required this.entries,
    required this.identicalCount,
  });
}
