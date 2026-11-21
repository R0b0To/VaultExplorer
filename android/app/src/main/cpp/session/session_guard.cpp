#include "session_guard.h"

#include <mutex>
#include <shared_mutex>

#include "platform/engine_log.h"
#include "volume_state.h"

#define LOGI(...) ENGINE_LOG_INFO("VaultExplorer_C++", __VA_ARGS__)

bool requireActiveSession(int volumeId, const char* operation) {
    if (volumeId < 0 || volumeId >= FF_VOLUMES) return false;
    VolumeState& volume = volumes[volumeId];
    std::shared_lock<std::shared_mutex> lock(volume.mutex);
    if (!volume.dataCtxInitialized || (volume.fd < 0 && !volume.isUsbSource && !volume.isCompositeSource)) {
        LOGI("%s: volume %d has no active session (not unlocked)", operation, volumeId);
        return false;
    }
    return true;
}

bool isVolumeReadOnly(int volumeId) {
    if (volumeId < 0 || volumeId >= FF_VOLUMES) return false;
    VolumeState& volume = volumes[volumeId];
    std::shared_lock<std::shared_mutex> lock(volume.mutex);
    return volume.readOnly;
}
