// Host helper for containers/vdisk.{h,cpp}; driven by vdisk_grow_qemu_check.sh (needs qemu-img, not part of CI).
//   vdisk_grow_tool grow   <image> <newSizeBytes>   grow the virtual disk in place, print the result
//   vdisk_grow_tool verify <image> <expected.raw>   read the whole virtual disk through VDisk (the app's own VHD/VHDX
//                                                   readers) and compare: the first raw.size() bytes must match, the
//                                                   rest must be zero
// Build (from the cpp/ directory, with a stub android/log.h on the include path):
//   g++ -std=c++17 -I<stubs> -Icontainers containers/test/vdisk_grow_tool.cpp containers/vdisk.cpp
//       containers/vhd_image.cpp containers/vhdx_image.cpp -o vdisk_grow_tool
#include "../vdisk.h"

#include <cstdio>
#include <cstdlib>
#include <algorithm>
#include <cstring>
#include <string>
#include <vector>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

int main(int argc, char** argv) {
    if (argc < 4) { std::fprintf(stderr, "usage: %s grow|verify <image> <arg>\n", argv[0]); return 2; }
    const std::string mode = argv[1];
    const int fd = open(argv[2], O_RDWR);
    if (fd < 0) { std::perror("open"); return 2; }
    struct stat st{};
    fstat(fd, &st);
    const uint64_t fileSize = static_cast<uint64_t>(st.st_size);

    if (mode == "grow") {
        VdiskGrowReport rep;
        const VdiskGrowStatus s = vdiskGrow(fd, fileSize, std::strtoull(argv[3], nullptr, 10), &rep);
        std::printf("grow status=%d old=%llu new=%llu reason=%s\n", static_cast<int>(s),
                    static_cast<unsigned long long>(rep.oldSize), static_cast<unsigned long long>(rep.newSize), rep.reason);
        return s == VdiskGrowStatus::kOk ? 0 : 1;
    }

    VDisk disk;
    if (!disk.open(fd, fileSize, /*requestReadWrite=*/false)) { std::printf("open failed: %s\n", disk.lastError()); return 1; }
    FILE* raw = std::fopen(argv[3], "rb");
    if (!raw) { std::perror("raw"); return 2; }
    std::fseek(raw, 0, SEEK_END);
    const uint64_t rawSize = static_cast<uint64_t>(std::ftell(raw));
    std::fseek(raw, 0, SEEK_SET);
    std::vector<unsigned char> a(1 << 20), b(1 << 20);
    uint64_t mismatches = 0;
    for (uint64_t pos = 0; pos < disk.size(); pos += a.size()) {
        const size_t n = static_cast<size_t>(std::min<uint64_t>(a.size(), disk.size() - pos));
        if (!disk.pread(pos, a.data(), n)) { std::printf("read failed at %llu\n", static_cast<unsigned long long>(pos)); return 1; }
        std::memset(b.data(), 0, n);
        if (pos < rawSize) {
            const size_t m = static_cast<size_t>(std::min<uint64_t>(n, rawSize - pos));
            if (std::fread(b.data(), 1, m, raw) != m) { std::puts("raw short read"); return 2; }
        }
        if (std::memcmp(a.data(), b.data(), n) != 0) { mismatches++; if (mismatches < 4) std::printf("mismatch in 1MiB chunk at %llu\n", static_cast<unsigned long long>(pos)); }
    }
    std::printf("verify: virtualSize=%llu rawSize=%llu mismatchedChunks=%llu\n", static_cast<unsigned long long>(disk.size()),
                static_cast<unsigned long long>(rawSize), static_cast<unsigned long long>(mismatches));
    return mismatches == 0 ? 0 : 1;
}
