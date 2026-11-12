#pragma once
// How much contiguous free space a file system has at the very END of its cluster area --
// the number VeraCrypt's "create a hidden volume inside an existing volume" (direct mode)
// needs: the hidden volume sits at the end of the outer volume, so its maximum size is bounded
// by the free clusters after the last used one. Upstream scans the cluster bitmap of the mounted
// outer volume (Format/Tcformat.c AnalyzeHiddenVolumeHost); this reads the on-disk structures
// directly, from the decrypted outer volume, for the file systems VeraCrypt allows as hosts:
//   FAT12/16/32 (the FAT itself), exFAT (the allocation bitmap), NTFS ($Bitmap).
// Read-only. Header-only; [read] reads bytes at an offset of the outer volume's logical space,
// so it can be tested on the host against raw images (containers/test/vc_fs_tail_test.cpp).
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <functional>
#include <vector>

enum class VcFsKind { kUnknown, kFat12, kFat16, kFat32, kExFat, kNtfs };

struct VcFsTail {
    VcFsKind kind = VcFsKind::kUnknown;
    uint64_t clusterSize = 0;        // bytes
    uint64_t freeTailClusters = 0;   // contiguous free clusters at the end of the cluster area
};

using VcReadFn = std::function<bool(uint64_t offset, unsigned char* buf, size_t len)>;

namespace vcfs {

inline uint32_t le16(const unsigned char* p) { return p[0] | (p[1] << 8); }
inline uint32_t le32(const unsigned char* p) { return p[0] | (p[1] << 8) | (p[2] << 16) | (static_cast<uint32_t>(p[3]) << 24); }
inline uint64_t le64(const unsigned char* p) { return le32(p) | (static_cast<uint64_t>(le32(p + 4)) << 32); }

// Number of zero bits at the end of a bitmap of [totalBits] bits, scanning backwards in windows.
// [readBitmap] reads bytes of the bitmap itself.
inline bool countTailZeroBits(const std::function<bool(uint64_t, unsigned char*, size_t)>& readBitmap,
                              uint64_t totalBits, uint64_t* zeros) {
    constexpr size_t kWin = 65536;
    std::vector<unsigned char> win(kWin);
    uint64_t count = 0;
    uint64_t bit = totalBits;                       // exclusive upper bound of the not-yet-examined bits
    while (bit > 0) {
        const uint64_t lastByte = (bit - 1) / 8;
        const uint64_t firstByte = lastByte >= kWin - 1 ? lastByte - (kWin - 1) : 0;
        const size_t len = static_cast<size_t>(lastByte - firstByte + 1);
        if (!readBitmap(firstByte, win.data(), len)) return false;
        for (uint64_t b = bit; b > 0; --b) {
            const uint64_t idx = b - 1;
            if (idx / 8 < firstByte) { bit = b; goto nextWindow; }
            if (win[static_cast<size_t>(idx / 8 - firstByte)] & (1u << (idx % 8))) { *zeros = count; return true; }
            ++count;
        }
        bit = 0;
    nextWindow:;
    }
    *zeros = count;
    return true;
}

inline bool analyzeFat(const VcReadFn& read, const unsigned char* bs, VcFsTail* out) {
    const uint32_t bps = le16(bs + 11), spc = bs[13], reserved = le16(bs + 14), nfats = bs[16];
    const uint32_t rootEntries = le16(bs + 17);
    uint64_t total = le16(bs + 19); if (total == 0) total = le32(bs + 32);
    uint64_t fatSz = le16(bs + 22); if (fatSz == 0) fatSz = le32(bs + 36);
    if (bps < 512 || bps > 4096 || (bps & (bps - 1)) || spc == 0 || (spc & (spc - 1)) || reserved == 0 ||
        nfats == 0 || fatSz == 0 || total == 0) return false;
    const uint64_t rootSectors = (static_cast<uint64_t>(rootEntries) * 32 + bps - 1) / bps;
    const uint64_t meta = reserved + nfats * fatSz + rootSectors;
    if (total <= meta) return false;
    const uint64_t clusters = (total - meta) / spc;
    if (clusters == 0) return false;
    const VcFsKind kind = clusters < 4085 ? VcFsKind::kFat12 : clusters < 65525 ? VcFsKind::kFat16 : VcFsKind::kFat32;
    const uint64_t fatBase = static_cast<uint64_t>(reserved) * bps;
    const uint64_t fatBytes = fatSz * bps;
    // entry value for cluster n (reads a small window around it)
    auto entry = [&](uint64_t n, uint32_t* v) -> bool {
        unsigned char b[4];
        uint64_t off, len;
        if (kind == VcFsKind::kFat12) { off = n + n / 2; len = 2; }
        else if (kind == VcFsKind::kFat16) { off = n * 2; len = 2; }
        else { off = n * 4; len = 4; }
        if (off + len > fatBytes) return false;
        if (!read(fatBase + off, b, static_cast<size_t>(len))) return false;
        if (kind == VcFsKind::kFat12) { const uint32_t w = le16(b); *v = (n & 1) ? (w >> 4) : (w & 0xFFF); }
        else if (kind == VcFsKind::kFat16) *v = le16(b);
        else *v = le32(b) & 0x0FFFFFFF;
        return true;
    };
    uint64_t free = 0;
    for (uint64_t n = clusters + 1; n >= 2; --n) {      // data clusters are numbered 2 .. clusters+1
        uint32_t v;
        if (!entry(n, &v)) return false;
        if (v != 0) break;
        ++free;
    }
    out->kind = kind; out->clusterSize = static_cast<uint64_t>(bps) * spc; out->freeTailClusters = free;
    return true;
}

inline bool analyzeExFat(const VcReadFn& read, const unsigned char* bs, VcFsTail* out) {
    const uint32_t bpsShift = bs[108], spcShift = bs[109];
    if (bpsShift < 9 || bpsShift > 12 || spcShift > 25 || bpsShift + spcShift > 25) return false;
    const uint64_t bps = 1ull << bpsShift, clusterSize = bps << spcShift;
    const uint64_t fatOffset = static_cast<uint64_t>(le32(bs + 80)) * bps;
    const uint64_t heapOffset = static_cast<uint64_t>(le32(bs + 88)) * bps;
    const uint64_t clusterCount = le32(bs + 92);
    const uint32_t rootCluster = le32(bs + 96);
    if (clusterCount == 0 || rootCluster < 2) return false;
    auto clusterOff = [&](uint64_t c) { return heapOffset + (c - 2) * clusterSize; };
    auto fatNext = [&](uint32_t c, uint32_t* next) {
        unsigned char b[4];
        if (!read(fatOffset + static_cast<uint64_t>(c) * 4, b, 4)) return false;
        *next = le32(b); return true;
    };
    // find the allocation-bitmap entry (type 0x81) in the root directory
    uint32_t bitmapCluster = 0; uint64_t bitmapLen = 0;
    uint32_t c = rootCluster;
    std::vector<unsigned char> dir(static_cast<size_t>(clusterSize));
    for (int hop = 0; hop < 64 && !bitmapCluster; ++hop) {
        if (c < 2 || c >= clusterCount + 2 || !read(clusterOff(c), dir.data(), dir.size())) return false;
        bool end = false;
        for (size_t e = 0; e + 32 <= dir.size(); e += 32) {
            if (dir[e] == 0x00) { end = true; break; }
            if (dir[e] == 0x81) { bitmapCluster = le32(&dir[e + 20]); bitmapLen = le64(&dir[e + 24]); break; }
        }
        if (bitmapCluster || end) break;
        uint32_t next;
        if (!fatNext(c, &next) || next < 2 || next >= 0xFFFFFFF7u) break;
        c = next;
    }
    if (bitmapCluster < 2 || bitmapLen == 0 || bitmapLen * 8 < clusterCount) return false;
    // the bitmap must be contiguous: a chain that is not simply cluster+1 is not handled
    const uint64_t bitmapClusters = (bitmapLen + clusterSize - 1) / clusterSize;
    for (uint64_t i = 0; i + 1 < bitmapClusters; ++i) {
        uint32_t next;
        if (!fatNext(bitmapCluster + static_cast<uint32_t>(i), &next)) return false;
        if (next != 0 && next != bitmapCluster + i + 1) return false;
    }
    const uint64_t base = clusterOff(bitmapCluster);
    uint64_t zeros = 0;
    if (!countTailZeroBits([&](uint64_t o, unsigned char* b, size_t n) { return read(base + o, b, n); }, clusterCount, &zeros)) return false;
    out->kind = VcFsKind::kExFat; out->clusterSize = clusterSize; out->freeTailClusters = zeros;
    return true;
}

struct Run { uint64_t lcn; uint64_t len; bool sparse; };

inline bool analyzeNtfs(const VcReadFn& read, const unsigned char* bs, VcFsTail* out) {
    const uint32_t bps = le16(bs + 11);
    uint32_t spc = bs[13];
    if (spc > 0x80) spc = 1u << (256 - spc);
    if (bps < 512 || bps > 4096 || (bps & (bps - 1)) || spc == 0 || (spc & (spc - 1))) return false;
    const uint64_t clusterSize = static_cast<uint64_t>(bps) * spc;
    const uint64_t totalClusters = le64(bs + 40) / spc;
    const uint64_t mftLcn = le64(bs + 48);
    const int8_t cpr = static_cast<int8_t>(bs[64]);
    const uint64_t recSize = cpr > 0 ? static_cast<uint64_t>(cpr) * clusterSize : (1ull << (-cpr));
    if (totalClusters == 0 || recSize < 512 || recSize > 65536) return false;
    std::vector<unsigned char> rec(static_cast<size_t>(recSize));
    if (!read(mftLcn * clusterSize + 6 * recSize, rec.data(), rec.size())) return false;      // $Bitmap is MFT record 6
    if (std::memcmp(rec.data(), "FILE", 4) != 0) return false;
    {   // apply the update-sequence fixups
        const uint32_t usaOff = le16(&rec[4]), usaCnt = le16(&rec[6]);
        if (usaCnt < 2 || usaOff + usaCnt * 2 > rec.size()) return false;
        for (uint32_t i = 1; i < usaCnt; ++i) {
            const size_t end = static_cast<size_t>(i) * 512;
            if (end > rec.size()) return false;
            rec[end - 2] = rec[usaOff + i * 2]; rec[end - 1] = rec[usaOff + i * 2 + 1];
        }
    }
    uint32_t a = le16(&rec[0x14]);
    std::vector<Run> runs; uint64_t realSize = 0; bool found = false, resident = false; size_t resOff = 0;
    while (a + 16 <= rec.size()) {
        const uint32_t type = le32(&rec[a]), len = le32(&rec[a + 4]);
        if (type == 0xFFFFFFFFu || len < 16 || a + len > rec.size()) break;
        if (type == 0x80 && rec[a + 9] == 0) {                       // unnamed $DATA
            found = true;
            if (rec[a + 8] == 0) { resident = true; realSize = le32(&rec[a + 0x10]); resOff = a + le16(&rec[a + 0x14]); }
            else {
                realSize = le64(&rec[a + 0x30]);
                size_t p = a + le16(&rec[a + 0x20]); int64_t lcn = 0;
                while (p < a + len && rec[p] != 0) {
                    const unsigned lenBytes = rec[p] & 0xF, offBytes = rec[p] >> 4;
                    if (lenBytes == 0 || lenBytes > 8 || offBytes > 8 || p + 1 + lenBytes + offBytes > a + len) return false;
                    uint64_t rl = 0; for (unsigned i = 0; i < lenBytes; ++i) rl |= static_cast<uint64_t>(rec[p + 1 + i]) << (8 * i);
                    int64_t delta = 0;
                    for (unsigned i = 0; i < offBytes; ++i) delta |= static_cast<int64_t>(rec[p + 1 + lenBytes + i]) << (8 * i);
                    if (offBytes && (rec[p + lenBytes + offBytes] & 0x80)) delta -= (1ll << (8 * offBytes));
                    lcn += delta;
                    runs.push_back({static_cast<uint64_t>(lcn), rl, offBytes == 0});
                    p += 1 + lenBytes + offBytes;
                }
            }
            break;
        }
        a += len;
    }
    if (!found || realSize * 8 < totalClusters) return false;
    auto readBitmap = [&](uint64_t off, unsigned char* buf, size_t n) -> bool {
        if (resident) { if (off + n > realSize) return false; std::memcpy(buf, &rec[resOff + off], n); return true; }
        uint64_t pos = 0;                                              // byte position at the start of the current run
        size_t done = 0;
        for (const Run& r : runs) {
            const uint64_t runBytes = r.len * clusterSize;
            if (off + done < pos + runBytes) {
                if (r.sparse) return false;
                const uint64_t inRun = off + done - pos;
                const size_t take = static_cast<size_t>(std::min<uint64_t>(n - done, runBytes - inRun));
                if (!read(r.lcn * clusterSize + inRun, buf + done, take)) return false;
                done += take;
                if (done == n) return true;
            }
            pos += runBytes;
        }
        return false;
    };
    uint64_t zeros = 0;
    if (!countTailZeroBits(readBitmap, totalClusters, &zeros)) return false;
    out->kind = VcFsKind::kNtfs; out->clusterSize = clusterSize; out->freeTailClusters = zeros;
    return true;
}

}  // namespace vcfs

// Detects the file system at the start of the volume and measures its free tail.
// Returns false for anything that is not FAT/exFAT/NTFS or whose structures don't parse.
inline bool vcAnalyzeFsTail(const VcReadFn& read, VcFsTail* out) {
    unsigned char bs[512];
    if (!read(0, bs, sizeof(bs))) return false;
    if (std::memcmp(bs + 3, "EXFAT   ", 8) == 0) return vcfs::analyzeExFat(read, bs, out);
    if (std::memcmp(bs + 3, "NTFS    ", 8) == 0) return vcfs::analyzeNtfs(read, bs, out);
    if (bs[510] == 0x55 && bs[511] == 0xAA) return vcfs::analyzeFat(read, bs, out);
    return false;
}

// Upstream's maximum hidden-volume size for an outer volume of [outerDataBytes] bytes
// (Format/Tcformat.c, DetermineMaxHiddenVolSize): the free tail minus a reserved end area
// (TC_HIDDEN_VOLUME_HOST_FS_RESERVED_END_AREA_SIZE = 4096) minus a safety reserve of 0.5% of the
// outer data area (at most 10 MiB) for file-system changes made after the analysis, rounded down
// to a whole number of clusters. 0 when below the minimum hidden volume size (40960).
inline uint64_t vcMaxHiddenVolumeSize(const VcFsTail& t, uint64_t outerDataBytes) {
    uint64_t reserve = outerDataBytes / 200;
    if (reserve > 10ull * 1024 * 1024) reserve = 10ull * 1024 * 1024;
    const uint64_t free = t.freeTailClusters * t.clusterSize;
    if (t.clusterSize == 0 || free <= 4096 + reserve) return 0;
    uint64_t max = free - 4096 - reserve;
    max -= max % t.clusterSize;
    return max < 40960 ? 0 : max;
}
