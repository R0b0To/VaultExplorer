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