#include <cstring>
#include <cstdlib>
#include <memory>
#include <mutex>
#include <atomic>
#include <ctime>
#include <thread>
#include <future>
#include <vector>
#include <cstdarg>
#include <cstdio>
#include <android/log.h>

#include "ff.h"
#include "diskio.h"

#include "crypto/cascade.h"
#include "crypto/vc_header_layout.h"
#include "crypto/xts_tweak.h"
#include "crypto/thread_pool.h"
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

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

extern "C" {
#include "device.h"
#include "volume.h"
#include "inode.h"
#include "dir.h"
#include "attrib.h"
#include "layout.h"
#include "logging.h"
#include <ext2fs/ext2fs.h>
#include <ext2fs/ext2_io.h>
#include <et/com_err.h>
}

static int android_ntfs_log_handler(const char * /*function*/, const char * /*file*/,
                                    int /*line*/, u32 /*level*/, void * /*data*/,
                                    const char * /*format*/, va_list /*args*/) {
    return 0;
}

static bool _ntfsLoggingInitialized = []() {
    ntfs_log_set_handler(android_ntfs_log_handler);
    return true;
}();

#undef min
#undef max

#define MAX_VOLUMES FF_VOLUMES

static constexpr uint64_t FALLBACK_SECTOR_COUNT_UNINITIALIZED = 1000000;

static bool _ext2ErrorTableInit = [](){
    initialize_ext2_error_table();
    return true;
}();

bool ensureMounted(int volId) {
    if (volId < 0 || volId >= MAX_VOLUMES) return false;
    auto& v = volumes[volId];
    if (v.fsMounted) {
        if (v.fsType == VolumeState::FS_FATFS && v.fatfs.fs_type == 0) {
            LOGI("ensureMounted: FatFs fs_type is 0 on volume %d, attempting remount", volId);
            FRESULT fr = f_mount(&v.fatfs, drivePaths[volId], 1);
            if (fr == FR_OK) {
                return true;
            }
            v.fsMounted = false;
        } else if (v.fsType == VolumeState::FS_NTFS && !v.ntfsVol) {
            v.fsMounted = false;
        } else if (v.fsType == VolumeState::FS_EXT && !v.extFs) {
            v.fsMounted = false;
        } else {
            return true;
        }
    }

    const uint32_t ss = (v.luksSectorSize >= 512) ? v.luksSectorSize : 512;
    const UINT probeSectors = (ss >= 1536) ? 1 : static_cast<UINT>((1536 + ss - 1) / ss);
    const size_t probeBytes = static_cast<size_t>(probeSectors) * ss;
    std::vector<unsigned char> probe(probeBytes);

    if (disk_read(static_cast<BYTE>(volId), probe.data(), 0, probeSectors) != RES_OK) {
        LOGI("ensureMounted: failed to read boot sector for volume %d", volId);
        return false;
    }
    unsigned char* decS = probe.data();

    LOGI("ensureMounted[vol=%d] Sector 0 (first 16 bytes): %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X",
         volId, decS[0], decS[1], decS[2], decS[3], decS[4], decS[5], decS[6], decS[7],
         decS[8], decS[9], decS[10], decS[11], decS[12], decS[13], decS[14], decS[15]);

    LOGI("ensureMounted[vol=%d] Boot sig (510-511): 0x%02X 0x%02X (expected 0x55 0xAA)",
         volId, decS[510], decS[511]);

    unsigned char* extSuperSector = probe.data() + 1024;
    LOGI("ensureMounted[vol=%d] Ext4 magic (1080-1081): 0x%02X 0x%02X (expected 0x53 0xEF)",
         volId, extSuperSector[0x38], extSuperSector[0x39]);

    if (decS[510] != 0x55 || decS[511] != 0xAA) {
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
        if (!v.ntfsVol && !v.readOnly) {
            v.ntfsVol = ntfs_device_mount(dev, NTFS_MNT_RECOVER | NTFS_MNT_IGNORE_HIBERFILE);
        }
        if (!v.ntfsVol) {
            LOGI("ensureMounted: ntfs_device_mount failed on volume %d, errno=%d (%s)",
                 volId, errno, strerror(errno));
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
        LOGI("ensureMounted: FatFs f_mount failed on volume %d, FRESULT=%d", volId, (int)fr);
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

    std::lock_guard<std::mutex> cacheLock(v.decryptedBlockCacheMutex);
    v.decryptedBlockCache.clear();
}

static unsigned char* getVolIoBuf(VolumeState& v, size_t neededBytes) {
    if (v.ioBufSize < neededBytes) {
        v.ioBuf.reset(new unsigned char[neededBytes]);
        v.ioBufSize = neededBytes;
    }
    return v.ioBuf.get();
}

extern "C" DSTATUS disk_initialize(BYTE pdrv) { return 0; }
extern "C" DSTATUS disk_status(BYTE pdrv)     { return 0; }

static void genericLuksXtsCrypt(const XtsLayerKey& layer, bool encrypt, size_t dataLen,
                                const unsigned char tweakSeed[16],
                                const unsigned char* in, unsigned char* out);

template <typename WorkFn>
static void parallelCryptoLoop(uint32_t count, WorkFn&& workFn) {
    constexpr uint32_t kMinUnitsForParallel = 256;
    constexpr uint32_t kMaxChunks = 8;
    if (count < kMinUnitsForParallel) {
        for (uint32_t i = 0; i < count; i++) workFn(i);
        return;
    }

    const unsigned hwThreads = std::max(1u, std::thread::hardware_concurrency());
    const uint32_t numChunks = std::min({static_cast<uint32_t>(hwThreads), kMaxChunks,
                                          (count + kMinUnitsForParallel - 1) / kMinUnitsForParallel});
    const uint32_t chunkSize = (count + numChunks - 1) / numChunks;

    std::vector<std::future<void>> futures;
    futures.reserve(numChunks);
    for (uint32_t start = 0; start < count; start += chunkSize) {
        const uint32_t end = std::min(count, start + chunkSize);
        futures.push_back(ThreadPool::getInstance().enqueue([&workFn, start, end]() {
            for (uint32_t i = start; i < end; i++) workFn(i);
        }));
    }
    for (auto& f : futures) f.get();
}

extern "C" DRESULT disk_read(BYTE pdrv, BYTE* buff, LBA_t sector, UINT count) {
    if (pdrv >= MAX_VOLUMES || !volumes[pdrv].dataCtxInitialized)
        return RES_NOTRDY;
    if (!volumes[pdrv].isUsbSource && volumes[pdrv].fd < 0)
        return RES_NOTRDY;
    if (count == 0) return RES_PARERR;

    VolumeState& v = volumes[pdrv];
    const bool isLuks = (v.containerFormat != ContainerFormat::kVeraCrypt);
    const uint32_t luksUnit = (isLuks && v.luksSectorSize >= 512) ? v.luksSectorSize : 512;

    if (v.containerFormat == ContainerFormat::kBitLocker) {
        const bool ok = bitlockerRead(pdrv, static_cast<uint64_t>(sector) * luksUnit,
                                      buff, static_cast<size_t>(count) * luksUnit);
        return ok ? RES_OK : RES_ERROR;
    }

    constexpr size_t MAX_BYTES_PER_BATCH = 4 * 1024 * 1024;
    const uint32_t maxSectorsPerBatch = static_cast<uint32_t>(std::max<size_t>(1, MAX_BYTES_PER_BATCH / luksUnit));
    const auto batches = planSectorBatches(static_cast<uint32_t>(count), maxSectorsPerBatch);

    alignas(16) unsigned char stackBuf[65536];

    for (const auto& batch : batches) {
        const uint64_t batchStartSector = static_cast<uint64_t>(sector) + batch.startSector;
        BYTE* curBuf = buff + static_cast<size_t>(batch.startSector) * luksUnit;

        const uint64_t startByte = v.dataOffset + (batchStartSector * luksUnit);
        const size_t totalBytes = static_cast<size_t>(batch.count) * luksUnit;

        {
            std::lock_guard<std::mutex> cacheLock(v.decryptedBlockCacheMutex);
            if (v.decryptedBlockCache.getDirect(startByte, totalBytes, curBuf, 0, totalBytes)) {
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

        if (!physicalRead(pdrv, startByte, encBuf, totalBytes)) {
            return RES_ERROR;
        }

        std::unique_ptr<unsigned char[]> decryptedOut(new unsigned char[totalBytes]);

        if (v.containerFormat == ContainerFormat::kVeraCrypt) {
            parallelCryptoLoop(batch.count, [&](uint32_t i) {
                const uint64_t phys512Sector = (startByte / 512) + i;
                const uint64_t tweak = phys512Sector - v.partitionStartSector;
                cascadeDecryptSector(v.cascade, tweak, encBuf + (i * 512),
                                     decryptedOut.get() + (i * 512));
            });
        } else if (luksUnit == 512) {
            parallelCryptoLoop(batch.count, [&](uint32_t i) {
                const uint64_t phys512Sector = (startByte / 512) + i;
                const uint64_t sectorNum = phys512Sector - v.partitionStartSector;
                unsigned char tweakBuf[16] = {0};
                for (int b = 0; b < 8; b++) tweakBuf[b] = (sectorNum >> (b * 8)) & 0xFF;
                genericLuksXtsCrypt(v.luksGenericCascade.layers[0], false, 512, tweakBuf,
                                     encBuf + (i * 512), decryptedOut.get() + (i * 512));
            });
        } else {
            parallelCryptoLoop(batch.count, [&](uint32_t unitIdx) {
                const uint64_t unitByteOffset = startByte + (static_cast<uint64_t>(unitIdx) * luksUnit);
                const uint64_t phys512Sector = unitByteOffset / 512;
                const uint64_t sectorTweak = phys512Sector - v.partitionStartSector;
                unsigned char tweakBuf[16] = {0};
                for (int b = 0; b < 8; b++) tweakBuf[b] = (sectorTweak >> (b * 8)) & 0xFF;
                genericLuksXtsCrypt(v.luksGenericCascade.layers[0], false, luksUnit, tweakBuf,
                                     encBuf + (unitIdx * luksUnit), decryptedOut.get() + (unitIdx * luksUnit));
            });
        }

        std::memcpy(curBuf, decryptedOut.get(), totalBytes);

        {
            std::lock_guard<std::mutex> cacheLock(v.decryptedBlockCacheMutex);
            v.decryptedBlockCache.put(startByte, totalBytes, decryptedOut.get());
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
    const bool isLuks = (v.containerFormat != ContainerFormat::kVeraCrypt);
    const uint32_t luksUnit = (isLuks && v.luksSectorSize >= 512) ? v.luksSectorSize : 512;

    if (volumes[pdrv].containerFormat == ContainerFormat::kBitLocker) {
        const bool ok = bitlockerWrite(pdrv, static_cast<uint64_t>(sector) * luksUnit,
                                       buff, static_cast<size_t>(count) * luksUnit);
        return ok ? RES_OK : RES_ERROR;
    }

    constexpr size_t MAX_BYTES_PER_BATCH = 4 * 1024 * 1024;
    const uint32_t maxSectorsPerBatch = static_cast<uint32_t>(std::max<size_t>(1, MAX_BYTES_PER_BATCH / luksUnit));
    const auto batches = planSectorBatches(static_cast<uint32_t>(count), maxSectorsPerBatch);

    alignas(16) unsigned char stackBuf[65536];

    for (const auto& batch : batches) {
        const uint64_t batchStartSector = static_cast<uint64_t>(sector) + batch.startSector;
        const BYTE* curBuf = buff + static_cast<size_t>(batch.startSector) * luksUnit;

        const uint64_t startByte = v.dataOffset + (batchStartSector * luksUnit);
        const size_t totalBytes = static_cast<size_t>(batch.count) * luksUnit;

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
            parallelCryptoLoop(batch.count, [&](uint32_t i) {
                const uint64_t phys512Sector = (startByte / 512) + i;
                const uint64_t tweak = phys512Sector - v.partitionStartSector;
                cascadeEncryptSector(v.cascade, tweak, curBuf + (i * 512), encBuf + (i * 512));
            });
        } else if (luksUnit == 512) {
            parallelCryptoLoop(batch.count, [&](uint32_t i) {
                const uint64_t phys512Sector = (startByte / 512) + i;
                const uint64_t sectorNum = phys512Sector - v.partitionStartSector;
                unsigned char tweakBuf[16] = {0};
                for (int b = 0; b < 8; b++) tweakBuf[b] = (sectorNum >> (b * 8)) & 0xFF;
                genericLuksXtsCrypt(v.luksGenericCascade.layers[0], true, 512, tweakBuf,
                                     curBuf + (i * 512), encBuf + (i * 512));
            });
        } else {
            parallelCryptoLoop(batch.count, [&](uint32_t unitIdx) {
                const uint64_t unitByteOffset = startByte + (static_cast<uint64_t>(unitIdx) * luksUnit);
                const uint64_t phys512Sector = unitByteOffset / 512;
                const uint64_t sectorTweak = phys512Sector - v.partitionStartSector;
                unsigned char tweakBuf[16] = {0};
                for (int b = 0; b < 8; b++) tweakBuf[b] = (sectorTweak >> (b * 8)) & 0xFF;
                genericLuksXtsCrypt(v.luksGenericCascade.layers[0], true, luksUnit, tweakBuf,
                                     curBuf + (unitIdx * luksUnit), encBuf + (unitIdx * luksUnit));
            });
        }

        if (!physicalWrite(pdrv, startByte, encBuf, totalBytes)) return RES_ERROR;

        {
            std::lock_guard<std::mutex> cacheLock(v.decryptedBlockCacheMutex);
            v.decryptedBlockCache.invalidateRange(startByte, totalBytes);
        }
    }
    return RES_OK;
}

extern "C" DRESULT disk_ioctl(BYTE pdrv, BYTE cmd, void* buff) {
    if (pdrv >= MAX_VOLUMES) return RES_PARERR;
    const auto& v = volumes[pdrv];
    const uint32_t sectorSize = (v.luksSectorSize >= 512) ? v.luksSectorSize : 512;

    switch (cmd) {
        case CTRL_SYNC:
            return RES_OK;

        case GET_SECTOR_COUNT:
            if (v.dataAreaLengthBytes > 0) {
                *(LBA_t*)buff = static_cast<LBA_t>(v.dataAreaLengthBytes / sectorSize);
            } else if (v.fileSize > VC_DATA_AREA_OFFSET * 2) {
                *(LBA_t*)buff = static_cast<LBA_t>((v.fileSize - VC_DATA_AREA_OFFSET * 2) / sectorSize);
            } else {
                *(LBA_t*)buff = FALLBACK_SECTOR_COUNT_UNINITIALIZED;
            }
            return RES_OK;

        case GET_SECTOR_SIZE:
            *(WORD*)buff = static_cast<WORD>(sectorSize);
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