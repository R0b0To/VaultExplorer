#pragma once

#include <cstdint>
#include <string>
#include <vector>

struct _ntfs_volume;
typedef struct _ntfs_volume ntfs_volume;
struct _ntfs_inode;
typedef struct _ntfs_inode ntfs_inode;
struct ntfs_device_operations;

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