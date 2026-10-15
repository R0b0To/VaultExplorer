import 'package:vaultexplorer/data/models/mounted_container.dart';

import 'filesystem_type.dart';
import 'volume_filesystem_registry.dart';

/// Whether an ext2/3/4 disk-image container is allowed to hold names that
/// differ only by capitalization ("Notes" and "notes" side by side).
///
/// When `true`, [resolveFilesystemType] returns
/// [FilesystemType.extPortable] for an ext volume, so the create / rename /
/// save-as dialogs, the advanced-rename preview, paste conflict detection,
/// conflict-plan keys and import planning all treat those two names as
/// different. It deliberately does NOT relax the character, trailing-dot or
/// reserved-name rules (see [FilesystemType.extPortable]).
///
/// This is only safe because every path that moves names *out of* an ext
/// container checks them against what the destination really does (see
/// [isDestinationCaseSensitive] and docs/architecture.md §2 rule 12): the
/// folder/sibling copy guard in `FileOperationService`, the import
/// child-collision handling, the export handling (`ImportExportHandlers`
/// multi-export and the automation `exportFolder`) and the archive-extract
/// plan (`ArchiveService.caseSafeExtractPlan`). Each keeps both colliding
/// entries by giving the later one a unique name ("notes (1)"), and none of
/// them depends on this switch.
///
/// Setting it back to `false` is a complete rollback: ext volumes go back to
/// the conservative case-insensitive name rules, and nothing else changes.
const bool kAllowCaseDistinctNamesInExtContainers = true;

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
///   from the mounted volume (see [VolumeFilesystemRegistry]). For *name
///   rules* an ext volume resolves to [FilesystemType.extPortable] while
///   [kAllowCaseDistinctNamesInExtContainers] is on; every other disk-image
///   volume, and an ext volume whose filesystem hasn't been recorded yet,
///   resolves to [FilesystemType.unknownConservative].
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

/// Whether name comparisons for [container] (conflict detection, conflict
/// plan keys, unique-name generation) should be case-sensitive. This is the
/// *policy* answer -- `FilesystemRules.of(resolveFilesystemType(...))` --
/// so it follows [kAllowCaseDistinctNamesInExtContainers]; contrast
/// [isDestinationCaseSensitive], which is what the destination really does.
bool namesAreCaseSensitive(MountedContainer container) =>
    FilesystemRules.of(resolveFilesystemType(container)).caseSensitive;

/// Folds [name] for comparison: unchanged when [caseSensitive], otherwise
/// lowercased. Every set of existing names and every `ConflictPlan` key
/// that is compared against another must be folded with the same
/// [caseSensitive] value.
String foldEntryName(String name, {required bool caseSensitive}) =>
    caseSensitive ? name : name.toLowerCase();

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
