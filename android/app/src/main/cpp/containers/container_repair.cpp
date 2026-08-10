#include "container_repair.h"

#include <android/log.h>
#include <cmath>
#include <cstring>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

#include "mbedtls/platform_util.h"

#include "container_format.h"
#include "crypto/luks_header.h"
#include "crypto/vc_header_layout.h"
#include "session/bitlocker_backend.h"
#include "session/session_prepare.h"
#include "session/volume_state.h"
#include "filesystems/ext_backend.h"
#include "filesystems/ntfs_backend.h"
#include "containers/vhdx_image.h"
#include "containers/vhd_image.h"
#include "jni/jni_callbacks.h"

#include "diskio.h" // FatFs: BYTE/LBA_t/UINT/DRESULT + disk_read/disk_write, see fat32/exFAT check below
#include "ff.h" // FatFs public API: f_opendir/f_readdir/f_unlink, for the directory-tree deep scan below
#include "filesystems/filesystem_paths.h" // drivePaths[] -- the volume is already f_mount'd by the time this runs
#include "containers/container_utils.h" // fatToUnixTimestamp

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

namespace {

// ── Small local helpers ──────────────────────────────────────────────────

bool preadFully(int fd, uint64_t offset, void* buf, size_t len) {
    return pread(fd, buf, len, static_cast<off_t>(offset)) == static_cast<ssize_t>(len);
}

bool pwriteFully(int fd, uint64_t offset, const void* buf, size_t len) {
    return pwrite(fd, buf, len, static_cast<off_t>(offset)) == static_cast<ssize_t>(len);
}

// Shannon entropy in bits/byte (0..8) over [data, data+len). Genuine
// VeraCrypt/TrueCrypt header ciphertext (salt + AES-XTS output) is
// statistically indistinguishable from random and sits very close to 8.0;
// zero-fill, repeated-byte overwrite, or accidentally-written plaintext
// (the common real-world corruption patterns -- partial truncation,
// filesystem zeroing a "deleted" region, a backup tool writing a sparse
// hole) all read noticeably lower. This is a pre-check only: it can't
// prove a header is *valid* (a lucky-looking high-entropy blob might still
// fail decryption), only that it doesn't look obviously destroyed --
// restoreVeraCryptBackupHeaderUnmounted does the real, cryptographic
// verification once a password is available.
double shannonEntropyBitsPerByte(const uint8_t* data, size_t len) {
    if (len == 0) return 0.0;
    uint32_t counts[256] = {0};
    for (size_t i = 0; i < len; ++i) counts[data[i]]++;
    double entropy = 0.0;
    for (uint32_t c : counts) {
        if (c == 0) continue;
        double p = static_cast<double>(c) / static_cast<double>(len);
        entropy -= p * std::log2(p);
    }
    return entropy;
}

constexpr double kMinPlausibleCiphertextEntropy = 7.0;

// Thin wrapper so call sites read as plain log statements rather than
// repeating reportRepairLog's opId-gating at every call site.
inline void rlog(int opId, const char* message) { reportRepairLog(opId, message); }

// Mirrors prepareSession()'s BitLocker-detection dispatch chain in
// session_prepare.cpp exactly (raw offset 0 -> MBR/GPT-partitioned raw
// file -> VHDX -> dynamic/differencing VHD), since a real-world BitLocker
// container is at least as likely to be a whole-disk image (fixed VHD
// export, USB-style MBR/GPT partition table, VHDX) as a bare FVE volume
// starting at byte 0 -- checking only offset 0, as an earlier version of
// this function did, silently misdiagnosed every one of those as
// "not BitLocker" and fell through to the VeraCrypt entropy heuristic
// instead (which then reported them as corrupted, since a real FVE/MBR/
// VHDX header doesn't look like uniform ciphertext).
bool detectBitlockerAnywhereInFile(int fd, uint64_t fileSize, int opId) {
    rlog(opId, "Checking for a BitLocker signature at the start of the file...");
    if (bitlockerDetectFile(fd)) {
        rlog(opId, "BitLocker signature found.");
        return true;
    }

    if (isVhdxContainer(fd)) {
        rlog(opId, "File looks like a VHDX disk image -- checking inside it for BitLocker...");
        VhdxImage probeImg;
        if (probeImg.open(fd, /*requestReadWrite=*/false)) {
            auto vhdxReadSectors = [&probeImg](uint64_t startSector, uint32_t count, unsigned char* out) -> bool {
                return probeImg.pread(startSector * 512ULL, out, static_cast<size_t>(count) * 512ULL);
            };
            auto vhdxDetectAt = [&probeImg](uint64_t byteOffset) -> bool {
                unsigned char header[11];
                if (!probeImg.pread(byteOffset, header, sizeof(header))) return false;
                static const unsigned char kFve[] = {'-', 'F', 'V', 'E', '-', 'F', 'S', '-'};
                static const unsigned char kBtg[] = {'M', 'S', 'W', 'I', 'N', '4', '.', '1'};
                return std::memcmp(header + 3, kFve, 8) == 0 || std::memcmp(header + 3, kBtg, 8) == 0;
            };
            if (vhdxDetectAt(0)) {
                rlog(opId, "BitLocker signature found at the start of the virtual disk.");
                return true;
            }
            rlog(opId, "Scanning the VHDX's partition table for a BitLocker volume...");
            for (const auto& part : scanPartitionTable(vhdxReadSectors)) {
                if (part.sectorCount == 0) continue;
                const uint64_t partStartByte = part.startSector * 512ULL;
                const uint64_t partSizeBytes = part.sectorCount * 512ULL;
                if (partStartByte + partSizeBytes > probeImg.virtualDiskSize()) continue;
                if (vhdxDetectAt(partStartByte)) {
                    rlog(opId, "BitLocker signature found in a VHDX partition.");
                    return true;
                }
            }
        }
        // A VHDX that isn't BitLocker-protected still isn't a VeraCrypt/
        // LUKS shape in practice, but returning false here (rather than a
        // separate "not applicable" state) just falls through to the
        // entropy heuristic below, same as the real unlock path does.
        return false;
    }

    const VhdDiskKind vhdKind = probeVhdDiskKind(fd, fileSize);
    if (vhdKind == VhdDiskKind::kDynamic || vhdKind == VhdDiskKind::kDifferencing) {
        rlog(opId, "File looks like a dynamic/differencing VHD disk image -- checking inside it for BitLocker...");
        VhdImage probeImg;
        if (probeImg.open(fd, fileSize, /*requestReadWrite=*/false)) {
            auto vhdReadSectors = [&probeImg](uint64_t startSector, uint32_t count, unsigned char* out) -> bool {
                return probeImg.pread(startSector * 512ULL, out, static_cast<size_t>(count) * 512ULL);
            };
            auto vhdDetectAt = [&probeImg](uint64_t byteOffset) -> bool {
                unsigned char header[11];
                if (!probeImg.pread(byteOffset, header, sizeof(header))) return false;
                static const unsigned char kFve[] = {'-', 'F', 'V', 'E', '-', 'F', 'S', '-'};
                static const unsigned char kBtg[] = {'M', 'S', 'W', 'I', 'N', '4', '.', '1'};
                return std::memcmp(header + 3, kFve, 8) == 0 || std::memcmp(header + 3, kBtg, 8) == 0;
            };
            if (vhdDetectAt(0)) {
                rlog(opId, "BitLocker signature found at the start of the virtual disk.");
                return true;
            }
            rlog(opId, "Scanning the VHD's partition table for a BitLocker volume...");
            for (const auto& part : scanPartitionTable(vhdReadSectors)) {
                if (part.sectorCount == 0) continue;
                const uint64_t partStartByte = part.startSector * 512ULL;
                const uint64_t partSizeBytes = part.sectorCount * 512ULL;
                if (partStartByte + partSizeBytes > probeImg.virtualDiskSize()) continue;
                if (vhdDetectAt(partStartByte)) {
                    rlog(opId, "BitLocker signature found in a VHD partition.");
                    return true;
                }
            }
        }
        return false;
    }

    // Flat (fixed-format VHD, or plain raw/.img) whole-disk file: byte N
    // of the file really is byte N of the disk, so the FVE signature can
    // live inside one of the file's own MBR/GPT partitions.
    rlog(opId, "Scanning the file's own partition table for a BitLocker volume...");
    const uint64_t usableBytes = usableFileBytesExcludingVhdFooter(fd, fileSize);
    auto fileReadSectors = [fd, usableBytes](uint64_t startSector, uint32_t count, unsigned char* out) -> bool {
        const uint64_t byteOffset = startSector * 512ULL;
        const uint64_t byteLen = static_cast<uint64_t>(count) * 512ULL;
        if (byteOffset + byteLen > usableBytes) return false;
        return pread(fd, out, byteLen, static_cast<off_t>(byteOffset)) == static_cast<ssize_t>(byteLen);
    };
    for (const auto& part : scanPartitionTable(fileReadSectors)) {
        if (part.sectorCount == 0) continue; // sentinel -- offset-0 case already tried above
        const uint64_t partStartByte = part.startSector * 512ULL;
        const uint64_t partSizeBytes = part.sectorCount * 512ULL;
        if (partStartByte + partSizeBytes > usableBytes) continue;
        if (bitlockerDetectFile(fd, partStartByte)) {
            rlog(opId, "BitLocker signature found in a disk partition.");
            return true;
        }
    }
    rlog(opId, "No BitLocker signature found anywhere in the file.");
    return false;
}

// ── LUKS1 structural sanity (no password, no on-disk backup to restore
//    from -- see the doc comment on luks_header.h's integrity-check
//    section) ───────────────────────────────────────────────────────────

RepairDiagnosisCode diagnoseLuks1(int fd, uint64_t fileSize, int opId) {
    rlog(opId, "LUKS1 container detected -- checking header fields for sane values...");
    Luks1Phdr phdr{};
    if (!preadFully(fd, 0, &phdr, sizeof(phdr))) return RepairDiagnosisCode::kHeaderCorrupted;
    if (std::memcmp(phdr.magic, LUKS_MAGIC, 6) != 0) return RepairDiagnosisCode::kHeaderCorrupted;

    auto readBE32 = [](const uint8_t* p) {
        return (uint32_t(p[0]) << 24) | (uint32_t(p[1]) << 16) | (uint32_t(p[2]) << 8) | p[3];
    };
    const uint32_t keyBytes = readBE32(reinterpret_cast<const uint8_t*>(&phdr.keyBytes));
    const uint32_t payloadOffsetSectors = readBE32(reinterpret_cast<const uint8_t*>(&phdr.payloadOffset));
    const uint32_t mkDigestIter = readBE32(reinterpret_cast<const uint8_t*>(&phdr.mkDigestIter));
    const uint64_t payloadOffsetBytes = static_cast<uint64_t>(payloadOffsetSectors) * 512;

    const bool keyBytesSane = keyBytes == 16 || keyBytes == 32 || keyBytes == 64;
    const bool payloadOffsetSane = payloadOffsetSectors > 0 && payloadOffsetBytes < fileSize;
    const bool iterationsSane = mkDigestIter > 0;
    rlog(opId, keyBytesSane ? "Key size field looks sane." : "Key size field looks wrong.");
    rlog(opId, payloadOffsetSane ? "Payload offset field looks sane." : "Payload offset field looks wrong.");
    rlog(opId, iterationsSane ? "Key-derivation iteration count looks sane." : "Key-derivation iteration count looks wrong.");

    return (keyBytesSane && payloadOffsetSane && iterationsSane)
               ? RepairDiagnosisCode::kHealthy
               : RepairDiagnosisCode::kHeaderCorrupted;
}

// ── VeraCrypt/TrueCrypt entropy heuristic ────────────────────────────────

RepairDiagnosisCode diagnoseVeraCrypt(int fd, uint64_t fileSize, int opId) {
    rlog(opId, "No LUKS or BitLocker signature -- treating as a VeraCrypt/TrueCrypt container.");
    // The smallest a real container can be: two 64KB header slots plus at
    // least a token amount of data area.
    if (fileSize < TC_VOLUME_HEADER_GROUP_SIZE + VC_SUPPORTED_SECTOR_SIZE) {
        rlog(opId, "File is too small to hold a valid header -- flagging as corrupted.");
        return RepairDiagnosisCode::kHeaderCorrupted;
    }
    uint8_t primary[VC_FULL_HEADER_SIZE];
    if (!preadFully(fd, 0, primary, sizeof(primary))) return RepairDiagnosisCode::kHeaderCorrupted;

    rlog(opId, "Measuring the entropy of the primary header (a genuine encrypted header reads as near-random)...");
    const double entropy = shannonEntropyBitsPerByte(primary, sizeof(primary));
    char entropyMsg[96];
    std::snprintf(entropyMsg, sizeof(entropyMsg), "Primary header entropy: %.2f bits/byte (out of 8.00).", entropy);
    rlog(opId, entropyMsg);
    return entropy >= kMinPlausibleCiphertextEntropy ? RepairDiagnosisCode::kHealthy
                                                      : RepairDiagnosisCode::kHeaderCorrupted;
}

} // namespace

// ── Public: unmounted-file diagnosis ─────────────────────────────────────

namespace {

RepairDiagnosisCode diagnoseUnmountedContainerFileImpl(int fd, ContainerFormat& outFormat, bool& outFormatKnown,
                                                         int opId) {
    outFormatKnown = false;
    if (fd < 0) return RepairDiagnosisCode::kHeaderCorrupted;

    struct stat st{};
    if (fstat(fd, &st) != 0 || st.st_size <= 0) {
        rlog(opId, "Could not stat the file, or it's empty -- flagging as corrupted.");
        return RepairDiagnosisCode::kHeaderCorrupted;
    }
    const uint64_t fileSize = static_cast<uint64_t>(st.st_size);

    uint8_t magicProbe[6];
    if (!preadFully(fd, 0, magicProbe, sizeof(magicProbe))) {
        rlog(opId, "Could not read the first few bytes of the file -- flagging as corrupted.");
        return RepairDiagnosisCode::kHeaderCorrupted;
    }

    if (isLuksContainer(magicProbe, sizeof(magicProbe))) {
        uint8_t versionBuf[2];
        if (!preadFully(fd, 6, versionBuf, sizeof(versionBuf))) {
            rlog(opId, "LUKS magic found, but the version field couldn't be read -- flagging as corrupted.");
            return RepairDiagnosisCode::kHeaderCorrupted;
        }
        const uint16_t version = (uint16_t(versionBuf[0]) << 8) | versionBuf[1];

        if (version == 1) {
            outFormat = ContainerFormat::kLuks1;
            outFormatKnown = true;
            return diagnoseLuks1(fd, fileSize, opId);
        }
        if (version == 2) {
            outFormat = ContainerFormat::kLuks2;
            outFormatKnown = true;
            rlog(opId, "LUKS2 container detected -- checking primary and secondary header checksums...");
            LuksByteReader reader = [fd](uint64_t offset, void* outData, size_t len) -> bool {
                return preadFully(fd, offset, outData, len);
            };
            bool primaryValid = false, secondaryValid = false;
            if (!luks2CheckHeaderIntegrity(reader, primaryValid, secondaryValid)) {
                rlog(opId, "Could not read the LUKS2 headers -- flagging as corrupted.");
                return RepairDiagnosisCode::kHeaderCorrupted;
            }
            rlog(opId, primaryValid ? "Primary header checksum is valid." : "Primary header checksum is invalid.");
            rlog(opId, secondaryValid ? "Secondary (backup) header checksum is valid."
                                       : "Secondary (backup) header checksum is invalid.");
            return primaryValid ? RepairDiagnosisCode::kHealthy : RepairDiagnosisCode::kHeaderCorrupted;
        }
        // Recognized as LUKS but an unknown version -- still "known", just
        // not one we can say anything more specific about.
        rlog(opId, "LUKS magic found, but the version number isn't one this tool recognizes.");
        outFormatKnown = true;
        outFormat = ContainerFormat::kLuks2;
        return RepairDiagnosisCode::kHeaderCorrupted;
    }

    if (detectBitlockerAnywhereInFile(fd, fileSize, opId)) {
        // BitLocker's FVE metadata format isn't one this tool can verify or
        // repair (no backup-header concept analogous to VeraCrypt/LUKS2 is
        // wired up here) -- report healthy rather than a corruption we
        // can't actually substantiate or fix.
        outFormat = ContainerFormat::kBitLocker;
        outFormatKnown = true;
        return RepairDiagnosisCode::kHealthy;
    }

    // Falls through to VeraCrypt/TrueCrypt: its header is fully encrypted,
    // so magic-byte detection isn't possible before a password is known.
    // Anything picked via the container file picker that isn't LUKS or
    // BitLocker is treated as a VeraCrypt-family candidate.
    outFormat = ContainerFormat::kVeraCrypt;
    outFormatKnown = true;
    return diagnoseVeraCrypt(fd, fileSize, opId);
}

} // namespace

bool repairFormatNeedsPasswordForRestore(ContainerFormat format) {
    return format == ContainerFormat::kVeraCrypt;
}

// fd is owned by the caller for the duration of this call and closed before
// returning, on every path -- matching this codebase's convention for
// native functions fed a Kotlin `detachFd()`'d SAF descriptor (see e.g.
// changeContainerPassword in container_create.cpp).
RepairDiagnosisCode diagnoseUnmountedContainerFile(int fd, ContainerFormat& outFormat, bool& outFormatKnown,
                                                    int logOpId) {
    RepairDiagnosisCode code = diagnoseUnmountedContainerFileImpl(fd, outFormat, outFormatKnown, logOpId);
    if (fd >= 0) close(fd);
    return code;
}

// ── Public: unmounted-file repair ────────────────────────────────────────

namespace {

bool restoreLuks2BackupHeaderUnmountedImpl(int fd, int opId) {
    if (fd < 0) return false;
    rlog(opId, "Reading the secondary (backup) header...");
    LuksByteReader reader = [fd](uint64_t offset, void* outData, size_t len) -> bool {
        return preadFully(fd, offset, outData, len);
    };
    LuksByteWriter writer = [fd](uint64_t offset, const void* data, size_t len) -> bool {
        return pwriteFully(fd, offset, data, len);
    };
    rlog(opId, "Verifying the backup header's checksum before trusting it...");
    const bool restored = luks2RestoreHeaderFromBackup(reader, writer);
    rlog(opId, restored ? "Backup header verified -- primary header overwritten from it."
                         : "Backup header did not verify either -- nothing safe to restore from.");
    return restored;
}

VeraCryptRestoreResult restoreVeraCryptBackupHeaderUnmountedImpl(
    int fd, const uint8_t* password, size_t passwordLen, int pim, int cipherId, int hashId, int opId) {
    if (fd < 0 || !password || passwordLen == 0) return VeraCryptRestoreResult::kIoError;

    struct stat st{};
    if (fstat(fd, &st) != 0 || st.st_size <= 0) return VeraCryptRestoreResult::kIoError;
    const uint64_t fileSize = static_cast<uint64_t>(st.st_size);
    if (fileSize < TC_VOLUME_HEADER_GROUP_SIZE + VC_FULL_HEADER_SIZE) {
        rlog(opId, "File is too small to hold a backup header group -- nothing to restore from.");
        return VeraCryptRestoreResult::kIoError;
    }

    // Mirrors the two primary-header slots the real unlock path tries
    // (session_prepare.cpp) -- standard volume header at 0, hidden-volume
    // header at TC_HIDDEN_VOLUME_HEADER_OFFSET -- paired with their
    // corresponding backup slots in the trailing TC_VOLUME_HEADER_GROUP_SIZE
    // backup-header group.
    struct Slot { uint64_t primaryOffset; uint64_t backupOffset; };
    const uint64_t backupGroupOffset = fileSize - TC_VOLUME_HEADER_GROUP_SIZE;
    const Slot slots[2] = {
        {0, backupGroupOffset},
        {TC_HIDDEN_VOLUME_HEADER_OFFSET, backupGroupOffset + TC_HIDDEN_VOLUME_HEADER_OFFSET},
    };

    rlog(opId, "Checking whether the primary header already decrypts fine (nothing to fix if so)...");
    bool anyPrimaryAlreadyHealthy = false;
    for (const Slot& slot : slots) {
        uint8_t primarySector[VC_FULL_HEADER_SIZE];
        if (preadFully(fd, slot.primaryOffset, primarySector, sizeof(primarySector))) {
            unsigned char keyMaterial[192];
            unsigned char decryptedHeader[VC_HEADER_BODY_SIZE];
            CascadeId matchedCipher;
            HashId matchedHash;
            ParsedHeaderFields fields;
            if (deriveAndValidateHeader(primarySector, password, passwordLen, pim, cipherId, hashId,
                                         keyMaterial, decryptedHeader, matchedCipher, matchedHash, fields)) {
                mbedtls_platform_zeroize(keyMaterial, sizeof(keyMaterial));
                mbedtls_platform_zeroize(decryptedHeader, sizeof(decryptedHeader));
                anyPrimaryAlreadyHealthy = true;
            }
        }
    }
    if (anyPrimaryAlreadyHealthy) {
        rlog(opId, "Primary header already decrypts fine -- nothing to restore.");
        return VeraCryptRestoreResult::kAlreadyHealthy;
    }

    rlog(opId, "Primary header doesn't verify -- trying the backup header slot(s)...");
    for (const Slot& slot : slots) {
        uint8_t backupSector[VC_FULL_HEADER_SIZE];
        if (!preadFully(fd, slot.backupOffset, backupSector, sizeof(backupSector))) {
            rlog(opId, "Could not read a backup header slot -- skipping it.");
            continue;
        }

        unsigned char keyMaterial[192];
        unsigned char decryptedHeader[VC_HEADER_BODY_SIZE];
        CascadeId matchedCipher;
        HashId matchedHash;
        ParsedHeaderFields fields;
        const bool verified = deriveAndValidateHeader(backupSector, password, passwordLen, pim, cipherId, hashId,
                                                        keyMaterial, decryptedHeader, matchedCipher, matchedHash,
                                                        fields);
        mbedtls_platform_zeroize(keyMaterial, sizeof(keyMaterial));
        mbedtls_platform_zeroize(decryptedHeader, sizeof(decryptedHeader));
        if (!verified) {
            rlog(opId, "Backup header slot didn't decrypt/verify under this password -- trying the next slot.");
            continue;
        }

        rlog(opId, "Backup header decrypted and CRC-validated -- it's genuine. Overwriting the primary header...");
        // The backup decrypted and CRC-validated under this password --
        // it's genuine. Overwrite the primary with its raw (still
        // encrypted) bytes, exactly as real VeraCrypt's header restore
        // does; nothing derived from the plaintext is ever written.
        if (!pwriteFully(fd, slot.primaryOffset, backupSector, sizeof(backupSector))) {
            mbedtls_platform_zeroize(backupSector, sizeof(backupSector));
            rlog(opId, "Writing the restored primary header failed (I/O error).");
            return VeraCryptRestoreResult::kIoError;
        }
        mbedtls_platform_zeroize(backupSector, sizeof(backupSector));
        LOGI("restoreVeraCryptBackupHeaderUnmounted: primary header restored from backup at slot offset %llu",
             static_cast<unsigned long long>(slot.primaryOffset));
        rlog(opId, "Primary header restored from the verified backup.");
        return VeraCryptRestoreResult::kSuccess;
    }

    rlog(opId, "No backup header slot verified under this password.");
    return VeraCryptRestoreResult::kPasswordIncorrect;
}

} // namespace

bool restoreLuks2BackupHeaderUnmounted(int fd, int logOpId) {
    bool ok = restoreLuks2BackupHeaderUnmountedImpl(fd, logOpId);
    if (fd >= 0) close(fd);
    return ok;
}

VeraCryptRestoreResult restoreVeraCryptBackupHeaderUnmounted(
    int fd, const uint8_t* password, size_t passwordLen, int pim, int cipherId, int hashId, int logOpId) {
    VeraCryptRestoreResult result =
        restoreVeraCryptBackupHeaderUnmountedImpl(fd, password, passwordLen, pim, cipherId, hashId, logOpId);
    if (fd >= 0) close(fd);
    return result;
}

// ── Public: mounted-volume filesystem diagnosis & repair ────────────────

namespace {

// FAT16/FAT32/exFAT dirty-bit check, implemented via direct sector I/O
// (disk_read/disk_write, pdrv == volId -- see io/virtual_block_device.cpp)
// rather than through FatFs's own FATFS struct, so this doesn't depend on
// exact field names in the vendored ff.h. All offsets below are from the
// standard BPB/exFAT boot-sector layout, not from any specific library.
//
//  * FAT32: the "clean shutdown" bit is bit 27 (0x08000000) of FAT
//    entry 1 (cluster 1's reserved entry) -- the same convention Windows
//    uses; entry 1 lives at byte offset 4 within the FAT.
//  * FAT16: same idea, bit 15 (0x8000) of a 2-byte entry 1, at byte
//    offset 2 within the FAT.
//  * exFAT: a dedicated VolumeFlags field at boot-sector byte offset
//    0x6A; bit 1 (0x0002) is VolumeDirty.
//  * FAT12 has no standard equivalent flag and isn't checked here --
//    containers this app creates use FAT16/FAT32/exFAT for anything large
//    enough for the distinction to matter.
bool fatReadBootSector(int volId, uint8_t sector[512]) {
    return disk_read(static_cast<BYTE>(volId), sector, 0, 1) == RES_OK;
}

uint16_t leU16(const uint8_t* p) { return uint16_t(p[0]) | (uint16_t(p[1]) << 8); }
uint32_t leU32(const uint8_t* p) {
    return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}

enum class FatKind { kFat16, kFat32, kExFat, kUnsupported };

FatKind classifyFatBootSector(const uint8_t sector[512]) {
    // exFAT's boot sector carries the literal OEM name "EXFAT   " at
    // byte offset 3.
    if (std::memcmp(sector + 3, "EXFAT   ", 8) == 0) return FatKind::kExFat;
    // Classic BPB: FAT16 has a 2-byte sectors-per-FAT field at offset 22
    // that's zero when the volume is actually FAT32 (which instead uses
    // the 4-byte field at offset 36) -- the standard way to tell them
    // apart without walking the whole cluster count formula.
    const uint16_t fat16SectorsPerFat = leU16(sector + 22);
    return fat16SectorsPerFat == 0 ? FatKind::kFat32 : FatKind::kFat16;
}

bool fatIsDirty(int volId, bool& outDirty) {
    uint8_t boot[512];
    if (!fatReadBootSector(volId, boot)) return false;
    const FatKind kind = classifyFatBootSector(boot);

    const uint16_t bytesPerSector = leU16(boot + 11);
    if (bytesPerSector == 0) return false;
    const uint16_t reservedSectors = leU16(boot + 14);

    switch (kind) {
        case FatKind::kExFat: {
            outDirty = (leU16(boot + 0x6A) & 0x0002) != 0;
            return true;
        }
        case FatKind::kFat32: {
            uint8_t fatSector[512];
            if (disk_read(static_cast<BYTE>(volId), fatSector, reservedSectors, 1) != RES_OK) return false;
            outDirty = (leU32(fatSector + 4) & 0x08000000u) == 0;
            return true;
        }
        case FatKind::kFat16: {
            uint8_t fatSector[512];
            if (disk_read(static_cast<BYTE>(volId), fatSector, reservedSectors, 1) != RES_OK) return false;
            outDirty = (leU16(fatSector + 2) & 0x8000u) == 0;
            return true;
        }
        default:
            return false;
    }
}

bool fatClearDirty(int volId) {
    uint8_t boot[512];
    if (!fatReadBootSector(volId, boot)) return false;
    const FatKind kind = classifyFatBootSector(boot);
    const uint16_t reservedSectors = leU16(boot + 14);

    switch (kind) {
        case FatKind::kExFat: {
            uint16_t flags = leU16(boot + 0x6A);
            flags &= ~uint16_t(0x0002);
            boot[0x6A] = static_cast<uint8_t>(flags & 0xFF);
            boot[0x6B] = static_cast<uint8_t>((flags >> 8) & 0xFF);
            return disk_write(static_cast<BYTE>(volId), boot, 0, 1) == RES_OK;
        }
        case FatKind::kFat32: {
            uint8_t fatSector[512];
            if (disk_read(static_cast<BYTE>(volId), fatSector, reservedSectors, 1) != RES_OK) return false;
            uint32_t entry1 = leU32(fatSector + 4);
            entry1 |= 0x08000000u;
            fatSector[4] = static_cast<uint8_t>(entry1 & 0xFF);
            fatSector[5] = static_cast<uint8_t>((entry1 >> 8) & 0xFF);
            fatSector[6] = static_cast<uint8_t>((entry1 >> 16) & 0xFF);
            fatSector[7] = static_cast<uint8_t>((entry1 >> 24) & 0xFF);
            return disk_write(static_cast<BYTE>(volId), fatSector, reservedSectors, 1) == RES_OK;
        }
        case FatKind::kFat16: {
            uint8_t fatSector[512];
            if (disk_read(static_cast<BYTE>(volId), fatSector, reservedSectors, 1) != RES_OK) return false;
            uint16_t entry1 = leU16(fatSector + 2);
            entry1 |= 0x8000u;
            fatSector[2] = static_cast<uint8_t>(entry1 & 0xFF);
            fatSector[3] = static_cast<uint8_t>((entry1 >> 8) & 0xFF);
            return disk_write(static_cast<BYTE>(volId), fatSector, reservedSectors, 1) == RES_OK;
        }
        default:
            return false;
    }
}

// ── FAT/exFAT directory-tree deep scan (a lightweight chkdsk-equivalent)
//    ─────────────────────────────────────────────────────────────────────
//
// fatIsDirty/fatClearDirty above only reflect whether the volume was
// cleanly unmounted -- that flag says nothing about whether the directory
// tree itself is intact. A torn write or a corrupted cluster can leave
// individual directory *entries* damaged (garbage date/size fields,
// unparseable name bytes) while the dirty bit stays clear the whole time,
// so the check above alone won't catch it -- this is what a real-world
// corrupted container actually looks like when browsed (entries showing
// as "?", implausible future dates, file sizes bigger than the volume
// itself). This walks the whole tree via FatFs's own directory API
// (drivePaths[volId] is already f_mount'd by the time diagnose/repair
// runs here -- see virtual_block_device.cpp) and flags any entry that
// couldn't plausibly be genuine, mirroring what Windows chkdsk does to a
// real corrupted FAT volume: prune entries that don't hold together
// rather than trying to interpret them.
struct FatCorruptEntry {
    std::string path;
    bool isDir;
};

// A name FatFs couldn't decode into valid Unicode surfaces, after its own
// OEM/UTF-8 conversion, as '?'. A genuine file can of course contain a
// literal '?' in its name, but a name that's *entirely* replacement
// characters is a strong corruption signal rather than a plausible real
// filename someone chose.
bool fatNameIsAllReplacementChars(const char* fname) {
    if (!fname || !fname[0]) return false;
    for (const char* p = fname; *p; ++p) {
        if (*p != '?') return false;
    }
    return true;
}

bool fatEntryLooksCorrupted(const FILINFO& fno, uint64_t volumeCapacityBytes, uint64_t nowUnix) {
    if (fatNameIsAllReplacementChars(fno.fname)) return true;

    if (!(fno.fattrib & AM_DIR) && volumeCapacityBytes > 0 &&
        static_cast<uint64_t>(fno.fsize) > volumeCapacityBytes) {
        return true;
    }

    // A little slack for clock skew between the device and whatever last
    // wrote the container; more than a year out isn't clock skew, it's a
    // mangled date field (FAT/exFAT dates can encode years up to 2107 --
    // easily hit by a few flipped bits in a corrupted entry).
    constexpr uint64_t kOneYearSeconds = 366ULL * 24 * 3600;
    const uint64_t entryUnix = fatToUnixTimestamp(fno.fdate, fno.ftime);
    if (entryUnix > nowUnix + kOneYearSeconds) return true;

    return false;
}

uint64_t fatVolumeCapacityBytes(int volId) {
    FATFS* fs = nullptr;
    DWORD freeClusters = 0;
    if (f_getfree(drivePaths[volId], &freeClusters, &fs) != FR_OK || !fs) return 0;
    return static_cast<uint64_t>(fs->n_fatent - 2) * fs->csize * 512ULL;
}

// Recurses into [pathSuffix] (relative to the volume root, "" for the
// root itself), appending every corrupted entry found to [outCorrupt].
// Does not recurse into a directory that is itself flagged corrupted --
// its contents are just as untrustworthy and get removed wholesale along
// with it.
void fatScanForCorruptEntries(int volId, const std::string& pathSuffix, uint64_t volumeCapacityBytes,
                               uint64_t nowUnix, std::vector<FatCorruptEntry>& outCorrupt, int opId) {
    std::string fullPath = drivePaths[volId];
    if (!pathSuffix.empty()) fullPath += "/" + pathSuffix;

    DIR dir;
    FILINFO fno;
    if (f_opendir(&dir, fullPath.c_str()) != FR_OK) return;
    while (f_readdir(&dir, &fno) == FR_OK && fno.fname[0]) {
        const std::string childSuffix = pathSuffix.empty() ? std::string(fno.fname) : pathSuffix + "/" + fno.fname;
        const bool isDir = (fno.fattrib & AM_DIR) != 0;

        if (fatEntryLooksCorrupted(fno, volumeCapacityBytes, nowUnix)) {
            char msg[320];
            std::snprintf(msg, sizeof(msg), "Found a corrupted %s entry: %s",
                          isDir ? "directory" : "file", childSuffix.c_str());
            rlog(opId, msg);
            outCorrupt.push_back({childSuffix, isDir});
            continue; // don't trust anything inside a corrupted directory either
        }

        if (isDir) {
            fatScanForCorruptEntries(volId, childSuffix, volumeCapacityBytes, nowUnix, outCorrupt, opId);
        }
    }
    f_closedir(&dir);
}

FRESULT fatRemoveRecursiveForRepair(const char* path) {
    DIR dir;
    FILINFO fno;
    FRESULT fr = f_opendir(&dir, path);
    if (fr == FR_OK) {
        while (f_readdir(&dir, &fno) == FR_OK && fno.fname[0]) {
            std::string childPath = std::string(path) + "/" + fno.fname;
            if (fno.fattrib & AM_DIR) {
                fatRemoveRecursiveForRepair(childPath.c_str());
            } else {
                f_unlink(childPath.c_str());
            }
        }
        f_closedir(&dir);
    }
    return f_unlink(path);
}

// True if any corrupted entry was found (whether or not [opId]'s caller
// goes on to actually remove them) -- used by diagnoseMountedVolumeFilesystem
// to fold "the tree has garbage in it" into the same kFilesystemDirty
// diagnosis the dirty-bit check reports, since the wizard's repair action
// (runMountedVolumeFilesystemCheck) handles both.
bool fatHasCorruptEntries(int volId, int opId) {
    const uint64_t capacity = fatVolumeCapacityBytes(volId);
    const uint64_t nowUnix = static_cast<uint64_t>(time(nullptr));
    std::vector<FatCorruptEntry> found;
    fatScanForCorruptEntries(volId, "", capacity, nowUnix, found, opId);
    return !found.empty();
}

// Removes every corrupted entry found by the same scan, deepest-first
// (the scan itself already avoids recursing into a corrupted directory,
// so ordering here just needs to not choke on a parent disappearing out
// from under a still-pending child -- which can't happen since corrupted
// directories are never recursed into to begin with).
bool fatRemoveCorruptEntries(int volId, int opId) {
    const uint64_t capacity = fatVolumeCapacityBytes(volId);
    const uint64_t nowUnix = static_cast<uint64_t>(time(nullptr));
    std::vector<FatCorruptEntry> found;
    fatScanForCorruptEntries(volId, "", capacity, nowUnix, found, opId);

    if (found.empty()) {
        rlog(opId, "No corrupted directory entries found.");
        return true;
    }

    char summary[96];
    std::snprintf(summary, sizeof(summary), "Removing %zu corrupted entr%s...", found.size(),
                  found.size() == 1 ? "y" : "ies");
    rlog(opId, summary);

    bool allRemoved = true;
    for (const auto& entry : found) {
        const std::string fullPath = std::string(drivePaths[volId]) + "/" + entry.path;
        const FRESULT fr = entry.isDir ? fatRemoveRecursiveForRepair(fullPath.c_str()) : f_unlink(fullPath.c_str());
        char msg[320];
        std::snprintf(msg, sizeof(msg), "%s: %s", fr == FR_OK ? "Removed" : "Failed to remove", entry.path.c_str());
        rlog(opId, msg);
        if (fr != FR_OK) allRemoved = false;
    }
    return allRemoved;
}

} // namespace

RepairDiagnosisCode diagnoseMountedVolumeFilesystem(int volId, int logOpId) {
    if (volId < 0 || volId >= FF_VOLUMES) return RepairDiagnosisCode::kHealthy;
    VolumeState& v = volumes[volId];

    switch (v.fsType) {
        case VolumeState::FS_EXT: {
            rlog(logOpId, "ext filesystem -- checking the superblock's clean-unmount state...");
            const bool dirty = extIsDirty(volId);
            rlog(logOpId, dirty ? "Superblock reports the filesystem was not unmounted cleanly."
                                 : "Superblock reports a clean unmount.");
            return dirty ? RepairDiagnosisCode::kFilesystemDirty : RepairDiagnosisCode::kHealthy;
        }
        case VolumeState::FS_NTFS: {
            rlog(logOpId, "NTFS filesystem -- checking the $Volume dirty flag...");
            const bool dirty = ntfsIsDirty(volId);
            rlog(logOpId, dirty ? "$Volume dirty flag is set." : "$Volume dirty flag is clear.");
            return dirty ? RepairDiagnosisCode::kFilesystemDirty : RepairDiagnosisCode::kHealthy;
        }
        case VolumeState::FS_FATFS: {
            rlog(logOpId, "FAT/exFAT filesystem -- checking the clean-shutdown bit...");
            bool dirty = false;
            const bool recognized = fatIsDirty(volId, dirty);
            if (recognized) {
                rlog(logOpId, dirty ? "Clean-shutdown bit is not set." : "Clean-shutdown bit is set.");
            } else {
                rlog(logOpId, "Boot sector isn't a recognized FAT16/FAT32/exFAT layout -- skipping that check.");
            }
            rlog(logOpId, "Scanning the directory tree for corrupted entries (garbage names, impossible "
                          "dates/sizes)...");
            const bool hasCorruptEntries = fatHasCorruptEntries(volId, logOpId);
            if (!hasCorruptEntries) rlog(logOpId, "No corrupted directory entries found.");
            if (!recognized) return hasCorruptEntries ? RepairDiagnosisCode::kFilesystemDirty
                                                        : RepairDiagnosisCode::kHealthy; // unrecognized/FAT12 dirty-bit: nothing to flag there
            return (dirty || hasCorruptEntries) ? RepairDiagnosisCode::kFilesystemDirty : RepairDiagnosisCode::kHealthy;
        }
        default:
            return RepairDiagnosisCode::kHealthy;
    }
}

bool runMountedVolumeFilesystemCheck(int volId, int logOpId) {
    if (volId < 0 || volId >= FF_VOLUMES) return false;
    VolumeState& v = volumes[volId];

    switch (v.fsType) {
        case VolumeState::FS_EXT:
            rlog(logOpId, "Clearing the ext superblock's dirty/error state...");
            return extClearDirtyState(volId);
        case VolumeState::FS_NTFS:
            rlog(logOpId, "Clearing the NTFS $Volume dirty flag...");
            return ntfsClearDirtyFlag(volId);
        case VolumeState::FS_FATFS: {
            rlog(logOpId, "Setting the FAT/exFAT clean-shutdown bit...");
            const bool clearedFlag = fatClearDirty(volId);
            rlog(logOpId, "Scanning the directory tree for corrupted entries to remove...");
            const bool removedCorrupt = fatRemoveCorruptEntries(volId, logOpId);
            return clearedFlag && removedCorrupt;
        }
        default:
            return false;
    }
}