#include "ntfs_backend.h"

#include <atomic>
#include <cerrno>
#include <cstring>
#include <cstdlib>
#include <memory>
#include <sys/stat.h>
#include <unistd.h>

extern "C" {
#include "device.h"
#include "inode.h"
#include "dir.h"
}

#include "block_io.h"
#include "crypto/cascade.h"
#include "volume_state.h"
#include "bitlocker_backend.h"

namespace {

constexpr int kMaxVolumes = FF_VOLUMES;

std::atomic<int64_t> ntfsDevicePositions[kMaxVolumes];
const bool kNtfsDevicePositionsInitialized = []() {
    for (auto& position : ntfsDevicePositions) position.store(0);
    return true;
}();

int ntfsVolumeId(const ntfs_device* device) {
    if (device->d_private) return *static_cast<const int*>(device->d_private);
    // mkntfs receives a synthetic "ve<N>" device name and uses these same
    // operations without a private context.
    return (device->d_name && std::strncmp(device->d_name, "ve", 2) == 0)
        ? std::atoi(device->d_name + 2) : -1;
}

int ntfsStat(ntfs_device* device, struct stat* statBuffer) {
    const int volumeId = ntfsVolumeId(device);
    if (volumeId < 0 || volumeId >= kMaxVolumes) {
        errno = ENODEV;
        return -1;
    }
    if (!device->d_private) {
        std::memset(statBuffer, 0, sizeof(*statBuffer));
        statBuffer->st_size = volumes[volumeId].dataAreaLengthBytes;
        statBuffer->st_mode = S_IFBLK | 0660;
        return 0;
    }
    if (volumes[volumeId].fd >= 0) return fstat(volumes[volumeId].fd, statBuffer);
    std::memset(statBuffer, 0, sizeof(*statBuffer));
    statBuffer->st_size = volumes[volumeId].fileSize;
    statBuffer->st_mode = S_IFBLK | 0660;
    return 0;
}

int ntfsOpen(ntfs_device* device, int) {
    const int volumeId = ntfsVolumeId(device);
    if (volumeId >= 0 && volumeId < kMaxVolumes)
        ntfsDevicePositions[volumeId].store(0, std::memory_order_relaxed);
    return 0;
}

int ntfsClose(ntfs_device*) { return 0; }

s64 ntfsSeek(ntfs_device* device, s64 offset, int whence) {
    const int volumeId = ntfsVolumeId(device);
    if (volumeId < 0 || volumeId >= kMaxVolumes) return -1;

    s64 base = 0;
    switch (whence) {
        case SEEK_SET: break;
        case SEEK_CUR:
            base = ntfsDevicePositions[volumeId].load(std::memory_order_relaxed);
            break;
        case SEEK_END: {
            struct stat statBuffer{};
            if (ntfsStat(device, &statBuffer) != 0) return -1;
            base = static_cast<s64>(statBuffer.st_size);
            break;
        }
        default: return -1;
    }
    const s64 newPosition = base + offset;
    if (newPosition < 0) return -1;
    ntfsDevicePositions[volumeId].store(newPosition, std::memory_order_relaxed);
    return newPosition;
}

class AlignedBuffer {
    void* ptr = nullptr;
    size_t capacity = 0;
public:
    ~AlignedBuffer() { std::free(ptr); }
    unsigned char* get(size_t size) {
        if (capacity < size) {
            std::free(ptr);
            if (posix_memalign(&ptr, 16, size) != 0) {
                ptr = nullptr;
                capacity = 0;
                return nullptr;
            }
            capacity = size;
        }
        return static_cast<unsigned char*>(ptr);
    }
};

s64 ntfsPread(ntfs_device* device, void* buffer, s64 count, s64 offset) {
    if (count <= 0 || offset < 0) return count == 0 ? 0 : -1;
    const int volumeId = ntfsVolumeId(device);
    if (volumeId < 0 || volumeId >= kMaxVolumes) return -1;
    VolumeState& volume = volumes[volumeId];

    const uint64_t startByte = static_cast<uint64_t>(offset);
    const uint64_t byteCount = static_cast<uint64_t>(count);
    if (startByte > volume.dataAreaLengthBytes || byteCount > volume.dataAreaLengthBytes - startByte)
        return -1;

    // BitLocker: bitlockerRead's logicalOffset uses the exact same
    // dataAreaLengthBytes-relative convention as startByte here, so this is
    // a direct hand-off -- no sector alignment or cascade decrypt needed,
    // dislocker does both internally via the dis_context_t from unlock time.
    if (volume.containerFormat == ContainerFormat::kBitLocker) {
        return bitlockerRead(volumeId, startByte, static_cast<unsigned char*>(buffer), byteCount)
            ? count : -1;
    }

    const uint64_t startSector = startByte / 512;
    const uint64_t endSector = (startByte + byteCount + 511) / 512;
    const uint32_t sectorCount = static_cast<uint32_t>(endSector - startSector);
    const uint64_t physicalStartSector = volume.dataOffset / 512 + startSector;
    const size_t transferBytes = static_cast<size_t>(sectorCount) * 512;

    thread_local AlignedBuffer tlsEncrypted;
    thread_local AlignedBuffer tlsPlaintext;

    unsigned char* encrypted = tlsEncrypted.get(transferBytes);
    if (!encrypted) return -1;
    
    if (!physicalRead(volumeId, physicalStartSector * 512, encrypted, transferBytes)) return -1;

    unsigned char* plaintext = tlsPlaintext.get(transferBytes);
    if (!plaintext) return -1;
    
    for (uint32_t i = 0; i < sectorCount; ++i) {
        const uint64_t tweak = physicalStartSector + i - volume.partitionStartSector;
        cascadeDecryptSector(volume.cascade, tweak, encrypted + i * 512, plaintext + i * 512);
    }

    std::memcpy(buffer, plaintext + startByte % 512, transferBytes == 0 ? 0 : byteCount);
    return count;
}

s64 ntfsPwrite(ntfs_device* device, const void* buffer, s64 count, s64 offset) {
    if (count <= 0 || offset < 0) return count == 0 ? 0 : -1;
    const int volumeId = ntfsVolumeId(device);
    if (volumeId < 0 || volumeId >= kMaxVolumes) return -1;
    VolumeState& volume = volumes[volumeId];

    const uint64_t startByte = static_cast<uint64_t>(offset);
    const uint64_t byteCount = static_cast<uint64_t>(count);
    if (startByte > volume.dataAreaLengthBytes || byteCount > volume.dataAreaLengthBytes - startByte)
        return -1;

    // See the matching comment in ntfsPread.
    if (volume.containerFormat == ContainerFormat::kBitLocker) {
        return bitlockerWrite(volumeId, startByte, static_cast<const unsigned char*>(buffer), byteCount)
            ? count : -1;
    }

    const uint64_t startSector = startByte / 512;
    const uint64_t endSector = (startByte + byteCount + 511) / 512;
    const uint32_t sectorCount = static_cast<uint32_t>(endSector - startSector);
    const uint64_t physicalStartSector = volume.dataOffset / 512 + startSector;
    const size_t transferBytes = static_cast<size_t>(sectorCount) * 512;

    thread_local AlignedBuffer tlsSectors;
    unsigned char* sectors = tlsSectors.get(transferBytes);
    if (!sectors) return -1;

    const bool partialTransfer = startByte % 512 != 0 || byteCount % 512 != 0;
    if (partialTransfer) {
        thread_local AlignedBuffer tlsEncrypted;
        unsigned char* encrypted = tlsEncrypted.get(transferBytes);
        if (!encrypted) return -1;
        
        if (!physicalRead(volumeId, physicalStartSector * 512, encrypted, transferBytes)) return -1;
        for (uint32_t i = 0; i < sectorCount; ++i) {
            const uint64_t tweak = physicalStartSector + i - volume.partitionStartSector;
            cascadeDecryptSector(volume.cascade, tweak, encrypted + i * 512, sectors + i * 512);
        }
    }
    std::memcpy(sectors + startByte % 512, buffer, byteCount);

    thread_local AlignedBuffer tlsEncryptedOut;
    unsigned char* encryptedOut = tlsEncryptedOut.get(transferBytes);
    if (!encryptedOut) return -1;
    for (uint32_t i = 0; i < sectorCount; ++i) {
        const uint64_t tweak = physicalStartSector + i - volume.partitionStartSector;
        cascadeEncryptSector(volume.cascade, tweak, sectors + i * 512, encryptedOut + i * 512);
    }
    if (!physicalWrite(volumeId, physicalStartSector * 512, encryptedOut, transferBytes)) return -1;
    return count;
}

s64 ntfsRead(ntfs_device* device, void* buffer, s64 count) {
    const int volumeId = ntfsVolumeId(device);
    if (volumeId < 0 || volumeId >= kMaxVolumes || count <= 0) return 0;
    const s64 position = ntfsDevicePositions[volumeId].load(std::memory_order_relaxed);
    const s64 got = ntfsPread(device, buffer, count, position);
    if (got > 0) ntfsDevicePositions[volumeId].fetch_add(got, std::memory_order_relaxed);
    return got;
}

s64 ntfsWrite(ntfs_device* device, const void* buffer, s64 count) {
    const int volumeId = ntfsVolumeId(device);
    if (volumeId < 0 || volumeId >= kMaxVolumes || count <= 0) return 0;
    const s64 position = ntfsDevicePositions[volumeId].load(std::memory_order_relaxed);
    const s64 written = ntfsPwrite(device, buffer, count, position);
    if (written > 0) ntfsDevicePositions[volumeId].fetch_add(written, std::memory_order_relaxed);
    return written;
}

int ntfsSync(ntfs_device* device) {
    const int volumeId = ntfsVolumeId(device);
    if (volumeId >= 0 && volumeId < kMaxVolumes && volumes[volumeId].fd >= 0)
        fsync(volumes[volumeId].fd);
    return 0;
}

int ntfsIoctl(ntfs_device* device, unsigned long request, void* argument) {
    const int volumeId = ntfsVolumeId(device);
    if (volumeId < 0 || volumeId >= kMaxVolumes) { errno = ENODEV; return -1; }
    switch (request) {
        case 0x1268: // BLKSSZGET
            *static_cast<int*>(argument) = 512;
            return 0;
        case 0x1260: // BLKGETSIZE
            *static_cast<unsigned long*>(argument) = volumes[volumeId].dataAreaLengthBytes / 512;
            return 0;
        case 0x80041272: // BLKGETSIZE64 (32-bit size_t encoding)
        case 0x80081272: // BLKGETSIZE64 (64-bit size_t encoding)
            *static_cast<uint64_t*>(argument) = volumes[volumeId].dataAreaLengthBytes;
            return 0;
        default:
            errno = EOPNOTSUPP;
            return -1;
    }
}

struct NtfsSizeContext {
    uint64_t totalSize = 0;
    ntfs_volume* volume;
};

int recursiveSizeEntry(void* directory, const ntfschar* name, const int nameLength,
                       const int nameType, const s64, const MFT_REF reference,
                       const unsigned) {
    auto* context = static_cast<NtfsSizeContext*>(directory);
    if (nameType == FILE_NAME_DOS) return 0;
    char* utf8Name = nullptr;
    const int utf8Length = ntfs_ucstombs(name, nameLength, &utf8Name, 0);
    if (utf8Length < 0 || !utf8Name) { if (utf8Name) free(utf8Name); return 0; }
    std::string entryName(utf8Name, utf8Length);
    free(utf8Name);
    if (entryName == "." || entryName == "..") return 0;
    if (entryName == "System Volume Information" || entryName == "$MFT" ||
        entryName == "$MFTMirr" || entryName == "$LogFile" || entryName == "$Volume" ||
        entryName == "$AttrDef" || entryName == "$Bitmap" || entryName == "$Boot" ||
        entryName == "$BadClus" || entryName == "$Secure" || entryName == "$UpCase" ||
        entryName == "$Extend" || entryName == "$RECYCLE.BIN") return 0;

    ntfs_inode* inode = ntfs_inode_open(context->volume, reference);
    if (!inode) return 0;
    if (inode->mrec->flags & MFT_RECORD_IS_DIRECTORY) {
        s64 position = 0;
        ntfs_readdir(inode, &position, context, recursiveSizeEntry);
    } else {
        context->totalSize += inode->data_size;
    }
    ntfs_inode_close(inode);
    return 0;
}

// Non-recursive directory-listing counterpart to recursiveSizeEntry above:
// same metadata-filtering rules, but reports the immediate children of one
// directory as "name|size|mtime" strings instead of summing file sizes.
// Backs listNtfsDirectory() below, which is buildDirectoryListing()'s only
// NTFS entry point (moved out of vaultexplorer.cpp).
struct NtfsFilldirContext {
    std::vector<std::string>* results;
    ntfs_volume* vol;
};

int ntfsFilldir(void* dirent, const ntfschar* name, const int nameLength,
                const int nameType, const s64, const MFT_REF reference,
                const unsigned) {
    auto* context = static_cast<NtfsFilldirContext*>(dirent);
    if (nameType == FILE_NAME_DOS) return 0;

    char* utf8Name = nullptr;
    const int utf8Length = ntfs_ucstombs(name, nameLength, &utf8Name, 0);
    if (utf8Length < 0 || !utf8Name) { if (utf8Name) free(utf8Name); return 0; }
    std::string nameStr(utf8Name, utf8Length);
    free(utf8Name);

    if (nameStr == "." || nameStr == "..") return 0;

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

    ntfs_inode* ni = ntfs_inode_open(context->vol, reference);
    if (!ni) return 0;

    uint64_t size = 0;
    uint64_t ts = 0;
    const bool isDir = (ni->mrec->flags & MFT_RECORD_IS_DIRECTORY) != 0;
    if (!isDir) size = ni->data_size;

    const uint64_t ntfsTime = ni->last_data_change_time;
    if (ntfsTime > 116444736000000000ULL) {
        ts = (ntfsTime - 116444736000000000ULL) / 10000000ULL;
    }

    ntfs_inode_close(ni);

    if (isDir) {
        context->results->push_back("[DIR] " + nameStr + "|0|" + std::to_string(ts));
    } else {
        context->results->push_back(nameStr + "|" + std::to_string(size) + "|" + std::to_string(ts));
    }
    return 0;
}

} // namespace

extern "C" ntfs_device_operations vExplorer_ntfs_ops = {
    ntfsOpen,
    ntfsClose,
    ntfsSeek,
    ntfsRead,
    ntfsWrite,
    ntfsPread,
    ntfsPwrite,
    ntfsSync,
    ntfsStat,
    ntfsIoctl
};

uint64_t recursiveNtfsFolderSize(int volumeId, const std::string& path) {
    ntfs_volume* volume = volumes[volumeId].ntfsVol;
    if (!volume) return 0;
    ntfs_inode* directory = (path.empty() || path == "/")
        ? ntfs_inode_open(volume, FILE_root)
        : ntfs_pathname_to_inode(volume, nullptr, ("/" + path).c_str());
    if (!directory) return 0;
    s64 position = 0;
    NtfsSizeContext context{0, volume};
    ntfs_readdir(directory, &position, &context, recursiveSizeEntry);
    ntfs_inode_close(directory);
    return context.totalSize;
}

bool listNtfsDirectory(int volumeId, const std::string& pathSuffix,
                       std::vector<std::string>& results) {
    if (volumeId < 0 || volumeId >= kMaxVolumes) return false;
    ntfs_volume* volume = volumes[volumeId].ntfsVol;
    if (!volume) return false;

    ntfs_inode* dirInode = (pathSuffix.empty() || pathSuffix == "/")
        ? ntfs_inode_open(volume, FILE_root)
        : ntfs_pathname_to_inode(volume, nullptr, ("/" + pathSuffix).c_str());
    if (!dirInode) return false;

    s64 position = 0;
    NtfsFilldirContext context{&results, volume};
    ntfs_readdir(dirInode, &position, &context, ntfsFilldir);
    ntfs_inode_close(dirInode);
    return true;
}

ntfs_inode* createNtfsFile(ntfs_volume* volume, const std::string& path) {
    const size_t slash = path.find_last_of('/');
    std::string parentPath = path.substr(0, slash);
    const std::string name = path.substr(slash + 1);
    if (parentPath.empty()) parentPath = "/";
    ntfs_inode* parent = ntfs_pathname_to_inode(volume, nullptr, parentPath.c_str());
    if (!parent) return nullptr;

    ntfschar* unicodeName = nullptr;
    const int unicodeLength = ntfs_mbstoucs(name.c_str(), &unicodeName);
    ntfs_inode* created = nullptr;
    if (unicodeLength >= 0) {
        created = ntfs_create(parent, 0, unicodeName, unicodeLength, S_IFREG);
        free(unicodeName);
    }
    ntfs_inode_close(parent);
    return created;
}

// Version string NTFS-3G's own code queries at a couple of internal
// call sites (we link its sources directly rather than the shared library,
// so this symbol has to come from somewhere in our binary). Relocated here
// from the former vaultexplorer.cpp god-file since it's NTFS-3G glue, not
// JNI or session logic.
extern "C" const char *ntfs_libntfs_version(void) {
    return "vaultexplorer-ntfs3g-edge";
}
