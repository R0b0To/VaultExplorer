#pragma once
#include <cstdint>
#include <vector>

struct SectorBatch {
    uint64_t startSector; 
    uint32_t count;
};


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