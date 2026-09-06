#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <shared_mutex>
#include <vector>
#include <unistd.h>

#include "ff.h"
#undef min
#undef max

#include "mbedtls/platform_util.h"
#include "container_format.h"
#include "crypto/cascade.h"
#include "io/decrypted_block_cache.h"
#include "io/usb_block_cache.h"
#include "containers/composite_block_device.h"

extern "C" {
#include "volume.h"
#include <ext2fs/ext2fs.h>
}

struct NtfsStream;
struct ExtStream;

struct VolumeState {
    std::shared_mutex mutex;
    int fd = -1;
    uint64_t dataOffset = 0;
    uint64_t dataAreaLengthBytes = 0;
    bool isHiddenVolume = false;
    bool dataCtxInitialized = false;
    uint64_t fileSize = 0;
    bool fsMounted = false;
    bool isUsbSource = false;
    bool isCompositeSource = false;
    std::unique_ptr<CompositeBlockDevice> composite;
    bool readOnly = false;

    bool hiddenVolumeProtectionEnabled = false;
    uint64_t hiddenProtectedStart = 0;
    uint64_t hiddenProtectedEnd = 0;
    bool hiddenVolumeProtectionTriggered = false;
    uint64_t partitionStartSector = 0;
    int matchedCipherId = -1;
    int matchedHashId = -1;
    unsigned char* preservedDerivedKey = nullptr;
    size_t preservedDerivedKeyLen = 0;
    ContainerFormat containerFormat = ContainerFormat::kVeraCrypt;
    uint32_t luksSectorSize = 512;
    CascadeContext luksGenericCascade;
    CascadeContext cascade;

    void* disContext = nullptr;
    int bitlockerProxyFd = -1;
    void* bitlockerIoCtx = nullptr;

    enum class PlainBacking { kFlatFile, kVhdx, kVhd } plainBacking = PlainBacking::kFlatFile;
    void* plainImage = nullptr;

    FATFS fatfs{};
    ntfs_volume* ntfsVol = nullptr;
    ext2_filsys extFs = nullptr;
    bool extBitmapsLoaded = false;
    enum FsType { FS_UNKNOWN, FS_FATFS, FS_NTFS, FS_EXT } fsType = FS_UNKNOWN;
    std::vector<NtfsStream*> openNtfsStreams;
    std::vector<ExtStream*> openExtStreams;
    std::unique_ptr<unsigned char[]> ioBuf;
    size_t ioBufSize = 0;
    std::mutex ioBufMutex;
    std::vector<FIL*> openStreams;

    DecryptedBlockCache decryptedBlockCache;
    std::mutex decryptedBlockCacheMutex;

    // Production USB block cache with write coalescing and 128 KB safe chunking
    UsbBlockCache usbCache;

    VolumeState() = default;
    ~VolumeState() = default;
    VolumeState(const VolumeState&) = delete;
    VolumeState& operator=(const VolumeState&) = delete;

    void reset();
};

extern VolumeState volumes[FF_VOLUMES];
extern std::mutex slotAllocMutex;