// Desktop implementation of the engine's callback API (jni/jni_callbacks.h).
//
// On Android these functions call into the JVM (Kotlin registries decide whether
// an operation was cancelled, progress goes to Dart through event channels). On
// desktop there is no JVM, so the same API is backed by:
//
//   * a thread-safe event queue the host drains with ve_poll_event(); progress
//     for the same operation is coalesced so a fast copy cannot flood it;
//   * a small registry of operation ids -> {flavor, cancelled} that the host
//     drives through ve_op_register / ve_op_cancel / ve_op_unregister.
//
// The engine core calls these from worker threads; everything here is guarded
// by one mutex and is cheap (no allocation on the cancellation-poll path).

#include "jni_callbacks.h"
#include "ve_engine.h"

#include <algorithm>
#include <cstring>
#include <deque>
#include <mutex>
#include <unordered_map>

// ── JNI globals declared extern in jni_callbacks.h ───────────────────────
// Never dereferenced on desktop; defined (null) so engine translation units
// that still reference them (e.g. session_guard.cpp's throw helpers) link.
JavaVM* g_vm = nullptr;
jclass g_usbBridgeClass = nullptr;
jmethodID g_usbReadMethod = nullptr;
jmethodID g_usbWriteMethod = nullptr;
jmethodID g_usbSyncMethod = nullptr;
jclass g_progressBridgeClass = nullptr;
jmethodID g_progressReportMethod = nullptr;
jclass g_hiddenVolumeProtectionBridgeClass = nullptr;
jmethodID g_hiddenVolumeProtectionTriggeredMethod = nullptr;
jclass g_illegalStateExceptionClass = nullptr;
jclass g_unlockCancelledExceptionClass = nullptr;
jclass g_splitJoinProgressBridgeClass = nullptr;
jmethodID g_splitJoinProgressReportMethod = nullptr;
jclass g_splitJoinCancellationClass = nullptr;
jmethodID g_splitJoinIsCancelledMethod = nullptr;
jclass g_repairLogBridgeClass = nullptr;
jmethodID g_repairLogReportMethod = nullptr;
jclass g_copyProgressBridgeClass = nullptr;
jmethodID g_copyProgressReportMethod = nullptr;
jclass g_copyCancellationClass = nullptr;
jmethodID g_copyIsCancelledMethod = nullptr;
jclass g_importProgressBridgeClass = nullptr;
jmethodID g_importChunkReportMethod = nullptr;
jmethodID g_importIsTrackingMethod = nullptr;
jclass g_importCancellationClass = nullptr;
jmethodID g_importIsCancelledMethod = nullptr;
jclass g_exportProgressBridgeClass = nullptr;
jmethodID g_exportChunkReportMethod = nullptr;
jmethodID g_exportIsTrackingMethod = nullptr;
jclass g_exportCancellationClass = nullptr;
jmethodID g_exportIsCancelledMethod = nullptr;
jclass g_containerSessionRegistryClass = nullptr;
jmethodID g_yieldWriteLockBrieflyMethod = nullptr;
jmethodID g_yieldCopyLocksBrieflyMethod = nullptr;

namespace {

struct OpState {
    int flavor = VE_OP_COPY;  // VE_OP_COPY / VE_OP_IMPORT / VE_OP_EXPORT
    bool cancelled = false;
};

std::mutex g_mu;
std::unordered_map<int, OpState> g_ops;
std::deque<ve_event> g_events;
void (*g_wake)(void) = nullptr;

constexpr size_t kMaxQueuedEvents = 4096;

// Pushes (or coalesces into) the queue. Caller holds g_mu. Returns whether the
// host should be woken.
void pushLocked(const ve_event& ev, bool coalesce) {
    if (coalesce) {
        for (auto it = g_events.rbegin(); it != g_events.rend(); ++it) {
            if (it->kind != ev.kind || it->vol_id != ev.vol_id || it->op_id != ev.op_id) continue;
            if (ev.kind == VE_EVENT_UNLOCK_PROGRESS || ev.kind == VE_EVENT_SPLITJOIN_PROGRESS) {
                *it = ev;                       // latest absolute value wins
            } else {
                it->n0 += ev.n0;                // byte deltas accumulate
            }
            return;
        }
    }
    if (g_events.size() >= kMaxQueuedEvents) {
        // Drop the oldest progress-ish event rather than growing without bound.
        for (auto it = g_events.begin(); it != g_events.end(); ++it) {
            if (it->kind != VE_EVENT_REPAIR_LOG && it->kind != VE_EVENT_HIDDEN_VOLUME_PROTECTION) {
                g_events.erase(it);
                break;
            }
        }
        if (g_events.size() >= kMaxQueuedEvents) g_events.pop_front();
    }
    g_events.push_back(ev);
}

void emit(const ve_event& ev, bool coalesce) {
    void (*wake)(void) = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_mu);
        pushLocked(ev, coalesce);
        wake = g_wake;
    }
    if (wake) wake();
}

bool opCancelled(int opId) {
    if (opId <= 0) return false;
    std::lock_guard<std::mutex> lock(g_mu);
    auto it = g_ops.find(opId);
    return it != g_ops.end() && it->second.cancelled;
}

int opFlavor(int opId) {
    std::lock_guard<std::mutex> lock(g_mu);
    auto it = g_ops.find(opId);
    return it == g_ops.end() ? VE_OP_COPY : it->second.flavor;
}

ve_event makeEvent(int kind, int volId, int opId) {
    ve_event ev;
    std::memset(&ev, 0, sizeof(ev));
    ev.kind = kind;
    ev.vol_id = volId;
    ev.op_id = opId;
    return ev;
}

}  // namespace

// ── Host-facing operation registry / event queue (ve_engine.h) ───────────

extern "C" void ve_set_wake_callback(void (*cb)(void)) {
    std::lock_guard<std::mutex> lock(g_mu);
    g_wake = cb;
}

extern "C" int32_t ve_poll_event(ve_event* out) {
    if (!out) return 0;
    std::lock_guard<std::mutex> lock(g_mu);
    if (g_events.empty()) return 0;
    *out = g_events.front();
    g_events.pop_front();
    return 1;
}

extern "C" void ve_op_register(int32_t op_id, int32_t flavor) {
    if (op_id <= 0) return;
    std::lock_guard<std::mutex> lock(g_mu);
    OpState st;
    st.flavor = (flavor == VE_OP_IMPORT || flavor == VE_OP_EXPORT) ? flavor : VE_OP_COPY;
    g_ops[op_id] = st;
}

extern "C" void ve_op_cancel(int32_t op_id) {
    if (op_id <= 0) return;
    std::lock_guard<std::mutex> lock(g_mu);
    auto it = g_ops.find(op_id);
    if (it != g_ops.end()) it->second.cancelled = true;
}

extern "C" void ve_op_unregister(int32_t op_id) {
    std::lock_guard<std::mutex> lock(g_mu);
    g_ops.erase(op_id);
}

// ── jni_callbacks.h API, desktop implementation ──────────────────────────

void reportUnlockProgress(int volId, int attempted, int total, int hashId,
                          int cipherId, int format, int slot) {
    if (volId < 0) return;
    ve_event ev = makeEvent(VE_EVENT_UNLOCK_PROGRESS, volId, 0);
    ev.i0 = attempted; ev.i1 = total; ev.i2 = hashId; ev.i3 = cipherId; ev.i4 = format;
    ev.n0 = slot;
    emit(ev, /*coalesce=*/true);
}

void reportSplitJoinProgress(int opId, uint64_t bytesDone, uint64_t bytesTotal) {
    if (opId <= 0) return;
    ve_event ev = makeEvent(VE_EVENT_SPLITJOIN_PROGRESS, -1, opId);
    ev.n0 = static_cast<int64_t>(bytesDone);
    ev.n1 = static_cast<int64_t>(bytesTotal);
    emit(ev, true);
}

bool isSplitJoinCancelled(int opId) { return opCancelled(opId); }

void reportRepairLog(int opId, const char* message) {
    if (opId <= 0 || !message) return;
    ve_event ev = makeEvent(VE_EVENT_REPAIR_LOG, -1, opId);
    std::strncpy(ev.text, message, sizeof(ev.text) - 1);
    emit(ev, false);
}

void reportCopyProgress(int opId, uint64_t bytesDelta) {
    if (opId <= 0 || bytesDelta == 0) return;
    ve_event ev = makeEvent(VE_EVENT_COPY_PROGRESS, -1, opId);
    ev.n0 = static_cast<int64_t>(bytesDelta);
    emit(ev, true);
}

bool isCopyCancelled(int opId) { return opCancelled(opId); }

void reportImportChunkProgress(int opId, uint64_t bytesDelta) {
    if (opId <= 0 || bytesDelta == 0) return;
    ve_event ev = makeEvent(VE_EVENT_IMPORT_PROGRESS, -1, opId);
    ev.n0 = static_cast<int64_t>(bytesDelta);
    emit(ev, true);
}

bool isImportCancelled(int opId) { return opCancelled(opId); }
bool isImportTracking(int opId) { return opId > 0 && opFlavor(opId) == VE_OP_IMPORT; }

void reportExportChunkProgress(int opId, uint64_t bytesDelta) {
    if (opId <= 0 || bytesDelta == 0) return;
    ve_event ev = makeEvent(VE_EVENT_EXPORT_PROGRESS, -1, opId);
    ev.n0 = static_cast<int64_t>(bytesDelta);
    emit(ev, true);
}

bool isExportCancelled(int opId) { return opCancelled(opId); }
bool isExportTracking(int opId) { return opId > 0 && opFlavor(opId) == VE_OP_EXPORT; }

// Unified writeBack / extract dispatch -- identical routing to jni_callbacks.cpp.
void reportWriteBackChunkProgress(int opId, uint64_t bytesWritten) {
    if (opId <= 0) return;
    if (isImportTracking(opId)) reportImportChunkProgress(opId, bytesWritten);
    else reportCopyProgress(opId, bytesWritten);
}

bool isWriteBackCancelled(int opId) {
    if (opId <= 0) return false;
    return opCancelled(opId);
}

void reportExtractChunkProgress(int opId, uint64_t bytesWritten) {
    if (opId <= 0) return;
    if (isExportTracking(opId)) reportExportChunkProgress(opId, bytesWritten);
    else reportCopyProgress(opId, bytesWritten);
}

bool isExtractCancelled(int opId) {
    if (opId <= 0) return false;
    return opCancelled(opId);
}

// On Android these let the Kotlin session registry briefly drop its own lock so a
// long copy does not starve other callers. The desktop host has no such lock.
void yieldContainerWriteLock(int) {}
void yieldContainerCopyLocks(int, int) {}

void notifyHiddenVolumeProtectionTriggered(int volId) {
    if (volId < 0) return;
    emit(makeEvent(VE_EVENT_HIDDEN_VOLUME_PROTECTION, volId, 0), false);
}

// Raw USB mass-storage access is Android-only (USB host mode).
bool usbReadSectors(int, uint64_t, uint32_t, unsigned char*) { return false; }
bool usbWriteSectors(int, uint64_t, uint32_t, const unsigned char*) { return false; }
bool usbSyncDevice(int) { return false; }
