#pragma once
#include <cstddef>
#include <cstdint>
#include <jni.h>

extern JavaVM* g_vm;
extern jclass g_usbBridgeClass;
extern jmethodID g_usbReadMethod;
extern jmethodID g_usbWriteMethod;
extern jclass g_progressBridgeClass;
extern jmethodID g_progressReportMethod;
extern jclass g_hiddenVolumeProtectionBridgeClass;
extern jmethodID g_hiddenVolumeProtectionTriggeredMethod;
extern jclass g_illegalStateExceptionClass;
extern jclass g_unlockCancelledExceptionClass;
extern jclass g_splitJoinProgressBridgeClass;
extern jmethodID g_splitJoinProgressReportMethod;
extern jclass g_splitJoinCancellationClass;
extern jmethodID g_splitJoinIsCancelledMethod;
extern jclass g_repairLogBridgeClass;
extern jmethodID g_repairLogReportMethod;
extern jclass g_copyProgressBridgeClass;
extern jmethodID g_copyProgressReportMethod;
extern jclass g_copyCancellationClass;
extern jmethodID g_copyIsCancelledMethod;
extern jclass g_importProgressBridgeClass;
extern jmethodID g_importChunkReportMethod;
extern jclass g_importCancellationClass;
extern jmethodID g_importIsCancelledMethod;

void reportUnlockProgress(int volId, int attempted, int total, int hashId,
                          int cipherId, int format = 0, int slot = 0);
void reportSplitJoinProgress(int opId, uint64_t bytesDone, uint64_t bytesTotal);
bool isSplitJoinCancelled(int opId);
void notifyHiddenVolumeProtectionTriggered(int volId);
// Check & Repair tool: pushes a single human-readable line ("Verifying
// backup header checksum...") to the wizard's live log panel. opId <= 0 is
// a no-op (matches reportSplitJoinProgress's convention) so call sites
// don't need to special-case "logging wasn't requested for this call".
void reportRepairLog(int opId, const char* message);

// Copy/move file-operation byte progress (see CopyProgressBridge.kt). Fired
// per-chunk from filesystem_bridge.cpp's copyFile JNI entry, wrapping
// fs_ops.cpp's CopyProgressCallback. bytesDelta is the size of the chunk
// just written, not a running total (mirrors _addTransferredBytes' delta
// semantics on the Dart side). opId <= 0 is a no-op, same convention as
// reportSplitJoinProgress.
void reportCopyProgress(int opId, uint64_t bytesDelta);
// True once CopyCancellation.cancel(opId) has been called on the Kotlin
// side (see FileOperation.requestCancel() -> vaultExplorerApi.cancelCopy()
// -> FileOperationHandlers.handleCancelCopy()). Checked once per buffer
// iteration alongside reportCopyProgress -- same call site in
// filesystem_bridge.cpp's copyFile callback -- so a cancel lands within
// one chunk instead of only between whole files.
bool isCopyCancelled(int opId);

// Import-side counterparts of the two above, for the raw-file writeBackFile
// path (see ImportProgressBridge.reportChunk / ImportCancellation.isCancelled).
// Kept as separate functions/bridges rather than a fusion of the two --
// opId is one shared numbering space across every FileOperation kind, so
// which Kotlin bridge a given opId's events should reach depends on which
// JNI entry point (copyFile vs writeBackFile) is calling, not on the opId
// value itself.
void reportImportChunkProgress(int opId, uint64_t bytesDelta);
bool isImportCancelled(int opId);

bool usbReadSectors(int volId, uint64_t startSector, uint32_t sectorCount,
                    unsigned char* outBuf);
bool usbWriteSectors(int volId, uint64_t startSector, uint32_t sectorCount,
                     const unsigned char* inBuf);
