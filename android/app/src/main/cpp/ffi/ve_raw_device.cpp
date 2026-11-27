// See ve_raw_device.h. No OS headers here: the platform halves are ve_rawdev_posix.cpp / ve_rawdev_win.cpp.
#include "ve_raw_device.h"

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <mutex>

namespace veraw {

namespace {

constexpr int kMaxSlots = 64;

struct Slot {
    std::mutex m;
    plat::Handle h = plat::kInvalid;
    uint64_t size = 0;      // usable bytes (a whole number of device sectors)
    uint32_t sector = 512;  // the device's logical sector size
    bool writable = false;
    std::string canon;
};

Slot g_slots[kMaxSlots];
std::mutex g_attachMutex;  // serialises attach() so two slots cannot claim the same device at once

bool validSlot(int vol) { return vol >= 0 && vol < kMaxSlots; }

// Reads [len] bytes at any [off] through a handle whose sector is [ss]: the raw handle needs sector-aligned
// offsets and lengths, so the covering range is read and the wanted part copied out.
bool readRange(plat::Handle h, uint32_t ss, uint64_t size, uint64_t off, size_t len, unsigned char* out) {
    if (len == 0) return true;
    if (ss == 0 || off > size || len > size - off) return false;
    if (off % ss == 0 && len % ss == 0) return plat::pread(h, out, len, off);
    const uint64_t aStart = off - off % ss;
    const uint64_t aEnd = ((off + len + ss - 1) / ss) * ss;
    if (aEnd > size) return false;
    std::vector<unsigned char> tmp(static_cast<size_t>(aEnd - aStart));
    if (!plat::pread(h, tmp.data(), tmp.size(), aStart)) return false;
    std::memcpy(out, tmp.data() + (off - aStart), len);
    return true;
}

uint32_t le32(const unsigned char* p) {
    return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) | (static_cast<uint32_t>(p[2]) << 16) |
           (static_cast<uint32_t>(p[3]) << 24);
}
uint64_t le64(const unsigned char* p) { return static_cast<uint64_t>(le32(p)) | (static_cast<uint64_t>(le32(p + 4)) << 32); }

void addFormatAt(plat::Handle h, uint32_t ss, uint64_t size, uint64_t byteOffset, std::vector<std::string>* out) {
    unsigned char s[16];
    if (!readRange(h, ss, size, byteOffset, sizeof(s), s)) return;
    const char* found = nullptr;
    if (std::memcmp(s + 3, "-FVE-FS-", 8) == 0) found = "bitlocker";
    else if (std::memcmp(s, "LUKS\xba\xbe", 6) == 0) found = "luks";
    if (!found) return;
    if (std::find(out->begin(), out->end(), found) == out->end()) out->emplace_back(found);
}

void appendJsonString(std::string& out, const std::string& s) {
    out.push_back('"');
    for (const unsigned char c : s) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out.push_back(static_cast<char>(c));  // UTF-8 passes through
                }
        }
    }
    out.push_back('"');
}

}  // namespace

AttachResult attach(int vol, const std::string& path, bool writable, uint64_t* sizeBytes, int* osError) {
    if (!validSlot(vol) || path.empty()) return AttachResult::kFailed;
    std::lock_guard<std::mutex> guard(g_attachMutex);

    const std::string canon = plat::canonical(path);
    for (int i = 0; i < kMaxSlots; ++i) {
        std::lock_guard<std::mutex> lock(g_slots[i].m);
        if (g_slots[i].h == plat::kInvalid) continue;
        if (i == vol || g_slots[i].canon == canon) return AttachResult::kAlreadyOpen;
    }

    plat::Handle h = plat::kInvalid;
    uint64_t size = 0;
    uint32_t sector = 512;
    int err = 0;
    switch (plat::open(path, writable, &h, &size, &sector, &err)) {
        case plat::OpenResult::kOk: break;
        case plat::OpenResult::kNotFound: if (osError) *osError = err; return AttachResult::kNotFound;
        case plat::OpenResult::kPermission: if (osError) *osError = err; return AttachResult::kPermission;
        case plat::OpenResult::kBusy: if (osError) *osError = err; return AttachResult::kBusy;
        case plat::OpenResult::kUnsupported: if (osError) *osError = err; return AttachResult::kUnsupported;
        default: if (osError) *osError = err; return AttachResult::kFailed;
    }
    if (sector == 0 || sector > 65536) sector = 512;
    size -= size % sector;
    if (size < kEngineSector) {  // an empty card reader slot, say
        plat::close(h);
        return AttachResult::kFailed;
    }

    Slot& s = g_slots[vol];
    std::lock_guard<std::mutex> lock(s.m);
    s.h = h;
    s.size = size;
    s.sector = sector;
    s.writable = writable;
    s.canon = canon;
    if (sizeBytes) *sizeBytes = size;
    return AttachResult::kOk;
}

void detach(int vol) {
    if (!validSlot(vol)) return;
    Slot& s = g_slots[vol];
    std::lock_guard<std::mutex> lock(s.m);
    if (s.h == plat::kInvalid) return;
    if (s.writable) plat::sync(s.h);
    plat::close(s.h);
    s.h = plat::kInvalid;
    s.size = 0;
    s.sector = 512;
    s.writable = false;
    s.canon.clear();
}

bool isAttached(int vol) {
    if (!validSlot(vol)) return false;
    std::lock_guard<std::mutex> lock(g_slots[vol].m);
    return g_slots[vol].h != plat::kInvalid;
}

bool readSectors(int vol, uint64_t startSector, uint32_t count, unsigned char* out) {
    if (!validSlot(vol) || !out) return false;
    Slot& s = g_slots[vol];
    std::lock_guard<std::mutex> lock(s.m);
    if (s.h == plat::kInvalid) return false;
    if (startSector > UINT64_MAX / kEngineSector) return false;
    return readRange(s.h, s.sector, s.size, startSector * kEngineSector, static_cast<size_t>(count) * kEngineSector, out);
}

bool writeSectors(int vol, uint64_t startSector, uint32_t count, const unsigned char* in) {
    if (!validSlot(vol) || !in) return false;
    Slot& s = g_slots[vol];
    std::lock_guard<std::mutex> lock(s.m);
    if (s.h == plat::kInvalid || !s.writable) return false;
    if (startSector > UINT64_MAX / kEngineSector) return false;
    const uint64_t off = startSector * kEngineSector;
    const size_t len = static_cast<size_t>(count) * kEngineSector;
    if (len == 0) return true;
    if (off > s.size || len > s.size - off) return false;
    if (off % s.sector == 0 && len % s.sector == 0) return plat::pwrite(s.h, in, len, off);

    // 512-byte writes onto a 4Kn device: read-modify-write the covering sectors.
    const uint64_t aStart = off - off % s.sector;
    const uint64_t aEnd = ((off + len + s.sector - 1) / s.sector) * s.sector;
    if (aEnd > s.size) return false;
    std::vector<unsigned char> tmp(static_cast<size_t>(aEnd - aStart));
    if (!plat::pread(s.h, tmp.data(), tmp.size(), aStart)) return false;
    std::memcpy(tmp.data() + (off - aStart), in, len);
    return plat::pwrite(s.h, tmp.data(), tmp.size(), aStart);
}

bool syncDevice(int vol) {
    if (!validSlot(vol)) return false;
    Slot& s = g_slots[vol];
    std::lock_guard<std::mutex> lock(s.m);
    if (s.h == plat::kInvalid) return false;
    return s.writable ? plat::sync(s.h) : true;
}

std::vector<std::string> probeFormats(plat::Handle h, uint64_t sizeBytes, uint32_t ss) {
    std::vector<std::string> formats;
    if (ss == 0) return formats;
    addFormatAt(h, ss, sizeBytes, 0, &formats);  // the whole device is one encrypted volume

    unsigned char mbr[512];
    if (!readRange(h, ss, sizeBytes, 0, sizeof(mbr), mbr) || mbr[510] != 0x55 || mbr[511] != 0xAA) return formats;

    bool gpt = false;
    for (int i = 0; i < 4; ++i) {
        const unsigned char* e = mbr + 446 + 16 * i;
        const unsigned type = e[4];
        const uint64_t start = le32(e + 8);
        const uint64_t count = le32(e + 12);
        if (type == 0xEE) { gpt = true; continue; }
        if (type == 0 || type == 0x05 || type == 0x0F || type == 0x85 || start == 0 || count == 0) continue;
        addFormatAt(h, ss, sizeBytes, start * ss, &formats);
    }
    if (!gpt) return formats;

    unsigned char hdr[96];
    if (!readRange(h, ss, sizeBytes, ss, sizeof(hdr), hdr) || std::memcmp(hdr, "EFI PART", 8) != 0) return formats;
    const uint64_t entriesLba = le64(hdr + 72);
    const uint32_t entryCount = le32(hdr + 80);
    const uint32_t entrySize = le32(hdr + 84);
    if (entryCount == 0 || entryCount > 256 || entrySize < 128 || entrySize > 512) return formats;
    std::vector<unsigned char> entries(static_cast<size_t>(entryCount) * entrySize);
    if (entriesLba > UINT64_MAX / ss || !readRange(h, ss, sizeBytes, entriesLba * ss, entries.size(), entries.data())) {
        return formats;
    }
    static const unsigned char kZeroGuid[16] = {0};
    for (uint32_t i = 0; i < entryCount; ++i) {
        const unsigned char* e = entries.data() + static_cast<size_t>(i) * entrySize;
        if (std::memcmp(e, kZeroGuid, 16) == 0) continue;
        const uint64_t firstLba = le64(e + 32);
        if (firstLba == 0 || firstLba > UINT64_MAX / ss) continue;
        addFormatAt(h, ss, sizeBytes, firstLba * ss, &formats);
    }
    return formats;
}

std::vector<DeviceInfo> listDevices() {
    std::vector<DeviceInfo> devices = plat::enumerate();
    for (DeviceInfo& d : devices) {
        if (!d.readable) continue;
        plat::Handle h = plat::kInvalid;
        uint64_t size = 0;
        uint32_t sector = 512;
        int err = 0;
        if (plat::open(d.path, /*writable=*/false, &h, &size, &sector, &err) != plat::OpenResult::kOk) continue;
        d.formats = probeFormats(h, size - size % (sector ? sector : 512), sector ? sector : 512);
        plat::close(h);
    }
    return devices;
}

std::string devicesToJson(const std::vector<DeviceInfo>& devices) {
    std::string out = "[";
    bool first = true;
    for (const DeviceInfo& d : devices) {
        if (!first) out.push_back(',');
        first = false;
        out += "{\"path\":";
        appendJsonString(out, d.path);
        out += ",\"name\":";
        appendJsonString(out, d.name);
        out += ",\"bus\":";
        appendJsonString(out, d.bus);
        out += ",\"sizeBytes\":" + std::to_string(d.sizeBytes);
        out += ",\"sectorSize\":" + std::to_string(d.sectorSize);
        out += std::string(",\"removable\":") + (d.removable ? "true" : "false");
        out += std::string(",\"readable\":") + (d.readable ? "true" : "false");
        out += std::string(",\"writable\":") + (d.writable ? "true" : "false");
        out += std::string(",\"inUse\":") + (d.inUse ? "true" : "false");
        out += std::string(",\"system\":") + (d.system ? "true" : "false");
        out += ",\"formats\":[";
        for (size_t i = 0; i < d.formats.size(); ++i) {
            if (i) out.push_back(',');
            appendJsonString(out, d.formats[i]);
        }
        out += "]}";
    }
    out.push_back(']');
    return out;
}

}  // namespace veraw
