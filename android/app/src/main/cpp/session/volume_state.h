#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <shared_mutex>
#include <vector>

#include <unistd.h>

#include "ff.h"
#include "mbedtls/platform_util.h"
#include "container_format.h"
#include "crypto/cascade.h"
#include "io/decrypted_block_cache.h"

extern "C" {
#include "volume.h"
#include <ext2fs/ext2fs.h>
}

struct NtfsStream;
struct ExtStream;

// The single owner of state for one unlocked container.  Filesystem backends
// share this transport/crypto session but retain their own mounted handles.
//
// `mutex` is a reader-writer lock (std::shared_mutex), not a plain mutex:
// operations that only read the mounted filesystem or read-only scalar
// fields (directory listing, file/folder size, chunked reads, free-space
// queries, matched-cipher/hash/format/offset getters, session/read-only
// status checks) take it shared via std::shared_lock, so browsing/viewing
// work can proceed concurrently across threads instead of serializing
// behind a single exclusive lock. Anything that mutates VolumeState fields
// or the mounted filesystem's on-disk structures -- unlock/lock/session
// lifecycle, container creation, write/delete/rename/create/copy-into,
// setLastModifiedTime, BitLocker session setup/teardown -- must keep taking
// it exclusive via std::unique_lock, exactly where a std::lock_guard was
// used before this type changed.
//
// This is NOT the same thing as mounting two independent FATFS/ntfs_volume/
// ext2_filsys instances over the same decrypted block device: there is
// still exactly one mounted filesystem handle per volume slot, and this
// lock is what keeps concurrent readers safe *against* the single writer
// (shared readers block a writer and vice versa; readers never block other
// readers). A second independent mount instance sharing the same
// VolumeState::decryptedBlockCache and physical fd would not be safe under
// any locking scheme, reader-writer or otherwise -- see the comment on
// decryptedBlockCache below and io/decrypted_block_cache.h's own header.
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
    // Opaque IoContext* (bitlocker_backend.cpp's internal dis_virtual_io_t
    // user_data struct) for BitLocker sessions -- void* for the same reason
    // disContext is, above. Previously this was allocated with `new` in
    // prepare*BitLockerSession and never freed anywhere (a small per-unlock
    // leak, harmless for a plain file/USB fd but not for a VHDX- or
    // VHD-backed session, whose IoContext also owns a VhdxImage/VhdImage
    // holding the whole Block Allocation Table in memory -- see
    // vhdx_image.h / vhd_image.h). Freed in bitlockerCloseVolume(), same
    // lifecycle spot as disContext.
    void* bitlockerIoCtx = nullptr;
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

    // Decrypted-block cache for disk_read/disk_write (see
    // io/decrypted_block_cache.h). Guarded by its own mutex rather than the
    // top-level `mutex` above: the cache is only ever touched from within
    // disk_read/disk_write's own per-batch buffer handling, which already
    // has narrower locking (ioBufMutex) for the same reason -- avoid
    // serializing unrelated volume operations (directory listings, other
    // files' metadata lookups) behind whatever a single read/write happens
    // to be doing.
    DecryptedBlockCache decryptedBlockCache;
    std::mutex decryptedBlockCacheMutex;

    VolumeState() = default;
    ~VolumeState() = default;
    VolumeState(const VolumeState&) = delete;
    VolumeState& operator=(const VolumeState&) = delete;

    void reset();
};

extern VolumeState volumes[FF_VOLUMES];
extern std::mutex slotAllocMutex;