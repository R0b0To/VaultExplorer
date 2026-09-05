#include "composite_block_device.h"
#include <algorithm>
#include <cstring>
#include <unistd.h>

#undef min
#undef max

CompositeBlockDevice::CompositeBlockDevice(
    std::vector<CarrierExtent> extents,
    std::shared_ptr<CarrierFdCache> fdCache
) : extents_(std::move(extents)), fdCache_(std::move(fdCache)) {
    cumulativeOffsets_.reserve(extents_.size() + 1);
    uint64_t acc = 0;
    cumulativeOffsets_.push_back(acc);
    for (const auto& extent : extents_) {
        // Enforce sector alignment (no sector straddles extents)
        uint64_t alignedLen = (extent.lengthBytes / 512) * 512;
        acc += alignedLen;
        cumulativeOffsets_.push_back(acc);
    }
    totalLogicalBytes_ = acc;
}

size_t CompositeBlockDevice::findExtentIndex(uint64_t logicalOffset) const {
    auto it = std::upper_bound(cumulativeOffsets_.begin(), cumulativeOffsets_.end(), logicalOffset);
    if (it == cumulativeOffsets_.begin()) return 0;
    return static_cast<size_t>((it - cumulativeOffsets_.begin()) - 1);
}

bool CompositeBlockDevice::pread(uint64_t byteOffset, unsigned char* outBuf, size_t len) {
    if (len == 0) return true;
    if (!outBuf || byteOffset > totalLogicalBytes_ ||
        static_cast<uint64_t>(len) > totalLogicalBytes_ - byteOffset) {
        return false;
    }
    if (!fdCache_) return false;

    std::lock_guard<std::mutex> lock(ioMutex_);
    uint64_t remaining = len;
    uint64_t currentLogical = byteOffset;
    unsigned char* outPtr = outBuf;

    while (remaining > 0) {
        size_t extIdx = findExtentIndex(currentLogical);
        if (extIdx >= extents_.size()) return false;

        const auto& extent = extents_[extIdx];
        uint64_t extStartLogical = cumulativeOffsets_[extIdx];
        uint64_t offsetInExtent = currentLogical - extStartLogical;
        uint64_t alignedLen = (extent.lengthBytes / 512) * 512;
        if (offsetInExtent >= alignedLen) return false;

        size_t bytesToRead = static_cast<size_t>(std::min<uint64_t>(remaining, alignedLen - offsetInExtent));

        int fd = fdCache_->acquire(extent.fileIndex);
        if (fd < 0) return false;

        uint64_t fileSeek = extent.offsetInFile + offsetInExtent;
        size_t totalRead = 0;
        while (totalRead < bytesToRead) {
            ssize_t n = ::pread64(fd, outPtr + totalRead, bytesToRead - totalRead,
                                  static_cast<off64_t>(fileSeek + totalRead));
            if (n > 0) {
                totalRead += static_cast<size_t>(n);
            } else if (n < 0 && (errno == EINTR || errno == EAGAIN)) {
                continue;
            } else {
                fdCache_->release(extent.fileIndex);
                return false;
            }
        }
        fdCache_->release(extent.fileIndex);

        remaining -= bytesToRead;
        currentLogical += bytesToRead;
        outPtr += bytesToRead;
    }
    return true;
}

bool CompositeBlockDevice::pwrite(uint64_t byteOffset, const unsigned char* inBuf, size_t len) {
    if (len == 0) return true;
    if (!inBuf || byteOffset > totalLogicalBytes_ ||
        static_cast<uint64_t>(len) > totalLogicalBytes_ - byteOffset) {
        return false;
    }
    if (!fdCache_) return false;

    std::lock_guard<std::mutex> lock(ioMutex_);
    uint64_t remaining = len;
    uint64_t currentLogical = byteOffset;
    const unsigned char* inPtr = inBuf;

    while (remaining > 0) {
        size_t extIdx = findExtentIndex(currentLogical);
        if (extIdx >= extents_.size()) return false;

        const auto& extent = extents_[extIdx];
        uint64_t extStartLogical = cumulativeOffsets_[extIdx];
        uint64_t offsetInExtent = currentLogical - extStartLogical;
        uint64_t alignedLen = (extent.lengthBytes / 512) * 512;
        if (offsetInExtent >= alignedLen) return false;

        size_t bytesToWrite = static_cast<size_t>(std::min<uint64_t>(remaining, alignedLen - offsetInExtent));

        int fd = fdCache_->acquire(extent.fileIndex);
        if (fd < 0) return false;

        uint64_t fileSeek = extent.offsetInFile + offsetInExtent;
        size_t totalWritten = 0;
        while (totalWritten < bytesToWrite) {
            ssize_t n = ::pwrite64(fd, inPtr + totalWritten, bytesToWrite - totalWritten,
                                   static_cast<off64_t>(fileSeek + totalWritten));
            if (n > 0) {
                totalWritten += static_cast<size_t>(n);
            } else if (n < 0 && (errno == EINTR || errno == EAGAIN)) {
                continue;
            } else {
                fdCache_->release(extent.fileIndex);
                return false;
            }
        }
        fdCache_->release(extent.fileIndex);

        remaining -= bytesToWrite;
        currentLogical += bytesToWrite;
        inPtr += bytesToWrite;
    }
    return true;
}