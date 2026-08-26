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
#include "diskio.h"
#include "ff.h"
#include "filesystems/filesystem_paths.h"
#include "containers/container_utils.h"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

namespace {
bool preadFully(int fd, uint64_t offset, void* buf, size_t len) {
    return pread(fd, buf, len, static_cast<off_t>(offset)) == static_cast<ssize_t>(len);
}

bool pwriteFully(int fd, uint64_t offset, const void* buf, size_t len) {
    return pwrite(fd, buf, len, static_cast<off_t>(offset)) == static_cast<ssize_t>(len);
}

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

inline void rlog(int opId, const char* message) { reportRepairLog(opId, message); }

bool detectBitlockerAnywhereInFile(int fd, uint64_t fileSize, int opId) {
    rlog(opId, "Checking for a BitLocker signature at the start of the file...");
    if (bitlockerDetectFile(fd)) {
        rlog(opId, "BitLocker signature found.");
        return true;
    }
    if (isVhdxContainer(fd)) {
        rlog(opId, "File looks like a VHDX disk image -- checking inside it for BitLocker...");
        VhdxImage probeImg;
        if (probeImg.open(fd, false)) {
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
        return false;
    }
    const VhdDiskKind vhdKind = probeVhdDiskKind(fd, fileSize);
    if (vhdKind == VhdDiskKind::kDynamic || vhdKind == VhdDiskKind::kDifferencing) {
        rlog(opId, "File looks like a dynamic/differencing VHD disk image -- checking inside it for BitLocker...");
        VhdImage probeImg;
        if (probeImg.open(fd, fileSize, false)) {
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
    rlog(opId, "Scanning the file's own partition table for a BitLocker volume...");
    const uint64_t usableBytes = usableFileBytesExcludingVhdFooter(fd, fileSize);
    auto fileReadSectors = [fd, usableBytes](uint64_t startSector, uint32_t count, unsigned char* out) -> bool {
        const uint64_t byteOffset = startSector * 512ULL;
        const uint64_t byteLen = static_cast<uint64_t>(count) * 512ULL;
        if (byteOffset + byteLen > usableBytes) return false;
        return pread(fd, out, byteLen, static_cast<off_t>(byteOffset)) == static_cast<ssize_t>(byteLen);
    };
    for (const auto& part : scanPartitionTable(fileReadSectors)) {
        if (part.sectorCount == 0) continue;
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

RepairDiagnosisCode diagnoseVeraCrypt(int fd, uint64_t fileSize, int opId) {
    rlog(opId, "No LUKS or BitLocker signature -- treating as a VeraCrypt/TrueCrypt container.");
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
}

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
        rlog(opId, "LUKS magic found, but the version number isn't one this tool recognizes.");
        outFormatKnown = true;
        outFormat = ContainerFormat::kLuks2;
        return RepairDiagnosisCode::kHeaderCorrupted;
    }
    if (detectBitlockerAnywhereInFile(fd, fileSize, opId)) {
        outFormat = ContainerFormat::kBitLocker;
        outFormatKnown = true;
        return RepairDiagnosisCode::kHealthy;
    }
    outFormat = ContainerFormat::kVeraCrypt;
    outFormatKnown = true;
    return diagnoseVeraCrypt(fd, fileSize, opId);
}
}

bool repairFormatNeedsPasswordForRestore(ContainerFormat format) {
    return format == ContainerFormat::kVeraCrypt;
}

RepairDiagnosisCode diagnoseUnmountedContainerFile(int fd, ContainerFormat& outFormat, bool& outFormatKnown,
                                                    int logOpId) {
    RepairDiagnosisCode code = diagnoseUnmountedContainerFileImpl(fd, outFormat, outFormatKnown, logOpId);
    if (fd >= 0) close(fd);
    return code;
}

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
}

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

namespace {
bool fatReadBootSector(int volId, uint8_t sector[4096]) {
    return disk_read(static_cast<BYTE>(volId), sector, 0, 1) == RES_OK;
}

uint16_t leU16(const uint8_t* p) { return uint16_t(p[0]) | (uint16_t(p[1]) << 8); }

uint32_t leU32(const uint8_t* p) {
    return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}

uint64_t leU64(const uint8_t* p) {
    return uint64_t(leU32(p)) | (uint64_t(leU32(p + 4)) << 32);
}

enum class FatKind { kFat16, kFat32, kExFat, kUnsupported };

FatKind classifyFatBootSector(const uint8_t sector[4096]) {
    if (std::memcmp(sector + 3, "EXFAT   ", 8) == 0) return FatKind::kExFat;
    const uint16_t fat16SectorsPerFat = leU16(sector + 22);
    return fat16SectorsPerFat == 0 ? FatKind::kFat32 : FatKind::kFat16;
}

bool fatIsDirty(int volId, bool& outDirty) {
    uint8_t boot[4096];
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
            uint8_t fatSector[4096];
            if (disk_read(static_cast<BYTE>(volId), fatSector, reservedSectors, 1) != RES_OK) return false;
            outDirty = (leU32(fatSector + 4) & 0x08000000u) == 0;
            return true;
        }
        case FatKind::kFat16: {
            uint8_t fatSector[4096];
            if (disk_read(static_cast<BYTE>(volId), fatSector, reservedSectors, 1) != RES_OK) return false;
            outDirty = (leU16(fatSector + 2) & 0x8000u) == 0;
            return true;
        }
        default:
            return false;
    }
}

bool fatClearDirty(int volId) {
    uint8_t boot[4096];
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
            uint8_t fatSector[4096];
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
            uint8_t fatSector[4096];
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

struct FatCorruptEntry {
    std::string path;
    std::string parentPath;
    bool isDir;
    BYTE attr;
    FSIZE_t size;
    WORD date;
    WORD time;
};

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
    constexpr uint64_t kOneYearSeconds = 366ULL * 24 * 3600;
    const uint64_t entryUnix = fatToUnixTimestamp(fno.fdate, fno.ftime);
    if (entryUnix > nowUnix + kOneYearSeconds) return true;
    return false;
}

uint64_t fatVolumeCapacityBytes(int volId) {
    FATFS* fs = nullptr;
    DWORD freeClusters = 0;
    if (f_getfree(drivePaths[volId], &freeClusters, &fs) != FR_OK || !fs) return 0;
    const uint64_t ss = (fs->ssize > 0) ? fs->ssize : 512ULL;
    return static_cast<uint64_t>(fs->n_fatent - 2) * fs->csize * ss;
}

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
            outCorrupt.push_back({childSuffix, pathSuffix, isDir, fno.fattrib, fno.fsize, fno.fdate, fno.ftime});
            continue;
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

struct FatRawDirectorySlot {
    LBA_t sector;
    uint16_t offset;
};

bool fatRawEntryMatches(const uint8_t* raw, const FatCorruptEntry& entry) {
    constexpr uint8_t kDeleted = 0xE5;
    constexpr uint8_t kLongFileName = 0x0F;
    constexpr uint8_t kAttributeMask = 0x3F;
    if (raw[0] == 0 || raw[0] == kDeleted || raw[11] == kLongFileName) return false;
    return (raw[11] & kAttributeMask) == entry.attr &&
           leU16(raw + 22) == entry.time &&
           leU16(raw + 24) == entry.date &&
           leU32(raw + 28) == static_cast<uint32_t>(entry.size);
}

bool fatFindRawFatDirectorySlot(int volId, const FatCorruptEntry& entry, FatRawDirectorySlot& outSlot) {
    std::string parent = drivePaths[volId];
    if (!entry.parentPath.empty()) parent += "/" + entry.parentPath;
    DIR dir;
    if (f_opendir(&dir, parent.c_str()) != FR_OK) return false;
    FATFS* fs = dir.obj.fs;
    if (!fs) {
        f_closedir(&dir);
        return false;
    }
    const DWORD firstCluster = entry.parentPath.empty() ? static_cast<DWORD>(fs->dirbase) : dir.obj.sclust;
    f_closedir(&dir);
    if ((fs->fs_type != FS_FAT16 && fs->fs_type != FS_FAT32) || fs->csize == 0) return false;
    const uint32_t ss = (fs->ssize > 0) ? fs->ssize : 512;
    constexpr uint32_t kEndOfChain = 0x0FFFFFF8;
    constexpr uint32_t kBadCluster = 0x0FFFFFF7;
    FatRawDirectorySlot candidate{};
    size_t matchCount = 0;
    if (fs->fs_type == FS_FAT16 && entry.parentPath.empty()) {
        const DWORD rootSectors = (static_cast<DWORD>(fs->n_rootdir) * 32 + ss - 1) / ss;
        for (DWORD index = 0; index < rootSectors; ++index) {
            uint8_t sector[4096];
            const LBA_t sectorNumber = fs->dirbase + index;
            if (disk_read(static_cast<BYTE>(volId), sector, sectorNumber, 1) != RES_OK) return false;
            for (uint16_t offset = 0; offset < ss; offset += 32) {
                if (sector[offset] == 0) return matchCount == 1 && (outSlot = candidate, true);
                if (fatRawEntryMatches(sector + offset, entry)) {
                    candidate = {sectorNumber, offset};
                    if (++matchCount > 1) return false;
                }
            }
        }
        if (matchCount != 1) return false;
        outSlot = candidate;
        return true;
    }
    if (firstCluster < 2) return false;
    DWORD cluster = firstCluster;
    for (DWORD hops = 0; hops < fs->n_fatent && cluster >= 2 && cluster < fs->n_fatent; ++hops) {
        const LBA_t clusterSector = fs->database + static_cast<LBA_t>(cluster - 2) * fs->csize;
        for (WORD sectorInCluster = 0; sectorInCluster < fs->csize; ++sectorInCluster) {
            uint8_t sector[4096];
            const LBA_t sectorNumber = clusterSector + sectorInCluster;
            if (disk_read(static_cast<BYTE>(volId), sector, sectorNumber, 1) != RES_OK) return false;
            for (uint16_t offset = 0; offset < ss; offset += 32) {
                if (sector[offset] == 0) return matchCount == 1 && (outSlot = candidate, true);
                if (fatRawEntryMatches(sector + offset, entry)) {
                    candidate = {sectorNumber, offset};
                    if (++matchCount > 1) return false;
                }
            }
        }
        const uint32_t fatEntrySize = fs->fs_type == FS_FAT32 ? 4 : 2;
        const uint64_t fatByteOffset = static_cast<uint64_t>(cluster) * fatEntrySize;
        const LBA_t fatSector = fs->fatbase + fatByteOffset / ss;
        const uint16_t fatOffset = static_cast<uint16_t>(fatByteOffset % ss);
        uint8_t sector[4096];
        if (fatOffset > ss - fatEntrySize ||
            disk_read(static_cast<BYTE>(volId), sector, fatSector, 1) != RES_OK) {
            return false;
        }
        const DWORD next = fs->fs_type == FS_FAT32
            ? leU32(sector + fatOffset) & 0x0FFFFFFF
            : leU16(sector + fatOffset);
        const DWORD endOfChain = fs->fs_type == FS_FAT32 ? kEndOfChain : 0xFFF8;
        const DWORD badCluster = fs->fs_type == FS_FAT32 ? kBadCluster : 0xFFF7;
        if (next >= endOfChain) break;
        if (next < 2 || next == badCluster || next >= fs->n_fatent) return false;
        cluster = next;
    }
    if (matchCount != 1) return false;
    outSlot = candidate;
    return true;
}

bool fatRawDeleteCorruptFatEntry(int volId, const FatCorruptEntry& entry) {
    FatRawDirectorySlot slot{};
    if (!fatFindRawFatDirectorySlot(volId, entry, slot)) return false;
    uint8_t sector[4096];
    if (disk_read(static_cast<BYTE>(volId), sector, slot.sector, 1) != RES_OK) return false;
    sector[slot.offset] = 0xE5;
    if (disk_write(static_cast<BYTE>(volId), sector, slot.sector, 1) != RES_OK) return false;
    FATFS* fs = &volumes[volId].fatfs;
    if (fs->winsect == slot.sector) fs->win[slot.offset] = 0xE5;
    return true;
}

bool fatFindRawExFatDirectorySlot(int volId, const FatCorruptEntry& entry, FatRawDirectorySlot& outSlot) {
    std::string parent = drivePaths[volId];
    if (!entry.parentPath.empty()) parent += "/" + entry.parentPath;
    DIR dir;
    if (f_opendir(&dir, parent.c_str()) != FR_OK) return false;
    FATFS* fs = dir.obj.fs;
    if (!fs) {
        f_closedir(&dir);
        return false;
    }
    const DWORD firstCluster = entry.parentPath.empty() ? static_cast<DWORD>(fs->dirbase) : dir.obj.sclust;
    f_closedir(&dir);
    if (fs->fs_type != FS_EXFAT || firstCluster < 2 || fs->csize == 0) return false;
    const uint32_t ss = (fs->ssize > 0) ? fs->ssize : 512;
    constexpr uint32_t kEndOfChain = 0x0FFFFFF8;
    constexpr uint32_t kBadCluster = 0x0FFFFFF7;
    FatRawDirectorySlot candidate{};
    size_t matchCount = 0;
    DWORD cluster = firstCluster;
    for (DWORD hops = 0; hops < fs->n_fatent && cluster >= 2 && cluster < fs->n_fatent; ++hops) {
        const LBA_t clusterSector = fs->database + static_cast<LBA_t>(cluster - 2) * fs->csize;
        for (WORD sectorInCluster = 0; sectorInCluster < fs->csize; ++sectorInCluster) {
            uint8_t sector[4096];
            const LBA_t sectorNumber = clusterSector + sectorInCluster;
            if (disk_read(static_cast<BYTE>(volId), sector, sectorNumber, 1) != RES_OK) return false;
            for (uint16_t offset = 0; offset < ss; offset += 32) {
                if (sector[offset] == 0) return matchCount == 1 && (outSlot = candidate, true);
                if (sector[offset] != 0x85 || offset > ss - 64 || sector[offset + 32] != 0xC0) continue;
                const uint8_t* primary = sector + offset;
                const uint8_t* stream = primary + 32;
                const uint64_t size = entry.isDir ? 0 : leU64(stream + 24);
                if ((leU16(primary + 4) & 0x3F) != entry.attr ||
                    leU16(primary + 12) != entry.time || leU16(primary + 14) != entry.date ||
                    size != entry.size) {
                    continue;
                }
                candidate = {sectorNumber, offset};
                if (++matchCount > 1) return false;
            }
        }
        const uint64_t fatByteOffset = static_cast<uint64_t>(cluster) * 4;
        const LBA_t fatSector = fs->fatbase + fatByteOffset / ss;
        const uint16_t fatOffset = static_cast<uint16_t>(fatByteOffset % ss);
        uint8_t sector[4096];
        if (fatOffset > ss - 4 ||
            disk_read(static_cast<BYTE>(volId), sector, fatSector, 1) != RES_OK) return false;
        const DWORD next = leU32(sector + fatOffset) & 0x0FFFFFFF;
        if (next >= kEndOfChain) break;
        if (next < 2 || next == kBadCluster || next >= fs->n_fatent) return false;
        cluster = next;
    }
    if (matchCount != 1) return false;
    outSlot = candidate;
    return true;
}

bool fatRawDeleteCorruptExFatEntry(int volId, const FatCorruptEntry& entry) {
    FatRawDirectorySlot slot{};
    if (!fatFindRawExFatDirectorySlot(volId, entry, slot)) return false;
    uint8_t sector[4096];
    if (disk_read(static_cast<BYTE>(volId), sector, slot.sector, 1) != RES_OK) return false;
    sector[slot.offset] &= 0x7F;
    if (disk_write(static_cast<BYTE>(volId), sector, slot.sector, 1) != RES_OK) return false;
    FATFS* fs = &volumes[volId].fatfs;
    if (fs->winsect == slot.sector) fs->win[slot.offset] &= 0x7F;
    return true;
}

bool fatRawDeleteCorruptEntry(int volId, const FatCorruptEntry& entry) {
    return fatRawDeleteCorruptFatEntry(volId, entry) || fatRawDeleteCorruptExFatEntry(volId, entry);
}

bool fatHasCorruptEntries(int volId, int opId) {
    const uint64_t capacity = fatVolumeCapacityBytes(volId);
    const uint64_t nowUnix = static_cast<uint64_t>(time(nullptr));
    std::vector<FatCorruptEntry> found;
    fatScanForCorruptEntries(volId, "", capacity, nowUnix, found, opId);
    return !found.empty();
}

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
        FRESULT fr = entry.isDir ? fatRemoveRecursiveForRepair(fullPath.c_str()) : f_unlink(fullPath.c_str());
        bool rawDeleted = false;
        if (fr != FR_OK) {
            char fallback[320];
            std::snprintf(fallback, sizeof(fallback),
                          "FatFs could not unlink %s (error %d); trying raw FAT directory-slot removal...",
                          entry.path.c_str(), static_cast<int>(fr));
            rlog(opId, fallback);
            rawDeleted = fatRawDeleteCorruptEntry(volId, entry);
        }
        char msg[320];
        std::snprintf(msg, sizeof(msg), "%s: %s",
                      (fr == FR_OK || rawDeleted) ? "Removed" : "Failed to remove", entry.path.c_str());
        rlog(opId, msg);
        if (fr != FR_OK && !rawDeleted) allRemoved = false;
    }
    return allRemoved;
}
}

RepairDiagnosisCode diagnoseMountedVolumeFilesystem(int volId, int logOpId) {
    if (volId < 0 || volId >= FF_VOLUMES) return RepairDiagnosisCode::kHealthy;
    VolumeState& v = volumes[volId];
    switch (v.fsType) {
        case VolumeState::FS_EXT: {
            rlog(logOpId, "ext filesystem -- checking the superblock's clean-unmount state...");
            const bool dirty = extIsDirty(volId);
            rlog(logOpId, dirty ? "Superblock reports the filesystem was not unmounted cleanly."
                                 : "Superblock reports a clean unmount.");
            rlog(logOpId, "Scanning the directory tree for entries with invalid inodes or impossible metadata...");
            const bool hasCorruptEntries = extHasCorruptDirectoryEntries(volId);
            if (!hasCorruptEntries) rlog(logOpId, "No corrupted directory entries found.");
            rlog(logOpId, "Comparing ext free-block counters with the allocation bitmap...");
            const bool badFreeSpaceAccounting = extFreeSpaceAccountingNeedsRepair(volId);
            if (badFreeSpaceAccounting) {
                rlog(logOpId, "Free-block counters disagree with the allocation bitmap; the volume may appear full incorrectly.");
            }
            rlog(logOpId, "Scanning for orphaned inodes (allocated but unreachable from any directory)...");
            const bool hasOrphanedInodes = extHasOrphanedInodes(volId);
            if (hasOrphanedInodes) {
                rlog(logOpId, "Found inodes that are allocated but not referenced by any directory entry; their blocks are wasting space.");
            } else {
                rlog(logOpId, "No orphaned inodes found.");
            }
            return (dirty || hasCorruptEntries || badFreeSpaceAccounting || hasOrphanedInodes)
                ? RepairDiagnosisCode::kFilesystemDirty : RepairDiagnosisCode::kHealthy;
        }
        case VolumeState::FS_NTFS: {
            rlog(logOpId, "NTFS filesystem -- checking the $Volume dirty flag...");
            const bool dirty = ntfsIsDirty(volId);
            rlog(logOpId, dirty ? "$Volume dirty flag is set." : "$Volume dirty flag is clear.");
            rlog(logOpId, "Scanning the $I30 directory indexes for unreadable entries or impossible metadata...");
            const bool hasCorruptEntries = ntfsHasCorruptDirectoryEntries(volId);
            if (!hasCorruptEntries) rlog(logOpId, "No corrupted directory entries found.");
            return (dirty || hasCorruptEntries) ? RepairDiagnosisCode::kFilesystemDirty
                                                : RepairDiagnosisCode::kHealthy;
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
                                                        : RepairDiagnosisCode::kHealthy;
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
        case VolumeState::FS_EXT: {
            rlog(logOpId, "Clearing the ext superblock's dirty/error state...");
            const bool clearedFlag = extClearDirtyState(volId);
            rlog(logOpId, "Removing corrupted ext directory entries...");
            const bool removedCorrupt = extRemoveCorruptDirectoryEntries(volId);
            rlog(logOpId, "Reclaiming orphaned inodes (allocated but unreachable from any directory)...");
            const bool reclaimedOrphans = extReclaimOrphanedInodes(volId);
            if (reclaimedOrphans) {
                rlog(logOpId, "Orphaned inodes reclaimed successfully.");
            }
            rlog(logOpId, "Rebuilding ext free-block counters from the allocation bitmap...");
            const bool repairedFreeSpaceAccounting = extRepairFreeSpaceAccounting(volId);
            return clearedFlag && removedCorrupt && reclaimedOrphans && repairedFreeSpaceAccounting;
        }
        case VolumeState::FS_NTFS: {
            rlog(logOpId, "Clearing the NTFS $Volume dirty flag...");
            const bool clearedFlag = ntfsClearDirtyFlag(volId);
            rlog(logOpId, "Removing corrupted NTFS directory-index entries...");
            const bool removedCorrupt = ntfsRemoveCorruptDirectoryEntries(volId);
            return clearedFlag && removedCorrupt;
        }
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