#include "fat_backend.h"

#include <algorithm>
#include <cstring>
#include <fstream>
#include <memory>

#include "ff.h"
#include "filesystem_paths.h"
#include "container_utils.h"
#include "volume_state.h"

uint64_t recursiveFatFolderSize(int volumeId, const std::string& path) {
    std::string fullPath = drivePaths[volumeId];
    if (!path.empty()) fullPath += '/' + path;

    uint64_t total = 0;
    DIR directory;
    FILINFO entry;
    if (f_opendir(&directory, fullPath.c_str()) != FR_OK) return 0;
    while (f_readdir(&directory, &entry) == FR_OK && entry.fname[0]) {
        if (entry.fattrib & AM_DIR) {
            const std::string child = path.empty() ? std::string(entry.fname)
                                                   : path + '/' + entry.fname;
            total += recursiveFatFolderSize(volumeId, child);
        } else {
            total += entry.fsize;
        }
    }
    f_closedir(&directory);
    return total;
}

// ----------------------------------------------------------------====
// The functions below implement filesystems/fs_ops.h's fsXxx() contract
// for FAT/exFAT. Extracted verbatim (same FatFs call sequences, same
// error-handling conditions) from what used to be inline
// `if (v.fsType == VolumeState::FS_FATFS) { ... }` branches in
// jni/filesystem_bridge.cpp -- the only changes are: parameter names
// (targetName/nativePath -> path, body/len -> data/length), and, for
// fatReadFileChunk/fatOpenStream/fatReadStream, swapping "allocate a JNI
// type and copy into it" for "fill the plain-C++ out-parameter" since
// this file has no JNIEnv access (by design -- see fs_ops.h).
// ----------------------------------------------------------------====

namespace { constexpr size_t kMaxDirEntries = 50000; }

void fatListDirectory(int volumeId, const std::string& pathSuffix, std::vector<std::string>& results) {
    std::string fullPath = drivePaths[volumeId];
    if (!pathSuffix.empty()) {
        fullPath += '/';
        fullPath += pathSuffix;
    }
    DIR dir;
    FILINFO fno;
    if (f_opendir(&dir, fullPath.c_str()) == FR_OK) {
        while (f_readdir(&dir, &fno) == FR_OK && fno.fname[0]) {
            if (results.size() >= kMaxDirEntries) {
                results.push_back("System:TRUNCATED");
                break;
            }
            const char* name = fno.fname;
            if (strcmp(name, "SYSTEM~1") == 0 || strcmp(name, "$RECYCLE.BIN") == 0) continue;

            const uint64_t ts = fatToUnixTimestamp(fno.fdate, fno.ftime);
            if (fno.fattrib & AM_DIR) {
                results.push_back("[DIR] " + std::string(name) + "|0|" + std::to_string(ts));
            } else {
                results.push_back(std::string(name) + "|" + std::to_string(fno.fsize) + "|" + std::to_string(ts));
            }
        }
        f_closedir(&dir);
    }
}

uint64_t fatGetFileSize(int volumeId, const std::string& path) {
    FIL f;
    uint64_t size = 0;
    std::string fatPath = std::string(drivePaths[volumeId]) + "/" + path;
    if (f_open(&f, fatPath.c_str(), FA_READ) == FR_OK) {
        size = static_cast<uint64_t>(f_size(&f));
        f_close(&f);
    }
    return size;
}

bool fatReadFileChunk(int volumeId, const std::string& path, uint64_t offset, size_t length, std::vector<uint8_t>& outBuffer) {
    FIL f;
    bool success = false;
    std::string fatPath = std::string(drivePaths[volumeId]) + "/" + path;
    if (f_open(&f, fatPath.c_str(), FA_READ) == FR_OK) {
        f_lseek(&f, static_cast<FSIZE_t>(offset));
        std::unique_ptr<unsigned char[]> buffer(new unsigned char[length]);
        UINT br = 0;
        if (f_read(&f, buffer.get(), static_cast<UINT>(length), &br) == FR_OK && br > 0) {
            outBuffer.assign(buffer.get(), buffer.get() + br);
            success = true;
        }
        f_close(&f);
    }
    return success;
}

bool fatWriteFileChunk(int volumeId, const std::string& path, uint64_t offset, const uint8_t* data, size_t length) {
    FIL f;
    bool success = false;
    std::string fatPath = std::string(drivePaths[volumeId]) + "/" + path;
    BYTE openMode = (offset == 0) ? (FA_WRITE | FA_CREATE_ALWAYS) : (FA_WRITE | FA_OPEN_ALWAYS);
    if (f_open(&f, fatPath.c_str(), openMode) == FR_OK) {
        if (f_lseek(&f, static_cast<FSIZE_t>(offset)) == FR_OK) {
            UINT bw = 0;
            if (f_write(&f, data, static_cast<UINT>(length), &bw) == FR_OK && bw == static_cast<UINT>(length))
                success = true;
        }
        f_close(&f);
    }
    return success;
}

bool fatWriteBackFile(int volumeId, const std::string& targetPath, const std::string& sourceHostPath) {
    constexpr size_t kIoBufferSize = 262144;
    FIL f;
    bool success = false;
    std::string fatPath = std::string(drivePaths[volumeId]) + "/" + targetPath;
    if (f_open(&f, fatPath.c_str(), FA_WRITE | FA_CREATE_ALWAYS) == FR_OK) {
        std::ifstream inFile(sourceHostPath, std::ios::binary);
        if (inFile.is_open()) {
            std::unique_ptr<char[]> buf(new char[kIoBufferSize]);
            UINT bw;
            bool writeError = false;
            while (inFile && !writeError) {
                inFile.read(buf.get(), kIoBufferSize);
                std::streamsize n = inFile.gcount();
                if (n > 0) {
                    FRESULT res = f_write(&f, buf.get(), static_cast<UINT>(n), &bw);
                    if (res != FR_OK || bw != static_cast<UINT>(n)) {
                        writeError = true;
                    }
                }
            }
            if (!writeError) {
                success = true;
            }
        }
        f_close(&f);
        if (!success) {
            f_unlink(fatPath.c_str());
        }
    }
    return success;
}

bool fatExtractFile(int volumeId, const std::string& targetPath, const std::string& destHostPath) {
    constexpr size_t kIoBufferSize = 262144;
    FIL f;
    bool success = false;
    std::string fatPath = std::string(drivePaths[volumeId]) + "/" + targetPath;
    if (f_open(&f, fatPath.c_str(), FA_READ) == FR_OK) {
        std::ofstream outFile(destHostPath, std::ios::binary);
        if (outFile.is_open()) {
            std::unique_ptr<unsigned char[]> buf(new unsigned char[kIoBufferSize]);
            UINT br;
            while (f_read(&f, buf.get(), kIoBufferSize, &br) == FR_OK && br > 0)
                outFile.write(reinterpret_cast<char*>(buf.get()), br);
            success = true;
        }
        f_close(&f);
    }
    return success;
}

bool fatDeleteFile(int volumeId, const std::string& path) {
    std::string fatPath = std::string(drivePaths[volumeId]) + "/" + path;
    return f_unlink(fatPath.c_str()) == FR_OK;
}

bool fatCreateDirectory(int volumeId, const std::string& path) {
    std::string fullPath = std::string(drivePaths[volumeId]) + "/" + path;
    return f_mkdir(fullPath.c_str()) == FR_OK;
}

bool fatRenameFile(int volumeId, const std::string& oldPath, const std::string& newPath) {
    std::string fullOld = std::string(drivePaths[volumeId]) + "/" + oldPath;
    std::string fullNew = std::string(drivePaths[volumeId]) + "/" + newPath;
    return f_rename(fullOld.c_str(), fullNew.c_str()) == FR_OK;
}

bool fatSetLastModifiedTime(int volumeId, const std::string& path, uint64_t epochSeconds) {
    WORD fdate = 0, ftime = 0;
    unixToFatTimestamp(epochSeconds, fdate, ftime);
    std::string fatPath = std::string(drivePaths[volumeId]) + "/" + path;
    FILINFO fno = {};
    fno.fdate = fdate;
    fno.ftime = ftime;
    return f_utime(fatPath.c_str(), &fno) == FR_OK;
}

void fatGetSpaceInfo(int volumeId, uint64_t& outTotalBytes, uint64_t& outFreeBytes) {
    FATFS* fs;
    DWORD fre_clust;
    if (f_getfree(drivePaths[volumeId], &fre_clust, &fs) == FR_OK) {
        outTotalBytes = static_cast<uint64_t>(fs->n_fatent - 2) * fs->csize * 512;
        outFreeBytes  = static_cast<uint64_t>(fre_clust) * fs->csize * 512;
    }
}

void* fatOpenStream(int volumeId, const std::string& path) {
    auto& v = volumes[volumeId];
    FIL* f = new FIL();
    std::string fatPath = std::string(drivePaths[volumeId]) + "/" + path;
    if (f_open(f, fatPath.c_str(), FA_READ) == FR_OK) {
        v.openStreams.push_back(f);
        return f;
    }
    delete f;
    return nullptr;
}

int32_t fatReadStream(int volumeId, void* handle, uint64_t offset, uint8_t* dest, size_t length) {
    auto& v = volumes[volumeId];
    FIL* f = reinterpret_cast<FIL*>(handle);
    auto& streams = v.openStreams;
    if (std::find(streams.begin(), streams.end(), f) == streams.end()) return -1;

    f_lseek(f, static_cast<FSIZE_t>(offset));
    UINT br = 0;
    if (f_read(f, dest, static_cast<UINT>(length), &br) == FR_OK)
        return static_cast<int32_t>(br);
    return -1;
}

void fatCloseStream(int volumeId, void* handle) {
    auto& v = volumes[volumeId];
    FIL* f = reinterpret_cast<FIL*>(handle);
    auto& streams = v.openStreams;
    auto it = std::find(streams.begin(), streams.end(), f);
    if (it == streams.end()) return;
    streams.erase(it);
    f_close(f);
    delete f;
}
