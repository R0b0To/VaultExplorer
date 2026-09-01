#pragma once

#include <cstdint>
#include <cstddef>
#include "../containers/usb_create_diagnostics.h"
#include "mbr_builder.h"  // buildMbrSector0 -- pure logic, see mbr_builder.h and io/test/mbr_builder_test.cpp

// Writes an MBR partition table to the USB device identified by volId.
// Creates a single primary partition starting at `startSector` (typically
// 2048) spanning `numSectors`. Validates via buildMbrSector0 (see
// mbr_builder.h) before writing anything, then performs the actual
// sector-0 write via usbWriteSectors.
UsbCreateResult writeMbrPartitionTable(int volId, uint64_t startSector, uint64_t numSectors,
                                        uint64_t deviceSectorCount);
