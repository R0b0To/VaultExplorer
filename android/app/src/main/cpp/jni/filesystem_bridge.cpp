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
        std::shared_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMountedShared(volId, fsLock)) {
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
        std::shared_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMountedShared(volId, fsLock)) {
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
        std::shared_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMountedShared(volId, fsLock)) {
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
        std::shared_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMountedShared(volId, fsLock)) {
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
    // len == 0 is legitimate: it's how createEmptyFile() creates a new,
    // empty file (offset 0, zero-byte chunk) before finishWrite(). Only
    // reject a corrupt/negative length or one over the chunk cap.
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
            // Same JNI-boundary pattern as copyFile's callback (see the
            // comment there): the only place this touches JNI. Targets a
            // different Kotlin bridge (ImportProgressBridge/ImportCancellation
            // via reportImportChunkProgress/isImportCancelled) than copyFile's
            // (CopyProgressBridge/CopyCancellation via reportCopyProgress/
            // isCopyCancelled) because opId is a single shared numbering
            // space across every FileOperation kind -- native can't tell a
            // copy's opId from an import's opId by value alone, only by
            // which JNI entry point it arrived through.
            //
            // Lock-yield addendum: fatWriteBackFile/ntfsWriteBackFile/
            // extWriteBackFile each loop over ~2MB chunks and call this
            // callback once per chunk (see copy_progress_callback.h) while
            // fsLock is held exclusively for the *entire* multi-chunk
            // transfer -- that's what stalls listDirectory and every other
            // reader behind a large import for the whole transfer instead
            // of just a couple milliseconds. Since this callback is the one
            // JNI-reachable point inside that per-chunk loop, it's also the
            // one place that can hand the mutex to a queued reader between
            // chunks without threading a lock reference through fs_ops.h /
            // the three backends (which are deliberately lock-agnostic --
            // see fs_ops.h's header comment).
            //
            // This isn't the only lock in play, though: ContainerFileSystem
            // .writeBackFile (Kotlin) wraps this *entire* JNI call in
            // withWriteLock -- a ReentrantReadWriteLock acquired before we
            // were ever called and held until we return -- and that's what
            // listDirectory's withReadLock actually queues behind, not
            // fsLock. Yielding fsLock alone doesn't unblock a reader stuck
            // at the Kotlin layer, since it never gets far enough to reach
            // fsLock in the first place. So each chunk yields *both* locks,
            // outer-to-inner order preserved on the way back down:
            // yieldContainerWriteLock() is the Kotlin-side counterpart
            // (ContainerSessionRegistry.yieldWriteLockBriefly) -- see
            // jni_callbacks.h.
            //
            // Correctness note: fs_ops.h's stated precondition is that the
            // caller holds fsLock for the whole call. Unlocking here breaks
            // that for the width of one chunk, for both locks. That's safe
            // with respect to queued *readers* (listDirectory etc. only
            // look, never mutate volumes[volId] or the backend's on-disk
            // structures). It is not fully safe against another queued
            // *writer* interleaving a structural change (delete/rename/
            // etc.) on the same volume while this call's ntfs_attr/
            // ext2_file_t/FIL handle is still open underneath us -- the
            // app's single-FileOperation-at-a-time model (FileOperation
            // Service's _queue) means that shouldn't happen in practice,
            // but it isn't enforced at this layer. Re-running ensureMounted()
            // after each reacquire only catches the unmount/session-close
            // case, not a concurrent structural write from some other code
            // path.
            success = fsWriteBackFile(volId, targetName, source,
                [opId, volId, &fsLock](uint64_t bytesWritten) -> bool {
                    reportImportChunkProgress(opId, bytesWritten);
                    if (isImportCancelled(opId)) return false;

                    // Unwind inner-to-outer (C++ mutex, then Kotlin lock),
                    // rewind outer-to-inner. This thread must never hold
                    // fsLock without also holding the Kotlin write lock,
                    // since every other native call for this backend
                    // assumes that nesting (ContainerFileSystem.kt always
                    // takes its lock before calling into JNI).
                    fsLock.unlock();
                    yieldContainerWriteLock(volId);
                    fsLock.lock();

                    // Re-validate rather than trust stale state: the volume
                    // could have been unmounted/locked while we held
                    // neither lock. ensureMounted() is cheap on the common
                    // (already-mounted) path -- see virtual_block_device.h.
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
        // Shared, not exclusive: this only reads the mounted volume --
        // fsExtractFile copies bytes out to destHostPath, a path outside
        // the vault (Android storage), and never mutates VolumeState or
        // the mounted filesystem's on-disk structures.
        std::shared_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMountedShared(volId, fsLock)) {
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
        // Dest is always exclusive (it's being written to). When src and
        // dest are the same volume, a single exclusive lock must cover
        // both -- src can't be taken shared while dest holds exclusive on
        // the same shared_mutex (and taking the same shared_mutex twice
        // from one thread, shared then exclusive or vice versa, is
        // undefined behavior/deadlock-prone regardless). Only when they're
        // genuinely different volumes can src be shared, letting a
        // same-volume copy's read side run alongside other volumes'
        // concurrent readers instead of blocking them.
        const bool sameVolume = (srcVolId == destVolId);
        std::unique_lock<std::shared_mutex> destLock(volumes[destVolId].mutex, std::defer_lock);
        std::shared_lock<std::shared_mutex> srcSharedLock(volumes[srcVolId].mutex, std::defer_lock);
        if (sameVolume) {
            destLock.lock();
        } else {
            srcSharedLock.lock();
            destLock.lock();
        }
        const bool srcMounted = sameVolume ? ensureMounted(srcVolId)
                                            : ensureMountedShared(srcVolId, srcSharedLock);
        if (srcMounted && ensureMounted(destVolId)) {
            // The only place this call touches JNI: fs_ops.cpp/fat_backend.cpp/
            // ntfs_backend.cpp/ext_backend.cpp just invoke whatever
            // CopyProgressCallback they're handed, so they stay JNI-free (see
            // copy_progress_callback.h). Runs on this same thread, synchronously,
            // once per existing 2 MB buffer iteration -- no extra round trips.
            // Returning false aborts the copy exactly like an I/O error would
            // (partial dest file gets cleaned up by the existing !ok path).
            //
            // Lock-yield addendum, mirroring writeBackFile: without
            // periodically dropping both this C++ lock pair and the
            // Kotlin-level lock that ContainerFileSystem.copyFile holds for
            // this entire JNI call, a large copy keeps dest exclusive (and
            // src shared) for the whole transfer, and every reader on
            // either volume -- listDirectory chief among them -- queues
            // behind it until the file finishes. yieldContainerCopyLocks()
            // is the Kotlin-side counterpart (ContainerSessionRegistry.
            // yieldCopyLocksBriefly); see the comment there for the full
            // story. Unwind inner-to-outer (dest was locked last above, so
            // it's dropped first), rewind outer-to-inner (src first, dest
            // second) -- the same order acquired above, so a paused copy
            // can't observe a different lock order than the one every copy
            // starts with.
            success = fsCopyFile(srcVolId, nativeSrc, destVolId, nativeDest,
                [opId, srcVolId, destVolId, sameVolume, &destLock, &srcSharedLock]
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
                    srcSharedLock.unlock();
                    yieldContainerCopyLocks(srcVolId, destVolId);
                    srcSharedLock.lock();
                    destLock.lock();

                    return ensureMountedShared(srcVolId, srcSharedLock) && ensureMounted(destVolId);
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
        std::shared_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMountedShared(volId, fsLock)) {
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
// Deliberately does NOT call ensureMounted(): every field read here comes
// from the crypto/session layer (VolumeState), not the mounted filesystem,
// so this stays valid even for a format this app can unlock but whose
// filesystem type isn't recognized.
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
    {
        std::shared_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        const VolumeState& v = volumes[volId];
        format = v.containerFormat;
        isHidden = v.isHiddenVolume;
        readOnly = v.readOnly;
        volumeSize = v.dataAreaLengthBytes;
        cipherId = v.matchedCipherId;
        hashId = v.matchedHashId;
        sectorSize = v.luksSectorSize;
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

    putBool("readOnly", readOnly);
    putLong("volumeSizeBytes", static_cast<int64_t>(volumeSize));

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
            // cipher/version fields -- readOnly/volumeSizeBytes above are
            // all that's available for this format.
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