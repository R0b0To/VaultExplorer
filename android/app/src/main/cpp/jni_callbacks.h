#pragma once

#include <cstddef>
#include <cstdint>
#include <jni.h>

// Process-lifetime handles owned by jni_runtime.cpp.
extern JavaVM* g_vm;
extern jclass g_usbBridgeClass;
extern jmethodID g_usbReadMethod;
extern jmethodID g_usbWriteMethod;
extern jclass g_progressBridgeClass;
extern jmethodID g_progressReportMethod;

void reportUnlockProgress(int volId, int attempted, int total, int hashId,
                          int cipherId, int format = 0);
bool usbReadSectors(int volId, uint64_t startSector, uint32_t sectorCount,
                    unsigned char* outBuf);
bool usbWriteSectors(int volId, uint64_t startSector, uint32_t sectorCount,
                     const unsigned char* inBuf);
