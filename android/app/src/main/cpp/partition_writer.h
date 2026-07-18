#pragma once

#include <cstdint>
#include <cstddef>

// Writes an MBR partition table to the USB device.
// Creates a single primary partition starting at `startSector` (typically 2048)
// spanning `numSectors`.
// Returns true on success.
bool writeMbrPartitionTable(int volId, uint64_t startSector, uint64_t numSectors);

// (Optional) Writes a basic GPT partition table.
// bool writeGptPartitionTable(int volId, uint64_t startSector, uint64_t numSectors);
