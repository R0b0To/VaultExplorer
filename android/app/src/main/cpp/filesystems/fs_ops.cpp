#include "fs_ops.h"

#include "volume_state.h"
#include "fat_backend.h"
#include "ntfs_backend.h"
#include "ext_backend.h"

void fsListDirectory(int volId, const std::string& pathSuffix, std::vector<std::string>& outResults) {
    switch (volumes[volId].fsType) {
        case VolumeState::FS_FATFS: fatListDirectory(volId, pathSuffix, outResults); break;
        case VolumeState::FS_NTFS:  listNtfsDirectory(volId, pathSuffix, outResults); break;
        case VolumeState::FS_EXT:   extListDirectory(volId, pathSuffix, outResults); break;
        default: break;
    }
}

uint64_t fsGetFileSize(int volId, const std::string& path) {
    switch (volumes[volId].fsType) {
        case VolumeState::FS_FATFS: return fatGetFileSize(volId, path);
        case VolumeState::FS_NTFS:  return ntfsGetFileSize(volId, path);
        case VolumeState::FS_EXT:   return extGetFileSize(volId, path);
        default: return 0;
    }
}

uint64_t fsGetFolderSize(int volId, const std::string& path) {
    switch (volumes[volId].fsType) {
        case VolumeState::FS_FATFS: return recursiveFatFolderSize(volId, path);
        case VolumeState::FS_NTFS:  return recursiveNtfsFolderSize(volId, path);
        case VolumeState::FS_EXT:   return recursiveExtFolderSize(volId, path);
        default: return 0;
    }
}

bool fsReadFileChunk(int volId, const std::string& path, uint64_t offset,
                      size_t length, std::vector<uint8_t>& outBuffer) {
    switch (volumes[volId].fsType) {
        case VolumeState::FS_FATFS: return fatReadFileChunk(volId, path, offset, length, outBuffer);
        case VolumeState::FS_NTFS:  return ntfsReadFileChunk(volId, path, offset, length, outBuffer);
        case VolumeState::FS_EXT:   return extReadFileChunk(volId, path, offset, length, outBuffer);
        default: return false;
    }
}

bool fsWriteFileChunk(int volId, const std::string& path, uint64_t offset,
                      const uint8_t* data, size_t length) {
    switch (volumes[volId].fsType) {
        case VolumeState::FS_FATFS: return fatWriteFileChunk(volId, path, offset, data, length);
        case VolumeState::FS_NTFS:  return ntfsWriteFileChunk(volId, path, offset, data, length);
        case VolumeState::FS_EXT:   return extWriteFileChunk(volId, path, offset, data, length);
        default: return false;
    }
}

bool fsWriteBackFile(int volId, const std::string& targetPath, const std::string& sourceHostPath) {
    switch (volumes[volId].fsType) {
        case VolumeState::FS_FATFS: return fatWriteBackFile(volId, targetPath, sourceHostPath);
        case VolumeState::FS_NTFS:  return ntfsWriteBackFile(volId, targetPath, sourceHostPath);
        case VolumeState::FS_EXT:   return extWriteBackFile(volId, targetPath, sourceHostPath);
        default: return false;
    }
}

bool fsExtractFile(int volId, const std::string& targetPath, const std::string& destHostPath) {
    switch (volumes[volId].fsType) {
        case VolumeState::FS_FATFS: return fatExtractFile(volId, targetPath, destHostPath);
        case VolumeState::FS_NTFS:  return ntfsExtractFile(volId, targetPath, destHostPath);
        case VolumeState::FS_EXT:   return extExtractFile(volId, targetPath, destHostPath);
        default: return false;
    }
}

bool fsDeleteFile(int volId, const std::string& path) {
    switch (volumes[volId].fsType) {
        case VolumeState::FS_FATFS: return fatDeleteFile(volId, path);
        case VolumeState::FS_NTFS:  return ntfsDeleteFile(volId, path);
        case VolumeState::FS_EXT:   return extDeleteFile(volId, path);
        default: return false;
    }
}

bool fsCreateDirectory(int volId, const std::string& path) {
    switch (volumes[volId].fsType) {
        case VolumeState::FS_FATFS: return fatCreateDirectory(volId, path);
        case VolumeState::FS_NTFS:  return ntfsCreateDirectory(volId, path);
        case VolumeState::FS_EXT:   return extCreateDirectory(volId, path);
        default: return false;
    }
}

bool fsRenameFile(int volId, const std::string& oldPath, const std::string& newPath) {
    switch (volumes[volId].fsType) {
        case VolumeState::FS_FATFS: return fatRenameFile(volId, oldPath, newPath);
        case VolumeState::FS_NTFS:  return ntfsRenameFile(volId, oldPath, newPath);
        case VolumeState::FS_EXT:   return extRenameFile(volId, oldPath, newPath);
        default: return false;
    }
}

bool fsSetLastModifiedTime(int volId, const std::string& path, uint64_t epochSeconds) {
    switch (volumes[volId].fsType) {
        case VolumeState::FS_FATFS: return fatSetLastModifiedTime(volId, path, epochSeconds);
        case VolumeState::FS_NTFS:  return ntfsSetLastModifiedTime(volId, path, epochSeconds);
        case VolumeState::FS_EXT:   return extSetLastModifiedTime(volId, path, epochSeconds);
        default: return false;
    }
}

void fsGetSpaceInfo(int volId, uint64_t& outTotalBytes, uint64_t& outFreeBytes) {
    outTotalBytes = 0;
    outFreeBytes = 0;
    switch (volumes[volId].fsType) {
        case VolumeState::FS_FATFS: fatGetSpaceInfo(volId, outTotalBytes, outFreeBytes); break;
        case VolumeState::FS_NTFS:  ntfsGetSpaceInfo(volId, outTotalBytes, outFreeBytes); break;
        case VolumeState::FS_EXT:   extGetSpaceInfo(volId, outTotalBytes, outFreeBytes); break;
        default: break;
    }
}

void* fsOpenStream(int volId, const std::string& path) {
    switch (volumes[volId].fsType) {
        case VolumeState::FS_FATFS: return fatOpenStream(volId, path);
        case VolumeState::FS_NTFS:  return ntfsOpenStream(volId, path);
        case VolumeState::FS_EXT:   return extOpenStream(volId, path);
        default: return nullptr;
    }
}

int32_t fsReadStream(int volId, void* handle, uint64_t offset, uint8_t* dest, size_t length) {
    switch (volumes[volId].fsType) {
        case VolumeState::FS_FATFS: return fatReadStream(volId, handle, offset, dest, length);
        case VolumeState::FS_NTFS:  return ntfsReadStream(volId, handle, offset, dest, length);
        case VolumeState::FS_EXT:   return extReadStream(volId, handle, offset, dest, length);
        default: return -1;
    }
}

void fsCloseStream(int volId, void* handle) {
    switch (volumes[volId].fsType) {
        case VolumeState::FS_FATFS: fatCloseStream(volId, handle); break;
        case VolumeState::FS_NTFS:  ntfsCloseStream(volId, handle); break;
        case VolumeState::FS_EXT:   extCloseStream(volId, handle); break;
        default: break;
    }
}
