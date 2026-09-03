// JNI bridge: Check & Repair tool (see containers/container_repair.cpp for
// the actual diagnosis/restore/check logic). Kept as its own bridge file
// alongside session_bridge.cpp/container_lifecycle_bridge.cpp/etc, per the
// vaultexplorer.cpp split described in jni_bridge_common.h.

#include <cstring>
#include <jni.h>
#include <vector>

#include "containers/container_repair.h"

#include "jni_bridge_common.h"

// Packs {diagnosis code, format ordinal (-1 if unrecognized)} for the
// unmounted-file case -- a small jintArray is simpler on the Kotlin side
// than inventing a parcelable result type for two ints.
extern "C" JNIEXPORT jintArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_nativeDiagnoseContainerFile(
        JNIEnv* env, jobject, jint fd, jint opId) {
    JNI_TRY

    ContainerFormat format = ContainerFormat::kVeraCrypt;
    bool formatKnown = false;
    RepairDiagnosisCode code = diagnoseUnmountedContainerFile(fd, format, formatKnown, opId);

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
        JNIEnv* env, jobject, jint fd, jint opId) {
    JNI_TRY

    return restoreLuks2BackupHeaderUnmounted(fd, opId) ? JNI_TRUE : JNI_FALSE;

    JNI_CATCH_RETURN(JNI_FALSE)
}

// Returns a VeraCryptRestoreResult ordinal (0=success, 1=wrong password,
// 2=already healthy, 3=I/O error) rather than a bool -- RepairHandlers.kt
// maps this to a specific MethodChannel error code so the Dart layer (and,
// through it, the wizard UI) can tell these apart instead of collapsing
// them all into one generic failure.
extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_nativeRestoreVeraCryptBackupHeaderFile(
        JNIEnv* env, jobject, jint fd, jstring password, jint pim, jint cipherId, jint hashId, jint opId) {
    JNI_TRY

    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    const size_t passLen = std::strlen(nativePass);

    VeraCryptRestoreResult result = restoreVeraCryptBackupHeaderUnmounted(
            fd, reinterpret_cast<const uint8_t*>(nativePass), passLen, pim, cipherId, hashId, opId);

    env->ReleaseStringUTFChars(password, nativePass);
    return static_cast<jint>(result);

    JNI_CATCH_RETURN(static_cast<jint>(VeraCryptRestoreResult::kIoError))
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_nativeDiagnoseMountedVolumeFilesystem(
        JNIEnv* env, jobject, jint volId, jint opId) {
    JNI_TRY

    return static_cast<jint>(diagnoseMountedVolumeFilesystem(volId, opId));

    JNI_CATCH_RETURN(static_cast<jint>(RepairDiagnosisCode::kHealthy))
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_nativeRunMountedVolumeFilesystemCheck(
        JNIEnv* env, jobject, jint volId, jint opId) {
    JNI_TRY

    return runMountedVolumeFilesystemCheck(volId, opId) ? JNI_TRUE : JNI_FALSE;

    JNI_CATCH_RETURN(JNI_FALSE)
}

// ── Header Backup / Restore (Header Exporter tool) ──────────────────────
// See container_repair.h's "Header Backup / Restore" section for what
// these actually do; this bridge just packs/unpacks the result shapes.

// Packs {result code, format ordinal (0xFF if unrecognized/I-O-error),
// region length (8 bytes, big-endian), payload bytes...} into one
// jbyteArray -- simpler on this side than building a JNI HashMap for three
// small fields plus a variable-length payload. Mirrors the
// std::vector<uint8_t>-to-jbyteArray convention crypto_bridge.cpp's
// cryfsEncryptBlockNative already uses. HeaderBackupHandlers.kt unpacks
// it: byte[0]=result code, byte[1]=format ordinal, bytes[2..9]=region
// length, bytes[10..]=payload.
extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_nativeExportContainerHeader(
        JNIEnv* env, jobject, jint fd, jint opId) {
    JNI_TRY

    ContainerFormat format = ContainerFormat::kVeraCrypt;
    std::vector<uint8_t> payload;
    HeaderExportResult result = exportContainerHeaderRegion(fd, format, payload, opId);

    const bool formatMeaningful = result != HeaderExportResult::kUnrecognizedFile &&
                                   result != HeaderExportResult::kIoError;
    std::vector<uint8_t> packed(10);
    packed[0] = static_cast<uint8_t>(result);
    packed[1] = formatMeaningful ? static_cast<uint8_t>(format) : 0xFFu;
    const uint64_t regionLength = payload.size();
    for (int i = 0; i < 8; i++) {
        packed[2 + i] = static_cast<uint8_t>(regionLength >> (56 - 8 * i));
    }
    packed.insert(packed.end(), payload.begin(), payload.end());

    jbyteArray out = env->NewByteArray(static_cast<jsize>(packed.size()));
    if (out != nullptr) {
        env->SetByteArrayRegion(out, 0, static_cast<jsize>(packed.size()),
                                 reinterpret_cast<const jbyte*>(packed.data()));
    }
    return out;

    JNI_CATCH_RETURN(nullptr)
}

// Returns a HeaderRestoreResult ordinal (0=success, 1=wrong password,
// 2=backup invalid, 3=size mismatch, 4=I/O error). [password] may be null
// -- only the VeraCrypt path (formatOrdinal 0) ever consults it; Kotlin
// gates that case itself (mirrors nativeRestoreVeraCryptBackupHeaderFile's
// caller) but this stays null-safe regardless.
extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_nativeRestoreContainerHeaderRegion(
        JNIEnv* env, jobject, jint fd, jint formatOrdinal, jbyteArray payload,
        jstring password, jint pim, jint cipherId, jint hashId, jint opId) {
    JNI_TRY

    const jsize payloadLen = payload != nullptr ? env->GetArrayLength(payload) : 0;
    std::vector<uint8_t> payloadBuf(static_cast<size_t>(payloadLen));
    if (payloadLen > 0) {
        env->GetByteArrayRegion(payload, 0, payloadLen, reinterpret_cast<jbyte*>(payloadBuf.data()));
    }

    const char* nativePass = password != nullptr ? env->GetStringUTFChars(password, nullptr) : nullptr;
    const size_t passLen = nativePass != nullptr ? std::strlen(nativePass) : 0;

    HeaderRestoreResult result = restoreContainerHeaderRegion(
            fd, static_cast<ContainerFormat>(formatOrdinal), payloadBuf.data(), payloadBuf.size(),
            reinterpret_cast<const uint8_t*>(nativePass), passLen, pim, cipherId, hashId, opId);

    if (nativePass != nullptr) env->ReleaseStringUTFChars(password, nativePass);
    return static_cast<jint>(result);

    JNI_CATCH_RETURN(static_cast<jint>(HeaderRestoreResult::kIoError))
}