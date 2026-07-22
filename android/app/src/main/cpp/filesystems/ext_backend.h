#pragma once

#include <string>
#include <vector>

extern "C" {
#include <ext2fs/ext2fs.h>
}

constexpr size_t EXT_DIRECTORY_MAX_ENTRIES = 50000;

struct ExtDirContext {
    ext2_filsys fs;
    std::vector<std::string>* results;
};

// Used by extRenameFile: ext2fs_link()/ext2fs_unlink() don't update a
// moved directory's own ".." entry, so when a directory changes parent
// this walks its entries once to repoint ".." at the new parent inode.
struct ExtDotDotFixupContext {
    ext2_ino_t newParentIno;
};

int extDotDotFixupCallback(ext2_ino_t, int, struct ext2_dir_entry*, int, int, char*, void*);

bool extResolvePath(ext2_filsys fs, const std::string& path, ext2_ino_t* inode);
int extDirectoryEntry(ext2_ino_t, int, struct ext2_dir_entry*, int, int, char*, void*);
bool extOpenFile(ext2_filsys fs, const std::string& path, bool write, bool create, ext2_file_t* out);
bool extWriteFromHostFile(ext2_filsys fs, const std::string& path, const char* source);
bool extExtractToHostFile(ext2_filsys fs, const std::string& path, const char* destination);
uint64_t recursiveExtFolderSize(int volumeId, const std::string& path);

// Mount and format ext filesystems through the encrypted-sector I/O manager.
bool mountExtVolume(int volumeId);
bool formatExtVolume(int volumeId, const char* variant);
bool ensureExtBitmapsLoaded(int volumeId);

// The rest of these back filesystems/fs_ops.h's fsXxx functions for ext --
// see that header for the exact contract each one implements. Several are
// thin wrappers around the helpers above (extOpenFile, extResolvePath,
// extWriteFromHostFile, extExtractToHostFile); the rest were extracted
// from what used to be inline `else if (v.fsType == FS_EXT) { ... }`
// branches in jni/filesystem_bridge.cpp.
void extListDirectory(int volumeId, const std::string& pathSuffix, std::vector<std::string>& results);
uint64_t extGetFileSize(int volumeId, const std::string& path);
bool extReadFileChunk(int volumeId, const std::string& path, uint64_t offset, size_t length, std::vector<uint8_t>& outBuffer);
bool extWriteFileChunk(int volumeId, const std::string& path, uint64_t offset, const uint8_t* data, size_t length);
bool extWriteBackFile(int volumeId, const std::string& targetPath, const std::string& sourceHostPath);
bool extExtractFile(int volumeId, const std::string& targetPath, const std::string& destHostPath);
bool extDeleteFile(int volumeId, const std::string& path);
bool extCreateDirectory(int volumeId, const std::string& path);
bool extRenameFile(int volumeId, const std::string& oldPath, const std::string& newPath);
bool extSetLastModifiedTime(int volumeId, const std::string& path, uint64_t epochSeconds);
void extGetSpaceInfo(int volumeId, uint64_t& outTotalBytes, uint64_t& outFreeBytes);
void* extOpenStream(int volumeId, const std::string& path);
int32_t extReadStream(int volumeId, void* handle, uint64_t offset, uint8_t* dest, size_t length);
void extCloseStream(int volumeId, void* handle);