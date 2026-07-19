#include "session_guard.h"

#include <android/log.h>
#include <cstdio>
#include <mutex>

#include "jni_callbacks.h"
#include "volume_state.h"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

bool requireActiveSession(int volumeId, const char* operation) {
    if (volumeId < 0 || volumeId >= FF_VOLUMES) return false;
    VolumeState& volume = volumes[volumeId];
    std::lock_guard<std::mutex> lock(volume.mutex);
    if (!volume.dataCtxInitialized || (volume.fd < 0 && !volume.isUsbSource)) {
        LOGI("%s: volume %d has no active session (not unlocked)", operation, volumeId);
        return false;
    }
    return true;
}

void throwNotUnlocked(JNIEnv* env, int volumeId, const char* operation) {
    char message[160];
    snprintf(message, sizeof(message), "NOT_UNLOCKED: volume %d has no active session (%s)",
             volumeId, operation);
    env->ThrowNew(g_illegalStateExceptionClass, message);
}

bool isVolumeReadOnly(int volumeId) {
    if (volumeId < 0 || volumeId >= FF_VOLUMES) return false;
    VolumeState& volume = volumes[volumeId];
    std::lock_guard<std::mutex> lock(volume.mutex);
    return volume.readOnly;
}

void throwReadOnly(JNIEnv* env, int volumeId, const char* operation) {
    char message[160];
    snprintf(message, sizeof(message), "READ_ONLY: volume %d is mounted read-only (%s)",
             volumeId, operation);
    env->ThrowNew(g_illegalStateExceptionClass, message);
}