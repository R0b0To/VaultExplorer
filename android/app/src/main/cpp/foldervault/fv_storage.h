// Where a vault's *physical* (encrypted) files live.
//
// The format engines never touch the filesystem directly; they talk to a
// Storage. Paths are relative to the vault root, '/'-separated, without a
// leading or trailing slash ("" is the root itself).
//
//  * PosixStorage   -- a plain directory tree. Used on desktop and on
//                      Android whenever the vault folder is reachable
//                      through a raw path (the fast case).
//  * (Android only) JniStorage in jni/foldervault_bridge.cpp forwards every
//    call to Kotlin, which runs it against SAF documents / the local mirror
//    (MirrorSyncCoordinator). That keeps all Storage-Access-Framework policy
//    on the Kotlin side while the format logic stays here.
//
// All methods must be thread-safe; engines call them concurrently.
#pragma once

#include <memory>
#include <string>
#include <vector>

#include "fv_common.h"

namespace fv {

// Owning wrapper around a POSIX file descriptor with the few operations the
// engines need. Handles descriptors that are not seekable (some
// ContentProviders hand out pipes): reads then become forward-only.
class FdFile {
public:
    FdFile() = default;
    explicit FdFile(int fd);
    ~FdFile();
    FdFile(const FdFile&) = delete;
    FdFile& operator=(const FdFile&) = delete;
    FdFile(FdFile&& o) noexcept;
    FdFile& operator=(FdFile&& o) noexcept;

    bool valid() const { return fd_ >= 0; }
    int fd() const { return fd_; }
    bool seekable() const { return seekable_; }
    int64_t size() const;                       // -1 when unknown
    void close();

    // Reads up to n bytes at absolute offset [off]; loops until n bytes or EOF.
    // Returns the byte count, or kNeedsReopen if the fd is not seekable and
    // [off] lies behind the current position, or -1 on I/O error.
    static constexpr int64_t kNeedsReopen = -2;
    int64_t readAt(uint8_t* buf, size_t n, int64_t off);

    // Sequential write of the whole buffer at the current position.
    bool writeAll(const uint8_t* buf, size_t n);
    bool sync();

private:
    int fd_ = -1;
    bool seekable_ = true;
    int64_t pos_ = 0;   // only maintained for non-seekable descriptors
};

class Storage {
public:
    virtual ~Storage() = default;

    // ---- namespace --------------------------------------------------------
    // Lists the children of [dir]. false if [dir] does not exist.
    virtual bool list(const std::string& dir, std::vector<DirEntry>& out) = 0;
    // Stat of a single node (out.name = its base name). false if missing.
    virtual bool stat(const std::string& path, DirEntry& out) = 0;
    // Creates one directory level. true if it exists afterwards.
    virtual bool mkdir(const std::string& path) = 0;
    // Creates an empty file if absent. true if a file exists afterwards.
    virtual bool createFile(const std::string& path) = 0;
    // Renames/moves a file or directory (parents may differ). Replaces an
    // existing destination file.
    virtual bool rename(const std::string& from, const std::string& to) = 0;
    // Deletes a file or a whole directory tree. true if nothing is left.
    virtual bool remove(const std::string& path) = 0;
    virtual bool setMtime(const std::string& path, int64_t epochSec) = 0;

    // ---- content ----------------------------------------------------------
    virtual bool readWhole(const std::string& path, Bytes& out) = 0;
    // Create-or-replace with [data] and make the content durable/published.
    virtual bool writeWhole(const std::string& path, const uint8_t* data, size_t len) = 0;
    // Bulk-data variant of writeWhole for CryFS blocks: same contract but the
    // backend may skip fsync (a torn block is detected by its authentication
    // tag, and brand-new blocks are unreferenced until the tree is published).
    virtual bool writeBlock(const std::string& path, const uint8_t* data, size_t len) {
        return writeWhole(path, data, len);
    }
    // Same, but never leaves a torn file behind (write temp + rename where
    // the backend can). Used for the vault's config files.
    virtual bool writeWholeAtomic(const std::string& path, const uint8_t* data, size_t len) {
        return writeWhole(path, data, len);
    }
    // Makes sure the content (and therefore the size) of [path] is locally
    // available -- the lazy pull of mirrored storage. No-op for local files.
    virtual void ensureContentReady(const std::string& /*path*/) {}
    // Opens for reading. The returned descriptor is owned by the caller.
    // For mirrored storage this is where a lazy pull happens; [hint] is the
    // cleartext path being read so the host can label that pull in its UI.
    virtual FdFile openRead(const std::string& path, const std::string& hint) = 0;
    // Opens an existing file for writing (truncating when asked). The caller
    // owns the descriptor. Call markWritePending first and publishWrite after.
    virtual FdFile openWrite(const std::string& path, bool truncate) = 0;
    virtual void markWritePending(const std::string& /*path*/) {}
    // Pushes written content to wherever the real copy lives. [defer] holds
    // the push back (write-tmp-then-rename scratch files).
    virtual bool publishWrite(const std::string& /*path*/, bool /*defer*/) { return true; }

    // ---- caches / misc ----------------------------------------------------
    virtual void invalidate(const std::string& /*dir*/) {}
    virtual void invalidateAll() {}
    virtual bool spaceInfo(int64_t& /*total*/, int64_t& /*free*/) { return false; }
    // Releases whatever the storage holds (mirror directory, ...).
    virtual void close() {}
};

// Plain directory on a local filesystem. Rejects any path with a "." / ".."
// segment so a hostile cleartext name can never escape the vault root.
class PosixStorage : public Storage {
public:
    explicit PosixStorage(std::string rootDir);
    const std::string& root() const { return root_; }

    bool list(const std::string& dir, std::vector<DirEntry>& out) override;
    bool stat(const std::string& path, DirEntry& out) override;
    bool mkdir(const std::string& path) override;
    bool createFile(const std::string& path) override;
    bool rename(const std::string& from, const std::string& to) override;
    bool remove(const std::string& path) override;
    bool setMtime(const std::string& path, int64_t epochSec) override;
    bool readWhole(const std::string& path, Bytes& out) override;
    bool writeWhole(const std::string& path, const uint8_t* data, size_t len) override;
    bool writeBlock(const std::string& path, const uint8_t* data, size_t len) override;
    bool writeWholeAtomic(const std::string& path, const uint8_t* data, size_t len) override;
    FdFile openRead(const std::string& path, const std::string& hint) override;
    FdFile openWrite(const std::string& path, bool truncate) override;
    bool spaceInfo(int64_t& total, int64_t& free) override;

private:
    bool abs(const std::string& rel, std::string& out) const;
    std::string root_;
};

}  // namespace fv
