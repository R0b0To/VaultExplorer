#include "volume_state.h"

VolumeState volumes[FF_VOLUMES];
std::mutex slotAllocMutex;

void VolumeState::reset() {
    if (fd >= 0) close(fd);
    fd = -1;
    dataOffset = 0;
    dataAreaLengthBytes = 0;
    isHiddenVolume = false;
    fileSize = 0;
    isUsbSource = false;
    readOnly = false;
    partitionStartSector = 0;
    dataCtxInitialized = false;
    cascade.initialized = false;
    matchedCipherId = -1;
    matchedHashId = -1;
    fsType = FS_UNKNOWN;
    ntfsVol = nullptr;
    extFs = nullptr;
    containerFormat = ContainerFormat::kVeraCrypt;
    luksSectorSize = 512;
    luksUsesGenericCipher = false;
    luksGenericCascade.initialized = false;
    if (luksXts.initialized) {
        mbedtls_aes_xts_free(&luksXts.dec);
        mbedtls_aes_xts_free(&luksXts.enc);
        mbedtls_aes_xts_init(&luksXts.dec);
        mbedtls_aes_xts_init(&luksXts.enc);
        luksXts.initialized = false;
    }
    if (preservedDerivedKey) {
        mbedtls_platform_zeroize(preservedDerivedKey, preservedDerivedKeyLen);
        delete[] preservedDerivedKey;
        preservedDerivedKey = nullptr;
        preservedDerivedKeyLen = 0;
    }
}
