// Default (do-nothing) definitions of the engine hooks declared in platform/engine_hooks.h, for
// builds that have no JVM: a desktop front-end that has no use for a given hook links this file
// and overrides nothing; one that does (progress to a UI, cancellation from a button, USB drives
// through libusb or a raw device) provides its own definitions of those functions *instead of*
// this file.
//
// NOT part of the Android library: there, jni/jni_callbacks.cpp defines every one of these by
// calling into Kotlin, and compiling both would be a duplicate-definition error.
//
// Semantics of the defaults: progress is discarded, nothing is ever cancelled, no operation is
// tracked, lock yielding does nothing, and USB access reports failure (no device is reachable).
#include "platform/engine_hooks.h"

void reportUnlockProgress(int, int, int, int, int, int, int) {}
void reportSplitJoinProgress(int, uint64_t, uint64_t) {}
bool isSplitJoinCancelled(int) { return false; }
void notifyHiddenVolumeProtectionTriggered(int) {}
void reportRepairLog(int, const char*) {}
void reportCopyProgress(int, uint64_t) {}
bool isCopyCancelled(int) { return false; }
void reportImportChunkProgress(int, uint64_t) {}
bool isImportCancelled(int) { return false; }
bool isImportTracking(int) { return false; }
void reportExportChunkProgress(int, uint64_t) {}
bool isExportCancelled(int) { return false; }
bool isExportTracking(int) { return false; }

void reportWriteBackChunkProgress(int, uint64_t) {}
bool isWriteBackCancelled(int) { return false; }
void reportExtractChunkProgress(int, uint64_t) {}
bool isExtractCancelled(int) { return false; }

void yieldContainerWriteLock(int) {}
void yieldContainerCopyLocks(int, int) {}

bool usbReadSectors(int, uint64_t, uint32_t, unsigned char*) { return false; }
bool usbWriteSectors(int, uint64_t, uint32_t, const unsigned char*) { return false; }
bool usbSyncDevice(int) { return false; }
