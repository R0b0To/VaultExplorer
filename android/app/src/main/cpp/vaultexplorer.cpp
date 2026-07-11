#include <jni.h>
#include <cstdio>
#include <string>
#include <fstream>
#include <vector>
#include <android/log.h>
#include <iomanip>
#include <sstream>
#include <cstring>
#include <cstdlib>
#include <unistd.h>
#include <sys/stat.h>
#include <memory>
#include <algorithm>
#include <mutex>
#include <atomic>
#include <chrono>
#include <ctime>   
#include "sector_batching.h"
#include "mbedtls/md.h"
#include "mbedtls/pkcs5.h"
#include "mbedtls/aes.h"

#include "ff.h"
#include "diskio.h"
#include "crypto/cascade.h"
#include "crypto/vc_header_layout.h"
#include "crypto/keyfile_mixing.h"
#include "crypto/luks_header.h"
#include "container_format.h"
#include "container_header.h"
#include "container_utils.h"
#include "block_io.h"
#include "ext_backend.h"
#include "fat_backend.h"
#include "filesystem_paths.h"
#include "jni_callbacks.h"
#include "ntfs_backend.h"
#include "session_guard.h"
#include "volume_state.h"
#include <thread>

#include <fcntl.h>

extern "C" {
#include "device.h"
#include "volume.h"
#include "inode.h"
#include "dir.h"
#include "attrib.h"
#include "layout.h"
#include <ext2fs/ext2fs.h>
#include <ext2fs/ext2_io.h>
#include <et/com_err.h>
}

// Undefine conflicting macros defined by NTFS-3G support.h
#undef min
#undef max

struct NtfsStream {
    ntfs_inode* inode = nullptr;
    ntfs_attr*  attr = nullptr;
};

extern "C" int vaultexplorer_mkntfs_main(int argc, char* argv[]);

struct ExtStream {
    ext2_file_t file = nullptr;
};

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

static inline long long elapsedMs(const std::chrono::steady_clock::time_point& start) {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start).count();
}

#define MAX_VOLUMES FF_VOLUMES


static constexpr size_t IO_BUFFER_SIZE          = 262144;   
static constexpr int    VC_KEY_MATERIAL_LEN     = 64;
static constexpr size_t MAX_DIR_ENTRIES         = 50000;
static constexpr int    MKFS_WORK_BUF_SIZE      = 4096;
static constexpr size_t MAX_CHUNK_SIZE          = 64 * 1024 * 1024;
static constexpr uint64_t FALLBACK_SECTOR_COUNT_UNINITIALIZED = 1000000; 
static constexpr uint64_t CREATE_FILL_BATCH     = 4096;
static constexpr size_t   IO_VOL_BUF_SECTORS    = 512;    
static constexpr size_t   IO_VOL_BUF_SIZE       = IO_VOL_BUF_SECTORS * 512;

// ----------------------------------------------------------------====
// RAII WRAPPERS
// ----------------------------------------------------------------====

struct MdContextGuard {
    mbedtls_md_context_t ctx;
    MdContextGuard() { mbedtls_md_init(&ctx); }
    ~MdContextGuard() { mbedtls_md_free(&ctx); }
};


struct ScopeZeroize {
    unsigned char* buf; size_t len;
    ScopeZeroize(unsigned char* b, size_t l) : buf(b), len(l) {}
    ~ScopeZeroize() { mbedtls_platform_zeroize(buf, len); }
    ScopeZeroize(const ScopeZeroize&) = delete;
    ScopeZeroize& operator=(const ScopeZeroize&) = delete;
};


static void closeUnusedKeyfileFds(const int* keyfileFds, int keyfileCount) {
    if (!keyfileFds) return;
    for (int i = 0; i < keyfileCount; i++) {
        if (keyfileFds[i] >= 0) close(keyfileFds[i]);
    }
}

// ----------------------------------------------------------------====
// PER-VOLUME STATE
// ----------------------------------------------------------------====

// ----------------------------------------------------------------====
// NTFS SUPPORT STRUCTURES & OPERATIONS
// ----------------------------------------------------------------====

struct NtfsFilldirContext {
    std::vector<std::string>* results;
    ntfs_volume* vol;
};

static int vExplorer_ntfs_filldir(void *dirent, const ntfschar *name, const int name_len, const int name_type, const s64 pos, const MFT_REF mft_reference, const unsigned dt_type) {
    NtfsFilldirContext* ctx = static_cast<NtfsFilldirContext*>(dirent);

    if (name_type == FILE_NAME_DOS) {
        return 0;
    }

    char* utf8Name = nullptr;
    int utf8NameLen = ntfs_ucstombs(name, name_len, &utf8Name, 0);
    if (utf8NameLen < 0 || !utf8Name) {
        if (utf8Name) free(utf8Name);
        return 0;
    }

    std::string nameStr(utf8Name, utf8NameLen);
    free(utf8Name);

    if (nameStr == "." || nameStr == "..") {
        return 0;
    }

    //Hide ONLY specific NTFS metadata & Windows system folders ---
    if (nameStr[0] == '$') {
        if (nameStr == "$MFT" || nameStr == "$MFTMirr" || nameStr == "$LogFile" ||
            nameStr == "$Volume" || nameStr == "$AttrDef" || nameStr == "$Bitmap" ||
            nameStr == "$Boot" || nameStr == "$BadClus" || nameStr == "$Secure" ||
            nameStr == "$UpCase" || nameStr == "$Extend" || nameStr == "$RECYCLE.BIN") {
            return 0;
        }
    } else if (nameStr == "System Volume Information") {
        return 0;
    }
    // -------------------------------------------------------------------------------


    ntfs_inode* ni = ntfs_inode_open(ctx->vol, mft_reference);
    if (!ni) return 0;

    uint64_t size = 0;
    uint64_t ts = 0;
    bool isDir = (ni->mrec->flags & MFT_RECORD_IS_DIRECTORY) != 0;

    if (!isDir) {
        size = ni->data_size;
    }

    uint64_t ntfsTime = ni->last_data_change_time;
    if (ntfsTime > 116444736000000000ULL) {
        ts = (ntfsTime - 116444736000000000ULL) / 10000000ULL;
    }

    ntfs_inode_close(ni);

    if (isDir) {
        ctx->results->push_back("[DIR] " + nameStr + "|0|" + std::to_string(ts));
    } else {
        ctx->results->push_back(nameStr + "|" + std::to_string(size) + "|" + std::to_string(ts));
    }
    return 0;
}

// ----------------------------------------------------------------====
// MOUNT CACHE HELPERS
// ----------------------------------------------------------------====

static bool ensureMounted(int volId) {
    if (volId < 0 || volId >= MAX_VOLUMES) return false;
    auto& v = volumes[volId];
    if (v.fsMounted) return true;

    alignas(16) unsigned char decS[512];
    DRESULT dr = disk_read(static_cast<BYTE>(volId), decS, 0, 1);
    if (dr != RES_OK) {
        LOGI("ensureMounted: failed to read boot sector for volume %d", volId);
        return false;
    }

    alignas(16) unsigned char extSuperSector[512];
    if (disk_read(static_cast<BYTE>(volId), extSuperSector, 2, 1) == RES_OK &&
        extSuperSector[0x38] == 0x53 && extSuperSector[0x39] == 0xEF) {
        return mountExtVolume(volId);
    }

    if (decS[510] != 0x55 || decS[511] != 0xAA) {
        LOGI("ensureMounted: invalid signature in boot sector for volume %d", volId);
        return false;
    }

    // Inspect Boot Sector for NTFS Oem ID
    if (std::memcmp(&decS[3], "NTFS    ", 8) == 0) {
        v.fsType = VolumeState::FS_NTFS;
        LOGI("ensureMounted: detected NTFS on volume %d", volId);

        int* privVolId = new int(volId);
        struct ntfs_device* dev = ntfs_device_alloc("vaultexplorer", 0, &vExplorer_ntfs_ops, privVolId);
        if (!dev) {
            delete privVolId;
            return false;
        }

        v.ntfsVol = ntfs_device_mount(dev, 0);
        if (!v.ntfsVol) {
            v.ntfsVol = ntfs_device_mount(dev, NTFS_MNT_RECOVER);
        }

        if (!v.ntfsVol) {
            LOGI("ensureMounted: ntfs_device_mount failed");
            ntfs_device_free(dev);
            delete privVolId;
            return false;
        }
        v.fsMounted = true;
        return true;
    } else {
        v.fsType = VolumeState::FS_FATFS;
        FRESULT fr = f_mount(&v.fatfs, drivePaths[volId], 1);
        if (fr == FR_OK) {
            v.fsMounted = true;
            return true;
        }
        return false;
    }
}

static void unmountVolume(int volId) {
    if (volId < 0 || volId >= MAX_VOLUMES) return;
    auto& v = volumes[volId];
    if (v.fsMounted) {
        if (v.fsType == VolumeState::FS_FATFS) {
            f_mount(nullptr, drivePaths[volId], 0);
        } else if (v.fsType == VolumeState::FS_NTFS && v.ntfsVol) {
            void* priv = v.ntfsVol->dev->d_private;
            ntfs_umount(v.ntfsVol, FALSE);
            if (priv) delete static_cast<int*>(priv);
            v.ntfsVol = nullptr;
        } else if (v.fsType == VolumeState::FS_EXT && v.extFs) {
            for (ExtStream* stream : v.openExtStreams) {
                ext2fs_file_close(stream->file);
                delete stream;
            }
            v.openExtStreams.clear();
            ext2fs_flush(v.extFs);
            ext2fs_close(v.extFs);
            v.extFs = nullptr;
        }
        v.fsMounted = false;
        v.fsType = VolumeState::FS_UNKNOWN;
    }
    std::lock_guard<std::mutex> bufLock(v.ioBufMutex);
    v.ioBuf.reset();
    v.ioBufSize = 0;
}

// ----------------------------------------------------------------====
// INLINE HELPERS
// ----------------------------------------------------------------====

static inline void setTweak(unsigned char* tweak, uint64_t sectorNum) {
    *reinterpret_cast<uint64_t*>(tweak)   = sectorNum;
    *reinterpret_cast<uint64_t*>(tweak+8) = 0ULL;
}

static inline int clampPim(int pim) {
    if (pim < 0) return 0;
    if (pim > 2000) return 2000;
    return pim;
}

struct PartitionCandidate {
    uint64_t startSector;
    uint64_t sectorCount;
};

static unsigned char* getVolIoBuf(VolumeState& v, size_t neededBytes) {
    if (v.ioBufSize < neededBytes) {
        v.ioBuf.reset(new unsigned char[neededBytes]);
        v.ioBufSize = neededBytes;
    }
    return v.ioBuf.get();
}

// ----------------------------------------------------------------====
// FATFS LOW-LEVEL DISK HOOKS
// ----------------------------------------------------------------====

extern "C" DSTATUS disk_initialize(BYTE pdrv) { return 0; }
extern "C" DSTATUS disk_status(BYTE pdrv)     { return 0; }

// Generic single-cipher XTS over a whole-block data unit (Serpent/Twofish —
// ciphers mbedTLS doesn't provide XTS mode for). Defined below, alongside
// localMultiplyTweak, which it reuses for the GF(2^128) tweak doubling;
// forward-declared here so disk_read/disk_write can call it. LUKS never
// needs ciphertext stealing, so dataLen is always a whole multiple of 16.
static void genericLuksXtsCrypt(const XtsLayerKey& layer, bool encrypt, size_t dataLen,
                                 const unsigned char tweakSeed[16],
                                 const unsigned char* in, unsigned char* out);

extern "C" DRESULT disk_read(BYTE pdrv, BYTE* buff, LBA_t sector, UINT count) {
    if (pdrv >= MAX_VOLUMES || !volumes[pdrv].dataCtxInitialized)
        return RES_NOTRDY;
    if (!volumes[pdrv].isUsbSource && volumes[pdrv].fd < 0)
        return RES_NOTRDY;
    if (count == 0) return RES_PARERR;

    VolumeState& v = volumes[pdrv];
    const uint64_t basePhysical = v.dataOffset / 512;
    static constexpr uint32_t MAX_SECTORS_PER_BATCH = 8192; // 4 MB/batch
    alignas(16) unsigned char stackBuf[65536];

    // LUKS AES-XTS "sector_size" (default 512) is the data-unit width: every
    // luksSectorSize-byte block shares exactly one XTS tweak. sectorsPerUnit
    // expresses that width in 512-byte FatFs/ext2/ntfs sectors. When it's >1
    // we must always decrypt whole aligned units, even if the caller only
    // asked for a sub-range of one — XTS can't be decrypted starting mid-unit.
    const bool isLuks = (v.containerFormat != ContainerFormat::kVeraCrypt);
    const uint32_t luksUnit = (isLuks && v.luksSectorSize >= 512) ? v.luksSectorSize : 512;
    const uint32_t sectorsPerUnit = luksUnit / 512;

    const auto batches = planSectorBatches(static_cast<uint32_t>(count), MAX_SECTORS_PER_BATCH);

    for (const auto& batch : batches) {
        const uint64_t firstPhysical = basePhysical + sector + batch.startSector;
        BYTE* curBuf = buff + batch.startSector * 512;

        // Expand the requested sector range out to full sectorsPerUnit-aligned
        // units, relative to the same base the tweak counter uses
        // (partitionStartSector). For VeraCrypt / LUKS1 / default-sector-size
        // LUKS2, sectorsPerUnit==1 so this is a no-op.
        const uint64_t relStart = firstPhysical - v.partitionStartSector;
        const uint64_t relEnd   = relStart + batch.count;
        const uint64_t alignedRelStart = (relStart / sectorsPerUnit) * sectorsPerUnit;
        const uint64_t alignedRelEnd   = ((relEnd + sectorsPerUnit - 1) / sectorsPerUnit) * sectorsPerUnit;
        const uint64_t alignedFirstPhysical = alignedRelStart + v.partitionStartSector;
        const uint64_t alignedCount    = alignedRelEnd - alignedRelStart;
        const size_t   totalBytes      = static_cast<size_t>(alignedCount) * 512;
        const size_t   copyOffset      = static_cast<size_t>(relStart - alignedRelStart) * 512;
        const size_t   copyBytes       = static_cast<size_t>(batch.count) * 512;

        unsigned char* encBuf;
        bool usedPersistent = (totalBytes > sizeof(stackBuf));

        std::unique_lock<std::mutex> bufLock;
        if (usedPersistent) {
            bufLock = std::unique_lock<std::mutex>(v.ioBufMutex);
            encBuf = getVolIoBuf(v, totalBytes);
        } else {
            encBuf = stackBuf;
        }

        if (!physicalRead(pdrv, alignedFirstPhysical * 512, encBuf, totalBytes)) return RES_ERROR;

        if (v.containerFormat == ContainerFormat::kVeraCrypt) {
            for (UINT i = 0; i < batch.count; i++) {
                const uint64_t physSector = firstPhysical + i;
                const uint64_t tweak = physSector - v.partitionStartSector;
                cascadeDecryptSector(v.cascade, tweak, encBuf + (i*512), curBuf + (i*512));
            }
        } else if (sectorsPerUnit <= 1) {
            for (UINT i = 0; i < batch.count; i++) {
                const uint64_t sectorNum = (firstPhysical + i) - v.partitionStartSector;
                unsigned char tweakBuf[16] = {0};
                for (int b = 0; b < 8; b++) tweakBuf[b] = (sectorNum >> (b * 8)) & 0xFF;
                if (v.luksUsesGenericCipher) {
                    genericLuksXtsCrypt(v.luksGenericCascade.layers[0], false, 512, tweakBuf,
                                         encBuf + (i * 512), curBuf + (i * 512));
                } else {
                    mbedtls_aes_crypt_xts(&v.luksXts.dec, MBEDTLS_AES_DECRYPT, 512, tweakBuf,
                                           encBuf + (i * 512), curBuf + (i * 512));
                }
            }
        } else {
            // Decrypt every full aligned unit, then copy out only the sectors
            // that were actually requested.
            std::vector<unsigned char> decBuf(totalBytes);
            for (uint64_t u = 0; u < alignedCount; u += sectorsPerUnit) {
                const uint64_t sectorTweak = alignedRelStart + u;
unsigned char tweakBuf[16] = {0};
for (int b = 0; b < 8; b++) tweakBuf[b] = (sectorTweak >> (b * 8)) & 0xFF;
                if (v.luksUsesGenericCipher) {
                    genericLuksXtsCrypt(v.luksGenericCascade.layers[0], false, luksUnit, tweakBuf,
                                         encBuf + (u * 512), decBuf.data() + (u * 512));
                } else {
                    mbedtls_aes_crypt_xts(&v.luksXts.dec, MBEDTLS_AES_DECRYPT, luksUnit, tweakBuf,
                                           encBuf + (u * 512), decBuf.data() + (u * 512));
                }
            }
            std::memcpy(curBuf, decBuf.data() + copyOffset, copyBytes);
        }
    }
    return RES_OK;
}

extern "C" DRESULT disk_write(BYTE pdrv, const BYTE* buff, LBA_t sector, UINT count) {
    if (pdrv >= MAX_VOLUMES || !volumes[pdrv].dataCtxInitialized)
        return RES_NOTRDY;
    if (!volumes[pdrv].isUsbSource && volumes[pdrv].fd < 0)
        return RES_NOTRDY;
    if (count == 0) return RES_PARERR;

    VolumeState& v = volumes[pdrv];
    const uint64_t basePhysical = v.dataOffset / 512;

    static constexpr uint32_t MAX_SECTORS_PER_BATCH = 8192;
    alignas(16) unsigned char stackBuf[65536];

    // See disk_read for why sectorsPerUnit matters. On the write side, a
    // sub-unit write (batch doesn't cover a whole aligned unit) requires a
    // read-modify-write: pull the existing ciphertext, decrypt the untouched
    // parts of each partially-covered unit, splice in the new plaintext,
    // then re-encrypt whole units before writing back.
    const bool isLuks = (v.containerFormat != ContainerFormat::kVeraCrypt);
    const uint32_t luksUnit = (isLuks && v.luksSectorSize >= 512) ? v.luksSectorSize : 512;
    const uint32_t sectorsPerUnit = luksUnit / 512;

    const auto batches = planSectorBatches(static_cast<uint32_t>(count), MAX_SECTORS_PER_BATCH);

    for (const auto& batch : batches) {
        const uint64_t firstPhysical = basePhysical + sector + batch.startSector;
        const BYTE* curBuf = buff + batch.startSector * 512;

        const uint64_t relStart = firstPhysical - v.partitionStartSector;
        const uint64_t relEnd   = relStart + batch.count;
        const uint64_t alignedRelStart = (relStart / sectorsPerUnit) * sectorsPerUnit;
        const uint64_t alignedRelEnd   = ((relEnd + sectorsPerUnit - 1) / sectorsPerUnit) * sectorsPerUnit;
        const uint64_t alignedFirstPhysical = alignedRelStart + v.partitionStartSector;
        const uint64_t alignedCount    = alignedRelEnd - alignedRelStart;
        const size_t   totalBytes      = static_cast<size_t>(alignedCount) * 512;
        const bool     needsSplice     = (alignedCount != batch.count);

        unsigned char* encBuf;

        bool usedPersistent = (totalBytes > sizeof(stackBuf));
        std::unique_lock<std::mutex> bufLock;
        if (usedPersistent) {
            bufLock = std::unique_lock<std::mutex>(v.ioBufMutex);
            encBuf = getVolIoBuf(v, totalBytes);
        } else {
            encBuf = stackBuf;
        }

        if (v.containerFormat == ContainerFormat::kVeraCrypt) {
            for (UINT i = 0; i < batch.count; i++) {
                const uint64_t physSector = firstPhysical + i;
                const uint64_t tweak = physSector - v.partitionStartSector;
                cascadeEncryptSector(v.cascade, tweak, curBuf + (i * 512), encBuf + (i * 512));
            }
        } else if (sectorsPerUnit <= 1) {
            for (UINT i = 0; i < batch.count; i++) {
                const uint64_t sectorNum = (firstPhysical + i) - v.partitionStartSector;
                unsigned char tweakBuf[16] = {0};
                for (int b = 0; b < 8; b++) tweakBuf[b] = (sectorNum >> (b * 8)) & 0xFF;
                if (v.luksUsesGenericCipher) {
                    genericLuksXtsCrypt(v.luksGenericCascade.layers[0], true, 512, tweakBuf,
                                         curBuf + (i * 512), encBuf + (i * 512));
                } else {
                    mbedtls_aes_crypt_xts(&v.luksXts.enc, MBEDTLS_AES_ENCRYPT, 512, tweakBuf,
                                           curBuf + (i * 512), encBuf + (i * 512));
                }
            }
        } else {
            std::vector<unsigned char> plain(totalBytes);
            if (needsSplice) {
                std::vector<unsigned char> existingEnc(totalBytes);
                if (!physicalRead(pdrv, alignedFirstPhysical * 512, existingEnc.data(), totalBytes))
                    return RES_ERROR;
                for (uint64_t u = 0; u < alignedCount; u += sectorsPerUnit) {
                    const uint64_t sectorTweak = alignedRelStart + u;
unsigned char tweakBuf[16] = {0};
for (int b = 0; b < 8; b++) tweakBuf[b] = (sectorTweak >> (b * 8)) & 0xFF;
                    if (v.luksUsesGenericCipher) {
                        genericLuksXtsCrypt(v.luksGenericCascade.layers[0], false, luksUnit, tweakBuf,
                                             existingEnc.data() + (u * 512), plain.data() + (u * 512));
                    } else {
                        mbedtls_aes_crypt_xts(&v.luksXts.dec, MBEDTLS_AES_DECRYPT, luksUnit, tweakBuf,
                                               existingEnc.data() + (u * 512), plain.data() + (u * 512));
                    }
                }
            }
            const size_t copyOffset = static_cast<size_t>(relStart - alignedRelStart) * 512;
            std::memcpy(plain.data() + copyOffset, curBuf, static_cast<size_t>(batch.count) * 512);

            for (uint64_t u = 0; u < alignedCount; u += sectorsPerUnit) {
                const uint64_t sectorTweak = alignedRelStart + u;
unsigned char tweakBuf[16] = {0};
for (int b = 0; b < 8; b++) tweakBuf[b] = (sectorTweak >> (b * 8)) & 0xFF;;
                if (v.luksUsesGenericCipher) {
                    genericLuksXtsCrypt(v.luksGenericCascade.layers[0], true, luksUnit, tweakBuf,
                                         plain.data() + (u * 512), encBuf + (u * 512));
                } else {
                    mbedtls_aes_crypt_xts(&v.luksXts.enc, MBEDTLS_AES_ENCRYPT, luksUnit, tweakBuf,
                                           plain.data() + (u * 512), encBuf + (u * 512));
                }
            }
        }

        if (!physicalWrite(pdrv, alignedFirstPhysical * 512, encBuf, totalBytes)) return RES_ERROR;

    }
    return RES_OK;
}

extern "C" DRESULT disk_ioctl(BYTE pdrv, BYTE cmd, void* buff) {
    switch (cmd) {
        case CTRL_SYNC:
            return RES_OK;

        case GET_SECTOR_COUNT:
            if (pdrv < MAX_VOLUMES && volumes[pdrv].dataAreaLengthBytes > 0) {
                *(LBA_t*)buff = static_cast<LBA_t>(volumes[pdrv].dataAreaLengthBytes / 512);
            } else if (pdrv < MAX_VOLUMES && volumes[pdrv].fileSize > VC_DATA_AREA_OFFSET * 2) {
                *(LBA_t*)buff = static_cast<LBA_t>(
                    (volumes[pdrv].fileSize - VC_DATA_AREA_OFFSET * 2) / 512);
            } else {
                *(LBA_t*)buff = FALLBACK_SECTOR_COUNT_UNINITIALIZED;
            }
            return RES_OK;

        case GET_SECTOR_SIZE:
            *(WORD*)buff  = 512;
            return RES_OK;

        case GET_BLOCK_SIZE:
            *(DWORD*)buff = 1;
            return RES_OK;
    }
    return RES_PARERR;
}

extern "C" DWORD get_fattime() {
    time_t now = time(nullptr);
    struct tm t{};
    localtime_r(&now, &t);

    WORD fdate = static_cast<WORD>(
        (((t.tm_year + 1900 - 1980) & 0x7F) << 9) |
        (((t.tm_mon + 1)            & 0x0F) << 5) |
        ( t.tm_mday                 & 0x1F));

    WORD ftime = static_cast<WORD>(
        ((t.tm_hour & 0x1F) << 11) |
        ((t.tm_min  & 0x3F) << 5)  |
        ((t.tm_sec / 2) & 0x1F));

    return (static_cast<DWORD>(fdate) << 16) | ftime;
}

static std::atomic<bool> derivationInProgress[MAX_VOLUMES];

static bool _ext2ErrorTableInit = [](){
    initialize_ext2_error_table();   
    return true;
}();

static bool _derivationInit = [](){
    for (int i = 0; i < MAX_VOLUMES; i++)
        derivationInProgress[i].store(false);
    return true;
}();


static std::atomic<bool> cancelRequested[MAX_VOLUMES];

static bool _cancelInit = [](){
    for (int i = 0; i < MAX_VOLUMES; i++)
        cancelRequested[i].store(false);
    return true;
}();

static inline bool isUnlockCancelled(int volId) {
    return volId >= 0 && volId < MAX_VOLUMES &&
           cancelRequested[volId].load(std::memory_order_acquire);
}


static void localMultiplyTweak(unsigned char T[16]) {
    unsigned char carry = 0;
    for (int i = 0; i < 16; i++) {
        unsigned char nextCarry = (T[i] & 0x80) ? 1 : 0;
        T[i] = (T[i] << 1) | carry;
        carry = nextCarry;
    }
    if (carry) {
        T[0] ^= 0x87;
    }
}

// See forward declaration near disk_read for rationale. Mirrors
// tryDecryptHeader's per-block tweak/encrypt/decrypt loop below, just
// parameterized on an arbitrary starting tweak seed (the LE sector-number
// buffer) instead of always starting from an all-zero seed.
static void genericLuksXtsCrypt(const XtsLayerKey& layer, bool encrypt, size_t dataLen,
                                 const unsigned char tweakSeed[16],
                                 const unsigned char* in, unsigned char* out) {
    unsigned char T[16];
    blockCipherEncryptBlock(layer.tweakKey, tweakSeed, T);
    for (size_t b = 0; b < dataLen / 16; b++) {
        unsigned char tmp[16];
        for (int j = 0; j < 16; j++) tmp[j] = in[b * 16 + j] ^ T[j];
        if (encrypt) blockCipherEncryptBlock(layer.dataKeyEnc, tmp, tmp);
        else         blockCipherDecryptBlock(layer.dataKeyDec, tmp, tmp);
        for (int j = 0; j < 16; j++) out[b * 16 + j] = tmp[j] ^ T[j];
        localMultiplyTweak(T);
    }
}

static bool tryDecryptHeader(
    const unsigned char encH[VC_HEADER_BODY_SIZE],
    CascadeId cipherId,
    const unsigned char* derivedKeyMaterial,
    unsigned char decH[VC_HEADER_BODY_SIZE],
    ParsedHeaderFields* outFields = nullptr
) {
    CascadeContext tempCtx;
    CascadeSpec spec = cascadeSpecFor(cipherId);
    if (!cascadeSetKeys(tempCtx, cipherId, derivedKeyMaterial, spec.layerCount * 64)) {
        return false;
    }

    std::memcpy(decH, encH, VC_HEADER_BODY_SIZE);

    for (int i = spec.layerCount - 1; i >= 0; i--) {
        const XtsLayerKey& layer = tempCtx.layers[i];
        unsigned char T[16] = {0};
        blockCipherEncryptBlock(layer.tweakKey, T, T);

        for (int block = 0; block < 28; block++) {
            unsigned char* blockPtr = decH + block * 16;
            unsigned char tmp[16];
            for (int j = 0; j < 16; j++) tmp[j] = blockPtr[j] ^ T[j];
            blockCipherDecryptBlock(layer.dataKeyDec, tmp, tmp);
            for (int j = 0; j < 16; j++) blockPtr[j] = tmp[j] ^ T[j];

            localMultiplyTweak(T);
        }
    }

    if (decH[0] != 'V' || decH[1] != 'E' || decH[2] != 'R' || decH[3] != 'A') {
        return false;
    }

    const uint32_t computedHdrCrc = crc32(decH, VC_HDR_CRC_COVERAGE_LEN);
    const uint32_t storedHdrCrc   = readHeaderBE32(decH, VC_HDR_OFF_HEADER_CRC);
    if (computedHdrCrc != storedHdrCrc) {
        return false;
    }

    const uint32_t computedKeyCrc = crc32(&decH[VC_KEY_OFFSET_MASTER], VC_HDR_KEY_CRC_COVERAGE_LEN);
    const uint32_t storedKeyCrc = readHeaderBE32(decH, VC_HDR_OFF_KEY_CRC);
    if (computedKeyCrc != storedKeyCrc) {
        return false;
    }


    if (outFields) {
        outFields->volumeSize          = readHeaderBE64(decH, VC_HDR_OFF_VOLUME_SIZE);
        outFields->hiddenVolumeSize    = readHeaderBE64(decH, VC_HDR_OFF_HIDDEN_VOL_SIZE);
        outFields->encryptedAreaStart  = readHeaderBE64(decH, VC_HDR_OFF_KEY_SCOPE_START);
        outFields->encryptedAreaLength = readHeaderBE64(decH, VC_HDR_OFF_KEY_SCOPE_SIZE);
        outFields->sectorSize          = readHeaderBE32(decH, VC_HDR_OFF_SECTOR_SIZE);
    }

    return true;
}

// VeraCrypt's Argon2id header KDF always emits 192 bytes.  Argon2 output is
// length-sensitive, so deriving only a cascade's first 64/128 bytes would not
// match an official VeraCrypt volume.
static bool deriveHeaderKey(HashId hash,
                            const unsigned char* password, size_t passwordLen,
                            const unsigned char* salt, int clampedPim,
                            unsigned char* out, size_t outLen) {
    if (hash == HashId::kArgon2id) {
        if (outLen != 192) return false;
        uint32_t memoryKiB = 0;
        uint32_t timeCost = 0;
        uint32_t parallelism = 0;
        argon2ParamsForPim(clampedPim, memoryKiB, timeCost, parallelism);
        return argon2idDeriveKey(password, passwordLen, salt, VC_SALT_SIZE,
                                 memoryKiB, timeCost, parallelism, out, outLen);
    }
    return pbkdf2Hmac(hash, password, passwordLen, salt, VC_SALT_SIZE,
                       iterationsForHash(hash, clampedPim), out, outLen);
}

std::mutex derivationMutexes[MAX_VOLUMES];
static bool deriveAndValidateHeader(
    const unsigned char headerSector[VC_FULL_HEADER_SIZE],
    const unsigned char* password, size_t passwordLen, int pim,
    int cipherIdParam, int hashIdParam,
    unsigned char outKeyMaterial[192],
    unsigned char outDecryptedHeader[VC_HEADER_BODY_SIZE], // Out parameter filled with the decrypted header body on success.
    CascadeId& outMatchedCipher,
    HashId& outMatchedHash,
    ParsedHeaderFields& outFields,
    int volId = -1

) {
    const auto timingStart = std::chrono::steady_clock::now();
    const unsigned char* salt = headerSector;
    const unsigned char* encH = headerSector + VC_SALT_SIZE;
    const int safePim = clampPim(pim);

    std::vector<HashId> hashesToTry;
    if (hashIdParam != 255) {
        hashesToTry.push_back(static_cast<HashId>(hashIdParam));
    } else {
        hashesToTry = { HashId::kSha512, HashId::kSha256, HashId::kWhirlpool,
                        HashId::kStreebog, HashId::kBlake2s256, HashId::kArgon2id };
    }

    std::vector<CascadeId> ciphersToTry;
    if (cipherIdParam != 255) {
        ciphersToTry.push_back(static_cast<CascadeId>(cipherIdParam));
    } else {
        ciphersToTry = {
            CascadeId::kAes,
            CascadeId::kSerpent,
            CascadeId::kTwofish,
            CascadeId::kAesTwofish,
            CascadeId::kSerpentAes,
            CascadeId::kTwofishSerpent,
            CascadeId::kAesTwofishSerpent,
            CascadeId::kSerpentTwofishAes,
            CascadeId::kCamellia,
            CascadeId::kKuznyechik,
            CascadeId::kCamelliaKuznyechik,
            CascadeId::kCamelliaSerpent,
            CascadeId::kKuznyechikAes,
            CascadeId::kKuznyechikSerpentCamellia,
            CascadeId::kKuznyechikTwofish,
        };
    }
    const int totalHashSteps = static_cast<int>(hashesToTry.size());

    if (isUnlockCancelled(volId)) return false;

    // Optimistic check: try a 64-byte Fast Path (AES + SHA-512) directly to avoid trying all combinations if default is used.
    if (cipherIdParam == 255 && hashIdParam == 255) {
        reportUnlockProgress(volId, 0, totalHashSteps,
                              static_cast<int>(HashId::kSha512), static_cast<int>(CascadeId::kAes));
        const int fastIter = iterationsForHash(HashId::kSha512, safePim);
        
        unsigned char fastKey[64]; 
        if (pbkdf2Hmac(HashId::kSha512, password, passwordLen,
                        salt, VC_SALT_SIZE, fastIter, fastKey, 64)) {
            unsigned char decH[VC_HEADER_BODY_SIZE];
            ParsedHeaderFields fastFields;
            if (tryDecryptHeader(encH, CascadeId::kAes, fastKey, decH, &fastFields)) {
                std::memcpy(outKeyMaterial, &decH[VC_KEY_OFFSET_MASTER], 64);
                std::memcpy(outDecryptedHeader, decH, VC_HEADER_BODY_SIZE);
                outMatchedCipher = CascadeId::kAes;
                outMatchedHash   = HashId::kSha512;
                outFields        = fastFields;
                mbedtls_platform_zeroize(decH, sizeof(decH));
                mbedtls_platform_zeroize(fastKey, sizeof(fastKey));
                return true;
            }
            mbedtls_platform_zeroize(decH, sizeof(decH));
        }
        mbedtls_platform_zeroize(fastKey, sizeof(fastKey));
        
    }

    if (isUnlockCancelled(volId)) return false;

    std::atomic<bool> found{false};
    std::atomic<int> combinationsAttempted{0};
    std::mutex resultMutex;
    unsigned char resultKeyMaterial[192] = {0};
    CascadeId resultCipher{};
    HashId resultHash{};
    ParsedHeaderFields resultFields;

    int maxLayersToTry = 1;
    for (CascadeId c : ciphersToTry) {
        maxLayersToTry = std::max(maxLayersToTry, cascadeSpecFor(c).layerCount);
    }
    const size_t neededKeyBytes = static_cast<size_t>(maxLayersToTry) * 64;

    auto worker = [&](HashId h) {
        if (found.load(std::memory_order_acquire) || isUnlockCancelled(volId)) return;

        unsigned char derivedKeyMaterial[192] = {0};

        // Argon2id's 192-byte header key is intentionally derived in full;
        // PBKDF2 only needs the longest selected cascade's key material.
        const size_t outputBytes = h == HashId::kArgon2id ? 192 : neededKeyBytes;
        if (!deriveHeaderKey(h, password, passwordLen, salt, safePim,
                             derivedKeyMaterial, outputBytes)) {
            reportUnlockProgress(volId, combinationsAttempted.fetch_add(1) + 1, totalHashSteps,
                                 static_cast<int>(h), -1);
            return;
        }

        if (found.load(std::memory_order_acquire) || isUnlockCancelled(volId)) {
            mbedtls_platform_zeroize(derivedKeyMaterial, sizeof(derivedKeyMaterial));
            return;
        }

        unsigned char decH[VC_HEADER_BODY_SIZE];
        int lastCipherTried = -1;
        for (CascadeId c : ciphersToTry) {
            if (found.load(std::memory_order_acquire) || isUnlockCancelled(volId)) break;
            lastCipherTried = static_cast<int>(c);
            ParsedHeaderFields candidateFields;
            if (tryDecryptHeader(encH, c, derivedKeyMaterial, decH, &candidateFields)) {
                bool expected = false;
                if (found.compare_exchange_strong(expected, true, std::memory_order_acq_rel)) {
                    std::lock_guard<std::mutex> lock(resultMutex);
                    std::memcpy(resultKeyMaterial, derivedKeyMaterial, 192); 
                    std::memcpy(outDecryptedHeader, decH, VC_HEADER_BODY_SIZE);
                    resultCipher = c;
                    resultHash = h;
                    resultFields = candidateFields;
                }
                mbedtls_platform_zeroize(decH, sizeof(decH));
                mbedtls_platform_zeroize(derivedKeyMaterial, sizeof(derivedKeyMaterial));
                reportUnlockProgress(volId, combinationsAttempted.fetch_add(1) + 1, totalHashSteps,
                                     static_cast<int>(h), lastCipherTried);
                return;
            }
        }
        mbedtls_platform_zeroize(derivedKeyMaterial, sizeof(derivedKeyMaterial));
        reportUnlockProgress(volId, combinationsAttempted.fetch_add(1) + 1, totalHashSteps,
                             static_cast<int>(h), lastCipherTried);
    };

    if (hashesToTry.size() <= 1) {
        worker(hashesToTry[0]);
    } else {
        std::vector<std::thread> threads;
        threads.reserve(hashesToTry.size());
        for (HashId h : hashesToTry) threads.emplace_back(worker, h);
        for (auto& t : threads) t.join();
    }

    if (!found.load(std::memory_order_acquire)) {
        if (isUnlockCancelled(volId)) {
            LOGI("deriveAndValidateHeader: cancelled after %lld ms (vol=%d)", elapsedMs(timingStart), volId);
        } else {
            LOGI("deriveAndValidateHeader: failed after %lld ms (cipher=%d hash=%d)",
                 elapsedMs(timingStart), cipherIdParam, hashIdParam);
        }
        return false;
    }

    std::memcpy(outKeyMaterial, resultKeyMaterial, sizeof(resultKeyMaterial));
    outMatchedCipher = resultCipher;
    outMatchedHash = resultHash;
    outFields = resultFields;
    mbedtls_platform_zeroize(resultKeyMaterial, sizeof(resultKeyMaterial));
    LOGI("deriveAndValidateHeader: success in %lld ms (cipher=%d hash=%d hidden=%d)",
         elapsedMs(timingStart), static_cast<int>(resultCipher), static_cast<int>(resultHash),
         resultFields.isHiddenVolume() ? 1 : 0);
    return true;
}

static bool prepareLuksSession(int fd, const unsigned char* password, size_t passwordLen, int volId,
                                const unsigned char* preservedKey, size_t preservedKeyLen,
                                const int* keyfileFds, int keyfileCount) {
    if (volId < 0 || volId >= MAX_VOLUMES) { if (fd >= 0) close(fd); closeUnusedKeyfileFds(keyfileFds, keyfileCount); return false; }
    if (fd < 0) { closeUnusedKeyfileFds(keyfileFds, keyfileCount); return false; }

    VolumeState& v = volumes[volId];

    // ── Passphrase resolution. Real LUKS (cryptsetup) treats a keyfile as a
    // *replacement* for the typed passphrase, not an additive mix-in the way
    // VeraCrypt's keyfile pool works here — a keyslot is unlocked by EITHER
    // a password OR a keyfile, never both combined. If a keyfile is
    // attached, its raw bytes become the passphrase and the typed password
    // is ignored, matching `cryptsetup --key-file`. Only the first attached
    // keyfile is used. ──
    std::vector<unsigned char> keyfileBuf;
    const unsigned char* effectivePassword = password;
    size_t effectivePasswordLen = passwordLen;

    if (keyfileCount > 0 && keyfileFds != nullptr && keyfileFds[0] >= 0) {
        constexpr size_t kMaxKeyfileBytes = 1024 * 1024;
        keyfileBuf.resize(kMaxKeyfileBytes);
        ssize_t total = 0, n;
        while (total < static_cast<ssize_t>(kMaxKeyfileBytes) &&
               (n = read(keyfileFds[0], keyfileBuf.data() + total, kMaxKeyfileBytes - total)) > 0) {
            total += n;
        }
        keyfileBuf.resize(total > 0 ? total : 0);
        closeUnusedKeyfileFds(keyfileFds, keyfileCount);
        if (keyfileBuf.empty()) {
            LOGI("prepareLuksSession(vol=%d): keyfile unreadable or empty", volId);
            close(fd);
            return false;
        }
        effectivePassword = keyfileBuf.data();
        effectivePasswordLen = keyfileBuf.size();
    } else {
        closeUnusedKeyfileFds(keyfileFds, keyfileCount);
    }

    uint64_t fileSize = 0;
    struct stat st;
    if (fstat(fd, &st) == 0) fileSize = static_cast<uint64_t>(st.st_size);

    LuksVolumeInfo luksInfo;

    auto cancelCheck = [volId](int) -> bool {
        return isUnlockCancelled(volId);
    };
    auto progressCb = [volId](int step, int total, int hashId, int cipherId) {
        int format = (cipherId == 1) ? 2 : 1; // 1 = FMT_LUKS1, 2 = FMT_LUKS2
        reportUnlockProgress(volId, step, total, hashId, 0, format);
    };

    const bool usingPreservedKey = (preservedKey != nullptr && preservedKeyLen > 0);
    if (!luksRecoverMasterKey(fd,
                              usingPreservedKey ? nullptr : effectivePassword,
                              usingPreservedKey ? 0 : effectivePasswordLen,
                              luksInfo, volId, cancelCheck, progressCb,
                              usingPreservedKey ? preservedKey : nullptr,
                              usingPreservedKey ? preservedKeyLen : 0)) {
        close(fd);
        if (!keyfileBuf.empty()) mbedtls_platform_zeroize(keyfileBuf.data(), keyfileBuf.size());
        return false;
    }

    // Only xts-plain64 is implemented on the sector-crypto side below —
    // refuse rather than silently mounting something we'd decrypt wrong.
    if (luksInfo.cipherMode.rfind("xts-plain64", 0) != 0) {
        LOGI("prepareLuksSession(vol=%d): unsupported cipher mode '%s'", volId, luksInfo.cipherMode.c_str());
        mbedtls_platform_zeroize(luksInfo.masterKey.data(), luksInfo.masterKey.size());
        if (!keyfileBuf.empty()) mbedtls_platform_zeroize(keyfileBuf.data(), keyfileBuf.size());
        close(fd);
        return false;
    }

    // mappedCipher stays the app's existing 0/1/2 (aes/serpent/twofish)
    // convention for matchedCipherId — unrelated to CascadeId's ordinals,
    // and kept exactly as before so any stored records / UI reading this
    // field keep behaving the same.
    int mappedCipher = 0; // aes
    if (luksInfo.cipherName == "serpent") mappedCipher = 1;
    else if (luksInfo.cipherName == "twofish") mappedCipher = 2;
    else if (luksInfo.cipherName != "aes") {
        LOGI("prepareLuksSession(vol=%d): unsupported cipher '%s'", volId, luksInfo.cipherName.c_str());
        mbedtls_platform_zeroize(luksInfo.masterKey.data(), luksInfo.masterKey.size());
        if (!keyfileBuf.empty()) mbedtls_platform_zeroize(keyfileBuf.data(), keyfileBuf.size());
        close(fd);
        return false;
    }
    int mappedHash = 0; // kSha512, display-only for LUKS

    // Cipher dispatch: AES gets mbedTLS's accelerated XTS directly (as
    // before); Serpent/Twofish — the other ciphers cryptsetup commonly
    // pairs with xts-plain64 — go through the same single-layer
    // CascadeContext machinery the VeraCrypt cascade path already uses,
    // via cascadeSetKeys(..., CascadeId::kSerpent/kTwofish, ...).
    const bool isGenericCipher = (mappedCipher != 0);
    const CascadeId genericCascadeId = (mappedCipher == 1) ? CascadeId::kSerpent : CascadeId::kTwofish;
    CascadeContext genericCascade;

    bool keySetupOk;
    if (!isGenericCipher) {
        const size_t xtsKeyBits = luksInfo.keyBytes * 8;
        keySetupOk = (mbedtls_aes_xts_setkey_dec(&v.luksXts.dec, luksInfo.masterKey.data(), xtsKeyBits) == 0 &&
                      mbedtls_aes_xts_setkey_enc(&v.luksXts.enc, luksInfo.masterKey.data(), xtsKeyBits) == 0);
    } else {
        CascadeSpec spec = cascadeSpecFor(genericCascadeId);
        if (spec.layerCount != 1 || luksInfo.masterKey.size() != static_cast<size_t>(spec.layerCount) * 64) {
            LOGI("prepareLuksSession(vol=%d): unsupported key size for %s (need %zu bytes, got %zu)",
                 volId, luksInfo.cipherName.c_str(), static_cast<size_t>(spec.layerCount) * 64,
                 luksInfo.masterKey.size());
            keySetupOk = false;
        } else {
            keySetupOk = cascadeSetKeys(genericCascade, genericCascadeId,
                                         luksInfo.masterKey.data(), luksInfo.masterKey.size());
        }
    }
    if (!keySetupOk) {
        mbedtls_platform_zeroize(luksInfo.masterKey.data(), luksInfo.masterKey.size());
        if (!keyfileBuf.empty()) mbedtls_platform_zeroize(keyfileBuf.data(), keyfileBuf.size());
        close(fd);
        return false;
    }

    {
        std::lock_guard<std::mutex> lock(v.mutex);
        v.fd = fd;
        v.dataOffset = luksInfo.dataOffsetBytes;
        v.dataAreaLengthBytes = fileSize - luksInfo.dataOffsetBytes;
        v.isHiddenVolume = false;
        v.fileSize = fileSize;
        v.matchedCipherId = mappedCipher;
        v.matchedHashId = mappedHash;
        v.luksSectorSize = (luksInfo.dataSectorSize >= 512) ? luksInfo.dataSectorSize : 512;
        v.luksUsesGenericCipher = isGenericCipher;
        if (luksInfo.version == 1) {
            // LUKS1: cryptsetup sets dm-crypt's iv_offset = payload_offset, so
            // the XTS tweak counter is the ABSOLUTE physical sector from the
            // start of the container (there's no segment/iv_tweak concept).
            v.partitionStartSector = 0;
        } else {
            // LUKS2: the segment's "iv_tweak" (default 0) is added to a
            // counter that starts at 0 at the FIRST sector of the segment
            // itself (segment-relative), not the start of the file. Folding
            // both the segment offset and iv_tweak into partitionStartSector
            // lets disk_read/disk_write's existing
            // "physSector - partitionStartSector" arithmetic land on the
            // correct dm-crypt sector value:
            //   (physSector - segmentStartSector) / sectorsPerUnit + ivTweak
            const uint64_t segmentStartSector = luksInfo.dataOffsetBytes / 512;
            const uint64_t sectorsPerUnit = v.luksSectorSize / 512;
            v.partitionStartSector = segmentStartSector - (luksInfo.ivTweak * sectorsPerUnit);
        }
        v.containerFormat = luksInfo.version == 1
            ? ContainerFormat::kLuks1 : ContainerFormat::kLuks2;
        if (isGenericCipher) {
            v.luksGenericCascade = genericCascade;
            v.luksXts.initialized = false;
        } else {
            v.luksXts.initialized = true;
            v.luksGenericCascade.initialized = false;
        }
        v.dataCtxInitialized = true;

        // Cache the recovered master key for quick-unlock — same
        // preservedDerivedKey slot VeraCrypt uses, read by
        // getLastDerivedKeyMaterialNative() and reused via
        // luksRecoverMasterKey's candidateMasterKey fast path above.
        if (v.preservedDerivedKey) delete[] v.preservedDerivedKey;
        v.preservedDerivedKey = new unsigned char[luksInfo.masterKey.size()];
        memcpy(v.preservedDerivedKey, luksInfo.masterKey.data(), luksInfo.masterKey.size());
        v.preservedDerivedKeyLen = luksInfo.masterKey.size();
    }

    mbedtls_platform_zeroize(luksInfo.masterKey.data(), luksInfo.masterKey.size());
    if (!keyfileBuf.empty()) mbedtls_platform_zeroize(keyfileBuf.data(), keyfileBuf.size());

    LOGI("prepareLuksSession(vol=%d): LUKS%d unlocked, cipher=%s, dataOffset=%llu, keyBytes=%u, "
         "sectorSize=%u, ivTweak=%llu, partitionStartSector=%llu, cachedKey=%d",
         volId, luksInfo.version, luksInfo.cipherName.c_str(),
         (unsigned long long)luksInfo.dataOffsetBytes, luksInfo.keyBytes,
         v.luksSectorSize, (unsigned long long)luksInfo.ivTweak,
         (unsigned long long)v.partitionStartSector, usingPreservedKey ? 1 : 0);
    return true;
}

bool prepareSession(int fd, const unsigned char* password, size_t passwordLen, int pim, int volId, bool forceDerive, int cipherId, int hashId, const unsigned char* preservedKey = nullptr, size_t preservedKeyLen = 0, const int* keyfileFds = nullptr, int keyfileCount = 0) {
    const auto opStart = std::chrono::steady_clock::now();
    if (volId < 0 || volId >= MAX_VOLUMES) { if (fd >= 0) close(fd); closeUnusedKeyfileFds(keyfileFds, keyfileCount); return false; }
    VolumeState& v = volumes[volId];

    if (!forceDerive) {
        std::lock_guard<std::mutex> lock(v.mutex);
        if (v.dataCtxInitialized && v.fd >= 0) { if (fd >= 0) close(fd); closeUnusedKeyfileFds(keyfileFds, keyfileCount); return true; }
    }
    if (fd < 0) { closeUnusedKeyfileFds(keyfileFds, keyfileCount); return false; }

    std::lock_guard<std::mutex> derivationLock(derivationMutexes[volId]);
    
    uint64_t fileSize = 0;
    struct stat st;
    if (fstat(fd, &st) == 0) fileSize = static_cast<uint64_t>(st.st_size);

    // ── LUKS detection ────────────────────────────────────────────────────
    {
        unsigned char magicBuf[6];
        if (pread(fd, magicBuf, 6, 0) == 6 && isLuksContainer(magicBuf, 6)) {
            return prepareLuksSession(fd, password, passwordLen, volId,
                                       preservedKey, preservedKeyLen,
                                       keyfileFds, keyfileCount);
        }
    }

    struct HeaderSlot { uint64_t fileOffset; };
    static constexpr HeaderSlot kHeaderSlots[] = { { 0 }, { VC_HIDDEN_HEADER_OFFSET } };

    unsigned char dKey[192];           // PBKDF2 result (Key to Header)
    unsigned char decH[VC_HEADER_BODY_SIZE]; // Decrypted Header Body
    CascadeId matchedCipher{};
    HashId matchedHash{};
    ParsedHeaderFields fields;
    bool matched = false;

    unsigned char mixedPassword[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize mixedPasswordGuard(mixedPassword, sizeof(mixedPassword));
    size_t mixedPasswordLen = 0;
    const bool usingPreservedKey = (preservedKey != nullptr && preservedKeyLen > 0);
    if (!usingPreservedKey) {
        mixedPasswordLen = std::min(passwordLen, sizeof(mixedPassword));
        memcpy(mixedPassword, password, mixedPasswordLen);
        if (keyfileCount > 0 && !applyKeyfilesToPassword(keyfileFds, keyfileCount, mixedPassword, &mixedPasswordLen)) {
            LOGI("prepareSession(vol=%d): keyfile mixing failed (unreadable/empty keyfile)", volId);
            close(fd);
            return false;
        }
    } else {
        closeUnusedKeyfileFds(keyfileFds, keyfileCount);
    }

    for (const auto& slot : kHeaderSlots) {
        unsigned char headerSector[VC_FULL_HEADER_SIZE];
        if (pread(fd, headerSector, VC_FULL_HEADER_SIZE, static_cast<off_t>(slot.fileOffset)) != VC_FULL_HEADER_SIZE) continue;

        if (usingPreservedKey) {
            CascadeId candidateCipher = (cipherId != 255) ? static_cast<CascadeId>(cipherId) : CascadeId::kAes;
            unsigned char candidateKey[192];
            memset(candidateKey, 0, 192);
            memcpy(candidateKey, preservedKey, std::min(preservedKeyLen, (size_t)192));

            if (tryDecryptHeader(headerSector + VC_SALT_SIZE, candidateCipher, candidateKey, decH, &fields)) {
                memcpy(dKey, candidateKey, 192);
                matchedCipher = candidateCipher;
                matchedHash = (hashId != 255) ? static_cast<HashId>(hashId) : HashId::kSha512;
                matched = true;
                break;
            }
        } else {
            if (deriveAndValidateHeader(headerSector, mixedPassword, mixedPasswordLen, pim, cipherId, hashId, dKey, decH, matchedCipher, matchedHash, fields, volId)) {
                matched = true;
                break;
            }
        }
    }

    if (!matched) { close(fd); return false; }


    CascadeContext candidateCascade;
    CascadeSpec spec = cascadeSpecFor(matchedCipher);
    const unsigned char* masterKeyPtr = &decH[VC_KEY_OFFSET_MASTER]; 


    if (!cascadeSetKeys(candidateCascade, matchedCipher, masterKeyPtr, spec.layerCount * 64)) {
        close(fd); return false;
    }

    {
        std::lock_guard<std::mutex> lock(v.mutex);
        if (v.preservedDerivedKey) delete[] v.preservedDerivedKey;
        v.preservedDerivedKey = new unsigned char[192];
        memcpy(v.preservedDerivedKey, dKey, 192); // Store PBKDF2 for future "preserved" unlocks
        v.preservedDerivedKeyLen = 192;

        v.cascade = candidateCascade;
        v.dataCtxInitialized = true;
        v.fd = fd;
        v.dataOffset = fields.encryptedAreaStart;
        v.dataAreaLengthBytes = fields.encryptedAreaLength;
        v.isHiddenVolume = fields.isHiddenVolume();
        v.fileSize = fileSize;
        v.matchedCipherId = (int)matchedCipher;
        v.matchedHashId = (int)matchedHash;
        v.partitionStartSector = 0; // For files, absolute tweak = physical sector
    }
    return true;
}


static bool prepareUsbSession(const unsigned char* password, size_t passwordLen, int pim, int volId, int cipherId, int hashId, const unsigned char* preservedKey = nullptr, size_t preservedKeyLen = 0, int64_t partitionOffsetHint = -1, const int* keyfileFds = nullptr, int keyfileCount = 0) {
    if (volId < 0 || volId >= MAX_VOLUMES) { closeUnusedKeyfileFds(keyfileFds, keyfileCount); return false; }
    VolumeState& v = volumes[volId];
    std::lock_guard<std::mutex> derivationLock(derivationMutexes[volId]);
    {
        std::lock_guard<std::mutex> lock(v.mutex);
        if (v.dataCtxInitialized && v.isUsbSource) {
            LOGI("prepareUsbSession(vol=%d): session prepared by another thread", volId);
            closeUnusedKeyfileFds(keyfileFds, keyfileCount);
            return true;
        }
    }

    unsigned char mixedPassword[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize mixedPasswordGuard(mixedPassword, sizeof(mixedPassword));
    size_t mixedPasswordLen = 0;
    const bool usingPreservedKey = (preservedKey != nullptr && preservedKeyLen > 0);
    if (!usingPreservedKey) {
        mixedPasswordLen = std::min(passwordLen, sizeof(mixedPassword));
        memcpy(mixedPassword, password, mixedPasswordLen);
        if (keyfileCount > 0 && !applyKeyfilesToPassword(keyfileFds, keyfileCount, mixedPassword, &mixedPasswordLen)) {
            LOGI("prepareUsbSession(vol=%d): keyfile mixing failed (unreadable/empty keyfile)", volId);
            return false;
        }
    } else {
        closeUnusedKeyfileFds(keyfileFds, keyfileCount);
    }

    std::vector<PartitionCandidate> partitions;

    std::unique_ptr<unsigned char[]> diskBuf(new unsigned char[34 * 512]);
    if (usbReadSectors(volId, 0, 34, diskBuf.get())) {
        const unsigned char* sector0 = diskBuf.get();
        const unsigned char* sector1 = diskBuf.get() + 512;
        const unsigned char* gptEntries = diskBuf.get() + 1024;

        if (sector0[510] == 0x55 && sector0[511] == 0xAA) {
            bool isGpt = false;
            
            for (int i = 0; i < 4; i++) {
                const unsigned char* entry = &sector0[446 + i * 16];
                uint8_t type = entry[4];
                if (type == 0xEE) {
                    isGpt = true;
                    break;
                }
                uint32_t startLba = readUint32LE(&entry[8]);
                uint32_t numSectors = readUint32LE(&entry[12]);
                if (startLba > 0 && numSectors > 0) {
                    partitions.push_back({startLba, numSectors});
                }
            }

            if (isGpt && memcmp(sector1, "EFI PART", 8) == 0) {
                uint32_t numEntries = readUint32LE(&sector1[80]);
                uint32_t entrySize = readUint32LE(&sector1[84]);
                
                if (entrySize >= 128 && numEntries <= 128) {
                    for (uint32_t i = 0; i < numEntries; i++) {
                        const unsigned char* entry = gptEntries + (i * entrySize);
                        
                        bool unused = true;
                        for (int g = 0; g < 16; g++) {
                            if (entry[g] != 0) { unused = false; break; }
                        }
                        if (unused) continue;

                        uint64_t startLba = readUint64LE(&entry[32]);
                        uint64_t endLba = readUint64LE(&entry[40]);
                        if (startLba > 0 && endLba >= startLba) {
                            partitions.push_back({startLba, endLba - startLba + 1});
                        }
                    }
                }
            }
        }
    }

    partitions.push_back({0, 0});

    if (partitionOffsetHint >= 0) {
        const uint64_t hint = static_cast<uint64_t>(partitionOffsetHint);
        auto hintIt = std::find_if(partitions.begin(), partitions.end(),
            [hint](const PartitionCandidate& p) { return p.startSector == hint; });
        if (hintIt != partitions.end()) {
            std::iter_swap(partitions.begin(), hintIt);
        } else {
            partitions.insert(partitions.begin(), {hint, 0});
        }
    }

    struct HeaderSlot { uint64_t sectorOffset; };
    static constexpr HeaderSlot kHeaderSlots[] = {
        { 0 },
        { VC_HIDDEN_HEADER_OFFSET / 512 },
    };

    bool fsFound = false;
    uint64_t foundDataOffset = 0;
    uint64_t foundDataLength = 0;
    bool foundIsHidden = false;
    CascadeContext candidateCascade;
    uint64_t matchedPartitionStart = 0;
    CascadeId matchedCipherFound{};
    HashId matchedHashFound{};
    std::vector<unsigned char> derivedKeyBytes;

    for (const auto& part : partitions) {
        for (const auto& slot : kHeaderSlots) {
            const uint64_t headerSector = part.startSector + slot.sectorOffset;

            unsigned char dKey[192]{};
            unsigned char decH[VC_HEADER_BODY_SIZE]; // Holds the decrypted header fields on successful decryption.
            CascadeId matchedCipher{};
            HashId matchedHash{};
            ParsedHeaderFields fields;
            bool derivedSuccessfully = false;

            if (usingPreservedKey) {
                unsigned char headerBuf[VC_FULL_HEADER_SIZE];
                if (!usbReadSectors(volId, headerSector, 1, headerBuf)) continue;

                CascadeId candidateCipher = (cipherId != 255) ? static_cast<CascadeId>(cipherId) : CascadeId::kAes;
                const size_t bytesToCopy = std::min(preservedKeyLen, (size_t)192);
                memcpy(dKey, preservedKey, bytesToCopy);
                

                if (tryDecryptHeader(headerBuf + VC_SALT_SIZE, candidateCipher, dKey, decH, &fields)) {
                    matchedCipher = candidateCipher;
                    matchedHash = (hashId != 255) ? static_cast<HashId>(hashId) : HashId::kSha512;
                    derivedSuccessfully = true;
                }
            } else {
                unsigned char headerBuf[VC_FULL_HEADER_SIZE];
                if (!usbReadSectors(volId, headerSector, 1, headerBuf)) continue;


                derivedSuccessfully = deriveAndValidateHeader(headerBuf, mixedPassword, mixedPasswordLen, pim, cipherId, hashId,
                                         dKey, decH, matchedCipher, matchedHash, fields, volId);
            }

            if (!derivedSuccessfully) {
                mbedtls_platform_zeroize(dKey, sizeof(dKey));
                continue;
            }

            // Extract Master Key from decH
            CascadeSpec spec = cascadeSpecFor(matchedCipher);
            const unsigned char* masterKeyPtr = &decH[VC_KEY_OFFSET_MASTER]; // Point to the master key material inside the decrypted header body.
            
            if (!cascadeSetKeys(candidateCascade, matchedCipher, masterKeyPtr, spec.layerCount * 64)) {
                mbedtls_platform_zeroize(dKey, sizeof(dKey));
                continue;
            }

            fsFound = true;
            foundDataOffset = part.startSector * 512 + fields.encryptedAreaStart;
            foundDataLength = fields.encryptedAreaLength;
            foundIsHidden   = fields.isHiddenVolume();
            matchedPartitionStart = part.startSector;
            matchedCipherFound = matchedCipher;
            matchedHashFound = matchedHash;
            derivedKeyBytes.assign(dKey, dKey + sizeof(dKey));
            mbedtls_platform_zeroize(dKey, sizeof(dKey));
            break;
        }
        if (fsFound) break;
    }

    if (!fsFound) {
        return false;
    }

    {
        std::lock_guard<std::mutex> lock(v.mutex);
        if (preservedKey == nullptr || preservedKeyLen == 0) {
            if (v.preservedDerivedKey != nullptr) {
                mbedtls_platform_zeroize(v.preservedDerivedKey, v.preservedDerivedKeyLen);
                delete[] v.preservedDerivedKey;
            }
            v.preservedDerivedKey = new unsigned char[derivedKeyBytes.size()];
            std::memcpy(v.preservedDerivedKey, derivedKeyBytes.data(), derivedKeyBytes.size());
            v.preservedDerivedKeyLen = derivedKeyBytes.size();
        }
        v.cascade = candidateCascade;
        v.isUsbSource          = true;
        v.dataCtxInitialized   = true;
        v.fd                   = -1;
        v.dataOffset           = foundDataOffset;
        v.dataAreaLengthBytes  = foundDataLength;
        v.isHiddenVolume       = foundIsHidden;
        v.partitionStartSector = matchedPartitionStart;
        v.matchedCipherId      = static_cast<int>(matchedCipherFound);
        v.matchedHashId        = static_cast<int>(matchedHashFound);
    }
    return true;
}

// ----------------------------------------------------------------====
// SHARED: Directory listing
// ----------------------------------------------------------------====

static jobjectArray buildDirectoryListing(JNIEnv* env, int volId, const char* pathSuffix) {
    std::vector<std::string> results;
    auto& v = volumes[volId];

    if (v.fsType == VolumeState::FS_FATFS) {
        std::string fullPath = drivePaths[volId];
        if (pathSuffix && pathSuffix[0] != '\0') {
            fullPath += '/';
            fullPath += pathSuffix;
        }
        DIR dir;
        FILINFO fno;
        if (f_opendir(&dir, fullPath.c_str()) == FR_OK) {
            while (f_readdir(&dir, &fno) == FR_OK && fno.fname[0]) {
                if (results.size() >= MAX_DIR_ENTRIES) {
                    results.push_back("System:TRUNCATED");
                    break;
                }
                const char* name = fno.fname;
                if (strcmp(name, "SYSTEM~1") == 0 || strcmp(name, "$RECYCLE.BIN") == 0) continue;

                const uint64_t ts = fatToUnixTimestamp(fno.fdate, fno.ftime);
                if (fno.fattrib & AM_DIR) {
                    results.push_back("[DIR] " + std::string(name) + "|0|" + std::to_string(ts));
                } else {
                    results.push_back(std::string(name) + "|" + std::to_string(fno.fsize) + "|" + std::to_string(ts));
                }
            }
            f_closedir(&dir);
        }
    } else if (v.fsType == VolumeState::FS_NTFS) {
        ntfs_inode* dir_ni = nullptr;
        if (!pathSuffix || pathSuffix[0] == '\0' || std::strcmp(pathSuffix, "/") == 0) {
            dir_ni = ntfs_inode_open(v.ntfsVol, FILE_root);
        } else {
            std::string fullPath = "/" + std::string(pathSuffix);
            dir_ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());
        }

        if (dir_ni) {
            s64 pos = 0;
            NtfsFilldirContext fillCtx = { &results, v.ntfsVol };
            ntfs_readdir(dir_ni, &pos, &fillCtx, vExplorer_ntfs_filldir);
            ntfs_inode_close(dir_ni);
        }
    } else if (v.fsType == VolumeState::FS_EXT) {
        ext2_ino_t dirInode = 0;
        if (extResolvePath(v.extFs, pathSuffix ? pathSuffix : "", &dirInode)) {
            struct ext2_inode dirNodeInfo{};
            const errcode_t readInodeErr = ext2fs_read_inode(v.extFs, dirInode, &dirNodeInfo);
            LOGI("buildDirectoryListing: ext dir inode=%u readInodeErr=%lu i_size=%u i_blocks=%u i_links_count=%u",
                 dirInode, (unsigned long)readInodeErr, dirNodeInfo.i_size,
                 dirNodeInfo.i_blocks, dirNodeInfo.i_links_count);
            ExtDirContext context{v.extFs, &results};
            const errcode_t iterErr = ext2fs_dir_iterate2(v.extFs, dirInode, 0, nullptr, extDirectoryEntry, &context);
            LOGI("buildDirectoryListing: ext2fs_dir_iterate2 return=%lu (%s) entries=%zu",
                 (unsigned long)iterErr, iterErr ? error_message(iterErr) : "OK", results.size());
            if (results.size() >= MAX_DIR_ENTRIES) results.push_back("System:TRUNCATED");
        }
    }

    jclass strClass = env->FindClass("java/lang/String");
    jobjectArray retArr = env->NewObjectArray(static_cast<jsize>(results.size()), strClass, nullptr);
    for (size_t i = 0; i < results.size(); i++) {
        sanitizeString(results[i]);
        jstring js = env->NewStringUTF(results[i].c_str());
        env->SetObjectArrayElement(retArr, i, js);
        env->DeleteLocalRef(js);
    }
    return retArr;
}

// ----------------------------------------------------------------====
// JNI API
// ----------------------------------------------------------------====
static std::vector<int> extractKeyfileFds(JNIEnv* env, jintArray arr) {
    std::vector<int> fds;
    if (!arr) return fds;
    jsize len = env->GetArrayLength(arr);
    if (len <= 0) return fds;
    jint* elems = env->GetIntArrayElements(arr, nullptr);
    if (!elems) return fds;
    fds.assign(elems, elems + len);
    env->ReleaseIntArrayElements(arr, elems, JNI_ABORT); // read-only access, nothing to copy back
    return fds;
}

static void throwUnlockCancelledException(JNIEnv* env) {
    jclass excClass = env->FindClass("com/aeidolon/vaultexplorer/UnlockCancelledException");
    if (excClass) env->ThrowNew(excClass, "CANCELLED");
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getMaxVolumesNative(JNIEnv*, jobject) {
    return static_cast<jint>(MAX_VOLUMES);
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getLastDerivedKeyMaterialNative(
        JNIEnv* env, jobject, jint volId) {
    if (volId < 0 || volId >= MAX_VOLUMES) return nullptr;

    VolumeState& v = volumes[volId];
    std::lock_guard<std::mutex> lock(v.mutex);
    if (v.preservedDerivedKey == nullptr || v.preservedDerivedKeyLen == 0) return nullptr;

    jbyteArray result = env->NewByteArray(static_cast<jsize>(v.preservedDerivedKeyLen));
    env->SetByteArrayRegion(result, 0, static_cast<jsize>(v.preservedDerivedKeyLen),
                            reinterpret_cast<const jbyte*>(v.preservedDerivedKey));
    return result;
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_deriveKeyMaterialNative(
        JNIEnv* env, jobject,
        jint fd, jstring password, jint pim, jint cipherId, jint hashId, jintArray keyfileFds) {
    if (fd < 0 || password == nullptr) return nullptr;

    std::vector<int> kfFds = extractKeyfileFds(env, keyfileFds);

    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    unsigned char headerBuf[VC_FULL_HEADER_SIZE];
    if (pread(fd, headerBuf, VC_FULL_HEADER_SIZE, 0) != VC_FULL_HEADER_SIZE) {
        env->ReleaseStringUTFChars(password, nativePass);
        closeUnusedKeyfileFds(kfFds.data(), static_cast<int>(kfFds.size()));
        return nullptr;
    }

    unsigned char mixedPassword[MAX_PASSWORD_LEN] = {0};
    ScopeZeroize mixedPasswordGuard(mixedPassword, sizeof(mixedPassword));
    size_t mixedPasswordLen = std::min(strlen(nativePass), sizeof(mixedPassword));
    memcpy(mixedPassword, nativePass, mixedPasswordLen);
    env->ReleaseStringUTFChars(password, nativePass);

    if (!kfFds.empty() && !applyKeyfilesToPassword(kfFds.data(), static_cast<int>(kfFds.size()), mixedPassword, &mixedPasswordLen)) {
        return nullptr;
    }

    unsigned char dKey[192];
    unsigned char dummyDecH[VC_HEADER_BODY_SIZE]; 
    CascadeId matchedCipher{};
    HashId matchedHash{};
    ParsedHeaderFields fields;

    const bool ok = deriveAndValidateHeader(
        headerBuf, 
        mixedPassword, 
        mixedPasswordLen, 
        pim, 
        cipherId, 
        hashId, 
        dKey, 
        dummyDecH, 
        matchedCipher, 
        matchedHash, 
        fields
    );

    if (!ok) return nullptr;

    jbyteArray result = env->NewByteArray(192);
    env->SetByteArrayRegion(result, 0, 192, reinterpret_cast<jbyte*>(dKey));
    mbedtls_platform_zeroize(dKey, sizeof(dKey));
    return result;
}

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_unlockAndListNative(
        JNIEnv* env, jobject, jint fd, jstring password, jint pim, jint volId, jint cipherId, jint hashId, jbyteArray preservedKey, jintArray keyfileFds) {

    if (volId >= 0 && volId < MAX_VOLUMES) {
        cancelRequested[volId].store(false, std::memory_order_release);
    }

    const unsigned char* preservedBytes = nullptr;
    size_t preservedLen = 0;
    if (preservedKey != nullptr) {
        preservedBytes = reinterpret_cast<const unsigned char*>(env->GetByteArrayElements(preservedKey, nullptr));
        preservedLen = static_cast<size_t>(env->GetArrayLength(preservedKey));
    }

    std::vector<int> kfFds = extractKeyfileFds(env, keyfileFds);
    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    
    if (!prepareSession(fd, reinterpret_cast<const unsigned char*>(nativePass), strlen(nativePass), pim, volId, true, cipherId, hashId, preservedBytes, preservedLen,
                         kfFds.empty() ? nullptr : kfFds.data(), static_cast<int>(kfFds.size()))) {
        if (preservedKey != nullptr) {
            env->ReleaseByteArrayElements(preservedKey, reinterpret_cast<jbyte*>(const_cast<unsigned char*>(preservedBytes)), JNI_ABORT);
        }
        env->ReleaseStringUTFChars(password, nativePass);
        if (isUnlockCancelled(volId)) throwUnlockCancelledException(env);
        return nullptr;
    }

    jobjectArray result = nullptr;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            result = buildDirectoryListing(env, volId, nullptr);
        } else {
            LOGI("FATFS/NTFS Mount failed on volume %d", volId);
        }
    }

    if (preservedKey != nullptr) {
        env->ReleaseByteArrayElements(preservedKey, reinterpret_cast<jbyte*>(const_cast<unsigned char*>(preservedBytes)), JNI_ABORT);
    }
    env->ReleaseStringUTFChars(password, nativePass);
    return result;
}

extern "C" JNIEXPORT void JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_requestCancelUnlockNative(
        JNIEnv*, jobject, jint volId) {
    if (volId >= 0 && volId < MAX_VOLUMES) {
        cancelRequested[volId].store(true, std::memory_order_release);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_lockNative(JNIEnv*, jobject, jint volId) {
    if (volId < 0 || volId >= MAX_VOLUMES) return;

    VolumeState& v = volumes[volId];
    std::lock_guard<std::mutex> lock(v.mutex);

    // Close FAT streams
    for (FIL* f : v.openStreams) {
        f_close(f);
        delete f;
    }
    v.openStreams.clear();

    // Close NTFS streams
    for (NtfsStream* ns : v.openNtfsStreams) {
        ntfs_attr_close(ns->attr);
        ntfs_inode_close(ns->inode);
        delete ns;
    }
    v.openNtfsStreams.clear();

    v.reset();

    unmountVolume(volId);  
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_createContainerNative(
        JNIEnv* env, jobject,
        jint fd, jstring password, jint pim, jlong sizeBytes, jstring fileSystem,
        jint cipherId, jint hashId) {

    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    const char* nativeFS   = env->GetStringUTFChars(fileSystem, nullptr);

    bool success = false;

    CascadeId createCipher = (cipherId != 255) ? static_cast<CascadeId>(cipherId) : CascadeId::kAes;
    HashId    createHash   = (hashId   != 255) ? static_cast<HashId>(hashId)      : HashId::kSha512;
    CascadeSpec cSpec      = cascadeSpecFor(createCipher);
    const int masterKeyLen = cSpec.layerCount * 64;

    unsigned char salt[VC_SALT_SIZE]   = {0};
    unsigned char combinedMasterKey[192] = {0};

    do {
        if (sizeBytes < static_cast<jlong>(300 * 1024)) {
            LOGI("createContainer: sizeBytes too small (%lld)", (long long)sizeBytes);
            break;
        }

        int volId = -1;
        {
            std::lock_guard<std::mutex> allocLock(slotAllocMutex);
            for (int i = 0; i < MAX_VOLUMES; i++) {
                if (!volumes[i].dataCtxInitialized) { volId = i; break; }
            }
        }
        if (volId == -1) {
            LOGI("createContainer: no free slots available");
            break;
        }
        VolumeState& v = volumes[volId];

        {
            FILE* urnd = fopen("/dev/urandom", "rb");
            if (!urnd) { LOGI("createContainer: cannot open /dev/urandom"); break; }
            bool ok = (fread(salt,              1, VC_SALT_SIZE, urnd) == VC_SALT_SIZE) &&
                      (fread(combinedMasterKey, 1, static_cast<size_t>(masterKeyLen), urnd) == static_cast<size_t>(masterKeyLen));
            fclose(urnd);
            if (!ok) { LOGI("createContainer: urandom read failed"); break; }
        }

        const int safePim = clampPim(pim);
        // Derive the complete 192-byte header key. This is mandatory for
        // Argon2id compatibility and harmless for PBKDF2-based headers.
        unsigned char headerKey[192] = {0};
        if (!deriveHeaderKey(createHash,
                             reinterpret_cast<const unsigned char*>(nativePass), strlen(nativePass),
                             salt, safePim, headerKey, sizeof(headerKey))) {
            LOGI("createContainer: header key derivation failed");
            break;
        }


        // Align to 4096 bytes
        const uint64_t VOLUME_SIZE = (static_cast<uint64_t>(sizeBytes) / 4096) * 4096;

        // Truncate file to exact aligned size
        if (static_cast<uint64_t>(sizeBytes) != VOLUME_SIZE) {
            if (ftruncate(fd, VOLUME_SIZE) != 0) {
                LOGI("DEBUG-Ext: ftruncate failed! errno=%d (%s)", errno, strerror(errno));
            } else {
                LOGI("DEBUG-Ext: Successfully truncated file to %llu", (unsigned long long)VOLUME_SIZE);
            }
        }

        // Verify physical file size matches using fstat
        struct stat st;
        if (fstat(fd, &st) == 0) {
            LOGI("DEBUG-Ext: Physical file size on disk: %lld", (long long)st.st_size);
            if (static_cast<uint64_t>(st.st_size) != VOLUME_SIZE) {
                LOGI("DEBUG-Ext: WARNING: Physical size does NOT match VOLUME_SIZE! Android SAF issue?");
            }
        } else {
            LOGI("DEBUG-Ext: fstat failed!");
        }

        const uint64_t DATA_SIZE = VOLUME_SIZE - (2 * VC_DATA_AREA_OFFSET);
        
        if (DATA_SIZE % 4096 != 0 || DATA_SIZE % 512 != 0) {
            LOGI("DEBUG-Ext: WARNING: DATA_SIZE is NOT aligned correctly!");
        }

        unsigned char body[VC_HEADER_BODY_SIZE];
        memset(body, 0, sizeof(body));

        body[0] = 'V'; body[1] = 'E'; body[2] = 'R'; body[3] = 'A';
        body[4] = 0x00; body[5] = 0x02;
        body[6] = 0x01; body[7] = 0x0b;

        // Note: For standard (non-hidden) volumes, the official VeraCrypt spec 
        // dictates that VC_HDR_OFF_VOLUME_SIZE holds the size of the decrypted 
        // payload area (DATA_SIZE), NOT the total physical container file size.
        for (int i = 7; i >= 0; --i)
            body[VC_HDR_OFF_VOLUME_SIZE + (7 - i)] = (DATA_SIZE >> (i * 8)) & 0xFF;
            
        for (int i = 7; i >= 0; --i)
            body[VC_HDR_OFF_KEY_SCOPE_START + (7 - i)] = (VC_DATA_AREA_OFFSET >> (i * 8)) & 0xFF;
            
        for (int i = 7; i >= 0; --i)
            body[VC_HDR_OFF_KEY_SCOPE_SIZE + (7 - i)] = (DATA_SIZE >> (i * 8)) & 0xFF;

        body[VC_HDR_OFF_SECTOR_SIZE]     = 0x00;
        body[VC_HDR_OFF_SECTOR_SIZE + 1] = 0x00;
        body[VC_HDR_OFF_SECTOR_SIZE + 2] = 0x02;
        body[VC_HDR_OFF_SECTOR_SIZE + 3] = 0x00;


        memcpy(&body[VC_KEY_OFFSET_MASTER], combinedMasterKey, masterKeyLen);

        uint32_t keyCrc = crc32(&body[VC_KEY_OFFSET_MASTER], VC_HDR_KEY_CRC_COVERAGE_LEN);
        body[VC_HDR_OFF_KEY_CRC]     = (keyCrc >> 24) & 0xFF;
        body[VC_HDR_OFF_KEY_CRC + 1] = (keyCrc >> 16) & 0xFF;
        body[VC_HDR_OFF_KEY_CRC + 2] = (keyCrc >>  8) & 0xFF;
        body[VC_HDR_OFF_KEY_CRC + 3] = (keyCrc      ) & 0xFF;

        uint32_t hdrCrc = crc32(body, VC_HDR_CRC_COVERAGE_LEN);
        body[VC_HDR_OFF_HEADER_CRC]     = (hdrCrc >> 24) & 0xFF;
        body[VC_HDR_OFF_HEADER_CRC + 1] = (hdrCrc >> 16) & 0xFF;
        body[VC_HDR_OFF_HEADER_CRC + 2] = (hdrCrc >>  8) & 0xFF;
        body[VC_HDR_OFF_HEADER_CRC + 3] = (hdrCrc      ) & 0xFF;

        unsigned char encBody[VC_HEADER_BODY_SIZE];
        {
            CascadeContext hdrCtx;
            if (!cascadeSetKeys(hdrCtx, createCipher, headerKey, masterKeyLen)) {
                LOGI("createContainer: cascadeSetKeys failed for header");
                break;
            }
            // Header is encrypted as a single "sector 0" with zero tweak
            // We need to handle the 448-byte body (28 blocks of 16 bytes)
            std::memcpy(encBody, body, VC_HEADER_BODY_SIZE);
            for (int layer = cSpec.layerCount - 1; layer >= 0; layer--) {
                const XtsLayerKey& lk = hdrCtx.layers[layer];
                unsigned char T[16] = {0};
                blockCipherEncryptBlock(lk.tweakKey, T, T);
                for (int blk = 0; blk < 28; blk++) {
                    unsigned char* bp = encBody + blk * 16;
                    unsigned char tmp[16];
                    for (int j = 0; j < 16; j++) tmp[j] = bp[j] ^ T[j];
                    blockCipherEncryptBlock(lk.dataKeyEnc, tmp, tmp);
                    for (int j = 0; j < 16; j++) bp[j] = tmp[j] ^ T[j];
                    localMultiplyTweak(T);
                }
            }
        }

        mbedtls_platform_zeroize(headerKey, sizeof(headerKey));
        mbedtls_platform_zeroize(body, sizeof(body));

        unsigned char hdrSector[VC_FULL_HEADER_SIZE];
        memcpy(hdrSector,                  salt,    VC_SALT_SIZE);
        memcpy(hdrSector + VC_SALT_SIZE,   encBody, VC_HEADER_BODY_SIZE);

        if (pwrite(fd, hdrSector, VC_FULL_HEADER_SIZE, 0) != VC_FULL_HEADER_SIZE) {
            LOGI("createContainer: primary header write failed"); break;
        }
        if (pwrite(fd, hdrSector, VC_FULL_HEADER_SIZE,
                   static_cast<off_t>(VOLUME_SIZE - VC_DATA_AREA_OFFSET)) != VC_FULL_HEADER_SIZE) {
            LOGI("createContainer: backup header write failed"); break;
        }
        if (pwrite(fd, hdrSector, VC_FULL_HEADER_SIZE,
                   static_cast<off_t>(VOLUME_SIZE - VC_DATA_AREA_OFFSET)) != VC_FULL_HEADER_SIZE) {
            LOGI("createContainer: backup header write failed"); break;
        }

        // --- NEW FIX START ---
        // Android SAF ignores ftruncate(). Because the backup header is only 512 bytes, 
        // there is a 130,560 byte gap at the end of the file that never gets written to.
        // We MUST force the OS to expand the file to the exact requested VOLUME_SIZE 
        // by writing a single byte at the very end of the file (VOLUME_SIZE - 1).
        unsigned char eofByte = 0;
        if (pwrite(fd, &eofByte, 1, static_cast<off_t>(VOLUME_SIZE - 1)) != 1) {
            LOGI("createContainer: failed to expand file to full VOLUME_SIZE");
        } else {
            LOGI("DEBUG-Ext: Successfully forced physical file size to %llu", (unsigned long long)VOLUME_SIZE);
        }
        // --- NEW FIX END ---

        {
            CascadeContext dataCtx;
            if (!cascadeSetKeys(dataCtx, createCipher, combinedMasterKey, masterKeyLen)) {
                LOGI("createContainer: cascadeSetKeys failed for data");
                break;
            }

            const uint64_t START_SECTOR  = VC_DATA_AREA_OFFSET / 512;
            const uint64_t TOTAL_SECTORS = (VOLUME_SIZE - VC_DATA_AREA_OFFSET) / 512;

            const unsigned char ZERO_SECTOR[512] = {0};
            const size_t batchBufBytes = CREATE_FILL_BATCH * 512;
            std::unique_ptr<unsigned char[]> batch(new unsigned char[batchBufBytes]);
            bool writeOk = true;

            for (uint64_t s = START_SECTOR; s < TOTAL_SECTORS && writeOk; ) {
                const uint64_t rem   = TOTAL_SECTORS - s;
                const uint64_t count = (rem < CREATE_FILL_BATCH) ? rem : CREATE_FILL_BATCH;

                for (uint64_t i = 0; i < count; ++i) {
                    cascadeEncryptSector(dataCtx, s + i, ZERO_SECTOR,
                                        batch.get() + i * 512);
                }

                const ssize_t want = static_cast<ssize_t>(count * 512);
                if (pwrite(fd, batch.get(), want,
                           static_cast<off_t>(s * 512)) != want) {
                    LOGI("createContainer: data fill write failed at sector %llu",
                         (unsigned long long)s);
                    writeOk = false;
                }
                s += count;
            }
            if (!writeOk) break;
        }

        fsync(fd);

        // Format drive
        {
            std::lock_guard<std::mutex> vlock(v.mutex);

            cascadeSetKeys(v.cascade, createCipher, combinedMasterKey, masterKeyLen);
            v.dataCtxInitialized = true;
            v.fd                 = fd;
            v.dataOffset         = VC_DATA_AREA_OFFSET;
            v.dataAreaLengthBytes = DATA_SIZE;
            v.fileSize           = VOLUME_SIZE;

            const bool useExFat = (strncasecmp(nativeFS, "exfat", 5) == 0);
            const bool useNtfs = (strncasecmp(nativeFS, "ntfs", 4) == 0);
            const bool useExt = strncasecmp(nativeFS, "ext2", 4) == 0 ||
                                strncasecmp(nativeFS, "ext3", 4) == 0 ||
                                strncasecmp(nativeFS, "ext4", 4) == 0;
            if (useExt) {
                // Prepare encryption context state
                v.partitionStartSector = 0;
                v.dataOffset = VC_DATA_AREA_OFFSET;
                v.dataAreaLengthBytes = DATA_SIZE;
                v.isUsbSource = false;
                
                // The keys were already set via cascadeSetKeys(v.cascade...) 
                // in the previous block.
                
                const bool formatted = formatExtVolume(volId, nativeFS);
                
                // Post-format cleanup
                v.fsMounted = false;
                v.fd = -1;
                v.dataCtxInitialized = false;

                if (!formatted) {
                    LOGI("createContainer: %s formatter failed", nativeFS);
                    break;
                }
                success = true;
                continue;
            }

            if (useNtfs) {
                char deviceName[16];
                std::snprintf(deviceName, sizeof(deviceName), "ve%d", volId);
                char* args[] = {
                    const_cast<char*>("mkntfs"), const_cast<char*>("-F"),
                    const_cast<char*>("-Q"), const_cast<char*>("-s"),
                    const_cast<char*>("512"), const_cast<char*>("-p"),
                    const_cast<char*>("0"), deviceName, nullptr
                };
                const int result = vaultexplorer_mkntfs_main(8, args);
                v.fsMounted = false;
                v.fsType = VolumeState::FS_UNKNOWN;
                v.fd = -1;
                v.dataOffset = 0;
                v.dataAreaLengthBytes = 0;
                v.fileSize = 0;
                v.cascade.initialized = false;
                v.dataCtxInitialized = false;
                if (result != 0) {
                    LOGI("createContainer: mkntfs failed, code=%d", result);
                    break;
                }
                success = true;
                continue;
            }

            MKFS_PARM mp;
            memset(&mp, 0, sizeof(mp));
            mp.fmt = (useExFat ? FM_EXFAT : (FM_FAT | FM_FAT32)) | FM_SFD;
            mp.n_fat  = 1;
            mp.n_root = 512;
            mp.au_size = 0;
            mp.align   = 0;

            alignas(16) unsigned char mkfsBuf[MKFS_WORK_BUF_SIZE];
            FRESULT fr = f_mkfs(drivePaths[volId], &mp, mkfsBuf, sizeof(mkfsBuf));

            LOGI("createContainer: f_mkfs result=%d fmt=%d exfat=%d",
                 (int)fr, (int)mp.fmt, (int)useExFat);

            f_mount(nullptr, drivePaths[volId], 0);
            v.fsMounted          = false;
            v.fd                 = -1;
            v.dataOffset         = 0;
            v.dataAreaLengthBytes = 0;
            v.fileSize           = 0;
            v.cascade.initialized = false;
            v.dataCtxInitialized = false;

            if (fr != FR_OK) {
                LOGI("createContainer: f_mkfs failed, code=%d", (int)fr);
                break;
            }
        }

        success = true;
        LOGI("createContainer: complete – %lld bytes, fs=%s",
             (long long)sizeBytes, nativeFS);

    } while (false);

    mbedtls_platform_zeroize(combinedMasterKey, sizeof(combinedMasterKey));
    mbedtls_platform_zeroize(salt, sizeof(salt));

    env->ReleaseStringUTFChars(password, nativePass);
    env->ReleaseStringUTFChars(fileSystem, nativeFS);
    if (success) {
        fsync(fd); // Final physical sync
        LOGI("createContainer: SUCCESS.");
    }
    close(fd);

    return success ? JNI_TRUE : JNI_FALSE;
}

// ----------------------------------------------------------------====
// PBKDF2-SHA512
// ----------------------------------------------------------------====

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_hashPasswordNative(
        JNIEnv* env, jobject,
        jstring password, jbyteArray salt, jint iterations) {

    if (password == nullptr || salt == nullptr) return nullptr;

    const jsize saltLen = env->GetArrayLength(salt);
    if (saltLen == 0) return nullptr;

    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    jbyte* saltData        = env->GetByteArrayElements(salt, nullptr);

    unsigned char out[64] = {0};
    jbyteArray result     = nullptr;

    const unsigned int safeIter =
        (iterations > 0) ? static_cast<unsigned int>(iterations) : 200000u;

    MdContextGuard mdGuard;
    if (mbedtls_md_setup(&mdGuard.ctx,
            mbedtls_md_info_from_type(MBEDTLS_MD_SHA512), 1) == 0) {
        int rc = mbedtls_pkcs5_pbkdf2_hmac(
            &mdGuard.ctx,
            reinterpret_cast<const unsigned char*>(nativePass), strlen(nativePass),
            reinterpret_cast<const unsigned char*>(saltData), static_cast<size_t>(saltLen),
            safeIter, 64, out);

        if (rc == 0) {
            result = env->NewByteArray(64);
            env->SetByteArrayRegion(result, 0, 64, reinterpret_cast<jbyte*>(out));
        } else {
            LOGI("hashPasswordNative: PBKDF2 failed, rc=%d", rc);
        }
    }

    mbedtls_platform_zeroize(out, sizeof(out));

    env->ReleaseStringUTFChars(password, nativePass);
    env->ReleaseByteArrayElements(salt, saltData, JNI_ABORT);

    return result;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getMatchedCipherId(JNIEnv*, jobject, jint volId) {
    if (volId < 0 || volId >= MAX_VOLUMES) return -1;
    std::lock_guard<std::mutex> lock(volumes[volId].mutex);
    return volumes[volId].matchedCipherId;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getMatchedHashId(JNIEnv*, jobject, jint volId) {
    if (volId < 0 || volId >= MAX_VOLUMES) return -1;
    std::lock_guard<std::mutex> lock(volumes[volId].mutex);
    return volumes[volId].matchedHashId;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getContainerFormat(JNIEnv*, jobject, jint volId) {
    if (volId < 0 || volId >= MAX_VOLUMES) return 0;
    std::lock_guard<std::mutex> lock(volumes[volId].mutex);
    return static_cast<jint>(volumes[volId].containerFormat);
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getMatchedPartitionOffset(JNIEnv*, jobject, jint volId) {
    if (volId < 0 || volId >= MAX_VOLUMES) return -1;
    std::lock_guard<std::mutex> lock(volumes[volId].mutex);
    if (!volumes[volId].isUsbSource) return -1;
    return static_cast<jlong>(volumes[volId].partitionStartSector);
}

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_listDirectory(
        JNIEnv* env, jobject, jstring dirPath, jint volId) {
    if (!requireActiveSession(volId, "listDirectory")) {
        throwNotUnlocked(env, volId, "listDirectory"); return nullptr;
    }
    const char* nativePath = env->GetStringUTFChars(dirPath, nullptr);
    jobjectArray result = nullptr;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId))
            result = buildDirectoryListing(env, volId, nativePath);
    }
    env->ReleaseStringUTFChars(dirPath, nativePath);
    return result;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getFileSize(
        JNIEnv* env, jobject, jstring fileName, jint volId) {
    if (!requireActiveSession(volId, "getFileSize")) {
        throwNotUnlocked(env, volId, "getFileSize"); return 0L;
    }
    const char* targetName = env->GetStringUTFChars(fileName, nullptr);
    jlong size = 0;
    auto& v = volumes[volId];
    {
        std::lock_guard<std::mutex> fsLock(v.mutex);
        if (ensureMounted(volId)) {
            if (v.fsType == VolumeState::FS_FATFS) {
                FIL f;
                std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
                if (f_open(&f, fatPath.c_str(), FA_READ) == FR_OK) {
                    size = static_cast<jlong>(f_size(&f));
                    f_close(&f);
                }
            } else if (v.fsType == VolumeState::FS_NTFS) {
                std::string fullPath = "/" + std::string(targetName);
                ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());
                if (ni) {
                    size = static_cast<jlong>(ni->data_size);
                    ntfs_inode_close(ni);
                }
            } else if (v.fsType == VolumeState::FS_EXT) {
                ext2_ino_t ino = 0;
                struct ext2_inode inode{};
                if (extResolvePath(v.extFs, targetName, &ino) &&
                    ext2fs_read_inode(v.extFs, ino, &inode) == 0)
                    size = static_cast<jlong>((static_cast<uint64_t>(inode.i_size_high) << 32) | inode.i_size);
            }
        }
    }
    env->ReleaseStringUTFChars(fileName, targetName);
    return size;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getFolderSize(
        JNIEnv* env, jobject, jstring dirPath, jint volId) {
    if (!requireActiveSession(volId, "getFolderSize")) {
        throwNotUnlocked(env, volId, "getFolderSize"); return 0L;
    }
    const char* nativePath = env->GetStringUTFChars(dirPath, nullptr);
    jlong total = 0;
    auto& v = volumes[volId];
    {
        std::lock_guard<std::mutex> fsLock(v.mutex);
        if (ensureMounted(volId)) {
            if (v.fsType == VolumeState::FS_FATFS) {
                total = static_cast<jlong>(recursiveFatFolderSize(volId, nativePath));
            } else if (v.fsType == VolumeState::FS_NTFS) {
                total = static_cast<jlong>(recursiveNtfsFolderSize(volId, nativePath));
            }
        }
    }
    env->ReleaseStringUTFChars(dirPath, nativePath);
    return total;
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_readFileChunk(
        JNIEnv* env, jobject,
        jstring fileName, jlong offset, jint length, jint volId) {
    if (length <= 0 || static_cast<size_t>(length) > MAX_CHUNK_SIZE) return nullptr;
    if (!requireActiveSession(volId, "readFileChunk")) {
        throwNotUnlocked(env, volId, "readFileChunk"); return nullptr;
    }
    const char* targetName = env->GetStringUTFChars(fileName, nullptr);
    jbyteArray retArray = nullptr;
    auto& v = volumes[volId];
    {
        std::lock_guard<std::mutex> fsLock(v.mutex);
        if (ensureMounted(volId)) {
            if (v.fsType == VolumeState::FS_FATFS) {
                FIL f;
                std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
                if (f_open(&f, fatPath.c_str(), FA_READ) == FR_OK) {
                    f_lseek(&f, static_cast<FSIZE_t>(offset));
                    std::unique_ptr<unsigned char[]> buffer(new unsigned char[length]);
                    UINT br = 0;
                    if (f_read(&f, buffer.get(), static_cast<UINT>(length), &br) == FR_OK && br > 0) {
                        retArray = env->NewByteArray(static_cast<jsize>(br));
                        env->SetByteArrayRegion(retArray, 0, static_cast<jsize>(br),
                                                reinterpret_cast<jbyte*>(buffer.get()));
                    }
                    f_close(&f);
                }
            } else if (v.fsType == VolumeState::FS_NTFS) {
                std::string fullPath = "/" + std::string(targetName);
                ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());
                if (ni) {
                    ntfs_attr* na = ntfs_attr_open(ni, AT_DATA, NULL, 0);
                    if (na) {
                        std::unique_ptr<unsigned char[]> buffer(new unsigned char[length]);
                        s64 br = ntfs_attr_pread(na, offset, length, buffer.get());
                        if (br > 0) {
                            retArray = env->NewByteArray(static_cast<jsize>(br));
                            env->SetByteArrayRegion(retArray, 0, static_cast<jsize>(br),
                                                    reinterpret_cast<jbyte*>(buffer.get()));
                        }
                        ntfs_attr_close(na);
                    }
                    ntfs_inode_close(ni);
                }
            } else if (v.fsType == VolumeState::FS_EXT) {
                ext2_file_t file = nullptr;
                if (extOpenFile(v.extFs, targetName, false, false, &file)) {
                    __u64 position = 0;
                    std::unique_ptr<unsigned char[]> buffer(new unsigned char[length]);
                    unsigned int got = 0;
                    if (ext2fs_file_llseek(file, static_cast<__u64>(offset), EXT2_SEEK_SET, &position) == 0 &&
                        ext2fs_file_read(file, buffer.get(), static_cast<unsigned int>(length), &got) == 0 && got > 0) {
                        retArray = env->NewByteArray(static_cast<jsize>(got));
                        env->SetByteArrayRegion(retArray, 0, static_cast<jsize>(got),
                                                reinterpret_cast<jbyte*>(buffer.get()));
                    }
                    ext2fs_file_close(file);
                }
            }
        }
    }
    env->ReleaseStringUTFChars(fileName, targetName);
    return retArray;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_writeFileChunk(
        JNIEnv* env, jobject,
        jstring fileName, jlong offset, jbyteArray data, jint volId) {
    jsize len = env->GetArrayLength(data);
    if (len <= 0 || static_cast<size_t>(len) > MAX_CHUNK_SIZE) return JNI_FALSE;
    if (!requireActiveSession(volId, "writeFileChunk")) {
        throwNotUnlocked(env, volId, "writeFileChunk"); return JNI_FALSE;
    }
    const char* targetName = env->GetStringUTFChars(fileName, nullptr);
    jbyte* body = env->GetByteArrayElements(data, nullptr);
    bool success = false;

    auto& v = volumes[volId];
    std::lock_guard<std::mutex> fsLock(v.mutex);
    if (ensureMounted(volId)) {
        if (v.fsType == VolumeState::FS_FATFS) {
            FIL f;
            std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
            BYTE openMode = (offset == 0) ? (FA_WRITE | FA_CREATE_ALWAYS) : (FA_WRITE | FA_OPEN_ALWAYS);
            if (f_open(&f, fatPath.c_str(), openMode) == FR_OK) {
                if (f_lseek(&f, static_cast<FSIZE_t>(offset)) == FR_OK) {
                    UINT bw = 0;
                    if (f_write(&f, body, static_cast<UINT>(len), &bw) == FR_OK && bw == static_cast<UINT>(len))
                        success = true;
                }
                f_close(&f);
            }
        } else if (v.fsType == VolumeState::FS_NTFS) {
            std::string fullPath = "/" + std::string(targetName);
            ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());

            if (!ni) { // Create file
                ni = createNtfsFile(v.ntfsVol, fullPath);
            }

            if (ni) {
                    ntfs_attr* na = ntfs_attr_open(ni, AT_DATA, NULL, 0);
                    if (!na) {
                        ntfs_attr_add(ni, AT_DATA, AT_UNNAMED, 0, NULL, 0);
                        na = ntfs_attr_open(ni, AT_DATA, NULL, 0);
                    }
                    if (na) {
                        if (offset == 0) {
                            ntfs_attr_truncate(na, 0);
                        }
                        s64 bw = ntfs_attr_pwrite(na, offset, len, body);
                        if (bw == static_cast<s64>(len)) success = true;
                        ntfs_attr_close(na);
                    }
                    ntfs_inode_close(ni);
                }
        } else if (v.fsType == VolumeState::FS_EXT) {
            ext2_file_t file = nullptr;
            if (extOpenFile(v.extFs, targetName, true, true, &file)) {
                __u64 position = 0;
                if (offset == 0) ext2fs_file_set_size2(file, 0);
                unsigned int written = 0;
                if (ext2fs_file_llseek(file, static_cast<__u64>(offset), EXT2_SEEK_SET, &position) == 0 &&
                    ext2fs_file_write(file, body, static_cast<unsigned int>(len), &written) == 0 &&
                    written == static_cast<unsigned int>(len) && ext2fs_file_flush(file) == 0) {
                    ext2fs_flush(v.extFs);
                    success = true;
                }
                ext2fs_file_close(file);
            }
        }
    }

    env->ReleaseByteArrayElements(data, body, JNI_ABORT);
    env->ReleaseStringUTFChars(fileName, targetName);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_writeBackFile(
        JNIEnv* env, jobject,
        jstring targetFileName, jstring sourcePath, jint volId) {
    if (!requireActiveSession(volId, "writeBackFile")) {
        throwNotUnlocked(env, volId, "writeBackFile"); return JNI_FALSE;
    }
    const char* targetName = env->GetStringUTFChars(targetFileName, nullptr);
    const char* source     = env->GetStringUTFChars(sourcePath, nullptr);
    bool success = false;
    auto& v = volumes[volId];
    {
        std::lock_guard<std::mutex> fsLock(v.mutex);
        if (ensureMounted(volId)) {
            if (v.fsType == VolumeState::FS_FATFS) {
                FIL f;
                std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
                if (f_open(&f, fatPath.c_str(), FA_WRITE | FA_CREATE_ALWAYS) == FR_OK) {
                    std::ifstream inFile(source, std::ios::binary);
                    if (inFile.is_open()) {
                        std::unique_ptr<char[]> buf(new char[IO_BUFFER_SIZE]);
                        UINT bw;
                        bool writeError = false;
                        while (inFile && !writeError) {
                            inFile.read(buf.get(), IO_BUFFER_SIZE);
                            std::streamsize n = inFile.gcount();
                            if (n > 0) {
                                FRESULT res = f_write(&f, buf.get(), static_cast<UINT>(n), &bw);
                                if (res != FR_OK || bw != static_cast<UINT>(n)) {
                                    writeError = true;
                                }
                            }
                        }
                        if (!writeError) {
                            success = true;
                        }
                    }
                    f_close(&f);
                    if (!success) {
                        f_unlink(fatPath.c_str());
                    }
                }
            } else if (v.fsType == VolumeState::FS_NTFS) {
                std::string fullPath = "/" + std::string(targetName);
                ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());
                if (!ni) {
                    ni = createNtfsFile(v.ntfsVol, fullPath);
                }

                if (ni) {
                    ntfs_attr* na = ntfs_attr_open(ni, AT_DATA, NULL, 0);
                    if (!na) {
                        ntfs_attr_add(ni, AT_DATA, AT_UNNAMED, 0, NULL, 0);
                        na = ntfs_attr_open(ni, AT_DATA, NULL, 0);
                    }
                    if (na) {
                        ntfs_attr_truncate(na, 0);
                        std::ifstream inFile(source, std::ios::binary);
                        if (inFile.is_open()) {
                            std::unique_ptr<char[]> buf(new char[IO_BUFFER_SIZE]);
                            s64 offset = 0;
                            bool writeError = false;
                            while (inFile && !writeError) {
                                inFile.read(buf.get(), IO_BUFFER_SIZE);
                                std::streamsize n = inFile.gcount();
                                if (n > 0) {
                                    s64 bw = ntfs_attr_pwrite(na, offset, n, buf.get());
                                    if (bw != n) {
                                        writeError = true;
                                    } else {
                                        offset += bw;
                                    }
                                }
                            }
                            if (!writeError) {
                                success = true;
                            }
                        }
                        ntfs_attr_close(na);
                    }
                    ntfs_inode_close(ni);
                }
            } else if (v.fsType == VolumeState::FS_EXT) {
                success = extWriteFromHostFile(v.extFs, targetName, source);
                if (success) success = ext2fs_flush(v.extFs) == 0;
            }
        }
    }
    env->ReleaseStringUTFChars(targetFileName, targetName);
    env->ReleaseStringUTFChars(sourcePath, source);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_extractFile(
        JNIEnv* env, jobject,
        jstring targetFileName, jstring destPath, jint volId) {
    if (!requireActiveSession(volId, "extractFile")) {
        throwNotUnlocked(env, volId, "extractFile"); return JNI_FALSE;
    }
    const char* targetName  = env->GetStringUTFChars(targetFileName, nullptr);
    const char* destination = env->GetStringUTFChars(destPath, nullptr);
    bool success = false;
    auto& v = volumes[volId];
    {
        std::lock_guard<std::mutex> fsLock(v.mutex);
        if (ensureMounted(volId)) {
            if (v.fsType == VolumeState::FS_FATFS) {
                FIL f;
                std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
                if (f_open(&f, fatPath.c_str(), FA_READ) == FR_OK) {
                    std::ofstream outFile(destination, std::ios::binary);
                    if (outFile.is_open()) {
                        std::unique_ptr<unsigned char[]> buf(new unsigned char[IO_BUFFER_SIZE]);
                        UINT br;
                        while (f_read(&f, buf.get(), IO_BUFFER_SIZE, &br) == FR_OK && br > 0)
                            outFile.write(reinterpret_cast<char*>(buf.get()), br);
                        success = true;
                    }
                    f_close(&f);
                }
            } else if (v.fsType == VolumeState::FS_NTFS) {
                std::string fullPath = "/" + std::string(targetName);
                ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());
                if (ni) {
                    ntfs_attr* na = ntfs_attr_open(ni, AT_DATA, NULL, 0);
                    if (na) {
                        std::ofstream outFile(destination, std::ios::binary);
                        if (outFile.is_open()) {
                            std::unique_ptr<unsigned char[]> buf(new unsigned char[IO_BUFFER_SIZE]);
                            s64 offset = 0;
                            while (true) {
                                s64 br = ntfs_attr_pread(na, offset, IO_BUFFER_SIZE, buf.get());
                                if (br <= 0) break;
                                outFile.write(reinterpret_cast<char*>(buf.get()), br);
                                offset += br;
                            }
                            success = true;
                        }
                        ntfs_attr_close(na);
                    }
                    ntfs_inode_close(ni);
                }
            } else if (v.fsType == VolumeState::FS_EXT) {
                success = extExtractToHostFile(v.extFs, targetName, destination);
            }
        }
    }
    env->ReleaseStringUTFChars(targetFileName, targetName);
    env->ReleaseStringUTFChars(destPath, destination);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_deleteFile(
        JNIEnv* env, jobject, jstring targetFileName, jint volId) {
    if (!requireActiveSession(volId, "deleteFile")) {
        throwNotUnlocked(env, volId, "deleteFile"); return JNI_FALSE;
    }
    const char* targetName = env->GetStringUTFChars(targetFileName, nullptr);
    bool success = false;
    auto& v = volumes[volId];
    {
        std::lock_guard<std::mutex> fsLock(v.mutex);
        if (ensureMounted(volId)) {
            if (v.fsType == VolumeState::FS_FATFS) {
                std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
                success = (f_unlink(fatPath.c_str()) == FR_OK);
            } else if (v.fsType == VolumeState::FS_NTFS) {
    std::string fullPath = "/" + std::string(targetName);
    ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());
    size_t slashPos = fullPath.find_last_of('/');
    std::string parentPath = fullPath.substr(0, slashPos);
    std::string childName = fullPath.substr(slashPos + 1);
    if (parentPath.empty()) parentPath = "/";

    ntfs_inode* dir_ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, parentPath.c_str());
    if (dir_ni && ni) {
        ntfschar* uname = nullptr;
        int uname_len = ntfs_mbstoucs(childName.c_str(), &uname);
        if (uname_len >= 0) {
            // ntfs_delete() unconditionally closes BOTH ni and dir_ni before
            // returning (success or failure) — closing them again below was
            // a double-free of already-released MFT-record state, which is
            // what corrupted the heap and crashed the app right after delete.
            success = (ntfs_delete(v.ntfsVol, fullPath.c_str(), ni, dir_ni,
                                    uname, static_cast<u8>(uname_len)) == 0);
            free(uname);
            ni = nullptr;
            dir_ni = nullptr;
        }
    }
    if (ni) ntfs_inode_close(ni);
    if (dir_ni) ntfs_inode_close(dir_ni);
}
            else if (v.fsType == VolumeState::FS_EXT) {
                const std::string path(targetName);
                const size_t slash = path.find_last_of('/');
                const std::string parentPath = slash == std::string::npos ? "" : path.substr(0, slash);
                const std::string name = slash == std::string::npos ? path : path.substr(slash + 1);
                ext2_ino_t parent = 0, ino = 0;
                if (!name.empty() && extResolvePath(v.extFs, parentPath, &parent) &&
                    extResolvePath(v.extFs, path, &ino) &&
                    ext2fs_unlink(v.extFs, parent, name.c_str(), ino, 0) == 0) {
                    struct ext2_inode inode{};
                    if (ext2fs_read_inode(v.extFs, ino, &inode) == 0 && inode.i_links_count) {
                        --inode.i_links_count;
                        ext2fs_write_inode(v.extFs, ino, &inode);
                    }
                    ext2fs_flush(v.extFs);
                    success = true;
                }
            }
        }
    }
    env->ReleaseStringUTFChars(targetFileName, targetName);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_createDirectory(
        JNIEnv* env, jobject, jstring dirPath, jint volId) {
    if (!requireActiveSession(volId, "createDirectory")) {
        throwNotUnlocked(env, volId, "createDirectory"); return JNI_FALSE;
    }
    const char* nativePath = env->GetStringUTFChars(dirPath, nullptr);
    bool success = false;
    auto& v = volumes[volId];
    {
        std::lock_guard<std::mutex> fsLock(v.mutex);
        if (ensureMounted(volId)) {
            if (v.fsType == VolumeState::FS_FATFS) {
                std::string fullPath = std::string(drivePaths[volId]) + "/" + nativePath;
                success = (f_mkdir(fullPath.c_str()) == FR_OK);
            } else if (v.fsType == VolumeState::FS_NTFS) {
                std::string fullPath = "/" + std::string(nativePath);
                size_t slashPos = fullPath.find_last_of('/');
                std::string parentPath = fullPath.substr(0, slashPos);
                std::string childName = fullPath.substr(slashPos + 1);
                if (parentPath.empty()) parentPath = "/";

                ntfs_inode* parentNi = ntfs_pathname_to_inode(v.ntfsVol, NULL, parentPath.c_str());
                if (parentNi) {
                    ntfschar* uChild = nullptr;
                    int uChildLen = ntfs_mbstoucs(childName.c_str(), &uChild);
                    if (uChildLen >= 0) {
                        ntfs_inode* ni = ntfs_create(parentNi, 0, uChild, uChildLen, S_IFDIR);
                        if (ni) {
                            success = true;
                            ntfs_inode_close(ni);
                        }
                        free(uChild);
                    }
                    ntfs_inode_close(parentNi);
                }
            } else if (v.fsType == VolumeState::FS_EXT) {
                const std::string path(nativePath);
                const size_t slash = path.find_last_of('/');
                const std::string parentPath = slash == std::string::npos ? "" : path.substr(0, slash);
                const std::string name = slash == std::string::npos ? path : path.substr(slash + 1);
                ext2_ino_t parent = 0;
                if (!name.empty() && extResolvePath(v.extFs, parentPath, &parent) &&
                    ext2fs_mkdir(v.extFs, parent, 0, name.c_str()) == 0) {
                    ext2fs_flush(v.extFs);
                    success = true;
                }
            }
        }
    }
    env->ReleaseStringUTFChars(dirPath, nativePath);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_renameFile(
        JNIEnv* env, jobject,
        jstring oldPath, jstring newPath, jint volId) {
    if (!requireActiveSession(volId, "renameFile")) {
        throwNotUnlocked(env, volId, "renameFile"); return JNI_FALSE;
    }
    const char* nativeOld = env->GetStringUTFChars(oldPath, nullptr);
    const char* nativeNew = env->GetStringUTFChars(newPath, nullptr);
    bool success = false;
    auto& v = volumes[volId];
    {
        std::lock_guard<std::mutex> fsLock(v.mutex);
        if (ensureMounted(volId)) {
            if (v.fsType == VolumeState::FS_FATFS) {
                std::string fullOld = std::string(drivePaths[volId]) + "/" + nativeOld;
                std::string fullNew = std::string(drivePaths[volId]) + "/" + nativeNew;
                success = (f_rename(fullOld.c_str(), fullNew.c_str()) == FR_OK);
            } else if (v.fsType == VolumeState::FS_NTFS) {
                std::string oldFullPath = "/" + std::string(nativeOld);
                std::string newFullPath = "/" + std::string(nativeNew);

                size_t slashPosOld = oldFullPath.find_last_of('/');
                std::string parentOldPath = oldFullPath.substr(0, slashPosOld);
                std::string oldChildName = oldFullPath.substr(slashPosOld + 1);
                if (parentOldPath.empty()) parentOldPath = "/";

                size_t slashPosNew = newFullPath.find_last_of('/');
                std::string parentNewPath = newFullPath.substr(0, slashPosNew);
                std::string newChildName = newFullPath.substr(slashPosNew + 1);
                if (parentNewPath.empty()) parentNewPath = "/";

                ntfschar* uOld = nullptr;
                int uOldLen = ntfs_mbstoucs(oldChildName.c_str(), &uOld);
                ntfschar* uNew = nullptr;
                int uNewLen = ntfs_mbstoucs(newChildName.c_str(), &uNew);

                if (uOldLen >= 0 && uNewLen >= 0) {
                    // Step 1: if something already exists at the destination, overwrite it
                    ntfs_inode* dest_ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, newFullPath.c_str());
                    if (dest_ni) {
                        ntfs_inode* dest_dir_ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, parentNewPath.c_str());
                        if (dest_dir_ni) {
                            ntfs_delete(v.ntfsVol, newFullPath.c_str(), dest_ni, dest_dir_ni,
                                        uNew, static_cast<u8>(uNewLen));
                        } else {
                            ntfs_inode_close(dest_ni);
                        }
                    }

                    // Step 2: pre-open all necessary inodes
                    ntfs_inode* old_ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, oldFullPath.c_str());
                    ntfs_inode* dir_new_ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, parentNewPath.c_str());
                    ntfs_inode* dir_old_ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, parentOldPath.c_str());

                    if (old_ni && dir_new_ni && dir_old_ni) {
                        // Link source under the new name
                        if (ntfs_link(old_ni, dir_new_ni, uNew, static_cast<u8>(uNewLen)) == 0) {
                            // Unlink the old name
                            success = (ntfs_delete(v.ntfsVol, oldFullPath.c_str(), old_ni, dir_old_ni,
                                                    uOld, static_cast<u8>(uOldLen)) == 0);
                            old_ni = nullptr; // pointer consumed by ntfs_delete
                            dir_old_ni = nullptr; // pointer consumed by ntfs_delete
                        }
                        
                        // Close whatever didn't get consumed
                        if (old_ni) ntfs_inode_close(old_ni);
                        if (dir_old_ni) ntfs_inode_close(dir_old_ni);
                        ntfs_inode_close(dir_new_ni);
                    } else {
                        if (old_ni) ntfs_inode_close(old_ni);
                        if (dir_new_ni) ntfs_inode_close(dir_new_ni);
                        if (dir_old_ni) ntfs_inode_close(dir_old_ni);
                    }
                }
                if (uOld) free(uOld);
                if (uNew) free(uNew);
            }
        }
    }
    env->ReleaseStringUTFChars(oldPath, nativeOld);
    env->ReleaseStringUTFChars(newPath, nativeNew);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_setLastModifiedTime(
        JNIEnv* env, jobject,
        jstring path, jlong epochSeconds, jint volId) {
    if (!requireActiveSession(volId, "setLastModifiedTime")) {
        throwNotUnlocked(env, volId, "setLastModifiedTime"); return JNI_FALSE;
    }
    const char* nativePath = env->GetStringUTFChars(path, nullptr);
    bool success = false;
    auto& v = volumes[volId];
    {
        std::lock_guard<std::mutex> fsLock(v.mutex);
        if (ensureMounted(volId)) {
            if (v.fsType == VolumeState::FS_FATFS) {
                WORD fdate = 0, ftime = 0;
                unixToFatTimestamp(static_cast<uint64_t>(epochSeconds), fdate, ftime);
                std::string fatPath = std::string(drivePaths[volId]) + "/" + nativePath;
                FILINFO fno = {};
                fno.fdate = fdate;
                fno.ftime = ftime;
                success = (f_utime(fatPath.c_str(), &fno) == FR_OK);
            } else if (v.fsType == VolumeState::FS_NTFS) {
                std::string fullPath = "/" + std::string(nativePath);
                ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());
                if (ni) {
                    uint64_t ntfsTime = (static_cast<uint64_t>(epochSeconds) * 10000000ULL) + 116444736000000000ULL;
                    ni->last_data_change_time = ntfsTime;
                    ni->last_access_time = ntfsTime;
                    ni->last_mft_change_time = ntfsTime;
                    NInoSetDirty(ni);
                    success = (ntfs_inode_close(ni) == 0);
                }
            } else if (v.fsType == VolumeState::FS_EXT) {
                ext2_ino_t ino = 0;
                if (extResolvePath(v.extFs, nativePath, &ino)) {
                    struct ext2_inode inode = {};
                    if (ext2fs_read_inode(v.extFs, ino, &inode) == 0) {
                        inode.i_mtime = static_cast<__u32>(epochSeconds);
                        inode.i_atime = static_cast<__u32>(epochSeconds);
                        inode.i_ctime = static_cast<__u32>(epochSeconds);
                        if (ext2fs_write_inode(v.extFs, ino, &inode) == 0) {
                            ext2fs_flush(v.extFs);
                            success = true;
                        }
                    }
                }
            }
        }
    }
    env->ReleaseStringUTFChars(path, nativePath);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jlongArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getSpaceInfo(
        JNIEnv* env, jobject, jint volId) {
    if (!requireActiveSession(volId, "getSpaceInfo")) {
        throwNotUnlocked(env, volId, "getSpaceInfo"); return nullptr;
    }
    jlong totalBytes = 0, freeBytes = 0;
    auto& v = volumes[volId];
    {
        std::lock_guard<std::mutex> fsLock(v.mutex);
        if (ensureMounted(volId)) {
            if (v.fsType == VolumeState::FS_FATFS) {
                FATFS* fs;
                DWORD fre_clust;
                if (f_getfree(drivePaths[volId], &fre_clust, &fs) == FR_OK) {
                    totalBytes = static_cast<jlong>(fs->n_fatent - 2) * fs->csize * 512;
                    freeBytes  = static_cast<jlong>(fre_clust) * fs->csize * 512;
                }
            } else if (v.fsType == VolumeState::FS_NTFS) {
                ntfs_volume* vol = v.ntfsVol;
                s64 total_clusters = vol->nr_clusters;
                s64 free_cl = ntfs_attr_get_free_bits(vol->lcnbmp_na);
                totalBytes = total_clusters * vol->cluster_size;
                freeBytes  = free_cl * vol->cluster_size;
            } else if (v.fsType == VolumeState::FS_EXT) {
                totalBytes = static_cast<jlong>(ext2fs_blocks_count(v.extFs->super)) * v.extFs->blocksize;
                freeBytes = static_cast<jlong>(ext2fs_free_blocks_count(v.extFs->super)) * v.extFs->blocksize;
            }
        }
    }
    jlongArray ret = env->NewLongArray(2);
    if (!ret) return nullptr;
    const jlong tmp[2] = {totalBytes, freeBytes};
    env->SetLongArrayRegion(ret, 0, 2, tmp);
    return ret;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_openStream(
        JNIEnv* env, jobject, jstring targetFileName, jint volId) {
    if (!requireActiveSession(volId, "openStream")) {
        throwNotUnlocked(env, volId, "openStream"); return 0L;
    }
    const char* targetName = env->GetStringUTFChars(targetFileName, nullptr);
    jlong streamPtr = 0;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            auto& v = volumes[volId];
            if (v.fsType == VolumeState::FS_FATFS) {
                FIL* f = new FIL();
                std::string fatPath = std::string(drivePaths[volId]) + "/" + targetName;
                if (f_open(f, fatPath.c_str(), FA_READ) == FR_OK) {
                    streamPtr = reinterpret_cast<jlong>(f);
                    v.openStreams.push_back(f);
                } else {
                    delete f;
                }
            } else if (v.fsType == VolumeState::FS_NTFS) {
                std::string fullPath = "/" + std::string(targetName);
                ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());
                if (ni) {
                    ntfs_attr* na = ntfs_attr_open(ni, AT_DATA, NULL, 0);
                    if (na) {
                        NtfsStream* ns = new NtfsStream();
                        ns->inode = ni;
                        ns->attr = na;
                        streamPtr = reinterpret_cast<jlong>(ns);
                        v.openNtfsStreams.push_back(ns);
                    } else {
                        ntfs_inode_close(ni);
                    }
                }
            } else if (v.fsType == VolumeState::FS_EXT) {
                ext2_file_t file = nullptr;
                if (extOpenFile(v.extFs, targetName, false, false, &file)) {
                    auto* stream = new ExtStream{file};
                    streamPtr = reinterpret_cast<jlong>(stream);
                    v.openExtStreams.push_back(stream);
                }
            }
        }
    }
    env->ReleaseStringUTFChars(targetFileName, targetName);
    return streamPtr;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_readStream(
        JNIEnv* env, jobject,
        jlong streamPtr, jlong offset, jbyteArray outBuffer, jint length, jint volId) {
    if (streamPtr == 0 || length <= 0) return -1;
    if (volId < 0 || volId >= MAX_VOLUMES) return -1;
    jint bytesRead = -1;

    std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
    auto& v = volumes[volId];
    if (v.fsType == VolumeState::FS_FATFS) {
        FIL* f = reinterpret_cast<FIL*>(streamPtr);
        auto& streams = v.openStreams;
        if (std::find(streams.begin(), streams.end(), f) == streams.end()) return -1;

        f_lseek(f, static_cast<FSIZE_t>(offset));
        jbyte* destBuf = env->GetByteArrayElements(outBuffer, nullptr);
        if (destBuf != nullptr) {
            UINT br = 0;
            if (f_read(f, destBuf, static_cast<UINT>(length), &br) == FR_OK)
                bytesRead = static_cast<jint>(br);
            env->ReleaseByteArrayElements(outBuffer, destBuf, 0);
        }
    } else if (v.fsType == VolumeState::FS_NTFS) {
        NtfsStream* ns = reinterpret_cast<NtfsStream*>(streamPtr);
        auto& streams = v.openNtfsStreams;
        if (std::find(streams.begin(), streams.end(), ns) == streams.end()) return -1;

        jbyte* destBuf = env->GetByteArrayElements(outBuffer, nullptr);
        if (destBuf != nullptr) {
            s64 br = ntfs_attr_pread(ns->attr, offset, length, destBuf);
            if (br >= 0) bytesRead = static_cast<jint>(br);
            env->ReleaseByteArrayElements(outBuffer, destBuf, 0);
        }
    } else if (v.fsType == VolumeState::FS_EXT) {
        ExtStream* stream = reinterpret_cast<ExtStream*>(streamPtr);
        if (std::find(v.openExtStreams.begin(), v.openExtStreams.end(), stream) == v.openExtStreams.end()) return -1;
        jbyte* destBuf = env->GetByteArrayElements(outBuffer, nullptr);
        if (destBuf != nullptr) {
            __u64 position = 0;
            unsigned int got = 0;
            if (ext2fs_file_llseek(stream->file, static_cast<__u64>(offset), EXT2_SEEK_SET, &position) == 0 &&
                ext2fs_file_read(stream->file, destBuf, static_cast<unsigned int>(length), &got) == 0)
                bytesRead = static_cast<jint>(got);
            env->ReleaseByteArrayElements(outBuffer, destBuf, 0);
        }
    }
    return bytesRead;
}

extern "C" JNIEXPORT void JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_closeStream(
        JNIEnv* env, jobject, jlong streamPtr, jint volId) {
    if (streamPtr == 0) return;
    if (volId < 0 || volId >= MAX_VOLUMES) return;

    std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
    auto& v = volumes[volId];
    if (v.fsType == VolumeState::FS_FATFS) {
        FIL* f = reinterpret_cast<FIL*>(streamPtr);
        auto& streams = v.openStreams;
        auto it = std::find(streams.begin(), streams.end(), f);
        if (it == streams.end()) return;
        streams.erase(it);
        f_close(f);
        delete f;
    } else if (v.fsType == VolumeState::FS_NTFS) {
        NtfsStream* ns = reinterpret_cast<NtfsStream*>(streamPtr);
        auto& streams = v.openNtfsStreams;
        auto it = std::find(streams.begin(), streams.end(), ns);
        if (it == streams.end()) return;
        streams.erase(it);
        ntfs_attr_close(ns->attr);
        ntfs_inode_close(ns->inode);
        delete ns;
    } else if (v.fsType == VolumeState::FS_EXT) {
        ExtStream* stream = reinterpret_cast<ExtStream*>(streamPtr);
        auto it = std::find(v.openExtStreams.begin(), v.openExtStreams.end(), stream);
        if (it == v.openExtStreams.end()) return;
        v.openExtStreams.erase(it);
        ext2fs_file_close(stream->file);
        delete stream;
    }
}

// ── Startup self-check ────────────────────────────────────────────────

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getCascadeFingerprint(
        JNIEnv*, jobject, jint cascadeId) {
    if (cascadeId < 0 || cascadeId >= 15) return -1;
    CascadeSpec spec = cascadeSpecFor(static_cast<CascadeId>(cascadeId));
    int packed = spec.layerCount * 1000;
    for (int i = 0; i < 3; i++) {
        int layerVal = (i < spec.layerCount) ? static_cast<int>(spec.layers[i]) : 9;
        packed += layerVal * (i == 0 ? 100 : (i == 1 ? 10 : 1));
    }
    return packed;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getCascadeIdCount(JNIEnv*, jobject) {
    return 15; // the eight legacy IDs plus the seven VeraCrypt 1.26.29 additions
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getHashIdCount(JNIEnv*, jobject) {
    return 6; // kSha512, kSha256, kWhirlpool, kStreebog, kBlake2s256, kArgon2id
}

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_unlockUsbAndListNative(
        JNIEnv* env, jobject, jstring password, jint pim, jint volId, jlong deviceSizeBytes, jint cipherId, jint hashId, jbyteArray preservedKey,
        jlong partitionOffsetHint, jintArray keyfileFds) {

    if (volId >= 0 && volId < MAX_VOLUMES) {
        cancelRequested[volId].store(false, std::memory_order_release);
    }

    const unsigned char* preservedBytes = nullptr;
    size_t preservedLen = 0;
    if (preservedKey != nullptr) {
        preservedBytes = reinterpret_cast<const unsigned char*>(env->GetByteArrayElements(preservedKey, nullptr));
        preservedLen = static_cast<size_t>(env->GetArrayLength(preservedKey));
    }

    std::vector<int> kfFds = extractKeyfileFds(env, keyfileFds);
    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    
    // Prepare the USB session with the password and explicit length parameter.
    const bool ok = prepareUsbSession(reinterpret_cast<const unsigned char*>(nativePass), strlen(nativePass), pim, volId, cipherId, hashId, preservedBytes, preservedLen,
                                       static_cast<int64_t>(partitionOffsetHint),
                                       kfFds.empty() ? nullptr : kfFds.data(), static_cast<int>(kfFds.size()));
    
    if (preservedKey != nullptr) {
        env->ReleaseByteArrayElements(preservedKey, reinterpret_cast<jbyte*>(const_cast<unsigned char*>(preservedBytes)), JNI_ABORT);
    }
    env->ReleaseStringUTFChars(password, nativePass);
    if (!ok) {
        if (isUnlockCancelled(volId)) throwUnlockCancelledException(env);
        return nullptr;
    }

    {
        std::lock_guard<std::mutex> lock(volumes[volId].mutex);
        volumes[volId].fileSize = static_cast<uint64_t>(deviceSizeBytes);
    }

    jobjectArray result = nullptr;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            result = buildDirectoryListing(env, volId, nullptr);
        } else {
            LOGI("FATFS/NTFS Mount failed on USB volume %d", volId);
        }
    }
    return result;
}

extern "C" jint JNI_OnLoad(JavaVM* vm, void* reserved);

extern "C" const char *ntfs_libntfs_version(void) {
    return "vaultexplorer-ntfs3g-edge";
}
