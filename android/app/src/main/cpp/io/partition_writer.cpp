#include "partition_writer.h"
#include "jni_callbacks.h"

UsbCreateResult writeMbrPartitionTable(int volId, uint64_t startSector, uint64_t numSectors,
                                        uint64_t deviceSectorCount) {
    unsigned char sector0[512];
    UsbCreateResult built = buildMbrSector0(sector0, startSector, numSectors, deviceSectorCount);
    if (!built.success) return built;

    if (!usbWriteSectors(volId, 0, 1, sector0)) {
        return UsbCreateResult::Fail(UsbCreatePhase::kWriteMbr, "USB_MBR_WRITE_FAILED",
                                      "Failed to write the MBR partition table to the device", 0, 0, 1);
    }
    return UsbCreateResult::Ok();
}
