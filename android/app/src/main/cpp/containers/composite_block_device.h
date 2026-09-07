#pragma once
#include <cstdint>
#include <vector>
#include <string>
#include <mutex>
#include <memory>
#include "io/carrier_fd_cache.h"

struct CarrierExtent {
    uint32_t fileIndex = 0;      // Index into CarrierFdCache
    uint64_t offsetInFile = 0;   // Byte offset inside the host carrier file
    uint64_t lengthBytes = 0;    // Sector-aligned length (multiple of 512)
};

class CompositeBlockDevice {
public:
    CompositeBlockDevice(std::vector<CarrierExtent> extents,
                         std::shared_ptr<CarrierFdCache> fdCache);
    ~CompositeBlockDevice() = default;

    CompositeBlockDevice(const CompositeBlockDevice&) = delete;
    CompositeBlockDevice& operator=(const CompositeBlockDevice&) = delete;

    bool pread(uint64_t byteOffset, unsigned char* outBuf, size_t len);
    bool pwrite(uint64_t byteOffset, const unsigned char* inBuf, size_t len);

    // Fsyncs every carrier fd backing this device. Composite volumes have no
    // single fd for the filesystem/session layer to fsync (see VolumeState::fd
    // == -1 for composite sources), so this is the only durability path they
    // have -- callers must invoke it wherever a non-composite volume would
    // normally fsync(v.fd) (CTRL_SYNC, filesystem unmount/flush, etc).
    bool sync();

    uint64_t totalSize() const { return totalLogicalBytes_; }
    size_t extentCount() const { return extents_.size(); }
    const std::vector<CarrierExtent>& extents() const { return extents_; }

private:
    std::vector<CarrierExtent> extents_;
    std::vector<uint64_t> cumulativeOffsets_; // Prefix sums, size = extents.size() + 1
    uint64_t totalLogicalBytes_ = 0;
    std::shared_ptr<CarrierFdCache> fdCache_;
    std::mutex ioMutex_;

    size_t findExtentIndex(uint64_t logicalOffset) const;
};