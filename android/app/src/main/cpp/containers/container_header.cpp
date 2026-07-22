#include "container_header.h"

#include <cstring>

bool isValidBootSector(const unsigned char* sector) {
    if (sector[510] != 0x55 || sector[511] != 0xAA) return false;
    if (sector[0] == 0xEB && sector[1] == 0x76 && sector[2] == 0x90 &&
        memcmp(&sector[3], "EXFAT   ", 8) == 0) {
        return true;
    }
    if (sector[0] == 0xEB || sector[0] == 0xE9) {
        const uint16_t bytesPerSector = static_cast<uint16_t>(sector[11]) |
                                        (static_cast<uint16_t>(sector[12]) << 8);
        return bytesPerSector == 512;
    }
    return false;
}

uint64_t readHeaderBE64(const unsigned char* data, int offset) {
    uint64_t value = 0;
    for (int index = 0; index < 8; ++index) value = (value << 8) | data[offset + index];
    return value;
}

uint32_t readHeaderBE32(const unsigned char* data, int offset) {
    return (static_cast<uint32_t>(data[offset]) << 24) |
           (static_cast<uint32_t>(data[offset + 1]) << 16) |
           (static_cast<uint32_t>(data[offset + 2]) << 8) |
           static_cast<uint32_t>(data[offset + 3]);
}
