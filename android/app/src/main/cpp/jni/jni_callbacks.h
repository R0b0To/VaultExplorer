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
extern jclass g_illegalStateExceptionClass;
extern jclass g_unlockCancelledExceptionClass;

void reportUnlockProgress(int volId, int attempted, int total, int hashId,
                          int cipherId, int format = 0, int slot = 0);
bool usbReadSectors(int volId, uint64_t startSector, uint32_t sectorCount,
                    unsigned char* outBuf);
bool usbWriteSectors(int volId, uint64_t startSector, uint32_t sectorCount,
                     const unsigned char* inBuf);