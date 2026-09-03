#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

#include "container_format.h"

// Native engine backing the Flutter "Check and Repair Tool" (see
// lib/features/tools/widgets/container_repair_sheet.dart). Two very
// different situations are handled, matching the two RepairTarget cases on
// the Dart side:
//
//  * An *unmounted* container file, reachable only via its SAF file
//    descriptor. Diagnosis here is necessarily read-only and, for formats
//    whose header is itself encrypted (VeraCrypt/TrueCrypt), a structural
//    heuristic rather than a cryptographic proof -- you cannot tell
//    corrupted ciphertext from valid ciphertext without the password. Repair
//    for those formats therefore requires the password to decrypt-and-verify
//    the backup header before it's trusted enough to overwrite the primary
//    with. LUKS2's header is checksummed in the clear, so both diagnosis and
//    repair work without a password there.
//
//  * An already-*mounted* volume (VolumeState, identified by volId). Its
//    header decrypted fine or it couldn't have been mounted, so the only
//    thing worth diagnosing here is the inner filesystem's own "was this
//    unmounted cleanly" signal (ext2's s_state, NTFS's $Volume dirty flag,
//    FAT's clean-shutdown bit).

// Mirrors Dart's RepairDiagnosis enum ordinal-for-ordinal
// (lib/features/tools/models/tool_models.dart): healthy=0,
// headerCorrupted=1, filesystemDirty=2.
enum class RepairDiagnosisCode : int32_t {
    kHealthy = 0,
    kHeaderCorrupted = 1,
    kFilesystemDirty = 2,
};

// Result codes for restoreVeraCryptBackupHeaderUnmounted, richer than a bool
// so the JNI layer can tell "wrong password" apart from "nothing to fix"
// apart from "I/O error" and surface each distinctly to Flutter.
enum class VeraCryptRestoreResult : int32_t {
    kSuccess = 0,
    kPasswordIncorrect = 1,
    kAlreadyHealthy = 2,
    kIoError = 3,
};

// ── Unmounted-file diagnosis ────────────────────────────────────────────

// Inspects the container file behind [fd] and reports both a best-effort
// diagnosis and, when recognizable, its on-disk format. [outFormatKnown] is
// false when the file doesn't look like any supported container at all
// (wrong file, truncated beyond recognition, etc.) -- callers should treat
// that as distinct from a confidently-diagnosed corruption.
//
// [logOpId], here and on every other entry point below, identifies this
// call to the wizard's live log panel (see jni_callbacks.h's
// reportRepairLog) -- pass <= 0 to skip logging entirely (e.g. from a
// context with no opId to report against).
RepairDiagnosisCode diagnoseUnmountedContainerFile(int fd, ContainerFormat& outFormat, bool& outFormatKnown,
                                                    int logOpId = -1);

// True if [format]'s backup-header restore path needs a password to verify
// the backup copy before trusting it (VeraCrypt/TrueCrypt). LUKS2's header
// checksum is unencrypted, so it doesn't. Formats with no supported restore
// path at all (LUKS1, BitLocker) also return false -- callers should check
// diagnosis rather than gate solely on this.
bool repairFormatNeedsPasswordForRestore(ContainerFormat format);

// ── Unmounted-file repair ───────────────────────────────────────────────

// Restores LUKS2's primary header copy from its secondary (backup) copy.
// No password needed -- see luks2RestoreHeaderFromBackup in luks_header.cpp
// for why this is safe (checksum-verified, not a blind copy).
bool restoreLuks2BackupHeaderUnmounted(int fd, int logOpId = -1);

// Restores a VeraCrypt/TrueCrypt container's primary header from whichever
// of its two backup-header slots (standard volume, hidden volume) decrypts
// and CRC-validates against [password]/[pim]/[cipherId]/[hashId] -- mirrors
// exactly what real VeraCrypt's "Repair Header" does: decrypt the backup to
// prove it's genuine, then overwrite the primary with the backup's raw
// (still-encrypted) bytes, never with anything derived from the plaintext.
// cipherId/hashId of 255 auto-detect across all supported combinations,
// matching the same auto-detect unlock supports.
VeraCryptRestoreResult restoreVeraCryptBackupHeaderUnmounted(
    int fd, const uint8_t* password, size_t passwordLen, int pim, int cipherId, int hashId,
    int logOpId = -1);

// ── Header Backup / Restore (Header Exporter tool) ─────────────────────
//
// Backs an unmounted container file's *header* up to (or restores it from)
// an external file, separate from Check & Repair's in-container
// backup-slot restore above: that repairs a container from redundancy it
// already carries on disk (LUKS2's secondary copy, VeraCrypt's own backup
// header group), which is useless once *both* copies are damaged together
// (the same bad sectors, a botched in-place write, the container
// truncated). This tool instead lets the header live somewhere else
// entirely -- mirroring real cryptsetup's `luksHeaderBackup`/
// `luksHeaderRestore` for LUKS, and serving the same role VeraCrypt's own
// "Backup Volume Header" does for VeraCrypt/TrueCrypt.
//
// The "header" here is everything a container needs to derive its master
// key at all: for LUKS1/LUKS2, that's the byte range [0, dataOffset) --
// both header copies plus the keyslot/AF-stripe area, ending exactly where
// the encrypted payload begins (a cleartext field for both formats, so no
// password is needed to size or read it). For VeraCrypt/TrueCrypt it's the
// fixed-size header group at the start of the file (opaque ciphertext
// either way). Wrapping the exported bytes with a magic/checksum envelope,
// and the SAF file I/O on both ends, are Kotlin-side concerns (see
// HeaderBackupHandlers.kt) -- this layer only ever sees a raw payload
// buffer already extracted/about-to-be-restored.
//
// BitLocker and Plain are recognized but unsupported (kUnsupportedFormat)
// -- BitLocker's FVE metadata has its own, much more complex internal
// redundancy scheme this tool doesn't attempt to reproduce, and Plain has
// no header/key material to protect at all.

enum class HeaderExportResult : int32_t {
    kSuccess = 0,
    kUnrecognizedFile = 1,   // Doesn't look like any supported container.
    kUnsupportedFormat = 2,  // Recognized (BitLocker/Plain) but not backed up.
    kHeaderUnreadable = 3,   // Recognized+supported format, but its cleartext
                             // sizing fields don't parse -- diagnose it with
                             // Check & Repair first.
    kIoError = 4,
};

// Reads the container behind [fd] and, on kSuccess, hands back its format
// and the exact leading byte range described above in [outPayload].
// Consumes/closes [fd] on every path. [outFormat] is meaningful for every
// result except kUnrecognizedFile/kIoError.
HeaderExportResult exportContainerHeaderRegion(int fd, ContainerFormat& outFormat,
                                                std::vector<uint8_t>& outPayload, int logOpId = -1);

enum class HeaderRestoreResult : int32_t {
    kSuccess = 0,
    kPasswordIncorrect = 1, // VeraCrypt/TrueCrypt only.
    kBackupInvalid = 2,     // Doesn't verify as a genuine header for [format].
    kSizeMismatch = 3,      // [fd]'s current size is smaller than [payloadLen]
                            // -- almost certainly the wrong target file.
    kIoError = 4,
};

// Verifies [payload]/[payloadLen] is a genuine header for [format] --
// decrypt-and-CRC for VeraCrypt/TrueCrypt (needs [password]; [pim]/
// [cipherId]/[hashId] of 255 auto-detect, same as everywhere else in this
// file), checksum for LUKS2 (no password needed), field-sanity for LUKS1
// (no on-disk checksum exists for it in the real spec either, so this is
// the same bar real cryptsetup's own luksHeaderRestore holds LUKS1 to) --
// then overwrites exactly [fd]'s leading [payloadLen] bytes with it, never
// anything beyond that. Consumes/closes [fd] on every path.
HeaderRestoreResult restoreContainerHeaderRegion(
    int fd, ContainerFormat format, const uint8_t* payload, size_t payloadLen,
    const uint8_t* password, size_t passwordLen, int pim, int cipherId, int hashId,
    int logOpId = -1);

// ── Mounted-volume diagnosis & repair ───────────────────────────────────

// Checks the already-mounted inner filesystem's own dirty/error signal.
// Returns kFilesystemDirty or kHealthy; kHeaderCorrupted is never returned
// here (a volume with a bad header couldn't have been mounted at all).
RepairDiagnosisCode diagnoseMountedVolumeFilesystem(int volId, int logOpId = -1);

// Clears the dirty/error signal checked by diagnoseMountedVolumeFilesystem.
// This is a superblock/boot-sector-level repair (clearing the flag that
// says "run a full check"), not a full fsck -- see the per-backend
// implementations (ext_backend.cpp, ntfs_backend.cpp, and the FAT/exFAT
// boot-sector logic in container_repair.cpp) for exactly what's checked.
bool runMountedVolumeFilesystemCheck(int volId, int logOpId = -1);