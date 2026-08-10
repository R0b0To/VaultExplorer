#pragma once

#include <cstdint>
#include <string>
#include <vector>

struct _ntfs_volume;
typedef struct _ntfs_volume ntfs_volume;
struct _ntfs_inode;
typedef struct _ntfs_inode ntfs_inode;
struct ntfs_device_operations;

constexpr size_t NTFS_DIRECTORY_MAX_ENTRIES = 50000;

extern "C" ntfs_device_operations vExplorer_ntfs_ops;

uint64_t recursiveNtfsFolderSize(int volumeId, const std::string& path);
ntfs_inode* createNtfsFile(ntfs_volume* volume, const std::string& path);

bool listNtfsDirectory(int volumeId, const std::string& pathSuffix,
                       std::vector<std::string>& results);

uint64_t ntfsGetFileSize(int volumeId, const std::string& path);
bool ntfsReadFileChunk(int volumeId, const std::string& path, uint64_t offset, size_t length, std::vector<uint8_t>& outBuffer);
bool ntfsWriteFileChunk(int volumeId, const std::string& path, uint64_t offset, const uint8_t* data, size_t length);
bool ntfsWriteBackFile(int volumeId, const std::string& targetPath, const std::string& sourceHostPath);
bool ntfsExtractFile(int volumeId, const std::string& targetPath, const std::string& destHostPath);
bool ntfsDeleteFile(int volumeId, const std::string& path);
bool ntfsCreateDirectory(int volumeId, const std::string& path);
bool ntfsRenameFile(int volumeId, const std::string& oldPath, const std::string& newPath);
bool ntfsSetLastModifiedTime(int volumeId, const std::string& path, uint64_t epochSeconds);
void ntfsGetSpaceInfo(int volumeId, uint64_t& outTotalBytes, uint64_t& outFreeBytes);
void* ntfsOpenStream(int volumeId, const std::string& path);
int32_t ntfsReadStream(int volumeId, void* handle, uint64_t offset, uint8_t* dest, size_t length);
void ntfsCloseStream(int volumeId, void* handle);

// Check & Repair tool (see containers/container_repair.cpp). Reads/clears
// the on-disk $Volume dirty flag (VOLUME_IS_DIRTY, in the VOLUME_INFORMATION
// attribute) -- the same flag Windows sets on an unclean unmount and that
// real `ntfsfix` clears once it's satisfied the volume is consistent.
// [volumeId]'s ntfs_volume must already be mounted (VolumeState::ntfsVol).
bool ntfsIsDirty(int volumeId);
bool ntfsClearDirtyFlag(int volumeId);
// Conservative Check & Repair directory pass. It removes only corrupt $I30
// index entries, leaving an uncertain target MFT record allocated.
bool ntfsHasCorruptDirectoryEntries(int volumeId);
bool ntfsRemoveCorruptDirectoryEntries(int volumeId);
