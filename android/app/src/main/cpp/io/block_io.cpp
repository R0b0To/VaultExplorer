#include "block_io.h"
#include <unistd.h>
#include <cerrno>
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
        size_t totalRead = 0;
        while (totalRead < byteCount) {
            const ssize_t received = pread64(volume.fd, buffer + totalRead,
                                           byteCount - totalRead,
                                           static_cast<off64_t>(byteOffset + totalRead));
            if (received > 0) {
                totalRead += static_cast<size_t>(received);
            } else if (received < 0 && (errno == EINTR || errno == EAGAIN)) {
                continue;
            } else {
                return false;
            }
        }
        return true;
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
        size_t totalWritten = 0;
        while (totalWritten < byteCount) {
            const ssize_t written = pwrite64(volume.fd, buffer + totalWritten,
                                            byteCount - totalWritten,
                                            static_cast<off64_t>(byteOffset + totalWritten));
            if (written > 0) {
                totalWritten += static_cast<size_t>(written);
            } else if (written < 0 && (errno == EINTR || errno == EAGAIN)) {
                continue;
            } else {
                return false;
            }
        }
        return true;
    }
}