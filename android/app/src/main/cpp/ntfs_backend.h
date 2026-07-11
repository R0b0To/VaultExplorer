#pragma once

#include <cstdint>
#include <string>

struct _ntfs_volume;
typedef struct _ntfs_volume ntfs_volume;
struct _ntfs_inode;
typedef struct _ntfs_inode ntfs_inode;
struct ntfs_device_operations;

extern "C" ntfs_device_operations vExplorer_ntfs_ops;

uint64_t recursiveNtfsFolderSize(int volumeId, const std::string& path);
ntfs_inode* createNtfsFile(ntfs_volume* volume, const std::string& path);
