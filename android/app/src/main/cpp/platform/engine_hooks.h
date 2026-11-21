// Host hooks the portable engine calls: progress, cancellation, lock yielding and raw USB access.
//
// These are plain C++ declarations with no JNI type in sight. On Android jni/jni_callbacks.cpp
// implements them by calling into Kotlin; a desktop host provides its own definitions (progress
// and cancellation can be no-ops or wired to its UI; the USB ones are its raw-device I/O).
// They used to be declared in jni/jni_callbacks.h next to the JVM globals, which made every
// engine file that wanted a progress callback include <jni.h>.
#pragma once

#include <cstddef>
#include <cstdint>

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
