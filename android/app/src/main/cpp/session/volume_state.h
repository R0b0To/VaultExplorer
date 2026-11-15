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
#include "crypto/luks_cipher.h"
#include "io/decrypted_block_cache.h"
#include "io/usb_block_cache.h"
#include "io/fd_write_buffer.h"
#include "containers/composite_block_device.h"

extern "C" {
#include "volume.h"
#if __has_include(<ext2fs/ext2fs.h>)
#include <ext2fs/ext2fs.h>
#else
typedef struct struct_ext2_filsys *ext2_filsys;
#endif
}

// e2fsprogs' ext2fs.h defines a function-like clamp() macro that collides with
// std::clamp in any libstdc++ <algorithm> included afterwards (see ext_backend.h).
#ifdef clamp
#undef clamp
#endif

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
    CascadeContext luksGenericCascade;   // legacy XTS-only context; superseded by luksCipher for all data-path crypto
    LuksCipherContext luksCipher;        // LUKS data-area cipher: XTS-128/256, CBC-plain/plain64/essiv:sha256
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

    // FatFs bookkeeping for filesystems/fat_backend.cpp. Both are only
    // touched while `mutex` is held.
    //  - fatActiveFiles: FIL objects a copy/extract/write-back keeps open
    //    across its lock-yield windows. While non-zero, nothing may
    //    remount the volume: f_mount() invalidates every open FIL.
    //  - fatNeedsRemount: an I/O-class FatFs error was seen, so the
    //    in-memory FATFS state (window, free-cluster counters) can't be
    //    trusted; it is rebuilt once the volume is idle.
    int fatActiveFiles = 0;
    bool fatNeedsRemount = false;

    DecryptedBlockCache decryptedBlockCache;
    std::mutex decryptedBlockCacheMutex;

    // Production USB block cache with write coalescing and 128 KB safe chunking
    UsbBlockCache usbCache;

    // Write-combining cache for file-descriptor backed volumes
    FdWriteBuffer fdWriteBuffer;

    VolumeState() = default;
    ~VolumeState() = default;
    VolumeState(const VolumeState&) = delete;
    VolumeState& operator=(const VolumeState&) = delete;

    void reset();
};

extern VolumeState volumes[FF_VOLUMES];
extern std::mutex slotAllocMutex;
// Serializes file-backed session registration/teardown with container
// mutations such as expansion. Acquire before any VolumeState::mutex.
extern std::mutex volumeLifecycleMutex;
// Encrypts/decrypts ONE LUKS logical sector ([unitLen] = the segment's sector_size,
// 512..4096) of a LUKS volume's data area. [sectorNum] is the dm-crypt IV/tweak
// counter in 512-byte units (physical 512-sector minus partitionStartSector).
// Dispatches on the volume's cipher (XTS-128/256, CBC with plain/plain64/essiv).
// On a context that was never initialised the output is zeroed rather than left
// holding unrelated bytes (cannot happen for a mounted LUKS volume).
inline void luksCryptUnit(const VolumeState& v, bool encrypt, uint64_t sectorNum, uint32_t unitLen,
                          const unsigned char* in, unsigned char* out) {
    if (!luksCipherCrypt(v.luksCipher, encrypt, sectorNum, unitLen, in, out, unitLen)) {
        for (uint32_t i = 0; i < unitLen; i++) out[i] = 0;
    }
}
