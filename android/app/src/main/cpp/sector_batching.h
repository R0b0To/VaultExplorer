// Pure, host-testable batching logic extracted from disk_read/disk_write's
// inner loop. No JNI/Android/mbedTLS dependency — this file can be compiled
// and unit-tested on any host machine.
#pragma once
#include <cstdint>
#include <vector>

struct SectorBatch {
    uint64_t startSector; // relative to the `sector` argument, i.e. offset 0 = first sector of the call
    uint32_t count;
};

// Splits [0, totalSectors) into batches of at most maxPerBatch sectors.
// Mirrors the loop structure in disk_read/disk_write exactly — if this
// function's output is wrong, the real I/O loop is wrong in the same way.
inline std::vector<SectorBatch> planSectorBatches(uint32_t totalSectors, uint32_t maxPerBatch) {
    std::vector<SectorBatch> batches;
    if (totalSectors == 0 || maxPerBatch == 0) return batches;

    uint64_t offset = 0;
    uint32_t remaining = totalSectors;
    while (remaining > 0) {
        uint32_t batchCount = remaining < maxPerBatch ? remaining : maxPerBatch;
        batches.push_back({offset, batchCount});
        offset += batchCount;
        remaining -= batchCount;
    }
    return batches;
}