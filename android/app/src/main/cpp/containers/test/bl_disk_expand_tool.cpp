// Host helper for the disk-image BitLocker expansion; driven by bl_disk_expand_qemu_check.sh.
// Needs dislocker (upstream, host build) only to obtain the VMK / verify decrypted content -- the expansion itself
// (blDiskLocate / blDiskExpand) is the production code.
//   bl_disk_expand_tool vmk    <raw-disk> <volumeOffsetBytes> <password>      -> "vmk=<hex> volume=<bytes> sha=<hex>"
//   bl_disk_expand_tool expand <image> <vmkHex> <newDiskBytes>                 -> expands, prints the result
//   bl_disk_expand_tool verify <raw-disk> <volumeOffsetBytes> <password> <oldVolumeBytes> <shaHex> <newVolumeBytes>
#include "../bl_disk_expand.h"
#include "../bl_expand.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

extern "C" {
#include "dislocker/dislocker.h"
#include "dislocker/config.h"
#include "dislocker/vmk_export.h"
uint64_t dis_host_volume_size(dis_context_t c);
}

static FILE* LOG;

static dis_context_t openCtx(const char* path, const char* pw, off_t offset, bool ro) {
    dis_context_t c = dis_new();
    dis_setopt(c, DIS_OPT_VOLUME_PATH, path);
    int one = 1;
    dis_setopt(c, DIS_OPT_USE_USER_PASSWORD, &one);
    dis_setopt(c, DIS_OPT_SET_USER_PASSWORD, pw);
    dis_setopt(c, DIS_OPT_VOLUME_OFFSET, &offset);
    if (ro) dis_setopt(c, DIS_OPT_READ_ONLY, &one);
    dis_setopt(c, DIS_OPT_DONT_CHECK_VOLUME_STATE, &one);
    if (dis_initialize(c) != 0) return nullptr;
    return c;
}

static std::string sha(dis_context_t c, uint64_t bytes) {
    mbedtls_sha256_context s; mbedtls_sha256_init(&s); mbedtls_sha256_starts(&s, 0);
    std::vector<uint8_t> buf(1 << 20);
    for (uint64_t pos = 0; pos < bytes;) {
        size_t n = (size_t)std::min<uint64_t>(buf.size(), bytes - pos);
        if (dislock(c, buf.data(), (off_t)pos, n) < 0) return "READ-FAILED";
        mbedtls_sha256_update(&s, buf.data(), n);
        pos += n;
    }
    unsigned char d[32]; mbedtls_sha256_finish(&s, d); mbedtls_sha256_free(&s);
    char hex[65]; for (int i = 0; i < 32; i++) std::snprintf(hex + 2 * i, 3, "%02x", d[i]);
    return hex;
}

int main(int argc, char** argv) {
    LOG = fdopen(dup(2), "w");   // dislocker redirects stdout
    if (argc < 3) return 2;
    const std::string mode = argv[1];
    if (mode == "vmk") {
        dis_context_t c = openCtx(argv[2], argv[4], (off_t)std::strtoull(argv[3], nullptr, 10), true);
        if (!c) { std::fprintf(LOG, "FAIL unlock\n"); return 1; }
        unsigned char vmk[32]; const size_t n = dis_export_vmk(c, vmk, sizeof(vmk));
        const uint64_t vol = dis_host_volume_size(c);
        std::fprintf(LOG, "vmk=");
        for (size_t i = 0; i < n; i++) std::fprintf(LOG, "%02x", vmk[i]);
        std::fprintf(LOG, " volume=%llu sha=%s\n", (unsigned long long)vol, sha(c, vol).c_str());
        return 0;
    }
    if (mode == "expand") {
        const int fd = open(argv[2], O_RDWR);
        if (fd < 0) { std::perror("open"); return 2; }
        unsigned char vmk[32]; const std::string hex = argv[3];
        for (size_t i = 0; i < 32 && 2 * i + 1 < hex.size(); i++) vmk[i] = (unsigned char)std::strtoul(hex.substr(2 * i, 2).c_str(), nullptr, 16);
        struct stat st{}; fstat(fd, &st);
        BlDiskLocation loc;
        BlDiskResult r = blDiskLocate(fd, (uint64_t)st.st_size, &loc);
        std::fprintf(LOG, "locate=%d kind=%d disk=%llu whole=%d partStart=%llu partBytes=%llu\n", (int)r, (int)loc.kind,
                     (unsigned long long)loc.diskBytes, loc.wholeDisk, (unsigned long long)loc.partStartBytes, (unsigned long long)loc.partBytes);
        if (r != BlDiskResult::kOk) return 1;
        BlDiskExpandResult res;
        r = blDiskExpand(fd, loc, vmk, 32, std::strtoull(argv[4], nullptr, 10), 133800000000000000ull, &res);
        std::fprintf(LOG, "expand=%d disk=%llu part=%llu volume %llu -> %llu\n", (int)r, (unsigned long long)res.newDiskBytes,
                     (unsigned long long)res.newPartBytes, (unsigned long long)res.oldVolumeBytes, (unsigned long long)res.newVolumeBytes);
        return r == BlDiskResult::kOk ? 0 : 1;
    }
    if (mode == "verify") {   // raw-disk pw oldVol sha newVol
        dis_context_t c = openCtx(argv[2], argv[4], (off_t)std::strtoull(argv[3], nullptr, 10), true);
        if (!c) { std::fprintf(LOG, "FAIL unlock after expand\n"); return 1; }
        const uint64_t vol = dis_host_volume_size(c);
        const uint64_t oldVol = std::strtoull(argv[5], nullptr, 10), newVol = std::strtoull(argv[7], nullptr, 10);
        const std::string h = sha(c, oldVol);
        uint8_t tail[4096];
        const bool tailOk = dislock(c, tail, (off_t)(vol - sizeof(tail)), sizeof(tail)) >= 0;
        std::fprintf(LOG, "volume=%llu (want %llu) content=%s tail=%d\n", (unsigned long long)vol, (unsigned long long)newVol, h == argv[6] ? "identical" : "DIFFERENT", tailOk);
        return (vol == newVol && h == argv[6] && tailOk) ? 0 : 1;
    }
    return 2;
}
