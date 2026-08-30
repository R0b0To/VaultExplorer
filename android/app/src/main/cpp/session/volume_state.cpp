#include "volume_state.h"
#include "bitlocker_backend.h"
#include "containers/vhd_image.h"
#include "containers/vhdx_image.h"

VolumeState volumes[FF_VOLUMES];
std::mutex slotAllocMutex;

void VolumeState::reset() {
    bitlockerCloseVolume(*this);
    // Mirrors bitlockerCloseVolume's own VhdxImage/VhdImage teardown, for
    // the same reason: whichever of the two plainImage actually points at
    // (per plainBacking) owns an in-memory BAT that nothing else
    // references once this slot is torn down.
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
    if (preservedDerivedKey) {
        mbedtls_platform_zeroize(preservedDerivedKey, preservedDerivedKeyLen);
        delete[] preservedDerivedKey;
        preservedDerivedKey = nullptr;
        preservedDerivedKeyLen = 0;
    }
}