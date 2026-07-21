#include "volume_state.h"
#include "bitlocker_backend.h"

VolumeState volumes[FF_VOLUMES];
std::mutex slotAllocMutex;

void VolumeState::reset() {
    // Must run before fd is touched below: bitlockerCloseVolume() frees the
    // dis_context_t (dislocker context), but (like every other owned
    // resource in this function) never closes the real fd itself -- the
    // close(fd) immediately below is what does that, same as it always has
    // for VeraCrypt/LUKS. See bitlocker_backend.h's doc comment on
    // bitlockerCloseVolume for why this lives here and not unmountVolume().
    bitlockerCloseVolume(*this);
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
    extBitmapsLoaded = false;
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