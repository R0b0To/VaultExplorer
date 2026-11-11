// Host-side test for containers/vc_expand.h. With argv[1] it dumps the expanded images for
// verification/oracle_expand.py (independent implementation of upstream's algorithm).
#include "../vc_expand.h"
#include <cassert>
#include <cstdio>
#include <vector>
bool deriveHeaderKey(HashId hash, const unsigned char* pw, size_t pwLen, const unsigned char* salt,
                     int clampedPim, unsigned char* out, size_t outLen, std::function<bool()> cancel) {
    if (hash == HashId::kArgon2id) return false;
    return pbkdf2Hmac(hash, pw, pwLen, salt, VC_SALT_SIZE,
                      static_cast<unsigned int>(iterationsForHash(hash, clampedPim)), out, outLen, cancel);
}
static void be64(unsigned char* p, uint64_t v) { for (int i = 7; i >= 0; --i) p[7 - i] = (v >> (i * 8)) & 0xFF; }
static void be32(unsigned char* p, uint32_t v) { for (int i = 0; i < 4; i++) p[i] = (v >> (24 - 8 * i)) & 0xFF; }
static void makeBody(unsigned char* b, uint64_t host) {
    memset(b, 0, VC_HEADER_BODY_SIZE);
    vcStampHeaderPreamble(b);
    be64(b + VC_HDR_OFF_VOLUME_SIZE, host - 262144);
    be64(b + VC_HDR_OFF_KEY_SCOPE_START, 131072);
    be64(b + VC_HDR_OFF_KEY_SCOPE_SIZE, host - 262144);
    be32(b + VC_HDR_OFF_SECTOR_SIZE, 512);
    for (int i = 0; i < 64; i++) b[VC_KEY_OFFSET_MASTER + i] = (unsigned char)(i * 11 + 5);
    be32(b + VC_HDR_OFF_KEY_CRC, vcCrc32(b + VC_KEY_OFFSET_MASTER, VC_HDR_KEY_CRC_COVERAGE_LEN));
    be32(b + VC_HDR_OFF_HEADER_CRC, vcCrc32(b, VC_HDR_CRC_COVERAGE_LEN));
}
int main(int argc, char** argv) {
    const uint64_t OLD = 1048576, NEW = 2097152 + 1000;           // 1000 extra bytes: must round down to 4096
    const unsigned char pw[] = "Passw0rd!"; const size_t pwLen = sizeof(pw) - 1;
    for (bool init : {true, false}) {
        std::vector<unsigned char> img(OLD, 0x5C);
        unsigned char body[VC_HEADER_BODY_SIZE]; makeBody(body, OLD);
        // a recognisable old backup header area, and one encrypted data sector
        CascadeContext dc; cascadeSetKeys(dc, CascadeId::kAes, body + VC_KEY_OFFSET_MASTER, 64);
        unsigned char sec[512], enc[512]; for (int i = 0; i < 512; i++) sec[i] = (unsigned char)(i * 3);
        cascadeEncryptSector(dc, 131072 / 512, sec, enc); memcpy(&img[131072], enc, 512);
        VcExpandIo io;
        io.setSize = [&](uint64_t n) { img.resize(n, 0); return true; };                         // sparse extension = zeros
        io.writeAt = [&](uint64_t off, const unsigned char* d, size_t n) { if (off + n > img.size()) return false; memcpy(&img[off], d, n); return true; };
        io.random = [&](unsigned char* p, size_t n) { return userentropy::fillRandom(p, n); };
        uint64_t last = 0; io.progress = [&](uint64_t d, uint64_t) { last = d; return true; };
        assert(vcExpandVolume(body, CascadeId::kAes, HashId::kSha512, pw, pwLen, 1, OLD, NEW, init, io) == VcExpandResult::kOk);
        const uint64_t N = (NEW / 4096) * 4096;
        assert(img.size() == N);
        assert(init ? last > 0 : last == 0);
        // old data untouched
        unsigned char chk[512]; cascadeDecryptSector(dc, 131072 / 512, &img[131072], chk); assert(!memcmp(chk, sec, 512));
        // new data area: encrypted zeros (init) decrypt to zeros; quick leaves the sparse zero extension
        const uint64_t probe = OLD;                                                              // first byte after the old end, inside the new data area
        cascadeDecryptSector(dc, probe / 512, &img[probe], chk);
        if (init) { for (int i = 0; i < 512; i++) assert(chk[i] == 0); assert(img[probe] != 0 || img[probe + 1] != 0); }
        else { for (int i = 0; i < 512; i++) assert(img[probe + 4096 + i] == 0); }
        // the old backup header group (old end - 128K) no longer looks like it did
        bool wiped = false; for (int i = 0; i < 512; i++) if (img[OLD - 131072 + i] != 0x5C) wiped = true; assert(wiped);
        if (argc > 1) { char path[512]; snprintf(path, sizeof path, "%s_%s.bin", argv[1], init ? "init" : "quick"); FILE* f = fopen(path, "wb"); fwrite(img.data(), 1, img.size(), f); fclose(f); }
    }
    // refusals
    { std::vector<unsigned char> img(OLD); unsigned char b[VC_HEADER_BODY_SIZE]; VcExpandIo io;
      io.setSize = [&](uint64_t) { return true; }; io.writeAt = [&](uint64_t, const unsigned char*, size_t) { return true; };
      io.random = [&](unsigned char* p, size_t n) { memset(p, 1, n); return true; };
      makeBody(b, OLD); assert(vcExpandVolume(b, CascadeId::kAes, HashId::kSha512, pw, pwLen, 1, OLD, OLD, true, io) == VcExpandResult::kNotLarger);
      makeBody(b, OLD); be64(b + VC_HDR_OFF_HIDDEN_VOL_SIZE, 4096); assert(vcExpandVolume(b, CascadeId::kAes, HashId::kSha512, pw, pwLen, 1, OLD, NEW, true, io) == VcExpandResult::kHiddenHeader);
      makeBody(b, OLD + 4096); assert(vcExpandVolume(b, CascadeId::kAes, HashId::kSha512, pw, pwLen, 1, OLD, NEW, true, io) == VcExpandResult::kInconsistentHeader); }
    printf("vc_expand_test: all assertions passed\n");
    return 0;
}
