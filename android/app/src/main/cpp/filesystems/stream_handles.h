#pragma once

// Definitions for the opaque per-open-file stream handles that
// VolumeState::openNtfsStreams / openExtStreams (see session/volume_state.h)
// hold as void*/forward-declared pointers. Split out into its own header
// because three different translation units need the full definition:
// io/virtual_block_device.cpp (unmountVolume, to close anything still open),
// jni/session_bridge.cpp (lockNative, same reason), and
// jni/filesystem_bridge.cpp (openStream/readStream/closeStream, which
// actually create and use them).

extern "C" {
#include <ext2fs/ext2fs.h>
}

struct _ntfs_inode;
typedef struct _ntfs_inode ntfs_inode;
struct _ntfs_attr;
typedef struct _ntfs_attr ntfs_attr;

struct NtfsStream {
    ntfs_inode* inode = nullptr;
    ntfs_attr*  attr = nullptr;
};

struct ExtStream {
    ext2_file_t file = nullptr;
};
