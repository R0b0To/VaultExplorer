// Host-side test, no Android toolchain required:
//   g++ -std=c++17 sector_batching_test.cpp -o sector_batching_test && ./sector_batching_test
#include "../sector_batching.h"
#include <cassert>
#include <cstdio>

static void expectBatches(const std::vector<SectorBatch>& b,
                           std::initializer_list<std::pair<uint64_t,uint32_t>> expected) {
    assert(b.size() == expected.size());
    size_t i = 0;
    for (auto& e : expected) {
        assert(b[i].startSector == e.first);
        assert(b[i].count == e.second);
        i++;
    }
}

int main() {
    // Under the old hard cap, count > 8192 would have returned RES_PARERR.
    // These cases are exactly what previously failed and must now succeed.

    // Exactly at the old limit — single batch, unchanged behavior.
    expectBatches(planSectorBatches(8192, 8192), {{0, 8192}});

    // One sector over the old limit — must now split into 2 batches, not fail.
    expectBatches(planSectorBatches(8193, 8192), {{0, 8192}, {8192, 1}});

    // Large multi-MB sequential read (e.g. 4096-sector video read chunks
    // multiplied up): 20000 sectors -> 8192 + 8192 + 3616, no remainder lost.
    expectBatches(planSectorBatches(20000, 8192), {{0, 8192}, {8192, 8192}, {16384, 3616}});

    // Exact multiple of batch size — no trailing empty batch.
    expectBatches(planSectorBatches(16384, 8192), {{0, 8192}, {8192, 8192}});

    // Single small read — one batch, no splitting overhead.
    expectBatches(planSectorBatches(1, 8192), {{0, 1}});

    // count == 0 must produce zero batches (caller still returns RES_PARERR
    // for this case at the disk_read/disk_write entry, not from the planner).
    expectBatches(planSectorBatches(0, 8192), {});

    printf("sector_batching_test: all assertions passed\n");
    return 0;
}