#include "block_io.h"
#include <unistd.h>
#include <android/log.h>
#include "jni_callbacks.h"
#include "volume_state.h"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

bool physicalRead(int volumeId, uint64_t byteOffset, unsigned char* buffer,
                  size_t byteCount) {
    VolumeState& volume = volumes[volumeId];
    if (volume.isUsbSource) {
        return usbReadSectors(volumeId, byteOffset / 512,
                              static_cast<uint32_t>(byteCount / 512), buffer);
    } else {
        const ssize_t received = pread(volume.fd, buffer, byteCount,
                                       static_cast<off_t>(byteOffset));
        return received == static_cast<ssize_t>(byteCount);
    }
}

bool physicalWrite(int volumeId, uint64_t byteOffset,
                   const unsigned char* buffer, size_t byteCount) {
    VolumeState& volume = volumes[volumeId];
    if (volume.readOnly) return false;

    // "Protect hidden volume against damage caused by writing to outer
    // volume" -- see enableHiddenVolumeProtection() (session_prepare.cpp)
    // for how [hiddenProtectedStart, hiddenProtectedEnd) is derived. Any
    // write that overlaps it is refused outright, and (matching real
    // VeraCrypt's documented behavior) the whole volume is permanently
    // switched to read-only for the rest of this session the first time
    // this happens: once one write has been silently dropped, the outer
    // filesystem's own bookkeeping of what's free/in-use can no longer be
    // trusted, so allowing further writes elsewhere in the volume risks
    // exactly the same kind of silent corruption this option exists to
    // prevent.
    if (volume.hiddenVolumeProtectionEnabled && byteCount > 0) {
        const uint64_t writeEnd = byteOffset + static_cast<uint64_t>(byteCount);
        const bool overlapsHiddenArea =
            writeEnd > volume.hiddenProtectedStart && byteOffset < volume.hiddenProtectedEnd;
        if (overlapsHiddenArea) {
            LOGI("physicalWrite(vol=%d): BLOCKED write [%llu,%llu) overlaps protected "
                 "range [%llu,%llu) (triggeredBefore=%d)",
                 volumeId, (unsigned long long)byteOffset, (unsigned long long)writeEnd,
                 (unsigned long long)volume.hiddenProtectedStart,
                 (unsigned long long)volume.hiddenProtectedEnd,
                 volume.hiddenVolumeProtectionTriggered ? 1 : 0);
            if (!volume.hiddenVolumeProtectionTriggered) {
                volume.hiddenVolumeProtectionTriggered = true;
                volume.readOnly = true;
                notifyHiddenVolumeProtectionTriggered(volumeId);
            }
            return false;
        }
    }

    if (volume.isUsbSource) {
        return usbWriteSectors(volumeId, byteOffset / 512,
                               static_cast<uint32_t>(byteCount / 512), buffer);
    } else {
        const ssize_t written = pwrite(volume.fd, buffer, byteCount,
                                       static_cast<off_t>(byteOffset));
        return written == static_cast<ssize_t>(byteCount);
    }
}