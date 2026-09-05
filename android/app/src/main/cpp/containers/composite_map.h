#pragma once
#include <cstdint>
#include <vector>
#include <string>
#include "composite_block_device.h"
#include "carrier_profiler.h"

class CompositeMap {
public:
    // Sorts carriers canonically using SHA-256 over immutable header bytes
    static void sortCanonical(std::vector<CarrierTarget>& carriers);

    // Derives extent definitions deterministically from capacity profile budgets
    static std::vector<CarrierExtent> deriveExtents(
        const std::vector<CarrierBudget>& budgets,
        uint64_t requestedTotalBytes = 0
    );

    // Formats host carriers with ignorable box headers (e.g., MP4 'free' box, PNG ancillary chunk)
    static bool prepareCarrierStructures(
        const std::vector<CarrierBudget>& budgets,
        const std::shared_ptr<CarrierFdCache>& fdCache
    );
};