#pragma once
#include <cstdint>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <algorithm>
#include <mutex>
#include "jni_callbacks.h"

// Two-Stream Write-Combining Cache for USB Mass Storage:
// - Coalesces data clusters into uninterrupted 128 KB bursts.
// - Buffers FAT table/directory metadata updates separately so they never break the data burst.
// - Provides 64 KB read-ahead for fast folder browsing and smooth video playback.
class UsbBlockCache {
public:
    static constexpr size_t SECTOR_SIZE         = 512;
    static constexpr size_t DATA_BURST_SECTORS  = 256;  // 128 KB burst
    static constexpr size_t META_BURST_SECTORS  = 64;   // 32 KB burst

    static constexpr size_t READ_CHUNK_BYTES    = 64 * 1024; // 64 KB read-ahead
    static constexpr size_t READ_CHUNK_COUNT    = 64;        // 4 MB read cache
    static constexpr uint64_t CHUNK_EMPTY       = UINT64_MAX;

    UsbBlockCache() {
        dataStream_.init(DATA_BURST_SECTORS);
        metaStream_.init(META_BURST_SECTORS);
        readChunks_.resize(READ_CHUNK_COUNT);
        for (auto& c : readChunks_) {
            c.off = CHUNK_EMPTY;
            c.data.resize(READ_CHUNK_BYTES);
        }
    }

    ~UsbBlockCache() = default;

    bool read(int volId, uint64_t byteOffset, unsigned char* outBuf, size_t byteCount) {
        if (byteCount == 0) return true;
        std::lock_guard<std::mutex> lock(mutex_);

        uint64_t sector = byteOffset / SECTOR_SIZE;
        uint32_t count = static_cast<uint32_t>((byteCount + SECTOR_SIZE - 1) / SECTOR_SIZE);

        if (dataStream_.overlaps(sector, count)) {
            if (!flushStreamLocked(volId, dataStream_)) return false;
        }
        if (metaStream_.overlaps(sector, count)) {
            if (!flushStreamLocked(volId, metaStream_)) return false;
        }

        // Streaming reads (>= 64 KB) bypass cache directly
        if (byteCount >= READ_CHUNK_BYTES) {
            return directRead(volId, byteOffset, outBuf, byteCount);
        }

        size_t done = 0;
        while (done < byteCount) {
            uint64_t cur = byteOffset + done;
            uint64_t aligned = cur - (cur % READ_CHUNK_BYTES);
            size_t inChunk = static_cast<size_t>(cur - aligned);
            size_t avail = READ_CHUNK_BYTES - inChunk;
            size_t toCopy = std::min(byteCount - done, avail);

            ReadChunk* c = findReadChunkLocked(aligned);
            if (!c) {
                c = fillReadChunkLocked(volId, aligned);
            }

            if (!c) {
                size_t rem = byteCount - done;
                if (!directRead(volId, cur, outBuf + done, rem)) return false;
                break;
            }

            std::memcpy(outBuf + done, c->data.data() + inChunk, toCopy);
            c->stamp = ++clock_;
            done += toCopy;
        }
        return true;
    }

    bool write(int volId, uint64_t byteOffset, const unsigned char* inBuf, size_t byteCount) {
        if (byteCount == 0) return true;
        std::lock_guard<std::mutex> lock(mutex_);

        uint64_t sector = byteOffset / SECTOR_SIZE;
        uint32_t count = static_cast<uint32_t>(byteCount / SECTOR_SIZE);

        invalidateReadCacheLocked(byteOffset, byteCount);

        // 1. Large writes (>= 128 KB) bypass both buffers and stream straight to device
        if (count >= dataStream_.maxSectors) {
            if (!flushStreamLocked(volId, dataStream_)) return false;
            if (!flushStreamLocked(volId, metaStream_)) return false;
            return directWrite(volId, byteOffset, inBuf, byteCount);
        }

        // 2. Extends current data stream: append without flushing
        if (dataStream_.canAppend(sector, count)) {
            dataStream_.append(sector, count, inBuf);
            if (dataStream_.count == dataStream_.maxSectors) {
                return flushStreamLocked(volId, dataStream_);
            }
            return true;
        }

        // 3. Small metadata write (<= 8 sectors / 4 KB): route to metaStream_
        // so it never breaks the contiguous dataStream_
        if (count <= 8) {
            if (metaStream_.contains(sector, count)) {
                metaStream_.updateInPlace(sector, count, inBuf);
                return true;
            }
            if (metaStream_.canAppend(sector, count)) {
                metaStream_.append(sector, count, inBuf);
                if (metaStream_.count == metaStream_.maxSectors) {
                    return flushStreamLocked(volId, metaStream_);
                }
                return true;
            }
            if (!flushStreamLocked(volId, metaStream_)) return false;
            metaStream_.append(sector, count, inBuf);
            return true;
        }

        // 4. Non-contiguous data cluster: flush previous data stream and start a new one
        if (!flushStreamLocked(volId, dataStream_)) return false;
        dataStream_.append(sector, count, inBuf);
        return true;
    }

    bool flush(int volId) {
        std::lock_guard<std::mutex> lock(mutex_);
        bool ok1 = flushStreamLocked(volId, dataStream_);
        bool ok2 = flushStreamLocked(volId, metaStream_);
        return ok1 && ok2;
    }

    bool sync(int volId) {
        if (!flush(volId)) return false;
        return usbSyncDevice(volId);
    }

    void clear() {
        std::lock_guard<std::mutex> lock(mutex_);
        dataStream_.reset();
        metaStream_.reset();
        for (auto& c : readChunks_) {
            c.off = CHUNK_EMPTY;
        }
    }

private:
    struct StreamBuffer {
        uint64_t startSector = 0;
        uint32_t count = 0;
        uint32_t maxSectors = 0;
        std::vector<uint8_t> data;
        bool active = false;

        void init(size_t maxSecs) {
            maxSectors = static_cast<uint32_t>(maxSecs);
            data.resize(maxSecs * SECTOR_SIZE);
            reset();
        }

        void reset() {
            active = false;
            count = 0;
            startSector = 0;
        }

        bool canAppend(uint64_t sec, uint32_t cnt) const {
            return active && (sec == startSector + count) && (count + cnt <= maxSectors);
        }

        bool contains(uint64_t sec, uint32_t cnt) const {
            return active && (sec >= startSector) && (sec + cnt <= startSector + count);
        }

        bool overlaps(uint64_t sec, uint32_t cnt) const {
            return active && (sec < startSector + count) && (sec + cnt > startSector);
        }

        void append(uint64_t sec, uint32_t cnt, const unsigned char* src) {
            if (!active) {
                startSector = sec;
                count = cnt;
                std::memcpy(data.data(), src, cnt * SECTOR_SIZE);
                active = true;
            } else {
                std::memcpy(data.data() + (count * SECTOR_SIZE), src, cnt * SECTOR_SIZE);
                count += cnt;
            }
        }

        void updateInPlace(uint64_t sec, uint32_t cnt, const unsigned char* src) {
            size_t offset = static_cast<size_t>(sec - startSector) * SECTOR_SIZE;
            std::memcpy(data.data() + offset, src, cnt * SECTOR_SIZE);
        }
    };

    struct ReadChunk {
        uint64_t off = CHUNK_EMPTY;
        uint64_t stamp = 0;
        std::vector<uint8_t> data;
    };

    std::mutex mutex_;
    StreamBuffer dataStream_;
    StreamBuffer metaStream_;
    std::vector<ReadChunk> readChunks_;
    uint64_t clock_ = 0;

    bool flushStreamLocked(int volId, StreamBuffer& s) {
        if (!s.active || s.count == 0) {
            s.reset();
            return true;
        }
        uint32_t count = s.count;
        uint64_t sector = s.startSector;
        s.reset();
        return directWrite(volId, sector * SECTOR_SIZE, s.data.data(), count * SECTOR_SIZE);
    }

    ReadChunk* findReadChunkLocked(uint64_t aligned) {
        for (auto& c : readChunks_) {
            if (c.off == aligned) return &c;
        }
        return nullptr;
    }

    ReadChunk* fillReadChunkLocked(int volId, uint64_t aligned) {
        ReadChunk* lru = &readChunks_[0];
        for (auto& c : readChunks_) {
            if (c.off == CHUNK_EMPTY) { lru = &c; break; }
            if (c.stamp < lru->stamp) lru = &c;
        }

        lru->off = CHUNK_EMPTY;
        if (!directRead(volId, aligned, lru->data.data(), READ_CHUNK_BYTES)) {
            return nullptr;
        }
        lru->off = aligned;
        lru->stamp = ++clock_;
        return lru;
    }

    void invalidateReadCacheLocked(uint64_t off, size_t len) {
        uint64_t end = off + len;
        for (auto& c : readChunks_) {
            if (c.off == CHUNK_EMPTY) continue;
            uint64_t cend = c.off + READ_CHUNK_BYTES;
            if (end <= c.off || off >= cend) continue;
            c.off = CHUNK_EMPTY;
        }
    }

    bool directRead(int volId, uint64_t off, unsigned char* dst, size_t len) {
        if (len % SECTOR_SIZE != 0 || off % SECTOR_SIZE != 0) return false;
        return usbReadSectors(volId, off / SECTOR_SIZE, static_cast<uint32_t>(len / SECTOR_SIZE), dst);
    }

    bool directWrite(int volId, uint64_t off, const unsigned char* src, size_t len) {
        if (len % SECTOR_SIZE != 0 || off % SECTOR_SIZE != 0) return false;
        return usbWriteSectors(volId, off / SECTOR_SIZE, static_cast<uint32_t>(len / SECTOR_SIZE), src);
    }
};