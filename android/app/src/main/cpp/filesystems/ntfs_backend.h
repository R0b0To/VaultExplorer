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

// Lists the NTFS directory at [pathSuffix] ("" or "/" for root) on
// volumes[volumeId].ntfsVol, appending "name|size|mtime" entries to
// [results] ("[DIR] " prefix for directories). NTFS metadata files
// ($MFT, $LogFile, ...) and "System Volume Information" are filtered out.
// Returns false if the volume isn't NTFS-mounted or the directory can't be
// opened; [results] is left unmodified in that case. Deliberately takes
// only opaque/basic types so callers don't need the NTFS-3G headers —
// mirrors recursiveNtfsFolderSize/createNtfsFile above.
bool listNtfsDirectory(int volumeId, const std::string& pathSuffix,
                       std::vector<std::string>& results);

// The rest of these back filesystems/fs_ops.h's fsXxx functions for NTFS --
// see that header for the exact contract each one implements. Same opaque-
// type discipline as listNtfsDirectory above: callers outside this file
// never see an ntfs_inode*/ntfs_attr* (stream handles are the one
// exception, returned/accepted as void* -- see fs_ops.h's note on why).
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