#include "container_utils.h"

#include <algorithm>
#include <array>
#include <ctime>

namespace {

bool hasControlChar(const std::string& value) {
    for (unsigned char c : value) {
        if (c < 32 || c == 127) return true;
    }
    return false;
}

// Replaces any invalid UTF-8 byte sequence in [value] with '?'.
bool sanitizeUtf8InPlace(std::string& value) {
    std::string out;
    out.reserve(value.size());
    bool changed = false;
    const auto* bytes = reinterpret_cast<const unsigned char*>(value.data());
    const size_t len = value.size();
    size_t i = 0;

    while (i < len) {
        const unsigned char b0 = bytes[i];
        if (b0 < 0x80) {
            out.push_back(static_cast<char>(b0));
            i++;
            continue;
        }

        int extra;
        unsigned char minB1 = 0x80, maxB1 = 0xBF;
        if ((b0 & 0xE0) == 0xC0) {
            extra = 1;
            if (b0 < 0xC2) { out.push_back('?'); changed = true; i++; continue; } // overlong
        } else if ((b0 & 0xF0) == 0xE0) {
            extra = 2;
            if (b0 == 0xE0) minB1 = 0xA0;      // overlong guard
            else if (b0 == 0xED) maxB1 = 0x9F; // surrogate-range guard
        } else if ((b0 & 0xF8) == 0xF0 && b0 <= 0xF4) {
            extra = 3;
            if (b0 == 0xF0) minB1 = 0x90;      // overlong guard
            else if (b0 == 0xF4) maxB1 = 0x8F; // > U+10FFFF guard
        } else {
            out.push_back('?'); changed = true; i++; continue; // stray continuation / invalid lead
        }

        if (i + extra >= len) { out.push_back('?'); changed = true; i++; continue; }

        bool valid = true;
        for (int k = 1; k <= extra && valid; k++) {
            const unsigned char bk = bytes[i + k];
            const unsigned char lo = (k == 1) ? minB1 : 0x80;
            const unsigned char hi = (k == 1) ? maxB1 : 0xBF;
            valid = bk >= lo && bk <= hi;
        }

        if (!valid) { out.push_back('?'); changed = true; i++; continue; }

        out.append(reinterpret_cast<const char*>(bytes + i), extra + 1);
        i += extra + 1;
    }

    if (changed) value = out;
    return changed;
}

} 

void sanitizeString(std::string& value) {
    if (hasControlChar(value)) {
        std::replace_if(value.begin(), value.end(),
            [](unsigned char c) { return c < 32 || c == 127; }, '?');
    }
    sanitizeUtf8InPlace(value);
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

namespace {
// Sarwate table-driven CRC32 -- mathematically identical to the bit-loop
// it replaces (same reflected CRC-32 polynomial 0xEDB88320), just ~8x
// fewer operations per byte via an 8-bit lookup table instead of 8
// conditional shift/XOR iterations.
const uint32_t* crc32LookupTable() {
    static const auto table = [] {
        std::array<uint32_t, 256> t{};
        for (uint32_t i = 0; i < 256; i++) {
            uint32_t c = i;
            for (int k = 0; k < 8; k++)
                c = (c & 1) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
            t[i] = c;
        }
        return t;
    }();
    return table.data();
}
} // namespace

uint32_t crc32(const unsigned char* data, size_t length) {
    const uint32_t* table = crc32LookupTable();
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < length; ++i) {
        crc = table[(crc ^ data[i]) & 0xFFu] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFFu;
}
