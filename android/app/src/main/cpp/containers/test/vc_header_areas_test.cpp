// Host-side test, no Android toolchain required:
//   g++ -std=c++17 -I . containers/test/vc_header_areas_test.cpp -o vc_header_areas_test && ./vc_header_areas_test
//
// The reserved header areas of a new container must be filled with random
// bytes (so a missing hidden-volume header is indistinguishable from a present
// one) and nothing else may be touched.
#include "containers/vc_header_areas.h"
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <string>
#include <vector>

namespace {

constexpr uint64_t kA = 131072;

struct TempFile {
    std::string path;
    int fd = -1;
    TempFile() {
        char tmpl[] = "/tmp/vc_areas_XXXXXX";
        fd = mkstemp(tmpl);
        assert(fd >= 0);
        path = tmpl;
    }
    ~TempFile() {
        if (fd >= 0) close(fd);
        unlink(path.c_str());
    }
    uint64_t size() const { return static_cast<uint64_t>(lseek(fd, 0, SEEK_END)); }
    std::vector<unsigned char> read(uint64_t off, size_t n) const {
        std::vector<unsigned char> v(n);
        assert(pread(fd, v.data(), n, static_cast<off_t>(off)) == static_cast<ssize_t>(n));
        return v;
    }
};

// Deterministic stand-in for the real random source: never emits a zero byte,
// so "random-filled" is distinguishable from "left as zeros" in assertions.
struct FakeRandom {
    uint32_t state = 1;
    bool fail = false;
    bool operator()(void* out, size_t n) {
        if (fail) return false;
        auto* p = static_cast<unsigned char*>(out);
        for (size_t i = 0; i < n; ++i) {
            state = state * 1664525u + 1013904223u;
            p[i] = static_cast<unsigned char>((state >> 24) | 1u);
        }
        return true;
    }
};

bool noZeroByte(const std::vector<unsigned char>& v) {
    for (unsigned char c : v) if (c == 0) return false;
    return true;
}
bool allZero(const std::vector<unsigned char>& v) {
    for (unsigned char c : v) if (c != 0) return false;
    return true;
}

auto fdSink(int fd) {
    return [fd](uint64_t off, const unsigned char* p, size_t n) { return vcgeom::pwriteFully(fd, off, p, n); };
}

}  // namespace

// Both groups random, data area untouched, every 512-byte slot (hidden header
// slots included) non-zero.
static void testFillsBothGroupsAndOnlyThose() {
    TempFile f;
    const uint64_t V = 4 * kA + 8192;
    assert(ftruncate(f.fd, static_cast<off_t>(V)) == 0);
    FakeRandom rnd;
    assert(vcgeom::randomizeHeaderGroups(0, V, fdSink(f.fd), rnd));
    assert(noZeroByte(f.read(0, kA)));
    assert(noZeroByte(f.read(V - kA, kA)));
    assert(allZero(f.read(kA, V - 2 * kA)));
    // The two slots a no-hidden-volume container used to leave as zeros.
    assert(noZeroByte(f.read(TC_HIDDEN_VOLUME_HEADER_OFFSET, 512)));
    assert(noZeroByte(f.read(V - TC_VOLUME_HEADER_SIZE, 512)));
}

// On a file that is still empty the fill must establish the full length (the
// creation code relies on this instead of writing a final marker byte).
static void testExtendsAnEmptyFileToContainerSize() {
    TempFile f;
    const uint64_t V = 3 * kA;
    FakeRandom rnd;
    assert(f.size() == 0);
    assert(vcgeom::randomizeHeaderGroups(0, V, fdSink(f.fd), rnd));
    assert(f.size() == V);
    assert(noZeroByte(f.read(V - 1, 1)));
}

// A container embedded at a non-zero base (USB partition) is filled there.
static void testHonoursBaseOffset() {
    TempFile f;
    const uint64_t base = 1 << 20, V = 2 * kA + 4096;
    assert(ftruncate(f.fd, static_cast<off_t>(base + V + 4096)) == 0);
    FakeRandom rnd;
    assert(vcgeom::randomizeHeaderGroups(base, V, fdSink(f.fd), rnd));
    assert(allZero(f.read(0, 4096)));
    assert(noZeroByte(f.read(base, kA)));
    assert(noZeroByte(f.read(base + V - kA, kA)));
    assert(allZero(f.read(base + V, 4096)));
}

static void testFailuresPropagate() {
    TempFile f;
    const uint64_t V = 2 * kA + 4096;
    FakeRandom bad;
    bad.fail = true;
    assert(!vcgeom::randomizeHeaderGroups(0, V, fdSink(f.fd), bad));
    FakeRandom ok;
    int ro = open(f.path.c_str(), O_RDONLY);
    assert(ro >= 0);
    assert(!vcgeom::randomizeHeaderGroups(0, V, fdSink(ro), ok));   // write refused
    close(ro);
    FakeRandom ok2;
    assert(!vcgeom::randomizeHeaderGroups(0, 2 * kA - 512, fdSink(f.fd), ok2));  // too small
}

// Chunking: a range that is not a multiple of the chunk size is covered exactly.
static void testWriteRandomRangeOddLength() {
    TempFile f;
    assert(ftruncate(f.fd, 300000) == 0);
    FakeRandom rnd;
    assert(vcgeom::writeRandomRange(1000, 200003, fdSink(f.fd), rnd));
    assert(allZero(f.read(0, 1000)));
    assert(noZeroByte(f.read(1000, 200003)));
    assert(allZero(f.read(201003, 300000 - 201003)));
}

int main() {
    testFillsBothGroupsAndOnlyThose();
    testExtendsAnEmptyFileToContainerSize();
    testHonoursBaseOffset();
    testFailuresPropagate();
    testWriteRandomRangeOddLength();
    std::puts("vc_header_areas_test: all passed");
    return 0;
}
