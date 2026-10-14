import 'package:vaultexplorer/data/models/mounted_container.dart';

import 'filesystem_type.dart';
import 'volume_filesystem_registry.dart';

/// Whether an ext2/3/4 disk-image container is allowed to hold names that
/// differ only by capitalization ("Notes" and "notes" side by side).
///
/// Turning this on changes [resolveFilesystemType] to return
/// [FilesystemType.extPortable] for ext containers, which makes the
/// create / rename / save-as dialogs and the advanced-rename preview treat
/// those two names as different. It deliberately does NOT relax the
/// character, trailing-dot or reserved-name rules (see
/// [FilesystemType.extPortable]).
///
/// Leave this `false` until every path that moves names *out of* an ext
/// container compares them the way the destination does. Currently done:
/// the folder/sibling copy guard in `FileOperationService`. Still to do:
/// paste conflict detection and the `ConflictPlan` keys (both lowercase the
/// name), the Kotlin import/paste planning in `ImportExportHandlers.kt`
/// (`existingNamesLowercase`, `uniqueNameAgainst`), and export / archive
/// extract / scheduled sync.
const bool kAllowCaseDistinctNamesInExtContainers = false;

/// The concrete filesystem recorded for a natively mounted disk-image
/// [container] (FAT32 / exFAT / NTFS / ext), or `null` when it is unknown:
/// not recorded yet, the native query failed, the label wasn't recognised,
/// or the container isn't a disk-image volume at all (local storage and the
/// folder-vault formats never have an entry).
FilesystemType? detectedFilesystemType(MountedContainer container) {
  if (container.volId < 0) return null;
  return VolumeFilesystemRegistry.lookup(container.volId);
}

/// Resolves which [FilesystemType] a given [MountedContainer]'s names
/// should be validated against. See docs/architecture.md ADR-002 (§ item 2).
///
/// - CryFS/Cryptomator/gocryptfs store names as encrypted blobs, not as
///   characters on a physical FAT/NTFS/ext volume, so they resolve to
///   [FilesystemType.encryptedVault] — real filesystem character rules
///   don't apply to the plaintext name the user types.
/// - A native disk-image container (VeraCrypt/LUKS/BitLocker/VHD/VHDX) is
///   mounted as FAT, exFAT, NTFS, or ext2/3/4. The concrete kind is read
///   from the mounted volume (see [VolumeFilesystemRegistry]); today every
///   one of them still resolves to [FilesystemType.unknownConservative]
///   for *name rules*, except an ext volume when
///   [kAllowCaseDistinctNamesInExtContainers] is on, which resolves to
///   [FilesystemType.extPortable].
/// - A plain folder vault (SAF-backed) could be backed by *any* real host
///   filesystem, which isn't knowable from here, so it also resolves to
///   [FilesystemType.unknownConservative].
///
/// [FilesystemType.unknownConservative] is the safe default: it never
/// under-restricts (never lets through a name that would actually be
/// illegal on the real target), it can only over-restrict compared to what
/// a fully wired-through concrete type would allow.
FilesystemType resolveFilesystemType(MountedContainer container) {
  final format = container.format;
  if (format.isCryfs || format.isCryptomator || format.isGocryptfs) {
    return FilesystemType.encryptedVault;
  }
  if (kAllowCaseDistinctNamesInExtContainers &&
      detectedFilesystemType(container) == FilesystemType.ext) {
    return FilesystemType.extPortable;
  }
  return FilesystemType.unknownConservative;
}

/// Whether [container] really treats "Notes" and "notes" as different names
/// -- a fact about the destination filesystem, NOT a naming policy.
///
/// This is separate from [resolveFilesystemType] on purpose: the name
/// policy can stay conservative while this still reports what the target
/// will actually do with two names that differ only by case. Copy code uses
/// it to decide whether two siblings are going to land on the same entry
/// (and silently overwrite each other) at the destination.
///
/// `true` for the encrypted folder-vault formats (names are encrypted, so
/// distinct plaintext names are distinct entries) and for a volume
/// recorded as ext. `false` for FAT/exFAT/NTFS, and `false` whenever the
/// answer isn't known (local storage, SAF folders, an unrecorded volume):
/// assuming case-insensitive can only make a copy refuse a colliding
/// sibling, never overwrite one.
bool isDestinationCaseSensitive(MountedContainer container) {
  final format = container.format;
  if (format.isCryfs || format.isCryptomator || format.isGocryptfs) {
    return true;
  }
  final detected = detectedFilesystemType(container);
  return detected != null && FilesystemRules.of(detected).caseSensitive;
}
