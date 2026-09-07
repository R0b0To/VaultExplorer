#pragma once
#include <cstddef>
#include <cstdint>
#include <jni.h>

extern JavaVM* g_vm;
extern jclass g_usbBridgeClass;
extern jmethodID g_usbReadMethod;
extern jmethodID g_usbWriteMethod;
extern jmethodID g_usbSyncMethod;
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
extern jmethodID g_importIsTrackingMethod;
extern jclass g_importCancellationClass;
extern jmethodID g_importIsCancelledMethod;
extern jclass g_exportProgressBridgeClass;
extern jmethodID g_exportChunkReportMethod;
extern jmethodID g_exportIsTrackingMethod;
extern jclass g_exportCancellationClass;
extern jmethodID g_exportIsCancelledMethod;
extern jclass g_containerSessionRegistryClass;
extern jmethodID g_yieldWriteLockBrieflyMethod;
extern jmethodID g_yieldCopyLocksBrieflyMethod;

void reportUnlockProgress(int volId, int attempted, int total, int hashId,
                          int cipherId, int format = 0, int slot = 0);
void reportSplitJoinProgress(int opId, uint64_t bytesDone, uint64_t bytesTotal);
bool isSplitJoinCancelled(int opId);
void notifyHiddenVolumeProtectionTriggered(int volId);
void reportRepairLog(int opId, const char* message);
void reportCopyProgress(int opId, uint64_t bytesDelta);
bool isCopyCancelled(int opId);
void reportImportChunkProgress(int opId, uint64_t bytesDelta);
bool isImportCancelled(int opId);
bool isImportTracking(int opId);
void reportExportChunkProgress(int opId, uint64_t bytesDelta);
bool isExportCancelled(int opId);
bool isExportTracking(int opId);

// Unified writeBack / extract progress and cancellation dispatch:
void reportWriteBackChunkProgress(int opId, uint64_t bytesWritten);
bool isWriteBackCancelled(int opId);
void reportExtractChunkProgress(int opId, uint64_t bytesWritten);
bool isExtractCancelled(int opId);

void yieldContainerWriteLock(int volId);
void yieldContainerCopyLocks(int srcVolId, int destVolId);

bool usbReadSectors(int volId, uint64_t startSector, uint32_t sectorCount,
                    unsigned char* outBuf);
bool usbWriteSectors(int volId, uint64_t startSector, uint32_t sectorCount,
                     const unsigned char* inBuf);
bool usbSyncDevice(int volId);