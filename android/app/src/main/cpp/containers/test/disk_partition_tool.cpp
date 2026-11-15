// Host helper for containers/disk_partition.h; driven by disk_partition_sfdisk_check.sh (needs sfdisk/sgdisk).
//   disk_partition_tool scan <raw-disk>
//   disk_partition_tool grow <raw-disk> <newDiskBytes> <startLba>
// Build (cpp/ dir): g++ -std=c++17 -I<mbedtls include> containers/test/disk_partition_tool.cpp -o disk_partition_tool
#include "../disk_partition.h"

#include <cstdio>
#include <cstdlib>
#include <string>
#include <fcntl.h>
#include <unistd.h>

int main(int argc, char** argv) {
    if (argc < 3) return 2;
    const int fd = open(argv[2], O_RDWR);
    if (fd < 0) { std::perror("open"); return 2; }
    DiskIo io;
    io.read = [fd](uint64_t o, unsigned char* b, size_t l) { return pread(fd, b, l, (off_t)o) == (ssize_t)l; };
    io.write = [fd](uint64_t o, const unsigned char* b, size_t l) { return pwrite(fd, b, l, (off_t)o) == (ssize_t)l; };
    io.sync = [fd]() { return fsync(fd) == 0; };
    const std::string mode = argv[1];
    if (mode == "scan") {
        std::vector<DiskPartition> parts; bool gpt = false;
        const PtResult r = ptScan(io, parts, gpt);
        std::printf("scan rc=%d gpt=%d\n", (int)r, gpt);
        for (auto& p : parts) std::printf("  start=%llu sectors=%llu type=0x%02x\n", (unsigned long long)p.startLba, (unsigned long long)p.sectors, p.mbrType);
        return r == PtResult::kOk ? 0 : 1;
    }
    uint64_t ns = 0;
    const PtResult r = ptGrowPartition(io, std::strtoull(argv[3], nullptr, 10), std::strtoull(argv[4], nullptr, 10), &ns);
    std::printf("grow rc=%d newSectors=%llu\n", (int)r, (unsigned long long)ns);
    return (r == PtResult::kOk || r == PtResult::kNothingToDo) ? 0 : 1;
}
