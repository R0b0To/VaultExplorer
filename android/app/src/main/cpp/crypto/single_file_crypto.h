#pragma once
#include <cstdint>
#include <cstddef>
#include <functional>

bool encryptSingleFile(
    int srcFd,
    int destFd,
    int cipherIndex,
    const unsigned char* password,
    size_t passwordLen,
    const int* keyfileFds,
    int keyfileCount,
    int opId,
    std::function<bool()> cancelCheck,
    std::function<void(uint64_t bytesDone, uint64_t bytesTotal)> progressCallback
);

bool decryptSingleFile(
    int srcFd,
    int destFd,
    const unsigned char* password,
    size_t passwordLen,
    const int* keyfileFds,
    int keyfileCount,
    int opId,
    std::function<bool()> cancelCheck,
    std::function<void(uint64_t bytesDone, uint64_t bytesTotal)> progressCallback
);