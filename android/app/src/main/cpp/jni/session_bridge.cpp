// JNI bridge: unlock/lock session lifecycle (VeraCrypt/LUKS + USB variants)
// and per-volume session metadata queries. See crypto_bridge.cpp's header
// comment for why splitting vaultexplorer.cpp this way doesn't require any
// Kotlin/Dart changes.

#include <jni.h>
#include <cstring>
#include <vector>
#include <mutex>
#include <shared_mutex>
#include <algorithm>

#include <mbedtls/platform_util.h>

#include "session_prepare.h"
#include "session_guard.h"
#include "lock_policy.h"
#include "volume_state.h"
#include "container_format.h"
#include "filesystems/stream_handles.h"
#include "jni_callbacks.h"
#include "virtual_block_device.h"

#include "jni_bridge_common.h"

static void throwUnlockCancelledException(JNIEnv* env) {
    if (g_unlockCancelledExceptionClass) env->ThrowNew(g_unlockCancelledExceptionClass, "CANCELLED");
}

static void rollBackUnprotectedSession(int volId) {
    VolumeState& v = volumes[volId];
    std::unique_lock<std::shared_mutex> lock(v.mutex);
    for (FIL* f : v.openStreams) { f_close(f); delete f; }
    v.openStreams.clear();
    for (NtfsStream* ns : v.openNtfsStreams) {
        ntfs_attr_close(ns->attr);
        ntfs_inode_close(ns->inode);
        delete ns;
    }
    v.openNtfsStreams.clear();
    unmountVolume(volId);
    v.reset();
}

static bool applyHiddenVolumeProtectionOrRollBack(
        JNIEnv* env, int volId, jstring hiddenPassword, jint hiddenPim,
        jint hiddenCipherId, jint hiddenHashId, jintArray hiddenKeyfileFds, bool useBackupHeader) {
    if (hiddenPassword == nullptr) return true;

    const char* nativeHiddenPass = vcGetPasswordUtf8(env, hiddenPassword);
    std::vector<int> hiddenKfFds = extractKeyfileFds(env, hiddenKeyfileFds);
    const bool ok = enableHiddenVolumeProtection(
        volId, reinterpret_cast<const unsigned char*>(nativeHiddenPass), strlen(nativeHiddenPass),
        hiddenPim, hiddenCipherId, hiddenHashId,
        hiddenKfFds.empty() ? nullptr : hiddenKfFds.data(), static_cast<int>(hiddenKfFds.size()),
        useBackupHeader);
    vcReleasePasswordUtf8(nativeHiddenPass);

    if (!ok) {
        rollBackUnprotectedSession(volId);
        return false;
    }
    return true;
}

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_unlockAndListNative(
        JNIEnv* env, jobject, jint fd, jstring password, jint pim, jint volId, jint cipherId, jint hashId, jbyteArray preservedKey, jintArray keyfileFds, jboolean readOnly,
        jstring hiddenPassword, jint hiddenPim, jint hiddenCipherId, jint hiddenHashId, jintArray hiddenKeyfileFds,
        jboolean useBackupHeader) {
    JNI_TRY

    clearUnlockCancellation(volId);

    const unsigned char* preservedBytes = nullptr;
    size_t preservedLen = 0;
    if (preservedKey != nullptr) {
        preservedBytes = reinterpret_cast<const unsigned char*>(env->GetByteArrayElements(preservedKey, nullptr));
        preservedLen = static_cast<size_t>(env->GetArrayLength(preservedKey));
    }

    std::vector<int> kfFds = extractKeyfileFds(env, keyfileFds);
    const char* nativePass = vcGetPasswordUtf8(env, password);
    
    if (!prepareSession(fd, reinterpret_cast<const unsigned char*>(nativePass), strlen(nativePass), pim, volId, true, cipherId, hashId, preservedBytes, preservedLen,
                             kfFds.empty() ? nullptr : kfFds.data(), static_cast<int>(kfFds.size()),
                             readOnly == JNI_TRUE, useBackupHeader == JNI_TRUE)) {
        if (preservedKey != nullptr) {
            env->ReleaseByteArrayElements(preservedKey, reinterpret_cast<jbyte*>(const_cast<unsigned char*>(preservedBytes)), JNI_ABORT);
        }
        vcReleasePasswordUtf8(nativePass);
        if (isUnlockCancelled(volId)) throwUnlockCancelledException(env);
        return nullptr;
    }

    bool mountOk;
    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        mountOk = ensureMounted(volId);
    }

    if (preservedKey != nullptr) {
        env->ReleaseByteArrayElements(preservedKey, reinterpret_cast<jbyte*>(const_cast<unsigned char*>(preservedBytes)), JNI_ABORT);
    }
    vcReleasePasswordUtf8(nativePass);

    if (!mountOk) {
        LOGI("FATFS/NTFS Mount failed on volume %d", volId);
        return nullptr;
    }

    if (!applyHiddenVolumeProtectionOrRollBack(env, volId, hiddenPassword, hiddenPim,
                                               hiddenCipherId, hiddenHashId, hiddenKeyfileFds,
                                               useBackupHeader == JNI_TRUE)) {
        return nullptr;
    }

    jclass strClass = env->FindClass("java/lang/String");
    return env->NewObjectArray(0, strClass, nullptr);

    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT void JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_requestCancelUnlockNative(
        JNIEnv* env, jobject, jint volId) {
    JNI_TRY

    requestUnlockCancellation(volId);

    JNI_CATCH_VOID
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_detectsAsPlainDiskImageNative(
        JNIEnv* env, jobject, jint fd) {
    JNI_TRY

    return detectsAsPlainDiskImage(fd) ? JNI_TRUE : JNI_FALSE;

    JNI_CATCH_RETURN(JNI_FALSE)
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_probeContainerFormatNative(
        JNIEnv* env, jobject, jint fd) {
    JNI_TRY

    const char* fmt = probeContainerFormat(fd);
    return env->NewStringUTF(fmt ? fmt : "unknown");

    JNI_CATCH_RETURN(nullptr)
}

// Locks one volume; the caller holds volumes[volId].mutex exclusively. The ordering is
// session/lock_policy.h: a normal lock of a USB volume never throws away data it has
// already acknowledged. If the device refuses the flush it returns false and keeps the
// pending write cache and the volume state, so locking can simply be retried (the
// keep-alive service and the Lock button do). `force` is the explicit "give up on the
// unwritten data" path -- a removed device, or the user choosing to lock anyway.
static bool lockVolumeLocked(int volId, bool force) {
    VolumeState& v = volumes[volId];
    bool discarded = false;
    const bool locked = lockpolicy::lockVolume(
        v.isUsbSource, force,
        // Flush while the filesystem is still mounted: if the device is already failing,
        // nothing has been torn down and the vault stays fully usable.
        [&] {
            const bool ok = v.usbCache.sync(volId);
            if (!ok) LOGI("lockNative(vol=%d): USB flush failed, volume left open for retry", volId);
            return ok;
        },
        [&] {
            // Close FAT streams
            for (FIL* f : v.openStreams) {
                f_close(f);
                delete f;
            }
            v.openStreams.clear();

            // Close NTFS streams
            for (NtfsStream* ns : v.openNtfsStreams) {
                ntfs_attr_close(ns->attr);
                ntfs_inode_close(ns->inode);
                delete ns;
            }
            v.openNtfsStreams.clear();

            const bool durable = unmountVolume(volId);
            if (!durable) LOGI("lockNative(vol=%d): final USB flush failed", volId);
            return durable;
        },
        // reset() clears the USB write cache, so it only runs once that is intended.
        [&] { v.reset(); },
        &discarded);
    if (!locked) {
        LOGI("lockNative(vol=%d): not locked, pending writes kept for retry", volId);
    } else if (discarded) {
        LOGI("lockNative(vol=%d): forced lock discarded buffered USB writes", volId);
    }
    return locked;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_lockNative(JNIEnv* env, jobject, jint volId, jboolean force) {
    JNI_TRY

    if (volId < 0 || volId >= MAX_VOLUMES) return JNI_TRUE;

    VolumeState& v = volumes[volId];
    std::unique_lock<std::shared_mutex> lock(v.mutex);
    return lockVolumeLocked(volId, force == JNI_TRUE) ? JNI_TRUE : JNI_FALSE;

    JNI_CATCH_RETURN(JNI_FALSE)
}

extern "C" JNIEXPORT void JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_emergencyPurgeNative(
    JNIEnv* env, jclass clazz, jint volId
) {
    JNI_TRY

    if (volId >= 0 && volId < MAX_VOLUMES) {
        VolumeState& vol = volumes[volId];
        std::unique_lock<std::shared_mutex> lock(vol.mutex);

        // Zeroize master/preserved key material
        if (vol.preservedDerivedKey != nullptr && vol.preservedDerivedKeyLen > 0) {
            mbedtls_platform_zeroize(vol.preservedDerivedKey, vol.preservedDerivedKeyLen);
            delete[] vol.preservedDerivedKey;
            vol.preservedDerivedKey = nullptr;
            vol.preservedDerivedKeyLen = 0;
        }

        // Zeroize intermediate sector / I/O buffers
        if (vol.ioBuf != nullptr && vol.ioBufSize > 0) {
            mbedtls_platform_zeroize(vol.ioBuf.get(), vol.ioBufSize);
        }

        // Force-invalidate crypto contexts and caches
        mbedtls_platform_zeroize(&vol.cascade, sizeof(vol.cascade));
        mbedtls_platform_zeroize(&vol.luksGenericCascade, sizeof(vol.luksGenericCascade));
        vol.cascade.initialized = false;
        vol.luksGenericCascade.initialized = false;
        vol.dataCtxInitialized = false;
        vol.decryptedBlockCache.clear();
        vol.usbCache.clear();
    }

    JNI_CATCH_VOID
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_getMatchedCipherId(JNIEnv* env, jobject, jint volId) {
    JNI_TRY

    if (volId < 0 || volId >= MAX_VOLUMES) return -1;
    std::shared_lock<std::shared_mutex> lock(volumes[volId].mutex);
    return volumes[volId].matchedCipherId;

    JNI_CATCH_RETURN(-1)
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_getMatchedHashId(JNIEnv* env, jobject, jint volId) {
    JNI_TRY

    if (volId < 0 || volId >= MAX_VOLUMES) return -1;
    std::shared_lock<std::shared_mutex> lock(volumes[volId].mutex);
    return volumes[volId].matchedHashId;

    JNI_CATCH_RETURN(-1)
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_getContainerFormat(JNIEnv* env, jobject, jint volId) {
    JNI_TRY

    if (volId < 0 || volId >= MAX_VOLUMES) return 0;
    std::shared_lock<std::shared_mutex> lock(volumes[volId].mutex);
    return static_cast<jint>(volumes[volId].containerFormat);

    JNI_CATCH_RETURN(-1)
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_getMatchedPartitionOffset(JNIEnv* env, jobject, jint volId) {
    JNI_TRY

    if (volId < 0 || volId >= MAX_VOLUMES) return -1;
    std::shared_lock<std::shared_mutex> lock(volumes[volId].mutex);
    if (!volumes[volId].isUsbSource) return -1;
    return static_cast<jlong>(volumes[volId].partitionStartSector);

    JNI_CATCH_RETURN(-1)
}

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_unlockUsbAndListNative(
        JNIEnv* env, jobject, jstring password, jint pim, jint volId, jlong deviceSizeBytes, jint cipherId, jint hashId, jbyteArray preservedKey,
        jlong partitionOffsetHint, jintArray keyfileFds, jboolean readOnly,
        jstring hiddenPassword, jint hiddenPim, jint hiddenCipherId, jint hiddenHashId, jintArray hiddenKeyfileFds,
        jboolean useBackupHeader) {
    JNI_TRY

    clearUnlockCancellation(volId);

    const unsigned char* preservedBytes = nullptr;
    size_t preservedLen = 0;
    if (preservedKey != nullptr) {
        preservedBytes = reinterpret_cast<const unsigned char*>(env->GetByteArrayElements(preservedKey, nullptr));
        preservedLen = static_cast<size_t>(env->GetArrayLength(preservedKey));
    }

    std::vector<int> kfFds = extractKeyfileFds(env, keyfileFds);
    const char* nativePass = vcGetPasswordUtf8(env, password);
    
    const bool ok = prepareUsbSession(reinterpret_cast<const unsigned char*>(nativePass), strlen(nativePass), pim, volId, cipherId, hashId, preservedBytes, preservedLen,
                                       static_cast<int64_t>(partitionOffsetHint),
                                       kfFds.empty() ? nullptr : kfFds.data(), static_cast<int>(kfFds.size()),
                                       readOnly == JNI_TRUE, useBackupHeader == JNI_TRUE,
                                       static_cast<int64_t>(deviceSizeBytes));
    
    if (preservedKey != nullptr) {
        env->ReleaseByteArrayElements(preservedKey, reinterpret_cast<jbyte*>(const_cast<unsigned char*>(preservedBytes)), JNI_ABORT);
    }
    vcReleasePasswordUtf8(nativePass);
    if (!ok) {
        if (isUnlockCancelled(volId)) throwUnlockCancelledException(env);
        return nullptr;
    }

    {
        std::unique_lock<std::shared_mutex> lock(volumes[volId].mutex);
        volumes[volId].fileSize = static_cast<uint64_t>(deviceSizeBytes);
    }

    bool mountOk;
    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        mountOk = ensureMounted(volId);
    }
    if (!mountOk) {
        LOGI("FATFS/NTFS Mount failed on USB volume %d", volId);
        return nullptr;
    }

    if (!applyHiddenVolumeProtectionOrRollBack(env, volId, hiddenPassword, hiddenPim,
                                               hiddenCipherId, hiddenHashId, hiddenKeyfileFds,
                                               useBackupHeader == JNI_TRUE)) {
        return nullptr;
    }

    jclass strClass = env->FindClass("java/lang/String");
    return env->NewObjectArray(0, strClass, nullptr);

    JNI_CATCH_RETURN(nullptr)
}