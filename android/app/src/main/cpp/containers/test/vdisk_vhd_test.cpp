// Host-side test for the legacy-VHD half of containers/vdisk.{h,cpp}: fixed VHD, dynamic VHD growth in place and with a
// relocated BAT. Synthetic images are built here from the VHD specification; results are checked with an independent
// footer / header validator and by reading the grown image back through VDisk (the app's own VhdImage reader).
// VHDX and real-world files are covered by vdisk_grow_qemu_check.sh (needs qemu-img).
//
// Build (cpp/ dir): g++ -std=c++17 -Ifilesystems/test/host_stubs -Icontainers containers/test/vdisk_vhd_test.cpp
//   containers/vdisk.cpp containers/vhd_image.cpp containers/vhdx_image.cpp -o vdisk_vhd_test
#include "../vdisk.h"

#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

static const uint64_t kMiB = 1 << 20;

static void be32(unsigned char* p, uint32_t v) { p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v; }
static void be64(unsigned char* p, uint64_t v) { be32(p, uint32_t(v >> 32)); be32(p + 4, uint32_t(v)); }
static uint32_t rbe32(const unsigned char* p) { return (uint32_t(p[0]) << 24) | (uint32_t(p[1]) << 16) | (uint32_t(p[2]) << 8) | p[3]; }
static uint64_t rbe64(const unsigned char* p) { return (uint64_t(rbe32(p)) << 32) | rbe32(p + 4); }

static uint32_t checksum(const unsigned char* d, size_t n, size_t ckOff) {
    uint32_t s = 0;
    for (size_t i = 0; i < n; i++) if (i < ckOff || i >= ckOff + 4) s += d[i];
    return ~s;
}

static std::vector<unsigned char> footer(uint64_t size, uint32_t type, uint64_t dataOffset) {
    std::vector<unsigned char> f(512, 0);
    std::memcpy(&f[0], "conectix", 8);
    be32(&f[8], 2); be32(&f[12], 0x00010000);
    be64(&f[16], dataOffset);
    std::memcpy(&f[28], "test", 4); be32(&f[32], 0x00010000); std::memcpy(&f[36], "Wi2k", 4);
    be64(&f[40], size); be64(&f[48], size);
    be32(&f[56], (200u << 16) | (16 << 8) | 63);          // arbitrary geometry: the grow code recomputes it
    be32(&f[60], type);
    for (int i = 0; i < 16; i++) f[68 + i] = uint8_t(0x40 + i);
    be32(&f[64], checksum(f.data(), 512, 64));
    return f;
}

struct TempFile {
    int fd; char path[64];
    TempFile() { std::strcpy(path, "/tmp/vdisk_vhd_testXXXXXX"); fd = mkstemp(path); assert(fd >= 0); }
    ~TempFile() { close(fd); unlink(path); }
    uint64_t size() const { struct stat st{}; fstat(fd, &st); return uint64_t(st.st_size); }
    void put(uint64_t off, const void* p, size_t n) { assert(pwrite(fd, p, n, off) == ssize_t(n)); }
    void get(uint64_t off, void* p, size_t n) const { assert(pread(fd, p, n, off) == ssize_t(n)); }
};

static unsigned char pat(uint64_t i) { return static_cast<unsigned char>((i * 2654435761u) >> 13); }

static void buildFixed(TempFile& t, uint64_t size) {
    std::vector<unsigned char> data(size);
    for (uint64_t i = 0; i < size; i++) data[i] = pat(i);
    t.put(0, data.data(), data.size());
    auto f = footer(size, 2, ~0ull);
    t.put(size, f.data(), f.size());
}

// Dynamic VHD: footer copy | dynamic header | BAT (padded to 512) | block 0 (bitmap sector + data) | footer.
static void buildDynamic(TempFile& t, uint64_t size, uint32_t blockSize) {
    const uint32_t entries = uint32_t((size + blockSize - 1) / blockSize);
    const uint64_t batOff = 1536, batBytes = (uint64_t(entries) * 4 + 511) / 512 * 512, block0 = batOff + batBytes;
    auto f = footer(size, 3, 512);
    t.put(0, f.data(), f.size());
    unsigned char dyn[1024] = {0};
    std::memcpy(dyn, "cxsparse", 8); be64(dyn + 8, ~0ull); be64(dyn + 16, batOff); be32(dyn + 24, 0x00010000);
    be32(dyn + 28, entries); be32(dyn + 32, blockSize);
    be32(dyn + 36, checksum(dyn, 1024, 36));
    t.put(512, dyn, sizeof(dyn));
    std::vector<unsigned char> bat(batBytes, 0xFF);
    be32(&bat[0], uint32_t(block0 / 512));                   // block 0 allocated, the rest not
    t.put(batOff, bat.data(), bat.size());
    std::vector<unsigned char> blk(512 + blockSize, 0);
    std::memset(blk.data(), 0xFF, 512);                       // sector bitmap: all present
    for (uint32_t i = 0; i < blockSize; i++) blk[512 + i] = pat(i);
    t.put(block0, blk.data(), blk.size());
    t.put(block0 + blk.size(), f.data(), f.size());
}

// Independent structural validation of a VHD footer (trailing + leading copy) and dynamic header.
static void validateFooter(const TempFile& t, uint64_t wantSize, bool dynamic, uint64_t* batOffOut = nullptr, uint32_t* entriesOut = nullptr) {
    const uint64_t fs = t.size();
    unsigned char f[512], first[512];
    t.get(fs - 512, f, 512);
    assert(std::memcmp(f, "conectix", 8) == 0);
    assert(rbe32(f + 64) == checksum(f, 512, 64));
    assert(rbe64(f + 48) == wantSize);
    assert(rbe32(f + 60) == (dynamic ? 3u : 2u));
    if (dynamic) {
        t.get(0, first, 512);
        assert(std::memcmp(first, f, 512) == 0);              // the leading copy is kept identical
        unsigned char dyn[1024];
        t.get(rbe64(f + 16), dyn, sizeof(dyn));
        assert(std::memcmp(dyn, "cxsparse", 8) == 0);
        assert(rbe32(dyn + 36) == checksum(dyn, 1024, 36));
        const uint32_t bs = rbe32(dyn + 32), entries = rbe32(dyn + 28);
        assert(entries == (wantSize + bs - 1) / bs);
        if (batOffOut) *batOffOut = rbe64(dyn + 16);
        if (entriesOut) *entriesOut = entries;
        // every BAT entry past block 0 must still read "unallocated"
        std::vector<unsigned char> bat(size_t(entries) * 4);
        t.get(rbe64(dyn + 16), bat.data(), bat.size());
        for (uint32_t i = 1; i < entries; i++) assert(rbe32(&bat[i * 4]) == 0xFFFFFFFFu);
    }
}

static void checkReadback(const TempFile& t, uint64_t oldSize, uint64_t newSize, uint64_t patBytes) {
    VDisk d;
    assert(d.open(t.fd, t.size(), false));
    assert(d.size() == newSize);
    std::vector<unsigned char> buf(64 * 1024);
    for (uint64_t pos = 0; pos < newSize; pos += buf.size()) {
        const size_t n = size_t(std::min<uint64_t>(buf.size(), newSize - pos));
        assert(d.pread(pos, buf.data(), n));
        for (size_t i = 0; i < n; i++) {
            const uint64_t at = pos + i;
            const unsigned char want = at < patBytes ? pat(at) : 0;
            if (buf[i] != want) { std::printf("mismatch at %llu (old=%llu)\n", (unsigned long long)at, (unsigned long long)oldSize); assert(false); }
        }
    }
}

int main() {
    // ---- fixed VHD ----
    {
        TempFile t; buildFixed(t, 4 * kMiB);
        assert(probeVdiskKind(t.fd, t.size()) == VdiskKind::kVhdFixed);
        VdiskGrowReport rep;
        assert(vdiskGrow(t.fd, t.size(), 4 * kMiB + 1000, &rep) == VdiskGrowStatus::kNotLarger);      // < 1 MiB more rounds down
        assert(vdiskGrow(t.fd, t.size(), 10 * kMiB + 4096, &rep) == VdiskGrowStatus::kOk);
        assert(rep.oldSize == 4 * kMiB && rep.newSize == 10 * kMiB);
        assert(t.size() == 10 * kMiB + 512);
        validateFooter(t, 10 * kMiB, false);
        unsigned char old[512], zeros[512] = {0};
        t.get(4 * kMiB, old, 512);                                   // the old footer, now disk space, is cleared
        assert(std::memcmp(old, zeros, 512) == 0);
        checkReadback(t, 4 * kMiB, 10 * kMiB, 4 * kMiB);
        assert(vdiskGrow(t.fd, t.size(), 10 * kMiB, &rep) == VdiskGrowStatus::kNotLarger);
    }
    // ---- dynamic VHD, BAT grows in place (8 MiB / 2 MiB blocks = 4 entries, sector padding holds 128) ----
    {
        TempFile t; buildDynamic(t, 8 * kMiB, 2 * kMiB);
        assert(probeVdiskKind(t.fd, t.size()) == VdiskKind::kVhdDynamic);
        checkReadback(t, 0, 8 * kMiB, 2 * kMiB);                      // the builder itself is right
        const uint64_t before = t.size();
        VdiskGrowReport rep;
        assert(vdiskGrow(t.fd, t.size(), 100 * kMiB, &rep) == VdiskGrowStatus::kOk);
        uint64_t bat = 0; uint32_t entries = 0;
        validateFooter(t, 100 * kMiB, true, &bat, &entries);
        assert(bat == 1536 && entries == 50 && t.size() == before);   // same BAT, same file size
        checkReadback(t, 8 * kMiB, 100 * kMiB, 2 * kMiB);
    }
    // ---- dynamic VHD, BAT must be relocated behind the data (1 GiB = 512 entries > 128) ----
    {
        TempFile t; buildDynamic(t, 8 * kMiB, 2 * kMiB);
        const uint64_t before = t.size();
        VdiskGrowReport rep;
        assert(vdiskGrow(t.fd, t.size(), 1024 * kMiB, &rep) == VdiskGrowStatus::kOk);
        uint64_t bat = 0; uint32_t entries = 0;
        validateFooter(t, 1024 * kMiB, true, &bat, &entries);
        assert(bat == before && entries == 512 && t.size() == before + 2048 + 512);
        unsigned char oldFooterSlot[512], zeros[512] = {0};
        t.get(before - 512, oldFooterSlot, 512);                      // the stale trailing footer was cleared
        assert(std::memcmp(oldFooterSlot, zeros, 512) == 0);
        checkReadback(t, 8 * kMiB, 1024 * kMiB, 2 * kMiB);
        assert(vdiskGrow(t.fd, t.size(), 2048 * kMiB, &rep) == VdiskGrowStatus::kOk);   // and again, from the new BAT
        validateFooter(t, 2048 * kMiB, true);
        checkReadback(t, 1024 * kMiB, 2048 * kMiB, 2 * kMiB);
        assert(vdiskGrow(t.fd, t.size(), 2048 * kMiB, &rep) == VdiskGrowStatus::kNotLarger);
    }
    // ---- not a disk image / differencing ----
    {
        TempFile t; std::vector<unsigned char> junk(2 * kMiB, 0x5A); t.put(0, junk.data(), junk.size());
        assert(probeVdiskKind(t.fd, t.size()) == VdiskKind::kNone);
        VdiskGrowReport rep;
        assert(vdiskGrow(t.fd, t.size(), 8 * kMiB, &rep) == VdiskGrowStatus::kUnsupported);
        assert(t.size() == 2 * kMiB);
    }
    std::puts("vdisk_vhd_test: OK");
    return 0;
}
