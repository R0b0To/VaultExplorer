#include <jni.h>
#include <string>
#include <vector>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <shared_mutex>

#include "archive/archive_engine.h"
#include "filesystems/fs_ops.h"
#include "session/volume_state.h"
#include "session/session_guard.h"
#include "virtual_block_device.h"
#include "jni_bridge_common.h"
#include "jni_callbacks.h"

static jobject buildEntryInfoMap(JNIEnv* env, jclass mapClass, jmethodID mapInit, jmethodID mapPut,
                                 jclass longClass, jmethodID longInit, jclass boolClass, jmethodID boolInit,
                                 jclass intClass, jmethodID intInit, const ArchiveEntryInfo& entry) {
    jobject map = env->NewObject(mapClass, mapInit);

    auto putString = [&](const char* k, const std::string& v) {
        jstring jk = env->NewStringUTF(k);
        jstring jv = env->NewStringUTF(v.c_str());
        env->CallObjectMethod(map, mapPut, jk, jv);
        env->DeleteLocalRef(jk);
        env->DeleteLocalRef(jv);
    };
    auto putLong = [&](const char* k, uint64_t v) {
        jstring jk = env->NewStringUTF(k);
        jobject jv = env->NewObject(longClass, longInit, static_cast<jlong>(v));
        env->CallObjectMethod(map, mapPut, jk, jv);
        env->DeleteLocalRef(jk);
        env->DeleteLocalRef(jv);
    };
    auto putBool = [&](const char* k, bool v) {
        jstring jk = env->NewStringUTF(k);
        jobject jv = env->NewObject(boolClass, boolInit, static_cast<jboolean>(v));
        env->CallObjectMethod(map, mapPut, jk, jv);
        env->DeleteLocalRef(jk);
        env->DeleteLocalRef(jv);
    };
    auto putInt = [&](const char* k, int32_t v) {
        jstring jk = env->NewStringUTF(k);
        jobject jv = env->NewObject(intClass, intInit, static_cast<jint>(v));
        env->CallObjectMethod(map, mapPut, jk, jv);
        env->DeleteLocalRef(jk);
        env->DeleteLocalRef(jv);
    };

    putString("path", entry.path);
    putLong("uncompressedSize", entry.uncompressedSize);
    putLong("compressedSize", entry.compressedSize);
    putLong("modTimeEpochSeconds", static_cast<uint64_t>(entry.modTimeEpochSeconds));
    putBool("isEncrypted", entry.isEncrypted);
    putBool("isDirectory", entry.isDirectory);
    putInt("index", entry.index);

    return map;
}

static jobject buildIndexResultMap(JNIEnv* env, const ArchiveIndexResult& result) {
    jclass mapClass = env->FindClass("java/util/HashMap");
    jmethodID mapInit = env->GetMethodID(mapClass, "<init>", "()V");
    jmethodID mapPut = env->GetMethodID(mapClass, "put",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");

    jclass listClass = env->FindClass("java/util/ArrayList");
    jmethodID listInit = env->GetMethodID(listClass, "<init>", "(I)V");
    jmethodID listAdd = env->GetMethodID(listClass, "add", "(Ljava/lang/Object;)Z");

    jclass intClass = env->FindClass("java/lang/Integer");
    jmethodID intInit = env->GetMethodID(intClass, "<init>", "(I)V");
    jclass longClass = env->FindClass("java/lang/Long");
    jmethodID longInit = env->GetMethodID(longClass, "<init>", "(J)V");
    jclass boolClass = env->FindClass("java/lang/Boolean");
    jmethodID boolInit = env->GetMethodID(boolClass, "<init>", "(Z)V");

    jobject resMap = env->NewObject(mapClass, mapInit);
    jobject entriesList = env->NewObject(listClass, listInit, static_cast<jint>(result.entries.size()));

    for (const auto& e : result.entries) {
        jobject eMap = buildEntryInfoMap(env, mapClass, mapInit, mapPut, longClass, longInit, boolClass, boolInit, intClass, intInit, e);
        env->CallBooleanMethod(entriesList, listAdd, eMap);
        env->DeleteLocalRef(eMap);
    }

    auto putInt = [&](const char* k, int v) {
        jstring jk = env->NewStringUTF(k);
        jobject jv = env->NewObject(intClass, intInit, v);
        env->CallObjectMethod(resMap, mapPut, jk, jv);
        env->DeleteLocalRef(jk);
        env->DeleteLocalRef(jv);
    };
    auto putBool = [&](const char* k, bool v) {
        jstring jk = env->NewStringUTF(k);
        jobject jv = env->NewObject(boolClass, boolInit, static_cast<jboolean>(v));
        env->CallObjectMethod(resMap, mapPut, jk, jv);
        env->DeleteLocalRef(jk);
        env->DeleteLocalRef(jv);
    };
    auto putString = [&](const char* k, const std::string& v) {
        jstring jk = env->NewStringUTF(k);
        jstring jv = env->NewStringUTF(v.c_str());
        env->CallObjectMethod(resMap, mapPut, jk, jv);
        env->DeleteLocalRef(jk);
        env->DeleteLocalRef(jv);
    };

    putInt("status", static_cast<int>(result.status));
    putBool("isSolid", result.isSolid);
    putString("errorMessage", result.errorMessage);

    jstring kEntries = env->NewStringUTF("entries");
    env->CallObjectMethod(resMap, mapPut, kEntries, entriesList);
    env->DeleteLocalRef(kEntries);
    env->DeleteLocalRef(entriesList);

    return resMap;
}

// ── In-Vault Archive Scan ──────────────────────────────────────────────
extern "C" JNIEXPORT jobject JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_archiveScanVaultNative(
        JNIEnv* env, jobject, jint volId, jstring vaultPath, jstring passphrase) {
    JNI_TRY
    if (!requireActiveSession(volId, "archiveScanVault")) {
        throwNotUnlocked(env, volId, "archiveScanVault");
        return nullptr;
    }

    const char* nativePath = env->GetStringUTFChars(vaultPath, nullptr);
    const char* nativePass = passphrase ? env->GetStringUTFChars(passphrase, nullptr) : nullptr;
    std::string passStr = nativePass ? nativePass : "";

    ArchiveIndexResult res;
    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            void* stream = fsOpenStream(volId, nativePath);
            if (!stream) {
                res.status = ArchiveOpenStatus::IoError;
                res.errorMessage = "Failed to open in-vault stream for archive";
            } else {
                uint64_t totalSize = fsGetFileSize(volId, nativePath);
                ArchiveStreamSource source;
                source.size = [totalSize]() { return totalSize; };
                source.read = [volId, stream](uint64_t offset, uint8_t* dest, size_t length) -> int64_t {
                    return fsReadStream(volId, stream, offset, dest, length);
                };
                res = archiveScanEntries(source, passStr);
                fsCloseStream(volId, stream);
            }
        }
    }

    env->ReleaseStringUTFChars(vaultPath, nativePath);
    if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);

    return buildIndexResultMap(env, res);
    JNI_CATCH_RETURN(nullptr)
}

// ── In-Vault Single-Entry Extract ──────────────────────────────────────
extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_archiveExtractVaultEntryNative(
        JNIEnv* env, jobject, jint volId, jstring vaultPath, jint targetIndex, jstring passphrase) {
    JNI_TRY
    if (!requireActiveSession(volId, "archiveExtractVaultEntry")) {
        throwNotUnlocked(env, volId, "archiveExtractVaultEntry");
        return nullptr;
    }

    const char* nativePath = env->GetStringUTFChars(vaultPath, nullptr);
    const char* nativePass = passphrase ? env->GetStringUTFChars(passphrase, nullptr) : nullptr;
    std::string passStr = nativePass ? nativePass : "";

    ArchiveExtractResult res;
    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            void* stream = fsOpenStream(volId, nativePath);
            if (!stream) {
                res.status = ArchiveOpenStatus::IoError;
            } else {
                uint64_t totalSize = fsGetFileSize(volId, nativePath);
                ArchiveStreamSource source;
                source.size = [totalSize]() { return totalSize; };
                source.read = [volId, stream](uint64_t offset, uint8_t* dest, size_t length) -> int64_t {
                    return fsReadStream(volId, stream, offset, dest, length);
                };
                res = archiveExtractEntry(source, targetIndex, passStr);
                fsCloseStream(volId, stream);
            }
        }
    }

    env->ReleaseStringUTFChars(vaultPath, nativePath);
    if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);

    if (res.status != ArchiveOpenStatus::Ok || res.data.empty()) {
        return nullptr;
    }

    jbyteArray bytes = env->NewByteArray(static_cast<jsize>(res.data.size()));
    env->SetByteArrayRegion(bytes, 0, static_cast<jsize>(res.data.size()), reinterpret_cast<const jbyte*>(res.data.data()));
    return bytes;
    JNI_CATCH_RETURN(nullptr)
}

static void ensureParentDirs(int volId, const std::string& path) {
    size_t pos = 0;
    while ((pos = path.find('/', pos)) != std::string::npos) {
        if (pos > 0) {
            std::string sub = path.substr(0, pos);
            fsCreateDirectory(volId, sub);
        }
        pos++;
    }
}

static jobject buildBulkExtractResultMap(JNIEnv* env, const ArchiveBulkExtractResult& result) {
    jclass mapClass = env->FindClass("java/util/HashMap");
    jmethodID mapInit = env->GetMethodID(mapClass, "<init>", "()V");
    jmethodID mapPut = env->GetMethodID(mapClass, "put",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");

    jclass intClass = env->FindClass("java/lang/Integer");
    jmethodID intInit = env->GetMethodID(intClass, "<init>", "(I)V");

    jobject resMap = env->NewObject(mapClass, mapInit);

    auto putInt = [&](const char* k, int v) {
        jstring jk = env->NewStringUTF(k);
        jobject jv = env->NewObject(intClass, intInit, v);
        env->CallObjectMethod(resMap, mapPut, jk, jv);
        env->DeleteLocalRef(jk);
        env->DeleteLocalRef(jv);
    };
    auto putString = [&](const char* k, const std::string& v) {
        jstring jk = env->NewStringUTF(k);
        jstring jv = env->NewStringUTF(v.c_str());
        env->CallObjectMethod(resMap, mapPut, jk, jv);
        env->DeleteLocalRef(jk);
        env->DeleteLocalRef(jv);
    };

    putInt("status", static_cast<int>(result.status));
    putInt("extractedCount", result.extractedCount);
    putString("errorMessage", result.errorMessage);

    return resMap;
}

// ── In-Vault Bulk Extract to Vault Folder ──────────────────────────────
extern "C" JNIEXPORT jobject JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_archiveExtractVaultAllNative(
        JNIEnv* env, jobject, jint volId, jstring vaultPath, jstring destDirPath,
        jstring subPath, jstring passphrase, jint opId) {
    JNI_TRY
    if (!requireActiveSession(volId, "archiveExtractVaultAll")) {
        throwNotUnlocked(env, volId, "archiveExtractVaultAll");
        return nullptr;
    }

    const char* nativePath = env->GetStringUTFChars(vaultPath, nullptr);
    const char* nativeDestDir = destDirPath ? env->GetStringUTFChars(destDirPath, nullptr) : nullptr;
    const char* nativeSubPath = subPath ? env->GetStringUTFChars(subPath, nullptr) : nullptr;
    const char* nativePass = passphrase ? env->GetStringUTFChars(passphrase, nullptr) : nullptr;

    std::string targetDirPath = nativeDestDir ? nativeDestDir : "";
    std::string subPathStr = nativeSubPath ? nativeSubPath : "";
    std::string passStr = nativePass ? nativePass : "";

    while (!targetDirPath.empty() && targetDirPath.front() == '/') targetDirPath.erase(targetDirPath.begin());
    while (!targetDirPath.empty() && targetDirPath.back() == '/') targetDirPath.pop_back();

    ArchiveBulkExtractResult res;
    void* stream = nullptr;
    uint64_t totalSize = 0;

    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        if (ensureMounted(volId)) {
            stream = fsOpenStream(volId, nativePath);
            if (stream) {
                totalSize = fsGetFileSize(volId, nativePath);
            }
        }
    }

    if (!stream) {
        res.status = ArchiveOpenStatus::IoError;
        res.errorMessage = "Failed to open archive stream in vault";
    } else {
        ArchiveStreamSource source;
        source.size = [totalSize]() { return totalSize; };
        source.read = [volId, stream](uint64_t offset, uint8_t* dest, size_t length) -> int64_t {
            std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
            return fsReadStream(volId, stream, offset, dest, length);
        };

        auto makeDir = [volId, targetDirPath](const std::string& relPath) -> bool {
            std::string fullDest = targetDirPath.empty() ? relPath : (targetDirPath + "/" + relPath);
            std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
            ensureParentDirs(volId, fullDest);
            return fsCreateDirectory(volId, fullDest);
        };

        auto writeFileChunk = [volId, targetDirPath](const std::string& relPath, uint64_t offset, const uint8_t* data, size_t length) -> bool {
            std::string fullDest = targetDirPath.empty() ? relPath : (targetDirPath + "/" + relPath);
            std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
            if (offset == 0) {
                ensureParentDirs(volId, fullDest);
            }
            return fsWriteFileChunk(volId, fullDest, offset, data, length);
        };

        auto progressCb = [opId](int32_t count, const std::string&) -> bool {
            if (opId > 0) {
                reportSplitJoinProgress(opId, count, 0);
                if (isSplitJoinCancelled(opId) || isCopyCancelled(opId)) return false;
            }
            return true;
        };

        res = archiveExtractAll(source, passStr, subPathStr, makeDir, writeFileChunk, progressCb);

        {
            std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
            fsCloseStream(volId, stream);
        }
    }

    env->ReleaseStringUTFChars(vaultPath, nativePath);
    if (destDirPath && nativeDestDir) env->ReleaseStringUTFChars(destDirPath, nativeDestDir);
    if (subPath && nativeSubPath) env->ReleaseStringUTFChars(subPath, nativeSubPath);
    if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);

    return buildBulkExtractResultMap(env, res);
    JNI_CATCH_RETURN(nullptr)
}

// ── Local File Bulk Extract to Vault Folder ────────────────────────────
extern "C" JNIEXPORT jobject JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_archiveExtractFdToVaultNative(
        JNIEnv* env, jobject, jint fd, jint destVolId, jstring destDirPath,
        jstring subPath, jstring passphrase, jint opId) {
    JNI_TRY
    if (fd < 0 || !requireActiveSession(destVolId, "archiveExtractFdToVault")) {
        throwNotUnlocked(env, destVolId, "archiveExtractFdToVault");
        return nullptr;
    }

    const char* nativeDestDir = destDirPath ? env->GetStringUTFChars(destDirPath, nullptr) : nullptr;
    const char* nativeSubPath = subPath ? env->GetStringUTFChars(subPath, nullptr) : nullptr;
    const char* nativePass = passphrase ? env->GetStringUTFChars(passphrase, nullptr) : nullptr;

    std::string targetDirPath = nativeDestDir ? nativeDestDir : "";
    std::string subPathStr = nativeSubPath ? nativeSubPath : "";
    std::string passStr = nativePass ? nativePass : "";

    while (!targetDirPath.empty() && targetDirPath.front() == '/') targetDirPath.erase(targetDirPath.begin());
    while (!targetDirPath.empty() && targetDirPath.back() == '/') targetDirPath.pop_back();

    struct stat st;
    if (fstat(fd, &st) != 0) {
        if (destDirPath && nativeDestDir) env->ReleaseStringUTFChars(destDirPath, nativeDestDir);
        if (subPath && nativeSubPath) env->ReleaseStringUTFChars(subPath, nativeSubPath);
        if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);
        return nullptr;
    }

    uint64_t totalSize = static_cast<uint64_t>(st.st_size);
    ArchiveStreamSource source;
    source.size = [totalSize]() { return totalSize; };
    source.read = [fd](uint64_t offset, uint8_t* dest, size_t length) -> int64_t {
        ssize_t n = pread(fd, dest, length, static_cast<off_t>(offset));
        return static_cast<int64_t>(n);
    };

    auto makeDir = [destVolId, targetDirPath](const std::string& relPath) -> bool {
        std::string fullDest = targetDirPath.empty() ? relPath : (targetDirPath + "/" + relPath);
        std::unique_lock<std::shared_mutex> fsLock(volumes[destVolId].mutex);
        ensureParentDirs(destVolId, fullDest);
        return fsCreateDirectory(destVolId, fullDest);
    };

    auto writeFileChunk = [destVolId, targetDirPath](const std::string& relPath, uint64_t offset, const uint8_t* data, size_t length) -> bool {
        std::string fullDest = targetDirPath.empty() ? relPath : (targetDirPath + "/" + relPath);
        std::unique_lock<std::shared_mutex> fsLock(volumes[destVolId].mutex);
        if (offset == 0) {
            ensureParentDirs(destVolId, fullDest);
        }
        return fsWriteFileChunk(destVolId, fullDest, offset, data, length);
    };

    auto progressCb = [opId](int32_t count, const std::string&) -> bool {
        if (opId > 0) {
            reportSplitJoinProgress(opId, count, 0);
            if (isSplitJoinCancelled(opId) || isCopyCancelled(opId)) return false;
        }
        return true;
    };

    ArchiveBulkExtractResult res = archiveExtractAll(source, passStr, subPathStr, makeDir, writeFileChunk, progressCb);

    if (destDirPath && nativeDestDir) env->ReleaseStringUTFChars(destDirPath, nativeDestDir);
    if (subPath && nativeSubPath) env->ReleaseStringUTFChars(subPath, nativeSubPath);
    if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);

    return buildBulkExtractResultMap(env, res);
    JNI_CATCH_RETURN(nullptr)
}

// ── Local File Archive Scan ────────────────────────────────────────────
extern "C" JNIEXPORT jobject JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_archiveScanFdNative(
        JNIEnv* env, jobject, jint fd, jstring passphrase) {
    JNI_TRY
    if (fd < 0) return nullptr;

    const char* nativePass = passphrase ? env->GetStringUTFChars(passphrase, nullptr) : nullptr;
    std::string passStr = nativePass ? nativePass : "";

    struct stat st;
    if (fstat(fd, &st) != 0) {
        if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);
        return nullptr;
    }

    uint64_t totalSize = static_cast<uint64_t>(st.st_size);
    ArchiveStreamSource source;
    source.size = [totalSize]() { return totalSize; };
    source.read = [fd](uint64_t offset, uint8_t* dest, size_t length) -> int64_t {
        ssize_t n = pread(fd, dest, length, static_cast<off_t>(offset));
        return static_cast<int64_t>(n);
    };

    ArchiveIndexResult res = archiveScanEntries(source, passStr);

    if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);
    return buildIndexResultMap(env, res);
    JNI_CATCH_RETURN(nullptr)
}

// ── Local File Single-Entry Extract ────────────────────────────────────
extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_archiveExtractFdEntryNative(
        JNIEnv* env, jobject, jint fd, jint targetIndex, jstring passphrase) {
    JNI_TRY
    if (fd < 0) return nullptr;

    const char* nativePass = passphrase ? env->GetStringUTFChars(passphrase, nullptr) : nullptr;
    std::string passStr = nativePass ? nativePass : "";

    struct stat st;
    if (fstat(fd, &st) != 0) {
        if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);
        return nullptr;
    }

    uint64_t totalSize = static_cast<uint64_t>(st.st_size);
    ArchiveStreamSource source;
    source.size = [totalSize]() { return totalSize; };
    source.read = [fd](uint64_t offset, uint8_t* dest, size_t length) -> int64_t {
        ssize_t n = pread(fd, dest, length, static_cast<off_t>(offset));
        return static_cast<int64_t>(n);
    };

    ArchiveExtractResult res = archiveExtractEntry(source, targetIndex, passStr);

    if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);
    if (res.status != ArchiveOpenStatus::Ok || res.data.empty()) return nullptr;

    jbyteArray bytes = env->NewByteArray(static_cast<jsize>(res.data.size()));
    env->SetByteArrayRegion(bytes, 0, static_cast<jsize>(res.data.size()), reinterpret_cast<const jbyte*>(res.data.data()));
    return bytes;
    JNI_CATCH_RETURN(nullptr)
}

// ── Create Archive: In-Vault Files -> Local File Descriptor ────────────
extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_archiveCreateVaultToFdNative(
        JNIEnv* env, jobject,
        jint srcVolId, jobjectArray vaultPaths, jobjectArray entryNames,
        jint destFd, jint format, jstring passphrase, jint opId) {
    JNI_TRY
    if (destFd < 0 || !vaultPaths || !entryNames) return JNI_FALSE;
    if (!requireActiveSession(srcVolId, "archiveCreateVaultToFd")) {
        throwNotUnlocked(env, srcVolId, "archiveCreateVaultToFd");
        return JNI_FALSE;
    }

    const jsize count = env->GetArrayLength(vaultPaths);
    const char* nativePass = passphrase ? env->GetStringUTFChars(passphrase, nullptr) : nullptr;
    std::string passStr = nativePass ? nativePass : "";

    std::vector<std::string> vPaths(count);
    std::vector<std::string> inArchivePaths(count);
    for (jsize i = 0; i < count; i++) {
        jstring jvp = static_cast<jstring>(env->GetObjectArrayElement(vaultPaths, i));
        jstring jnp = static_cast<jstring>(env->GetObjectArrayElement(entryNames, i));
        const char* vp = env->GetStringUTFChars(jvp, nullptr);
        const char* np = env->GetStringUTFChars(jnp, nullptr);
        vPaths[i] = vp;
        inArchivePaths[i] = np;
        env->ReleaseStringUTFChars(jvp, vp);
        env->ReleaseStringUTFChars(jnp, np);
        env->DeleteLocalRef(jvp);
        env->DeleteLocalRef(jnp);
    }

    uint64_t destOffset = 0;
    ArchiveSink sink;
    sink.write = [destFd, &destOffset](const uint8_t* data, size_t length) -> int64_t {
        ssize_t n = pwrite(destFd, data, length, static_cast<off_t>(destOffset));
        if (n < 0 || static_cast<size_t>(n) != length) return -1;
        destOffset += length;
        return static_cast<int64_t>(n);
    };

    std::vector<ArchiveSourceEntry> entries(count);
    std::vector<void*> openStreams(count, nullptr);
    std::vector<uint64_t> streamOffsets(count, 0);

    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[srcVolId].mutex);
        if (!ensureMounted(srcVolId)) {
            if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);
            return JNI_FALSE;
        }

        for (jsize i = 0; i < count; i++) {
            entries[i].pathInArchive = inArchivePaths[i];
            entries[i].uncompressedSize = fsGetFileSize(srcVolId, vPaths[i]);
            entries[i].isDirectory = false; // Filesystems list directories separately or size 0

            void* stream = fsOpenStream(srcVolId, vPaths[i]);
            openStreams[i] = stream;

            entries[i].readData = [srcVolId, stream, &streamOffsets, i](uint8_t* dest, size_t length) -> int64_t {
                if (!stream) return -1;
                int32_t n = fsReadStream(srcVolId, stream, streamOffsets[i], dest, length);
                if (n > 0) streamOffsets[i] += static_cast<uint64_t>(n);
                return n;
            };
        }
    }

    auto progressCb = [opId](uint64_t bytesWritten) -> bool {
        if (opId > 0) {
            reportSplitJoinProgress(opId, bytesWritten, 0);
            if (isSplitJoinCancelled(opId) || isCopyCancelled(opId)) return false;
        }
        return true;
    };

    ArchiveCreateResult res = archiveCreate(
        sink, static_cast<ArchiveFormat>(format), entries, passStr, progressCb
    );

    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[srcVolId].mutex);
        for (void* s : openStreams) {
            if (s) fsCloseStream(srcVolId, s);
        }
    }

    if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);
    return (res.status == ArchiveOpenStatus::Ok) ? JNI_TRUE : JNI_FALSE;
    JNI_CATCH_RETURN(JNI_FALSE)
}

// ── Create Archive: In-Vault Files -> In-Vault Target File ─────────────
extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_archiveCreateVaultToVaultNative(
        JNIEnv* env, jobject,
        jint srcVolId, jobjectArray vaultPaths, jobjectArray entryNames,
        jint destVolId, jstring destVaultPath, jint format, jstring passphrase, jint opId) {
    JNI_TRY
    if (!vaultPaths || !entryNames || !destVaultPath) return JNI_FALSE;
    if (!requireActiveSession(srcVolId, "archiveCreateVaultToVault (src)") ||
        !requireActiveSession(destVolId, "archiveCreateVaultToVault (dest)")) {
        throwNotUnlocked(env, srcVolId, "archiveCreateVaultToVault");
        return JNI_FALSE;
    }

    const jsize count = env->GetArrayLength(vaultPaths);
    const char* nativeDestPath = env->GetStringUTFChars(destVaultPath, nullptr);
    const char* nativePass = passphrase ? env->GetStringUTFChars(passphrase, nullptr) : nullptr;
    std::string passStr = nativePass ? nativePass : "";
    std::string targetVaultPath = nativeDestPath;

    std::vector<std::string> vPaths(count);
    std::vector<std::string> inArchivePaths(count);
    for (jsize i = 0; i < count; i++) {
        jstring jvp = static_cast<jstring>(env->GetObjectArrayElement(vaultPaths, i));
        jstring jnp = static_cast<jstring>(env->GetObjectArrayElement(entryNames, i));
        const char* vp = env->GetStringUTFChars(jvp, nullptr);
        const char* np = env->GetStringUTFChars(jnp, nullptr);
        vPaths[i] = vp;
        inArchivePaths[i] = np;
        env->ReleaseStringUTFChars(jvp, vp);
        env->ReleaseStringUTFChars(jnp, np);
        env->DeleteLocalRef(jvp);
        env->DeleteLocalRef(jnp);
    }

    uint64_t destOffset = 0;
    ArchiveSink sink;
    sink.write = [destVolId, targetVaultPath, &destOffset](const uint8_t* data, size_t length) -> int64_t {
        std::unique_lock<std::shared_mutex> fsLock(volumes[destVolId].mutex);
        bool ok = fsWriteFileChunk(destVolId, targetVaultPath, destOffset, data, length);
        if (!ok) return -1;
        destOffset += length;
        return static_cast<int64_t>(length);
    };

    std::vector<ArchiveSourceEntry> entries(count);
    std::vector<void*> openStreams(count, nullptr);
    std::vector<uint64_t> streamOffsets(count, 0);

    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[srcVolId].mutex);
        if (!ensureMounted(srcVolId)) {
            env->ReleaseStringUTFChars(destVaultPath, nativeDestPath);
            if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);
            return JNI_FALSE;
        }

        for (jsize i = 0; i < count; i++) {
            entries[i].pathInArchive = inArchivePaths[i];
            entries[i].uncompressedSize = fsGetFileSize(srcVolId, vPaths[i]);
            entries[i].isDirectory = false;

            void* stream = fsOpenStream(srcVolId, vPaths[i]);
            openStreams[i] = stream;

            entries[i].readData = [srcVolId, stream, &streamOffsets, i](uint8_t* dest, size_t length) -> int64_t {
                if (!stream) return -1;
                std::unique_lock<std::shared_mutex> streamLock(volumes[srcVolId].mutex);
                int32_t n = fsReadStream(srcVolId, stream, streamOffsets[i], dest, length);
                if (n > 0) streamOffsets[i] += static_cast<uint64_t>(n);
                return n;
            };
        }
    }

    auto progressCb = [opId](uint64_t bytesWritten) -> bool {
        if (opId > 0) {
            reportSplitJoinProgress(opId, bytesWritten, 0);
            if (isSplitJoinCancelled(opId) || isCopyCancelled(opId)) return false;
        }
        return true;
    };

    ArchiveCreateResult res = archiveCreate(
        sink, static_cast<ArchiveFormat>(format), entries, passStr, progressCb
    );

    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[srcVolId].mutex);
        for (void* s : openStreams) {
            if (s) fsCloseStream(srcVolId, s);
        }
    }

    env->ReleaseStringUTFChars(destVaultPath, nativeDestPath);
    if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);
    return (res.status == ArchiveOpenStatus::Ok) ? JNI_TRUE : JNI_FALSE;
    JNI_CATCH_RETURN(JNI_FALSE)
}

// ── Create Archive: Local Files -> Local File Descriptor ───────────────
extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_archiveCreateLocalToFdNative(
        JNIEnv* env, jobject,
        jobjectArray localPaths, jobjectArray entryNames,
        jint destFd, jint format, jstring passphrase, jint opId) {
    JNI_TRY
    if (destFd < 0 || !localPaths || !entryNames) return JNI_FALSE;

    const jsize count = env->GetArrayLength(localPaths);
    const char* nativePass = passphrase ? env->GetStringUTFChars(passphrase, nullptr) : nullptr;
    std::string passStr = nativePass ? nativePass : "";

    std::vector<std::string> lPaths(count);
    std::vector<std::string> inArchivePaths(count);
    for (jsize i = 0; i < count; i++) {
        jstring jlp = static_cast<jstring>(env->GetObjectArrayElement(localPaths, i));
        jstring jnp = static_cast<jstring>(env->GetObjectArrayElement(entryNames, i));
        const char* lp = env->GetStringUTFChars(jlp, nullptr);
        const char* np = env->GetStringUTFChars(jnp, nullptr);
        lPaths[i] = lp;
        inArchivePaths[i] = np;
        env->ReleaseStringUTFChars(jlp, lp);
        env->ReleaseStringUTFChars(jnp, np);
        env->DeleteLocalRef(jlp);
        env->DeleteLocalRef(jnp);
    }

    uint64_t destOffset = 0;
    ArchiveSink sink;
    sink.write = [destFd, &destOffset](const uint8_t* data, size_t length) -> int64_t {
        ssize_t n = pwrite(destFd, data, length, static_cast<off_t>(destOffset));
        if (n < 0 || static_cast<size_t>(n) != length) return -1;
        destOffset += length;
        return static_cast<int64_t>(n);
    };

    std::vector<ArchiveSourceEntry> entries(count);
    std::vector<int> openFds(count, -1);
    std::vector<uint64_t> readOffsets(count, 0);

    for (jsize i = 0; i < count; i++) {
        entries[i].pathInArchive = inArchivePaths[i];

        struct stat st;
        if (stat(lPaths[i].c_str(), &st) == 0) {
            entries[i].isDirectory = S_ISDIR(st.st_mode);
            entries[i].uncompressedSize = entries[i].isDirectory ? 0 : static_cast<uint64_t>(st.st_size);
            entries[i].modTimeEpochSeconds = static_cast<int64_t>(st.st_mtime);

            if (!entries[i].isDirectory) {
                int sfd = open(lPaths[i].c_str(), O_RDONLY);
                openFds[i] = sfd;
                entries[i].readData = [&openFds, &readOffsets, i](uint8_t* dest, size_t length) -> int64_t {
                    int sfd = openFds[i];
                    if (sfd < 0) return -1;
                    ssize_t n = pread(sfd, dest, length, static_cast<off_t>(readOffsets[i]));
                    if (n > 0) readOffsets[i] += static_cast<uint64_t>(n);
                    return static_cast<int64_t>(n);
                };
            }
        }
    }

    auto progressCb = [opId](uint64_t bytesWritten) -> bool {
        if (opId > 0) {
            reportSplitJoinProgress(opId, bytesWritten, 0);
            if (isSplitJoinCancelled(opId) || isCopyCancelled(opId)) return false;
        }
        return true;
    };

    ArchiveCreateResult res = archiveCreate(
        sink, static_cast<ArchiveFormat>(format), entries, passStr, progressCb
    );

    for (int sfd : openFds) {
        if (sfd >= 0) close(sfd);
    }

    if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);
    return (res.status == ArchiveOpenStatus::Ok) ? JNI_TRUE : JNI_FALSE;
    JNI_CATCH_RETURN(JNI_FALSE)
}