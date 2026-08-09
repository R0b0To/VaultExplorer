#include "jni_callbacks.h"
#include "crypto/thread_pool.h"
#include <android/log.h>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

// Process-lifetime JNI cache.  Filesystem and crypto code only consume these
// handles; registration, lookup and global-reference ownership remain here.
JavaVM*   g_vm = nullptr;
jclass    g_usbBridgeClass = nullptr;
jmethodID g_usbReadMethod = nullptr;
jmethodID g_usbWriteMethod = nullptr;
jclass    g_progressBridgeClass = nullptr;
jmethodID g_progressReportMethod = nullptr;
jclass    g_hiddenVolumeProtectionBridgeClass = nullptr;
jmethodID g_hiddenVolumeProtectionTriggeredMethod = nullptr;
jclass    g_illegalStateExceptionClass = nullptr;
jclass    g_unlockCancelledExceptionClass = nullptr;
jclass    g_cloudChunkBridgeClass = nullptr;
jmethodID g_cloudChunkReadMethod = nullptr;
jmethodID g_cloudChunkWriteMethod = nullptr;

extern "C" int av_jni_set_java_vm(void *vm, void *log_ctx);

extern "C" jint JNI_OnLoad(JavaVM* vm, void*) {
    g_vm = vm;
    JNIEnv* env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;

    jclass usbLocal = env->FindClass("com/aeidolon/vaultexplorer/UsbBlockBridge");
    if (!usbLocal) {
        LOGI("JNI_OnLoad: UsbBlockBridge class not found");
        return JNI_ERR;
    }
    g_usbBridgeClass = static_cast<jclass>(env->NewGlobalRef(usbLocal));
    env->DeleteLocalRef(usbLocal);
    g_usbReadMethod = env->GetStaticMethodID(g_usbBridgeClass, "readSectors", "(IJI)[B");
    g_usbWriteMethod = env->GetStaticMethodID(g_usbBridgeClass, "writeSectors", "(IJI[B)Z");
    if (!g_usbReadMethod || !g_usbWriteMethod) {
        LOGI("JNI_OnLoad: UsbBlockBridge methods not found");
        return JNI_ERR;
    }

    jclass progressLocal = env->FindClass("com/aeidolon/vaultexplorer/UnlockProgressBridge");
    if (!progressLocal) {
        LOGI("JNI_OnLoad: UnlockProgressBridge class not found");
        return JNI_ERR;
    }
    g_progressBridgeClass = static_cast<jclass>(env->NewGlobalRef(progressLocal));
    env->DeleteLocalRef(progressLocal);
    
    // Updated signature to take 7 integers (including slotId)
    g_progressReportMethod = env->GetStaticMethodID(
        g_progressBridgeClass, "reportProgress", "(IIIIIII)V");
    if (!g_progressReportMethod) {
        LOGI("JNI_OnLoad: UnlockProgressBridge.reportProgress not found");
        return JNI_ERR;
    }

    jclass hiddenProtectionLocal = env->FindClass("com/aeidolon/vaultexplorer/HiddenVolumeProtectionBridge");
    if (!hiddenProtectionLocal) {
        LOGI("JNI_OnLoad: HiddenVolumeProtectionBridge class not found");
        return JNI_ERR;
    }
    g_hiddenVolumeProtectionBridgeClass = static_cast<jclass>(env->NewGlobalRef(hiddenProtectionLocal));
    env->DeleteLocalRef(hiddenProtectionLocal);

    g_hiddenVolumeProtectionTriggeredMethod = env->GetStaticMethodID(
        g_hiddenVolumeProtectionBridgeClass, "reportTriggered", "(I)V");
    if (!g_hiddenVolumeProtectionTriggeredMethod) {
        LOGI("JNI_OnLoad: HiddenVolumeProtectionBridge.reportTriggered not found");
        return JNI_ERR;
    }

    jclass iseLocal = env->FindClass("java/lang/IllegalStateException");
    if (!iseLocal) {
        LOGI("JNI_OnLoad: IllegalStateException class not found");
        return JNI_ERR;
    }
    g_illegalStateExceptionClass = static_cast<jclass>(env->NewGlobalRef(iseLocal));
    env->DeleteLocalRef(iseLocal);

    jclass uceLocal = env->FindClass("com/aeidolon/vaultexplorer/UnlockCancelledException");
    if (!uceLocal) {
        LOGI("JNI_OnLoad: UnlockCancelledException class not found");
        return JNI_ERR;
    }
    g_unlockCancelledExceptionClass = static_cast<jclass>(env->NewGlobalRef(uceLocal));
    env->DeleteLocalRef(uceLocal);

    // CloudChunkBridge lives in VaultExplorer's own APK (not the
    // VaultSync Bridge plugin's), same as UsbBlockBridge above — its
    // absence would be a packaging bug, not a "plugin not installed"
    // condition, so this fails JNI_OnLoad exactly like the USB lookup
    // does rather than degrading gracefully.
    jclass cloudChunkLocal = env->FindClass("com/aeidolon/vaultexplorer/CloudChunkBridge");
    if (!cloudChunkLocal) {
        LOGI("JNI_OnLoad: CloudChunkBridge class not found");
        return JNI_ERR;
    }
    g_cloudChunkBridgeClass = static_cast<jclass>(env->NewGlobalRef(cloudChunkLocal));
    env->DeleteLocalRef(cloudChunkLocal);
    g_cloudChunkReadMethod = env->GetStaticMethodID(g_cloudChunkBridgeClass, "readChunk", "(IJ)[B");
    g_cloudChunkWriteMethod = env->GetStaticMethodID(g_cloudChunkBridgeClass, "writeChunkRange", "(IJI[B)Z");
    if (!g_cloudChunkReadMethod || !g_cloudChunkWriteMethod) {
        LOGI("JNI_OnLoad: CloudChunkBridge methods not found");
        return JNI_ERR;
    }

    ThreadPool::getInstance();

    return JNI_VERSION_1_6;
}

extern "C" void JNI_OnUnload(JavaVM* vm, void*) {
    JNIEnv* env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK) {
        if (g_usbBridgeClass) env->DeleteGlobalRef(g_usbBridgeClass);
        if (g_progressBridgeClass) env->DeleteGlobalRef(g_progressBridgeClass);
        if (g_hiddenVolumeProtectionBridgeClass) env->DeleteGlobalRef(g_hiddenVolumeProtectionBridgeClass);
        if (g_illegalStateExceptionClass) env->DeleteGlobalRef(g_illegalStateExceptionClass);
        if (g_unlockCancelledExceptionClass) env->DeleteGlobalRef(g_unlockCancelledExceptionClass);
        if (g_cloudChunkBridgeClass) env->DeleteGlobalRef(g_cloudChunkBridgeClass);
    }
    g_usbBridgeClass = nullptr;
    g_usbReadMethod = nullptr;
    g_usbWriteMethod = nullptr;
    g_progressBridgeClass = nullptr;
    g_progressReportMethod = nullptr;
    g_hiddenVolumeProtectionBridgeClass = nullptr;
    g_hiddenVolumeProtectionTriggeredMethod = nullptr;
    g_illegalStateExceptionClass = nullptr;
    g_unlockCancelledExceptionClass = nullptr;
    g_cloudChunkBridgeClass = nullptr;
    g_cloudChunkReadMethod = nullptr;
    g_cloudChunkWriteMethod = nullptr;
    g_vm = nullptr;
}