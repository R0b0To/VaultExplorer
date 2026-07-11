#pragma once

#include <cstddef>
#include <cstdint>

// Raw access to an encrypted volume's backing store.  The caller supplies
// physical offsets; this layer selects the file descriptor or USB transport.
bool physicalRead(int volumeId, uint64_t byteOffset, unsigned char* buffer,
                  size_t byteCount);
bool physicalWrite(int volumeId, uint64_t byteOffset,
                   const unsigned char* buffer, size_t byteCount);
