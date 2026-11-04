library;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

/// What kind of storage one side of a Vault Sync comparison lives on.
enum VaultSyncTargetKind {
  /// A mounted, encrypted vault container.
  vault,

  /// Plain device storage reached through the file system (the primary
  /// "Local Storage" root, or a saved folder on internal/removable storage).
  deviceStorage,

  /// A folder granted through Android's Storage Access Framework -- an SD
  /// card, USB drive, or a cloud/document provider such as Google Drive.
  documentProvider,
}

/// Classifies [container]. Device storage and document-provider folders are
/// modelled as pseudo-containers with a negative `volId` (see
/// `local_storage_container.dart`); a `content://` URI marks a SAF tree.
VaultSyncTargetKind syncTargetKindOf(MountedContainer container) {
  if (container.isSafStorage) return VaultSyncTargetKind.documentProvider;
  if (container.isLocalStorage) return VaultSyncTargetKind.deviceStorage;
  return VaultSyncTargetKind.vault;
}

/// One side of a Vault Sync comparison: a storage target plus the folder
/// within it being compared. The target is a [MountedContainer] -- either a
/// real vault, or one of the app's pseudo-containers for device storage or a
/// document-provider folder. [relativePath] is `''` for the container's
/// root -- same convention as [VaultFileIoApi.listDirectory].
@immutable
class VaultSyncSide {
  final MountedContainer container;
  final String relativePath;

  const VaultSyncSide({required this.container, required this.relativePath});

  /// The kind of storage this side lives on.
  VaultSyncTargetKind get kind => syncTargetKindOf(container);

  /// Whether files on this side are stored encrypted (vaults only). Device
  /// storage and document providers hold plain files.
  bool get isEncrypted => kind == VaultSyncTargetKind.vault;

  /// True when this side and [other] point at the same folder, or one is
  /// nested inside the other. Syncing such a pair would copy a folder into
  /// itself, so callers refuse to compare them.
  ///
  /// Best effort: sides are compared within one namespace -- the same vault,
  /// the same file-system path, or the same SAF tree URI. Two different SAF
  /// grants that happen to overlap on the provider can't be detected.
  bool overlapsWith(VaultSyncSide other) {
    final a = _location;
    final b = other._location;
    if (a.scope != b.scope) return false;
    return _isSameOrWithin(a.path, b.path) || _isSameOrWithin(b.path, a.path);
  }

  ({String scope, String path}) get _location => switch (kind) {
    VaultSyncTargetKind.deviceStorage => (
      scope: 'fs',
      path: p.posix.normalize(
        p.posix.join(container.uri, _trimSlashes(relativePath)),
      ),
    ),
    VaultSyncTargetKind.documentProvider => (
      scope: 'saf:${container.uri}',
      path: _trimSlashes(relativePath),
    ),
    VaultSyncTargetKind.vault => (
      scope: 'vault:${container.volId}',
      path: _trimSlashes(relativePath),
    ),
  };

  static String _trimSlashes(String path) =>
      path.split('/').where((s) => s.isNotEmpty).join('/');

  /// Whether [child] is [parent] itself or lies beneath it. An empty
  /// [parent] is a container root, which contains everything.
  static bool _isSameOrWithin(String parent, String child) {
    if (parent.isEmpty || parent == child) return true;
    final prefix = parent.endsWith('/') ? parent : '$parent/';
    return child.startsWith(prefix);
  }

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

/// The names the UI shows for the two compared storages, in place of a
/// generic "left" and "right".
@immutable
class VaultSyncNames {
  final String left;
  final String right;

  const VaultSyncNames({required this.left, required this.right});

  String of({required bool isLeft}) => isLeft ? left : right;
}

/// Picks the display name for each compared storage.
///
/// Normally that is just the storage's own name. When both sides would read
/// the same -- two folders in one vault, say -- the folder is added to tell
/// them apart, and as a last resort a number is. A side that hasn't been
/// chosen yet gets its [leftFallback] / [rightFallback] text.
VaultSyncNames vaultSyncNamesFor(
  VaultSyncSide? left,
  VaultSyncSide? right, {
  required String leftFallback,
  required String rightFallback,
}) {
  if (left == null || right == null) {
    return VaultSyncNames(
      left: left?.container.displayName ?? leftFallback,
      right: right?.container.displayName ?? rightFallback,
    );
  }
  String full(VaultSyncSide s) => s.relativePath.isEmpty
      ? s.container.displayName
      : '${s.container.displayName} / ${s.relativePath}';

  var l = left.container.displayName;
  var r = right.container.displayName;
  if (l == r) {
    l = left.displayLabel;
    r = right.displayLabel;
  }
  if (l == r) {
    l = full(left);
    r = full(right);
  }
  if (l == r) {
    l = '$l (1)';
    r = '$r (2)';
  }
  return VaultSyncNames(left: l, right: r);
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

  /// Folder explorer only: a file on both sides with the same size, i.e.
  /// already in sync. A full scan never puts these in its diff list -- they
  /// only appear when the user browses all items.
  identical,

  /// Folder explorer only: a folder that exists on both sides. Open it to
  /// compare what is inside.
  bothFolders,
}

/// What a sync run does with a [VaultDiffEntry]: copy it to the other side,
/// delete the copy on one side, or leave it untouched. Chosen per-entry,
/// either from a [SyncDirection] default or an explicit user override.
enum EntryAction {
  copyToLeft,
  copyToRight,

  /// Permanently delete this path from the left side.
  deleteLeft,

  /// Permanently delete this path from the right side.
  deleteRight,
  skip;

  bool get isCopy => this == copyToLeft || this == copyToRight;
  bool get isDelete => this == deleteLeft || this == deleteRight;
}

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

  /// Make the right side an exact copy of the left side: everything on the
  /// left is copied over (whichever copy is newer), and anything that exists
  /// only on the right is deleted.
  mirrorToRight,

  /// Make the left side an exact copy of the right side: everything on the
  /// right is copied over (whichever copy is newer), and anything that exists
  /// only on the left is deleted.
  mirrorToLeft;

  /// Whether this direction deletes items that exist only on the target side.
  bool get deletesExtras =>
      this == SyncDirection.mirrorToRight || this == SyncDirection.mirrorToLeft;
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

/// The direct children of one folder as compared by
/// `VaultSyncService.listFolder`.
@immutable
class VaultSyncFolderListing {
  final List<VaultDiffEntry> entries;

  /// True when a vault folder couldn't be read, so [entries] is empty rather
  /// than a trustworthy "this folder is empty".
  final bool unreadable;

  const VaultSyncFolderListing({required this.entries, this.unreadable = false});
}

/// Which sides a [VaultDiffEntry] exists on. A type-mismatched entry (file on
/// one side, folder on the other) exists on both.
extension VaultDiffEntrySides on VaultDiffEntry {
  bool get existsOnLeft => status != VaultDiffStatus.onlyRight;
  bool get existsOnRight => status != VaultDiffStatus.onlyLeft;
}

/// Stages of a `VaultSyncService.scanDiff` run.
/// [failed]: a folder inside a vault couldn't be read, so the comparison was
/// abandoned instead of treating that folder as empty.
enum VaultSyncScanStage { idle, comparing, complete, cancelled, failed }

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
