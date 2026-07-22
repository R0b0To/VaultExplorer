#include "partition_writer.h"
#include "jni_callbacks.h"
#include <string.h>

static void writeUint32LE(unsigned char* buf, uint32_t val) {
    buf[0] = static_cast<unsigned char>(val & 0xFF);
    buf[1] = static_cast<unsigned char>((val >> 8) & 0xFF);
    buf[2] = static_cast<unsigned char>((val >> 16) & 0xFF);
    buf[3] = static_cast<unsigned char>((val >> 24) & 0xFF);
}

bool writeMbrPartitionTable(int volId, uint64_t startSector, uint64_t numSectors) {
    unsigned char sector0[512];
    memset(sector0, 0, 512);

    // Boot signature
    sector0[510] = 0x55;
    sector0[511] = 0xAA;

    // Partition 1 entry (at offset 446)
    unsigned char* p1 = &sector0[446];
    
    // Status (0x00 = non-bootable)
    p1[0] = 0x00;
    
    // CHS start (not really used much anymore, setting to 0xFFFFFF)
    p1[1] = 0xFF;
    p1[2] = 0xFF;
    p1[3] = 0xFF;
    
    // Partition type (0x83 = Linux native, typical for LUKS/VeraCrypt)
    p1[4] = 0x83;
    
    // CHS end
    p1[5] = 0xFF;
    p1[6] = 0xFF;
    p1[7] = 0xFF;
    
    // LBA start
    writeUint32LE(&p1[8], static_cast<uint32_t>(startSector));
    
    // Number of sectors
    writeUint32LE(&p1[12], static_cast<uint32_t>(numSectors));

    return usbWriteSectors(volId, 0, 1, sector0);
}
