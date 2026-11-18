// JNI bridge for the platform-neutral volume manager (../volman).
//
// Kotlin side: com.aeidolon.vaultexplorer.volman.NativeVolumeManager.
//
// This is deliberately a thin start: the manager can already do far more (listing, chunked
// I/O, streams -- see volman/vm_manager.h), but the Android app moves over one operation at
// a time. Today that is copying a file between any two unlocked volumes, which is what
// ContainerFileSystem.copyFileStreaming used to do chunk by chunk across JNI.
//
// Slots are filled lazily and cleaned up for free. Kotlin calls nativeAttach* right before
// it needs a volume in the manager; nothing has to hook "unlocked" / "locked" events:
//   * a block-device slot dies when the session layer locks the container -- VolumeState's
//     session epoch changes, vm::BlockVolume::alive() turns false, and the manager frees the
//     slot on the next attach;
//   * a folder-vault slot dies when anyone closes the vault (NativeFolderVault.nativeClose
//     included), which fv::Vault::closed() reports.
// Every attach carries a tag naming the session (Kotlin passes one that is unique per
// unlock), so a slot that still belongs to another live session is never taken over.
//
// Strings cross as UTF-16 -> UTF-8 (jni_utf8.h), not NewStringUTF/GetStringUTFChars.
#include <jni.h>
#include <android/log.h>

#include <memory>
#include <string>

#include "jni_bridge_common.h"
#include "jni_callbacks.h"
#include "jni_utf8.h"
#include "foldervault_registry.h"
#include "volman/vm_block_volume.h"
#include "volman/vm_foldervault.h"
#include "volman/vm_manager.h"

namespace {

vm::VolumeManager& manager() {
    // Never destroyed: at process exit its destructor would close volumes while engine globals
    // such as volumes[] may already be gone.
    static vm::VolumeManager* m = new vm::VolumeManager(MAX_VOLUMES);
    return *m;
}

// NativeVolumeManager.COPY_*.
constexpr jint kCopyOk = 0;
constexpr jint kCopyFailed = 1;
constexpr jint kCopyNotAttached = 2;
constexpr jint kCopyCancelled = 3;

// Progress and cancellation of a copy, on the same per-operation channels the other native copy
// paths use (CopyProgressBridge / CopyCancellation, keyed by opId). opId <= 0 means "not tracked".
class CopyObserver final : public vm::Observer {
public:
    explicit CopyObserver(int opId) : opId_(opId) {}
    void onBytes(uint64_t bytes) override {
        if (opId_ > 0) reportCopyProgress(opId_, bytes);
    }
    bool cancelled() override { return opId_ > 0 && isCopyCancelled(opId_); }

private:
    int opId_;
};

// True when `volId` holds a live volume tagged `tag` afterwards: the one just attached, or one an
// earlier call (or a racing thread) attached for the same session. A slot held by a *different*
// live session is left alone and reported as false, so the caller keeps using its own path.
template <class Make>
bool attachTagged(int volId, const std::string& tag, Make&& make) {
    vm::VolumeManager& m = manager();
    if (m.isUnlocked(volId)) return m.tagOf(volId) == tag;
    std::shared_ptr<vm::Volume> v = make();
    if (!v || !v->alive()) return false;
    if (m.attach(volId, std::move(v), tag)) return true;
    return m.isUnlocked(volId) && m.tagOf(volId) == tag;
}

}  // namespace

#define VM_JNI(ret, name) extern "C" JNIEXPORT ret JNICALL Java_com_aeidolon_vaultexplorer_volman_NativeVolumeManager_##name

// Probe for NativeVolumeManager.isAvailable: resolves the library, does nothing else.
VM_JNI(void, nativeInit)(JNIEnv*, jclass) {}

// Puts the engine's block-device volume `volId` into manager slot `volId`. False when that
// volume is not unlocked, or the slot belongs to another live session.
VM_JNI(jboolean, nativeAttachBlock)(JNIEnv* env, jclass, jint volId, jstring tag) {
    JNI_TRY
    if (volId < 0 || volId >= MAX_VOLUMES) return JNI_FALSE;
    const std::string t = jniStringToUtf8(env, tag);
    return attachTagged(volId, t,
                        [&]() -> std::shared_ptr<vm::Volume> { return vm::wrapBlockVolume(volId); })
               ? JNI_TRUE
               : JNI_FALSE;
    JNI_CATCH_RETURN(JNI_FALSE)
}

// Puts the folder vault behind NativeFolderVault handle `handle` into manager slot `volId`. The
// manager and the handle's registry share one session. False for an unknown or closed handle, or
// when the slot belongs to another live session.
VM_JNI(jboolean, nativeAttachFolderVault)(JNIEnv* env, jclass, jint volId, jlong handle, jstring tag) {
    JNI_TRY
    if (volId < 0 || volId >= MAX_VOLUMES) return JNI_FALSE;
    const std::string t = jniStringToUtf8(env, tag);
    return attachTagged(volId, t,
                        [&]() -> std::shared_ptr<vm::Volume> {
                            auto vault = foldervaultShare(handle);
                            if (!vault) return nullptr;
                            return vm::wrapFolderVault(std::move(vault));
                        })
               ? JNI_TRUE
               : JNI_FALSE;
    JNI_CATCH_RETURN(JNI_FALSE)
}

// Does manager slot `volId` hold a live volume attached with this tag?
VM_JNI(jboolean, nativeIsAttached)(JNIEnv* env, jclass, jint volId, jstring tag) {
    JNI_TRY
    if (volId < 0 || volId >= MAX_VOLUMES) return JNI_FALSE;
    vm::VolumeManager& m = manager();
    return (m.isUnlocked(volId) && m.tagOf(volId) == jniStringToUtf8(env, tag)) ? JNI_TRUE : JNI_FALSE;
    JNI_CATCH_RETURN(JNI_FALSE)
}

// Copies one file between two attached volumes (any families, the same volume allowed), through
// memory only -- no temp file for any pair. Replaces the destination; a copy that fails or is
// cancelled deletes what it created under `dstPath`. Progress and cancellation follow `opId`
// (0 = untracked). Returns NativeVolumeManager.COPY_*: OK, FAILED, NOT_ATTACHED (a slot is empty
// or its container was locked: the caller should fall back), CANCELLED.
VM_JNI(jint, nativeCopyFile)(JNIEnv* env, jclass, jint srcVol, jstring srcPath, jint dstVol, jstring dstPath, jint opId) {
    JNI_TRY
    const std::string src = jniStringToUtf8(env, srcPath);
    const std::string dst = jniStringToUtf8(env, dstPath);
    CopyObserver obs(opId);
    switch (manager().copyFile(srcVol, src, dstVol, dst, &obs)) {
        case vm::Status::Ok: return kCopyOk;
        case vm::Status::NotUnlocked: return kCopyNotAttached;
        case vm::Status::Cancelled: return kCopyCancelled;
        case vm::Status::Failed: break;
    }
    return kCopyFailed;
    JNI_CATCH_RETURN(kCopyFailed)
}
