#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <vector>

#include <unistd.h>

#include "ff.h"
#include "mbedtls/aes.h"
#include "mbedtls/platform_util.h"
#include "container_format.h"
#include "crypto/cascade.h"

extern "C" {
#include "volume.h"
#include <ext2fs/ext2fs.h>
}

struct NtfsStream;
struct ExtStream;

struct XtsContextPair {
    mbedtls_aes_xts_context dec;
    mbedtls_aes_xts_context enc;
    bool initialized = false;

    XtsContextPair() {
        mbedtls_aes_xts_init(&dec);
        mbedtls_aes_xts_init(&enc);
    }

    ~XtsContextPair() {
        mbedtls_aes_xts_free(&dec);
        mbedtls_aes_xts_free(&enc);
    }

    XtsContextPair(const XtsContextPair&) = delete;
    XtsContextPair& operator=(const XtsContextPair&) = delete;
};

// The single owner of state for one unlocked container.  Filesystem backends
// share this transport/crypto session but retain their own mounted handles.
struct VolumeState {
    std::mutex mutex;
    int fd = -1;
    uint64_t dataOffset = 0;
    uint64_t dataAreaLengthBytes = 0;
    bool isHiddenVolume = false;
    bool dataCtxInitialized = false;
    uint64_t fileSize = 0;
    bool fsMounted = false;
    bool isUsbSource = false;
    bool readOnly = false;
    uint64_t partitionStartSector = 0;
    int matchedCipherId = -1;
    int matchedHashId = -1;
    unsigned char* preservedDerivedKey = nullptr;
    size_t preservedDerivedKeyLen = 0;
    ContainerFormat containerFormat = ContainerFormat::kVeraCrypt;
    XtsContextPair luksXts;
    uint32_t luksSectorSize = 512;
    bool luksUsesGenericCipher = false;
    CascadeContext luksGenericCascade;
    CascadeContext cascade;
    // Opaque dis_context_t (dislocker's own opaque struct _dis_ctx*) for
    // BitLocker sessions -- void* rather than the real dislocker type so
    // this widely-included header never has to pull in dislocker's
    // generated headers. Only bitlocker_backend.cpp casts this back. See
    // bitlocker_backend.h for the ownership/lifecycle contract; freed in
    // reset(), not unmountVolume().
    void* disContext = nullptr;
    // Real fd bitlocker_backend.cpp hands to dislocker as DIS_OPT_VOLUME_PATH
    // (via /proc/self/fd/<this>). File-backed sessions alias VolumeState::fd
    // itself here (nothing extra to close). USB-backed sessions get a
    // distinct AppFuse-proxied fd obtained from Kotlin's
    // UsbBlockBridge.openBitlockerProxyFd() -- see bitlocker_backend.cpp's
    // header comment -- and it's THIS fd (not VolumeState::fd, which stays
    // -1 for USB sources) that bitlockerCloseVolume() must close.
    int bitlockerProxyFd = -1;
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

    VolumeState() = default;
    ~VolumeState() = default;
    VolumeState(const VolumeState&) = delete;
    VolumeState& operator=(const VolumeState&) = delete;

    void reset();
};

extern VolumeState volumes[FF_VOLUMES];
extern std::mutex slotAllocMutex;