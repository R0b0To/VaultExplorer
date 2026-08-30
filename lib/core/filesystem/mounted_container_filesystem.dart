import 'package:vaultexplorer/data/models/mounted_container.dart';

import 'filesystem_type.dart';
import 'local_storage_container.dart';

/// Resolves which [FilesystemType] a given [MountedContainer]'s names
/// should be validated against. See docs/architecture.md ADR-002 (§ item 2)
/// and ADR-005 for the follow-up that would make the native-disk-image case
/// exact instead of conservative.
///
/// - CryFS/Cryptomator/gocryptfs store names as encrypted blobs, not as
///   characters on a physical FAT/NTFS/ext volume, so they resolve to
///   [FilesystemType.encryptedVault] — real filesystem character rules
///   don't apply to the plaintext name the user types.
/// - A plain folder vault (SAF-backed) could be backed by *any* real host
///   filesystem, which isn't knowable from here.
/// - A native disk-image container (VeraCrypt/LUKS/BitLocker/VHD/VHDX) is
///   mounted as FAT32, exFAT, NTFS, or ext2/3/4 — the user chose which at
///   creation time, but that choice isn't currently threaded through to
///   this call site (ADR-005 tracks doing so, either by persisting it or by
///   querying the native volume directly).
///
/// Both of the last two cases resolve to
/// [FilesystemType.unknownConservative] — the safe default: it never
/// under-restricts (never lets through a name that would actually be
/// illegal on the real target), it can only over-restrict compared to what
/// a fully wired-through concrete type would allow.
FilesystemType resolveFilesystemType(MountedContainer container) {
  final format = container.format;
  if (format.isCryfs || format.isCryptomator || format.isGocryptfs) {
    return FilesystemType.encryptedVault;
  }
  return FilesystemType.unknownConservative;
}