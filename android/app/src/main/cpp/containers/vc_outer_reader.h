#pragma once
// Random-access reader over the DECRYPTED logical space of an opened standard VeraCrypt volume
// (container I/O is a callback). Used to look at the outer volume's file system before a hidden
// volume is created inside it (containers/vc_fs_tail.h). XTS data units follow the host offset:
// unit = (container offset) / 512, exactly like Volume::ReadSectors upstream.
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <functional>
#include <vector>
#include "crypto/cascade.h"
#include "vc_fs_tail.h"

// [readRaw] reads container bytes (offset, buf, len). [dataOffset]/[volumeBytes] come from the verified header.
inline VcReadFn vcMakeOuterReader(const CascadeContext* ctx, uint64_t dataOffset, uint64_t volumeBytes,
                                  std::function<bool(uint64_t, unsigned char*, size_t)> readRaw) {
    return [=](uint64_t off, unsigned char* buf, size_t len) -> bool {
        if (len == 0) return true;
        if (off > volumeBytes || len > volumeBytes - off) return false;
        const uint64_t abs = dataOffset + off;
        const uint64_t first = abs & ~511ull;
        const uint64_t last = (abs + len + 511) & ~511ull;
        std::vector<unsigned char> enc(static_cast<size_t>(last - first)), dec(enc.size());
        if (!readRaw(first, enc.data(), enc.size())) return false;
        for (uint64_t o = 0; o < enc.size(); o += 512) {
            cascadeDecryptSector(*ctx, (first + o) / 512, enc.data() + o, dec.data() + o);
        }
        std::memcpy(buf, dec.data() + (abs - first), len);
        return true;
    };
}
