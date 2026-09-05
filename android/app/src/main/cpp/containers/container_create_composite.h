#pragma once
#include <cstdint>
#include <vector>
#include <string>
#include "containers/composite_block_device.h"
#include "containers/carrier_profiler.h"

struct CompositeCreateResult {
    bool success = false;
    std::string errorCode;
    std::string errorMessage;
    uint64_t totalVolumeBytes = 0;
};

CompositeCreateResult createCompositeContainer(
    int volId,
    const std::vector<CarrierTarget>& carriers,
    const std::vector<CarrierExtent>& extents,
    const char* password,
    int pim,
    const char* fileSystem,
    int containerFormat,
    int cipherId,
    int hashId,
    const int* keyfileFds,
    int keyfileCount,
    bool quickFormat,
    const char* operationId = ""
);

bool prepareCompositeSession(
    int volId,
    const std::vector<CarrierTarget>& carriers,
    const std::vector<CarrierExtent>& extents,
    const unsigned char* password,
    size_t passwordLen,
    int pim,
    int cipherId,
    int hashId,
    const int* keyfileFds,
    int keyfileCount,
    bool readOnly
);