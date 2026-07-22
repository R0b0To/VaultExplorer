// FatFs diskio hooks + per-sector crypto dispatch, plus the small mount-cache
// layer (ensureMounted/unmountVolume) that decides which of FAT/NTFS/ext a
// volume is and keeps it mounted across calls.
//
// This is the lowest layer of the native stack: FatFs calls disk_read/
// disk_write/disk_ioctl by convention (see diskio.h, from the vendored
// FatFs dependency), and every read/write of container ciphertext funnels
// through here regardless of which JNI entry point (jni/*_bridge.cpp)
// triggered it. Split out of the former vaultexplorer.cpp god-file because
// this is a distinct, self-contained concern (block-device transport +
// crypto) from JNI marshalling.

#include <cstring>
#include <cstdlib>
#include <memory>
#include <mutex>
#include <atomic>
#include <ctime>
#include <android/log.h>

#include "ff.h"
#include "diskio.h"
#include "mbedtls/aes.h"

#include "crypto/cascade.h"
#include "crypto/vc_header_layout.h"
#include "crypto/xts_tweak.h"
#include "container_format.h"
#include "container_utils.h"
#include "sector_batching.h"
#include "session_prepare.h"
#include "bitlocker_backend.h"
#include "ext_backend.h"
#include "filesystem_paths.h"
#include "ntfs_backend.h"
#include "volume_state.h"
#include "jni_callbacks.h"
#include "block_io.h"
#include "filesystems/stream_handles.h"
#include "virtual_block_device.h"

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

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

#define MAX_VOLUMES FF_VOLUMES

static constexpr uint64_t FALLBACK_SECTOR_COUNT_UNINITIALIZED = 1000000;

static bool _ext2ErrorTableInit = [](){
    initialize_ext2_error_table();
    return true;
}();

// ----------------------------------------------------------------====
// MOUNT CACHE HELPERS
// ----------------------------------------------------------------====

bool ensureMounted(int volId) {
    if (volId < 0 || volId >= MAX_VOLUMES) return false;
    auto& v = volumes[volId];
    if (v.fsMounted) return true;

    alignas(16) unsigned char probe[3 * 512];
    if (disk_read(static_cast<BYTE>(volId), probe, 0, 3) != RES_OK) {
        LOGI("ensureMounted: failed to read boot sector for volume %d", volId);
        return false;
    }
    unsigned char* decS = probe;

    if (decS[510] != 0x55 || decS[511] != 0xAA) {
        unsigned char* extSuperSector = probe + 2 * 512;
        if (extSuperSector[0x38] == 0x53 && extSuperSector[0x39] == 0xEF) {
            return mountExtVolume(volId);
        }
        LOGI("ensureMounted: invalid signature in boot sector for volume %d", volId);
        return false;
    }

    if (std::memcmp(&decS[3], "NTFS    ", 8) == 0) {
        v.fsType = VolumeState::FS_NTFS;
        LOGI("ensureMounted: detected NTFS on volume %d (readOnly=%d)", volId, v.readOnly ? 1 : 0);

        int* privVolId = new int(volId);
        struct ntfs_device* dev = ntfs_device_alloc("vaultexplorer", 0, &vExplorer_ntfs_ops, privVolId);
        if (!dev) {
            delete privVolId;
            return false;
        }

        const unsigned long mountFlags = v.readOnly ? NTFS_MNT_RDONLY : 0;
        v.ntfsVol = ntfs_device_mount(dev, mountFlags);
        if (!v.ntfsVol && !v.readOnly) {
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

void unmountVolume(int volId) {
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
            v.extBitmapsLoaded = false;
        }
        v.fsMounted = false;
        v.fsType = VolumeState::FS_UNKNOWN;
    }
    std::lock_guard<std::mutex> bufLock(v.ioBufMutex);
    v.ioBuf.reset();
    v.ioBufSize = 0;

    // The cache is keyed by physical block index only -- if a different
    // container/hidden-volume gets unlocked into this same slot on a later
    // mount, physical offsets can mean something entirely different. Drop
    // everything now rather than risk serving stale plaintext under a new
    // mount.
    std::lock_guard<std::mutex> cacheLock(v.decryptedBlockCacheMutex);
    v.decryptedBlockCache.clear();
}

// ----------------------------------------------------------------====
// INLINE HELPERS
// ----------------------------------------------------------------====

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

// Generic single-cipher XTS over a whole-block data unit (Serpent/Twofish --
// ciphers mbedTLS doesn't provide XTS mode for). Defined below, using
// crypto/xts_tweak.h's xtsMultiplyTweak() for the GF(2^128) tweak doubling.
// LUKS never needs ciphertext stealing, so dataLen is always a whole
// multiple of 16.
static void genericLuksXtsCrypt(const XtsLayerKey& layer, bool encrypt, size_t dataLen,
                                 const unsigned char tweakSeed[16],
                                 const unsigned char* in, unsigned char* out);

extern "C" DRESULT disk_read(BYTE pdrv, BYTE* buff, LBA_t sector, UINT count) {
    if (pdrv >= MAX_VOLUMES || !volumes[pdrv].dataCtxInitialized)
        return RES_NOTRDY;
    if (!volumes[pdrv].isUsbSource && volumes[pdrv].fd < 0)
        return RES_NOTRDY;
    if (count == 0) return RES_PARERR;

    // BitLocker: dislocker already owns the real physical I/O (via the virtual_io
    // callbacks), so the logic is the same: hand it the post-metadata logical
    // offset and it translates it automatically. -- none of the physicalRead + per-sector
    // cascade machinery below applies. `sector` here is already relative to
    // this volume's mounted filesystem (see basePhysical below for why),
    // which is exactly the convention bitlockerRead's logicalOffset expects.
    if (volumes[pdrv].containerFormat == ContainerFormat::kBitLocker) {
        const bool ok = bitlockerRead(pdrv, static_cast<uint64_t>(sector) * 512,
                                      buff, static_cast<size_t>(count) * 512);
        return ok ? RES_OK : RES_ERROR;
    }

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

        // Decrypted-range cache: a hit here skips both the physical USB read
        // AND the XTS/cascade decryption below entirely, since what's cached
        // is the fully-decrypted output for exactly this aligned physical
        // range. See io/decrypted_block_cache.h for why this is keyed by
        // exact (offset, length) match rather than sub-range splitting.
        const uint64_t cacheKeyOffset = alignedFirstPhysical * 512;
        {
            std::lock_guard<std::mutex> cacheLock(v.decryptedBlockCacheMutex);
            std::vector<unsigned char> cached(totalBytes);
            if (v.decryptedBlockCache.get(cacheKeyOffset, totalBytes, cached.data())) {
                std::memcpy(curBuf, cached.data() + copyOffset, copyBytes);
                continue;
            }
        }

        unsigned char* encBuf;
        bool usedPersistent = (totalBytes > sizeof(stackBuf));

        std::unique_lock<std::mutex> bufLock;
        if (usedPersistent) {
            bufLock = std::unique_lock<std::mutex>(v.ioBufMutex);
            encBuf = getVolIoBuf(v, totalBytes);
        } else {
            encBuf = stackBuf;
        }

        if (!physicalRead(pdrv, alignedFirstPhysical * 512, encBuf, totalBytes)) {
            return RES_ERROR;
        }

        // Decrypted output for the whole aligned range is assembled into
        // decryptedOut regardless of which branch below runs, so it can be
        // cached once at the end rather than duplicating the cache-populate
        // call three times (and risking one branch forgetting it).
        std::vector<unsigned char> decryptedOut(totalBytes);

        if (v.containerFormat == ContainerFormat::kVeraCrypt) {
            for (UINT i = 0; i < batch.count; i++) {
                const uint64_t physSector = firstPhysical + i;
                const uint64_t tweak = physSector - v.partitionStartSector;
                cascadeDecryptSector(v.cascade, tweak, encBuf + (i*512),
                                     decryptedOut.data() + copyOffset + (i * 512));
            }
            // VeraCrypt never needs multi-sector alignment (sectorsPerUnit
            // is always 1), so copyOffset is always 0 and decryptedOut is
            // fully populated by the loop above -- no gap to worry about.
        } else if (sectorsPerUnit <= 1) {
            for (UINT i = 0; i < batch.count; i++) {
                const uint64_t sectorNum = (firstPhysical + i) - v.partitionStartSector;
                unsigned char tweakBuf[16] = {0};
                for (int b = 0; b < 8; b++) tweakBuf[b] = (sectorNum >> (b * 8)) & 0xFF;
                if (v.luksUsesGenericCipher) {
                    genericLuksXtsCrypt(v.luksGenericCascade.layers[0], false, 512, tweakBuf,
                                         encBuf + (i * 512), decryptedOut.data() + copyOffset + (i * 512));
                } else {
                    mbedtls_aes_crypt_xts(&v.luksXts.dec, MBEDTLS_AES_DECRYPT, 512, tweakBuf,
                                           encBuf + (i * 512), decryptedOut.data() + copyOffset + (i * 512));
                }
            }
        } else {
            // Decrypt every full aligned unit directly into decryptedOut --
            // this branch already computes the full aligned range (that's
            // what alignedCount covers), so decryptedOut is fully populated
            // here without a separate copyOffset-relative write.
            for (uint64_t u = 0; u < alignedCount; u += sectorsPerUnit) {
                const uint64_t sectorTweak = alignedRelStart + u;
                unsigned char tweakBuf[16] = {0};
                for (int b = 0; b < 8; b++) tweakBuf[b] = (sectorTweak >> (b * 8)) & 0xFF;
                if (v.luksUsesGenericCipher) {
                    genericLuksXtsCrypt(v.luksGenericCascade.layers[0], false, luksUnit, tweakBuf,
                                         encBuf + (u * 512), decryptedOut.data() + (u * 512));
                } else {
                    mbedtls_aes_crypt_xts(&v.luksXts.dec, MBEDTLS_AES_DECRYPT, luksUnit, tweakBuf,
                                           encBuf + (u * 512), decryptedOut.data() + (u * 512));
                }
            }
        }

        std::memcpy(curBuf, decryptedOut.data() + copyOffset, copyBytes);

        {
            std::lock_guard<std::mutex> cacheLock(v.decryptedBlockCacheMutex);
            v.decryptedBlockCache.put(cacheKeyOffset, totalBytes, decryptedOut.data());
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

    // See the matching comment in disk_read: BitLocker bypasses this
    // function's physicalRead/cascade machinery entirely and hands off
    // straight to dislocker, which owns re-encrypting and writing back through
    // the same fd/USB transport internally.
    if (volumes[pdrv].containerFormat == ContainerFormat::kBitLocker) {
        const bool ok = bitlockerWrite(pdrv, static_cast<uint64_t>(sector) * 512,
                                       buff, static_cast<size_t>(count) * 512);
        return ok ? RES_OK : RES_ERROR;
    }

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
                for (int b = 0; b < 8; b++) tweakBuf[b] = (sectorTweak >> (b * 8)) & 0xFF;
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

        // Must run after every write that reaches physical storage: a cached
        // decrypted range from before this write would otherwise be served
        // back to any later disk_read for the same physical bytes (see the
        // invalidateRange contract in io/decrypted_block_cache.h). Done after
        // the write succeeds so a failed write leaves the still-accurate
        // cache entry alone instead of evicting it for no reason.
        {
            std::lock_guard<std::mutex> cacheLock(v.decryptedBlockCacheMutex);
            v.decryptedBlockCache.invalidateRange(alignedFirstPhysical * 512, totalBytes);
        }

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