// Desktop C ABI over the VaultExplorer engine (see ve_engine.h).
//
// This file is the desktop twin of jni/{session,filesystem,container_lifecycle}_bridge.cpp.
// It deliberately mirrors their locking discipline and ownership rules line for
// line -- requireActiveSession -> (read-only check) -> exclusive volume lock ->
// ensureMounted -> fsXxx -- so behavior on desktop is the behavior Android has
// shipped, only with C types instead of JNI ones.
//
// File-level calls (list, read, write, delete, streams, ...) no longer branch on "container or folder vault":
// both families sit in one vm::VolumeManager (ve_volumes.h) and these functions are thin wrappers over it.
// Sessions (unlock, lock, password change) still use the engine's own state; they register or remove the slot.
//
// NOTE (tech debt, intentional for the first cut): a few bodies (lockSlot, the
// unlock sequence, the copy dual-lock) are duplicated from the JNI bridges so the
// Android build is left completely untouched. A follow-up should hoist them into
// a JNI-free session_ops.{h,cpp} that both bridges call.

#include "ve_engine.h"
#include "ve_volumes.h"
#include "ve_mount_internal.h"
#include "ve_raw_device.h"

#include <algorithm>
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

#include <mbedtls/platform_util.h>

#include "container_create.h"
#include "container_format.h"
#include "container_utils.h"
#include "crypto/single_file_crypto.h"
#include "crypto/user_entropy.h"
#include "platform/engine_log.h"
#include "filesystems/fs_ops.h"
#include "filesystems/stream_handles.h"
#include "platform/engine_hooks.h"
#include "session_guard.h"
#include "session_prepare.h"
#include "virtual_block_device.h"
#include "volman/vm_block_volume.h"
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

#define VE_LOG(...) ENGINE_LOG_INFO("VaultExplorer_C++", __VA_ARGS__)

namespace {
// The portable engine (session/, io/, filesystems/, ...) logs through platform/engine_log.h, which on desktop
// goes to a sink the host installs. This one hands each line to ve_log_dispatch() -- the host's callback, or
// stderr -- but only while the host has switched logging on (ve_set_log_enabled): the lines can name volume ids,
// paths and sizes, so logging stays off by default. The callback keeps receiving Android-style priorities.
void desktopLogSink(int level, const char* tag, const char* message) {
    if (!g_logEnabled.load(std::memory_order_relaxed)) return;
    constexpr int kPrioInfo = 4, kPrioWarn = 5, kPrioError = 6;   // android/log.h's ANDROID_LOG_INFO / WARN / ERROR
    const int prio = level >= ENGINE_LOG_LEVEL_ERROR ? kPrioError : level == ENGINE_LOG_LEVEL_WARN ? kPrioWarn : kPrioInfo;
    ve_log_dispatch(prio, tag, message);
}
// Installed when the library loads, so the lines of an unlock in progress are not lost.
[[maybe_unused]] const bool g_logSinkInstalled = (engineLogSetSink(&desktopLogSink), true);
}  // namespace

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

vm::VolumeManager& mgr() { return ve_internal_volumes(); }

// vm::Status as the ABI's code. A cancelled transfer reports VE_ERR_FAILED, as the block-device path always did
// (VE_ERR_CANCELLED belongs to unlock).
int32_t rcOf(vm::Status s) {
    switch (s) {
        case vm::Status::Ok: return VE_OK;
        case vm::Status::NotUnlocked: return VE_ERR_NOT_UNLOCKED;
        default: return VE_ERR_FAILED;
    }
}

bool isFolderVault(int32_t vol) {
    vm::VolumeManager::Traits t;
    return validVol(vol) && mgr().traits(vol, t) == vm::Status::Ok && t.family == vm::Family::FolderVault;
}

// What every write checks first: the slot must hold a live volume (NOT_UNLOCKED) that allows writes
// (READ_ONLY). `out` receives the traits when the slot is live.
int32_t writeGate(int32_t vol, vm::VolumeManager::Traits* out = nullptr) {
    vm::VolumeManager::Traits t;
    if (mgr().traits(vol, t) != vm::Status::Ok) return VE_ERR_NOT_UNLOCKED;
    if (out) *out = t;
    return t.readOnly ? VE_ERR_READ_ONLY : VE_OK;
}

// Progress and cancellation of a copy between volumes, keyed by the caller's op id.
struct CopyObserver final : vm::Observer {
    explicit CopyObserver(int32_t op) : op_(op) {}
    void onBytes(uint64_t n) override { reportCopyProgress(op_, n); }
    bool cancelled() override { return isCopyCancelled(op_); }
    int32_t op_;
};

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

// Directory entries on the wire: u32 count, then u32-length-prefixed UTF-8 entries. Names come out of an
// untrusted container, so each one gets the same UTF-8 scrub the JNI path applies.
int32_t packWireList(std::vector<std::string>& results, ve_buffer* out) {
    std::vector<uint8_t> packed;
    putU32(packed, static_cast<uint32_t>(results.size()));
    for (auto& entry : results) {
        sanitizeString(entry);
        putU32(packed, static_cast<uint32_t>(entry.size()));
        packed.insert(packed.end(), entry.begin(), entry.end());
    }
    return emitBuffer(packed.data(), packed.size(), out) ? VE_OK : VE_ERR_FAILED;
}

}  // namespace

// ── the slot table ───────────────────────────────────────────────────────

// Leaked on purpose: a BlockVolume touches the global volumes[] table when it closes, and a function-local
// static would be destroyed at an unspecified point relative to that table when the process exits.
vm::VolumeManager& ve_internal_volumes() {
    static vm::VolumeManager* const manager = new vm::VolumeManager(FF_VOLUMES);
    return *manager;
}

bool ve_internal_attach_block(int32_t volId) {
    if (!validVol(volId)) return false;
    auto volume = vm::wrapBlockVolume(volId);
    return volume && mgr().attach(volId, std::move(volume));
}

bool ve_internal_prepare_block_slot(int32_t volId) {
    if (!validVol(volId)) return false;
    if (isFolderVault(volId)) return false;
    // A container that is still registered here is about to be replaced by the session being unlocked:
    // detach it (new calls see NotUnlocked, calls in flight finish) so attach() finds the slot free.
    // Closing a BlockVolume only detaches it; the session itself belongs to the unlock that follows.
    mgr().close(volId);
    return true;
}

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
    if (!ve_internal_prepare_block_slot(volId)) {  // the slot holds an unlocked folder vault
        closeOne(p->fd);
        closeFds(p->keyfile_fds, p->keyfile_count);
        closeFds(p->hidden_keyfile_fds, p->hidden_keyfile_count);
        return VE_ERR_FAILED;
    }
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
    if (!ve_internal_attach_block(volId)) {  // never leave a decrypted session behind that no call can reach
        lockSlot(volId);
        return VE_ERR_FAILED;
    }
    return VE_OK;
    VE_CATCH(VE_ERR_EXCEPTION)
}

// ── raw block devices ────────────────────────────────────────────────────
// The device is attached to the slot first (ffi/ve_raw_device.cpp), because the engine reads it through the
// usbReadSectors / usbWriteSectors hooks, which are keyed by slot. prepareUsbSession is the same call the
// Android USB path uses: it scans the partitions for LUKS / BitLocker and tries VeraCrypt on each.

extern "C" VE_API int32_t ve_list_block_devices(ve_buffer* out) {
    if (!out) return VE_ERR_INVALID_ARG;
    out->data = nullptr;
    out->len = 0;
    VE_TRY
    const std::string json = veraw::devicesToJson(veraw::listDevices());
    return emitBuffer(reinterpret_cast<const uint8_t*>(json.data()), json.size(), out) ? VE_OK : VE_ERR_FAILED;
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_unlock_device(const ve_unlock_device_params* p) {
    auto closeAllFds = [](const ve_unlock_device_params* q) {
        closeFds(q->keyfile_fds, q->keyfile_count);
        closeFds(q->hidden_keyfile_fds, q->hidden_keyfile_count);
    };
    if (!p || p->struct_size < static_cast<int32_t>(sizeof(ve_unlock_device_params))) {
        if (p) closeAllFds(p);
        return VE_ERR_INVALID_ARG;
    }
    if (!p->device_path || !p->device_path[0] || !validVol(p->vol_id) || p->password_len < 0 || p->keyfile_count < 0) {
        closeAllFds(p);
        return VE_ERR_INVALID_ARG;
    }
    if (p->os_error_out) *p->os_error_out = 0;
    VE_TRY
    const int volId = p->vol_id;
    if (!ve_internal_prepare_block_slot(volId)) {  // the slot holds an unlocked folder vault
        closeAllFds(p);
        return VE_ERR_FAILED;
    }
    clearUnlockCancellation(volId);

    uint64_t deviceSize = 0;
    int osError = 0;
    switch (veraw::attach(volId, p->device_path, /*writable=*/p->read_only == 0, &deviceSize, &osError)) {
        case veraw::AttachResult::kOk: break;
        case veraw::AttachResult::kNotFound: closeAllFds(p); if (p->os_error_out) *p->os_error_out = osError; return VE_ERR_DEVICE_NOT_FOUND;
        case veraw::AttachResult::kPermission: closeAllFds(p); if (p->os_error_out) *p->os_error_out = osError; return VE_ERR_DEVICE_PERMISSION;
        case veraw::AttachResult::kBusy: closeAllFds(p); if (p->os_error_out) *p->os_error_out = osError; return VE_ERR_DEVICE_BUSY;
        default: closeAllFds(p); if (p->os_error_out) *p->os_error_out = osError; return VE_ERR_DEVICE_OPEN;
    }

    static const unsigned char kEmpty[1] = {0};
    const unsigned char* pw = p->password ? p->password : kEmpty;
    const size_t pwLen = p->password ? static_cast<size_t>(p->password_len) : 0;

    if (!prepareUsbSession(pw, pwLen, p->pim, volId, p->cipher_id, p->hash_id,
                           p->preserved_key, p->preserved_key ? static_cast<size_t>(p->preserved_key_len) : 0,
                           p->partition_offset_hint,
                           p->keyfile_count > 0 ? p->keyfile_fds : nullptr, p->keyfile_count,
                           p->read_only != 0, /*useBackupHeader=*/false, static_cast<int64_t>(deviceSize))) {
        // prepareUsbSession owns (and has closed) the keyfile fds on every path.
        closeFds(p->hidden_keyfile_fds, p->hidden_keyfile_count);
        veraw::detach(volId);
        return isUnlockCancelled(volId) ? VE_ERR_CANCELLED : VE_ERR_FAILED;
    }

    {
        std::unique_lock<std::shared_mutex> lock(volumes[volId].mutex);
        volumes[volId].fileSize = deviceSize;
    }
    bool mountOk;
    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[volId].mutex);
        mountOk = ensureMounted(volId);
    }
    if (!mountOk) {
        VE_LOG("file system mount failed on device volume %d", volId);
        closeFds(p->hidden_keyfile_fds, p->hidden_keyfile_count);
        lockSlot(volId);
        veraw::detach(volId);
        return VE_ERR_MOUNT_FAILED;
    }

    if (p->hidden_password != nullptr) {
        if (!enableHiddenVolumeProtection(
                volId, p->hidden_password, static_cast<size_t>(p->hidden_password_len),
                p->hidden_pim, p->hidden_cipher_id, p->hidden_hash_id,
                p->hidden_keyfile_count > 0 ? p->hidden_keyfile_fds : nullptr,
                p->hidden_keyfile_count)) {
            lockSlot(volId);
            veraw::detach(volId);
            return VE_ERR_FAILED;
        }
    } else {
        closeFds(p->hidden_keyfile_fds, p->hidden_keyfile_count);
    }
    if (!ve_internal_attach_block(volId)) {  // never leave a decrypted session behind that no call can reach
        lockSlot(volId);
        veraw::detach(volId);
        return VE_ERR_FAILED;
    }
    return VE_OK;
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API void ve_request_cancel_unlock(int32_t vol_id) {
    if (validVol(vol_id)) requestUnlockCancellation(vol_id);
}

extern "C" VE_API void ve_lock(int32_t vol_id) {
    try {
        // OS mounts first: they commit pending writes through this very slot, and must be gone before the
        // keys are wiped (otherwise a live mount would hand out errors -- or worse, stale data).
        ve_internal_unmount_volume(vol_id);
        const bool folderVault = isFolderVault(vol_id);
        // New calls see NotUnlocked from here on; streams end and calls in flight finish. Closing a folder vault
        // wipes its keys; a container is only detached -- the session below is what actually locks it.
        if (validVol(vol_id)) mgr().close(vol_id);
        if (!folderVault) {
            lockSlot(vol_id);       // flushes + syncs a raw device's write cache (unmountVolume), then wipes the keys
            veraw::detach(vol_id);  // closes the raw disk (no-op for slots that never had one)
        }
    } catch (...) {}
}

extern "C" VE_API int32_t ve_get_container_format(int32_t vol_id) {
    if (!validVol(vol_id)) return -1;
    if (const int32_t fvFormat = vefv::containerFormat(vol_id); fvFormat >= 0) return fvFormat;
    std::shared_lock<std::shared_mutex> lock(volumes[vol_id].mutex);
    return static_cast<int32_t>(volumes[vol_id].containerFormat);
}

extern "C" VE_API int32_t ve_get_matched_cipher_id(int32_t vol_id) {
    if (!validVol(vol_id)) return -1;
    if (isFolderVault(vol_id)) return 255;  // folder vaults have no cascade to report
    std::shared_lock<std::shared_mutex> lock(volumes[vol_id].mutex);
    return static_cast<int32_t>(volumes[vol_id].matchedCipherId);
}

extern "C" VE_API int32_t ve_get_matched_hash_id(int32_t vol_id) {
    if (!validVol(vol_id)) return -1;
    if (isFolderVault(vol_id)) return 255;
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

// ── single-file encryption ───────────────────────────────────────────────

extern "C" VE_API int32_t ve_single_file_crypt(const ve_single_file_params* p) {
    if (!p || p->struct_size < static_cast<int32_t>(sizeof(ve_single_file_params)) || p->password_len < 0 ||
        p->keyfile_count < 0 || p->src_fd < 0 || p->dest_fd < 0) {
        if (p) {
            closeOne(p->src_fd);
            closeOne(p->dest_fd);
            closeFds(p->keyfile_fds, p->keyfile_count);
        }
        return VE_ERR_INVALID_ARG;
    }
    VE_TRY
    const int opId = p->op_id;
    auto cancelCheck = [opId]() -> bool { return opId > 0 && isSplitJoinCancelled(opId); };
    auto progress = [opId](uint64_t done, uint64_t total) {
        if (opId > 0) reportSplitJoinProgress(opId, done, total);
    };
    static const unsigned char kEmpty[1] = {0};
    const unsigned char* pw = p->password ? p->password : kEmpty;
    const size_t pwLen = p->password ? static_cast<size_t>(p->password_len) : 0;
    const int* kf = p->keyfile_count > 0 ? p->keyfile_fds : nullptr;

    const bool ok = p->encrypt
        ? encryptSingleFile(p->src_fd, p->dest_fd, p->cipher_index, pw, pwLen, kf, p->keyfile_count, opId, cancelCheck, progress)
        : decryptSingleFile(p->src_fd, p->dest_fd, pw, pwLen, kf, p->keyfile_count, opId, cancelCheck, progress);
    const bool cancelled = !ok && cancelCheck();
    closeOne(p->src_fd);   // the engine routine does not close these; keyfile fds it consumes itself
    closeOne(p->dest_fd);
    if (ok) return VE_OK;
    return cancelled ? VE_ERR_CANCELLED : VE_ERR_FAILED;
    VE_CATCH(VE_ERR_EXCEPTION)
}

// ── password change ──────────────────────────────────────────────────────

extern "C" VE_API int32_t ve_change_password(const ve_change_password_params* p) {
    if (!p || p->struct_size < static_cast<int32_t>(sizeof(ve_change_password_params)) ||
        p->old_password_len < 0 || p->new_password_len < 0 || p->old_keyfile_count < 0 ||
        p->new_keyfile_count < 0 || (p->new_password_len == 0 && p->new_keyfile_count == 0)) {
        if (p) {
            closeOne(p->fd);
            closeFds(p->old_keyfile_fds, p->old_keyfile_count);
            closeFds(p->new_keyfile_fds, p->new_keyfile_count);
        }
        return VE_ERR_INVALID_ARG;
    }
    VE_TRY
    std::string oldPass(p->old_password ? reinterpret_cast<const char*>(p->old_password) : "",
                        p->old_password ? static_cast<size_t>(p->old_password_len) : 0);
    std::string newPass(p->new_password ? reinterpret_cast<const char*>(p->new_password) : "",
                        p->new_password ? static_cast<size_t>(p->new_password_len) : 0);
    const int* oldKf = p->old_keyfile_count > 0 ? p->old_keyfile_fds : nullptr;
    const int* newKf = p->new_keyfile_count > 0 ? p->new_keyfile_fds : nullptr;

    int32_t rc;
    if (p->container_format == 1 || p->container_format == 2) {
        const int outcome = changeLuksContainerPassword(p->fd, oldPass.c_str(), newPass.c_str(),
                                                        oldKf, p->old_keyfile_count, newKf, p->new_keyfile_count);
        rc = outcome == 0 ? VE_OK : (outcome == 1 ? VE_ERR_AUTH_FAILED : VE_ERR_FAILED);
    } else {
        rc = okOrFailed(changeContainerPassword(p->fd, oldPass.c_str(), newPass.c_str(), p->old_pim, p->new_pim,
                                                p->cipher_id, p->hash_id, oldKf, p->old_keyfile_count, newKf,
                                                p->new_keyfile_count));
    }
    mbedtls_platform_zeroize(oldPass.data(), oldPass.size());
    mbedtls_platform_zeroize(newPass.data(), newPass.size());
    return rc;
    VE_CATCH(VE_ERR_EXCEPTION)
}

// ── filesystem operations ────────────────────────────────────────────────
// Every call below asks the slot table (ve_volumes.h) for the volume in `vol`; the manager answers
// NotUnlocked for an empty slot, so no call needs to know whether a container or a folder vault is behind it.
// Block-device volumes keep the quirks their ABI always had (marked "legacy" where they differ from folder vaults).

extern "C" VE_API int32_t ve_list_directory(int32_t vol, const char* path, ve_buffer* out) {
    if (!out) return VE_ERR_INVALID_ARG;
    out->data = nullptr;
    out->len = 0;
    if (!path || !validVol(vol)) return VE_ERR_INVALID_ARG;
    VE_TRY
    vm::VolumeManager::Traits t;
    if (mgr().traits(vol, t) != vm::Status::Ok) return VE_ERR_NOT_UNLOCKED;
    std::vector<std::string> results;
    results.reserve(256);
    const vm::Status st = mgr().listDirectory(vol, path, results);
    if (st == vm::Status::NotUnlocked) return VE_ERR_NOT_UNLOCKED;
    if (st != vm::Status::Ok) {
        if (t.family == vm::Family::FolderVault) return VE_ERR_FAILED;
        // Legacy: a block-device folder that cannot be read lists as empty (the callers -- browsing, the mount
        // layer, archive part discovery -- were written against that). Only a session that ended meanwhile is an error.
        if (!mgr().isUnlocked(vol)) return VE_ERR_NOT_UNLOCKED;
        results.clear();
    }
    return packWireList(results, out);
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_list_symlinks(int32_t vol, const char* path, ve_buffer* out) {
    if (!out) return VE_ERR_INVALID_ARG;
    out->data = nullptr;
    out->len = 0;
    if (!path || !validVol(vol)) return VE_ERR_INVALID_ARG;
    VE_TRY
    std::vector<std::string> results;
    const vm::Status st = mgr().listSymlinks(vol, path, results);
    if (st != vm::Status::Ok) return rcOf(st);
    return packWireList(results, out);
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_read_symlink(int32_t vol, const char* path, ve_buffer* out) {
    if (!out) return VE_ERR_INVALID_ARG;
    out->data = nullptr;
    out->len = 0;
    if (!path || !validVol(vol)) return VE_ERR_INVALID_ARG;
    VE_TRY
    std::string target;
    const vm::Status st = mgr().readSymlink(vol, path, target);
    if (st != vm::Status::Ok) return rcOf(st);
    return emitBuffer(reinterpret_cast<const uint8_t*>(target.data()), target.size(), out) ? VE_OK : VE_ERR_FAILED;
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_create_symlink(int32_t vol, const char* path, const char* target) {
    if (!path || !target || !validVol(vol)) return VE_ERR_INVALID_ARG;
    VE_TRY
    if (const int32_t gate = writeGate(vol); gate != VE_OK) return gate;
    return rcOf(mgr().createSymlink(vol, path, target));
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int64_t ve_get_file_size(int32_t vol, const char* path) {
    if (!path || !validVol(vol)) return -VE_ERR_INVALID_ARG;
    VE_TRY
    int64_t size = -1;
    const vm::Status st = mgr().getFileSize(vol, path, size);
    if (st == vm::Status::NotUnlocked) return -static_cast<int64_t>(VE_ERR_NOT_UNLOCKED);
    return st == vm::Status::Ok && size >= 0 ? size : -1;  // -1: missing, or a directory
    VE_CATCH(-VE_ERR_EXCEPTION)
}

extern "C" VE_API int64_t ve_get_folder_size(int32_t vol, const char* path) {
    if (!path || !validVol(vol)) return -VE_ERR_INVALID_ARG;
    VE_TRY
    int64_t total = -1;
    const vm::Status st = mgr().getFolderSize(vol, path, total);
    if (st != vm::Status::Ok || total < 0) return -static_cast<int64_t>(rcOf(st == vm::Status::Ok ? vm::Status::Failed : st));
    return total;
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
    vm::VolumeManager::Traits t;
    if (mgr().traits(vol, t) != vm::Status::Ok) return VE_ERR_NOT_UNLOCKED;
    std::vector<uint8_t> buffer;
    const vm::Status st = mgr().readFileChunk(vol, path, offset, static_cast<size_t>(length), buffer);
    if (st != vm::Status::Ok) return rcOf(st);
    // Legacy: a block-device read that returns no bytes (end of file) is VE_ERR_FAILED, as ve_engine.h says;
    // a folder vault answers OK with an empty buffer. Both mean "no more data" to the callers.
    if (buffer.empty() && t.family == vm::Family::BlockDevice) return VE_ERR_FAILED;
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
    if (const int32_t gate = writeGate(vol); gate != VE_OK) return gate;
    static const uint8_t kNone = 0;  // a zero-length write at offset 0 still creates / empties the file
    return rcOf(mgr().writeFileChunk(vol, path, offset, data ? data : &kNone, len));
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_delete_file(int32_t vol, const char* path) {
    if (!path || !validVol(vol)) return VE_ERR_INVALID_ARG;
    VE_TRY
    if (const int32_t gate = writeGate(vol); gate != VE_OK) return gate;
    return rcOf(mgr().deleteFile(vol, path));
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_create_directory(int32_t vol, const char* path) {
    if (!path || !validVol(vol)) return VE_ERR_INVALID_ARG;
    VE_TRY
    if (const int32_t gate = writeGate(vol); gate != VE_OK) return gate;
    return rcOf(mgr().createDirectory(vol, path));
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_rename_file(int32_t vol, const char* old_path, const char* new_path) {
    if (!old_path || !new_path || !validVol(vol)) return VE_ERR_INVALID_ARG;
    VE_TRY
    if (const int32_t gate = writeGate(vol); gate != VE_OK) return gate;
    return rcOf(mgr().renameFile(vol, old_path, new_path));
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_set_last_modified(int32_t vol, const char* path, int64_t epoch_seconds) {
    if (!path || !validVol(vol) || epoch_seconds < 0) return VE_ERR_INVALID_ARG;
    VE_TRY
    if (const int32_t gate = writeGate(vol); gate != VE_OK) return gate;
    return rcOf(mgr().setLastModifiedTime(vol, path, epoch_seconds));
    VE_CATCH(VE_ERR_EXCEPTION)
}

// ── random-access writes (desktop mount layer) ───────────────────────────────────────────────────────

extern "C" VE_API int32_t ve_write_file_at(int32_t vol, const char* path, int64_t offset, const uint8_t* data, size_t len) {
    if (!path || !validVol(vol) || offset < 0 || len > kMaxChunk || (len > 0 && !data)) return VE_ERR_INVALID_ARG;
    VE_TRY
    vm::VolumeManager::Traits t;
    if (const int32_t gate = writeGate(vol, &t); gate == VE_ERR_NOT_UNLOCKED) return gate;
    if (!t.randomWrites) return VE_ERR_UNSUPPORTED;  // folder vaults write sequentially (see ve_fv_finish_write)
    if (t.readOnly) return VE_ERR_READ_ONLY;
    static const uint8_t kNone = 0;
    return rcOf(mgr().writeFileAt(vol, path, offset, data ? data : &kNone, len));
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_truncate(int32_t vol, const char* path, int64_t size) {
    if (!path || !validVol(vol) || size < 0) return VE_ERR_INVALID_ARG;
    VE_TRY
    vm::VolumeManager::Traits t;
    if (const int32_t gate = writeGate(vol, &t); gate == VE_ERR_NOT_UNLOCKED) return gate;
    if (!t.randomWrites) return VE_ERR_UNSUPPORTED;
    if (t.readOnly) return VE_ERR_READ_ONLY;
    return rcOf(mgr().truncateFile(vol, path, size));
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_create_empty_file(int32_t vol, const char* path) {
    if (!path || !validVol(vol)) return VE_ERR_INVALID_ARG;
    VE_TRY
    if (const int32_t gate = writeGate(vol); gate != VE_OK) return gate;
    return rcOf(mgr().createEmptyFile(vol, path));
    VE_CATCH(VE_ERR_EXCEPTION)
}

// Facts the mount layer needs that the public ABI does not carry (see ve_mount_internal.h).
bool ve_internal_vol_traits(int32_t vol, bool* folderVault, bool* caseInsensitive, bool* readOnly) {
    vm::VolumeManager::Traits t;
    if (!validVol(vol) || mgr().traits(vol, t) != vm::Status::Ok) return false;
    if (folderVault) *folderVault = t.family == vm::Family::FolderVault;
    if (caseInsensitive) *caseInsensitive = t.caseInsensitive;
    if (readOnly) *readOnly = t.readOnly;
    return true;
}

// ── whole-file transfers ─────────────────────────────────────────────────

extern "C" VE_API int32_t ve_import_file(int32_t vol, const char* vault_path,
                                         const char* host_source_path, int32_t op_id) {
    if (!vault_path || !host_source_path || !validVol(vol)) return VE_ERR_INVALID_ARG;
    VE_TRY
    if (isFolderVault(vol)) return vefv::importFile(vol, vault_path, host_source_path, op_id);
    // Containers copy through the filesystem backends' own host-file path, which holds the volume lock for the
    // whole file and yields it between chunks.
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
    if (isFolderVault(vol)) return vefv::exportFile(vol, vault_path, host_dest_path, op_id);
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
    vm::VolumeManager::Traits srcTraits, destTraits;
    if (mgr().traits(srcVol, srcTraits) != vm::Status::Ok || mgr().traits(destVol, destTraits) != vm::Status::Ok) {
        return VE_ERR_NOT_UNLOCKED;
    }
    if (destTraits.readOnly) return VE_ERR_READ_ONLY;

    // A folder vault on either side: through memory in 2 MiB steps, one chunk at a time, nothing staged on disk;
    // a failed or cancelled copy removes the partial destination (vm::VolumeManager::copyFile).
    if (srcTraits.family == vm::Family::FolderVault || destTraits.family == vm::Family::FolderVault) {
        CopyObserver observer(opId);
        return rcOf(mgr().copyFile(srcVol, srcPath, destVol, destPath, &observer));
    }

    // Container to container keeps the filesystem backends' own copy, which has same-filesystem fast paths.
    if (!requireActiveSession(srcVol, "copyFile (src)")) return VE_ERR_NOT_UNLOCKED;
    if (!requireActiveSession(destVol, "copyFile (dest)")) return VE_ERR_NOT_UNLOCKED;

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

// ── volume info ──────────────────────────────────────────────────────────

extern "C" VE_API int32_t ve_get_space_info(int32_t vol, uint64_t* total, uint64_t* free_bytes) {
    if (!total || !free_bytes || !validVol(vol)) return VE_ERR_INVALID_ARG;
    VE_TRY
    vm::VolumeManager::Traits t;
    if (mgr().traits(vol, t) != vm::Status::Ok) return VE_ERR_NOT_UNLOCKED;
    vm::SpaceInfo si;
    const vm::Status st = mgr().spaceInfo(vol, si);
    if (st == vm::Status::NotUnlocked) return VE_ERR_NOT_UNLOCKED;
    if (st != vm::Status::Ok) {
        if (t.family == vm::Family::FolderVault) return VE_ERR_FAILED;
        // Legacy: a container whose filesystem cannot say reports 0 / 0 rather than an error.
        if (!mgr().isUnlocked(vol)) return VE_ERR_NOT_UNLOCKED;
        si = vm::SpaceInfo{0, 0};
    }
    *total = si.total > 0 ? static_cast<uint64_t>(si.total) : 0;
    *free_bytes = si.free > 0 ? static_cast<uint64_t>(si.free) : 0;
    return VE_OK;
    VE_CATCH(VE_ERR_EXCEPTION)
}

extern "C" VE_API int32_t ve_get_filesystem_label(int32_t vol, char* buf, size_t cap) {
    if (!buf || cap == 0 || !validVol(vol)) return -VE_ERR_INVALID_ARG;
    VE_TRY
    vm::VolumeManager::Traits t;
    if (mgr().traits(vol, t) != vm::Status::Ok) return -VE_ERR_NOT_UNLOCKED;
    if (t.family == vm::Family::FolderVault) { buf[0] = '\0'; return 0; }  // folder vaults have no filesystem label
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

extern "C" VE_API int32_t ve_get_vault_info(int32_t vol, ve_vault_info* out) {
    if (!out || out->struct_size < static_cast<int32_t>(sizeof(ve_vault_info)) || !validVol(vol)) {
        return VE_ERR_INVALID_ARG;
    }
    VE_TRY
    if (isFolderVault(vol)) return vefv::vaultInfo(vol, out);
    if (!requireActiveSession(vol, "getVaultInfo")) return VE_ERR_NOT_UNLOCKED;
    const int32_t size = out->struct_size;
    std::memset(out, 0, sizeof(*out));
    out->struct_size = size;

    // Same sequence as the JNI bridge: crypto/session fields from VolumeState, and a best-effort
    // mount so the filesystem label is available even if the file browser was never opened.
    std::string label;
    {
        std::unique_lock<std::shared_mutex> fsLock(volumes[vol].mutex);
        VolumeState& v = volumes[vol];
        out->container_format = static_cast<int32_t>(v.containerFormat);
        out->read_only = v.readOnly ? 1 : 0;
        out->hidden_volume = v.isHiddenVolume ? 1 : 0;
        out->volume_size_bytes = static_cast<int64_t>(v.dataAreaLengthBytes);
        out->cipher_id = static_cast<int32_t>(v.matchedCipherId);
        out->hash_id = static_cast<int32_t>(v.matchedHashId);
        out->sector_size = static_cast<int32_t>(v.luksSectorSize);
        if (ensureMounted(vol)) label = fsGetFilesystemLabel(vol);
    }
    switch (static_cast<ContainerFormat>(out->container_format)) {
        case ContainerFormat::kVeraCrypt:
            out->has_cipher_hash = 1;
            break;
        case ContainerFormat::kLuks1:
        case ContainerFormat::kLuks2:
            out->has_cipher_hash = 1;
            out->luks_version = static_cast<ContainerFormat>(out->container_format) == ContainerFormat::kLuks1 ? 1 : 2;
            break;
        default:  // BitLocker etc.: only size / read-only / filesystem are known
            out->cipher_id = 0;
            out->hash_id = 0;
            out->sector_size = 0;
            break;
    }
    if (static_cast<ContainerFormat>(out->container_format) != ContainerFormat::kLuks1 &&
        static_cast<ContainerFormat>(out->container_format) != ContainerFormat::kLuks2) {
        out->sector_size = 0;
    }
    if (!label.empty()) {
        out->has_file_system = 1;
        std::strncpy(out->file_system, label.c_str(), sizeof(out->file_system) - 1);
    }
    return VE_OK;
    VE_CATCH(VE_ERR_EXCEPTION)
}

// ── streams ──────────────────────────────────────────────────────────────
// Handles come from the manager: unique across volumes, never reused, and ended when their volume closes.
// A container's streams are native (an open file of the mounted filesystem); a folder vault's are emulated with
// positioned reads.

extern "C" VE_API int64_t ve_open_stream(int32_t vol, const char* path) {
    if (!path || !validVol(vol)) return 0;
    VE_TRY
    uint64_t handle = 0;
    return mgr().openStream(vol, path, handle) == vm::Status::Ok ? static_cast<int64_t>(handle) : 0;
    VE_CATCH(0)
}

extern "C" VE_API int32_t ve_read_stream(int32_t vol, int64_t handle, int64_t offset,
                                         uint8_t* dest, int32_t length) {
    if (handle == 0 || length <= 0 || !dest || offset < 0 || !validVol(vol)) return -1;
    VE_TRY
    const int64_t n = mgr().readStream(vol, static_cast<uint64_t>(handle), static_cast<uint64_t>(offset),
                                       dest, static_cast<size_t>(length));
    return n < 0 ? -1 : static_cast<int32_t>(n);
    VE_CATCH(-1)
}

extern "C" VE_API void ve_close_stream(int32_t vol, int64_t handle) {
    if (handle == 0 || !validVol(vol)) return;
    try {
        mgr().closeStream(vol, static_cast<uint64_t>(handle));
    } catch (...) {}
}
