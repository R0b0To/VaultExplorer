#include "block_io.h"
#include <unistd.h>
#include "jni_callbacks.h"
#include "volume_state.h"

bool physicalRead(int volumeId, uint64_t byteOffset, unsigned char* buffer,
                  size_t byteCount) {
    VolumeState& volume = volumes[volumeId];
    if (volume.isUsbSource) {
        return usbReadSectors(volumeId, byteOffset / 512,
                              static_cast<uint32_t>(byteCount / 512), buffer);
    }
    const ssize_t received = pread(volume.fd, buffer, byteCount,
                                   static_cast<off_t>(byteOffset));
    return received == static_cast<ssize_t>(byteCount);
}

bool physicalWrite(int volumeId, uint64_t byteOffset,
                   const unsigned char* buffer, size_t byteCount) {
    VolumeState& volume = volumes[volumeId];
    if (volume.readOnly) return false;
    if (volume.isUsbSource) {
        return usbWriteSectors(volumeId, byteOffset / 512,
                               static_cast<uint32_t>(byteCount / 512), buffer);
    }
    const ssize_t written = pwrite(volume.fd, buffer, byteCount,
                                   static_cast<off_t>(byteOffset));
    return written == static_cast<ssize_t>(byteCount);
}