#include "../composite_block_device.h"
#include "../carrier_profiler.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <vector>

int main() {
    printf("composite_block_device_test: running assertions...\n");

    // 1. Create simulated carriers using temp files
    auto fdCache = std::make_shared<CarrierFdCache>(4);

    char tmp1[] = "/tmp/vx_carrier_1_XXXXXX";
    char tmp2[] = "/tmp/vx_carrier_2_XXXXXX";
    int fd1 = mkstemp(tmp1);
    int fd2 = mkstemp(tmp2);
    assert(fd1 >= 0 && fd2 >= 0);

    // Populate each carrier with 4096 bytes of distinct patterns
    std::vector<unsigned char> p1(4096, 0xAA);
    std::vector<unsigned char> p2(4096, 0xBB);
    assert(::pwrite(fd1, p1.data(), 4096, 0) == 4096);
    assert(::pwrite(fd2, p2.data(), 4096, 0) == 4096);

    uint32_t idx1 = fdCache->addTarget(fd1, tmp1, false, true);
    uint32_t idx2 = fdCache->addTarget(fd2, tmp2, false, true);

    // 2. Define extents: Carrier 1 (offset 512, len 1024), Carrier 2 (offset 0, len 1536)
    std::vector<CarrierExtent> extents = {
        {idx1, 512, 1024},
        {idx2, 0, 1536}
    };

    CompositeBlockDevice dev(extents, fdCache);
    assert(dev.totalSize() == 2560); // 1024 + 1536

    // 3. Test read across extent boundary
    // Read 1024 bytes starting at offset 512 (512 bytes from Carrier 1, 512 bytes from Carrier 2)
    std::vector<unsigned char> readBuf(1024, 0);
    assert(dev.pread(512, readBuf.data(), 1024));
    for (size_t i = 0; i < 512; ++i) assert(readBuf[i] == 0xAA);
    for (size_t i = 512; i < 1024; ++i) assert(readBuf[i] == 0xBB);

    // 4. Test write across boundary
    std::vector<unsigned char> writeBuf(512, 0xCC);
    assert(dev.pwrite(768, writeBuf.data(), 512));

    std::vector<unsigned char> verifyBuf(512, 0);
    assert(dev.pread(768, verifyBuf.data(), 512));
    for (size_t i = 0; i < 512; ++i) assert(verifyBuf[i] == 0xCC);

    // 5. Test out-of-bounds rejected
    assert(!dev.pread(2560, readBuf.data(), 1));
    assert(!dev.pwrite(2550, writeBuf.data(), 20));

    // Cleanup
    unlink(tmp1);
    unlink(tmp2);

    printf("composite_block_device_test: all assertions passed successfully.\n");
    return 0;
}