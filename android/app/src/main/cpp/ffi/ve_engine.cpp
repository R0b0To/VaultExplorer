// Desktop C ABI over the VaultExplorer engine (see ve_engine.h).
//
// This file is the desktop twin of jni/{session,filesystem,container_lifecycle}_bridge.cpp.
// It deliberately mirrors their locking discipline and ownership rules line for
// line -- requireActiveSession -> (read-only check) -> exclusive volume lock ->
// ensureMounted -> fsXxx -- so behavior on desktop is the behavior Android has
// shipped, only with C types instead of JNI ones.
//
// NOTE (tech debt, intentional for the first cut): a few bodies (lockSlot, the
// unlock sequence, the copy dual-lock) are duplicated from the JNI bridges so the
// Android build is left completely untouched. A follow-up should hoist them into
// a JNI-free session_ops.{h,cpp} that both bridges call.

#include "ve_engine.h"

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <mutex>
#include <shared_mutex>
#include <string>
#include <vector>

#if defined(_WIN32)
#  include <io.h>
#  include <fcntl.h>
// Defined in ffi/ve_win_platform.cpp -- the only file allowed to include <windows.h>.
int ve_win_open_utf8(const char* path, int writable, int create);
#else
#  include <fcntl.h>
#  include <unistd.h>
#endif

#include <android/log.h>
#include <mbedtls/platform_util.h>

#include "container_create.h"
#include "container_format.h"
#include "container_utils.h"
#include "crypto/user_entropy.h"
#include "filesystems/fs_ops.h"
#include "filesystems/stream_handles.h"
#include "jni_callbacks.h"
#include "session_guard.h"
#include "session_prepare.h"
#include "virtual_block_device.h"
#include "volume_state.h"

// ── logging ──────────────────────────────────────────────────────────────

namespace {
std::atomic<int> g_logEnabled{0};
std::atomic<void (*)(int32_t, const char*, const char*)> g_logCallback{nullptr};
}  // namespace

extern "C" int ve_log_enabled(void) { return g_logEnabled.load(std::memory_order_relaxed); }

extern "C" void ve_log_dispatch(int prio, const char* tag, const char* message) {
    auto cb = g_logCallback.load();
    if (cb) {
        cb(prio, tag ? tag : "", message ? message : "");
    } else {
        std::fprintf(stderr, "[%s] %s\n", tag ? tag : "VaultExplorer", message ? message : "");
    }
}

#define VE_LOG(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

extern "C" VE_API void ve_set_log_enabled(int32_t enabled) { g_logEnabled.store(enabled ? 1 : 0); }
extern "C" VE_API void ve_set_log_callback(void (*cb)(int32_t, const char*, const char*)) {
    g_logCallback.store(cb);
}

// ── boundary safety ──────────────────────────────────────────────────────
// A C++ exception must never unwind into Dart/FFI (undefined behavior). The
// engine does not throw on reachable paths, but parallelCryptoLoop deliberately
// propagates worker exceptions ("fail loud rather than silently corrupt
// plaintext"), so convert them to a return code here.
#define VE_TRY try {
#define VE_CATCH(retval)                                              \
    }                                                                 \
    catch (const std::exception& e) {                                 \
        VE_LOG("uncaught C++ exception at C ABI boundary: %s", e.what()); \
        return (retval);                                              \
    }                                                                 \
    catch (...) {                                                     \
        VE_LOG("uncaught non-standard C++ exception at C ABI boundary"); \
        return (retval);                                              \
    }

namespace {

constexpr size_t kMaxChunk = 64u * 1024u * 1024u;  // same cap as the JNI read/write calls

bool validVol(int32_t vol) { return vol >= 0 && vol < FF_VOLUMES; }

void closeFds(const int32_t* fds, int32_t count) {
    if (!fds) return;
    for (int32_t i = 0; i < count; ++i) {
        if (fds[i] >= 0) {
#if defined(_WIN32)
            _close(fds[i]);
#else
            close(fds[i]);
#endif
        }
    }
}

void closeOne(int32_t fd) {
    if (fd < 0) return;
#if defined(_WIN32)
    _close(fd);
#else
    close(fd);
#endif
}

// Duplicated from jni/session_bridge.cpp (lockNative / rollBackUnprotectedSession).
void lockSlot(int volId) {
    if (!validVol(volId)) return;
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

// Runs `body(lock)` with the same preconditions every JNI filesystem entry point
// establishes. `body` returns a VE_* code and may unlock/relock `lock` (the
// progress callbacks do, to let other callers interleave during long copies).
template <typename Body>
int32_t withMounted(int32_t vol, const char* op, bool needsWrite, Body&& body) {
    if (!requireActiveSession(vol, op)) return VE_ERR_NOT_UNLOCKED;
    if (needsWrite && isVolumeReadOnly(vol)) return VE_ERR_READ_ONLY;
    std::unique_lock<std::shared_mutex> lock(volumes[vol].mutex);
    if (!ensureMounted(vol)) return VE_ERR_MOUNT_FAILED;
    return body(lock);
}

inline int32_t okOrFailed(bool ok) { return ok ? VE_OK : VE_ERR_FAILED; }

void putU32(std::vector<uint8_t>& out, uint32_t v) {
    out.push_back(static_cast<uint8_t>(v));
    out.push_back(static_cast<uint8_t>(v >> 8));
    out.push_back(static_cast<uint8_t>(v >> 16));
    out.push_back(static_cast<uint8_t>(v >> 24));
}

// Hands `bytes` to the caller in a malloc'd ve_buffer.
bool emitBuffer(const uint8_t* bytes, size_t len, ve_buffer* out) {
    out->data = nullptr;
    out->len = 0;
    if (len == 0) return true;
    auto* mem = static_cast<uint8_t*>(std::malloc(len));
    if (!mem) return false;
    std::memcpy(mem, bytes, len);
    out->data = mem;
    out->len = len;
    return true;
}

}  // namespace

// ── info ─────────────────────────────────────────────────────────────────

extern "C" VE_API int32_t ve_abi_version(void) { return VE_ABI_VERSION; }
extern "C" VE_API int32_t ve_max_volumes(void) { return FF_VOLUMES; }

extern "C" VE_API void ve_buffer_free(ve_buffer* buf) {
    if (!buf) return;
    if (buf->data) {
        mbedtls_platform_zeroize(buf->data, buf->len);  // may hold decrypted content
        std::free(buf->data);
    }
    buf->data = nullptr;
    buf->len = 0;
}

// ── host files ───────────────────────────────────────────────────────────

extern "C" VE_API int32_t ve_open_file(const char* path, int32_t writable) {
    if (!path) return -1;
#if defined(_WIN32)
    return ve_win_open_utf8(path, writable, /*create=*/0);
#else
    return open(path, (writable ? O_RDWR : O_RDONLY) | O_CLOEXEC);
#endif
}

extern "C" VE_API int32_t ve_create_file(const char* path) {
    if (!path) return -1;
#if defined(_WIN32)
    return ve_win_open_utf8(path, /*writable=*/1, /*create=*/1);
#else
    return open(path, O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
#endif
}

extern "C" VE_API void ve_close_fd(int32_t fd) { closeOne(fd); }

extern "C" VE_API const char* ve_probe_format(int32_t fd) {
    VE_TRY
    if (fd < 0) return "unknown";
    const char* fmt = probeContainerFormat(fd);
    return fmt ? fmt : "unknown";
    VE_CATCH("unknown")
}

// ── session lifecycle ────────────────────────────────────────────────────

extern "C" VE_API int32_t ve_unlock(const ve_unlock_params* p) {
    if (!p || p->struct_size < static_cast<int32_t>(sizeof(ve_unlock_params))) {
        if (p) { closeOne(p->fd); closeFds(p->keyfile_fds, p->keyfile_count); closeFds(p->hidden_keyfile_fds, p->hidden_keyfile_count); }
        return VE_ERR_INVALID_ARG;
    }
    if (!validVol(p->vol_id) || p->password_len < 0 || p->keyfile_count < 0) {
        closeOne(p->fd);
        closeFds(p->keyfile_fds, p->keyfile_count);
        closeFds(p->hidden_keyfile_fds, p->hidden_keyfile_count);
        return VE_ERR_INVALID_ARG;
    }
    VE_TRY
    const int volId = p->vol_id;
    clearUnlockCancellation(volId);

    static const unsigned char kEmpty[1] = {0};
    const unsigned char* pw = p->password ? p->password : kEmpty;
    const size_t pwLen = p->password ? static_cast<size_t>(p->password_len) : 0;

    if (!prepareSession(p->fd, pw, pwLen, p->pim, volId, /*forceDerive=*/true,
                        p->cipher_id, p->hash_id,
                        p->preserved_key, p->preserved_key ? static_cast<size_t>(p->preserved_key_len) : 0,
                        p->keyfile_count > 0 ? p->keyfile_fds : nullptr, p->keyfile_count,
                        p->read_only != 0)) {
        // prepareSession owns (and has closed) fd + keyfile fds on every path.
        closeFds(p->hidden_keyfile_fds, p->hidden_keyfile_count);
        return isUnlockCancelled(volId) ? VE_ERR_CANCELLED : VE_ERR_FAILED;
    }

    bool mountOk;
    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        mountOk = ensureMounted(volId);
    }
    if (!mountOk) {
        VE_LOG("FATFS/NTFS/ext mount failed on volume %d", volId);
        closeFds(p->hidden_keyfile_fds, p->hidden_keyfile_count);
        lockSlot(volId);  // never leave a decrypted session behind a failed mount
        return VE_ERR_MOUNT_FAILED;
    }

    if (p->hidden_password != nullptr) {
        if (!enableHiddenVolumeProtection(
                volId, p->hidden_password, static_cast<size_t>(p->hidden_password_len),
                p->hidden_pim, p->hidden_cipher_id, p->hidden_hash_id,
                p->hidden_keyfile_count > 0 ? p->hidden_keyfile_fds : nullptr,
                p->hidden_keyfile_count)) {
            lockSlot(volId);
            return VE_ERR_FAILED;
        }
    } else {
        closeFds(p->hidden_keyfile_fds, p->hidden_keyfile_count);
    }
    return VE_OK;
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API void ve_request_cancel_unlock(int32_t vol_id) {
    if (validVol(vol_id)) requestUnlockCancellation(vol_id);
}

extern "C" VE_API void ve_lock(int32_t vol_id) {
    try { lockSlot(vol_id); } catch (...) {}
}

extern "C" VE_API int32_t ve_get_container_format(int32_t vol_id) {
    if (!validVol(vol_id)) return -1;
    std::shared_lock<std::shared_mutex> lock(volumes[vol_id].mutex);
    return static_cast<int32_t>(volumes[vol_id].containerFormat);
}

extern "C" VE_API int32_t ve_get_matched_cipher_id(int32_t vol_id) {
    if (!validVol(vol_id)) return -1;
    std::shared_lock<std::shared_mutex> lock(volumes[vol_id].mutex);
    return static_cast<int32_t>(volumes[vol_id].matchedCipherId);
}

extern "C" VE_API int32_t ve_get_matched_hash_id(int32_t vol_id) {
    if (!validVol(vol_id)) return -1;
    std::shared_lock<std::shared_mutex> lock(volumes[vol_id].mutex);
    return static_cast<int32_t>(volumes[vol_id].matchedHashId);
}

// ── container creation ───────────────────────────────────────────────────

extern "C" VE_API int32_t ve_create_container(const ve_create_params* p) {
    if (!p || p->struct_size < static_cast<int32_t>(sizeof(ve_create_params)) ||
        !p->file_system || p->size_bytes <= 0 || p->password_len < 0 || p->keyfile_count < 0) {
        if (p) { closeOne(p->fd); closeFds(p->keyfile_fds, p->keyfile_count); }
        return VE_ERR_INVALID_ARG;
    }
    VE_TRY
    userentropy::Scope entropy(p->user_entropy,
                               p->user_entropy ? static_cast<size_t>(p->user_entropy_len) : 0);

    std::string pass(p->password ? reinterpret_cast<const char*>(p->password) : "",
                     p->password ? static_cast<size_t>(p->password_len) : 0);
    const int* kf = p->keyfile_count > 0 ? p->keyfile_fds : nullptr;

    bool success;
    if (p->container_format == 1 || p->container_format == 2) {
        success = createLuksContainer(p->fd, pass.c_str(), p->pim, p->size_bytes, p->file_system,
                                      p->container_format, p->cipher_id, p->hash_id,
                                      kf, p->keyfile_count, p->quick_format != 0);
    } else {
        success = createContainer(p->fd, pass.c_str(), p->pim, p->size_bytes, p->file_system,
                                  p->cipher_id, p->hash_id, kf, p->keyfile_count,
                                  p->quick_format != 0);
    }
    mbedtls_platform_zeroize(pass.data(), pass.size());
    return okOrFailed(success);
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_create_container_with_hidden(const ve_create_hidden_params* p) {
    if (!p || p->struct_size < static_cast<int32_t>(sizeof(ve_create_hidden_params)) ||
        !p->outer_file_system || !p->hidden_file_system || p->size_bytes <= 0 ||
        p->hidden_size_bytes <= 0 || p->outer_password_len < 0 || p->hidden_password_len < 0 ||
        p->outer_keyfile_count < 0 || p->hidden_keyfile_count < 0) {
        if (p) {
            closeOne(p->fd);
            closeFds(p->outer_keyfile_fds, p->outer_keyfile_count);
            closeFds(p->hidden_keyfile_fds, p->hidden_keyfile_count);
        }
        return VE_ERR_INVALID_ARG;
    }
    VE_TRY
    userentropy::Scope entropy(p->user_entropy,
                               p->user_entropy ? static_cast<size_t>(p->user_entropy_len) : 0);
    std::string outerPass(p->outer_password ? reinterpret_cast<const char*>(p->outer_password) : "",
                          p->outer_password ? static_cast<size_t>(p->outer_password_len) : 0);
    std::string hiddenPass(p->hidden_password ? reinterpret_cast<const char*>(p->hidden_password) : "",
                           p->hidden_password ? static_cast<size_t>(p->hidden_password_len) : 0);
    const bool success = createContainerWithHidden(
        p->fd, outerPass.c_str(), hiddenPass.c_str(), p->outer_pim, p->hidden_pim, p->size_bytes,
        p->outer_file_system, p->hidden_file_system, p->hidden_size_bytes,
        p->outer_cipher_id, p->outer_hash_id, p->hidden_cipher_id, p->hidden_hash_id,
        p->outer_keyfile_count > 0 ? p->outer_keyfile_fds : nullptr, p->outer_keyfile_count,
        p->hidden_keyfile_count > 0 ? p->hidden_keyfile_fds : nullptr, p->hidden_keyfile_count,
        p->quick_format != 0);
    mbedtls_platform_zeroize(outerPass.data(), outerPass.size());
    mbedtls_platform_zeroize(hiddenPass.data(), hiddenPass.size());
    return okOrFailed(success);
    VE_CATCH(VE_ERR_EXCEPTION)
}

// ── filesystem operations ────────────────────────────────────────────────

extern "C" VE_API int32_t ve_list_directory(int32_t vol, const char* path, ve_buffer* out) {
    if (!out) return VE_ERR_INVALID_ARG;
    out->data = nullptr;
    out->len = 0;
    if (!path || !validVol(vol)) return VE_ERR_INVALID_ARG;
    VE_TRY
    std::vector<std::string> results;
    results.reserve(256);
    const int32_t rc = withMounted(vol, "listDirectory", false, [&](auto&) {
        fsListDirectory(vol, path, results);
        return VE_OK;
    });
    if (rc != VE_OK) return rc;

    std::vector<uint8_t> packed;
    putU32(packed, static_cast<uint32_t>(results.size()));
    for (auto& entry : results) {
        sanitizeString(entry);  // same UTF-8 scrub the JNI path applies
        putU32(packed, static_cast<uint32_t>(entry.size()));
        packed.insert(packed.end(), entry.begin(), entry.end());
    }
    return emitBuffer(packed.data(), packed.size(), out) ? VE_OK : VE_ERR_FAILED;
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int64_t ve_get_file_size(int32_t vol, const char* path) {
    if (!path || !validVol(vol)) return -VE_ERR_INVALID_ARG;
    VE_TRY
    int64_t size = 0;
    const int32_t rc = withMounted(vol, "getFileSize", false, [&](auto&) {
        size = static_cast<int64_t>(fsGetFileSize(vol, path));
        return VE_OK;
    });
    return rc == VE_OK ? size : -static_cast<int64_t>(rc);
    VE_CATCH(-VE_ERR_EXCEPTION)
}

extern "C" VE_API int64_t ve_get_folder_size(int32_t vol, const char* path) {
    if (!path || !validVol(vol)) return -VE_ERR_INVALID_ARG;
    VE_TRY
    int64_t total = 0;
    const int32_t rc = withMounted(vol, "getFolderSize", false, [&](auto&) {
        total = static_cast<int64_t>(fsGetFolderSize(vol, path));
        return VE_OK;
    });
    return rc == VE_OK ? total : -static_cast<int64_t>(rc);
    VE_CATCH(-VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_read_file_chunk(int32_t vol, const char* path, int64_t offset,
                                             int32_t length, ve_buffer* out) {
    if (!out) return VE_ERR_INVALID_ARG;
    out->data = nullptr;
    out->len = 0;
    if (!path || !validVol(vol) || offset < 0 || length <= 0 ||
        static_cast<size_t>(length) > kMaxChunk) {
        return VE_ERR_INVALID_ARG;
    }
    VE_TRY
    std::vector<uint8_t> buffer;
    const int32_t rc = withMounted(vol, "readFileChunk", false, [&](auto&) {
        return okOrFailed(fsReadFileChunk(vol, path, static_cast<uint64_t>(offset),
                                          static_cast<size_t>(length), buffer));
    });
    if (rc != VE_OK) return rc;
    const bool ok = emitBuffer(buffer.data(), buffer.size(), out);
    if (!buffer.empty()) mbedtls_platform_zeroize(buffer.data(), buffer.size());
    return ok ? VE_OK : VE_ERR_FAILED;
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_write_file_chunk(int32_t vol, const char* path, int64_t offset,
                                              const uint8_t* data, size_t len) {
    if (!path || !validVol(vol) || offset < 0 || len > kMaxChunk || (len > 0 && !data)) {
        return VE_ERR_INVALID_ARG;
    }
    VE_TRY
    return withMounted(vol, "writeFileChunk", true, [&](auto&) {
        return okOrFailed(fsWriteFileChunk(vol, path, static_cast<uint64_t>(offset), data, len));
    });
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_delete_file(int32_t vol, const char* path) {
    if (!path || !validVol(vol)) return VE_ERR_INVALID_ARG;
    VE_TRY
    return withMounted(vol, "deleteFile", true, [&](auto&) { return okOrFailed(fsDeleteFile(vol, path)); });
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_create_directory(int32_t vol, const char* path) {
    if (!path || !validVol(vol)) return VE_ERR_INVALID_ARG;
    VE_TRY
    return withMounted(vol, "createDirectory", true, [&](auto&) { return okOrFailed(fsCreateDirectory(vol, path)); });
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_rename_file(int32_t vol, const char* old_path, const char* new_path) {
    if (!old_path || !new_path || !validVol(vol)) return VE_ERR_INVALID_ARG;
    VE_TRY
    return withMounted(vol, "renameFile", true, [&](auto&) { return okOrFailed(fsRenameFile(vol, old_path, new_path)); });
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_set_last_modified(int32_t vol, const char* path, int64_t epoch_seconds) {
    if (!path || !validVol(vol) || epoch_seconds < 0) return VE_ERR_INVALID_ARG;
    VE_TRY
    return withMounted(vol, "setLastModifiedTime", true, [&](auto&) {
        return okOrFailed(fsSetLastModifiedTime(vol, path, static_cast<uint64_t>(epoch_seconds)));
    });
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_import_file(int32_t vol, const char* vault_path,
                                         const char* host_source_path, int32_t op_id) {
    if (!vault_path || !host_source_path || !validVol(vol)) return VE_ERR_INVALID_ARG;
    VE_TRY
    return withMounted(vol, "writeBackFile", true, [&](std::unique_lock<std::shared_mutex>& fsLock) {
        return okOrFailed(fsWriteBackFile(vol, vault_path, host_source_path,
            [op_id, vol, &fsLock](uint64_t bytesWritten) -> bool {
                reportWriteBackChunkProgress(op_id, bytesWritten);
                if (isWriteBackCancelled(op_id)) return false;
                fsLock.unlock();
                yieldContainerWriteLock(vol);
                fsLock.lock();
                return ensureMounted(vol);
            }));
    });
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_export_file(int32_t vol, const char* vault_path,
                                         const char* host_dest_path, int32_t op_id) {
    if (!vault_path || !host_dest_path || !validVol(vol)) return VE_ERR_INVALID_ARG;
    VE_TRY
    return withMounted(vol, "extractFile", false, [&](std::unique_lock<std::shared_mutex>& fsLock) {
        return okOrFailed(fsExtractFile(vol, vault_path, host_dest_path,
            [op_id, vol, &fsLock](uint64_t bytesWritten) -> bool {
                reportExtractChunkProgress(op_id, bytesWritten);
                if (isExtractCancelled(op_id)) return false;
                fsLock.unlock();
                yieldContainerWriteLock(vol);
                fsLock.lock();
                return ensureMounted(vol);
            }));
    });
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_copy_file(int32_t srcVol, const char* srcPath,
                                       int32_t destVol, const char* destPath, int32_t opId) {
    if (!srcPath || !destPath || !validVol(srcVol) || !validVol(destVol)) return VE_ERR_INVALID_ARG;
    VE_TRY
    if (!requireActiveSession(srcVol, "copyFile (src)")) return VE_ERR_NOT_UNLOCKED;
    if (!requireActiveSession(destVol, "copyFile (dest)")) return VE_ERR_NOT_UNLOCKED;
    if (isVolumeReadOnly(destVol)) return VE_ERR_READ_ONLY;

    const bool sameVolume = (srcVol == destVol);
    std::unique_lock<std::shared_mutex> destLock(volumes[destVol].mutex, std::defer_lock);
    std::unique_lock<std::shared_mutex> srcLock(volumes[srcVol].mutex, std::defer_lock);
    if (sameVolume) destLock.lock();
    else std::lock(srcLock, destLock);

    if (!ensureMounted(srcVol) || !ensureMounted(destVol)) return VE_ERR_MOUNT_FAILED;
    return okOrFailed(fsCopyFile(srcVol, srcPath, destVol, destPath,
        [opId, srcVol, destVol, sameVolume, &destLock, &srcLock](uint64_t bytesWritten) -> bool {
            reportCopyProgress(opId, bytesWritten);
            if (isCopyCancelled(opId)) return false;
            if (sameVolume) {
                destLock.unlock();
                yieldContainerCopyLocks(srcVol, destVol);
                destLock.lock();
                return ensureMounted(destVol);
            }
            destLock.unlock();
            srcLock.unlock();
            yieldContainerCopyLocks(srcVol, destVol);
            std::lock(srcLock, destLock);
            return ensureMounted(srcVol) && ensureMounted(destVol);
        }));
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_get_space_info(int32_t vol, uint64_t* total, uint64_t* free_bytes) {
    if (!total || !free_bytes || !validVol(vol)) return VE_ERR_INVALID_ARG;
    VE_TRY
    uint64_t t = 0, f = 0;
    const int32_t rc = withMounted(vol, "getSpaceInfo", false, [&](auto&) {
        fsGetSpaceInfo(vol, t, f);
        return VE_OK;
    });
    if (rc != VE_OK) return rc;
    *total = t;
    *free_bytes = f;
    return VE_OK;
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_get_filesystem_label(int32_t vol, char* buf, size_t cap) {
    if (!buf || cap == 0 || !validVol(vol)) return -VE_ERR_INVALID_ARG;
    VE_TRY
    std::string label;
    const int32_t rc = withMounted(vol, "getFilesystemLabel", false, [&](auto&) {
        label = fsGetFilesystemLabel(vol);
        return VE_OK;
    });
    if (rc != VE_OK) return -rc;
    const size_t n = label.size() < cap - 1 ? label.size() : cap - 1;
    std::memcpy(buf, label.data(), n);
    buf[n] = '\0';
    return static_cast<int32_t>(n);
    VE_CATCH(-VE_ERR_EXCEPTION)
}

// ── streams ──────────────────────────────────────────────────────────────

extern "C" VE_API int64_t ve_open_stream(int32_t vol, const char* path) {
    if (!path || !validVol(vol)) return 0;
    VE_TRY
    intptr_t handle = 0;
    const int32_t rc = withMounted(vol, "openStream", false, [&](auto&) {
        handle = reinterpret_cast<intptr_t>(fsOpenStream(vol, path));
        return VE_OK;
    });
    return rc == VE_OK ? static_cast<int64_t>(handle) : 0;
    VE_CATCH(0)
}

extern "C" VE_API int32_t ve_read_stream(int32_t vol, int64_t handle, int64_t offset,
                                         uint8_t* dest, int32_t length) {
    if (handle == 0 || length <= 0 || !dest || offset < 0 || !validVol(vol)) return -1;
    VE_TRY
    std::unique_lock<std::shared_mutex> fsLock(volumes[vol].mutex);
    return fsReadStream(vol, reinterpret_cast<void*>(static_cast<intptr_t>(handle)),
                        static_cast<uint64_t>(offset), dest, static_cast<size_t>(length));
    VE_CATCH(-1)
}

extern "C" VE_API void ve_close_stream(int32_t vol, int64_t handle) {
    if (handle == 0 || !validVol(vol)) return;
    try {
        std::unique_lock<std::shared_mutex> fsLock(volumes[vol].mutex);
        fsCloseStream(vol, reinterpret_cast<void*>(static_cast<intptr_t>(handle)));
    } catch (...) {}
}
