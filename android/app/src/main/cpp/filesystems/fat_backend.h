#pragma once

#include <cstdint>
#include <string>
#include <vector>

uint64_t recursiveFatFolderSize(int volumeId, const std::string& path);

// The rest of these back filesystems/fs_ops.h's fsXxx functions for FAT --
// see that header for the exact contract each one implements. All take
// int volumeId and look up volumes[volumeId] themselves, matching
// recursiveFatFolderSize above.
void fatListDirectory(int volumeId, const std::string& pathSuffix, std::vector<std::string>& results);
uint64_t fatGetFileSize(int volumeId, const std::string& path);
bool fatReadFileChunk(int volumeId, const std::string& path, uint64_t offset, size_t length, std::vector<uint8_t>& outBuffer);
bool fatWriteFileChunk(int volumeId, const std::string& path, uint64_t offset, const uint8_t* data, size_t length);
bool fatWriteBackFile(int volumeId, const std::string& targetPath, const std::string& sourceHostPath);
bool fatExtractFile(int volumeId, const std::string& targetPath, const std::string& destHostPath);
bool fatDeleteFile(int volumeId, const std::string& path);
bool fatCreateDirectory(int volumeId, const std::string& path);
bool fatRenameFile(int volumeId, const std::string& oldPath, const std::string& newPath);
bool fatSetLastModifiedTime(int volumeId, const std::string& path, uint64_t epochSeconds);
void fatGetSpaceInfo(int volumeId, uint64_t& outTotalBytes, uint64_t& outFreeBytes);
void* fatOpenStream(int volumeId, const std::string& path);
int32_t fatReadStream(int volumeId, void* handle, uint64_t offset, uint8_t* dest, size_t length);
void fatCloseStream(int volumeId, void* handle);

