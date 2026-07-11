#include "jni_callbacks.h"

namespace {

struct ScopedJniEnv {
    JNIEnv* env = nullptr;
    bool attached = false;

    ScopedJniEnv() {
        if (!g_vm) return;
        if (g_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK) return;
        if (g_vm->AttachCurrentThread(&env, nullptr) == JNI_OK) attached = true;
        else env = nullptr;
    }

    ~ScopedJniEnv() {
        if (attached) g_vm->DetachCurrentThread();
    }
};

} // namespace

void reportUnlockProgress(int volId, int attempted, int total, int hashId,
                          int cipherId, int format) {
    if (volId < 0) return;
    ScopedJniEnv scope;
    if (!scope.env) return;
    scope.env->CallStaticVoidMethod(
        g_progressBridgeClass, g_progressReportMethod,
        static_cast<jint>(volId), static_cast<jint>(attempted), static_cast<jint>(total),
        static_cast<jint>(hashId), static_cast<jint>(cipherId), static_cast<jint>(format));
    if (scope.env->ExceptionCheck()) scope.env->ExceptionClear();
}

bool usbReadSectors(int volId, uint64_t startSector, uint32_t sectorCount,
                    unsigned char* outBuf) {
    ScopedJniEnv scope;
    if (!scope.env) return false;
    JNIEnv* env = scope.env;
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
    ScopedJniEnv scope;
    if (!scope.env) return false;
    JNIEnv* env = scope.env;
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
