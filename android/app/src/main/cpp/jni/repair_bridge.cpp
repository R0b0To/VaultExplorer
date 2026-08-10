// JNI bridge: Check & Repair tool (see containers/container_repair.cpp for
// the actual diagnosis/restore/check logic). Kept as its own bridge file
// alongside session_bridge.cpp/container_lifecycle_bridge.cpp/etc, per the
// vaultexplorer.cpp split described in jni_bridge_common.h.

#include <cstring>
#include <jni.h>

#include "containers/container_repair.h"

#include "jni_bridge_common.h"

// Packs {diagnosis code, format ordinal (-1 if unrecognized)} for the
// unmounted-file case -- a small jintArray is simpler on the Kotlin side
// than inventing a parcelable result type for two ints.
extern "C" JNIEXPORT jintArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_nativeDiagnoseContainerFile(
        JNIEnv* env, jobject, jint fd) {
    JNI_TRY

    ContainerFormat format = ContainerFormat::kVeraCrypt;
    bool formatKnown = false;
    RepairDiagnosisCode code = diagnoseUnmountedContainerFile(fd, format, formatKnown);

    jint packed[2] = {
        static_cast<jint>(code),
        formatKnown ? static_cast<jint>(format) : -1,
    };
    jintArray result = env->NewIntArray(2);
    if (result != nullptr) {
        env->SetIntArrayRegion(result, 0, 2, packed);
    }
    return result;

    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_nativeRestoreLuks2BackupHeaderFile(
        JNIEnv* env, jobject, jint fd) {
    JNI_TRY

    return restoreLuks2BackupHeaderUnmounted(fd) ? JNI_TRUE : JNI_FALSE;

    JNI_CATCH_RETURN(JNI_FALSE)
}

// Returns a VeraCryptRestoreResult ordinal (0=success, 1=wrong password,
// 2=already healthy, 3=I/O error) rather than a bool -- RepairHandlers.kt
// maps this to a specific MethodChannel error code so the Dart layer (and,
// through it, the wizard UI) can tell these apart instead of collapsing
// them all into one generic failure.
extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_nativeRestoreVeraCryptBackupHeaderFile(
        JNIEnv* env, jobject, jint fd, jstring password, jint pim, jint cipherId, jint hashId) {
    JNI_TRY

    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    const size_t passLen = std::strlen(nativePass);

    VeraCryptRestoreResult result = restoreVeraCryptBackupHeaderUnmounted(
            fd, reinterpret_cast<const uint8_t*>(nativePass), passLen, pim, cipherId, hashId);

    env->ReleaseStringUTFChars(password, nativePass);
    return static_cast<jint>(result);

    JNI_CATCH_RETURN(static_cast<jint>(VeraCryptRestoreResult::kIoError))
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_nativeDiagnoseMountedVolumeFilesystem(
        JNIEnv* env, jobject, jint volId) {
    JNI_TRY

    return static_cast<jint>(diagnoseMountedVolumeFilesystem(volId));

    JNI_CATCH_RETURN(static_cast<jint>(RepairDiagnosisCode::kHealthy))
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_nativeRunMountedVolumeFilesystemCheck(
        JNIEnv* env, jobject, jint volId) {
    JNI_TRY

    return runMountedVolumeFilesystemCheck(volId) ? JNI_TRUE : JNI_FALSE;

    JNI_CATCH_RETURN(JNI_FALSE)
}