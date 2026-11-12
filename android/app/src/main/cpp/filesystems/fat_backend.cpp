#include "fat_backend.h"
#include "dir_entry_wire.h"
#include <algorithm>
#include <android/log.h>
#include <chrono>
#include <cstring>
#include <fcntl.h>
#include <memory>
#include <sys/stat.h>
#include <unistd.h>
#include "ff.h"
#include "diskio.h"
#include "filesystem_paths.h"
#include "container_utils.h"
#include "volume_state.h"
#include "io/host_file.h"

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

namespace {
constexpr size_t kMaxDirEntries = 50000;
// FatFs results meaning the volume's I/O or its in-memory state (window,
// free-cluster counters, file-object ids) can't be trusted any more.
bool isIoClassError(FRESULT fr) {
    switch (fr) {
        case FR_DISK_ERR:
        case FR_INT_ERR:
        case FR_NOT_READY:
        case FR_INVALID_OBJECT:
        case FR_NOT_ENABLED:
        case FR_NO_FILESYSTEM:
            return true;
        default:
            return false;
    }
}

// Remembers that this volume saw an I/O-class error so the next operation
// that finds it idle rebuilds the FatFs state (recoverFatIfNeeded). Without
// this a poisoned instance -- e.g. a dirty window that can't be written --
// kept failing every call (empty listings, unreadable files, "disk full")
// until the user unmounted and mounted the container again.
void noteFatError(int volumeId, FRESULT fr) {
    if (isIoClassError(fr)) volumes[volumeId].fatNeedsRemount = true;
}

// Failures in this file used to collapse into a bare `false`, which the Dart
// layer reports as "disk full" whatever the real cause was. Logging the
// FatFs result code (no file names) keeps a field report diagnosable.
void logFatFailure(const char* op, int volumeId, FRESULT fr) {
    __android_log_print(ANDROID_LOG_WARN, "VaultExplorer_FatIO",
                        "%s failed: vol=%d fr=%d", op, volumeId, static_cast<int>(fr));
    noteFatError(volumeId, fr);
}

// Marks FIL objects a copy/extract/write-back keeps open across its
// lock-yield windows (the native lock is released between chunks so listings
// can interleave). While any exist, remounting would invalidate them.
class FatActiveFileGuard {
public:
    explicit FatActiveFileGuard(int volumeId) : volumeId_(volumeId) {
        ++volumes[volumeId_].fatActiveFiles;
    }
    ~FatActiveFileGuard() {
        if (volumes[volumeId_].fatActiveFiles > 0) --volumes[volumeId_].fatActiveFiles;
    }
    FatActiveFileGuard(const FatActiveFileGuard&) = delete;
    FatActiveFileGuard& operator=(const FatActiveFileGuard&) = delete;

private:
    int volumeId_;
};

// Rebuilds the FatFs state of a volume flagged by noteFatError, once nothing
// holds open files on it. Pending bytes are flushed first; if even that
// fails the backing store is the problem and a remount would only discard
// data, so it waits. f_mount(..., 1) drops the (possibly unwritable) dirty
// window and re-reads the volume; the full FAT scan FF_FS_NOFSINFO forces on
// the next f_getfree also corrects the free-space figures.
void recoverFatIfNeeded(int volumeId) {
    VolumeState& v = volumes[volumeId];
    if (!v.fatNeedsRemount) return;
    if (v.fatActiveFiles > 0) return;
    if (disk_ioctl(static_cast<BYTE>(volumeId), CTRL_SYNC, nullptr) != RES_OK) return;
    {
        std::lock_guard<std::mutex> cacheLock(v.decryptedBlockCacheMutex);
        v.decryptedBlockCache.clear();
    }
    const FRESULT fr = f_mount(&v.fatfs, drivePaths[volumeId], 1);
    __android_log_print(ANDROID_LOG_WARN, "VaultExplorer_FatIO",
                        "recovery remount: vol=%d fr=%d", volumeId, static_cast<int>(fr));
    if (fr == FR_OK) v.fatNeedsRemount = false;
}

// The retry-after-remount used by the open/opendir paths. Skipped while a
// copy owns open files on this volume: f_mount would invalidate them and
// fail that copy for an error that belongs to someone else's call.
bool fatRemountForRetry(int volumeId, FRESULT fr) {
    if (fr != FR_NOT_READY && fr != FR_DISK_ERR) return false;
    VolumeState& v = volumes[volumeId];
    if (v.fatActiveFiles > 0) {
        noteFatError(volumeId, fr);
        return false;
    }
    f_mount(&v.fatfs, drivePaths[volumeId], 1);
    return true;
}

inline bool ensureFatFsValid(int volumeId) {
    recoverFatIfNeeded(volumeId);
    if (volumes[volumeId].fatfs.fs_type == 0) {
        return f_mount(&volumes[volumeId].fatfs, drivePaths[volumeId], 1) == FR_OK;
    }
    return true;
}

int openHostSource(const std::string& sourceHostPath) {
    if (sourceHostPath.rfind("/proc/self/fd/", 0) == 0) {
        int fd = std::atoi(sourceHostPath.c_str() + 14);
        int duplicated = dup(fd);
        if (duplicated >= 0) {
            lseek(duplicated, 0, SEEK_SET);
            return duplicated;
        }
    }
    return hostOpen(sourceHostPath.c_str(), O_RDONLY | O_CLOEXEC);
}

int openHostDest(const std::string& destHostPath) {
    if (destHostPath.rfind("/proc/self/fd/", 0) == 0) {
        int fd = std::atoi(destHostPath.c_str() + 14);
        int duplicated = dup(fd);
        if (duplicated >= 0) {
            lseek(duplicated, 0, SEEK_SET);
            return duplicated;
        }
    }
    return hostOpen(destHostPath.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
}
}

bool fatListDirectory(int volumeId, const std::string& pathSuffix, std::vector<std::string>& results) {
    ensureFatFsValid(volumeId);
    std::string fullPath = drivePaths[volumeId];
    if (!pathSuffix.empty()) {
        fullPath += '/';
        fullPath += pathSuffix;
    }
    DIR dir;
    FILINFO fno;
    FRESULT fr = f_opendir(&dir, fullPath.c_str());
    if (fatRemountForRetry(volumeId, fr)) {
        fr = f_opendir(&dir, fullPath.c_str());
    }
    if (fr != FR_OK) {
        // A folder that doesn't exist reads as empty, as before. Anything
        // else (I/O error, volume not mounted, ...) must not look like an
        // empty folder: the browser would show and cache it, and Vault
        // Sync would treat every file on the other side as missing here.
        if (fr == FR_NO_PATH || fr == FR_NO_FILE || fr == FR_INVALID_NAME) return true;
        logFatFailure("opendir", volumeId, fr);
        return false;
    }
    FRESULT readRes = FR_OK;
    while ((readRes = f_readdir(&dir, &fno)) == FR_OK && fno.fname[0]) {
        if (results.size() >= kMaxDirEntries) {
            results.push_back("System:TRUNCATED");
            break;
        }
        const char* name = fno.fname;
        if (strcmp(name, "SYSTEM~1") == 0 || strcmp(name, "$RECYCLE.BIN") == 0) continue;
        const uint64_t ts = fatToUnixTimestamp(fno.fdate, fno.ftime);
        const bool isDir = fno.fattrib & AM_DIR;
        results.push_back(encodeDirEntryWire(name, isDir, fno.fsize, ts));
    }
    f_closedir(&dir);
    if (readRes != FR_OK) {
        // A read error part-way used to end the loop like end-of-directory,
        // returning a silently truncated listing.
        logFatFailure("readdir", volumeId, readRes);
        results.clear();
        return false;
    }
    return true;
}

int64_t fatGetFileSize(int volumeId, const std::string& path) {
    ensureFatFsValid(volumeId);
    FIL f;
    int64_t size = -1;
    std::string fatPath = std::string(drivePaths[volumeId]) + "/" + path;
    FRESULT fr = f_open(&f, fatPath.c_str(), FA_READ);
    if (fatRemountForRetry(volumeId, fr)) {
        fr = f_open(&f, fatPath.c_str(), FA_READ);
    }
    if (fr == FR_OK) {
        size = static_cast<int64_t>(f_size(&f));
        f_close(&f);
    } else {
        noteFatError(volumeId, fr);
    }
    return size;
}

bool fatReadFileChunk(int volumeId, const std::string& path, uint64_t offset, size_t length, std::vector<uint8_t>& outBuffer) {
    ensureFatFsValid(volumeId);
    FIL f;
    bool success = false;
    std::string fatPath = std::string(drivePaths[volumeId]) + "/" + path;
    FRESULT fr = f_open(&f, fatPath.c_str(), FA_READ);
    if (fatRemountForRetry(volumeId, fr)) {
        fr = f_open(&f, fatPath.c_str(), FA_READ);
    }
    if (fr == FR_OK) {
        f_lseek(&f, static_cast<FSIZE_t>(offset));
        std::unique_ptr<unsigned char[]> buffer(new unsigned char[length]);
        UINT br = 0;
        const FRESULT readRes = f_read(&f, buffer.get(), static_cast<UINT>(length), &br);
        if (readRes == FR_OK && br > 0) {
            outBuffer.assign(buffer.get(), buffer.get() + br);
            success = true;
        } else if (readRes != FR_OK) {
            logFatFailure("read", volumeId, readRes);
        }
        f_close(&f);
    } else {
        noteFatError(volumeId, fr);
    }
    return success;
}

bool fatWriteFileChunk(int volumeId, const std::string& path, uint64_t offset, const uint8_t* data, size_t length) {
    ensureFatFsValid(volumeId);
    FIL f;
    bool success = false;
    std::string fatPath = std::string(drivePaths[volumeId]) + "/" + path;
    BYTE openMode = (offset == 0) ? (FA_WRITE | FA_CREATE_ALWAYS) : (FA_WRITE | FA_OPEN_ALWAYS);
    FRESULT fr = f_open(&f, fatPath.c_str(), openMode);
    if (fatRemountForRetry(volumeId, fr)) {
        fr = f_open(&f, fatPath.c_str(), openMode);
    }
    if (fr == FR_OK) {
        const FRESULT seekRes = f_lseek(&f, static_cast<FSIZE_t>(offset));
        if (seekRes == FR_OK) {
            UINT bw = 0;
            const FRESULT writeRes = f_write(&f, data, static_cast<UINT>(length), &bw);
            if (writeRes == FR_OK && bw == static_cast<UINT>(length)) {
                success = true;
            } else {
                // FR_OK with a short write is FatFs's "no free cluster"; any
                // other result is an I/O or internal error, not a full disk.
                logFatFailure(writeRes == FR_OK ? "write(short)" : "write", volumeId, writeRes);
            }
        } else {
            logFatFailure("seek", volumeId, seekRes);
        }
        // f_close commits the directory entry (size) and syncs. Ignoring its
        // result reported success for files whose size/data never landed.
        const FRESULT closeRes = f_close(&f);
        if (closeRes != FR_OK) {
            logFatFailure("close", volumeId, closeRes);
            success = false;
        }
    } else {
        logFatFailure("open(write)", volumeId, fr);
    }
    return success;
}

bool fatCopyFile(int srcVolId, const std::string& srcPath, int destVolId, const std::string& destPath,
                  const CopyProgressCallback& onProgress) {
    ensureFatFsValid(srcVolId);
    ensureFatFsValid(destVolId);
    // Both volumes keep a FIL open across the lock-yield in onProgress.
    FatActiveFileGuard srcGuard(srcVolId);
    FatActiveFileGuard destGuard(destVolId);
    std::string srcFatPath = std::string(drivePaths[srcVolId]) + "/" + srcPath;
    std::string destFatPath = std::string(drivePaths[destVolId]) + "/" + destPath;
    FIL srcF, destF;
    if (f_open(&srcF, srcFatPath.c_str(), FA_READ) != FR_OK) return false;
    if (f_open(&destF, destFatPath.c_str(), FA_WRITE | FA_CREATE_ALWAYS) != FR_OK) {
        f_close(&srcF);
        return false;
    }
    constexpr size_t kBufSize = 2097152;
    std::unique_ptr<unsigned char[]> buf(new unsigned char[kBufSize]);
    UINT br = 0, bw = 0;
    bool ok = true;
    FRESULT readRes = FR_OK;
    while ((readRes = f_read(&srcF, buf.get(), kBufSize, &br)) == FR_OK && br > 0) {
        const FRESULT writeRes = f_write(&destF, buf.get(), br, &bw);
        if (writeRes != FR_OK || bw != br) {
            logFatFailure(writeRes == FR_OK ? "copy write(short)" : "copy write",
                          destVolId, writeRes);
            ok = false;
            break;
        }
        if (onProgress && !onProgress(bw)) {
            ok = false;
            break;
        }
    }
    // A read error ends the loop exactly like EOF does; without this check a
    // source read failure produced a truncated destination reported as OK.
    if (readRes != FR_OK) {
        logFatFailure("copy read", srcVolId, readRes);
        ok = false;
    }
    const FRESULT closeRes = f_close(&destF);
    if (closeRes != FR_OK) {
        logFatFailure("copy close", destVolId, closeRes);
        ok = false;
    }
    f_close(&srcF);
    if (!ok) f_unlink(destFatPath.c_str());
    return ok;
}

bool fatWriteBackFile(int volumeId, const std::string& targetPath, const std::string& sourceHostPath,
                       const CopyProgressCallback& onProgress) {
    constexpr size_t kIoBufferSize = 2097152;
    FatActiveFileGuard activeGuard(volumeId);
    FIL f;
    bool success = false;
    std::string fatPath = std::string(drivePaths[volumeId]) + "/" + targetPath;
    const auto opStart = std::chrono::steady_clock::now();
    int64_t readNanos = 0, writeNanos = 0;
    uint64_t totalBytes = 0;
    int chunkCount = 0;

    int srcFd = openHostSource(sourceHostPath);
    if (srcFd < 0) return false;

    if (f_open(&f, fatPath.c_str(), FA_WRITE | FA_CREATE_ALWAYS) == FR_OK) {
        struct stat st{};
        if (fstat(srcFd, &st) == 0 && st.st_size > 0) {
            auto expStart = std::chrono::steady_clock::now();
            if (f_expand(&f, static_cast<FSIZE_t>(st.st_size), 1) != FR_OK) {
                if (f_lseek(&f, static_cast<FSIZE_t>(st.st_size)) == FR_OK) {
                    f_lseek(&f, 0);
                }
            }
            writeNanos += (std::chrono::steady_clock::now() - expStart).count();
        }

        std::unique_ptr<char[]> buf(new char[kIoBufferSize]);
        UINT bw;
        bool writeError = false;
        bool cancelled = false;

        while (!writeError && !cancelled) {
            auto rStart = std::chrono::steady_clock::now();
            ssize_t n = read(srcFd, buf.get(), kIoBufferSize);
            readNanos += (std::chrono::steady_clock::now() - rStart).count();

            if (n <= 0) break;

            auto wStart = std::chrono::steady_clock::now();
            FRESULT res = f_write(&f, buf.get(), static_cast<UINT>(n), &bw);
            writeNanos += (std::chrono::steady_clock::now() - wStart).count();

            if (res != FR_OK || bw != static_cast<UINT>(n)) {
                logFatFailure(res == FR_OK ? "writeback write(short)" : "writeback write",
                              volumeId, res);
                writeError = true;
            } else {
                totalBytes += bw;
                chunkCount++;
                if (onProgress && !onProgress(bw)) cancelled = true;
            }
        }
        success = !writeError && !cancelled;
        auto closeStart = std::chrono::steady_clock::now();
        const FRESULT closeRes = f_close(&f);
        writeNanos += (std::chrono::steady_clock::now() - closeStart).count();
        if (closeRes != FR_OK) {
            logFatFailure("writeback close", volumeId, closeRes);
            success = false;
        }
        if (!success) f_unlink(fatPath.c_str());
    }
    close(srcFd);

    const auto totalMs = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - opStart).count();
    __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_FatIO",
        "WRITE_BACK target=%s bytes=%llu chunks=%d totalMs=%lld readMs=%lld writeMs=%lld ok=%d",
        targetPath.c_str(), (unsigned long long)totalBytes, chunkCount,
        (long long)totalMs, (long long)(readNanos / 1000000), (long long)(writeNanos / 1000000),
        success ? 1 : 0);
    return success;
}

bool fatExtractFile(int volumeId, const std::string& targetPath, const std::string& destHostPath,
                     const CopyProgressCallback& onProgress) {
    constexpr size_t kIoBufferSize = 2097152;
    FatActiveFileGuard activeGuard(volumeId);
    FIL f;
    bool success = false;
    std::string fatPath = std::string(drivePaths[volumeId]) + "/" + targetPath;

    int destFd = openHostDest(destHostPath);
    if (destFd < 0) return false;

    if (f_open(&f, fatPath.c_str(), FA_READ) == FR_OK) {
        std::unique_ptr<unsigned char[]> buf(new unsigned char[kIoBufferSize]);
        UINT br;
        bool readError = false;
        bool cancelled = false;
        FRESULT readRes = FR_OK;
        while ((readRes = f_read(&f, buf.get(), kIoBufferSize, &br)) == FR_OK && br > 0) {
            ssize_t written = write(destFd, buf.get(), br);
            if (written != static_cast<ssize_t>(br)) {
                readError = true;
                break;
            }
            if (onProgress && !onProgress(static_cast<uint64_t>(written))) {
                cancelled = true;
                break;
            }
        }
        // f_read failing mid-file used to look like EOF -> truncated export
        // reported as a success.
        if (readRes != FR_OK) {
            logFatFailure("extract read", volumeId, readRes);
            readError = true;
        }
        success = !readError && !cancelled;
        f_close(&f);
        if (!success && destHostPath.rfind("/proc/self/fd/", 0) != 0) {
            unlink(destHostPath.c_str());
        }
    }
    close(destFd);
    return success;
}

static FRESULT fatRemoveRecursive(const char* path) {
    DIR dir;
    FILINFO fno;
    FRESULT fr = f_opendir(&dir, path);
    if (fr == FR_OK) {
        while (f_readdir(&dir, &fno) == FR_OK && fno.fname[0]) {
            if (strcmp(fno.fname, ".") == 0 || strcmp(fno.fname, "..") == 0) continue;
            std::string childPath = std::string(path) + "/" + fno.fname;
            if (fno.fattrib & AM_DIR) {
                fatRemoveRecursive(childPath.c_str());
            } else {
                f_unlink(childPath.c_str());
            }
        }
        f_closedir(&dir);
    }
    return f_unlink(path);
}

bool fatDeleteFile(int volumeId, const std::string& path) {
    ensureFatFsValid(volumeId);
    std::string fatPath = std::string(drivePaths[volumeId]) + "/" + path;
    FRESULT fr = f_unlink(fatPath.c_str());
    if (fr == FR_DENIED) {
        fr = fatRemoveRecursive(fatPath.c_str());
    }
    noteFatError(volumeId, fr);
    return fr == FR_OK;
}

bool fatCreateDirectory(int volumeId, const std::string& path) {
    ensureFatFsValid(volumeId);
    std::string fullPath = std::string(drivePaths[volumeId]) + "/" + path;
    const FRESULT fr = f_mkdir(fullPath.c_str());
    noteFatError(volumeId, fr);
    return fr == FR_OK;
}

bool fatRenameFile(int volumeId, const std::string& oldPath, const std::string& newPath) {
    std::string fullOld = std::string(drivePaths[volumeId]) + "/" + oldPath;
    std::string fullNew = std::string(drivePaths[volumeId]) + "/" + newPath;
    ensureFatFsValid(volumeId);
    const FRESULT fr = f_rename(fullOld.c_str(), fullNew.c_str());
    noteFatError(volumeId, fr);
    return fr == FR_OK;
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
    ensureFatFsValid(volumeId);
    FATFS* fs;
    DWORD fre_clust;
    FRESULT fr = f_getfree(drivePaths[volumeId], &fre_clust, &fs);
    if (fr != FR_OK) {
        logFatFailure("getfree", volumeId, fr);
        // If that flagged the volume, rebuild it (when idle) and ask once more.
        recoverFatIfNeeded(volumeId);
        fr = f_getfree(drivePaths[volumeId], &fre_clust, &fs);
    }
    if (fr == FR_OK) {
        const uint64_t ss = (fs->ssize > 0) ? fs->ssize : 512ULL;
        outTotalBytes = static_cast<uint64_t>(fs->n_fatent - 2) * fs->csize * ss;
        outFreeBytes  = static_cast<uint64_t>(fre_clust) * fs->csize * ss;
    }
}

std::string fatGetFilesystemLabel(int volumeId) {
    switch (volumes[volumeId].fatfs.fs_type) {
        case FS_FAT12: return "FAT12";
        case FS_FAT16: return "FAT16";
        case FS_FAT32: return "FAT32";
        case FS_EXFAT: return "exFAT";
        default:       return std::string();
    }
}

void* fatOpenStream(int volumeId, const std::string& path) {
    ensureFatFsValid(volumeId);
    auto& v = volumes[volumeId];
    FIL* f = new FIL();
    std::string fatPath = std::string(drivePaths[volumeId]) + "/" + path;
    FRESULT fr = f_open(f, fatPath.c_str(), FA_READ);
    if (fatRemountForRetry(volumeId, fr)) {
        fr = f_open(f, fatPath.c_str(), FA_READ);
    }
    if (fr == FR_OK) {
        v.openStreams.push_back(f);
        return f;
    }
    noteFatError(volumeId, fr);
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