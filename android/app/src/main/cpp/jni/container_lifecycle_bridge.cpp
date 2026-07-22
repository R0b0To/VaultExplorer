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
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_createContainerNative(
        JNIEnv* env, jobject,
        jint fd, jstring password, jint pim, jlong sizeBytes, jstring fileSystem,
        jint containerFormat, jint cipherId, jint hashId, jintArray keyfileFds) {

    std::vector<int> kfFds = extractKeyfileFds(env, keyfileFds);
    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    const char* nativeFS   = env->GetStringUTFChars(fileSystem, nullptr);

    bool success;
    if (containerFormat == 1 || containerFormat == 2) {
        // 1 = LUKS1, 2 = LUKS2 — see ContainerFormat (container_format.h).
        success = createLuksContainer(fd, nativePass, pim, static_cast<int64_t>(sizeBytes),
                                      nativeFS, containerFormat, cipherId, hashId,
                                      kfFds.empty() ? nullptr : kfFds.data(),
                                      static_cast<int>(kfFds.size()));
    } else {
        success = createContainer(fd, nativePass, pim, static_cast<int64_t>(sizeBytes),
                                  nativeFS, cipherId, hashId,
                                  kfFds.empty() ? nullptr : kfFds.data(),
                                  static_cast<int>(kfFds.size()));
    }

    env->ReleaseStringUTFChars(password, nativePass);
    env->ReleaseStringUTFChars(fileSystem, nativeFS);

    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_createContainerWithHiddenNative(
        JNIEnv* env, jobject,
        jint fd, jstring outerPassword, jstring hiddenPassword,
        jint outerPim, jint hiddenPim, jlong sizeBytes, jstring outerFileSystem, jstring hiddenFileSystem,
        jlong hiddenSizeBytes,
        jint outerCipherId, jint outerHashId,
        jint hiddenCipherId, jint hiddenHashId,
        jintArray outerKeyfileFds, jintArray hiddenKeyfileFds) {

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
                                             hiddenKfFds.empty() ? nullptr : hiddenKfFds.data(), static_cast<int>(hiddenKfFds.size()));

    env->ReleaseStringUTFChars(outerPassword, nativeOuterPass);
    env->ReleaseStringUTFChars(hiddenPassword, nativeHiddenPass);
    env->ReleaseStringUTFChars(outerFileSystem, nativeOuterFS);
    env->ReleaseStringUTFChars(hiddenFileSystem, nativeHiddenFS);

    return success ? JNI_TRUE : JNI_FALSE;
}

#include "partition_writer.h"

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_createUsbContainerNative(
        JNIEnv* env, jobject,
        jint volId, jstring partitionScheme, jstring password, jint pim, jlong sizeBytes, jstring fileSystem,
        jint containerFormat, jint cipherId, jint hashId, jintArray keyfileFds, jboolean quickFormat) {

    if (volId < 0 || volId >= MAX_VOLUMES) return JNI_FALSE;

    std::vector<int> kfFds = extractKeyfileFds(env, keyfileFds);
    const char* nativePass = env->GetStringUTFChars(password, nullptr);
    const char* nativeFS   = env->GetStringUTFChars(fileSystem, nullptr);

    static constexpr uint64_t kUsbPartitionStartSector = 2048;
    const uint64_t numSectors = static_cast<uint64_t>(sizeBytes) / 512;

    LOGI("createUsbContainerNative: volId=%d sizeBytes=%lld fs=%s format=%d numSectors=%llu",
         volId, (long long)sizeBytes, nativeFS, containerFormat, (unsigned long long)numSectors);

    bool success = writeMbrPartitionTable(volId, kUsbPartitionStartSector, numSectors);
    LOGI("createUsbContainerNative: writeMbrPartitionTable success=%d", success ? 1 : 0);

    if (success) {
        success = (containerFormat == 1 || containerFormat == 2)
            ? createUsbLuksContainer(volId, kUsbPartitionStartSector, nativePass, pim,
                                     static_cast<int64_t>(sizeBytes), nativeFS,
                                     containerFormat, cipherId, hashId,
                                     kfFds.empty() ? nullptr : kfFds.data(), static_cast<int>(kfFds.size()), quickFormat)
            : createUsbContainer(volId, kUsbPartitionStartSector, nativePass, pim,
                                 static_cast<int64_t>(sizeBytes), nativeFS,
                                 cipherId, hashId,
                                 kfFds.empty() ? nullptr : kfFds.data(), static_cast<int>(kfFds.size()), quickFormat);
    } else {
        closeUnusedKeyfileFds(kfFds.empty() ? nullptr : kfFds.data(), static_cast<int>(kfFds.size()));
    }

    LOGI("createUsbContainerNative: EXIT success=%d", success ? 1 : 0);
    env->ReleaseStringUTFChars(password, nativePass);
    env->ReleaseStringUTFChars(fileSystem, nativeFS);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_createUsbContainerWithHiddenNative(
        JNIEnv* env, jobject,
        jint volId, jstring partitionScheme,
        jstring outerPassword, jstring hiddenPassword,
        jint outerPim, jint hiddenPim, jlong sizeBytes,
        jstring outerFileSystem, jstring hiddenFileSystem, jlong hiddenSizeBytes,
        jint outerCipherId, jint outerHashId, jint hiddenCipherId, jint hiddenHashId,
        jintArray outerKeyfileFds, jintArray hiddenKeyfileFds, jboolean quickFormat) {

    if (volId < 0 || volId >= MAX_VOLUMES) return JNI_FALSE;

    std::vector<int> outerKfFds = extractKeyfileFds(env, outerKeyfileFds);
    std::vector<int> hiddenKfFds = extractKeyfileFds(env, hiddenKeyfileFds);
    
    const char* nativeOuterPass = env->GetStringUTFChars(outerPassword, nullptr);
    const char* nativeHiddenPass = env->GetStringUTFChars(hiddenPassword, nullptr);
    const char* nativeOuterFS   = env->GetStringUTFChars(outerFileSystem, nullptr);
    const char* nativeHiddenFS   = env->GetStringUTFChars(hiddenFileSystem, nullptr);

    static constexpr uint64_t kUsbPartitionStartSector = 2048;
    const uint64_t numSectors = static_cast<uint64_t>(sizeBytes) / 512;

    bool success = writeMbrPartitionTable(volId, kUsbPartitionStartSector, numSectors);

    if (success) {
        success = createUsbContainerWithHidden(
            volId, kUsbPartitionStartSector,
            nativeOuterPass, nativeHiddenPass, outerPim, hiddenPim, static_cast<int64_t>(sizeBytes),
            nativeOuterFS, nativeHiddenFS, static_cast<int64_t>(hiddenSizeBytes),
            outerCipherId, outerHashId, hiddenCipherId, hiddenHashId,
            outerKfFds.empty() ? nullptr : outerKfFds.data(), static_cast<int>(outerKfFds.size()),
            hiddenKfFds.empty() ? nullptr : hiddenKfFds.data(), static_cast<int>(hiddenKfFds.size()),
            quickFormat
        );
    } else {
        closeUnusedKeyfileFds(outerKfFds.empty() ? nullptr : outerKfFds.data(), static_cast<int>(outerKfFds.size()));
        closeUnusedKeyfileFds(hiddenKfFds.empty() ? nullptr : hiddenKfFds.data(), static_cast<int>(hiddenKfFds.size()));
    }

    env->ReleaseStringUTFChars(outerPassword, nativeOuterPass);
    env->ReleaseStringUTFChars(hiddenPassword, nativeHiddenPass);
    env->ReleaseStringUTFChars(outerFileSystem, nativeOuterFS);
    env->ReleaseStringUTFChars(hiddenFileSystem, nativeHiddenFS);

    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_changeContainerPasswordNative(
        JNIEnv* env, jobject,
        jint fd, jstring oldPassword, jstring newPassword,
        jint oldPim, jint newPim,
        jint cipherId, jint hashId, jintArray oldKeyfileFds, jintArray newKeyfileFds) {

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
}
