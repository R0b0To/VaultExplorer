#include "jni_callbacks.h"
#include "crypto/thread_pool.h"
#include <android/log.h>
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

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
jclass    g_splitJoinProgressBridgeClass = nullptr;
jmethodID g_splitJoinProgressReportMethod = nullptr;
jclass    g_splitJoinCancellationClass = nullptr;
jmethodID g_splitJoinIsCancelledMethod = nullptr;

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

    jclass sjProgressLocal = env->FindClass("com/aeidolon/vaultexplorer/SplitJoinProgressBridge");
    if (sjProgressLocal) {
        g_splitJoinProgressBridgeClass = static_cast<jclass>(env->NewGlobalRef(sjProgressLocal));
        env->DeleteLocalRef(sjProgressLocal);
        g_splitJoinProgressReportMethod = env->GetStaticMethodID(
            g_splitJoinProgressBridgeClass, "reportProgress", "(IJJ)V");
        if (env->ExceptionCheck()) env->ExceptionClear();
    }

    jclass sjCancelLocal = env->FindClass("com/aeidolon/vaultexplorer/SplitJoinCancellation");
    if (sjCancelLocal) {
        g_splitJoinCancellationClass = static_cast<jclass>(env->NewGlobalRef(sjCancelLocal));
        env->DeleteLocalRef(sjCancelLocal);
        g_splitJoinIsCancelledMethod = env->GetStaticMethodID(
            g_splitJoinCancellationClass, "isCancelled", "(I)Z");
        if (env->ExceptionCheck()) env->ExceptionClear();
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
        if (g_splitJoinProgressBridgeClass) env->DeleteGlobalRef(g_splitJoinProgressBridgeClass);
        if (g_splitJoinCancellationClass) env->DeleteGlobalRef(g_splitJoinCancellationClass);
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
    g_splitJoinProgressBridgeClass = nullptr;
    g_splitJoinProgressReportMethod = nullptr;
    g_splitJoinCancellationClass = nullptr;
    g_splitJoinIsCancelledMethod = nullptr;
    g_vm = nullptr;
}