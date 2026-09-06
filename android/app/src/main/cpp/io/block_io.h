#pragma once
#include <cstddef>
#include <cstdint>

bool physicalRead(int volumeId, uint64_t byteOffset, unsigned char* buffer,
                  size_t byteCount);
bool physicalWrite(int volumeId, uint64_t byteOffset,
                   const unsigned char* buffer, size_t byteCount);
bool usbFlushAndSync(int volumeId);