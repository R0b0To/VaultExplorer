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

// The engine-facing callbacks (progress, cancellation, lock yielding, USB I/O) are declared in
// platform/engine_hooks.h, which has no JNI types; this header keeps only the JVM globals that
// jni_callbacks.cpp and the bridges use to implement them.
#include "platform/engine_hooks.h"
