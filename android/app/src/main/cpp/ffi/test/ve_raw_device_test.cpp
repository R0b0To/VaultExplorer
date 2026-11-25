// Unit test for ffi/ve_raw_device.cpp: the per-slot registry, the 512-byte-sector view of a device whose real sector is
// larger (4Kn), the BitLocker / LUKS probing and the JSON listing. Links only ve_raw_device.cpp; the platform layer
// (veraw::plat) is replaced by an in-memory disk that, like a raw Windows handle, REFUSES any read or write that is not
// a whole number of sectors at a sector-aligned offset, so a missing alignment step in the adapter shows up as a failure.
//
//   g++ -std=c++17 ffi/test/ve_raw_device_test.cpp ffi/ve_raw_device.cpp -Iffi -o ve_raw_device_test && ./ve_raw_device_test
#include "ve_raw_device.h"

#include <cstdio>
#include <cstring>
#include <map>

static int g_checks = 0, g_failures = 0;
#define CHECK(cond)                                                                 \
    do {                                                                            \
        ++g_checks;                                                                 \
        if (!(cond)) {                                                              \
            ++g_failures;                                                           \
            std::fprintf(stderr, "  FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);  \
        }                                                                           \
    } while (0)

namespace {

struct FakeDisk {
    std::vector<unsigned char> bytes;
    uint32_t sector = 512;
    bool openFails = false;
    veraw::plat::OpenResult failWith = veraw::plat::OpenResult::kFailed;
    int syncs = 0;
    int closes = 0;
};
std::map<std::string, FakeDisk> g_disks;
std::map<veraw::plat::Handle, std::string> g_open;
veraw::plat::Handle g_next = 100;

FakeDisk& of(veraw::plat::Handle h) { return g_disks[g_open[h]]; }

}  // namespace

namespace veraw::plat {
OpenResult open(const std::string& path, bool, Handle* h, uint64_t* size, uint32_t* sector, int* err) {
    auto it = g_disks.find(path);
    if (it == g_disks.end()) { if (err) *err = 2; return OpenResult::kNotFound; }
    if (it->second.openFails) { if (err) *err = 13; return it->second.failWith; }
    *h = g_next++;
    g_open[*h] = path;
    *size = it->second.bytes.size();
    *sector = it->second.sector;
    return OpenResult::kOk;
}
bool pread(Handle h, void* buf, size_t len, uint64_t off) {
    FakeDisk& d = of(h);
    if (off % d.sector || len % d.sector || off + len > d.bytes.size()) return false;  // what a raw handle does
    std::memcpy(buf, d.bytes.data() + off, len);
    return true;
}
bool pwrite(Handle h, const void* buf, size_t len, uint64_t off) {
    FakeDisk& d = of(h);
    if (off % d.sector || len % d.sector || off + len > d.bytes.size()) return false;
    std::memcpy(d.bytes.data() + off, buf, len);
    return true;
}
bool sync(Handle h) { ++of(h).syncs; return true; }
void close(Handle h) { ++of(h).closes; g_open.erase(h); }
std::string canonical(const std::string& p) { return p; }
std::vector<DeviceInfo> enumerate() { return {}; }
}  // namespace veraw::plat

static std::vector<unsigned char> pattern(size_t n, unsigned char seed) {
    std::vector<unsigned char> v(n);
    for (size_t i = 0; i < n; ++i) v[i] = static_cast<unsigned char>(seed + i * 7);
    return v;
}

static void putLe(unsigned char* p, uint64_t v, int bytes) {
    for (int i = 0; i < bytes; ++i) p[i] = static_cast<unsigned char>(v >> (8 * i));
}

static void testSectorAdapter(uint32_t realSector) {
    std::printf("== sector adapter, device sector %u ==\n", realSector);
    const std::string path = "/fake/disk" + std::to_string(realSector);
    FakeDisk& d = g_disks[path];
    d = FakeDisk();
    d.sector = realSector;
    d.bytes = pattern(1 << 20, 3);
    const std::vector<unsigned char> original = d.bytes;

    uint64_t size = 0;
    int err = 0;
    CHECK(veraw::attach(0, path, true, &size, &err) == veraw::AttachResult::kOk);
    CHECK(size == (1u << 20));
    CHECK(veraw::isAttached(0));

    // Reads of 512-byte sectors, aligned or not to the real sector, come back exactly.
    unsigned char buf[2048];
    for (uint64_t start : {0ull, 1ull, 3ull, 7ull, 8ull, 9ull, 2040ull}) {
        CHECK(veraw::readSectors(0, start, 3, buf));
        CHECK(std::memcmp(buf, original.data() + start * 512, 3 * 512) == 0);
    }
    // Past the end, and a slot nothing is attached to, fail.
    CHECK(!veraw::readSectors(0, 2047, 2, buf));
    CHECK(!veraw::readSectors(1, 0, 1, buf));
    CHECK(!veraw::readSectors(-1, 0, 1, buf));

    // Writes: one sector inside a real sector, one straddling two real sectors, and a long run.
    std::vector<unsigned char> expect = original;
    auto doWrite = [&](uint64_t start, uint32_t count, unsigned char seed) {
        std::vector<unsigned char> data = pattern(static_cast<size_t>(count) * 512, seed);
        CHECK(veraw::writeSectors(0, start, count, data.data()));
        std::memcpy(expect.data() + start * 512, data.data(), data.size());
    };
    doWrite(3, 1, 0x11);
    doWrite(7, 2, 0x22);
    doWrite(15, 1, 0x33);
    doWrite(100, 37, 0x44);
    doWrite(0, 1, 0x55);
    CHECK(d.bytes == expect);  // and nothing else was touched (the read-modify-write kept the neighbours)

    CHECK(!veraw::writeSectors(0, 2047, 2, buf));  // past the end
    CHECK(veraw::syncDevice(0));
    CHECK(d.syncs >= 1);

    // The same disk cannot be claimed by a second slot; another disk can.
    CHECK(veraw::attach(1, path, false, &size, &err) == veraw::AttachResult::kAlreadyOpen);
    g_disks["/fake/other"].bytes = pattern(1 << 16, 9);
    CHECK(veraw::attach(1, "/fake/other", false, &size, &err) == veraw::AttachResult::kOk);
    CHECK(!veraw::writeSectors(1, 0, 1, buf));  // opened read-only: writes are refused
    veraw::detach(1);

    veraw::detach(0);
    CHECK(!veraw::isAttached(0));
    CHECK(d.closes == 1);
    CHECK(!veraw::readSectors(0, 0, 1, buf));
    veraw::detach(0);  // detaching twice is harmless
    CHECK(d.closes == 1);
    CHECK(veraw::attach(1, path, false, &size, &err) == veraw::AttachResult::kOk);  // free again
    veraw::detach(1);
}

static void testOpenErrors() {
    std::printf("== open errors ==\n");
    uint64_t size = 0;
    int err = 0;
    CHECK(veraw::attach(0, "/fake/missing", true, &size, &err) == veraw::AttachResult::kNotFound && err == 2);
    FakeDisk& denied = g_disks["/fake/denied"];
    denied.bytes = pattern(4096, 1);
    denied.openFails = true;
    denied.failWith = veraw::plat::OpenResult::kPermission;
    CHECK(veraw::attach(0, "/fake/denied", true, &size, &err) == veraw::AttachResult::kPermission && err == 13);
    denied.failWith = veraw::plat::OpenResult::kBusy;
    CHECK(veraw::attach(0, "/fake/denied", true, &size, &err) == veraw::AttachResult::kBusy);
    CHECK(!veraw::isAttached(0));
    CHECK(veraw::attach(0, "", true, &size, &err) == veraw::AttachResult::kFailed);
    CHECK(veraw::attach(9999, "/fake/other", true, &size, &err) == veraw::AttachResult::kFailed);
    FakeDisk& tiny = g_disks["/fake/tiny"];
    tiny.bytes = pattern(100, 1);  // smaller than one sector: an empty card-reader slot
    CHECK(veraw::attach(0, "/fake/tiny", false, &size, &err) == veraw::AttachResult::kFailed);
}

static void testProbe(uint32_t ss) {
    std::printf("== format probe, sector %u ==\n", ss);
    const size_t total = 64u * 1024 * 1024;
    // MBR: BitLocker in partition 1 (LBA 2048*512/ss), LUKS in partition 2.
    {
        FakeDisk& d = g_disks["/fake/mbr"];
        d = FakeDisk();
        d.sector = ss;
        d.bytes.assign(total, 0);
        unsigned char* mbr = d.bytes.data();
        const uint64_t p1 = (1u << 20) / ss, p2 = (8u << 20) / ss;
        mbr[446 + 4] = 0x07; putLe(mbr + 446 + 8, p1, 4); putLe(mbr + 446 + 12, (4u << 20) / ss, 4);
        mbr[462 + 4] = 0x83; putLe(mbr + 462 + 8, p2, 4); putLe(mbr + 462 + 12, (4u << 20) / ss, 4);
        mbr[510] = 0x55; mbr[511] = 0xAA;
        std::memcpy(d.bytes.data() + p1 * ss + 3, "-FVE-FS-", 8);
        std::memcpy(d.bytes.data() + p2 * ss, "LUKS\xba\xbe", 6);
        veraw::plat::Handle h; uint64_t size; uint32_t sector; int err;
        CHECK(veraw::plat::open("/fake/mbr", false, &h, &size, &sector, &err) == veraw::plat::OpenResult::kOk);
        const auto f = veraw::probeFormats(h, size, sector);
        CHECK(f.size() == 2 && f[0] == "bitlocker" && f[1] == "luks");
        veraw::plat::close(h);
    }
    // GPT: LUKS in the second entry; protective MBR in front.
    {
        FakeDisk& d = g_disks["/fake/gpt"];
        d = FakeDisk();
        d.sector = ss;
        d.bytes.assign(total, 0);
        unsigned char* b = d.bytes.data();
        b[446 + 4] = 0xEE; putLe(b + 446 + 8, 1, 4); putLe(b + 446 + 12, 0xFFFFFFFF, 4);
        b[510] = 0x55; b[511] = 0xAA;
        unsigned char* hdr = b + ss;
        std::memcpy(hdr, "EFI PART", 8);
        putLe(hdr + 72, 2, 8);    // entries at LBA 2
        putLe(hdr + 80, 128, 4);  // 128 entries
        putLe(hdr + 84, 128, 4);  // of 128 bytes
        unsigned char* entries = b + 2ull * ss;
        for (int i : {0, 1}) {
            unsigned char* e = entries + i * 128;
            e[0] = 0xAF; e[1] = 0x3D;  // a non-zero type GUID
            putLe(e + 32, ((static_cast<uint64_t>(i) + 1) * (2u << 20)) / ss, 8);
        }
        std::memcpy(b + (4u << 20) + 0, "LUKS\xba\xbe", 6);  // entry 1 starts at 4 MiB
        veraw::plat::Handle h; uint64_t size; uint32_t sector; int err;
        CHECK(veraw::plat::open("/fake/gpt", false, &h, &size, &sector, &err) == veraw::plat::OpenResult::kOk);
        const auto f = veraw::probeFormats(h, size, sector);
        CHECK(f.size() == 1 && f[0] == "luks");
        veraw::plat::close(h);
    }
    // No partition table at all: the whole disk is one BitLocker volume.
    {
        FakeDisk& d = g_disks["/fake/raw"];
        d = FakeDisk();
        d.sector = ss;
        d.bytes.assign(1u << 20, 0);
        std::memcpy(d.bytes.data() + 3, "-FVE-FS-", 8);
        veraw::plat::Handle h; uint64_t size; uint32_t sector; int err;
        CHECK(veraw::plat::open("/fake/raw", false, &h, &size, &sector, &err) == veraw::plat::OpenResult::kOk);
        const auto f = veraw::probeFormats(h, size, sector);
        CHECK(f.size() == 1 && f[0] == "bitlocker");
        veraw::plat::close(h);
    }
    // Nothing recognisable, and a garbage partition table, give no formats and no crash.
    {
        FakeDisk& d = g_disks["/fake/junk"];
        d = FakeDisk();
        d.sector = ss;
        d.bytes = pattern(1u << 20, 77);
        d.bytes[510] = 0x55; d.bytes[511] = 0xAA;
        veraw::plat::Handle h; uint64_t size; uint32_t sector; int err;
        CHECK(veraw::plat::open("/fake/junk", false, &h, &size, &sector, &err) == veraw::plat::OpenResult::kOk);
        (void)veraw::probeFormats(h, size, sector);
        veraw::plat::close(h);
    }
}

static void testJson() {
    std::printf("== json ==\n");
    veraw::DeviceInfo d;
    d.path = "/dev/disk/by-id/usb-A\"B\\C";
    d.name = "Vendor \xC3\xA9 Model\n";
    d.bus = "usb";
    d.sizeBytes = 123456789012ull;
    d.sectorSize = 4096;
    d.removable = true;
    d.readable = true;
    d.formats = {"bitlocker", "luks"};
    const std::string j = veraw::devicesToJson({d});
    CHECK(j == "[{\"path\":\"/dev/disk/by-id/usb-A\\\"B\\\\C\",\"name\":\"Vendor \xC3\xA9 Model\\n\",\"bus\":\"usb\","
               "\"sizeBytes\":123456789012,\"sectorSize\":4096,\"removable\":true,\"readable\":true,\"writable\":false,"
               "\"inUse\":false,\"system\":false,\"formats\":[\"bitlocker\",\"luks\"]}]");
    CHECK(veraw::devicesToJson({}) == "[]");
}

int main() {
    testSectorAdapter(512);
    testSectorAdapter(4096);
    testOpenErrors();
    testProbe(512);
    testProbe(4096);
    testJson();
    std::printf("\n%d checks, %d failed\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
