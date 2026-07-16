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
#include "crypto/xts_tweak.h"
#include "session_prepare.h"
#include "container_create.h"
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

struct ExtStream {
    ext2_file_t file = nullptr;
};

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

#define MAX_VOLUMES FF_VOLUMES


static constexpr size_t IO_BUFFER_SIZE          = 262144;   
static constexpr int    VC_KEY_MATERIAL_LEN     = 64;
static constexpr size_t MAX_DIR_ENTRIES         = 50000;
static constexpr size_t MAX_CHUNK_SIZE          = 64 * 1024 * 1024;
static constexpr uint64_t FALLBACK_SECTOR_COUNT_UNINITIALIZED = 1000000; 
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


// ----------------------------------------------------------------====
// PER-VOLUME STATE
// ----------------------------------------------------------------====

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
// ciphers mbedTLS doesn't provide XTS mode for). Defined below, using
// crypto/xts_tweak.h's xtsMultiplyTweak() for the GF(2^128) tweak doubling;
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


// See forward declaration near disk_read for rationale. Mirrors
// tryDecryptHeader's (session_prepare.cpp) per-block tweak/encrypt/decrypt
// loop, just parameterized on an arbitrary starting tweak seed (the LE
// sector-number buffer) instead of always starting from an all-zero seed.
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
        xtsMultiplyTweak(T);
    }
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
        listNtfsDirectory(volId, pathSuffix ? pathSuffix : "", results);
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

    clearUnlockCancellation(volId);

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


    bool mountOk;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        mountOk = ensureMounted(volId);
    }

    if (preservedKey != nullptr) {
        env->ReleaseByteArrayElements(preservedKey, reinterpret_cast<jbyte*>(const_cast<unsigned char*>(preservedBytes)), JNI_ABORT);
    }
    env->ReleaseStringUTFChars(password, nativePass);

    if (!mountOk) {
        LOGI("FATFS/NTFS Mount failed on volume %d", volId);
        return nullptr;
    }

    // Empty (non-null) array — preserves the existing "null == AUTH_FAIL"
    jclass strClass = env->FindClass("java/lang/String");
    return env->NewObjectArray(0, strClass, nullptr);
}

extern "C" JNIEXPORT void JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_requestCancelUnlockNative(
        JNIEnv*, jobject, jint volId) {
    requestUnlockCancellation(volId);
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
        jint containerFormat, jint cipherId, jint hashId, jintArray keyfileFds) {

    std::vector<int> kfFds = extractKeyfileFds(env, keyfileFds);
    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    const char* nativeFS   = env->GetStringUTFChars(fileSystem, nullptr);

    bool success;
    if (containerFormat == 1 || containerFormat == 2) {
        // 1 = LUKS1, 2 = LUKS2 — see ContainerFormat (container_format.h).
        success = createLuksContainer(fd, nativePass, pim, static_cast<int64_t>(sizeBytes),
                                      nativeFS, containerFormat, cipherId, hashId,
                                      kfFds.empty() ? nullptr : kfFds.data(),
                                      static_cast<int>(kfFds.size()));
    } else {
        success = createContainer(fd, nativePass, pim, static_cast<int64_t>(sizeBytes),
                                  nativeFS, cipherId, hashId,
                                  kfFds.empty() ? nullptr : kfFds.data(),
                                  static_cast<int>(kfFds.size()));
    }

    env->ReleaseStringUTFChars(password, nativePass);
    env->ReleaseStringUTFChars(fileSystem, nativeFS);

    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_createContainerWithHiddenNative(
        JNIEnv* env, jobject,
        jint fd, jstring outerPassword, jstring hiddenPassword,
        jint outerPim, jint hiddenPim, jlong sizeBytes, jstring outerFileSystem, jstring hiddenFileSystem,
        jlong hiddenSizeBytes,
        jint outerCipherId, jint outerHashId,
        jint hiddenCipherId, jint hiddenHashId,
        jintArray outerKeyfileFds, jintArray hiddenKeyfileFds) {

    std::vector<int> outerKfFds = extractKeyfileFds(env, outerKeyfileFds);
    std::vector<int> hiddenKfFds = extractKeyfileFds(env, hiddenKeyfileFds);
    
    const char* nativeOuterPass = env->GetStringUTFChars(outerPassword, nullptr);
    const char* nativeHiddenPass = env->GetStringUTFChars(hiddenPassword, nullptr);
    const char* nativeOuterFS   = env->GetStringUTFChars(outerFileSystem, nullptr);
    const char* nativeHiddenFS   = env->GetStringUTFChars(hiddenFileSystem, nullptr);

    bool success = createContainerWithHidden(fd, nativeOuterPass, nativeHiddenPass, outerPim, hiddenPim, static_cast<int64_t>(sizeBytes),
                                             nativeOuterFS, nativeHiddenFS, static_cast<int64_t>(hiddenSizeBytes),
                                             outerCipherId, outerHashId,
                                             hiddenCipherId, hiddenHashId,
                                             outerKfFds.empty() ? nullptr : outerKfFds.data(), static_cast<int>(outerKfFds.size()),
                                             hiddenKfFds.empty() ? nullptr : hiddenKfFds.data(), static_cast<int>(hiddenKfFds.size()));

    env->ReleaseStringUTFChars(outerPassword, nativeOuterPass);
    env->ReleaseStringUTFChars(hiddenPassword, nativeHiddenPass);
    env->ReleaseStringUTFChars(outerFileSystem, nativeOuterFS);
    env->ReleaseStringUTFChars(hiddenFileSystem, nativeHiddenFS);

    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_changeContainerPasswordNative(
        JNIEnv* env, jobject,
        jint fd, jstring oldPassword, jstring newPassword,
        jint oldPim, jint newPim,
        jint cipherId, jint hashId, jintArray oldKeyfileFds, jintArray newKeyfileFds) {

    std::vector<int> oldKfFds = extractKeyfileFds(env, oldKeyfileFds);
    std::vector<int> newKfFds = extractKeyfileFds(env, newKeyfileFds);
    
    const char* nativeOldPass = env->GetStringUTFChars(oldPassword, nullptr);
    const char* nativeNewPass = env->GetStringUTFChars(newPassword, nullptr);

    bool success = changeContainerPassword(fd, nativeOldPass, nativeNewPass, oldPim, newPim,
                                           cipherId, hashId,
                                           oldKfFds.empty() ? nullptr : oldKfFds.data(), static_cast<int>(oldKfFds.size()),
                                           newKfFds.empty() ? nullptr : newKfFds.data(), static_cast<int>(newKfFds.size()));

    env->ReleaseStringUTFChars(oldPassword, nativeOldPass);
    env->ReleaseStringUTFChars(newPassword, nativeNewPass);

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

// ── EXT2/3/4 rename support ──────────────────────────────────────────────
struct ExtDotDotFixupContext {
    ext2_ino_t newParentIno;
};

static int extDotDotFixupCallback(ext2_ino_t, int, struct ext2_dir_entry* dirent,
                                   int, int, char*, void* priv) {
    auto* ctx = static_cast<ExtDotDotFixupContext*>(priv);
    if (ext2fs_dirent_name_len(dirent) == 2 &&
        dirent->name[0] == '.' && dirent->name[1] == '.') {
        dirent->inode = ctx->newParentIno;
        return DIRENT_CHANGED;
    }
    return 0;
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
            } else if (v.fsType == VolumeState::FS_EXT) {
                const std::string oldFull(nativeOld);
                const std::string newFull(nativeNew);
                const size_t oldSlash = oldFull.find_last_of('/');
                const std::string oldParentPath = oldSlash == std::string::npos ? "" : oldFull.substr(0, oldSlash);
                const std::string oldName = oldSlash == std::string::npos ? oldFull : oldFull.substr(oldSlash + 1);
                const size_t newSlash = newFull.find_last_of('/');
                const std::string newParentPath = newSlash == std::string::npos ? "" : newFull.substr(0, newSlash);
                const std::string newName = newSlash == std::string::npos ? newFull : newFull.substr(newSlash + 1);

                ext2_ino_t oldParentIno = 0, newParentIno = 0, srcIno = 0;
                if (!oldName.empty() && !newName.empty() &&
                    extResolvePath(v.extFs, oldParentPath, &oldParentIno) &&
                    extResolvePath(v.extFs, newParentPath, &newParentIno) &&
                    extResolvePath(v.extFs, oldFull, &srcIno)) {

                    struct ext2_inode srcInode{};
                    const bool isDir = ext2fs_read_inode(v.extFs, srcIno, &srcInode) == 0 &&
                                        LINUX_S_ISDIR(srcInode.i_mode);
                    const int fileType = isDir ? EXT2_FT_DIR : EXT2_FT_REG_FILE;

                    ext2_ino_t destIno = 0;
                    if (extResolvePath(v.extFs, newFull, &destIno) && destIno != srcIno) {
                        if (ext2fs_unlink(v.extFs, newParentIno, newName.c_str(), destIno, 0) == 0) {
                            struct ext2_inode destInode{};
                            if (ext2fs_read_inode(v.extFs, destIno, &destInode) == 0 && destInode.i_links_count) {
                                --destInode.i_links_count;
                                ext2fs_write_inode(v.extFs, destIno, &destInode);
                            }
                        }
                    }

                    errcode_t linkErr = ext2fs_link(v.extFs, newParentIno, newName.c_str(), srcIno, fileType);
                    if (linkErr == EXT2_ET_DIR_NO_SPACE) {
                        if (ext2fs_expand_dir(v.extFs, newParentIno) == 0) {
                            linkErr = ext2fs_link(v.extFs, newParentIno, newName.c_str(), srcIno, fileType);
                        }
                    }

                    if (linkErr == 0) {
                        if (ext2fs_unlink(v.extFs, oldParentIno, oldName.c_str(), srcIno, 0) == 0) {
                            success = true;
                            if (isDir && oldParentIno != newParentIno) {
                                ExtDotDotFixupContext ctx{newParentIno};
                                ext2fs_dir_iterate2(v.extFs, srcIno, 0, nullptr, extDotDotFixupCallback, &ctx);

                                struct ext2_inode oldParentInode{};
                                if (ext2fs_read_inode(v.extFs, oldParentIno, &oldParentInode) == 0 &&
                                    oldParentInode.i_links_count) {
                                    --oldParentInode.i_links_count;
                                    ext2fs_write_inode(v.extFs, oldParentIno, &oldParentInode);
                                }
                                struct ext2_inode newParentInode{};
                                if (ext2fs_read_inode(v.extFs, newParentIno, &newParentInode) == 0) {
                                    ++newParentInode.i_links_count;
                                    ext2fs_write_inode(v.extFs, newParentIno, &newParentInode);
                                }
                            }
                        } else {
                            ext2fs_unlink(v.extFs, newParentIno, newName.c_str(), srcIno, 0);
                        }
                    }

                    if (success) ext2fs_flush(v.extFs);
                }
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

    clearUnlockCancellation(volId);

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

    // See the matching comment in unlockAndListNative — mount only, defer
    // the directory walk to a separate listDirectory("") call.
    bool mountOk;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        mountOk = ensureMounted(volId);
    }
    if (!mountOk) {
        LOGI("FATFS/NTFS Mount failed on USB volume %d", volId);
        return nullptr;
    }

    jclass strClass = env->FindClass("java/lang/String");
    return env->NewObjectArray(0, strClass, nullptr);
}

extern "C" jint JNI_OnLoad(JavaVM* vm, void* reserved);

extern "C" const char *ntfs_libntfs_version(void) {
    return "vaultexplorer-ntfs3g-edge";
}