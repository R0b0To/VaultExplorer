#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "copy_progress_callback.h"

uint64_t recursiveFatFolderSize(int volumeId, const std::string& path);

// Returns false when the listing could not be read reliably (I/O error, volume
// not mounted, read failing part-way) -- `results` must then not be trusted or
// cached. A directory that simply doesn't exist lists as empty and returns true.
bool fatListDirectory(int volumeId, const std::string& pathSuffix, std::vector<std::string>& results);
uint64_t fatGetFileSize(int volumeId, const std::string& path);
bool fatReadFileChunk(int volumeId, const std::string& path, uint64_t offset, size_t length, std::vector<uint8_t>& outBuffer);
bool fatWriteFileChunk(int volumeId, const std::string& path, uint64_t offset, const uint8_t* data, size_t length);
bool fatWriteBackFile(int volumeId, const std::string& targetPath, const std::string& sourceHostPath,
                       const CopyProgressCallback& onProgress = nullptr);
bool fatExtractFile(int volumeId, const std::string& targetPath, const std::string& destHostPath,
                     const CopyProgressCallback& onProgress = nullptr);
bool fatDeleteFile(int volumeId, const std::string& path);
bool fatCreateDirectory(int volumeId, const std::string& path);
bool fatRenameFile(int volumeId, const std::string& oldPath, const std::string& newPath);
bool fatCopyFile(int srcVolId, const std::string& srcPath, int destVolId, const std::string& destPath,
                  const CopyProgressCallback& onProgress = nullptr);
bool fatSetLastModifiedTime(int volumeId, const std::string& path, uint64_t epochSeconds);
void fatGetSpaceInfo(int volumeId, uint64_t& outTotalBytes, uint64_t& outFreeBytes);
std::string fatGetFilesystemLabel(int volumeId);
void* fatOpenStream(int volumeId, const std::string& path);
int32_t fatReadStream(int volumeId, void* handle, uint64_t offset, uint8_t* dest, size_t length);
void fatCloseStream(int volumeId, void* handle);