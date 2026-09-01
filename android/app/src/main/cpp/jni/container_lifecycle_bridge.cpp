// JNI bridge: container lifecycle -- creating new VeraCrypt/LUKS containers
// (file-backed and USB-backed, plain and hidden-volume variants) and
// changing an existing container's password. See crypto_bridge.cpp's header
// comment for why splitting vaultexplorer.cpp this way doesn't require any
// Kotlin/Dart changes.

#include <jni.h>
#include <vector>

#include "container_create.h"
#include "crypto/keyfile_mixing.h"

#include "jni_bridge_common.h"

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_createContainerNative(
        JNIEnv* env, jobject,
        jint fd, jstring password, jint pim, jlong sizeBytes, jstring fileSystem,
        jint containerFormat, jint cipherId, jint hashId, jintArray keyfileFds,
        jboolean quickFormat) {
    JNI_TRY


    std::vector<int> kfFds = extractKeyfileFds(env, keyfileFds);
    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    const char* nativeFS   = env->GetStringUTFChars(fileSystem, nullptr);

    bool success;
    if (containerFormat == 1 || containerFormat == 2) {
        // 1 = LUKS1, 2 = LUKS2 — see ContainerFormat (container_format.h).
        success = createLuksContainer(fd, nativePass, pim, static_cast<int64_t>(sizeBytes),
                                      nativeFS, containerFormat, cipherId, hashId,
                                      kfFds.empty() ? nullptr : kfFds.data(),
                                      static_cast<int>(kfFds.size()),
                                      quickFormat);
    } else {
        success = createContainer(fd, nativePass, pim, static_cast<int64_t>(sizeBytes),
                                  nativeFS, cipherId, hashId,
                                  kfFds.empty() ? nullptr : kfFds.data(),
                                  static_cast<int>(kfFds.size()),
                                  quickFormat);
    }

    env->ReleaseStringUTFChars(password, nativePass);
    env->ReleaseStringUTFChars(fileSystem, nativeFS);

    return success ? JNI_TRUE : JNI_FALSE;

    JNI_CATCH_RETURN(JNI_FALSE)
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_createContainerWithHiddenNative(
        JNIEnv* env, jobject,
        jint fd, jstring outerPassword, jstring hiddenPassword,
        jint outerPim, jint hiddenPim, jlong sizeBytes, jstring outerFileSystem, jstring hiddenFileSystem,
        jlong hiddenSizeBytes,
        jint outerCipherId, jint outerHashId,
        jint hiddenCipherId, jint hiddenHashId,
        jintArray outerKeyfileFds, jintArray hiddenKeyfileFds,
        jboolean quickFormat) {
    JNI_TRY


    std::vector<int> outerKfFds = extractKeyfileFds(env, outerKeyfileFds);
    std::vector<int> hiddenKfFds = extractKeyfileFds(env, hiddenKeyfileFds);
    
    const char* nativeOuterPass = env->GetStringUTFChars(outerPassword, nullptr);
    const char* nativeHiddenPass = env->GetStringUTFChars(hiddenPassword, nullptr);
    const char* nativeOuterFS   = env->GetStringUTFChars(outerFileSystem, nullptr);
    const char* nativeHiddenFS   = env->GetStringUTFChars(hiddenFileSystem, nullptr);

    bool success = createContainerWithHidden(fd, nativeOuterPass, nativeHiddenPass, outerPim, hiddenPim, static_cast<int64_t>(sizeBytes),
                                             nativeOuterFS, nativeHiddenFS, static_cast<int64_t>(hiddenSizeBytes),
                                             outerCipherId, outerHashId,
                                             hiddenCipherId, hiddenHashId,
                                             outerKfFds.empty() ? nullptr : outerKfFds.data(), static_cast<int>(outerKfFds.size()),
                                             hiddenKfFds.empty() ? nullptr : hiddenKfFds.data(), static_cast<int>(hiddenKfFds.size()),
                                             quickFormat);

    env->ReleaseStringUTFChars(outerPassword, nativeOuterPass);
    env->ReleaseStringUTFChars(hiddenPassword, nativeHiddenPass);
    env->ReleaseStringUTFChars(outerFileSystem, nativeOuterFS);
    env->ReleaseStringUTFChars(hiddenFileSystem, nativeHiddenFS);

    return success ? JNI_TRUE : JNI_FALSE;

    JNI_CATCH_RETURN(JNI_FALSE)
}

#include "partition_writer.h"

// Builds a Map<String, Any?> from a UsbCreateResult, following the same
// HashMap-construction pattern as getVaultInfo (filesystem_bridge.cpp).
// Used by both createUsbContainerNative and createUsbContainerWithHiddenNative
// below -- kept `static` in this file rather than in jni_bridge_common.h per
// that header's own stated policy (shared across files goes there; shared
// within one file stays local).
//
// Keys: "success" (Boolean), "phase" (String), "errorCode" (String, only
// when !success), "errorMessage" (String, only when !success),
// "offsetBytes"/"sector" (Long, only when !success), "sectorCount" (Integer,
// only when !success). NativeEngine.createUsbContainerNative's doc comment
// documents this shape for the Kotlin side.
static jobject buildUsbCreateResultMap(JNIEnv* env, const UsbCreateResult& r) {
    jclass mapClass = env->FindClass("java/util/HashMap");
    jmethodID mapInit = env->GetMethodID(mapClass, "<init>", "()V");
    jmethodID mapPut = env->GetMethodID(mapClass, "put",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
    jobject result = env->NewObject(mapClass, mapInit);

    jclass boolClass = env->FindClass("java/lang/Boolean");
    jmethodID boolInit = env->GetMethodID(boolClass, "<init>", "(Z)V");
    jclass longClass = env->FindClass("java/lang/Long");
    jmethodID longInit = env->GetMethodID(longClass, "<init>", "(J)V");
    jclass intClass = env->FindClass("java/lang/Integer");
    jmethodID intInit = env->GetMethodID(intClass, "<init>", "(I)V");

    auto putBool = [&](const char* key, bool value) {
        jstring k = env->NewStringUTF(key);
        jobject boxed = env->NewObject(boolClass, boolInit, static_cast<jboolean>(value));
        env->CallObjectMethod(result, mapPut, k, boxed);
        env->DeleteLocalRef(k);
        env->DeleteLocalRef(boxed);
    };
    auto putLong = [&](const char* key, int64_t value) {
        jstring k = env->NewStringUTF(key);
        jobject boxed = env->NewObject(longClass, longInit, static_cast<jlong>(value));
        env->CallObjectMethod(result, mapPut, k, boxed);
        env->DeleteLocalRef(k);
        env->DeleteLocalRef(boxed);
    };
    auto putInt = [&](const char* key, int value) {
        jstring k = env->NewStringUTF(key);
        jobject boxed = env->NewObject(intClass, intInit, static_cast<jint>(value));
        env->CallObjectMethod(result, mapPut, k, boxed);
        env->DeleteLocalRef(k);
        env->DeleteLocalRef(boxed);
    };
    auto putString = [&](const char* key, const std::string& value) {
        jstring k = env->NewStringUTF(key);
        jstring v = env->NewStringUTF(value.c_str());
        env->CallObjectMethod(result, mapPut, k, v);
        env->DeleteLocalRef(k);
        env->DeleteLocalRef(v);
    };

    putBool("success", r.success);
    putString("phase", usbCreatePhaseName(r.phase));
    if (!r.success) {
        putString("errorCode", r.errorCode);
        putString("errorMessage", r.errorMessage);
        putLong("offsetBytes", static_cast<int64_t>(r.offsetBytes));
        putLong("sector", static_cast<int64_t>(r.sector));
        putInt("sectorCount", static_cast<int>(r.sectorCount));
    }
    return result;
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_createUsbContainerNative(
        JNIEnv* env, jobject,
        jint volId, jstring partitionScheme, jstring password, jint pim, jlong sizeBytes, jstring fileSystem,
        jint containerFormat, jint cipherId, jint hashId, jintArray keyfileFds, jboolean quickFormat,
        jlong deviceSectorCount, jstring operationId) {
    JNI_TRY

    if (volId < 0 || volId >= MAX_VOLUMES) {
        return buildUsbCreateResultMap(env, UsbCreateResult::Fail(
            UsbCreatePhase::kValidate, "USB_INVALID_VOLUME_ID", "Invalid internal volume id"));
    }

    std::vector<int> kfFds = extractKeyfileFds(env, keyfileFds);
    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    const char* nativeFS   = env->GetStringUTFChars(fileSystem, nullptr);
    const char* nativeOpId = operationId ? env->GetStringUTFChars(operationId, nullptr) : nullptr;

    static constexpr uint64_t kUsbPartitionStartSector = 2048;
    const uint64_t numSectors = static_cast<uint64_t>(sizeBytes) / 512;

    LOGI("[%s] createUsbContainerNative: volId=%d sizeBytes=%lld fs=%s format=%d numSectors=%llu deviceSectorCount=%lld",
         nativeOpId ? nativeOpId : "-", volId, (long long)sizeBytes, nativeFS, containerFormat,
         (unsigned long long)numSectors, (long long)deviceSectorCount);

    UsbCreateResult mbrResult = writeMbrPartitionTable(volId, kUsbPartitionStartSector, numSectors,
                                                        static_cast<uint64_t>(deviceSectorCount));
    LOGI("[%s] createUsbContainerNative: writeMbrPartitionTable success=%d errorCode=%s",
         nativeOpId ? nativeOpId : "-", mbrResult.success ? 1 : 0, mbrResult.errorCode.c_str());

    UsbCreateResult createResult;
    if (mbrResult.success) {
        createResult = (containerFormat == 1 || containerFormat == 2)
            ? createUsbLuksContainer(volId, kUsbPartitionStartSector, nativePass, pim,
                                     static_cast<int64_t>(sizeBytes), nativeFS,
                                     containerFormat, cipherId, hashId,
                                     kfFds.empty() ? nullptr : kfFds.data(), static_cast<int>(kfFds.size()), quickFormat,
                                     nativeOpId)
            : createUsbContainer(volId, kUsbPartitionStartSector, nativePass, pim,
                                 static_cast<int64_t>(sizeBytes), nativeFS,
                                 cipherId, hashId,
                                 kfFds.empty() ? nullptr : kfFds.data(), static_cast<int>(kfFds.size()), quickFormat,
                                 nativeOpId);
    } else {
        closeUnusedKeyfileFds(kfFds.empty() ? nullptr : kfFds.data(), static_cast<int>(kfFds.size()));
        createResult = mbrResult;
    }

    LOGI("[%s] createUsbContainerNative: EXIT success=%d phase=%s",
         nativeOpId ? nativeOpId : "-", createResult.success ? 1 : 0, usbCreatePhaseName(createResult.phase));
    env->ReleaseStringUTFChars(password, nativePass);
    env->ReleaseStringUTFChars(fileSystem, nativeFS);
    if (operationId && nativeOpId) env->ReleaseStringUTFChars(operationId, nativeOpId);
    return buildUsbCreateResultMap(env, createResult);

    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_createUsbContainerWithHiddenNative(
        JNIEnv* env, jobject,
        jint volId, jstring partitionScheme,
        jstring outerPassword, jstring hiddenPassword,
        jint outerPim, jint hiddenPim, jlong sizeBytes,
        jstring outerFileSystem, jstring hiddenFileSystem, jlong hiddenSizeBytes,
        jint outerCipherId, jint outerHashId, jint hiddenCipherId, jint hiddenHashId,
        jintArray outerKeyfileFds, jintArray hiddenKeyfileFds, jboolean quickFormat,
        jlong deviceSectorCount, jstring operationId) {
    JNI_TRY

    if (volId < 0 || volId >= MAX_VOLUMES) {
        return buildUsbCreateResultMap(env, UsbCreateResult::Fail(
            UsbCreatePhase::kValidate, "USB_INVALID_VOLUME_ID", "Invalid internal volume id"));
    }

    std::vector<int> outerKfFds = extractKeyfileFds(env, outerKeyfileFds);
    std::vector<int> hiddenKfFds = extractKeyfileFds(env, hiddenKeyfileFds);
    
    const char* nativeOuterPass = env->GetStringUTFChars(outerPassword, nullptr);
    const char* nativeHiddenPass = env->GetStringUTFChars(hiddenPassword, nullptr);
    const char* nativeOuterFS   = env->GetStringUTFChars(outerFileSystem, nullptr);
    const char* nativeHiddenFS   = env->GetStringUTFChars(hiddenFileSystem, nullptr);
    const char* nativeOpId = operationId ? env->GetStringUTFChars(operationId, nullptr) : nullptr;

    static constexpr uint64_t kUsbPartitionStartSector = 2048;
    const uint64_t numSectors = static_cast<uint64_t>(sizeBytes) / 512;

    UsbCreateResult mbrResult = writeMbrPartitionTable(volId, kUsbPartitionStartSector, numSectors,
                                                        static_cast<uint64_t>(deviceSectorCount));

    UsbCreateResult createResult;
    if (mbrResult.success) {
        createResult = createUsbContainerWithHidden(
            volId, kUsbPartitionStartSector,
            nativeOuterPass, nativeHiddenPass, outerPim, hiddenPim, static_cast<int64_t>(sizeBytes),
            nativeOuterFS, nativeHiddenFS, static_cast<int64_t>(hiddenSizeBytes),
            outerCipherId, outerHashId, hiddenCipherId, hiddenHashId,
            outerKfFds.empty() ? nullptr : outerKfFds.data(), static_cast<int>(outerKfFds.size()),
            hiddenKfFds.empty() ? nullptr : hiddenKfFds.data(), static_cast<int>(hiddenKfFds.size()),
            quickFormat, nativeOpId
        );
    } else {
        closeUnusedKeyfileFds(outerKfFds.empty() ? nullptr : outerKfFds.data(), static_cast<int>(outerKfFds.size()));
        closeUnusedKeyfileFds(hiddenKfFds.empty() ? nullptr : hiddenKfFds.data(), static_cast<int>(hiddenKfFds.size()));
        createResult = mbrResult;
    }

    env->ReleaseStringUTFChars(outerPassword, nativeOuterPass);
    env->ReleaseStringUTFChars(hiddenPassword, nativeHiddenPass);
    env->ReleaseStringUTFChars(outerFileSystem, nativeOuterFS);
    env->ReleaseStringUTFChars(hiddenFileSystem, nativeHiddenFS);
    if (operationId && nativeOpId) env->ReleaseStringUTFChars(operationId, nativeOpId);
    return buildUsbCreateResultMap(env, createResult);

    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_changeContainerPasswordNative(
        JNIEnv* env, jobject,
        jint fd, jstring oldPassword, jstring newPassword,
        jint oldPim, jint newPim,
        jint cipherId, jint hashId, jintArray oldKeyfileFds, jintArray newKeyfileFds) {
    JNI_TRY


    std::vector<int> oldKfFds = extractKeyfileFds(env, oldKeyfileFds);
    std::vector<int> newKfFds = extractKeyfileFds(env, newKeyfileFds);
    
    const char* nativeOldPass = env->GetStringUTFChars(oldPassword, nullptr);
    const char* nativeNewPass = env->GetStringUTFChars(newPassword, nullptr);

    bool success = changeContainerPassword(fd, nativeOldPass, nativeNewPass, oldPim, newPim,
                                           cipherId, hashId,
                                           oldKfFds.empty() ? nullptr : oldKfFds.data(), static_cast<int>(oldKfFds.size()),
                                           newKfFds.empty() ? nullptr : newKfFds.data(), static_cast<int>(newKfFds.size()));

    env->ReleaseStringUTFChars(oldPassword, nativeOldPass);
    env->ReleaseStringUTFChars(newPassword, nativeNewPass);

    return success ? JNI_TRUE : JNI_FALSE;

    JNI_CATCH_RETURN(JNI_FALSE)
}

// Returns changeLuksContainerPassword()'s tri-state int directly (0 =
// success, 1 = wrong old password/keyfile, 2 = any other error) rather
// than collapsing to a jboolean like changeContainerPasswordNative above
// — LUKS's Kotlin caller needs to tell "wrong password" apart from "I/O
// or format error" to report AUTH_FAIL vs INVALID_VAULT, matching the
// folder-vault (Cryptomator/gocryptfs/CryFS) change-password handlers.
extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_changeLuksContainerPasswordNative(
        JNIEnv* env, jobject,
        jint fd, jstring oldPassword, jstring newPassword,
        jintArray oldKeyfileFds, jintArray newKeyfileFds) {
    JNI_TRY

    std::vector<int> oldKfFds = extractKeyfileFds(env, oldKeyfileFds);
    std::vector<int> newKfFds = extractKeyfileFds(env, newKeyfileFds);

    const char* nativeOldPass = env->GetStringUTFChars(oldPassword, nullptr);
    const char* nativeNewPass = env->GetStringUTFChars(newPassword, nullptr);

    int result = changeLuksContainerPassword(fd, nativeOldPass, nativeNewPass,
                                             oldKfFds.empty() ? nullptr : oldKfFds.data(), static_cast<int>(oldKfFds.size()),
                                             newKfFds.empty() ? nullptr : newKfFds.data(), static_cast<int>(newKfFds.size()));

    env->ReleaseStringUTFChars(oldPassword, nativeOldPass);
    env->ReleaseStringUTFChars(newPassword, nativeNewPass);

    return result;

    JNI_CATCH_RETURN(2)
}
