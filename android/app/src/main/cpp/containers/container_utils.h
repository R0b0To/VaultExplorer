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
uint32_t crc32(const unsigned char* data, size_t length);
