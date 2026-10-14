import 'filesystem_type.dart';

/// Maps the label the native layer reports for a mounted volume (the
/// `fileSystem` entry of `getVaultInfo`, produced by `fsGetFilesystemLabel`
/// in `fs_ops.cpp`) to the [FilesystemType] whose rules apply to it.
///
/// Native reports `FAT12` / `FAT16` / `FAT32` / `exFAT` / `NTFS` / `ext2` /
/// `ext3` / `ext4`. FAT12 and FAT16 share FAT32's naming grammar and the
/// rule table has no separate entry for them, so all three map to
/// [FilesystemType.fat32]; the three ext generations map to
/// [FilesystemType.ext] for the same reason.
///
/// Returns `null` for `null`, an empty string, or any label this table
/// doesn't recognise. Callers must treat `null` as "unknown" and fall back
/// to the conservative rules -- never guess a concrete type.
FilesystemType? filesystemTypeFromLabel(String? label) {
  if (label == null) return null;
  switch (label.trim().toLowerCase()) {
    case 'fat12':
    case 'fat16':
    case 'fat32':
      return FilesystemType.fat32;
    case 'exfat':
      return FilesystemType.exfat;
    case 'ntfs':
      return FilesystemType.ntfs;
    case 'ext2':
    case 'ext3':
    case 'ext4':
      return FilesystemType.ext;
    default:
      return null;
  }
}

/// Process-wide record of which concrete filesystem each natively mounted
/// disk-image volume turned out to have, keyed by native volume id.
///
/// This is deliberately a plain registry rather than a field on
/// `MountedContainer`: `MountedContainer` is constructed in a dozen places
/// (unlock, USB, composite, background sync, automation API, ...) and the
/// concrete filesystem is only known once the volume is mounted, so the
/// dashboard controller records it once at the single point where a mounted
/// container is added (`onContainerMounted` / `onUsbContainerReconnected`)
/// and drops it in `onContainerLocked`.
///
/// A volume that has not been recorded (yet, or because the native query
/// failed) simply has no entry, and every consumer falls back to the
/// conservative behaviour for "unknown".
class VolumeFilesystemRegistry {
  VolumeFilesystemRegistry._();

  static final Map<int, FilesystemType> _byVolId = <int, FilesystemType>{};

  /// The concrete type recorded for [volId], or `null` if unknown.
  static FilesystemType? lookup(int volId) => _byVolId[volId];

  /// Records [type] for [volId]. A `null` [type] clears any earlier entry,
  /// so a re-used volume id can never inherit a stale filesystem.
  static void record(int volId, FilesystemType? type) {
    if (type == null) {
      _byVolId.remove(volId);
    } else {
      _byVolId[volId] = type;
    }
  }

  /// Drops whatever is recorded for [volId] (the volume was locked).
  static void forget(int volId) => _byVolId.remove(volId);

  /// Test-only: removes every entry.
  static void clearForTesting() => _byVolId.clear();
}
