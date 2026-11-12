#include "ntfs_backend.h"
#include "dir_entry_wire.h"
#include <android/log.h>
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)
#include <algorithm>
#include <atomic>
#include <cerrno>
#include <cstring>
#include <cstdlib>
#include <fstream>
#include <memory>
#include <sys/stat.h>
#include <unordered_set>
#include <utility>
#include <vector>
#include <unistd.h>
extern "C" {
#include "device.h"
#include "inode.h"
#include "dir.h"
#include "attrib.h"
#include "index.h"
#include "layout.h"
#include "runlist.h"
#include "bitmap.h"
#include "volume.h"
#include "reparse.h"
}
#include "block_io.h"
#include "crypto/cascade.h"
#include "crypto/xts_tweak.h"
#include "volume_state.h"
#include "bitlocker_backend.h"
#include "containers/vhd_image.h"
#include "containers/vhdx_image.h"
#include "filesystems/stream_handles.h"

static bool ntfsIsDirectoryInode(const ntfs_inode* ni);

namespace {
bool ntfsIsSymlinkInode(const ntfs_inode* inode);
constexpr int kMaxVolumes = FF_VOLUMES;
std::atomic<int64_t> ntfsDevicePositions[kMaxVolumes];
const bool kNtfsDevicePositionsInitialized = []() {
    for (auto& position : ntfsDevicePositions) position.store(0);
    return true;
}();

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

int ntfsVolumeId(const ntfs_device* device) {
    if (device->d_private) return *static_cast<const int*>(device->d_private);
    return (device->d_name && std::strncmp(device->d_name, "ve", 2) == 0)
        ? std::atoi(device->d_name + 2) : -1;
}

int ntfsStat(ntfs_device* device, struct stat* statBuffer) {
    const int volumeId = ntfsVolumeId(device);
    if (volumeId < 0 || volumeId >= kMaxVolumes) {
        errno = ENODEV;
        return -1;
    }
    std::memset(statBuffer, 0, sizeof(*statBuffer));
    statBuffer->st_size = static_cast<off_t>(volumes[volumeId].dataAreaLengthBytes);
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
    if (startByte >= volume.dataAreaLengthBytes) return 0;
    uint64_t byteCount = static_cast<uint64_t>(count);
    if (byteCount > volume.dataAreaLengthBytes - startByte) {
        byteCount = volume.dataAreaLengthBytes - startByte;
    }
    std::memset(buffer, 0, static_cast<size_t>(count));

    if (volume.containerFormat == ContainerFormat::kBitLocker) {
        return bitlockerRead(volumeId, startByte, static_cast<unsigned char*>(buffer), byteCount)
            ? count : -1;
    }

    // No encryption layer at all -- pass bytes straight through instead of
    // running them through a cascade. See VolumeState's plainBacking doc
    // comment for why the backing (flat fd vs. VHDX vs. VHD) matters here.
    if (volume.containerFormat == ContainerFormat::kPlain) {
        const uint64_t physicalStartByte = volume.dataOffset + startByte;
        bool ok;
        switch (volume.plainBacking) {
            case VolumeState::PlainBacking::kVhdx:
                ok = static_cast<VhdxImage*>(volume.plainImage)
                         ->pread(physicalStartByte, static_cast<unsigned char*>(buffer), byteCount);
                break;
            case VolumeState::PlainBacking::kVhd:
                ok = static_cast<VhdImage*>(volume.plainImage)
                         ->pread(physicalStartByte, static_cast<unsigned char*>(buffer), byteCount);
                break;
            default:
                ok = physicalRead(volumeId, physicalStartByte, static_cast<unsigned char*>(buffer), byteCount);
                break;
        }
        return ok ? count : -1;
    }

    const bool isLuks = (volume.containerFormat != ContainerFormat::kVeraCrypt);
    const uint32_t luksUnit = (isLuks && volume.luksSectorSize >= 512) ? volume.luksSectorSize : 512;
    const uint64_t startUnit = startByte / luksUnit;
    const uint64_t endUnit = (startByte + byteCount + luksUnit - 1) / luksUnit;
    const uint32_t unitCount = static_cast<uint32_t>(endUnit - startUnit);
    const uint64_t physicalStartByte = volume.dataOffset + startUnit * luksUnit;
    const size_t transferBytes = static_cast<size_t>(unitCount) * luksUnit;

    thread_local AlignedBuffer tlsEncrypted;
    thread_local AlignedBuffer tlsPlaintext;
    unsigned char* encrypted = tlsEncrypted.get(transferBytes);
    if (!encrypted) return -1;
    if (!physicalRead(volumeId, physicalStartByte, encrypted, transferBytes)) {
        LOGI("ntfsPread: physicalRead failed for volume %d at offset %llu (count=%zu)",
             volumeId, (unsigned long long)physicalStartByte, transferBytes);
        return -1;
    }
    unsigned char* plaintext = tlsPlaintext.get(transferBytes);
    if (!plaintext) return -1;

    if (volume.containerFormat == ContainerFormat::kVeraCrypt) {
        for (uint32_t i = 0; i < unitCount; ++i) {
            const uint64_t phys512Sector = (physicalStartByte / 512) + i;
            const uint64_t tweak = phys512Sector - volume.partitionStartSector;
            cascadeDecryptSector(volume.cascade, tweak, encrypted + i * 512, plaintext + i * 512);
        }
    } else if (luksUnit == 512) {
        for (uint32_t i = 0; i < unitCount; ++i) {
            const uint64_t phys512Sector = (physicalStartByte / 512) + i;
            const uint64_t sectorNum = phys512Sector - volume.partitionStartSector;
            unsigned char tweakBuf[16] = {0};
            for (int b = 0; b < 8; b++) tweakBuf[b] = (sectorNum >> (b * 8)) & 0xFF;
            genericLuksXtsCrypt(volume.luksGenericCascade.layers[0], false, 512, tweakBuf,
                                 encrypted + i * 512, plaintext + i * 512);
        }
    } else {
        for (uint32_t i = 0; i < unitCount; ++i) {
            const uint64_t unitByteOffset = physicalStartByte + static_cast<uint64_t>(i) * luksUnit;
            const uint64_t phys512Sector = unitByteOffset / 512;
            const uint64_t sectorTweak = phys512Sector - volume.partitionStartSector;
            unsigned char tweakBuf[16] = {0};
            for (int b = 0; b < 8; b++) tweakBuf[b] = (sectorTweak >> (b * 8)) & 0xFF;
            genericLuksXtsCrypt(volume.luksGenericCascade.layers[0], false, luksUnit, tweakBuf,
                                 encrypted + i * luksUnit, plaintext + i * luksUnit);
        }
    }

    std::memcpy(buffer, plaintext + (startByte % luksUnit), byteCount);
    return count;
}

s64 ntfsPwrite(ntfs_device* device, const void* buffer, s64 count, s64 offset) {
    if (count <= 0 || offset < 0) return count == 0 ? 0 : -1;
    const int volumeId = ntfsVolumeId(device);
    if (volumeId < 0 || volumeId >= kMaxVolumes) return -1;
    VolumeState& volume = volumes[volumeId];
    const uint64_t startByte = static_cast<uint64_t>(offset);
    if (startByte >= volume.dataAreaLengthBytes) return -1;
    uint64_t byteCount = static_cast<uint64_t>(count);
    if (byteCount > volume.dataAreaLengthBytes - startByte) {
        byteCount = volume.dataAreaLengthBytes - startByte;
    }
    if (volume.containerFormat == ContainerFormat::kBitLocker) {
        return bitlockerWrite(volumeId, startByte, static_cast<const unsigned char*>(buffer), byteCount)
            ? count : -1;
    }

    // See the matching branch in ntfsPread above.
    if (volume.containerFormat == ContainerFormat::kPlain) {
        const uint64_t physicalStartByte = volume.dataOffset + startByte;
        bool ok;
        switch (volume.plainBacking) {
            case VolumeState::PlainBacking::kVhdx:
                ok = static_cast<VhdxImage*>(volume.plainImage)
                         ->pwrite(physicalStartByte, static_cast<const unsigned char*>(buffer), byteCount);
                break;
            case VolumeState::PlainBacking::kVhd:
                ok = static_cast<VhdImage*>(volume.plainImage)
                         ->pwrite(physicalStartByte, static_cast<const unsigned char*>(buffer), byteCount);
                break;
            default:
                ok = physicalWrite(volumeId, physicalStartByte, static_cast<const unsigned char*>(buffer), byteCount);
                break;
        }
        return ok ? count : -1;
    }

    const bool isLuks = (volume.containerFormat != ContainerFormat::kVeraCrypt);
    const uint32_t luksUnit = (isLuks && volume.luksSectorSize >= 512) ? volume.luksSectorSize : 512;
    const uint64_t startUnit = startByte / luksUnit;
    const uint64_t endUnit = (startByte + byteCount + luksUnit - 1) / luksUnit;
    const uint32_t unitCount = static_cast<uint32_t>(endUnit - startUnit);
    const uint64_t physicalStartByte = volume.dataOffset + startUnit * luksUnit;
    const size_t transferBytes = static_cast<size_t>(unitCount) * luksUnit;

    thread_local AlignedBuffer tlsSectors;
    unsigned char* sectors = tlsSectors.get(transferBytes);
    if (!sectors) return -1;

    const bool partialTransfer = (startByte % luksUnit != 0) || (byteCount % luksUnit != 0);
    if (partialTransfer) {
        thread_local AlignedBuffer tlsEncrypted;
        unsigned char* encrypted = tlsEncrypted.get(transferBytes);
        if (!encrypted) return -1;
        if (!physicalRead(volumeId, physicalStartByte, encrypted, transferBytes)) {
            LOGI("ntfsPwrite: physicalRead failed for volume %d at offset %llu (count=%zu)",
                 volumeId, (unsigned long long)physicalStartByte, transferBytes);
            return -1;
        }
        if (volume.containerFormat == ContainerFormat::kVeraCrypt) {
            for (uint32_t i = 0; i < unitCount; ++i) {
                const uint64_t phys512Sector = (physicalStartByte / 512) + i;
                const uint64_t tweak = phys512Sector - volume.partitionStartSector;
                cascadeDecryptSector(volume.cascade, tweak, encrypted + i * 512, sectors + i * 512);
            }
        } else if (luksUnit == 512) {
            for (uint32_t i = 0; i < unitCount; ++i) {
                const uint64_t phys512Sector = (physicalStartByte / 512) + i;
                const uint64_t sectorNum = phys512Sector - volume.partitionStartSector;
                unsigned char tweakBuf[16] = {0};
                for (int b = 0; b < 8; b++) tweakBuf[b] = (sectorNum >> (b * 8)) & 0xFF;
                genericLuksXtsCrypt(volume.luksGenericCascade.layers[0], false, 512, tweakBuf,
                                     encrypted + i * 512, sectors + i * 512);
            }
        } else {
            for (uint32_t i = 0; i < unitCount; ++i) {
                const uint64_t unitByteOffset = physicalStartByte + static_cast<uint64_t>(i) * luksUnit;
                const uint64_t phys512Sector = unitByteOffset / 512;
                const uint64_t sectorTweak = phys512Sector - volume.partitionStartSector;
                unsigned char tweakBuf[16] = {0};
                for (int b = 0; b < 8; b++) tweakBuf[b] = (sectorTweak >> (b * 8)) & 0xFF;
                genericLuksXtsCrypt(volume.luksGenericCascade.layers[0], false, luksUnit, tweakBuf,
                                     encrypted + i * luksUnit, sectors + i * luksUnit);
            }
        }
    }

    std::memcpy(sectors + (startByte % luksUnit), buffer, byteCount);
    thread_local AlignedBuffer tlsEncryptedOut;
    unsigned char* encryptedOut = tlsEncryptedOut.get(transferBytes);
    if (!encryptedOut) return -1;

    if (volume.containerFormat == ContainerFormat::kVeraCrypt) {
        for (uint32_t i = 0; i < unitCount; ++i) {
            const uint64_t phys512Sector = (physicalStartByte / 512) + i;
            const uint64_t tweak = phys512Sector - volume.partitionStartSector;
            cascadeEncryptSector(volume.cascade, tweak, sectors + i * 512, encryptedOut + i * 512);
        }
    } else if (luksUnit == 512) {
        for (uint32_t i = 0; i < unitCount; ++i) {
            const uint64_t phys512Sector = (physicalStartByte / 512) + i;
            const uint64_t sectorNum = phys512Sector - volume.partitionStartSector;
            unsigned char tweakBuf[16] = {0};
            for (int b = 0; b < 8; b++) tweakBuf[b] = (sectorNum >> (b * 8)) & 0xFF;
            genericLuksXtsCrypt(volume.luksGenericCascade.layers[0], true, 512, tweakBuf,
                                 sectors + i * 512, encryptedOut + i * 512);
        }
    } else {
        for (uint32_t i = 0; i < unitCount; ++i) {
            const uint64_t unitByteOffset = physicalStartByte + static_cast<uint64_t>(i) * luksUnit;
            const uint64_t phys512Sector = unitByteOffset / 512;
            const uint64_t sectorTweak = phys512Sector - volume.partitionStartSector;
            unsigned char tweakBuf[16] = {0};
            for (int b = 0; b < 8; b++) tweakBuf[b] = (sectorTweak >> (b * 8)) & 0xFF;
            genericLuksXtsCrypt(volume.luksGenericCascade.layers[0], true, luksUnit, tweakBuf,
                                 sectors + i * luksUnit, encryptedOut + i * luksUnit);
        }
    }

    if (!physicalWrite(volumeId, physicalStartByte, encryptedOut, transferBytes)) return -1;
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
    if (volumeId < 0 || volumeId >= kMaxVolumes) return 0;
    auto& v = volumes[volumeId];
    if (v.isUsbSource) {
        // USB sessions have no fd (it is -1): without this branch the sync did
        // nothing and reported success while writes were still in the USB cache.
        if (!v.usbCache.sync(volumeId)) {
            errno = EIO;
            return -1;
        }
        return 0;
    }
    if (v.isCompositeSource && v.composite) {
        v.composite->sync();
    } else if (v.fd >= 0) {
        v.fdWriteBuffer.flush(v.fd);
        fsync(v.fd);
    }
    return 0;
}

int ntfsIoctl(ntfs_device* device, unsigned long request, void* argument) {
    const int volumeId = ntfsVolumeId(device);
    if (volumeId < 0 || volumeId >= kMaxVolumes) { errno = ENODEV; return -1; }
    const auto& volume = volumes[volumeId];
    const uint32_t sectorSize = (volume.luksSectorSize >= 512) ? volume.luksSectorSize : 512;

    switch (request) {
        case 0x1268:
            *static_cast<int*>(argument) = static_cast<int>(sectorSize);
            return 0;
        case 0x1260:
            *static_cast<unsigned long*>(argument) = static_cast<unsigned long>(volume.dataAreaLengthBytes / sectorSize);
            return 0;
        case 0x80041272:
        case 0x80081272:
            *static_cast<uint64_t*>(argument) = volume.dataAreaLengthBytes;
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
    if (ntfsIsSymlinkInode(inode)) { ntfs_inode_close(inode); return 0; }
    if (inode->mrec->flags & MFT_RECORD_IS_DIRECTORY) {
        s64 position = 0;
        ntfs_readdir(inode, &position, context, recursiveSizeEntry);
    } else {
        context->totalSize += inode->data_size;
    }
    ntfs_inode_close(inode);
    return 0;
}

struct NtfsFilldirContext {
    std::vector<std::string>* results;
    ntfs_volume* vol;
};

int ntfsFilldir(void* dirent, const ntfschar* name, const int nameLength,
                const int nameType, const s64, const MFT_REF reference,
                const unsigned) {
    auto* context = static_cast<NtfsFilldirContext*>(dirent);
    if (nameType == FILE_NAME_DOS) return 0;
    if (context->results->size() >= NTFS_DIRECTORY_MAX_ENTRIES) return 0;
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
    if (ntfsIsSymlinkInode(ni)) { ntfs_inode_close(ni); return 0; }
    uint64_t size = 0;
    uint64_t ts = 0;
    const bool isDir = (ni->mrec->flags & MFT_RECORD_IS_DIRECTORY) != 0;
    if (!isDir) size = ni->data_size;
    const uint64_t ntfsTime = ni->last_data_change_time;
    if (ntfsTime > 116444736000000000ULL) {
        ts = (ntfsTime - 116444736000000000ULL) / 10000000ULL;
    }
    ntfs_inode_close(ni);
    context->results->push_back(encodeDirEntryWire(nameStr, isDir, size, ts));
    return 0;
}

struct NtfsRepairEntry {
    std::string parentPath;
    std::vector<ntfschar> name;
    int nameType;
};

struct NtfsRepairScan {
    ntfs_volume* volume;
    uint64_t capacityBytes;
    uint64_t nowUnix;
    bool found = false;
    bool complete = true;
    std::unordered_set<uint64_t> visited;
    std::vector<NtfsRepairEntry> corrupt;
};

struct NtfsRepairDirectory {
    NtfsRepairScan* scan;
    std::string path;
    std::vector<std::pair<std::string, uint64_t>> childDirectories;
};

bool ntfsRepairIsInternalName(const std::string& name) {
    return name == "System Volume Information" || name == "$MFT" || name == "$MFTMirr" ||
           name == "$LogFile" || name == "$Volume" || name == "$AttrDef" || name == "$Bitmap" ||
           name == "$Boot" || name == "$BadClus" || name == "$Secure" || name == "$UpCase" ||
           name == "$Extend" || name == "$RECYCLE.BIN";
}

int ntfsRepairDirectoryEntry(void* data, const ntfschar* name, const int nameLength,
                             const int nameType, const s64, const MFT_REF reference, const unsigned) {
    auto* context = static_cast<NtfsRepairDirectory*>(data);
    if (nameType == FILE_NAME_DOS || nameLength <= 0 || nameLength > 255) return 0;
    char* utf8Name = nullptr;
    const int utf8Length = ntfs_ucstombs(name, nameLength, &utf8Name, 0);
    const bool nameInvalid = utf8Length < 0 || !utf8Name;
    std::string nameString;
    if (!nameInvalid) {
        nameString.assign(utf8Name, utf8Length);
        free(utf8Name);
        if (nameString == "." || nameString == ".." || ntfsRepairIsInternalName(nameString)) return 0;
    } else if (utf8Name) {
        free(utf8Name);
    }
    ntfs_inode* inode = nameInvalid ? nullptr : ntfs_inode_open(context->scan->volume, reference);
    bool corrupt = nameInvalid || !inode;
    bool isDirectory = false;
    if (inode) {
        isDirectory = !ntfsIsSymlinkInode(inode) &&
                      (inode->mrec->flags & MFT_RECORD_IS_DIRECTORY) != 0;
        const uint64_t ntfsTime = inode->last_data_change_time;
        constexpr uint64_t kNtfsEpochOffset = 116444736000000000ULL;
        constexpr uint64_t kOneYearSeconds = 366ULL * 24 * 3600;
        const bool futureTimestamp = ntfsTime > kNtfsEpochOffset &&
            (ntfsTime - kNtfsEpochOffset) / 10000000ULL > context->scan->nowUnix + kOneYearSeconds;
        corrupt = (!isDirectory && (inode->data_size < 0 ||
                    static_cast<uint64_t>(inode->data_size) > context->scan->capacityBytes)) || futureTimestamp;
        ntfs_inode_close(inode);
    }
    if (corrupt) {
        context->scan->found = true;
        context->scan->corrupt.push_back({context->path,
                                          std::vector<ntfschar>(name, name + nameLength), nameType});
        return 0;
    }
    if (isDirectory) {
        const std::string childPath = context->path.empty() ? nameString : context->path + "/" + nameString;
        context->childDirectories.push_back({childPath, static_cast<uint64_t>(reference)});
    }
    return 0;
}

void ntfsScanRepairDirectory(NtfsRepairScan& scan, const std::string& path, uint64_t directoryReference) {
    if (!scan.visited.insert(directoryReference).second) return;
    ntfs_inode* directory = path.empty()
        ? ntfs_inode_open(scan.volume, FILE_root)
        : ntfs_pathname_to_inode(scan.volume, nullptr, ("/" + path).c_str());
    if (!directory) {
        scan.found = true;
        scan.complete = false;
        return;
    }
    s64 position = 0;
    NtfsRepairDirectory context{&scan, path, {}};
    if (ntfs_readdir(directory, &position, &context, ntfsRepairDirectoryEntry) != 0) {
        scan.found = true;
        scan.complete = false;
    }
    ntfs_inode_close(directory);
    for (const auto& child : context.childDirectories) ntfsScanRepairDirectory(scan, child.first, child.second);
}

bool ntfsRemoveRepairIndexEntry(NtfsRepairScan& scan, const NtfsRepairEntry& entry) {
    ntfs_inode* directory = entry.parentPath.empty()
        ? ntfs_inode_open(scan.volume, FILE_root)
        : ntfs_pathname_to_inode(scan.volume, nullptr, ("/" + entry.parentPath).c_str());
    if (!directory) return false;
    const size_t keyLength = offsetof(FILE_NAME_ATTR, file_name) + entry.name.size() * sizeof(ntfschar);
    std::vector<uint8_t> keyBuffer(keyLength, 0);
    auto* key = reinterpret_cast<FILE_NAME_ATTR*>(keyBuffer.data());
    key->file_name_length = static_cast<uint8_t>(entry.name.size());
    key->file_name_type = static_cast<FILE_NAME_TYPE_FLAGS>(entry.nameType);
    std::memcpy(key->file_name, entry.name.data(), entry.name.size() * sizeof(ntfschar));
    const bool removed = ntfs_index_remove(directory, nullptr, key, static_cast<int>(keyLength)) == 0 &&
                         ntfs_inode_sync(directory) == 0;
    ntfs_inode_close(directory);
    return removed;
}

bool ntfsScanCorruptDirectoryEntries(int volumeId, bool remove) {
    if (volumeId < 0 || volumeId >= kMaxVolumes) return false;
    VolumeState& volume = volumes[volumeId];
    if (!volume.ntfsVol || (remove && volume.readOnly)) return false;
    NtfsRepairScan scan{volume.ntfsVol, volume.dataAreaLengthBytes, static_cast<uint64_t>(time(nullptr))};
    ntfsScanRepairDirectory(scan, "", static_cast<uint64_t>(FILE_root));
    if (!remove) return scan.found;
    if (!scan.complete) return false;
    for (const auto& entry : scan.corrupt) {
        if (!ntfsRemoveRepairIndexEntry(scan, entry)) return false;
    }
    return ntfs_device_sync(volume.ntfsVol->dev) == 0;
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


// ---- Growing the file system into unallocated space after the container was expanded ----------------------
//
// libntfs-3g has no resize API; this is the grow-only path of ntfsresize (ntfsprogs/ntfsresize.c), minus
// everything about relocating data, written against the library so it never calls exit():
//   * $Bitmap gets one bit per new cluster (new clusters free; the padding bits after the last cluster set).
//     If it no longer fits its allocated clusters it is extended with clusters taken from the NEW space --
//     the old file system may be completely full, which is the usual reason to expand;
//   * $BadClus:$Bad, a sparse stream as long as the volume, is extended with a hole;
//   * the boot sector gets the new size and a copy is written to the last sector (the backup boot sector).
// Like ntfsresize the new volume is (device size - one sector) / cluster size clusters: the backup boot sector
// at the end of the device is not part of the volume.
// Order matters for interruption: the new backup boot sector is written first and the primary boot sector
// (which is what the next mount reads the size from) last, so a half-finished grow leaves the old size.
FsGrowStatus ntfsGrowToFit(int volumeId) {
    if (volumeId < 0 || volumeId >= kMaxVolumes) return FsGrowStatus::kFailed;
    VolumeState& volume = volumes[volumeId];
    ntfs_volume* vol = volume.ntfsVol;
    if (!vol || volume.readOnly) return FsGrowStatus::kFailed;
    if (!volume.openNtfsStreams.empty()) return FsGrowStatus::kBusy;
    const s64 sectorSize = vol->sector_size;
    const s64 clusterSize = vol->cluster_size;
    const s64 deviceBytes = static_cast<s64>(volume.dataAreaLengthBytes / sectorSize) * sectorSize;
    if (deviceBytes <= sectorSize) return FsGrowStatus::kFailed;
    const s64 oldClusters = vol->nr_clusters;
    const s64 newClusters = (deviceBytes - sectorSize) / clusterSize;
    if (newClusters <= oldClusters) return FsGrowStatus::kAlreadyFills;
    if (vol->major_ver < 3) return FsGrowStatus::kUnsupported;   // NTFS 1.x: $BadClus isn't sparse
    if (vol->flags & VOLUME_IS_DIRTY) return FsGrowStatus::kNeedsCheck;
    ntfs_attr* bitmapAttr = vol->lcnbmp_na;
    if (!bitmapAttr || !NAttrNonResident(bitmapAttr)) return FsGrowStatus::kFailed;

    auto bitmapBytesFor = [](s64 clusters) { return ((clusters + 7) / 8 + 7) & ~static_cast<s64>(7); };
    const s64 oldBitmapBytes = bitmapAttr->data_size;
    const s64 newBitmapBytes = bitmapBytesFor(newClusters);
    const s64 oldBitmapClusters = bitmapAttr->allocated_size >> vol->cluster_size_bits;
    const s64 neededBitmapClusters = (newBitmapBytes + clusterSize - 1) / clusterSize;
    const s64 extraClusters = std::max<s64>(0, neededBitmapClusters - oldBitmapClusters);
    if (extraClusters >= newClusters - oldClusters) return FsGrowStatus::kFailed;
    LOGI("ntfsGrowToFit: volume %d growing %lld -> %lld clusters (bitmap %lld -> %lld bytes, +%lld clusters)",
         volumeId, static_cast<long long>(oldClusters), static_cast<long long>(newClusters),
         static_cast<long long>(oldBitmapBytes), static_cast<long long>(newBitmapBytes),
         static_cast<long long>(extraClusters));

    // The new $Bitmap content.
    std::vector<u8> bitmap(static_cast<size_t>(newBitmapBytes), 0);
    if (ntfs_attr_pread(bitmapAttr, 0, std::min(oldBitmapBytes, newBitmapBytes), bitmap.data()) !=
        std::min(oldBitmapBytes, newBitmapBytes)) {
        return FsGrowStatus::kFailed;
    }
    for (s64 bit = oldClusters; bit < newBitmapBytes * 8; ++bit)
        ntfs_bit_set(bitmap.data(), static_cast<u64>(bit), bit < newClusters ? 0 : 1);
    // $Bitmap's own extension lives at the start of the new space.
    const s64 extensionLcn = oldClusters;
    for (s64 i = 0; i < extraClusters; ++i) ntfs_bit_set(bitmap.data(), static_cast<u64>(extensionLcn + i), 1);

    // Boot sector with the new size, plus its backup at the last sector of the device.
    std::vector<u8> boot(static_cast<size_t>(sectorSize));
    if (ntfs_pread(vol->dev, 0, sectorSize, boot.data()) != sectorSize) return FsGrowStatus::kFailed;
    auto* bootSector = reinterpret_cast<NTFS_BOOT_SECTOR*>(boot.data());
    bootSector->number_of_sectors = cpu_to_sle64(newClusters * (clusterSize / sectorSize));
    if (ntfs_pwrite(vol->dev, deviceBytes - sectorSize, sectorSize, boot.data()) != sectorSize)
        return FsGrowStatus::kFailed;

    // 1. $Bitmap: new runs, then the data, then the attribute record.
    if (ntfs_attr_map_whole_runlist(bitmapAttr)) return FsGrowStatus::kFailed;
    runlist* merged = bitmapAttr->rl;
    if (extraClusters > 0) {
        auto* extension = static_cast<runlist*>(std::malloc(2 * sizeof(runlist_element)));
        if (!extension) return FsGrowStatus::kFailed;
        extension[0].vcn = oldBitmapClusters;
        extension[0].lcn = extensionLcn;
        extension[0].length = extraClusters;
        extension[1].vcn = oldBitmapClusters + extraClusters;
        extension[1].lcn = LCN_ENOENT;
        extension[1].length = 0;
        merged = ntfs_runlists_merge(bitmapAttr->rl, extension);
        if (!merged) { std::free(extension); return FsGrowStatus::kFailed; }
    }
    if (ntfs_rl_pwrite(vol, merged, 0, 0, newBitmapBytes, bitmap.data()) != newBitmapBytes) {
        if (extraClusters > 0) bitmapAttr->rl = merged;   // merge already consumed the old list
        return FsGrowStatus::kFailed;
    }
    bitmapAttr->rl = merged;
    bitmapAttr->allocated_size = neededBitmapClusters << vol->cluster_size_bits;
    NAttrSetRunlistDirty(bitmapAttr);
    if (ntfs_attr_update_mapping_pairs(bitmapAttr, 0)) return FsGrowStatus::kFailed;
    {
        ntfs_attr_search_ctx* ctx = ntfs_attr_get_search_ctx(vol->lcnbmp_ni, nullptr);
        if (!ctx) return FsGrowStatus::kFailed;
        if (ntfs_attr_lookup(AT_DATA, AT_UNNAMED, 0, CASE_SENSITIVE, 0, nullptr, 0, ctx)) {
            ntfs_attr_put_search_ctx(ctx);
            return FsGrowStatus::kFailed;
        }
        bitmapAttr->data_size = bitmapAttr->initialized_size = newBitmapBytes;
        ctx->attr->data_size = ctx->attr->initialized_size = cpu_to_sle64(newBitmapBytes);
        ctx->attr->allocated_size = cpu_to_sle64(bitmapAttr->allocated_size);
        vol->lcnbmp_ni->data_size = newBitmapBytes;
        vol->lcnbmp_ni->allocated_size = bitmapAttr->allocated_size;
        ntfs_inode_mark_dirty(ctx->ntfs_ino);
        NInoFileNameSetDirty(vol->lcnbmp_ni);
        ntfs_attr_put_search_ctx(ctx);
    }
    if (ntfs_inode_sync(vol->lcnbmp_ni)) return FsGrowStatus::kFailed;

    // 2. $BadClus:$Bad covers the whole volume.
    {
        static const ntfschar badName[4] = {cpu_to_le16('$'), cpu_to_le16('B'), cpu_to_le16('a'), cpu_to_le16('d')};
        ntfs_inode* badInode = ntfs_inode_open(vol, FILE_BadClus);
        if (!badInode) return FsGrowStatus::kFailed;
        ntfs_attr* bad = ntfs_attr_open(badInode, AT_DATA, const_cast<ntfschar*>(badName), 4);
        const bool resized = bad && ntfs_attr_truncate(bad, newClusters << vol->cluster_size_bits) == 0;
        if (bad) ntfs_attr_close(bad);
        const bool synced = ntfs_inode_sync(badInode) == 0;
        ntfs_inode_close(badInode);
        if (!resized || !synced) return FsGrowStatus::kFailed;
    }

    // 3. The primary boot sector last: from here on the volume has its new size.
    if (ntfs_device_sync(vol->dev) != 0) return FsGrowStatus::kFailed;
    if (ntfs_pwrite(vol->dev, 0, sectorSize, boot.data()) != sectorSize) return FsGrowStatus::kFailed;
    if (ntfs_device_sync(vol->dev) != 0) return FsGrowStatus::kFailed;
    vol->nr_clusters = newClusters;
    vol->free_clusters = -1;
    return FsGrowStatus::kGrown;   // the caller remounts so every cached length is re-read
}

bool ntfsHasCorruptDirectoryEntries(int volumeId) {
    return ntfsScanCorruptDirectoryEntries(volumeId, false);
}

bool ntfsRemoveCorruptDirectoryEntries(int volumeId) {
    return ntfsScanCorruptDirectoryEntries(volumeId, true);
}

namespace {
// NTFS-3G supports Windows reparse-point symlinks, WSL LX symlinks and
// Interix INTX_SYMBOLIC_LINK data attributes. New links use the WSL LX reparse
// representation; existing Windows and legacy Interix links are also read.
struct NtfsWslLinkReparseData {
    le32 type;
    char link[1];
};

static bool ntfsReadWslSymlinkTarget(ntfs_inode* inode, std::string& outTarget) {
    if (!inode || !(inode->flags & FILE_ATTR_REPARSE_POINT)) return false;
    s64 attrSize = 0;
    auto* reparse = reinterpret_cast<REPARSE_POINT*>(
        ntfs_attr_readall(inode, AT_REPARSE_POINT, nullptr, 0, &attrSize));
    if (!reparse) return false;
    bool success = false;
    const size_t dataOffset = offsetof(REPARSE_POINT, reparse_data);
    const uint16_t dataLength = le16_to_cpu(reparse->reparse_data_length);
    if (reparse->reparse_tag == IO_REPARSE_TAG_LX_SYMLINK &&
        dataLength > sizeof(le32) &&
        attrSize >= static_cast<s64>(dataOffset + dataLength)) {
        const auto* link = reinterpret_cast<const NtfsWslLinkReparseData*>(reparse->reparse_data);
        if (link->type == const_cpu_to_le32(2)) {
            const size_t targetLength = dataLength - sizeof(le32);
            if (targetLength > 0 && targetLength <= 32767) {
                outTarget.assign(link->link, targetLength);
                success = outTarget.find('\0') == std::string::npos;
            }
        }
    }
    free(reparse);
    return success;
}

static bool ntfsReadInterixSymlinkTarget(ntfs_inode* inode, std::string& outTarget) {
    if (!inode || !(inode->flags & FILE_ATTR_SYSTEM)) return false;
    ntfs_attr* attr = ntfs_attr_open(inode, AT_DATA, nullptr, 0);
    if (!attr) return false;
    const s64 size = attr->data_size;
    if (size <= static_cast<s64>(offsetof(INTX_FILE, target)) || size > 65536) {
        ntfs_attr_close(attr);
        return false;
    }
    std::vector<uint8_t> data(static_cast<size_t>(size));
    const s64 bytesRead = ntfs_attr_pread(attr, 0, size, data.data());
    ntfs_attr_close(attr);
    if (bytesRead != size) return false;
    const auto* intx = reinterpret_cast<const INTX_FILE*>(data.data());
    if (intx->magic != INTX_SYMBOLIC_LINK) return false;
    const int targetUnits = static_cast<int>((size - offsetof(INTX_FILE, target)) / sizeof(ntfschar));
    char* utf8 = nullptr;
    const int utf8Length = ntfs_ucstombs(intx->target, targetUnits, &utf8, 0);
    if (utf8Length <= 0 || !utf8) { if (utf8) free(utf8); return false; }
    outTarget.assign(utf8, static_cast<size_t>(utf8Length));
    free(utf8);
    return outTarget.size() <= 32767 && outTarget.find('\0') == std::string::npos;
}

bool ntfsIsSymlinkInode(const ntfs_inode* inode) {
    if (!inode) return false;
    if (inode->flags & FILE_ATTR_REPARSE_POINT) {
        if (ntfs_possible_symlink(const_cast<ntfs_inode*>(inode))) return true;
        std::string ignored;
        return ntfsReadWslSymlinkTarget(const_cast<ntfs_inode*>(inode), ignored);
    }
    std::string ignored;
    return ntfsReadInterixSymlinkTarget(const_cast<ntfs_inode*>(inode), ignored);
}

static bool ntfsReadSymlinkTarget(ntfs_inode* inode, std::string& outTarget) {
    if (!ntfsIsSymlinkInode(inode)) return false;
    if (inode->flags & FILE_ATTR_REPARSE_POINT) {
        if (ntfs_possible_symlink(inode)) {
            char* rawTarget = ntfs_make_symlink(inode, "/");
            if (rawTarget) {
                outTarget.assign(rawTarget);
                free(rawTarget);
                return !outTarget.empty() && outTarget.size() <= 32767 &&
                       outTarget.find('\0') == std::string::npos;
            }
        }
        return ntfsReadWslSymlinkTarget(inode, outTarget);
    }
    return ntfsReadInterixSymlinkTarget(inode, outTarget);
}

bool ntfsNormalizeInsideRoot(const std::vector<std::string>& input,
                             std::vector<std::string>& output) {
    output.clear();
    for (const std::string& part : input) {
        if (part.empty() || part == ".") continue;
        if (part == "..") {
            if (output.empty()) return false;
            output.pop_back();
        } else {
            if (part.find('\0') != std::string::npos) return false;
            output.push_back(part);
        }
    }
    return true;
}

std::vector<std::string> ntfsSplitPath(const std::string& path) {
    std::vector<std::string> parts;
    size_t start = 0;
    while (start < path.size()) {
        while (start < path.size() && (path[start] == '/' || path[start] == '\\')) ++start;
        if (start >= path.size()) break;
        size_t end = path.find_first_of("/\\", start);
        if (end == std::string::npos) end = path.size();
        parts.emplace_back(path.substr(start, end - start));
        start = end;
    }
    return parts;
}

std::string ntfsJoinPath(const std::vector<std::string>& parts) {
    std::string out;
    for (const auto& part : parts) {
        if (!out.empty()) out.push_back('/');
        out += part;
    }
    return out;
}

bool ntfsTargetStaysInside(const std::string& parentPath, const std::string& target) {
    if (target.empty() || target.front() == '/' || target.front() == '\\' ||
        target.find('\0') != std::string::npos) return false;
    std::vector<std::string> combined = ntfsSplitPath(parentPath);
    const auto targetParts = ntfsSplitPath(target);
    combined.insert(combined.end(), targetParts.begin(), targetParts.end());
    std::vector<std::string> normalized;
    return ntfsNormalizeInsideRoot(combined, normalized);
}

ntfs_inode* ntfsResolvePath(ntfs_volume* volume, const std::string& inputPath,
                            bool followFinal = true) {
    if (!volume) return nullptr;
    std::vector<std::string> initial = ntfsSplitPath(inputPath);
    std::vector<std::string> parts;
    if (!ntfsNormalizeInsideRoot(initial, parts)) return nullptr;
    if (parts.empty()) return ntfs_inode_open(volume, FILE_root);

    std::unordered_set<std::string> followed;
    for (int hop = 0; hop <= 40; ++hop) {
        std::string prefix;
        bool restarted = false;
        for (size_t i = 0; i < parts.size(); ++i) {
            if (!prefix.empty()) prefix.push_back('/');
            prefix += parts[i];
            const std::string absolutePrefix = "/" + prefix;
            ntfs_inode* inode = ntfs_pathname_to_inode(volume, nullptr, absolutePrefix.c_str());
            if (!inode) return nullptr;
            const bool shouldFollow = ntfsIsSymlinkInode(inode) &&
                                      (followFinal || i + 1 < parts.size());
            if (shouldFollow) {
                if (!followed.insert(prefix).second) {
                    ntfs_inode_close(inode);
                    return nullptr;
                }
                std::string target;
                const bool targetReadable = ntfsReadSymlinkTarget(inode, target);
                ntfs_inode_close(inode);
                if (!targetReadable || target.empty() || target.front() == '/' || target.front() == '\\') return nullptr;

                std::vector<std::string> expanded(parts.begin(), parts.begin() + i);
                const auto targetParts = ntfsSplitPath(target);
                expanded.insert(expanded.end(), targetParts.begin(), targetParts.end());
                expanded.insert(expanded.end(), parts.begin() + i + 1, parts.end());
                std::vector<std::string> normalized;
                if (!ntfsNormalizeInsideRoot(expanded, normalized)) return nullptr;
                parts = std::move(normalized);
                if (parts.empty()) return ntfs_inode_open(volume, FILE_root);
                restarted = true;
                break;
            }
            if (i + 1 == parts.size()) return inode;
            ntfs_inode_close(inode);
        }
        if (!restarted) return nullptr;
    }
    return nullptr; // More than 40 link traversals: loop or hostile chain.
}

struct NtfsSymlinkListContext {
    std::vector<std::string>* results;
    ntfs_volume* volume;
    std::string parentPath;
};

int ntfsSymlinkFilldir(void* dirent, const ntfschar* name, const int nameLength,
                       const int nameType, const s64, const MFT_REF reference,
                       const unsigned) {
    auto* context = static_cast<NtfsSymlinkListContext*>(dirent);
    if (nameType == FILE_NAME_DOS || context->results->size() >= NTFS_DIRECTORY_MAX_ENTRIES) return 0;
    char* utf8Name = nullptr;
    const int utf8Length = ntfs_ucstombs(name, nameLength, &utf8Name, 0);
    if (utf8Length < 0 || !utf8Name) { if (utf8Name) free(utf8Name); return 0; }
    std::string nameStr(utf8Name, utf8Length);
    free(utf8Name);
    if (nameStr == "." || nameStr == "..") return 0;
    ntfs_inode* inode = ntfs_inode_open(context->volume, reference);
    if (!inode) return 0;
    if (!ntfsIsSymlinkInode(inode)) { ntfs_inode_close(inode); return 0; }
    std::string target;
    const uint64_t targetBytes = ntfsReadSymlinkTarget(inode, target) ? target.size() : 0;
    const uint64_t ntfsTime = inode->last_data_change_time;
    const uint64_t mtime = ntfsTime > 116444736000000000ULL
        ? (ntfsTime - 116444736000000000ULL) / 10000000ULL : 0;
    ntfs_inode_close(inode);
    const std::string linkPath = context->parentPath.empty()
        ? nameStr : context->parentPath + "/" + nameStr;
    ntfs_inode* targetInode = ntfsResolvePath(context->volume, linkPath, true);
    const bool targetIsDirectory = ntfsIsDirectoryInode(targetInode);
    if (targetInode) ntfs_inode_close(targetInode);
    context->results->push_back(
        encodeSymlinkEntryWire(nameStr, targetBytes, mtime, targetIsDirectory));
    return 0;
}
} // namespace

uint64_t recursiveNtfsFolderSize(int volumeId, const std::string& path) {
    ntfs_volume* volume = volumes[volumeId].ntfsVol;
    if (!volume) return 0;
    ntfs_inode* directory = ntfsResolvePath(volume, path, true);
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
    ntfs_inode* dirInode = ntfsResolvePath(volume, pathSuffix, true);
    if (!dirInode) return false;
    s64 position = 0;
    NtfsFilldirContext context{&results, volume};
    ntfs_readdir(dirInode, &position, &context, ntfsFilldir);
    ntfs_inode_close(dirInode);
    if (results.size() >= NTFS_DIRECTORY_MAX_ENTRIES) results.push_back("System:TRUNCATED");
    return true;
}

void ntfsListSymlinks(int volumeId, const std::string& pathSuffix,
                      std::vector<std::string>& results) {
    if (volumeId < 0 || volumeId >= kMaxVolumes) return;
    ntfs_volume* volume = volumes[volumeId].ntfsVol;
    if (!volume) return;
    ntfs_inode* dirInode = ntfsResolvePath(volume, pathSuffix, true);
    if (!dirInode) return;
    s64 position = 0;
    NtfsSymlinkListContext context{&results, volume, pathSuffix};
    ntfs_readdir(dirInode, &position, &context, ntfsSymlinkFilldir);
    ntfs_inode_close(dirInode);
    if (results.size() >= NTFS_DIRECTORY_MAX_ENTRIES) results.push_back("System:TRUNCATED");
}

bool ntfsReadSymlink(int volumeId, const std::string& path, std::string& outTarget) {
    if (volumeId < 0 || volumeId >= kMaxVolumes) return false;
    ntfs_volume* volume = volumes[volumeId].ntfsVol;
    ntfs_inode* inode = ntfsResolvePath(volume, path, false);
    if (!inode) return false;
    if (!ntfsIsSymlinkInode(inode)) { ntfs_inode_close(inode); return false; }
    const bool success = ntfsReadSymlinkTarget(inode, outTarget);
    ntfs_inode_close(inode);
    return success;
}

static bool ntfsNameLengthOk(int unicodeLength);

bool ntfsCreateSymlink(int volumeId, const std::string& path, const std::string& target) {
    if (volumeId < 0 || volumeId >= kMaxVolumes || target.empty() || target.size() > 32767 ||
        target.find('\0') != std::string::npos) return false;
    VolumeState& volumeState = volumes[volumeId];
    ntfs_volume* volume = volumeState.ntfsVol;
    if (!volume || volumeState.readOnly) return false;
    const size_t slash = path.find_last_of('/');
    const std::string parentPath = slash == std::string::npos ? "" : path.substr(0, slash);
    const std::string name = slash == std::string::npos ? path : path.substr(slash + 1);
    if (name.empty() || !ntfsTargetStaysInside(parentPath, target)) return false;
    ntfs_inode* parent = ntfsResolvePath(volume, parentPath, true);
    if (!parent) return false;
    ntfschar* unicodeName = nullptr;
    ntfschar* unicodeTarget = nullptr;
    const int nameLength = ntfs_mbstoucs(name.c_str(), &unicodeName);
    const int targetLength = ntfs_mbstoucs(target.c_str(), &unicodeTarget);
    ntfs_inode* created = nullptr;
    if (ntfsNameLengthOk(nameLength) && targetLength > 0 && targetLength <= 32767) {
        const auto previousSpecialFiles = volume->special_files;
        volume->special_files = NTFS_FILES_WSL;
        created = ntfs_create_symlink(parent, 0, unicodeName, static_cast<u8>(nameLength),
                                      unicodeTarget, targetLength);
        volume->special_files = previousSpecialFiles;
    }
    if (unicodeName) free(unicodeName);
    if (unicodeTarget) free(unicodeTarget);
    ntfs_inode_close(parent);
    if (!created) return false;
    ntfs_inode_close(created);
    return ntfs_device_sync(volume->dev) == 0;
}

// NTFS names are at most 255 UTF-16 units, and ntfs_create()/ntfs_link() take the
// length as a u8: a longer name doesn't fail, the count wraps and a different,
// shorter name is stored (256 units wrap to 0 and are rejected by luck).
static bool ntfsNameLengthOk(int unicodeLength) {
    return unicodeLength > 0 && unicodeLength <= NTFS_MAX_NAME_LEN;
}

static bool ntfsIsDirectoryInode(const ntfs_inode* ni) {
    return ni && !ntfsIsSymlinkInode(ni) &&
           (ni->mrec->flags & MFT_RECORD_IS_DIRECTORY) != 0;
}

// True if [dir] is the directory with MFT number [ancestorMftNo] or lies somewhere
// below it, found by walking ".." up to the root. Fails closed: an unreadable
// parent counts as "inside", so the caller refuses the operation. [dir] stays
// owned by the caller.
static bool ntfsIsSelfOrDescendant(ntfs_inode* dir, u64 ancestorMftNo) {
    ntfs_inode* current = dir;
    bool owned = false;
    for (int depth = 0; depth < 4096; ++depth) {
        const bool hit = current->mft_no == ancestorMftNo;
        const bool atRoot = current->mft_no == FILE_root;
        if (hit || atRoot) {
            if (owned) ntfs_inode_close(current);
            return hit;
        }
        ntfs_inode* parent = ntfs_dir_parent_inode(current);
        if (owned) ntfs_inode_close(current);
        if (!parent) return true;
        current = parent;
        owned = true;
    }
    if (owned) ntfs_inode_close(current);
    return true;
}

ntfs_inode* createNtfsFile(ntfs_volume* volume, const std::string& path) {
    const size_t slash = path.find_last_of('/');
    std::string parentPath = path.substr(0, slash);
    const std::string name = path.substr(slash + 1);
    if (parentPath.empty()) parentPath = "/";
    ntfs_inode* parent = ntfsResolvePath(volume, parentPath, true);
    if (!parent) return nullptr;
    ntfschar* unicodeName = nullptr;
    const int unicodeLength = ntfs_mbstoucs(name.c_str(), &unicodeName);
    ntfs_inode* created = nullptr;
    if (ntfsNameLengthOk(unicodeLength)) {
        created = ntfs_create(parent, 0, unicodeName, unicodeLength, S_IFREG);
    }
    free(unicodeName);
    ntfs_inode_close(parent);
    return created;
}

extern "C" const char *ntfs_libntfs_version(void) {
    return "vaultexplorer-ntfs3g-edge";
}

int64_t ntfsGetFileSize(int volumeId, const std::string& path) {
    auto& v = volumes[volumeId];
    int64_t size = -1;
    ntfs_inode* ni = ntfsResolvePath(v.ntfsVol, path, true);
    if (ni) {
        size = static_cast<int64_t>(ni->data_size);
        ntfs_inode_close(ni);
    }
    return size;
}

bool ntfsReadFileChunk(int volumeId, const std::string& path, uint64_t offset, size_t length, std::vector<uint8_t>& outBuffer) {
    auto& v = volumes[volumeId];
    bool success = false;
    ntfs_inode* ni = ntfsResolvePath(v.ntfsVol, path, true);
    if (ni) {
        ntfs_attr* na = ntfs_attr_open(ni, AT_DATA, NULL, 0);
        if (na) {
            std::unique_ptr<unsigned char[]> buffer(new unsigned char[length]);
            s64 br = ntfs_attr_pread(na, offset, length, buffer.get());
            if (br > 0) {
                outBuffer.assign(buffer.get(), buffer.get() + br);
                success = true;
            }
            ntfs_attr_close(na);
        }
        ntfs_inode_close(ni);
    }
    return success;
}

bool ntfsWriteFileChunk(int volumeId, const std::string& path, uint64_t offset, const uint8_t* data, size_t length) {
    auto& v = volumes[volumeId];
    // The low-level write path already refuses (io/block_io.cpp), but libntfs-3g applies changes in
    // memory first, so without this a write to a read-only volume -- including one made read-only
    // mid-session by hidden-volume protection -- would report success and silently vanish.
    if (v.readOnly) return false;
    bool success = false;
    std::string fullPath = "/" + path;
    ntfs_inode* ni = ntfsResolvePath(v.ntfsVol, path, true);
    if (!ni) {
        ni = createNtfsFile(v.ntfsVol, fullPath);
    }
    if (ni && ntfsIsDirectoryInode(ni)) {
        // Without this the code below adds an unnamed $DATA stream to the directory.
        ntfs_inode_close(ni);
        ni = nullptr;
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
            s64 bw = ntfs_attr_pwrite(na, offset, length, data);
            if (bw == static_cast<s64>(length)) success = true;
            ntfs_attr_close(na);
        }
        ntfs_inode_close(ni);
    }
    return success;
}

bool ntfsCopyFile(int srcVolId, const std::string& srcPath, int destVolId, const std::string& destPath,
                   const CopyProgressCallback& onProgress) {
    auto& srcV = volumes[srcVolId];
    auto& destV = volumes[destVolId];
    if (destV.readOnly) return false;
    std::string srcFullPath = "/" + srcPath;
    std::string destFullPath = "/" + destPath;
    ntfs_inode* src_ni = ntfsResolvePath(srcV.ntfsVol, srcPath, true);
    if (!src_ni) return false;
    ntfs_inode* dest_ni = ntfsResolvePath(destV.ntfsVol, destPath, true);
    if (!dest_ni) {
        dest_ni = createNtfsFile(destV.ntfsVol, destFullPath);
    }
    if (dest_ni && ntfsIsDirectoryInode(dest_ni)) {
        ntfs_inode_close(dest_ni);
        dest_ni = nullptr;
    }
    if (!dest_ni) {
        ntfs_inode_close(src_ni);
        return false;
    }
    ntfs_attr* src_na = ntfs_attr_open(src_ni, AT_DATA, NULL, 0);
    ntfs_attr* dest_na = ntfs_attr_open(dest_ni, AT_DATA, NULL, 0);
    if (!dest_na) {
        ntfs_attr_add(dest_ni, AT_DATA, AT_UNNAMED, 0, NULL, 0);
        dest_na = ntfs_attr_open(dest_ni, AT_DATA, NULL, 0);
    }
    bool ok = false;
    if (src_na && dest_na) {
        ntfs_attr_truncate(dest_na, 0);
        constexpr size_t kBufSize = 2097152;
        std::unique_ptr<unsigned char[]> buf(new unsigned char[kBufSize]);
        s64 offset = 0;
        ok = true;
        while (true) {
            s64 br = ntfs_attr_pread(src_na, offset, kBufSize, buf.get());
            if (br <= 0) break;
            s64 bw = ntfs_attr_pwrite(dest_na, offset, br, buf.get());
            if (bw != br) { ok = false; break; }
            offset += br;
            if (onProgress && !onProgress(static_cast<uint64_t>(bw))) {
                ok = false;
                break;
            }
        }
    }
    if (src_na) ntfs_attr_close(src_na);
    if (dest_na) ntfs_attr_close(dest_na);
    ntfs_inode_close(src_ni);
    ntfs_inode_close(dest_ni);
    return ok;
}

namespace {
int openNtfsHostSource(const std::string& sourceHostPath) {
    if (sourceHostPath.rfind("/proc/self/fd/", 0) == 0) {
        int fd = std::atoi(sourceHostPath.c_str() + 14);
        int duplicated = dup(fd);
        if (duplicated >= 0) {
            lseek(duplicated, 0, SEEK_SET);
            return duplicated;
        }
    }
    return open(sourceHostPath.c_str(), O_RDONLY | O_CLOEXEC);
}

int openNtfsHostDest(const std::string& destHostPath) {
    if (destHostPath.rfind("/proc/self/fd/", 0) == 0) {
        int fd = std::atoi(destHostPath.c_str() + 14);
        int duplicated = dup(fd);
        if (duplicated >= 0) {
            lseek(duplicated, 0, SEEK_SET);
            return duplicated;
        }
    }
    return open(destHostPath.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
}
} // namespace

bool ntfsWriteBackFile(int volumeId, const std::string& targetPath, const std::string& sourceHostPath,
                        const CopyProgressCallback& onProgress) {
    constexpr size_t kIoBufferSize = 2097152;
    auto& v = volumes[volumeId];
    if (v.readOnly) return false;
    bool success = false;
    std::string fullPath = "/" + targetPath;
    ntfs_inode* ni = ntfsResolvePath(v.ntfsVol, targetPath, true);
    if (!ni) {
        ni = createNtfsFile(v.ntfsVol, fullPath);
    }
    if (ni && ntfsIsDirectoryInode(ni)) {
        ntfs_inode_close(ni);
        ni = nullptr;
    }
    if (ni) {
        ntfs_attr* na = ntfs_attr_open(ni, AT_DATA, NULL, 0);
        if (!na) {
            ntfs_attr_add(ni, AT_DATA, AT_UNNAMED, 0, NULL, 0);
            na = ntfs_attr_open(ni, AT_DATA, NULL, 0);
        }
        if (na) {
            ntfs_attr_truncate(na, 0);
            int srcFd = openNtfsHostSource(sourceHostPath);
            if (srcFd >= 0) {
                std::unique_ptr<char[]> buf(new char[kIoBufferSize]);
                s64 offset = 0;
                bool writeError = false;
                bool cancelled = false;
                while (!writeError && !cancelled) {
                    ssize_t n = read(srcFd, buf.get(), kIoBufferSize);
                    if (n <= 0) break;
                    s64 bw = ntfs_attr_pwrite(na, offset, n, buf.get());
                    if (bw != n) {
                        writeError = true;
                    } else {
                        offset += bw;
                        if (onProgress && !onProgress(static_cast<uint64_t>(bw))) cancelled = true;
                    }
                }
                close(srcFd);
                if (!writeError && !cancelled) {
                    success = true;
                }
            }
            ntfs_attr_close(na);
        }
        ntfs_inode_close(ni);
    }
    return success;
}

bool ntfsExtractFile(int volumeId, const std::string& targetPath, const std::string& destHostPath,
                      const CopyProgressCallback& onProgress) {
    constexpr size_t kIoBufferSize = 2097152;
    auto& v = volumes[volumeId];
    bool success = false;
    ntfs_inode* ni = ntfsResolvePath(v.ntfsVol, targetPath, true);
    if (ni) {
        ntfs_attr* na = ntfs_attr_open(ni, AT_DATA, NULL, 0);
        if (na) {
            int destFd = openNtfsHostDest(destHostPath);
            if (destFd >= 0) {
                std::unique_ptr<unsigned char[]> buf(new unsigned char[kIoBufferSize]);
                s64 offset = 0;
                bool writeError = false;
                bool cancelled = false;
                while (!writeError && !cancelled) {
                    s64 br = ntfs_attr_pread(na, offset, kIoBufferSize, buf.get());
                    if (br <= 0) break;
                    ssize_t written = write(destFd, buf.get(), br);
                    if (written != static_cast<ssize_t>(br)) {
                        writeError = true;
                        break;
                    }
                    offset += br;
                    if (onProgress && !onProgress(static_cast<uint64_t>(written))) {
                        cancelled = true;
                        break;
                    }
                }
                close(destFd);
                success = !writeError && !cancelled;
            }
            ntfs_attr_close(na);
        }
        ntfs_inode_close(ni);
    }
    return success;
}

bool ntfsDeleteFile(int volumeId, const std::string& path) {
    auto& v = volumes[volumeId];
    if (v.readOnly) return false;
    bool success = false;
    std::string fullPath = "/" + path;
    ntfs_inode* ni = ntfsResolvePath(v.ntfsVol, path, false);
    size_t slashPos = fullPath.find_last_of('/');
    std::string parentPath = fullPath.substr(0, slashPos);
    std::string childName = fullPath.substr(slashPos + 1);
    if (parentPath.empty()) parentPath = "/";
    ntfs_inode* dir_ni = ntfsResolvePath(v.ntfsVol, parentPath, true);
    if (dir_ni && ni) {
        ntfschar* uname = nullptr;
        int uname_len = ntfs_mbstoucs(childName.c_str(), &uname);
        if (uname_len >= 0) {
            success = (ntfs_delete(v.ntfsVol, fullPath.c_str(), ni, dir_ni,
                                    uname, static_cast<u8>(uname_len)) == 0);
            free(uname);
            ni = nullptr;
            dir_ni = nullptr;
        }
    }
    if (ni) ntfs_inode_close(ni);
    if (dir_ni) ntfs_inode_close(dir_ni);
    return success;
}

bool ntfsCreateDirectory(int volumeId, const std::string& path) {
    auto& v = volumes[volumeId];
    if (v.readOnly) return false;
    bool success = false;
    std::string fullPath = "/" + path;
    size_t slashPos = fullPath.find_last_of('/');
    std::string parentPath = fullPath.substr(0, slashPos);
    std::string childName = fullPath.substr(slashPos + 1);
    if (parentPath.empty()) parentPath = "/";
    ntfs_inode* parentNi = ntfsResolvePath(v.ntfsVol, parentPath, true);
    if (parentNi) {
        ntfschar* uChild = nullptr;
        int uChildLen = ntfs_mbstoucs(childName.c_str(), &uChild);
        if (ntfsNameLengthOk(uChildLen)) {
            ntfs_inode* ni = ntfs_create(parentNi, 0, uChild, uChildLen, S_IFDIR);
            if (ni) {
                success = true;
                ntfs_inode_close(ni);
            }
        }
        free(uChild);
        ntfs_inode_close(parentNi);
    }
    return success;
}

bool ntfsRenameFile(int volumeId, const std::string& oldPath, const std::string& newPath) {
    auto& v = volumes[volumeId];
    if (v.readOnly) return false;
    bool success = false;
    std::string oldFullPath = "/" + oldPath;
    std::string newFullPath = "/" + newPath;
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
    if (uOldLen >= 0 && ntfsNameLengthOk(uNewLen)) {
        ntfs_inode* existing_dest_ni = ntfsResolvePath(v.ntfsVol, newPath, false);
        if (existing_dest_ni) {
            ntfs_inode_close(existing_dest_ni);
            if (uOld) free(uOld);
            if (uNew) free(uNew);
            return false;
        }
        ntfs_inode* old_ni = ntfsResolvePath(v.ntfsVol, oldPath, false);
        ntfs_inode* dir_new_ni = ntfsResolvePath(v.ntfsVol, parentNewPath, true);
        ntfs_inode* dir_old_ni = ntfsResolvePath(v.ntfsVol, parentOldPath, true);
        if (old_ni && dir_new_ni && dir_old_ni) {
            // Linking a directory under its own subtree and then removing its old name
            // would detach the whole branch from the root (rename(2) says EINVAL).
            const bool movesIntoItself =
                ntfsIsDirectoryInode(old_ni) && ntfsIsSelfOrDescendant(dir_new_ni, old_ni->mft_no);
            if (movesIntoItself) {
                LOGI("ntfsRenameFile: refusing to move directory '%s' into itself ('%s')",
                     oldFullPath.c_str(), newFullPath.c_str());
            }
            if (!movesIntoItself && ntfs_link(old_ni, dir_new_ni, uNew, static_cast<u8>(uNewLen)) == 0) {
                int delRet = ntfs_delete(v.ntfsVol, oldFullPath.c_str(), old_ni, dir_old_ni,
                                          uOld, static_cast<u8>(uOldLen));
                old_ni = nullptr;
                dir_old_ni = nullptr;
                if (delRet != 0) {
                    LOGI("ntfsRenameFile: linked '%s' OK but removing old name '%s' failed (errno=%d); retrying cleanup",
                         newFullPath.c_str(), oldFullPath.c_str(), errno);
                    ntfs_inode* retryOldNi = ntfsResolvePath(v.ntfsVol, oldPath, false);
                    ntfs_inode* retryDirNi = ntfsResolvePath(v.ntfsVol, parentOldPath, true);
                    if (retryOldNi && retryDirNi) {
                        if (ntfs_delete(v.ntfsVol, oldFullPath.c_str(), retryOldNi, retryDirNi,
                                         uOld, static_cast<u8>(uOldLen)) != 0) {
                            LOGI("ntfsRenameFile: retry cleanup of old name '%s' also failed (errno=%d); leaving stray link, move still reported successful",
                                 oldFullPath.c_str(), errno);
                        }
                    } else {
                        if (retryOldNi) ntfs_inode_close(retryOldNi);
                        if (retryDirNi) ntfs_inode_close(retryDirNi);
                    }
                }
                success = true;  // ntfs_link() succeeding is what makes the move real.
            }
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
    return success;
}

bool ntfsSetLastModifiedTime(int volumeId, const std::string& path, uint64_t epochSeconds) {
    auto& v = volumes[volumeId];
    if (v.readOnly) return false;
    bool success = false;
    ntfs_inode* ni = ntfsResolvePath(v.ntfsVol, path, true);
    if (ni) {
        uint64_t ntfsTime = (epochSeconds * 10000000ULL) + 116444736000000000ULL;
        ni->last_data_change_time = ntfsTime;
        ni->last_access_time = ntfsTime;
        ni->last_mft_change_time = ntfsTime;
        NInoSetDirty(ni);
        success = (ntfs_inode_close(ni) == 0);
    }
    return success;
}

void ntfsGetSpaceInfo(int volumeId, uint64_t& outTotalBytes, uint64_t& outFreeBytes) {
    auto& v = volumes[volumeId];
    ntfs_volume* vol = v.ntfsVol;
    s64 total_clusters = vol->nr_clusters;
    s64 free_cl = ntfs_attr_get_free_bits(vol->lcnbmp_na);
    outTotalBytes = static_cast<uint64_t>(total_clusters * vol->cluster_size);
    outFreeBytes  = static_cast<uint64_t>(free_cl * vol->cluster_size);
}

void* ntfsOpenStream(int volumeId, const std::string& path) {
    auto& v = volumes[volumeId];
    ntfs_inode* ni = ntfsResolvePath(v.ntfsVol, path, true);
    if (ni) {
        ntfs_attr* na = ntfs_attr_open(ni, AT_DATA, NULL, 0);
        if (na) {
            NtfsStream* ns = new NtfsStream();
            ns->inode = ni;
            ns->attr = na;
            v.openNtfsStreams.push_back(ns);
            return ns;
        } else {
            ntfs_inode_close(ni);
        }
    }
    return nullptr;
}

int32_t ntfsReadStream(int volumeId, void* handle, uint64_t offset, uint8_t* dest, size_t length) {
    auto& v = volumes[volumeId];
    NtfsStream* ns = reinterpret_cast<NtfsStream*>(handle);
    auto& streams = v.openNtfsStreams;
    if (std::find(streams.begin(), streams.end(), ns) == streams.end()) return -1;
    s64 br = ntfs_attr_pread(ns->attr, offset, length, dest);
    if (br >= 0) return static_cast<int32_t>(br);
    return -1;
}

void ntfsCloseStream(int volumeId, void* handle) {
    auto& v = volumes[volumeId];
    NtfsStream* ns = reinterpret_cast<NtfsStream*>(handle);
    auto& streams = v.openNtfsStreams;
    auto it = std::find(streams.begin(), streams.end(), ns);
    if (it == streams.end()) return;
    streams.erase(it);
    ntfs_attr_close(ns->attr);
    ntfs_inode_close(ns->inode);
    delete ns;
}

bool ntfsIsDirty(int volumeId) {
    if (volumeId < 0 || volumeId >= FF_VOLUMES) return false;
    auto& v = volumes[volumeId];
    if (!v.ntfsVol) return false;
    return (v.ntfsVol->flags & VOLUME_IS_DIRTY) != 0;
}

bool ntfsClearDirtyFlag(int volumeId) {
    if (volumeId < 0 || volumeId >= FF_VOLUMES) return false;
    auto& v = volumes[volumeId];
    if (!v.ntfsVol || v.readOnly) return false;
    const le16 newFlags = static_cast<le16>(v.ntfsVol->flags & ~VOLUME_IS_DIRTY);
    if (ntfs_volume_write_flags(v.ntfsVol, newFlags) != 0) {
        LOGI("ntfsClearDirtyFlag: ntfs_volume_write_flags failed on volume %d (errno=%d)", volumeId, errno);
        return false;
    }
    return true;
}