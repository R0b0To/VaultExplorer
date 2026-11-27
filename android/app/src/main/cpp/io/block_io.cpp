#include "block_io.h"
#include <unistd.h>
#include <cerrno>
#include <atomic>
#include <system_error>
#include "platform/engine_log.h"
#include "platform/engine_hooks.h"
#include "volume_state.h"
#include "containers/composite_block_device.h"

#define LOGI(...) ENGINE_LOG_INFO("VaultExplorer_C++", __VA_ARGS__)
#define LOGW(...) ENGINE_LOG_WARN("VaultExplorer_C++", __VA_ARGS__)

namespace {
// First few occurrences, then exponentially rarer, so a dead fd or a
// read-only volume being written to in a loop cannot flood logcat.
bool shouldLogOccurrence(std::atomic<unsigned>& counter, unsigned& nOut) {
    nOut = counter.fetch_add(1, std::memory_order_relaxed) + 1;
    return nOut <= 5 || (nOut & (nOut - 1)) == 0;
}
}  // namespace

bool physicalRead(int volumeId, uint64_t byteOffset, unsigned char* buffer,
                  size_t byteCount) {
    VolumeState& volume = volumes[volumeId];
    if (volume.isCompositeSource) {
        if (!volume.composite) return false;
        return volume.composite->pread(byteOffset, buffer, byteCount);
    } else if (volume.isUsbSource) {
        return volume.usbCache.read(volumeId, byteOffset, buffer, byteCount);
    } else {
        if (!volume.fdWriteBuffer.flushIfOverlaps(volume.fd, byteOffset, byteCount)) {
            return false;
        }
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
                // received == 0 is a plain EOF (format probing reads past the end
                // on purpose); only a real errno is worth a log line.
                if (received < 0) {
                    const int err = errno;
                    static std::atomic<unsigned> readFailures{0};
                    unsigned n = 0;
                    if (shouldLogOccurrence(readFailures, n)) {
                        LOGW("pread64 failed (#%u): vol=%d errno=%d (%s) off=%llu len=%zu done=%zu",
                             n, volumeId, err, std::generic_category().message(err).c_str(),
                             (unsigned long long)(byteOffset + totalRead),
                             byteCount - totalRead, totalRead);
                    }
                }
                return false;
            }
        }
        return true;
    }
}

bool physicalWrite(int volumeId, uint64_t byteOffset,
                   const unsigned char* buffer, size_t byteCount) {
    VolumeState& volume = volumes[volumeId];
    if (volume.readOnly) {
        // The JNI layer throws READ_ONLY before getting here, so reaching this
        // means an internal path (cache flush, metadata update) tried to write.
        static std::atomic<unsigned> readOnlyRefusals{0};
        unsigned n = 0;
        if (shouldLogOccurrence(readOnlyRefusals, n)) {
            LOGW("physicalWrite(vol=%d): refused, volume is read-only (#%u, off=%llu len=%zu, "
                 "hiddenProtectionTriggered=%d)",
                 volumeId, n, (unsigned long long)byteOffset, byteCount,
                 volume.hiddenVolumeProtectionTriggered ? 1 : 0);
        }
        return false;
    }
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

    if (volume.isCompositeSource) {
        if (!volume.composite) return false;
        return volume.composite->pwrite(byteOffset, buffer, byteCount);
    } else if (volume.isUsbSource) {
        return volume.usbCache.write(volumeId, byteOffset, buffer, byteCount);
    } else {
        return volume.fdWriteBuffer.write(volume.fd, byteOffset, buffer, byteCount);
    }
}

bool usbFlushAndSync(int volumeId) {
    if (volumeId < 0 || volumeId >= FF_VOLUMES) return false;
    VolumeState& v = volumes[volumeId];
    if (!v.isUsbSource) return true;
    return v.usbCache.sync(volumeId);
}