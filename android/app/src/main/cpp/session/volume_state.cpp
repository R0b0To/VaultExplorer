#include "volume_state.h"
#include "bitlocker_backend.h"
#include "containers/vhd_image.h"
#include "containers/vhdx_image.h"

VolumeState volumes[FF_VOLUMES];
std::mutex slotAllocMutex;

void VolumeState::reset() {
    bitlockerCloseVolume(*this);

    if (plainImage) {
        if (plainBacking == PlainBacking::kVhdx) delete static_cast<VhdxImage*>(plainImage);
        else if (plainBacking == PlainBacking::kVhd) delete static_cast<VhdImage*>(plainImage);
        plainImage = nullptr;
    }
    plainBacking = PlainBacking::kFlatFile;

    if (fd >= 0) close(fd);
    fd = -1;
    dataOffset = 0;
    dataAreaLengthBytes = 0;
    isHiddenVolume = false;
    fileSize = 0;
    isUsbSource = false;
    readOnly = false;
    hiddenVolumeProtectionEnabled = false;
    hiddenProtectedStart = 0;
    hiddenProtectedEnd = 0;
    hiddenVolumeProtectionTriggered = false;
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
    luksGenericCascade.initialized = false;
    isCompositeSource = false;
    composite.reset();

    // Clear and reset USB cache state
    usbCache.clear();

    if (preservedDerivedKey) {
        mbedtls_platform_zeroize(preservedDerivedKey, preservedDerivedKeyLen);
        delete[] preservedDerivedKey;
        preservedDerivedKey = nullptr;
        preservedDerivedKeyLen = 0;
    }
}