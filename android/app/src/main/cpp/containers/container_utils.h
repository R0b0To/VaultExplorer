#pragma once
#include <cstddef>
#include <cstdint>
#include <string>
#include "ff.h"

void sanitizeString(std::string& value);
uint32_t readUint32LE(const unsigned char* data);
uint64_t readUint64LE(const unsigned char* data);
uint64_t fatToUnixTimestamp(WORD date, WORD time);
void unixToFatTimestamp(uint64_t unixTime, WORD& date, WORD& time);
uint32_t container_crc32(const unsigned char* data, size_t length);

// Computes the VeraCrypt-standard FAT cluster size ladder to prevent FatFs from
// falling into the 512-entry root-directory FAT16 trap on volumes < 2 GB.
uint32_t vc_fat_cluster_size(uint64_t volumeSize);