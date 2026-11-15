// Host CLI around the project's public LUKS API (luks_header.h), used only for differential testing.
#include "crypto/luks_header.h"
#include "crypto/luks_cipher.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

static std::string hex(const std::vector<uint8_t>& v) {
    std::string s; char b[3];
    for (auto c : v) { snprintf(b, 3, "%02x", c); s += b; }
    return s;
}
static std::string readPass(const char* path) {  // password = file content (no trailing newline stripping)
    FILE* f = fopen(path, "rb"); if (!f) { perror("pass"); exit(2); }
    std::string s; char buf[4096]; size_t n;
    while ((n = fread(buf, 1, sizeof buf, f)) > 0) s.append(buf, n);
    fclose(f); return s;
}
static void printInfo(const LuksVolumeInfo& i) {
    printf("OK version=%d cipher=%s mode=%s keybytes=%u dataoffset=%llu sectorsize=%llu ivtweak=%llu dynamic=%d size=%llu segs=%u crypt=%d integrity=%d flags=%d mandatory=%d\n",
           i.version, i.cipherName.c_str(), i.cipherMode.c_str(), i.keyBytes,
           (unsigned long long)i.dataOffsetBytes, (unsigned long long)i.dataSectorSize,
           (unsigned long long)i.ivTweak, i.dynamicSize, (unsigned long long)i.dataSizeBytes,
           i.dataSegmentCount, i.dataIsCryptSegment, i.dataHasIntegrity, i.dataSegmentHasFlags, i.hasMandatoryRequirements);
    printf("MK %s\n", hex(i.masterKey).c_str());
}
int main(int argc, char** argv) {
    if (argc < 3) { fprintf(stderr, "usage\n"); return 2; }
    std::string cmd = argv[1];
    if (cmd == "unlock") {            // unlock <img> <passfile>
        int fd = open(argv[2], O_RDONLY); if (fd < 0) { perror("open"); return 2; }
        std::string p = readPass(argv[3]); LuksVolumeInfo info;
        bool ok = luksRecoverMasterKey(fd, (const uint8_t*)p.data(), p.size(), info);
        if (!ok) { printf("FAIL\n"); return 1; }
        printInfo(info); return 0;
    }
    if (cmd == "create") {            // create <img> <passfile> <sizeBytes> <ver> <cipher> <hash> <pbkdf2iters|argon2> [mem time cpus]
        int fd = open(argv[2], O_RDWR | O_CREAT, 0600); if (fd < 0) { perror("open"); return 2; }
        std::string p = readPass(argv[3]); int64_t size = atoll(argv[4]);
        if (ftruncate(fd, size) != 0) { perror("ftruncate"); return 2; }
        LuksCreateParams cp; cp.version = atoi(argv[5]); cp.cipherName = argv[6]; cp.hashName = argv[7];
        if (!strcmp(argv[8], "argon2")) { cp.useArgon2id = true; cp.argon2MemoryKiB = atoi(argv[9]); cp.argon2TimeCost = atoi(argv[10]); cp.argon2Parallelism = atoi(argv[11]); }
        else cp.pbkdf2Iterations = atoi(argv[8]);
        LuksVolumeInfo info;
        if (!luksCreateHeader(fd, (const uint8_t*)p.data(), p.size(), size, cp, info)) { printf("FAIL\n"); return 1; }
        printInfo(info); return 0;
    }
    if (cmd == "chpw") {              // chpw <img> <oldpassfile> <newpassfile>
        int fd = open(argv[2], O_RDWR); if (fd < 0) { perror("open"); return 2; }
        std::string o = readPass(argv[3]), n = readPass(argv[4]);
        auto r = luksChangeKeyslotPassword(fd, (const uint8_t*)o.data(), o.size(), (const uint8_t*)n.data(), n.size());
        printf(r == LuksChangePasswordResult::kSuccess ? "OK\n" : r == LuksChangePasswordResult::kWrongOldPassword ? "WRONGPW\n" : "ERROR\n");
        return r == LuksChangePasswordResult::kSuccess ? 0 : 1;
    }
    if (cmd == "integrity") {         // integrity <img>
        int fd = open(argv[2], O_RDONLY); if (fd < 0) { perror("open"); return 2; }
        LuksByteReader rd = [fd](uint64_t off, void* out, size_t len) { return pread(fd, out, len, off) == (ssize_t)len; };
        bool p = false, s = false; bool ok = luks2CheckHeaderIntegrity(rd, p, s);
        printf("ok=%d primary=%d secondary=%d probe=%d\n", ok, p, s, (int)luksProbeHeader(rd));
        return 0;
    }
    if (cmd == "cipher") {            // cipher <name> <mode> <keyhex> <iv512> <sectorSize> <enc|dec> <datahex>
        auto unhex = [](const std::string& h) { std::vector<uint8_t> v; for (size_t i = 0; i + 1 < h.size(); i += 2) v.push_back((uint8_t)strtoul(h.substr(i, 2).c_str(), nullptr, 16)); return v; };
        auto key = unhex(argv[4]); auto data = unhex(argv[8]);
        LuksCipherSpec spec;
        if (!luksParseCipherSpec(argv[2], argv[3], key.size(), spec)) { printf("REJECT\n"); return 1; }
        LuksCipherContext ctx;
        if (!luksCipherInit(ctx, spec, key.data(), key.size())) { printf("INITFAIL\n"); return 1; }
        std::vector<uint8_t> out(data.size());
        if (!luksCipherCrypt(ctx, !strcmp(argv[7], "enc"), strtoull(argv[5], nullptr, 10), atoi(argv[6]), data.data(), out.data(), data.size())) { printf("CRYPTFAIL\n"); return 1; }
        printf("%s\n", hex(out).c_str()); return 0;
    }
    if (cmd == "chpw-fail") {         // chpw-fail <img> <old> <new> <failAfterWrites>   (simulates the process dying mid-change)
        int fd = open(argv[2], O_RDWR); if (fd < 0) { perror("open"); return 2; }
        std::string o = readPass(argv[3]), n = readPass(argv[4]); int limit = atoi(argv[5]); int count = 0;
        LuksByteReader rd = [fd](uint64_t off, void* out, size_t len) { return pread(fd, out, len, off) == (ssize_t)len; };
        LuksByteWriter wr = [&](uint64_t off, const void* d, size_t len) { if (count++ >= limit) return false; return pwrite(fd, d, len, off) == (ssize_t)len; };
        auto r = luksChangeKeyslotPassword(rd, wr, (const uint8_t*)o.data(), o.size(), (const uint8_t*)n.data(), n.size());
        printf("%s writes=%d\n", r == LuksChangePasswordResult::kSuccess ? "OK" : r == LuksChangePasswordResult::kWrongOldPassword ? "WRONGPW" : "ERROR", count > limit ? limit : count);
        return 0;
    }
    if (cmd == "restore") {           // restore <img>
        int fd = open(argv[2], O_RDWR); if (fd < 0) { perror("open"); return 2; }
        LuksByteReader rd = [fd](uint64_t off, void* out, size_t len) { return pread(fd, out, len, off) == (ssize_t)len; };
        LuksByteWriter wr = [fd](uint64_t off, const void* d, size_t len) { return pwrite(fd, d, len, off) == (ssize_t)len; };
        printf("%s\n", luks2RestoreHeaderFromBackup(rd, wr) ? "RESTORED" : "REFUSED"); return 0;
    }
    if (cmd == "dataoffset") {        // dataoffset <img>
        int fd = open(argv[2], O_RDONLY); if (fd < 0) { perror("open"); return 2; }
        LuksByteReader rd = [fd](uint64_t off, void* out, size_t len) { return pread(fd, out, len, off) == (ssize_t)len; };
        uint64_t off = 0; bool ok = luks2DataSegmentOffset(rd, off); printf("%s %llu\n", ok ? "OK" : "FAIL", (unsigned long long)off); return 0;
    }
    if (cmd == "resize" || cmd == "resize-validate") {   // resize <img> <oldsize> <newsize>
        int fd = open(argv[2], O_RDWR); if (fd < 0) { perror("open"); return 2; }
        uint64_t oldS = strtoull(argv[3], nullptr, 10), newS = strtoull(argv[4], nullptr, 10);
        LuksByteReader rd = [fd](uint64_t off, void* out, size_t len) { return pread(fd, out, len, off) == (ssize_t)len; };
        if (cmd == "resize-validate") {
            uint64_t dOff = 0, oldData = 0, iv = 0; bool dyn = false, repair = false;
            bool ok = luks2ValidateResize(rd, oldS, newS, dOff, oldData, iv, dyn, repair);
            printf("%s dataoffset=%llu olddata=%llu dynamic=%d repair=%d\n", ok ? "OK" : "REFUSED", (unsigned long long)dOff, (unsigned long long)oldData, dyn, repair); return 0;
        }
        LuksByteWriter wr = [fd](uint64_t off, const void* d, size_t len) { return pwrite(fd, d, len, off) == (ssize_t)len; };
        LuksByteSync sy = [fd]() { return fsync(fd) == 0; };
        printf("%s\n", luks2ResizeSegmentMetadata(rd, wr, oldS, newS, sy) ? "RESIZED" : "FAIL"); return 0;
    }
    fprintf(stderr, "unknown cmd\n"); return 2;
}
