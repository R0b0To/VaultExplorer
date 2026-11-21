// Platform-neutral "mounted vault" filesystem (desktop).
//
// MountFs is what the OS-facing glue (libfuse3 on Linux in ve_mount_fuse.cpp, WinFsp on Windows later)
// talks to. It is the desktop twin of Android's ContainerDocumentsProvider + ContainerProxyCallback: a
// file-level view of one volume slot, expressed through the public C ABI (ve_*), so it works unchanged for
// every format behind a slot -- block containers (FAT/exFAT/NTFS/ext) and folder vaults (gocryptfs,
// Cryptomator, CryFS).
//
// Conventions
//   * Every method returns 0 / a byte count on success and -errno on failure (POSIX errno values; the
//     Windows glue translates them to NTSTATUS), so the glue stays a thin translation layer.
//   * Paths are mount-relative, UTF-8, '/'-separated, with a leading '/' ("/" = the mount root).
//   * Thread-safe: one coarse mutex. The engine serialises per volume anyway, so finer locking would only
//     add risk.
//   * Plaintext never touches host storage. Write buffering is memory only and is wiped when released.
//
// Write model (why it is not a plain pass-through)
//   Block containers do real random-access writes through ve_write_file_at / ve_truncate; consecutive
//   writes are coalesced (as Android's proxy callback does) so every 128 KiB FUSE write does not become a
//   directory-entry commit on the container.
//   Folder vaults only accept chunks in order from offset 0 followed by ve_fv_finish_write, and the file
//   appears only at that point. A handle therefore runs in one of two modes:
//     Stream   -- a new or truncated file written front to back. Chunks go straight to the vault.
//     Buffered -- anything else (modify in place, writes after commit): the whole file is held in memory
//                 (up to FsOptions::maxBufferBytes) and rewritten on flush.
//   A backwards seek inside an already-sent Stream is the one pattern that cannot be honoured; it fails
//   with EIO rather than corrupting the file.
#pragma once

#include <chrono>
#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace vemount {

enum class NodeType : uint8_t { File, Dir, Symlink };

struct Attr {
    NodeType type = NodeType::File;
    uint64_t size = 0;   // bytes (symlink: target length)
    int64_t mtime = 0;   // unix seconds
};

struct DirItem {
    std::string name;
    Attr attr;
};

struct StatFsInfo {
    uint64_t blockSize = 4096;
    uint64_t blocks = 0;
    uint64_t blocksFree = 0;
    uint32_t nameMax = 255;
};

struct FsOptions {
    bool readOnly = false;
    std::string root;                          // vault folder to expose: "" / "/" = whole vault, else "/a/b"
    uint64_t maxBufferBytes = 256ull << 20;    // per handle, Buffered mode only
};

// Flags mirror POSIX so the glue can pass them straight through.
constexpr int kOpenRead = 0x1;
constexpr int kOpenWrite = 0x2;
constexpr int kOpenTrunc = 0x4;
constexpr int kOpenExcl = 0x8;

class MountFs {
public:
    MountFs(int32_t vol, FsOptions options);
    ~MountFs();
    MountFs(const MountFs&) = delete;
    MountFs& operator=(const MountFs&) = delete;

    // ---- metadata --------------------------------------------------------------------------------
    int getattr(const std::string& path, Attr& out);
    int readdir(const std::string& path, std::vector<DirItem>& out);
    int statfs(StatFsInfo& out);
    int readlink(const std::string& path, std::string& target);

    // ---- namespace -------------------------------------------------------------------------------
    int mkdir(const std::string& path);
    int rmdir(const std::string& path);
    int unlink(const std::string& path);
    // flags: bit0 = RENAME_NOREPLACE. RENAME_EXCHANGE is rejected with EINVAL.
    int rename(const std::string& from, const std::string& to, unsigned flags);
    int symlink(const std::string& target, const std::string& linkPath);
    int setMtime(const std::string& path, int64_t epochSeconds);

    // ---- file I/O --------------------------------------------------------------------------------
    // open/create return 0 and set `fh` (never 0).
    int open(const std::string& path, int flags, uint64_t& fh);
    int create(const std::string& path, int flags, uint64_t& fh);
    int read(uint64_t fh, uint8_t* buf, size_t size, uint64_t offset);   // bytes read, 0 at EOF
    int write(uint64_t fh, const uint8_t* buf, size_t size, uint64_t offset);  // bytes written
    int truncate(const std::string& path, uint64_t size);
    int ftruncate(uint64_t fh, uint64_t size);
    int flush(uint64_t fh);     // commits pending data; returns a deferred write error, if any
    int release(uint64_t fh);

    // Commits every pending write and forgets all handles. Called before a vault is locked / unmounted.
    void closeAll();

    // Number of open file handles (used to decide whether an unmount is "busy").
    size_t openHandleCount();

private:
    struct Handle;
    struct DirCache {
        std::chrono::steady_clock::time_point stamp;
        std::unordered_map<std::string, Attr> entries;
        std::unordered_map<std::string, std::string> folded;  // lower-cased name -> real name (case-insensitive FS only)
    };

    // All *Locked helpers assume mu_ is held.
    std::string enginePath(const std::string& mountPath) const;
    static std::string parentOf(const std::string& path);
    static std::string leafOf(const std::string& path);
    static bool isRoot(const std::string& path) { return path.empty() || path == "/"; }

    int loadDirLocked(const std::string& dir, bool force, DirCache** out);
    int lookupLocked(const std::string& path, Attr& out);          // engine view + cache, ignores open handles
    int statLocked(const std::string& path, Attr& out);            // lookup + pending (uncommitted) handles
    void cachePutLocked(const std::string& path, const Attr& attr);
    void cacheEraseLocked(const std::string& path);
    void cacheDropTreeLocked(const std::string& path);
    int nonEmptyDirLocked(const std::string& path);                // 0 = empty, -ENOTEMPTY, or -errno

    Handle* handleLocked(uint64_t fh);
    int openLocked(const std::string& path, int flags, bool created, uint64_t& fh);
    int flushHandleLocked(Handle& h);
    int flushPathLocked(const std::string& path, bool includeSubtree, bool directOnly = false);
    int writeDirectLocked(Handle& h, const uint8_t* buf, size_t size, uint64_t offset);
    int writeStreamLocked(Handle& h, const uint8_t* buf, size_t size, uint64_t offset);
    int writeBufferedLocked(Handle& h, const uint8_t* buf, size_t size, uint64_t offset);
    int loadBufferedLocked(Handle& h);
    int sendStreamChunkLocked(Handle& h, const uint8_t* data, size_t len);
    int finishStreamLocked(Handle& h);
    int commitBufferedLocked(Handle& h);
    int prepareReplaceLocked(const std::string& path);
    int truncateLocked(const std::string& path, uint64_t size);
    int ftruncateLocked(Handle& h, uint64_t size);
    int engineErr(int32_t rc, int fallbackErrno) const;
    int writeFailureErrno(size_t len);
    void orphanHandlesLocked(const std::string& path, bool subtree);
    void retargetHandlesLocked(const std::string& from, const std::string& to);

    const int32_t vol_;
    FsOptions opt_;
    bool folderVault_ = false;
    bool cryfs_ = false;  // CryFS overlays writes on the old content instead of replacing it
    bool caseInsensitive_ = false;

    std::mutex mu_;
    std::map<std::string, DirCache> dirs_;
    std::unordered_map<uint64_t, std::unique_ptr<Handle>> handles_;
    uint64_t nextFh_ = 1;
};

}  // namespace vemount
