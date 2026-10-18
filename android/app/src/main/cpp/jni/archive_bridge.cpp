#include <jni.h>
#include <string>
#include <vector>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <shared_mutex>
#include <cerrno>
#include <climits>
#include <dirent.h>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>

#include "archive/archive_engine.h"
#include "filesystems/fs_ops.h"
#define DIR FatFs_DIR
#include "session/volume_state.h"
#include "session/session_guard.h"
#undef DIR
#include "virtual_block_device.h"
#include "jni_bridge_common.h"
#include "jni_callbacks.h"

// ── Helper Functions & Builders ────────────────────────────────────────

static void logArchiveFailure(const char* operation, ArchiveOpenStatus status,
                              const std::string& errorMessage) {
    if (status == ArchiveOpenStatus::Ok) return;
    __android_log_print(ANDROID_LOG_ERROR, "VaultExplorer_Archive",
                        "%s failed (status=%d): %s", operation,
                        static_cast<int>(status),
                        errorMessage.empty() ? "<no native error message>" : errorMessage.c_str());
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

static bool readModifiedSecs(JNIEnv* env, jlongArray modifiedSecs, jsize count,
                             std::vector<int64_t>& out) {
    if (!modifiedSecs || env->GetArrayLength(modifiedSecs) != count) return false;
    std::vector<jlong> sourceTimes(count);
    env->GetLongArrayRegion(modifiedSecs, 0, count, sourceTimes.data());
    if (env->ExceptionCheck()) return false;
    out.resize(count);
    for (jsize i = 0; i < count; ++i) {
        out[i] = static_cast<int64_t>(sourceTimes[i]);
    }
    return true;
}

// ── Archives that are split into parts ──────────────────────────────────
// Opening any part of a split archive (name.7z.001, name.z01 + name.zip, ...) must open the
// whole set, so every reader goes through these instead of building a one-file source. All the
// recognition and joining lives in the engine (archiveOpenPartSet); this only supplies "list the
// folder" and "open a sibling" for a device folder or a vault.

// Descriptors opened for sibling parts; closed when the last copy of the source goes away.
struct OpenedPartFds {
    std::vector<int> fds;
    ~OpenedPartFds() {
        for (int f : fds) ::close(f);
    }
};

static ArchiveStreamSource singleFdSource(int fd, uint64_t totalSize) {
    ArchiveStreamSource source;
    source.size = [totalSize]() { return totalSize; };
    source.read = [fd](uint64_t offset, uint8_t* dest, size_t length) -> int64_t {
        return static_cast<int64_t>(::pread(fd, dest, length, static_cast<off_t>(offset)));
    };
    return source;
}

// Source for an archive file opened by descriptor. If that file is a part of a split archive that
// lives in a device folder, the result covers the whole set; when the set is incomplete the
// message goes to `partSetError` (if given) and the single file is returned.
static ArchiveStreamSource archiveSourceForFd(int fd, uint64_t totalSize, std::string* partSetError) {
    ArchiveStreamSource single = singleFdSource(fd, totalSize);

    char link[64];
    std::snprintf(link, sizeof(link), "/proc/self/fd/%d", fd);
    char target[PATH_MAX];
    const ssize_t len = ::readlink(link, target, sizeof(target) - 1);
    if (len <= 0) return single;  // not a real path (pipe, proxy fd, ...)
    const std::string path(target, static_cast<size_t>(len));
    const size_t slash = path.rfind('/');
    if (path[0] != '/' || slash == std::string::npos) return single;
    const std::string dir = path.substr(0, slash);
    const std::string name = path.substr(slash + 1);

    auto opened = std::make_shared<OpenedPartFds>();
    ArchivePartSetEnv partEnv;
    partEnv.listSiblings = [dir]() {
        std::vector<std::string> names;
        if (DIR* d = ::opendir(dir.c_str())) {
            while (const dirent* e = ::readdir(d)) {
                if (e->d_type != DT_DIR) names.emplace_back(e->d_name);
            }
            ::closedir(d);
        }
        return names;
    };
    partEnv.openSibling = [dir, opened](const std::string& siblingName, ArchiveStreamSource* out) {
        const int f = ::open((dir + "/" + siblingName).c_str(), O_RDONLY | O_CLOEXEC);
        if (f < 0) return false;
        struct stat st;
        if (::fstat(f, &st) != 0) {
            ::close(f);
            return false;
        }
        opened->fds.push_back(f);
        *out = singleFdSource(f, static_cast<uint64_t>(st.st_size));
        return true;
    };

    ArchiveStreamSource joined;
    std::string error;
    switch (archiveOpenPartSet(name, partEnv, &joined, &error)) {
        case ArchivePartSetStatus::Opened: {
            // The sibling descriptors must live exactly as long as the source.
            auto sizeFn = joined.size;
            auto readFn = joined.read;
            joined.size = [sizeFn, opened]() { return sizeFn(); };
            joined.read = [readFn, opened](uint64_t off, uint8_t* dest, size_t n) { return readFn(off, dest, n); };
            return joined;
        }
        case ArchivePartSetStatus::Missing:
            if (partSetError) *partSetError = error;
            return single;
        case ArchivePartSetStatus::NotASet:
            break;
    }
    return single;
}

// Same for an archive inside an unlocked vault. Streams opened for sibling parts are collected so the
// caller can close them (while holding the volume lock) together with the main one.
struct VaultPartStreams {
    std::vector<void*> streams;
    void closeAll(int volId) {
        for (void* s : streams) fsCloseStream(volId, s);
        streams.clear();
    }
};

// `callerHoldsLock`: true when the caller already holds the volume's mutex for the whole read
// (the single-entry paths); false when it does not (the bulk path), in which case every vault
// access here takes the lock itself.
static ArchiveStreamSource vaultArchiveSource(int volId, const std::string& vaultPath, void* mainStream,
                                              uint64_t mainSize, bool callerHoldsLock,
                                              VaultPartStreams& parts, std::string* partSetError) {
    auto lockedRead = [volId, callerHoldsLock](void* stream, uint64_t offset, uint8_t* dest, size_t length) -> int64_t {
        if (callerHoldsLock) return fsReadStream(volId, stream, offset, dest, length);
        std::unique_lock<std::shared_mutex> lock(volumes[volId].mutex);
        return fsReadStream(volId, stream, offset, dest, length);
    };
    ArchiveStreamSource single;
    single.size = [mainSize]() { return mainSize; };
    single.read = [mainStream, lockedRead](uint64_t offset, uint8_t* dest, size_t length) -> int64_t {
        return lockedRead(mainStream, offset, dest, length);
    };

    const size_t slash = vaultPath.rfind('/');
    const std::string dir = slash == std::string::npos ? std::string() : vaultPath.substr(0, slash);
    const std::string name = slash == std::string::npos ? vaultPath : vaultPath.substr(slash + 1);
    auto prefix = [dir](const std::string& n) { return dir.empty() ? n : dir + "/" + n; };

    ArchivePartSetEnv partEnv;
    partEnv.listSiblings = [volId, dir, callerHoldsLock]() {
        std::vector<std::string> lines;
        {
            std::unique_lock<std::shared_mutex> lock(volumes[volId].mutex, std::defer_lock);
            if (!callerHoldsLock) lock.lock();
            fsListDirectory(volId, dir, lines);
        }
        std::vector<std::string> names;
        for (const auto& line : lines) {
            // "F|size|unixSecs|name" -- the name is everything after the third '|'.
            if (line.size() < 2 || line[0] != 'F') continue;
            size_t bar = 0;
            int seen = 0;
            while (seen < 3 && (bar = line.find('|', bar)) != std::string::npos) {
                ++bar;
                ++seen;
            }
            if (seen == 3) names.push_back(line.substr(bar));
        }
        return names;
    };
    partEnv.openSibling = [volId, callerHoldsLock, prefix, lockedRead, &parts](const std::string& n, ArchiveStreamSource* out) {
        const std::string full = prefix(n);
        void* stream = nullptr;
        uint64_t size = 0;
        {
            std::unique_lock<std::shared_mutex> lock(volumes[volId].mutex, std::defer_lock);
            if (!callerHoldsLock) lock.lock();
            stream = fsOpenStream(volId, full);
            if (stream) size = fsGetFileSize(volId, full);
        }
        if (!stream) return false;
        parts.streams.push_back(stream);
        out->size = [size]() { return size; };
        out->read = [stream, lockedRead](uint64_t offset, uint8_t* dest, size_t length) -> int64_t {
            return lockedRead(stream, offset, dest, length);
        };
        return true;
    };

    ArchiveStreamSource joined;
    std::string error;
    switch (archiveOpenPartSet(name, partEnv, &joined, &error)) {
        case ArchivePartSetStatus::Opened:
            return joined;
        case ArchivePartSetStatus::Missing:
            if (partSetError) *partSetError = error;
            return single;
        case ArchivePartSetStatus::NotASet:
            break;
    }
    return single;
}

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
    logArchiveFailure("scan", result.status, result.errorMessage);
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
    putBool("isSevenZip", result.isSevenZip);
    putString("errorMessage", result.errorMessage);

    jstring kEntries = env->NewStringUTF("entries");
    env->CallObjectMethod(resMap, mapPut, kEntries, entriesList);
    env->DeleteLocalRef(kEntries);
    env->DeleteLocalRef(entriesList);

    return resMap;
}

static jobject buildExtractResultMap(JNIEnv* env, const ArchiveExtractResult& result) {
    logArchiveFailure("extract", result.status, result.errorMessage);
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
    putString("errorMessage", result.errorMessage);

    if (result.status == ArchiveOpenStatus::Ok) {
        jbyteArray bytes = env->NewByteArray(static_cast<jsize>(result.data.size()));
        env->SetByteArrayRegion(bytes, 0, static_cast<jsize>(result.data.size()),
                                 reinterpret_cast<const jbyte*>(result.data.data()));
        jstring kData = env->NewStringUTF("data");
        env->CallObjectMethod(resMap, mapPut, kData, bytes);
        env->DeleteLocalRef(kData);
        env->DeleteLocalRef(bytes);
    }

    return resMap;
}

static jobject buildBulkExtractResultMap(JNIEnv* env, const ArchiveBulkExtractResult& result) {
    logArchiveFailure("extract-all", result.status, result.errorMessage);
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
                VaultPartStreams vaultParts;
                std::string partSetError;
                ArchiveStreamSource source = vaultArchiveSource(volId, nativePath, stream, totalSize, true,
                                                                vaultParts, &partSetError);
                if (!partSetError.empty()) {
                    res.status = ArchiveOpenStatus::IoError;
                    res.errorMessage = partSetError;
                } else {
                    res = archiveScanEntries(source, passStr);
                }
                fsCloseStream(volId, stream);
                vaultParts.closeAll(volId);
            }
        }
    }

    env->ReleaseStringUTFChars(vaultPath, nativePath);
    if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);

    return buildIndexResultMap(env, res);
    JNI_CATCH_RETURN(nullptr)
}

// ── In-Vault Single-Entry Extract ──────────────────────────────────────
extern "C" JNIEXPORT jobject JNICALL
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
                res.errorMessage = "Failed to open in-vault stream for archive";
            } else {
                uint64_t totalSize = fsGetFileSize(volId, nativePath);
                VaultPartStreams vaultParts;
                std::string partSetError;
                ArchiveStreamSource source = vaultArchiveSource(volId, nativePath, stream, totalSize, true,
                                                                vaultParts, &partSetError);
                if (!partSetError.empty()) {
                    res.status = ArchiveOpenStatus::IoError;
                    res.errorMessage = partSetError;
                } else {
                    res = archiveExtractEntry(source, targetIndex, passStr);
                }
                fsCloseStream(volId, stream);
                vaultParts.closeAll(volId);
            }
        }
    }

    env->ReleaseStringUTFChars(vaultPath, nativePath);
    if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);

    return buildExtractResultMap(env, res);
    JNI_CATCH_RETURN(nullptr)
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
        VaultPartStreams vaultParts;
        std::string partSetError;
        ArchiveStreamSource source = vaultArchiveSource(volId, nativePath, stream, totalSize, false,
                                                        vaultParts, &partSetError);

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

        if (!partSetError.empty()) {
            res.status = ArchiveOpenStatus::IoError;
            res.errorMessage = partSetError;
        } else {
            res = archiveExtractAll(source, passStr, subPathStr, makeDir, writeFileChunk, progressCb);
        }

        {
            std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
            fsCloseStream(volId, stream);
            vaultParts.closeAll(volId);
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
    ArchiveStreamSource source = archiveSourceForFd(fd, totalSize, nullptr);

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

extern "C" JNIEXPORT jobject JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_archiveExtractFdToLocalDirNative(
        JNIEnv* env, jobject, jint fd, jstring destDirPath,
        jstring subPath, jstring passphrase, jint opId) {
    JNI_TRY
    if (fd < 0) return nullptr;

    const char* nativeDestDir = destDirPath ? env->GetStringUTFChars(destDirPath, nullptr) : nullptr;
    const char* nativeSubPath = subPath ? env->GetStringUTFChars(subPath, nullptr) : nullptr;
    const char* nativePass = passphrase ? env->GetStringUTFChars(passphrase, nullptr) : nullptr;

    std::string targetDirPath = nativeDestDir ? nativeDestDir : "";
    std::string subPathStr = nativeSubPath ? nativeSubPath : "";
    std::string passStr = nativePass ? nativePass : "";

    while (!targetDirPath.empty() && targetDirPath.back() == '/') targetDirPath.pop_back();

    struct stat st;
    if (fstat(fd, &st) != 0) {
        if (destDirPath && nativeDestDir) env->ReleaseStringUTFChars(destDirPath, nativeDestDir);
        if (subPath && nativeSubPath) env->ReleaseStringUTFChars(subPath, nativeSubPath);
        if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);
        return nullptr;
    }

    uint64_t totalSize = static_cast<uint64_t>(st.st_size);
    ArchiveStreamSource source = archiveSourceForFd(fd, totalSize, nullptr);

    auto makeDir = [targetDirPath](const std::string& relPath) -> bool {
        std::string fullDest = targetDirPath + "/" + relPath;
        size_t pos = 0;
        while ((pos = fullDest.find('/', pos)) != std::string::npos) {
            if (pos > 0) {
                mkdir(fullDest.substr(0, pos).c_str(), 0755);
            }
            pos++;
        }
        return mkdir(fullDest.c_str(), 0755) == 0 || errno == EEXIST;
    };

    auto writeFileChunk = [targetDirPath](const std::string& relPath, uint64_t offset, const uint8_t* data, size_t length) -> bool {
        std::string fullDest = targetDirPath + "/" + relPath;
        if (offset == 0) {
            size_t pos = 0;
            while ((pos = fullDest.find('/', pos)) != std::string::npos) {
                if (pos > 0) {
                    mkdir(fullDest.substr(0, pos).c_str(), 0755);
                }
                pos++;
            }
            int ofd = open(fullDest.c_str(), O_CREAT | O_TRUNC | O_WRONLY, 0644);
            if (ofd < 0) return false;
            close(ofd);
        }
        if (length == 0) return true;
        int ofd = open(fullDest.c_str(), O_WRONLY);
        if (ofd < 0) return false;
        ssize_t written = pwrite(ofd, data, length, static_cast<off_t>(offset));
        close(ofd);
        return written == static_cast<ssize_t>(length);
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
    std::string partSetError;
    ArchiveStreamSource source = archiveSourceForFd(fd, totalSize, &partSetError);

    ArchiveIndexResult res;
    if (!partSetError.empty()) {
        res.status = ArchiveOpenStatus::IoError;
        res.errorMessage = partSetError;
    } else {
        res = archiveScanEntries(source, passStr);
    }

    if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);
    return buildIndexResultMap(env, res);
    JNI_CATCH_RETURN(nullptr)
}

// ── Local File Single-Entry Extract ────────────────────────────────────
extern "C" JNIEXPORT jobject JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_archiveExtractFdEntryNative(
        JNIEnv* env, jobject, jint fd, jint targetIndex, jstring passphrase) {
    JNI_TRY
    if (fd < 0) return nullptr;

    const char* nativePass = passphrase ? env->GetStringUTFChars(passphrase, nullptr) : nullptr;
    std::string passStr = nativePass ? nativePass : "";

    struct stat st;
    if (fstat(fd, &st) != 0) {
        if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);
        ArchiveExtractResult res;
        res.status = ArchiveOpenStatus::IoError;
        res.errorMessage = "Failed to stat archive file descriptor";
        return buildExtractResultMap(env, res);
    }

    uint64_t totalSize = static_cast<uint64_t>(st.st_size);
    ArchiveStreamSource source = archiveSourceForFd(fd, totalSize, nullptr);

    ArchiveExtractResult res = archiveExtractEntry(source, targetIndex, passStr);

    if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);
    return buildExtractResultMap(env, res);
    JNI_CATCH_RETURN(nullptr)
}

// ── Local File Single-Entry Stream to File Descriptor ──────────────────
extern "C" JNIEXPORT jobject JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_archiveExtractFdEntryToFdNative(
        JNIEnv* env, jobject, jint sourceFd, jint targetIndex, jstring passphrase, jint destFd) {
    JNI_TRY
    ArchiveExtractResult result;
    if (sourceFd < 0 || destFd < 0) {
        result.errorMessage = "source and destination file descriptors are required";
        return buildExtractResultMap(env, result);
    }

    const char* nativePass = passphrase ? env->GetStringUTFChars(passphrase, nullptr) : nullptr;
    const std::string passStr = nativePass ? nativePass : "";

    struct stat st;
    if (fstat(sourceFd, &st) != 0) {
        if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);
        result.errorMessage = "Failed to stat archive file descriptor";
        return buildExtractResultMap(env, result);
    }

    const uint64_t totalSize = static_cast<uint64_t>(st.st_size);
    ArchiveStreamSource source = archiveSourceForFd(sourceFd, totalSize, nullptr);

    uint64_t destinationOffset = 0;
    result = archiveExtractEntryToSink(
        source,
        targetIndex,
        passStr,
        [destFd, &destinationOffset](const uint8_t* data, size_t length) -> bool {
            size_t written = 0;
            while (written < length) {
                const ssize_t n = pwrite(
                    destFd,
                    data + written,
                    length - written,
                    static_cast<off_t>(destinationOffset + written)
                );
                if (n <= 0) return false;
                written += static_cast<size_t>(n);
            }
            destinationOffset += length;
            return true;
        }
    );

    if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);
    return buildExtractResultMap(env, result);
    JNI_CATCH_RETURN(nullptr)
}

// Progress/cancel hook shared by the archiveCreate* entry points. The engine
// reports progress on a 0..totalSourceBytes scale, where the total is the sum of
// the files going in, so Dart can keep showing "done / total" in real file
// sizes. For 7z and ISO the top part of that scale covers copying the buffered
// output to the destination, so a store doesn't sit at 100% while it finishes.
// (It used to report bytes written to the destination with a total of 0, which
// for those formats stays at 0 until the archive is closed.)
static std::function<bool(uint64_t)> makeCreateProgress(jint opId, uint64_t totalSourceBytes) {
    return [opId, totalSourceBytes](uint64_t sourceBytesProcessed) -> bool {
        if (opId > 0) {
            reportSplitJoinProgress(opId, sourceBytesProcessed, totalSourceBytes);
            if (isSplitJoinCancelled(opId) || isCopyCancelled(opId)) return false;
        }
        return true;
    };
}

// Maps the Dart/Kotlin method code onto the engine enum. An unknown code
// falls back to the format's default instead of being cast blindly, so a stale
// caller can't select a codec that doesn't exist.
static ArchiveCompressionMethod toCompressionMethod(jint code) {
    switch (code) {
        case 1: return ArchiveCompressionMethod::Deflate;
        case 2: return ArchiveCompressionMethod::Lzma;
        case 3: return ArchiveCompressionMethod::Lzma2;
        default: return ArchiveCompressionMethod::Default;
    }
}

// ── Create Archive: In-Vault Files -> Local File Descriptor ────────────
extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_archiveCreateVaultToFdNative(
        JNIEnv* env, jobject,
        jint srcVolId, jobjectArray vaultPaths, jobjectArray entryNames, jlongArray modifiedSecs,
        jint destFd, jint format, jstring passphrase, jboolean encryptFilenames,
        jint compressionLevel, jint compressionMethod, jint opId) {
    JNI_TRY
    if (destFd < 0 || !vaultPaths || !entryNames || !modifiedSecs) return JNI_FALSE;
    if (!requireActiveSession(srcVolId, "archiveCreateVaultToFd")) {
        throwNotUnlocked(env, srcVolId, "archiveCreateVaultToFd");
        return JNI_FALSE;
    }

    const jsize count = env->GetArrayLength(vaultPaths);
    std::vector<int64_t> sourceModifiedSecs;
    if (!readModifiedSecs(env, modifiedSecs, count, sourceModifiedSecs)) return JNI_FALSE;
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
            entries[i].isDirectory = false;
            entries[i].modTimeEpochSeconds = sourceModifiedSecs[i];

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

    uint64_t totalSourceBytes = 0;
    for (const auto& e : entries) {
        if (!e.isDirectory) totalSourceBytes += e.uncompressedSize;
    }

    ArchiveCreateResult res = archiveCreate(
        sink, static_cast<ArchiveFormat>(format), entries, passStr,
        encryptFilenames == JNI_TRUE, makeCreateProgress(opId, totalSourceBytes),
        static_cast<int>(compressionLevel),
        toCompressionMethod(compressionMethod)
    );

    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[srcVolId].mutex);
        for (void* s : openStreams) {
            if (s) fsCloseStream(srcVolId, s);
        }
    }

    if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);
    logArchiveFailure("create-vault-to-fd", res.status, res.errorMessage);
    return (res.status == ArchiveOpenStatus::Ok) ? JNI_TRUE : JNI_FALSE;
    JNI_CATCH_RETURN(JNI_FALSE)
}

// ── Create Archive: In-Vault Files -> In-Vault Target File ─────────────
extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_archiveCreateVaultToVaultNative(
        JNIEnv* env, jobject,
        jint srcVolId, jobjectArray vaultPaths, jobjectArray entryNames, jlongArray modifiedSecs,
        jint destVolId, jstring destVaultPath, jint format, jstring passphrase,
        jboolean encryptFilenames, jint compressionLevel, jint compressionMethod, jint opId) {
    JNI_TRY
    if (!vaultPaths || !entryNames || !modifiedSecs || !destVaultPath) return JNI_FALSE;
    if (!requireActiveSession(srcVolId, "archiveCreateVaultToVault (src)") ||
        !requireActiveSession(destVolId, "archiveCreateVaultToVault (dest)")) {
        throwNotUnlocked(env, srcVolId, "archiveCreateVaultToVault");
        return JNI_FALSE;
    }

    const jsize count = env->GetArrayLength(vaultPaths);
    std::vector<int64_t> sourceModifiedSecs;
    if (!readModifiedSecs(env, modifiedSecs, count, sourceModifiedSecs)) return JNI_FALSE;
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
        if (destOffset == 0) {
            ensureParentDirs(destVolId, targetVaultPath);
        }
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
            entries[i].modTimeEpochSeconds = sourceModifiedSecs[i];

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

    uint64_t totalSourceBytes = 0;
    for (const auto& e : entries) {
        if (!e.isDirectory) totalSourceBytes += e.uncompressedSize;
    }

    ArchiveCreateResult res = archiveCreate(
        sink, static_cast<ArchiveFormat>(format), entries, passStr,
        encryptFilenames == JNI_TRUE, makeCreateProgress(opId, totalSourceBytes),
        static_cast<int>(compressionLevel),
        toCompressionMethod(compressionMethod)
    );

    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[srcVolId].mutex);
        for (void* s : openStreams) {
            if (s) fsCloseStream(srcVolId, s);
        }
    }

    env->ReleaseStringUTFChars(destVaultPath, nativeDestPath);
    if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);
    logArchiveFailure("create-vault-to-vault", res.status, res.errorMessage);
    return (res.status == ArchiveOpenStatus::Ok) ? JNI_TRUE : JNI_FALSE;
    JNI_CATCH_RETURN(JNI_FALSE)
}

// ── Create Archive: Local Files -> Local File Descriptor ───────────────
extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_archiveCreateLocalToFdNative(
        JNIEnv* env, jobject,
        jobjectArray localPaths, jobjectArray entryNames, jlongArray modifiedSecs,
        jint destFd, jint format, jstring passphrase, jboolean encryptFilenames,
        jint compressionLevel, jint compressionMethod, jint opId) {
    JNI_TRY
    if (destFd < 0 || !localPaths || !entryNames || !modifiedSecs) return JNI_FALSE;

    const jsize count = env->GetArrayLength(localPaths);
    std::vector<int64_t> sourceModifiedSecs;
    if (!readModifiedSecs(env, modifiedSecs, count, sourceModifiedSecs)) return JNI_FALSE;
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
            entries[i].modTimeEpochSeconds = sourceModifiedSecs[i] > 0
                ? sourceModifiedSecs[i]
                : static_cast<int64_t>(st.st_mtime);

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

    uint64_t totalSourceBytes = 0;
    for (const auto& e : entries) {
        if (!e.isDirectory) totalSourceBytes += e.uncompressedSize;
    }

    ArchiveCreateResult res = archiveCreate(
        sink, static_cast<ArchiveFormat>(format), entries, passStr,
        encryptFilenames == JNI_TRUE, makeCreateProgress(opId, totalSourceBytes),
        static_cast<int>(compressionLevel),
        toCompressionMethod(compressionMethod)
    );

    for (int sfd : openFds) {
        if (sfd >= 0) close(sfd);
    }

    if (passphrase && nativePass) env->ReleaseStringUTFChars(passphrase, nativePass);
    logArchiveFailure("create-local-to-fd", res.status, res.errorMessage);
    return (res.status == ArchiveOpenStatus::Ok) ? JNI_TRUE : JNI_FALSE;
    JNI_CATCH_RETURN(JNI_FALSE)
}


// ── Split (multi-part) archive creation ─────────────────────────────────
//
// One entry point for every source/destination combination: a negative volume
// id means "plain device path", otherwise the path lives inside that unlocked
// vault. The archive engine only asks for "part N" / "part N is finished"; all
// naming and file handling is here.
//
//   7z : <archive>.7z.001, .002, ...        (archive path already ends in .7z)
//   ZIP: <archive>.z01, .z02, ... and the last part <archive>.zip
//
// The last ZIP part's name is only known once the archive is complete, so each
// part is created under its numbered name and the final one is renamed.

namespace {

std::vector<std::string> readJavaStringArray(JNIEnv* env, jobjectArray arr) {
    const jsize n = env->GetArrayLength(arr);
    std::vector<std::string> out(static_cast<size_t>(n));
    for (jsize i = 0; i < n; ++i) {
        jstring js = static_cast<jstring>(env->GetObjectArrayElement(arr, i));
        const char* c = env->GetStringUTFChars(js, nullptr);
        out[static_cast<size_t>(i)] = c ? c : "";
        if (c) env->ReleaseStringUTFChars(js, c);
        env->DeleteLocalRef(js);
    }
    return out;
}

bool endsWithIgnoreCase(const std::string& s, const char* suffix) {
    const size_t n = std::strlen(suffix);
    if (s.size() < n) return false;
    for (size_t i = 0; i < n; ++i) {
        const char a = s[s.size() - n + i];
        const char b = suffix[i];
        if ((a >= 'A' && a <= 'Z' ? a - 'A' + 'a' : a) != b) return false;
    }
    return true;
}

// Names of the parts of one split archive.
struct SplitNaming {
    bool zip = false;
    std::string base;   // 7z: the archive path; zip: the path without ".zip"

    static SplitNaming forArchive(const std::string& archivePath, bool zip) {
        SplitNaming n;
        n.zip = zip;
        n.base = (zip && endsWithIgnoreCase(archivePath, ".zip"))
                     ? archivePath.substr(0, archivePath.size() - 4)
                     : archivePath;
        return n;
    }
    // Name a part has while it is being written.
    std::string working(uint32_t index) const {
        char suffix[24];
        if (zip) std::snprintf(suffix, sizeof(suffix), ".z%02u", index + 1);
        else std::snprintf(suffix, sizeof(suffix), ".%03u", index + 1);
        return base + suffix;
    }
    // Name once the archive is complete (only differs for the last ZIP part).
    std::string finalName(uint32_t index, bool isLast) const {
        return (zip && isLast) ? base + ".zip" : working(index);
    }
};

// Part target writing to plain files next to each other.
struct LocalPartFiles {
    SplitNaming naming;
    int fd = -1;
    std::string current;
    std::vector<std::string> created;

    bool open(uint32_t index) {
        current = naming.working(index);
        fd = ::open(current.c_str(), O_WRONLY | O_CREAT | O_EXCL, 0644);
        if (fd < 0) {
            __android_log_print(ANDROID_LOG_ERROR, "VaultExplorer_Archive", "cannot create part %s: %s",
                                current.c_str(), std::strerror(errno));
            return false;
        }
        created.push_back(current);
        return true;
    }
    int64_t write(const uint8_t* data, size_t length) {
        size_t done = 0;
        while (done < length) {
            const ssize_t n = ::write(fd, data + done, length - done);
            if (n < 0) {
                if (errno == EINTR) continue;
                return -1;
            }
            done += static_cast<size_t>(n);
        }
        return static_cast<int64_t>(length);
    }
    bool close(uint32_t index, bool isLast) {
        const int rc = ::close(fd);
        fd = -1;
        if (rc != 0) return false;
        const std::string finalPath = naming.finalName(index, isLast);
        if (finalPath == current) return true;
        if (::access(finalPath.c_str(), F_OK) == 0) return false;  // never replace a file
        if (::rename(current.c_str(), finalPath.c_str()) != 0) return false;
        created.back() = finalPath;
        return true;
    }
    void abort() {
        if (fd >= 0) {
            ::close(fd);
            fd = -1;
        }
        for (const auto& path : created) ::unlink(path.c_str());
        created.clear();
    }
};

// Part target writing into an unlocked vault.
struct VaultPartFiles {
    int volId = -1;
    SplitNaming naming;
    std::string current;
    uint64_t offset = 0;
    std::vector<std::string> created;

    bool open(uint32_t index) {
        current = naming.working(index);
        std::unique_lock<std::shared_mutex> lock(volumes[volId].mutex);
        if (!ensureMounted(volId)) return false;
        if (fsGetFileSize(volId, current) > 0) return false;  // never replace a file
        if (created.empty()) ensureParentDirs(volId, current);
        offset = 0;
        created.push_back(current);
        return true;
    }
    int64_t write(const uint8_t* data, size_t length) {
        std::unique_lock<std::shared_mutex> lock(volumes[volId].mutex);
        if (!fsWriteFileChunk(volId, current, offset, data, length)) return -1;
        offset += length;
        return static_cast<int64_t>(length);
    }
    bool close(uint32_t index, bool isLast) {
        const std::string finalPath = naming.finalName(index, isLast);
        if (finalPath == current) return true;
        std::unique_lock<std::shared_mutex> lock(volumes[volId].mutex);
        if (fsGetFileSize(volId, finalPath) > 0) return false;
        if (!fsRenameFile(volId, current, finalPath)) return false;
        created.back() = finalPath;
        return true;
    }
    void abort() {
        std::unique_lock<std::shared_mutex> lock(volumes[volId].mutex);
        for (const auto& path : created) fsDeleteFile(volId, path);
        created.clear();
    }
};

// Reads one source file only while the archive is working on it, so a
// selection with thousands of files never holds thousands of descriptors.
struct LazySource {
    std::string path;
    uint64_t size = 0;
    uint64_t offset = 0;
    int fd = -1;              // device source
    void* stream = nullptr;   // vault source
    bool opened = false;
    bool finished = false;
};

}  // namespace

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_archiveCreateSplitNative(
        JNIEnv* env, jobject,
        jint srcVolId, jobjectArray srcPaths, jobjectArray entryNames, jlongArray modifiedSecs,
        jint destVolId, jstring destArchivePath, jlong partSize, jint format,
        jstring passphrase, jboolean encryptFilenames,
        jint compressionLevel, jint compressionMethod, jint opId) {
    JNI_TRY
    if (!srcPaths || !entryNames || !modifiedSecs || !destArchivePath || partSize <= 0) return JNI_FALSE;
    if (srcVolId >= 0 && !requireActiveSession(srcVolId, "archiveCreateSplit (src)")) {
        throwNotUnlocked(env, srcVolId, "archiveCreateSplit");
        return JNI_FALSE;
    }
    if (destVolId >= 0 && !requireActiveSession(destVolId, "archiveCreateSplit (dest)")) {
        throwNotUnlocked(env, destVolId, "archiveCreateSplit");
        return JNI_FALSE;
    }

    const jsize count = env->GetArrayLength(srcPaths);
    std::vector<int64_t> sourceModifiedSecs;
    if (!readModifiedSecs(env, modifiedSecs, count, sourceModifiedSecs)) return JNI_FALSE;
    const std::vector<std::string> sources = readJavaStringArray(env, srcPaths);
    const std::vector<std::string> inArchivePaths = readJavaStringArray(env, entryNames);

    std::string passStr;
    if (passphrase) {
        const char* p = env->GetStringUTFChars(passphrase, nullptr);
        if (p) {
            passStr = p;
            env->ReleaseStringUTFChars(passphrase, p);
        }
    }
    std::string archivePath;
    {
        const char* d = env->GetStringUTFChars(destArchivePath, nullptr);
        archivePath = d ? d : "";
        if (d) env->ReleaseStringUTFChars(destArchivePath, d);
    }

    const ArchiveFormat fmt = static_cast<ArchiveFormat>(format);
    const SplitNaming naming = SplitNaming::forArchive(archivePath, fmt == ArchiveFormat::Zip);

    // Where the parts go.
    LocalPartFiles localParts;
    VaultPartFiles vaultParts;
    ArchivePartTarget target;
    if (destVolId < 0) {
        localParts.naming = naming;
        target.openPart = [&localParts](uint32_t i) { return localParts.open(i); };
        target.writePart = [&localParts](const uint8_t* d, size_t n) { return localParts.write(d, n); };
        target.closePart = [&localParts](uint32_t i, bool last) { return localParts.close(i, last); };
        target.abort = [&localParts]() { localParts.abort(); };
    } else {
        vaultParts.volId = destVolId;
        vaultParts.naming = naming;
        target.openPart = [&vaultParts](uint32_t i) { return vaultParts.open(i); };
        target.writePart = [&vaultParts](const uint8_t* d, size_t n) { return vaultParts.write(d, n); };
        target.closePart = [&vaultParts](uint32_t i, bool last) { return vaultParts.close(i, last); };
        target.abort = [&vaultParts]() { vaultParts.abort(); };
    }

    // What goes in.
    std::vector<LazySource> lazy(static_cast<size_t>(count));
    std::vector<ArchiveSourceEntry> entries(static_cast<size_t>(count));
    if (srcVolId >= 0) {
        std::unique_lock<std::shared_mutex> fsLock(volumes[srcVolId].mutex);
        if (!ensureMounted(srcVolId)) return JNI_FALSE;
        for (jsize i = 0; i < count; ++i) {
            lazy[i].path = sources[i];
            lazy[i].size = fsGetFileSize(srcVolId, sources[i]);
        }
    } else {
        for (jsize i = 0; i < count; ++i) {
            lazy[i].path = sources[i];
            struct stat st;
            if (stat(sources[i].c_str(), &st) == 0 && !S_ISDIR(st.st_mode)) {
                lazy[i].size = static_cast<uint64_t>(st.st_size);
                if (sourceModifiedSecs[i] <= 0) sourceModifiedSecs[i] = static_cast<int64_t>(st.st_mtime);
            }
        }
    }
    for (jsize i = 0; i < count; ++i) {
        entries[i].pathInArchive = inArchivePaths[i];
        entries[i].isDirectory = false;
        entries[i].uncompressedSize = lazy[i].size;
        entries[i].modTimeEpochSeconds = sourceModifiedSecs[i];
        entries[i].readData = [&lazy, srcVolId, i](uint8_t* dest, size_t length) -> int64_t {
            LazySource& s = lazy[i];
            if (s.finished) return 0;
            int64_t n = -1;
            if (srcVolId >= 0) {
                std::unique_lock<std::shared_mutex> lock(volumes[srcVolId].mutex);
                if (!s.opened) {
                    s.stream = fsOpenStream(srcVolId, s.path);
                    s.opened = true;
                }
                if (!s.stream) return -1;
                n = fsReadStream(srcVolId, s.stream, s.offset, dest, length);
                if (n <= 0 || s.offset + static_cast<uint64_t>(n) >= s.size) {
                    fsCloseStream(srcVolId, s.stream);
                    s.stream = nullptr;
                    s.finished = true;
                }
            } else {
                if (!s.opened) {
                    s.fd = ::open(s.path.c_str(), O_RDONLY);
                    s.opened = true;
                }
                if (s.fd < 0) return -1;
                n = ::pread(s.fd, dest, length, static_cast<off_t>(s.offset));
                if (n <= 0 || s.offset + static_cast<uint64_t>(n) >= s.size) {
                    ::close(s.fd);
                    s.fd = -1;
                    s.finished = true;
                }
            }
            if (n > 0) s.offset += static_cast<uint64_t>(n);
            return n;
        };
    }

    uint64_t totalSourceBytes = 0;
    for (const auto& src : lazy) totalSourceBytes += src.size;

    const ArchiveCreateResult res = archiveCreateSplit(
        target, static_cast<uint64_t>(partSize), fmt, entries, passStr,
        encryptFilenames == JNI_TRUE, makeCreateProgress(opId, totalSourceBytes),
        static_cast<int>(compressionLevel), toCompressionMethod(compressionMethod));

    // Anything the archive stopped reading before the end (failure, cancel).
    for (auto& s : lazy) {
        if (s.fd >= 0) ::close(s.fd);
        if (s.stream && srcVolId >= 0) {
            std::unique_lock<std::shared_mutex> lock(volumes[srcVolId].mutex);
            fsCloseStream(srcVolId, s.stream);
        }
    }

    logArchiveFailure("create-split", res.status, res.errorMessage);
    return (res.status == ArchiveOpenStatus::Ok) ? JNI_TRUE : JNI_FALSE;
    JNI_CATCH_RETURN(JNI_FALSE)
}
