#include "jni_callbacks.h"

namespace {
struct ThreadJniEnv {
    JNIEnv* env = nullptr;
    bool weAttached = false;
    JNIEnv* get() {
        if (env) return env;
        if (!g_vm) return nullptr;
        if (g_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK) {
            return env;
        }
        if (g_vm->AttachCurrentThread(&env, nullptr) == JNI_OK) {
            weAttached = true;
            return env;
        }
        env = nullptr;
        return nullptr;
    }
    ~ThreadJniEnv() {
        if (weAttached && g_vm) g_vm->DetachCurrentThread();
    }
};
thread_local ThreadJniEnv g_threadJniEnv;
}

void reportUnlockProgress(int volId, int attempted, int total, int hashId,
                          int cipherId, int format, int slot) {
    if (volId < 0) return;
    JNIEnv* env = g_threadJniEnv.get();
    if (!env) return;
    env->CallStaticVoidMethod(
        g_progressBridgeClass, g_progressReportMethod,
        static_cast<jint>(volId), static_cast<jint>(attempted), static_cast<jint>(total),
        static_cast<jint>(hashId), static_cast<jint>(cipherId), static_cast<jint>(format), static_cast<jint>(slot));
    if (env->ExceptionCheck()) env->ExceptionClear();
}

void reportSplitJoinProgress(int opId, uint64_t bytesDone, uint64_t bytesTotal) {
    if (opId <= 0) return;
    JNIEnv* env = g_threadJniEnv.get();
    if (!env || !g_splitJoinProgressBridgeClass || !g_splitJoinProgressReportMethod) return;
    env->CallStaticVoidMethod(
        g_splitJoinProgressBridgeClass, g_splitJoinProgressReportMethod,
        static_cast<jint>(opId), static_cast<jlong>(bytesDone), static_cast<jlong>(bytesTotal));
    if (env->ExceptionCheck()) env->ExceptionClear();
}

bool isSplitJoinCancelled(int opId) {
    if (opId <= 0) return false;
    JNIEnv* env = g_threadJniEnv.get();
    if (!env || !g_splitJoinCancellationClass || !g_splitJoinIsCancelledMethod) return false;
    jboolean cancelled = env->CallStaticBooleanMethod(
        g_splitJoinCancellationClass, g_splitJoinIsCancelledMethod, static_cast<jint>(opId));
    if (env->ExceptionCheck()) { env->ExceptionClear(); return false; }
    return cancelled == JNI_TRUE;
}

void reportRepairLog(int opId, const char* message) {
    if (opId <= 0 || !message) return;
    JNIEnv* env = g_threadJniEnv.get();
    if (!env || !g_repairLogBridgeClass || !g_repairLogReportMethod) return;
    jstring jMessage = env->NewStringUTF(message);
    if (!jMessage) return;
    env->CallStaticVoidMethod(g_repairLogBridgeClass, g_repairLogReportMethod,
                              static_cast<jint>(opId), jMessage);
    env->DeleteLocalRef(jMessage);
    if (env->ExceptionCheck()) env->ExceptionClear();
}

void reportCopyProgress(int opId, uint64_t bytesDelta) {
    if (opId <= 0 || bytesDelta == 0) return;
    JNIEnv* env = g_threadJniEnv.get();
    if (!env || !g_copyProgressBridgeClass || !g_copyProgressReportMethod) return;
    env->CallStaticVoidMethod(
        g_copyProgressBridgeClass, g_copyProgressReportMethod,
        static_cast<jint>(opId), static_cast<jlong>(bytesDelta));
    if (env->ExceptionCheck()) env->ExceptionClear();
}

bool isCopyCancelled(int opId) {
    if (opId <= 0) return false;
    JNIEnv* env = g_threadJniEnv.get();
    if (!env || !g_copyCancellationClass || !g_copyIsCancelledMethod) return false;
    jboolean cancelled = env->CallStaticBooleanMethod(
        g_copyCancellationClass, g_copyIsCancelledMethod, static_cast<jint>(opId));
    if (env->ExceptionCheck()) { env->ExceptionClear(); return false; }
    return cancelled == JNI_TRUE;
}

void reportImportChunkProgress(int opId, uint64_t bytesDelta) {
    if (opId <= 0 || bytesDelta == 0) return;
    JNIEnv* env = g_threadJniEnv.get();
    if (!env || !g_importProgressBridgeClass || !g_importChunkReportMethod) return;
    env->CallStaticVoidMethod(
        g_importProgressBridgeClass, g_importChunkReportMethod,
        static_cast<jint>(opId), static_cast<jlong>(bytesDelta));
    if (env->ExceptionCheck()) env->ExceptionClear();
}

bool isImportCancelled(int opId) {
    if (opId <= 0) return false;
    JNIEnv* env = g_threadJniEnv.get();
    if (!env || !g_importCancellationClass || !g_importIsCancelledMethod) return false;
    jboolean cancelled = env->CallStaticBooleanMethod(
        g_importCancellationClass, g_importIsCancelledMethod, static_cast<jint>(opId));
    if (env->ExceptionCheck()) { env->ExceptionClear(); return false; }
    return cancelled == JNI_TRUE;
}

void yieldContainerWriteLock(int volId) {
    if (volId < 0) return;
    JNIEnv* env = g_threadJniEnv.get();
    if (!env || !g_containerSessionRegistryClass || !g_yieldWriteLockBrieflyMethod) return;
    env->CallStaticVoidMethod(
        g_containerSessionRegistryClass, g_yieldWriteLockBrieflyMethod, static_cast<jint>(volId));
    if (env->ExceptionCheck()) env->ExceptionClear();
}

void yieldContainerCopyLocks(int srcVolId, int destVolId) {
    if (destVolId < 0) return;
    JNIEnv* env = g_threadJniEnv.get();
    if (!env || !g_containerSessionRegistryClass || !g_yieldCopyLocksBrieflyMethod) return;
    env->CallStaticVoidMethod(
        g_containerSessionRegistryClass, g_yieldCopyLocksBrieflyMethod,
        static_cast<jint>(srcVolId), static_cast<jint>(destVolId));
    if (env->ExceptionCheck()) env->ExceptionClear();
}

void notifyHiddenVolumeProtectionTriggered(int volId) {
    if (volId < 0) return;
    JNIEnv* env = g_threadJniEnv.get();
    if (!env) return;
    if (!g_hiddenVolumeProtectionBridgeClass || !g_hiddenVolumeProtectionTriggeredMethod) return;
    env->CallStaticVoidMethod(
        g_hiddenVolumeProtectionBridgeClass, g_hiddenVolumeProtectionTriggeredMethod,
        static_cast<jint>(volId));
    if (env->ExceptionCheck()) env->ExceptionClear();
}

bool usbReadSectors(int volId, uint64_t startSector, uint32_t sectorCount,
                    unsigned char* outBuf) {
    JNIEnv* env = g_threadJniEnv.get();
    if (!env) return false;
    jbyteArray result = static_cast<jbyteArray>(env->CallStaticObjectMethod(
        g_usbBridgeClass, g_usbReadMethod,
        static_cast<jint>(volId), static_cast<jlong>(startSector), static_cast<jint>(sectorCount)));
    if (env->ExceptionCheck()) { env->ExceptionClear(); return false; }
    if (!result) return false;
    const jsize len = env->GetArrayLength(result);
    const size_t expected = static_cast<size_t>(sectorCount) * 512;
    if (static_cast<size_t>(len) != expected) { env->DeleteLocalRef(result); return false; }
    env->GetByteArrayRegion(result, 0, len, reinterpret_cast<jbyte*>(outBuf));
    env->DeleteLocalRef(result);
    return true;
}

bool usbWriteSectors(int volId, uint64_t startSector, uint32_t sectorCount,
                     const unsigned char* inBuf) {
    JNIEnv* env = g_threadJniEnv.get();
    if (!env) return false;
    const jsize len = static_cast<jsize>(static_cast<size_t>(sectorCount) * 512);
    jbyteArray data = env->NewByteArray(len);
    if (!data) return false;
    env->SetByteArrayRegion(data, 0, len, reinterpret_cast<const jbyte*>(inBuf));
    const jboolean ok = env->CallStaticBooleanMethod(
        g_usbBridgeClass, g_usbWriteMethod,
        static_cast<jint>(volId), static_cast<jlong>(startSector), static_cast<jint>(sectorCount), data);
    env->DeleteLocalRef(data);
    if (env->ExceptionCheck()) { env->ExceptionClear(); return false; }
    return ok == JNI_TRUE;
}