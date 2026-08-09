#include "chunked_block_device.h"
#include <algorithm>

ChunkedBlockDevice::ChunkedBlockDevice(uint64_t totalVolumeSizeBytes,
                                       uint32_t chunkSizeNumBytes,
                                       ChunkReadFn readFn,
                                       ChunkWriteFn writeFn)
    : totalVolumeSizeBytes_(totalVolumeSizeBytes),
      chunkSizeNumBytes_(chunkSizeNumBytes > 0 ? chunkSizeNumBytes : static_cast<uint32_t>(DEFAULT_CHUNK_SIZE_BYTES)),
      readFn_(std::move(readFn)),
      writeFn_(std::move(writeFn)) {}

bool ChunkedBlockDevice::pread(uint64_t byteOffset, unsigned char* outBuf, size_t len) {
    if (len == 0) return true;
    if (!outBuf || byteOffset > totalVolumeSizeBytes_ ||
        static_cast<uint64_t>(len) > totalVolumeSizeBytes_ - byteOffset) return false;
    if (!readFn_) return false;

    std::lock_guard<std::mutex> lock(ioMutex_);
    uint64_t bytesRemaining = len;
    uint64_t currentOffset = byteOffset;
    unsigned char* destPtr = outBuf;

    while (bytesRemaining > 0) {
        const uint64_t chunkIndex = currentOffset / chunkSizeNumBytes_;
        const uint64_t offsetInChunk = currentOffset % chunkSizeNumBytes_;
        const size_t bytesToRead = static_cast<size_t>(
            std::min<uint64_t>(bytesRemaining, chunkSizeNumBytes_ - offsetInChunk));

        if (!readFn_(chunkIndex, offsetInChunk, destPtr, bytesToRead)) {
            return false;
        }

        bytesRemaining -= bytesToRead;
        currentOffset += bytesToRead;
        destPtr += bytesToRead;
    }
    return true;
}

bool ChunkedBlockDevice::pwrite(uint64_t byteOffset, const unsigned char* inBuf, size_t len) {
    if (len == 0) return true;
    if (!inBuf || byteOffset > totalVolumeSizeBytes_ ||
        static_cast<uint64_t>(len) > totalVolumeSizeBytes_ - byteOffset) return false;
    if (!writeFn_) return false;

    std::lock_guard<std::mutex> lock(ioMutex_);
    uint64_t bytesRemaining = len;
    uint64_t currentOffset = byteOffset;
    const unsigned char* srcPtr = inBuf;

    while (bytesRemaining > 0) {
        const uint64_t chunkIndex = currentOffset / chunkSizeNumBytes_;
        const uint64_t offsetInChunk = currentOffset % chunkSizeNumBytes_;
        const size_t bytesToWrite = static_cast<size_t>(
            std::min<uint64_t>(bytesRemaining, chunkSizeNumBytes_ - offsetInChunk));

        // Sub-chunk read-modify-write (e.g. a 5 KB file write landing
        // inside one 4 MB chunk) is intentionally NOT this class's job —
        // writeFn_ owns that, exactly the way CloudChunkBridge.writeChunkRange
        // does on the Kotlin side (reads the current full chunk from its
        // cache, splices, re-uploads the whole chunk). Keeping the splice
        // out of this class keeps it a pure offset router with no cache
        // of its own to keep coherent with the one Kotlin already
        // maintains (Phase 3's ChunkCacheManager) or invalidate correctly.
        if (!writeFn_(chunkIndex, offsetInChunk, srcPtr, bytesToWrite)) {
            return false;
        }

        bytesRemaining -= bytesToWrite;
        currentOffset += bytesToWrite;
        srcPtr += bytesToWrite;
    }
    return true;
}
