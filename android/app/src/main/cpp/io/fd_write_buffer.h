#pragma once

#include <cstdint>
#include <cstddef>
#include <cstring>
#include <vector>
#include <algorithm>
#include <mutex>
#include <unistd.h>
#include <cerrno>

// Two-Stream Write-Combining Cache for File Descriptor (fd)-backed Volumes:
// - Coalesces sequential sector writes into uninterrupted 1 MB bursts before issuing pwrite64.
// - Buffers FAT table / directory metadata updates in a separate 64 KB stream so they
//   never prematurely break the sequential data burst.
// - Provides coherency by flushing overlapping ranges before reading from fd or syncing.
class FdWriteBuffer {
public:
    static constexpr size_t DATA_BURST_BYTES        = 1024 * 1024; // 1 MB data burst
    static constexpr size_t META_BURST_BYTES        = 64 * 1024;   // 64 KB metadata burst
    static constexpr size_t SMALL_WRITE_THRESHOLD   = 2 * 1024;    // <= 2 KB writes (FAT/dir/FSInfo/MFT) route to metaStream

    FdWriteBuffer()
        : dataStream_(DATA_BURST_BYTES),
          metaStream_(META_BURST_BYTES) {}

    ~FdWriteBuffer() = default;
    FdWriteBuffer(const FdWriteBuffer&) = delete;
    FdWriteBuffer& operator=(const FdWriteBuffer&) = delete;

    bool write(int fd, uint64_t byteOffset, const unsigned char* inBuf, size_t byteCount) {
        if (byteCount == 0) return true;
        if (fd < 0 || !inBuf) return false;
        std::lock_guard<std::mutex> lock(mutex_);

        // 1. Large writes (>= 1 MB) bypass both buffers and stream straight to fd
        if (byteCount >= DATA_BURST_BYTES) {
            if (!flushStreamLocked(fd, dataStream_)) return false;
            if (!flushStreamLocked(fd, metaStream_)) return false;
            return directWrite(fd, byteOffset, inBuf, byteCount);
        }

        // 2. Overwrites within current data stream: update in place
        if (dataStream_.contains(byteOffset, byteCount)) {
            dataStream_.updateInPlace(byteOffset, byteCount, inBuf);
            return true;
        }

        // 3. Extends current data stream: append without flushing
        if (dataStream_.canAppend(byteOffset, byteCount)) {
            if (metaStream_.overlaps(byteOffset, byteCount)) {
                if (!flushStreamLocked(fd, metaStream_)) return false;
            }
            dataStream_.append(byteOffset, byteCount, inBuf);
            if (dataStream_.size == dataStream_.maxBytes) {
                return flushStreamLocked(fd, dataStream_);
            }
            return true;
        }

        // 4. Small metadata write (<= 2 KB): route to metaStream_
        // so it never breaks the contiguous dataStream_
        if (byteCount <= SMALL_WRITE_THRESHOLD) {
            if (dataStream_.overlaps(byteOffset, byteCount)) {
                if (!flushStreamLocked(fd, dataStream_)) return false;
            }
            if (metaStream_.contains(byteOffset, byteCount)) {
                metaStream_.updateInPlace(byteOffset, byteCount, inBuf);
                return true;
            }
            if (metaStream_.canAppend(byteOffset, byteCount)) {
                metaStream_.append(byteOffset, byteCount, inBuf);
                if (metaStream_.size == metaStream_.maxBytes) {
                    return flushStreamLocked(fd, metaStream_);
                }
                return true;
            }
            if (!flushStreamLocked(fd, metaStream_)) return false;
            metaStream_.append(byteOffset, byteCount, inBuf);
            return true;
        }

        // 5. Non-contiguous data write: flush previous data stream and start a new one
        if (metaStream_.overlaps(byteOffset, byteCount)) {
            if (!flushStreamLocked(fd, metaStream_)) return false;
        }
        if (!flushStreamLocked(fd, dataStream_)) return false;
        dataStream_.append(byteOffset, byteCount, inBuf);
        return true;
    }

    bool flushIfOverlaps(int fd, uint64_t byteOffset, size_t byteCount) {
        if (byteCount == 0 || fd < 0) return true;
        std::lock_guard<std::mutex> lock(mutex_);
        if (dataStream_.overlaps(byteOffset, byteCount)) {
            if (!flushStreamLocked(fd, dataStream_)) return false;
        }
        if (metaStream_.overlaps(byteOffset, byteCount)) {
            if (!flushStreamLocked(fd, metaStream_)) return false;
        }
        return true;
    }

    bool flush(int fd) {
        if (fd < 0) return true;
        std::lock_guard<std::mutex> lock(mutex_);
        bool ok1 = flushStreamLocked(fd, dataStream_);
        bool ok2 = flushStreamLocked(fd, metaStream_);
        return ok1 && ok2;
    }

    void reset() {
        std::lock_guard<std::mutex> lock(mutex_);
        dataStream_.reset();
        metaStream_.reset();
    }

    static bool directWrite(int fd, uint64_t byteOffset, const unsigned char* buffer, size_t byteCount) {
        if (fd < 0 || (!buffer && byteCount > 0)) return false;
        size_t totalWritten = 0;
        while (totalWritten < byteCount) {
            const ssize_t written = pwrite64(fd, buffer + totalWritten,
                                            byteCount - totalWritten,
                                            static_cast<off64_t>(byteOffset + totalWritten));
            if (written > 0) {
                totalWritten += static_cast<size_t>(written);
            } else if (written < 0 && (errno == EINTR || errno == EAGAIN)) {
                continue;
            } else {
                return false;
            }
        }
        return true;
    }

private:
    struct StreamBuffer {
        uint64_t startOffset = 0;
        size_t size = 0;
        size_t maxBytes = 0;
        std::vector<uint8_t> data;
        bool active = false;

        explicit StreamBuffer(size_t maxB) : maxBytes(maxB) {}

        void reset() {
            active = false;
            size = 0;
            startOffset = 0;
        }

        bool canAppend(uint64_t off, size_t len) const {
            return active && (off == startOffset + size) && (size + len <= maxBytes);
        }

        bool contains(uint64_t off, size_t len) const {
            return active && (off >= startOffset) && (off + len <= startOffset + size);
        }

        bool overlaps(uint64_t off, size_t len) const {
            return active && (off < startOffset + size) && (off + len > startOffset);
        }

        void append(uint64_t off, size_t len, const unsigned char* src) {
            if (data.size() < maxBytes) {
                data.resize(maxBytes);
            }
            if (!active) {
                startOffset = off;
                size = len;
                std::memcpy(data.data(), src, len);
                active = true;
            } else {
                std::memcpy(data.data() + size, src, len);
                size += len;
            }
        }

        void updateInPlace(uint64_t off, size_t len, const unsigned char* src) {
            size_t rel = static_cast<size_t>(off - startOffset);
            std::memcpy(data.data() + rel, src, len);
        }
    };

    std::mutex mutex_;
    StreamBuffer dataStream_;
    StreamBuffer metaStream_;

    bool flushStreamLocked(int fd, StreamBuffer& s) {
        if (!s.active || s.size == 0) {
            s.reset();
            return true;
        }
        uint64_t off = s.startOffset;
        size_t len = s.size;
        const unsigned char* ptr = s.data.data();
        s.reset();
        return directWrite(fd, off, ptr, len);
    }
};
