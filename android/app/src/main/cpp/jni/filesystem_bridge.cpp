// JNI bridge: filesystem operations inside an unlocked container --
// directory listing, file read/write/delete/rename/create, streaming
// read (for media playback), and free-space queries -- across all three
// supported filesystem families (FAT/exFAT via FatFs, NTFS via NTFS-3G,
// ext2/3/4 via e2fsprogs's libext2fs). See crypto_bridge.cpp's header
// comment for why splitting vaultexplorer.cpp this way doesn't require any
// Kotlin/Dart changes.
//
// Per-filesystem-type branching used to happen inline in every function
// here. It now lives behind filesystems/fs_ops.h -- one fsXxx(...) call per
// operation, dispatched to filesystems/{fat,ntfs,ext}_backend.cpp by
// volumes[volId].fsType. This file is now purely JNI marshalling: locking
// volumes[volId].mutex, calling ensureMounted(), throwing the right
// exception on failure, and converting between jstring/jbyteArray and
// plain C++ types. No FatFs/NTFS-3G/libext2fs symbol is referenced here
// any more.

#include <jni.h>
#include <string>
#include <vector>
#include <mutex>

#include "session_prepare.h"
#include "container_utils.h"
#include "session_guard.h"
#include "volume_state.h"
#include "virtual_block_device.h"
#include "filesystems/fs_ops.h"

#include "jni_bridge_common.h"

static constexpr size_t MAX_CHUNK_SIZE = 64 * 1024 * 1024;  // 64 MB per JNI read/write call

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_listDirectory(
        JNIEnv* env, jobject, jstring dirPath, jint volId) {
    if (!requireActiveSession(volId, "listDirectory")) {
        throwNotUnlocked(env, volId, "listDirectory"); return nullptr;
    }
    const char* nativePath = env->GetStringUTFChars(dirPath, nullptr);
    jobjectArray result = nullptr;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            std::vector<std::string> results;
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
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getFileSize(
        JNIEnv* env, jobject, jstring fileName, jint volId) {
    if (!requireActiveSession(volId, "getFileSize")) {
        throwNotUnlocked(env, volId, "getFileSize"); return 0L;
    }
    const char* targetName = env->GetStringUTFChars(fileName, nullptr);
    jlong size = 0;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            size = static_cast<jlong>(fsGetFileSize(volId, targetName));
        }
    }
    env->ReleaseStringUTFChars(fileName, targetName);
    return size;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getFolderSize(
        JNIEnv* env, jobject, jstring dirPath, jint volId) {
    if (!requireActiveSession(volId, "getFolderSize")) {
        throwNotUnlocked(env, volId, "getFolderSize"); return 0L;
    }
    const char* nativePath = env->GetStringUTFChars(dirPath, nullptr);
    jlong total = 0;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            total = static_cast<jlong>(fsGetFolderSize(volId, nativePath));
        }
    }
    env->ReleaseStringUTFChars(dirPath, nativePath);
    return total;
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_readFileChunk(
        JNIEnv* env, jobject,
        jstring fileName, jlong offset, jint length, jint volId) {
    if (length <= 0 || static_cast<size_t>(length) > MAX_CHUNK_SIZE) return nullptr;
    if (!requireActiveSession(volId, "readFileChunk")) {
        throwNotUnlocked(env, volId, "readFileChunk"); return nullptr;
    }
    const char* targetName = env->GetStringUTFChars(fileName, nullptr);
    jbyteArray retArray = nullptr;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
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
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_writeFileChunk(
        JNIEnv* env, jobject,
        jstring fileName, jlong offset, jbyteArray data, jint volId) {
    jsize len = env->GetArrayLength(data);
    if (len <= 0 || static_cast<size_t>(len) > MAX_CHUNK_SIZE) return JNI_FALSE;
    if (!requireActiveSession(volId, "writeFileChunk")) {
        throwNotUnlocked(env, volId, "writeFileChunk"); return JNI_FALSE;
    }
    if (isVolumeReadOnly(volId)) {
        throwReadOnly(env, volId, "writeFileChunk"); return JNI_FALSE;
    }
    const char* targetName = env->GetStringUTFChars(fileName, nullptr);
    jbyte* body = env->GetByteArrayElements(data, nullptr);
    bool success = false;

    std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
    if (ensureMounted(volId)) {
        success = fsWriteFileChunk(volId, targetName, static_cast<uint64_t>(offset),
                                    reinterpret_cast<const uint8_t*>(body), static_cast<size_t>(len));
    }

    env->ReleaseByteArrayElements(data, body, JNI_ABORT);
    env->ReleaseStringUTFChars(fileName, targetName);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_writeBackFile(
        JNIEnv* env, jobject,
        jstring targetFileName, jstring sourcePath, jint volId) {
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
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            success = fsWriteBackFile(volId, targetName, source);
        }
    }
    env->ReleaseStringUTFChars(targetFileName, targetName);
    env->ReleaseStringUTFChars(sourcePath, source);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_extractFile(
        JNIEnv* env, jobject,
        jstring targetFileName, jstring destPath, jint volId) {
    if (!requireActiveSession(volId, "extractFile")) {
        throwNotUnlocked(env, volId, "extractFile"); return JNI_FALSE;
    }
    const char* targetName  = env->GetStringUTFChars(targetFileName, nullptr);
    const char* destination = env->GetStringUTFChars(destPath, nullptr);
    bool success = false;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            success = fsExtractFile(volId, targetName, destination);
        }
    }
    env->ReleaseStringUTFChars(targetFileName, targetName);
    env->ReleaseStringUTFChars(destPath, destination);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_deleteFile(
        JNIEnv* env, jobject, jstring targetFileName, jint volId) {
    if (!requireActiveSession(volId, "deleteFile")) {
        throwNotUnlocked(env, volId, "deleteFile"); return JNI_FALSE;
    }
    if (isVolumeReadOnly(volId)) {
        throwReadOnly(env, volId, "deleteFile"); return JNI_FALSE;
    }
    const char* targetName = env->GetStringUTFChars(targetFileName, nullptr);
    bool success = false;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            success = fsDeleteFile(volId, targetName);
        }
    }
    env->ReleaseStringUTFChars(targetFileName, targetName);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_createDirectory(
        JNIEnv* env, jobject, jstring dirPath, jint volId) {
    if (!requireActiveSession(volId, "createDirectory")) {
        throwNotUnlocked(env, volId, "createDirectory"); return JNI_FALSE;
    }
    if (isVolumeReadOnly(volId)) {
        throwReadOnly(env, volId, "createDirectory"); return JNI_FALSE;
    }
    const char* nativePath = env->GetStringUTFChars(dirPath, nullptr);
    bool success = false;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            success = fsCreateDirectory(volId, nativePath);
        }
    }
    env->ReleaseStringUTFChars(dirPath, nativePath);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_renameFile(
        JNIEnv* env, jobject,
        jstring oldPath, jstring newPath, jint volId) {
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
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            success = fsRenameFile(volId, nativeOld, nativeNew);
        }
    }
    env->ReleaseStringUTFChars(oldPath, nativeOld);
    env->ReleaseStringUTFChars(newPath, nativeNew);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_setLastModifiedTime(
        JNIEnv* env, jobject,
        jstring path, jlong epochSeconds, jint volId) {
    if (!requireActiveSession(volId, "setLastModifiedTime")) {
        throwNotUnlocked(env, volId, "setLastModifiedTime"); return JNI_FALSE;
    }
    if (isVolumeReadOnly(volId)) {
        throwReadOnly(env, volId, "setLastModifiedTime"); return JNI_FALSE;
    }
    const char* nativePath = env->GetStringUTFChars(path, nullptr);
    bool success = false;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            success = fsSetLastModifiedTime(volId, nativePath, static_cast<uint64_t>(epochSeconds));
        }
    }
    env->ReleaseStringUTFChars(path, nativePath);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jlongArray JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_getSpaceInfo(
        JNIEnv* env, jobject, jint volId) {
    if (!requireActiveSession(volId, "getSpaceInfo")) {
        throwNotUnlocked(env, volId, "getSpaceInfo"); return nullptr;
    }
    uint64_t totalBytes = 0, freeBytes = 0;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            fsGetSpaceInfo(volId, totalBytes, freeBytes);
        }
    }
    jlongArray ret = env->NewLongArray(2);
    if (!ret) return nullptr;
    const jlong tmp[2] = {static_cast<jlong>(totalBytes), static_cast<jlong>(freeBytes)};
    env->SetLongArrayRegion(ret, 0, 2, tmp);
    return ret;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_openStream(
        JNIEnv* env, jobject, jstring targetFileName, jint volId) {
    if (!requireActiveSession(volId, "openStream")) {
        throwNotUnlocked(env, volId, "openStream"); return 0L;
    }
    const char* targetName = env->GetStringUTFChars(targetFileName, nullptr);
    jlong streamPtr = 0;
    {
        std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            streamPtr = reinterpret_cast<jlong>(fsOpenStream(volId, targetName));
        }
    }
    env->ReleaseStringUTFChars(targetFileName, targetName);
    return streamPtr;
}

// Note: unlike every other function above, this doesn't call ensureMounted()
// -- matches the original inline version, which also skipped it here and
// went straight to dispatching on fsType. A stream can only exist if
// openStream() already mounted successfully, so re-checking on every read
// would be redundant work on a hot path (media playback).
extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_readStream(
        JNIEnv* env, jobject,
        jlong streamPtr, jlong offset, jbyteArray outBuffer, jint length, jint volId) {
    if (streamPtr == 0 || length <= 0) return -1;
    if (volId < 0 || volId >= MAX_VOLUMES) return -1;

    std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
    jbyte* destBuf = env->GetByteArrayElements(outBuffer, nullptr);
    if (destBuf == nullptr) return -1;
    jint bytesRead = static_cast<jint>(fsReadStream(volId, reinterpret_cast<void*>(streamPtr),
                                                     static_cast<uint64_t>(offset),
                                                     reinterpret_cast<uint8_t*>(destBuf),
                                                     static_cast<size_t>(length)));
    env->ReleaseByteArrayElements(outBuffer, destBuf, 0);
    return bytesRead;
}

extern "C" JNIEXPORT void JNICALL
Java_com_aeidolon_vaultexplorer_VeraCryptEngine_closeStream(
        JNIEnv* env, jobject, jlong streamPtr, jint volId) {
    if (streamPtr == 0) return;
    if (volId < 0 || volId >= MAX_VOLUMES) return;

    std::lock_guard<std::mutex> fsLock(volumes[volId].mutex);
    fsCloseStream(volId, reinterpret_cast<void*>(streamPtr));
}
