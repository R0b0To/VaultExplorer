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
#include <unistd.h>
extern "C" {
#include "device.h"
#include "inode.h"
#include "dir.h"
#include "attrib.h"
#include "index.h"
#include "layout.h"
}
#include "block_io.h"
#include "crypto/cascade.h"
#include "crypto/xts_tweak.h"
#include "volume_state.h"
#include "bitlocker_backend.h"
#include "filesystems/stream_handles.h"

namespace {
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
    if (volumeId >= 0 && volumeId < kMaxVolumes && volumes[volumeId].fd >= 0)
        fsync(volumes[volumeId].fd);
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
        isDirectory = (inode->mrec->flags & MFT_RECORD_IS_DIRECTORY) != 0;
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

bool ntfsHasCorruptDirectoryEntries(int volumeId) {
    return ntfsScanCorruptDirectoryEntries(volumeId, false);
}

bool ntfsRemoveCorruptDirectoryEntries(int volumeId) {
    return ntfsScanCorruptDirectoryEntries(volumeId, true);
}

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
    if (results.size() >= NTFS_DIRECTORY_MAX_ENTRIES) results.push_back("System:TRUNCATED");
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

extern "C" const char *ntfs_libntfs_version(void) {
    return "vaultexplorer-ntfs3g-edge";
}

uint64_t ntfsGetFileSize(int volumeId, const std::string& path) {
    auto& v = volumes[volumeId];
    uint64_t size = 0;
    std::string fullPath = "/" + path;
    ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());
    if (ni) {
        size = static_cast<uint64_t>(ni->data_size);
        ntfs_inode_close(ni);
    }
    return size;
}

bool ntfsReadFileChunk(int volumeId, const std::string& path, uint64_t offset, size_t length, std::vector<uint8_t>& outBuffer) {
    auto& v = volumes[volumeId];
    bool success = false;
    std::string fullPath = "/" + path;
    ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());
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
    bool success = false;
    std::string fullPath = "/" + path;
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
    std::string srcFullPath = "/" + srcPath;
    std::string destFullPath = "/" + destPath;
    ntfs_inode* src_ni = ntfs_pathname_to_inode(srcV.ntfsVol, NULL, srcFullPath.c_str());
    if (!src_ni) return false;
    ntfs_inode* dest_ni = ntfs_pathname_to_inode(destV.ntfsVol, NULL, destFullPath.c_str());
    if (!dest_ni) {
        dest_ni = createNtfsFile(destV.ntfsVol, destFullPath);
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

bool ntfsWriteBackFile(int volumeId, const std::string& targetPath, const std::string& sourceHostPath,
                        const CopyProgressCallback& onProgress) {
    constexpr size_t kIoBufferSize = 2097152;
    auto& v = volumes[volumeId];
    bool success = false;
    std::string fullPath = "/" + targetPath;
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
            std::ifstream inFile(sourceHostPath, std::ios::binary);
            if (inFile.is_open()) {
                std::unique_ptr<char[]> buf(new char[kIoBufferSize]);
                s64 offset = 0;
                bool writeError = false;
                bool cancelled = false;
                while (inFile && !writeError && !cancelled) {
                    inFile.read(buf.get(), kIoBufferSize);
                    std::streamsize n = inFile.gcount();
                    if (n > 0) {
                        s64 bw = ntfs_attr_pwrite(na, offset, n, buf.get());
                        if (bw != n) {
                            writeError = true;
                        } else {
                            offset += bw;
                            if (onProgress && !onProgress(static_cast<uint64_t>(bw))) cancelled = true;
                        }
                    }
                }
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

bool ntfsExtractFile(int volumeId, const std::string& targetPath, const std::string& destHostPath) {
    constexpr size_t kIoBufferSize = 2097152;
    auto& v = volumes[volumeId];
    bool success = false;
    std::string fullPath = "/" + targetPath;
    ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());
    if (ni) {
        ntfs_attr* na = ntfs_attr_open(ni, AT_DATA, NULL, 0);
        if (na) {
            std::ofstream outFile(destHostPath, std::ios::binary);
            if (outFile.is_open()) {
                std::unique_ptr<unsigned char[]> buf(new unsigned char[kIoBufferSize]);
                s64 offset = 0;
                while (true) {
                    s64 br = ntfs_attr_pread(na, offset, kIoBufferSize, buf.get());
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
    return success;
}

bool ntfsDeleteFile(int volumeId, const std::string& path) {
    auto& v = volumes[volumeId];
    bool success = false;
    std::string fullPath = "/" + path;
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
    bool success = false;
    std::string fullPath = "/" + path;
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
    return success;
}

bool ntfsRenameFile(int volumeId, const std::string& oldPath, const std::string& newPath) {
    auto& v = volumes[volumeId];
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
    if (uOldLen >= 0 && uNewLen >= 0) {
        ntfs_inode* existing_dest_ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, newFullPath.c_str());
        if (existing_dest_ni) {
            ntfs_inode_close(existing_dest_ni);
            if (uOld) free(uOld);
            if (uNew) free(uNew);
            return false;
        }
        ntfs_inode* old_ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, oldFullPath.c_str());
        ntfs_inode* dir_new_ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, parentNewPath.c_str());
        ntfs_inode* dir_old_ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, parentOldPath.c_str());
        if (old_ni && dir_new_ni && dir_old_ni) {
            if (ntfs_link(old_ni, dir_new_ni, uNew, static_cast<u8>(uNewLen)) == 0) {
                success = (ntfs_delete(v.ntfsVol, oldFullPath.c_str(), old_ni, dir_old_ni,
                                        uOld, static_cast<u8>(uOldLen)) == 0);
                old_ni = nullptr;
                dir_old_ni = nullptr;
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
    bool success = false;
    std::string fullPath = "/" + path;
    ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());
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
    std::string fullPath = "/" + path;
    ntfs_inode* ni = ntfs_pathname_to_inode(v.ntfsVol, NULL, fullPath.c_str());
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