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
            if (b0 < 0xC2) { out.push_back('?'); changed = true; i++; continue; }
        } else if ((b0 & 0xF0) == 0xE0) {
            extra = 2;
            if (b0 == 0xE0) minB1 = 0xA0;
            else if (b0 == 0xED) maxB1 = 0x9F;
        } else if ((b0 & 0xF8) == 0xF0 && b0 <= 0xF4) {
            extra = 3;
            if (b0 == 0xF0) minB1 = 0x90;
            else if (b0 == 0xF4) maxB1 = 0x8F;
        } else {
            out.push_back('?'); changed = true; i++; continue;
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
            [](unsigned char c) { return c < 32 || c == 127; }, '_');
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

uint32_t container_crc32(const unsigned char* data, size_t length) {
    const uint32_t* table = crc32LookupTable();
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < length; ++i) {
        crc = table[(crc ^ data[i]) & 0xFFu] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFFu;
}

uint32_t vc_fat_cluster_size(uint64_t volumeSize) {
    const uint64_t KB = 1024ULL, MB = 1024ULL * KB, GB = 1024ULL * MB, TB = 1024ULL * GB;
    uint32_t clusterSize;
    if      (volumeSize >= 2   * TB) clusterSize = static_cast<uint32_t>(256 * KB);
    else if (volumeSize >= 512 * GB) clusterSize = static_cast<uint32_t>(128 * KB);
    else if (volumeSize >= 128 * GB) clusterSize = static_cast<uint32_t>( 64 * KB);
    else if (volumeSize >=  64 * GB) clusterSize = static_cast<uint32_t>( 32 * KB);
    else if (volumeSize >=  32 * GB) clusterSize = static_cast<uint32_t>( 16 * KB);
    else if (volumeSize >=  16 * GB) clusterSize = static_cast<uint32_t>(  8 * KB);
    else if (volumeSize >= 512 * MB) clusterSize = static_cast<uint32_t>(  4 * KB);
    else if (volumeSize >= 256 * MB) clusterSize = static_cast<uint32_t>(  2 * KB);
    else if (volumeSize >=   1 * MB) clusterSize = static_cast<uint32_t>(  1 * KB);
    else                             clusterSize = 512;

    const uint32_t maxAu = 128u * 512u; // 64 KB (FatFs limit)
    if (clusterSize > maxAu) clusterSize = maxAu;
    if (volumeSize <= 1024ULL * KB) clusterSize = 512;

    // Prevent landing inside the FAT16 boundary trap
    const uint32_t FAT16_MAX_CLUSTERS = 0xFFF5;
    const uint32_t margin = FAT16_MAX_CLUSTERS / 50; // 2%
    for (int guard = 0; guard < 8; guard++) {
        uint64_t clusters = volumeSize / clusterSize;
        if (clusters <= FAT16_MAX_CLUSTERS ||
            clusters >= static_cast<uint64_t>(FAT16_MAX_CLUSTERS) + margin) break;
        if (clusterSize > 512) clusterSize /= 2;
        else if (clusterSize * 2 <= maxAu) clusterSize *= 2;
        else break;
    }
    return clusterSize;
}