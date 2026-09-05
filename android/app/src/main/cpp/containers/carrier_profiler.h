#pragma once
#include <cstdint>
#include <string>
#include <vector>
#include "io/carrier_fd_cache.h"

enum class CarrierTier : uint8_t {
    High = 0,    // Spec-guaranteed skippable box (MP4/MOV free box, MKV Void, PNG ancillary chunk)
    Medium = 1,  // JPEG APPn, PDF unreferenced objects
    Low = 2      // Appended bytes after logical EOF
};

struct CarrierBudget {
    uint32_t fileIndex = 0;
    std::string path;
    std::string detectedFormat; // "png", "isobmff", "ebml", "jpeg", "wav", "flac", "generic"
    uint64_t fileSize = 0;
    uint64_t payloadOffset = 0;     // Byte offset where embedded storage starts
    uint64_t allocatableBytes = 0; // Sector-aligned (multiple of 512)
    CarrierTier tier = CarrierTier::Low;
    bool alreadyAllocated = false;
};

struct CapacityProfile {
    std::vector<CarrierBudget> perFile;
    uint64_t totalAllocatableBytes = 0;
};

class CarrierProfiler {
public:
    static CapacityProfile profileForAllocation(
        const std::vector<CarrierTarget>& carriers,
        unsigned safetyMarginPct = 90
    );

    static CapacityProfile profileForRecovery(
        const std::vector<CarrierTarget>& carriers
    );

    static CarrierBudget inspectSingleCarrier(
        int fd,
        uint32_t fileIndex,
        const std::string& path,
        bool allocateMode,
        unsigned safetyMarginPct = 90
    );
};