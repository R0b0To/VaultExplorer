#include <jni.h>
#include <string>
#include <vector>
#include <mutex>
#include <shared_mutex>

#include "session_prepare.h"
#include "container_utils.h"
#include "session_guard.h"
#include "volume_state.h"
#include "virtual_block_device.h"
#include "filesystems/fs_ops.h"
#include "jni_callbacks.h"

#include "jni_bridge_common.h"

static constexpr size_t MAX_CHUNK_SIZE = 64 * 1024 * 1024;  // 64 MB per JNI read/write call

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_listDirectory(
        JNIEnv* env, jobject, jstring dirPath, jint volId) {
    JNI_TRY

    if (!requireActiveSession(volId, "listDirectory")) {
        throwNotUnlocked(env, volId, "listDirectory"); return nullptr;
    }
    const char* nativePath = env->GetStringUTFChars(dirPath, nullptr);
    jobjectArray result = nullptr;
    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            std::vector<std::string> results;
            results.reserve(256);
            fsListDirectory(volId, nativePath, results);

            jclass strClass = env->FindClass("java/lang/String");
            result = env->NewObjectArray(static_cast<jsize>(results.size()), strClass, nullptr);
            for (size_t i = 0; i < results.size(); i++) {
                sanitizeString(results[i]);
                jstring js = env->NewStringUTF(results[i].c_str());
                env->SetObjectArrayElement(result, i, js);
                env->DeleteLocalRef(js);
            }
        }
    }
    env->ReleaseStringUTFChars(dirPath, nativePath);
    return result;

    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_getFileSize(
        JNIEnv* env, jobject, jstring fileName, jint volId) {
    JNI_TRY

    if (!requireActiveSession(volId, "getFileSize")) {
        throwNotUnlocked(env, volId, "getFileSize"); return 0L;
    }
    const char* targetName = env->GetStringUTFChars(fileName, nullptr);
    jlong size = 0;
    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            size = static_cast<jlong>(fsGetFileSize(volId, targetName));
        }
    }
    env->ReleaseStringUTFChars(fileName, targetName);
    return size;

    JNI_CATCH_RETURN(-1)
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_getFolderSize(
        JNIEnv* env, jobject, jstring dirPath, jint volId) {
    JNI_TRY

    if (!requireActiveSession(volId, "getFolderSize")) {
        throwNotUnlocked(env, volId, "getFolderSize"); return 0L;
    }
    const char* nativePath = env->GetStringUTFChars(dirPath, nullptr);
    jlong total = 0;
    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            total = static_cast<jlong>(fsGetFolderSize(volId, nativePath));
        }
    }
    env->ReleaseStringUTFChars(dirPath, nativePath);
    return total;

    JNI_CATCH_RETURN(-1)
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_readFileChunk(
        JNIEnv* env, jobject,
        jstring fileName, jlong offset, jint length, jint volId) {
    JNI_TRY
    if (length <= 0 || static_cast<size_t>(length) > MAX_CHUNK_SIZE) return nullptr;
    if (!requireActiveSession(volId, "readFileChunk")) {
        throwNotUnlocked(env, volId, "readFileChunk"); return nullptr;
    }
    const char* targetName = env->GetStringUTFChars(fileName, nullptr);
    jbyteArray retArray = nullptr;
    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            std::vector<uint8_t> buffer;
            if (fsReadFileChunk(volId, targetName, static_cast<uint64_t>(offset),
                                 static_cast<size_t>(length), buffer)) {
                retArray = env->NewByteArray(static_cast<jsize>(buffer.size()));
                env->SetByteArrayRegion(retArray, 0, static_cast<jsize>(buffer.size()),
                                        reinterpret_cast<jbyte*>(buffer.data()));
            }
        }
    }
    env->ReleaseStringUTFChars(fileName, targetName);
    return retArray;
    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_writeFileChunk(
        JNIEnv* env, jobject,
        jstring fileName, jlong offset, jbyteArray data, jint volId) {
    JNI_TRY

    jsize len = env->GetArrayLength(data);
    if (len < 0 || static_cast<size_t>(len) > MAX_CHUNK_SIZE) return JNI_FALSE;
    if (!requireActiveSession(volId, "writeFileChunk")) {
        throwNotUnlocked(env, volId, "writeFileChunk"); return JNI_FALSE;
    }
    if (isVolumeReadOnly(volId)) {
        throwReadOnly(env, volId, "writeFileChunk"); return JNI_FALSE;
    }
    const char* targetName = env->GetStringUTFChars(fileName, nullptr);
    jbyte* body = env->GetByteArrayElements(data, nullptr);
    bool success = false;

    std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
    if (ensureMounted(volId)) {
        success = fsWriteFileChunk(volId, targetName, static_cast<uint64_t>(offset),
                                    reinterpret_cast<const uint8_t*>(body), static_cast<size_t>(len));
    }

    env->ReleaseByteArrayElements(data, body, JNI_ABORT);
    env->ReleaseStringUTFChars(fileName, targetName);
    return success ? JNI_TRUE : JNI_FALSE;

    JNI_CATCH_RETURN(JNI_FALSE)
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_writeBackFile(
        JNIEnv* env, jobject,
        jstring targetFileName, jstring sourcePath, jint volId, jint opId) {
    JNI_TRY

    if (!requireActiveSession(volId, "writeBackFile")) {
        throwNotUnlocked(env, volId, "writeBackFile"); return JNI_FALSE;
    }
    if (isVolumeReadOnly(volId)) {
        throwReadOnly(env, volId, "writeBackFile"); return JNI_FALSE;
    }
    const char* targetName = env->GetStringUTFChars(targetFileName, nullptr);
    const char* source     = env->GetStringUTFChars(sourcePath, nullptr);
    bool success = false;
    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            success = fsWriteBackFile(volId, targetName, source,
                [opId, volId, &fsLock](uint64_t bytesWritten) -> bool {
                    reportImportChunkProgress(opId, bytesWritten);
                    if (isImportCancelled(opId)) return false;

                    fsLock.unlock();
                    yieldContainerWriteLock(volId);
                    fsLock.lock();

                    return ensureMounted(volId);
                });
        }
    }
    env->ReleaseStringUTFChars(targetFileName, targetName);
    env->ReleaseStringUTFChars(sourcePath, source);
    return success ? JNI_TRUE : JNI_FALSE;

    JNI_CATCH_RETURN(JNI_FALSE)
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_extractFile(
        JNIEnv* env, jobject,
        jstring targetFileName, jstring destPath, jint volId) {
    JNI_TRY

    if (!requireActiveSession(volId, "extractFile")) {
        throwNotUnlocked(env, volId, "extractFile"); return JNI_FALSE;
    }
    const char* targetName  = env->GetStringUTFChars(targetFileName, nullptr);
    const char* destination = env->GetStringUTFChars(destPath, nullptr);
    bool success = false;
    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            success = fsExtractFile(volId, targetName, destination);
        }
    }
    env->ReleaseStringUTFChars(targetFileName, targetName);
    env->ReleaseStringUTFChars(destPath, destination);
    return success ? JNI_TRUE : JNI_FALSE;

    JNI_CATCH_RETURN(JNI_FALSE)
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_deleteFile(
        JNIEnv* env, jobject, jstring targetFileName, jint volId) {
    JNI_TRY

    if (!requireActiveSession(volId, "deleteFile")) {
        throwNotUnlocked(env, volId, "deleteFile"); return JNI_FALSE;
    }
    if (isVolumeReadOnly(volId)) {
        throwReadOnly(env, volId, "deleteFile"); return JNI_FALSE;
    }
    const char* targetName = env->GetStringUTFChars(targetFileName, nullptr);
    bool success = false;
    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            success = fsDeleteFile(volId, targetName);
        }
    }
    env->ReleaseStringUTFChars(targetFileName, targetName);
    return success ? JNI_TRUE : JNI_FALSE;

    JNI_CATCH_RETURN(JNI_FALSE)
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_createDirectory(
        JNIEnv* env, jobject, jstring dirPath, jint volId) {
    JNI_TRY

    if (!requireActiveSession(volId, "createDirectory")) {
        throwNotUnlocked(env, volId, "createDirectory"); return JNI_FALSE;
    }
    if (isVolumeReadOnly(volId)) {
        throwReadOnly(env, volId, "createDirectory"); return JNI_FALSE;
    }
    const char* nativePath = env->GetStringUTFChars(dirPath, nullptr);
    bool success = false;
    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            success = fsCreateDirectory(volId, nativePath);
        }
    }
    env->ReleaseStringUTFChars(dirPath, nativePath);
    return success ? JNI_TRUE : JNI_FALSE;

    JNI_CATCH_RETURN(JNI_FALSE)
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_renameFile(
        JNIEnv* env, jobject,
        jstring oldPath, jstring newPath, jint volId) {
    JNI_TRY
    if (!requireActiveSession(volId, "renameFile")) {
        throwNotUnlocked(env, volId, "renameFile"); return JNI_FALSE;
    }
    if (isVolumeReadOnly(volId)) {
        throwReadOnly(env, volId, "renameFile"); return JNI_FALSE;
    }
    const char* nativeOld = env->GetStringUTFChars(oldPath, nullptr);
    const char* nativeNew = env->GetStringUTFChars(newPath, nullptr);
    bool success = false;
    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            success = fsRenameFile(volId, nativeOld, nativeNew);
        }
    }
    env->ReleaseStringUTFChars(oldPath, nativeOld);
    env->ReleaseStringUTFChars(newPath, nativeNew);
    return success ? JNI_TRUE : JNI_FALSE;
    JNI_CATCH_RETURN(JNI_FALSE)
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_copyFile(
        JNIEnv* env, jobject,
        jstring srcPath, jint srcVolId, jstring destPath, jint destVolId, jint opId) {
    JNI_TRY
    if (!requireActiveSession(srcVolId, "copyFile (src)")) {
        throwNotUnlocked(env, srcVolId, "copyFile"); return JNI_FALSE;
    }
    if (!requireActiveSession(destVolId, "copyFile (dest)")) {
        throwNotUnlocked(env, destVolId, "copyFile"); return JNI_FALSE;
    }
    if (isVolumeReadOnly(destVolId)) {
        throwReadOnly(env, destVolId, "copyFile"); return JNI_FALSE;
    }
    const char* nativeSrc = env->GetStringUTFChars(srcPath, nullptr);
    const char* nativeDest = env->GetStringUTFChars(destPath, nullptr);
    bool success = false;
    {
        const bool sameVolume = (srcVolId == destVolId);
        std::unique_lock<std::shared_mutex> destLock(volumes[destVolId].mutex, std::defer_lock);
        std::unique_lock<std::shared_mutex> srcLock(volumes[srcVolId].mutex, std::defer_lock);
        if (sameVolume) {
            destLock.lock();
        } else {
            std::lock(srcLock, destLock);
        }
        const bool srcMounted = ensureMounted(srcVolId);
        if (srcMounted && ensureMounted(destVolId)) {
            success = fsCopyFile(srcVolId, nativeSrc, destVolId, nativeDest,
                [opId, srcVolId, destVolId, sameVolume, &destLock, &srcLock]
                (uint64_t bytesWritten) -> bool {
                    reportCopyProgress(opId, bytesWritten);
                    if (isCopyCancelled(opId)) return false;

                    if (sameVolume) {
                        destLock.unlock();
                        yieldContainerCopyLocks(srcVolId, destVolId);
                        destLock.lock();
                        return ensureMounted(destVolId);
                    }

                    destLock.unlock();
                    srcLock.unlock();
                    yieldContainerCopyLocks(srcVolId, destVolId);
                    std::lock(srcLock, destLock);

                    return ensureMounted(srcVolId) && ensureMounted(destVolId);
                });
        }
    }
    env->ReleaseStringUTFChars(srcPath, nativeSrc);
    env->ReleaseStringUTFChars(destPath, nativeDest);
    return success ? JNI_TRUE : JNI_FALSE;
    JNI_CATCH_RETURN(JNI_FALSE)
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_setLastModifiedTime(
        JNIEnv* env, jobject,
        jstring path, jlong epochSeconds, jint volId) {
    JNI_TRY

    if (!requireActiveSession(volId, "setLastModifiedTime")) {
        throwNotUnlocked(env, volId, "setLastModifiedTime"); return JNI_FALSE;
    }
    if (isVolumeReadOnly(volId)) {
        throwReadOnly(env, volId, "setLastModifiedTime"); return JNI_FALSE;
    }
    const char* nativePath = env->GetStringUTFChars(path, nullptr);
    bool success = false;
    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            success = fsSetLastModifiedTime(volId, nativePath, static_cast<uint64_t>(epochSeconds));
        }
    }
    env->ReleaseStringUTFChars(path, nativePath);
    return success ? JNI_TRUE : JNI_FALSE;

    JNI_CATCH_RETURN(JNI_FALSE)
}

extern "C" JNIEXPORT jlongArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_getSpaceInfo(
        JNIEnv* env, jobject, jint volId) {
    JNI_TRY

    if (!requireActiveSession(volId, "getSpaceInfo")) {
        throwNotUnlocked(env, volId, "getSpaceInfo"); return nullptr;
    }
    uint64_t totalBytes = 0, freeBytes = 0;
    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            fsGetSpaceInfo(volId, totalBytes, freeBytes);
        }
    }
    jlongArray ret = env->NewLongArray(2);
    if (!ret) return nullptr;
    const jlong tmp[2] = {static_cast<jlong>(totalBytes), static_cast<jlong>(freeBytes)};
    env->SetLongArrayRegion(ret, 0, 2, tmp);
    return ret;

    JNI_CATCH_RETURN(nullptr)
}

// Vault Settings' "Vault Information" screen (native block-device formats
// only -- Cryptomator/gocryptfs/CryFS answer the equivalent Kotlin-side
// VaultBackend.getVaultInfo() instead, see ContainerEngine.getVaultInfo()).
// Most fields here come from the crypto/session layer (VolumeState), not
// the mounted filesystem, so they stay valid even for a format this app
// can unlock but whose filesystem type isn't recognized. fileSystem is the
// one exception -- it needs the volume actually mounted, which normally
// only happens lazily on first browse (see ensureMounted()'s callers), and
// Vault Settings is reachable without ever opening the file browser. So
// this does call ensureMounted() itself, best-effort: on failure (or for
// an unrecognized filesystem) fileSystem is simply left out of the map,
// same as every other field above already degrades to being absent rather
// than failing the whole call.
extern "C" JNIEXPORT jobject JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_getVaultInfo(
        JNIEnv* env, jobject, jint volId) {
    JNI_TRY

    if (!requireActiveSession(volId, "getVaultInfo")) {
        throwNotUnlocked(env, volId, "getVaultInfo"); return nullptr;
    }

    ContainerFormat format;
    bool isHidden;
    bool readOnly;
    uint64_t volumeSize;
    int cipherId;
    int hashId;
    uint32_t sectorSize;
    std::string fileSystemLabel;
    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        VolumeState& v = volumes[volId];
        format = v.containerFormat;
        isHidden = v.isHiddenVolume;
        readOnly = v.readOnly;
        volumeSize = v.dataAreaLengthBytes;
        cipherId = v.matchedCipherId;
        hashId = v.matchedHashId;
        sectorSize = v.luksSectorSize;
        if (ensureMounted(volId)) {
            fileSystemLabel = fsGetFilesystemLabel(volId);
        }
    }

    jclass mapClass = env->FindClass("java/util/HashMap");
    jmethodID mapInit = env->GetMethodID(mapClass, "<init>", "()V");
    jmethodID mapPut = env->GetMethodID(mapClass, "put",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
    jobject result = env->NewObject(mapClass, mapInit);

    jclass intClass = env->FindClass("java/lang/Integer");
    jmethodID intInit = env->GetMethodID(intClass, "<init>", "(I)V");
    jclass longClass = env->FindClass("java/lang/Long");
    jmethodID longInit = env->GetMethodID(longClass, "<init>", "(J)V");
    jclass boolClass = env->FindClass("java/lang/Boolean");
    jmethodID boolInit = env->GetMethodID(boolClass, "<init>", "(Z)V");

    auto putInt = [&](const char* key, int value) {
        jstring k = env->NewStringUTF(key);
        jobject boxed = env->NewObject(intClass, intInit, static_cast<jint>(value));
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
    auto putBool = [&](const char* key, bool value) {
        jstring k = env->NewStringUTF(key);
        jobject boxed = env->NewObject(boolClass, boolInit, static_cast<jboolean>(value));
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

    putBool("readOnly", readOnly);
    putLong("volumeSizeBytes", static_cast<int64_t>(volumeSize));
    // All three formats below are block-device-backed ("file containers"),
    // so an inner filesystem is always meaningful -- unlike the folder-vault
    // formats (Cryptomator/gocryptfs/CryFS), which store individual
    // encrypted files directly and have no such thing.
    if (!fileSystemLabel.empty()) putString("fileSystem", fileSystemLabel);

    switch (format) {
        case ContainerFormat::kVeraCrypt:
            putInt("cipherId", cipherId);
            putInt("hashId", hashId);
            putBool("hiddenVolume", isHidden);
            break;
        case ContainerFormat::kLuks1:
        case ContainerFormat::kLuks2:
            putInt("luksVersion", format == ContainerFormat::kLuks1 ? 1 : 2);
            putInt("cipherId", cipherId);
            putInt("sectorSize", static_cast<int>(sectorSize));
            break;
        case ContainerFormat::kBitLocker:
            // This app's dislocker-backed BitLocker support (see
            // bitlocker_backend.h) doesn't parse/retain the FVE metadata's
            // cipher/version fields -- readOnly/volumeSizeBytes/fileSystem
            // above are all that's available for this format.
            break;
    }

    return result;

    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_openStream(
        JNIEnv* env, jobject, jstring targetFileName, jint volId) {
    JNI_TRY

    if (!requireActiveSession(volId, "openStream")) {
        throwNotUnlocked(env, volId, "openStream"); return 0L;
    }
    const char* targetName = env->GetStringUTFChars(targetFileName, nullptr);
    jlong streamPtr = 0;
    {
        // Exclusive, not shared: fsOpenStream pushes onto the volume's
        // openNtfsStreams/openExtStreams/openStreams vector (see
        // ntfs_backend.cpp/ext_backend.cpp/fat_backend.cpp), which is a
        // plain std::vector with no locking of its own -- concurrent
        // openStream/closeStream calls from different threads would race
        // on that push_back/erase otherwise, even though each call only
        // touches "its own" stream handle.
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            streamPtr = reinterpret_cast<jlong>(fsOpenStream(volId, targetName));
        }
    }
    env->ReleaseStringUTFChars(targetFileName, targetName);
    return streamPtr;

    JNI_CATCH_RETURN(-1)
}

// Note: unlike every other function above, this doesn't call ensureMounted()
// -- matches the original inline version, which also skipped it here and
// went straight to dispatching on fsType. A stream can only exist if
// openStream() already mounted successfully, so re-checking on every read
// would be redundant work on a hot path (media playback).
extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_readStream(
        JNIEnv* env, jobject,
        jlong streamPtr, jlong offset, jbyteArray outBuffer, jint length, jint volId) {
    JNI_TRY

    if (streamPtr == 0 || length <= 0) return -1;
    if (volId < 0 || volId >= MAX_VOLUMES) return -1;
    if (outBuffer == nullptr) return -1;

    // The caller-supplied `length` must never exceed the real capacity of
    // outBuffer: fsReadStream is trusted to write up to `length` bytes into
    // destBuf, so an oversized `length` here would overflow the JVM-managed
    // array (see writeFileChunk above, which already bounds `len` against
    // GetArrayLength(data) the same way).
    const jsize bufCapacity = env->GetArrayLength(outBuffer);
    if (length > bufCapacity) length = bufCapacity;
    if (length <= 0) return -1;

    // Exclusive, not shared: fsReadStream validates `streamPtr` against the
    // volume's openNtfsStreams/openExtStreams/openStreams vector on every
    // call (std::find over the vector -- see ntfsReadStream/extReadStream/
    // fatReadStream), the same vector openStream()/closeStream() push_back
    // into and erase from. A concurrent open or close reallocating/erasing
    // that vector while this thread's find() is mid-traversal is undefined
    // behavior, not just a stale-data race -- so this can't be downgraded
    // to a shared lock the way the chunk-based reads above were, even
    // though a single readStream call only touches its own stream's data.
    // (This means stream-based reads -- the media-playback path -- don't
    // get the same concurrent-reader benefit as listDirectory/getFileSize/
    // readFileChunk/etc. above; loosening that would need the stream
    // vectors to have their own lock separate from the filesystem-mutation
    // lock, which is a larger change than this one.)
    std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
    jbyte* destBuf = env->GetByteArrayElements(outBuffer, nullptr);
    if (destBuf == nullptr) return -1;
    jint bytesRead = static_cast<jint>(fsReadStream(volId, reinterpret_cast<void*>(streamPtr),
                                                     static_cast<uint64_t>(offset),
                                                     reinterpret_cast<uint8_t*>(destBuf),
                                                     static_cast<size_t>(length)));
    env->ReleaseByteArrayElements(outBuffer, destBuf, 0);
    return bytesRead;

    JNI_CATCH_RETURN(-1)
}

extern "C" JNIEXPORT void JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_closeStream(
        JNIEnv* env, jobject, jlong streamPtr, jint volId) {
    JNI_TRY

    if (streamPtr == 0) return;
    if (volId < 0 || volId >= MAX_VOLUMES) return;

    // Exclusive: fsCloseStream erases from the same stream vector
    // fsOpenStream pushes onto and fsReadStream searches -- same
    // reasoning as readStream above.
    std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
    fsCloseStream(volId, reinterpret_cast<void*>(streamPtr));

    JNI_CATCH_VOID
}