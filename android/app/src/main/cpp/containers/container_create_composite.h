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

struct CompositeUnlockResult {
    bool success = false;
    // One of: INVALID_VOLUME_ID, SIZE_TOO_SMALL, HEADER_READ_FAILED,
    // KEYFILE_FAILED, INCORRECT_PASSWORD_OR_INVALID_CONTAINER,
    // COMPOSITE_CARRIERS_INCOMPLETE, CASCADE_KEY_SETUP_FAILED. Empty on success.
    std::string errorCode;
};

CompositeUnlockResult prepareCompositeSession(
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