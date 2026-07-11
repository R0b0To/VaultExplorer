#include "container_utils.h"

#include <algorithm>
#include <ctime>

namespace {

bool hasControlChar(const std::string& value) {
    for (unsigned char c : value) {
        if (c < 32 || c == 127) return true;
    }
    return false;
}

} // namespace

void sanitizeString(std::string& value) {
    if (!hasControlChar(value)) return;
    std::replace_if(value.begin(), value.end(),
        [](unsigned char c) { return c < 32 || c == 127; }, '?');
}

uint32_t readUint32LE(const unsigned char* data) {
    return static_cast<uint32_t>(data[0]) |
           (static_cast<uint32_t>(data[1]) << 8) |
           (static_cast<uint32_t>(data[2]) << 16) |
           (static_cast<uint32_t>(data[3]) << 24);
}

uint64_t readUint64LE(const unsigned char* data) {
    return static_cast<uint64_t>(data[0]) |
           (static_cast<uint64_t>(data[1]) << 8) |
           (static_cast<uint64_t>(data[2]) << 16) |
           (static_cast<uint64_t>(data[3]) << 24) |
           (static_cast<uint64_t>(data[4]) << 32) |
           (static_cast<uint64_t>(data[5]) << 40) |
           (static_cast<uint64_t>(data[6]) << 48) |
           (static_cast<uint64_t>(data[7]) << 56);
}

uint64_t fatToUnixTimestamp(WORD date, WORD time) {
    if (date == 0) return 0;
    struct tm value = {};
    value.tm_year = ((date >> 9) & 0x7F) + 80;
    value.tm_mon = ((date >> 5) & 0x0F) - 1;
    value.tm_mday = date & 0x1F;
    value.tm_hour = (time >> 11) & 0x1F;
    value.tm_min = (time >> 5) & 0x3F;
    value.tm_sec = (time & 0x1F) * 2;
    value.tm_isdst = -1;
    const time_t timestamp = mktime(&value);
    return timestamp < 0 ? 0 : static_cast<uint64_t>(timestamp);
}

void unixToFatTimestamp(uint64_t unixTime, WORD& date, WORD& time) {
    time_t seconds = static_cast<time_t>(unixTime);
    struct tm value = {};
    localtime_r(&seconds, &value);
    const int year = value.tm_year + 1900;
    if (year < 1980) {
        date = 0;
        time = 0;
        return;
    }
    date = static_cast<WORD>(
        (((year - 1980) & 0x7F) << 9) |
        (((value.tm_mon + 1) & 0x0F) << 5) |
        (value.tm_mday & 0x1F));
    time = static_cast<WORD>(
        ((value.tm_hour & 0x1F) << 11) |
        ((value.tm_min & 0x3F) << 5) |
        ((value.tm_sec / 2) & 0x1F));
}

uint32_t crc32(const unsigned char* data, size_t length) {
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < length; ++i) {
        crc ^= data[i];
        for (int bit = 0; bit < 8; ++bit) {
            crc = (crc >> 1) ^ (0xEDB88320u & ~((crc & 1) - 1));
        }
    }
    return crc ^ 0xFFFFFFFFu;
}
