// Chunked file engine shared by gocryptfs and Cryptomator: random-access
// reads (with a small per-file chunk cache and an LRU of open handles),
// incremental FUSE-style writes, and bulk import / export. A port of the
// Kotlin ChunkedFileEngine, with the SAF specifics moved behind fv::Storage.
#pragma once

#include <atomic>
#include <condition_variable>
#include <functional>
#include <list>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <unordered_map>
#include <unordered_set>

#include "fv_vault.h"

namespace fv {

// Per-file decoded header state (nonce / content key / file id ...).
struct FileKey {
    virtual ~FileKey() = default;
};

// The on-disk file layout of one format: <header><chunk><chunk>...
class FileFormat {
public:
    virtual ~FileFormat() = default;
    virtual size_t headerSize() const = 0;
    virtual size_t cleartextChunk() const = 0;
    virtual size_t ciphertextChunk() const = 0;
    size_t overhead() const { return ciphertextChunk() - cleartextChunk(); }

    virtual std::shared_ptr<FileKey> newHeader(Bytes& encodedHeader) const = 0;
    // Throws Error(Auth) when the header does not verify.
    virtual std::shared_ptr<FileKey> decodeHeader(const uint8_t* p, size_t n) const = 0;

    // [n] plaintext bytes starting at chunk [firstChunk]; every chunk is full
    // except possibly the last. [out] needs encryptedSize(n) bytes.
    virtual void encrypt(const FileKey& k, uint64_t firstChunk, const uint8_t* in, size_t n, uint8_t* out) const = 0;
    // Inverse of encrypt; throws Error(Auth) on any authentication failure.
    virtual void decrypt(const FileKey& k, uint64_t firstChunk, const uint8_t* in, size_t n, uint8_t* out) const = 0;

    // Cleartext size of a file whose physical size (header included) is [physicalSize].
    virtual int64_t cleartextSize(int64_t physicalSize) const = 0;

    size_t encryptedSize(size_t plainBytes) const {
        size_t cs = cleartextChunk();
        return plainBytes + ((plainBytes + cs - 1) / cs) * overhead();
    }
    // Throws Error(Auth) if a trailing partial chunk is shorter than the overhead.
    size_t decryptedSize(size_t cipherBytes) const;
};

// What the engine needs from the session that owns it.
class EngineHost {
public:
    virtual ~EngineHost() = default;
    // Physical storage path of an existing file, or false.
    virtual bool resolveForRead(const std::string& vpath, std::string& physical) = 0;
    // Finds or creates the physical file for [vpath], marks it write-pending
    // and returns its storage path.
    virtual std::string prepareForWrite(const std::string& vpath) = 0;
    // A write finished outside a batch: publish it and refresh listings.
    virtual void afterWrite(const std::string& vpath, const std::string& physical) = 0;
    // A write failed or was aborted midway: remove the half-written file (and
    // anything created next to it) and drop cached knowledge of it.
    virtual void abortedWrite(const std::string& vpath, const std::string& physical) = 0;
};

// Per-path mutual exclusion with automatic cleanup of idle entries.
class PathLocks {
public:
    class Guard {
    public:
        Guard(PathLocks& l, const std::string& path);
        ~Guard();
        Guard(const Guard&) = delete;
        Guard& operator=(const Guard&) = delete;
    private:
        PathLocks& l_;
        std::string path_;
        std::shared_ptr<std::mutex> m_;
    };
private:
    struct Entry { std::shared_ptr<std::mutex> m; int refs = 0; };
    std::mutex mu_;
    std::unordered_map<std::string, Entry> map_;
};

class ChunkedFileEngine {
public:
    ChunkedFileEngine(Storage& st, const FileFormat& fmt, EngineHost& host,
                      bool readOnly, const std::atomic<bool>& batchWriteActive);
    ~ChunkedFileEngine();

    std::optional<Bytes> readFileChunk(const std::string& vpath, int64_t offset, int length);
    bool writeFileChunk(const std::string& vpath, int64_t offset, const uint8_t* data, size_t len);
    bool finishWrite(const std::string& vpath);
    bool writeBackFile(const std::string& vpath, const std::string& sourceFile, Progress* p);
    bool writeBackStream(const std::string& vpath, ByteSource& src, Progress* p);
    bool extractFile(const std::string& vpath, const std::string& destFile, Progress* p);

    void invalidateRead(const std::string& vpath);
    void invalidateAll();
    // Aborts open writes and drops every handle; the engine is unusable afterwards.
    void close();

private:
    struct ReadHandle {
        FdFile file;
        std::shared_ptr<FileKey> key;
        static constexpr int kCache = 4;
        int64_t idx[kCache] = {-1, -1, -1, -1};
        Bytes chunk[kCache];
        int ptr = 0;
        const Bytes* cached(int64_t i) const { for (int k = 0; k < kCache; k++) if (idx[k] == i) return &chunk[k]; return nullptr; }
        void put(int64_t i, Bytes b) { idx[ptr] = i; chunk[ptr] = std::move(b); ptr = (ptr + 1) % kCache; }
    };
    struct WriteHandle {
        FdFile file;
        std::string physical;
        std::shared_ptr<FileKey> key;
        Bytes pending;
        int64_t written = 0;
        uint64_t nextChunk = 0;
        bool committed = false;
    };

    std::shared_ptr<ReadHandle> findHandle(const std::string& path);
    void putHandle(const std::string& path, std::shared_ptr<ReadHandle> h);
    void dropHandle(const std::string& path);
    std::shared_ptr<ReadHandle> openHandle(const std::string& path);
    std::optional<Bytes> readRange(const std::string& path, int64_t offset, int length, bool retried);
    bool writeFrom(const std::string& vpath, ByteSource& src, Progress* p, bool doSync);
    void abortWrite(WriteHandle& h);
    void flushPending(WriteHandle& h, bool final);
    void markWriting(const std::string& path);
    void unmarkWriting(const std::string& path);
    void waitNotWriting(const std::string& path);

    Storage& st_;
    const FileFormat& fmt_;
    EngineHost& host_;
    const bool readOnly_;
    const std::atomic<bool>& batch_;
    std::atomic<bool> closed_{false};

    PathLocks locks_;

    std::mutex rmu_;
    static constexpr size_t kMaxHandles = 32;
    std::list<std::string> lru_;
    struct HandleSlot { std::shared_ptr<ReadHandle> h; std::list<std::string>::iterator it; };
    std::unordered_map<std::string, HandleSlot> handles_;

    std::mutex wmu_;
    std::condition_variable wcv_;
    std::unordered_map<std::string, std::shared_ptr<WriteHandle>> openWrites_;
    std::unordered_set<std::string> writing_;
};

}  // namespace fv
