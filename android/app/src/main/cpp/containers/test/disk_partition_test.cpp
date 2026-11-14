// Host-side test for containers/disk_partition.h on in-memory disks (no external tools). Builds MBR and GPT disks, grows
// the last partition, and checks the result with a validator written independently of the production code. The sfdisk /
// sgdisk cross-check lives in disk_partition_sfdisk_check.sh.
//
// Build: g++ -std=c++17 -I<mbedtls include> containers/test/disk_partition_test.cpp -o disk_partition_test
#include "../disk_partition.h"

#include <array>
#include <cassert>
#include <cstdio>
#include <vector>

using blexp::rd32; using blexp::rd64; using blexp::wr32; using blexp::wr64;

static const uint64_t kMiB = 1 << 20;

struct Disk {
    std::vector<unsigned char> d;
    DiskIo io;
    int writes = 0;
    void bind() {
        io.read = [this](uint64_t o, unsigned char* b, size_t l) { if (o + l > d.size()) return false; std::memcpy(b, &d[o], l); return true; };
        io.write = [this](uint64_t o, const unsigned char* b, size_t l) { if (o + l > d.size()) return false; std::memcpy(&d[o], b, l); writes++; return true; };
        io.sync = [] { return true; };
    }
};

static uint32_t crcOf(const unsigned char* p, size_t n) { return blexp::crc32(p, n); }

static void mbrEntry(unsigned char* s0, int i, uint8_t type, uint32_t start, uint32_t count) {
    unsigned char* e = s0 + 446 + 16 * i;
    e[4] = type; wr32(e + 8, start); wr32(e + 12, count);
}

static Disk makeMbr(uint64_t bytes, std::initializer_list<std::array<uint32_t, 3>> parts) {
    Disk x; x.d.assign(bytes, 0);
    int i = 0;
    for (auto& p : parts) mbrEntry(x.d.data(), i++, (uint8_t)p[0], p[1], p[2]);
    x.d[510] = 0x55; x.d[511] = 0xAA;
    x.bind(); return x;
}

// GPT: [protective MBR][primary hdr][32 entry sectors] ... [backup entries][backup hdr]; entries given as (start,end).
static Disk makeGpt(uint64_t bytes, std::initializer_list<std::array<uint64_t, 2>> parts) {
    Disk x; x.d.assign(bytes, 0); x.bind();
    const uint64_t total = bytes / 512, last = total - 1;
    unsigned char* s0 = x.d.data();
    mbrEntry(s0, 0, 0xEE, 1, (uint32_t)(total - 1)); s0[510] = 0x55; s0[511] = 0xAA;
    std::vector<unsigned char> ent(128 * 128, 0);
    int i = 0;
    for (auto& p : parts) {
        unsigned char* e = &ent[128 * i++];
        e[0] = 0xA2; e[16] = (unsigned char)(0x10 + i);   // type / unique guid (non-zero)
        wr64(e + 32, p[0]); wr64(e + 40, p[1]);
    }
    auto header = [&](uint64_t my, uint64_t alt, uint64_t entLba, unsigned char* h) {
        std::memset(h, 0, 512);
        std::memcpy(h, "EFI PART", 8); wr32(h + 8, 0x00010000); wr32(h + 12, 92);
        wr64(h + 24, my); wr64(h + 32, alt); wr64(h + 40, 34); wr64(h + 48, last - 33);
        for (int k = 0; k < 16; k++) h[56 + k] = (unsigned char)(0xD0 + k);
        wr64(h + 72, entLba); wr32(h + 80, 128); wr32(h + 84, 128); wr32(h + 88, crcOf(ent.data(), ent.size()));
        wr32(h + 16, crcOf(h, 92));
    };
    header(1, last, 2, s0 + 512);
    std::memcpy(s0 + 1024, ent.data(), ent.size());
    std::memcpy(s0 + (last - 32) * 512, ent.data(), ent.size());
    header(last, 1, last - 32, s0 + last * 512);
    return x;
}

// Independent GPT validator: both headers + both entry arrays, backup at the very end, returns the end LBA of the entry
// that starts at [startLba] (0 if absent).
static bool validGpt(const Disk& x, uint64_t startLba, uint64_t* endLba) {
    const uint64_t total = x.d.size() / 512, last = total - 1;
    for (uint64_t lba : {uint64_t(1), last}) {
        unsigned char h[512]; std::memcpy(h, &x.d[lba * 512], 512);
        if (std::memcmp(h, "EFI PART", 8)) return false;
        const uint32_t crc = rd32(h + 16); wr32(h + 16, 0);
        if (crcOf(h, rd32(h + 12)) != crc) return false;
        if (rd64(h + 24) != lba) return false;
        if (rd64(h + 32) != (lba == 1 ? last : 1)) return false;
        if (rd64(h + 48) != last - 33) return false;                          // last usable
        const uint64_t el = rd64(h + 72);
        if (lba == 1 && el != 2) return false;
        if (lba == last && el != last - 32) return false;
        if (crcOf(&x.d[el * 512], rd32(h + 80) * rd32(h + 84)) != rd32(h + 88)) return false;
        if (endLba) {
            *endLba = 0;
            for (uint32_t i = 0; i < rd32(h + 80); i++) {
                const unsigned char* e = &x.d[el * 512 + i * rd32(h + 84)];
                if (rd64(e + 32) == startLba) *endLba = rd64(e + 40);
            }
        }
    }
    const unsigned char* pm = &x.d[446];
    return pm[4] == 0xEE && rd32(pm + 12) == total - 1;
}

int main() {
    uint64_t ns = 0; PtResult r;

    // ---- MBR ----
    {
        Disk x = makeMbr(64 * kMiB, {{0x83, 2048, 20480}, {0x07, 22528, 64 * 2048 - 22528}});
        x.d.resize(300 * kMiB, 0);
        r = ptGrowPartition(x.io, 300 * kMiB, 22528, &ns);
        assert(r == PtResult::kOk && ns == 300 * 2048 - 22528);
        assert(rd32(&x.d[446 + 16 + 12]) == 300 * 2048 - 22528);
        assert(rd32(&x.d[446 + 12]) == 20480);                                 // first partition untouched
        assert(x.d[510] == 0x55 && x.d[511] == 0xAA);
        const int w = x.writes;
        r = ptGrowPartition(x.io, 300 * kMiB, 22528, &ns);                     // resume / second run
        assert(r == PtResult::kNothingToDo && x.writes == w && ns == 300 * 2048 - 22528);
        r = ptGrowPartition(x.io, 300 * kMiB, 2048, &ns);                      // not the last partition
        assert(r == PtResult::kNotLast);
        r = ptGrowPartition(x.io, 300 * kMiB, 999, &ns);
        assert(r == PtResult::kNotFound);
        std::vector<DiskPartition> p; bool gpt = true;
        assert(ptScan(x.io, p, gpt) == PtResult::kOk && !gpt && p.size() == 2 && p[1].startLba == 22528);
    }
    {   // extended partition target is refused and nothing is written
        Disk x = makeMbr(64 * kMiB, {{0x83, 2048, 20480}, {0x05, 22528, 1000}});
        x.d.resize(100 * kMiB, 0);
        assert(ptGrowPartition(x.io, 100 * kMiB, 22528, &ns) == PtResult::kUnsupported && x.writes == 0);
    }
    {   // 2 TiB limit of the 32-bit MBR size field
        Disk x = makeMbr(64 * kMiB, {{0x07, 2048, 100000}});
        Disk big; big.d = x.d; big.bind();
        r = ptGrowPartition(big.io, 3ull << 40, 2048, &ns);                    // the disk is not really that big: logic only
        assert(r == PtResult::kOk && uint64_t(2048) + ns == (1ull << 32));
    }
    // ---- GPT ----
    {
        const uint64_t old = 64 * kMiB / 512;
        Disk x = makeGpt(64 * kMiB, {{2048, 22527}, {22528, old - 34}});
        uint64_t end = 0;
        assert(validGpt(x, 22528, &end) && end == old - 34);
        // grow the disk: the old backup is now in the interior
        const uint64_t oldBackupHdr = (old - 1) * 512, oldBackupEnt = (old - 33) * 512;
        x.d.resize(500 * kMiB, 0);
        r = ptGrowPartition(x.io, 500 * kMiB, 22528, &ns);
        const uint64_t total = 500 * kMiB / 512;
        assert(r == PtResult::kOk && ns == (total - 34) - 22528 + 1);
        assert(validGpt(x, 22528, &end) && end == total - 34);
        assert(validGpt(x, 2048, &end) && end == 22527);                      // other partition unchanged
        for (size_t i = 0; i < 512; i++) assert(x.d[oldBackupHdr + i] == 0);  // old backup header cleared
        for (size_t i = 0; i < 128 * 128; i++) assert(x.d[oldBackupEnt + i] == 0);
        const int w = x.writes;
        r = ptGrowPartition(x.io, 500 * kMiB, 22528, &ns);
        assert(r == PtResult::kNothingToDo && x.writes == w);
        assert(ptGrowPartition(x.io, 500 * kMiB, 2048, &ns) == PtResult::kNotLast);
        std::vector<DiskPartition> p; bool gpt = false;
        assert(ptScan(x.io, p, gpt) == PtResult::kOk && gpt && p.size() == 2 && p[0].startLba == 2048 && p[1].sectors == ns);
    }
    {   // damaged primary header: refuse, write nothing
        Disk x = makeGpt(64 * kMiB, {{2048, 64 * 2048 - 35}});
        x.d.resize(200 * kMiB, 0); x.d[512 + 40] ^= 0xFF;
        assert(ptGrowPartition(x.io, 200 * kMiB, 2048, &ns) == PtResult::kUnsupported && x.writes == 0);
    }
    {   // no partition table at all
        Disk x; x.d.assign(10 * kMiB, 0); x.bind();
        assert(ptGrowPartition(x.io, 10 * kMiB, 2048, &ns) == PtResult::kNoTable);
    }
    std::puts("disk_partition_test: OK");
    return 0;
}
