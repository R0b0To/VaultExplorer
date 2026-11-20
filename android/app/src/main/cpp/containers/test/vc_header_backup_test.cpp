// Host-side test for containers/vc_header_backup.h (desktop-VeraCrypt "restore header" write semantics).
// Needs the crypto sources (see verification/run_all.sh). With argv[1] it also dumps the resulting container
// image so verification/oracle_restore.py can check it with an independent implementation.
#include "../vc_header_backup.h"
#include <cassert>
#include <cstdio>
#include <vector>

bool deriveHeaderKey(HashId hash, const unsigned char* pw, size_t pwLen, const unsigned char* salt,
                     int clampedPim, unsigned char* out, size_t outLen, std::function<bool()> cancel) {
    if (hash == HashId::kArgon2id) return false;
    return pbkdf2Hmac(hash, pw, pwLen, salt, VC_SALT_SIZE,
                      static_cast<unsigned int>(iterationsForHash(hash, clampedPim)), out, outLen, cancel);
}
static uint32_t crc32(const unsigned char* d, size_t n) {
    uint32_t c = 0xFFFFFFFFu;
    for (size_t i = 0; i < n; i++) { c ^= d[i]; for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320u & (0u - (c & 1u))); }
    return ~c;
}
static void be64(unsigned char* p, uint64_t v) { for (int i = 7; i >= 0; --i) p[7 - i] = (v >> (i * 8)) & 0xFF; }
static void be32(unsigned char* p, uint32_t v) { for (int i = 0; i < 4; i++) p[i] = (v >> (24 - 8 * i)) & 0xFF; }

static void makeBody(unsigned char* b, CascadeId c, bool hidden, uint64_t dataStart, uint64_t dataLen, unsigned seed) {
    memset(b, 0, VC_HEADER_BODY_SIZE);
    vcStampHeaderPreamble(b);
    if (hidden) be64(b + VC_HDR_OFF_HIDDEN_VOL_SIZE, dataLen);
    be64(b + VC_HDR_OFF_VOLUME_SIZE, dataLen);
    be64(b + VC_HDR_OFF_KEY_SCOPE_START, dataStart);
    be64(b + VC_HDR_OFF_KEY_SCOPE_SIZE, dataLen);
    be32(b + VC_HDR_OFF_SECTOR_SIZE, 512);
    const int keyLen = cascadeSpecFor(c).layerCount * 64;
    for (int i = 0; i < keyLen; i++) b[VC_KEY_OFFSET_MASTER + i] = (unsigned char)(i * 13 + seed);
    be32(b + VC_HDR_OFF_KEY_CRC, crc32(b + VC_KEY_OFFSET_MASTER, VC_HDR_KEY_CRC_COVERAGE_LEN));
    be32(b + VC_HDR_OFF_HEADER_CRC, crc32(b, VC_HDR_CRC_COVERAGE_LEN));
}
static bool decryptSector(CascadeId c, HashId h, const unsigned char* pw, size_t pwLen, int pim,
                          const unsigned char* sector, unsigned char* body) {
    unsigned char hk[192] = {0};
    if (!deriveHeaderKey(h, pw, pwLen, sector, pim, hk, sizeof hk, nullptr)) return false;
    const CascadeSpec spec = cascadeSpecFor(c);
    CascadeContext ctx;
    if (!cascadeSetKeys(ctx, c, hk, spec.layerCount * 64)) return false;
    memcpy(body, sector + VC_SALT_SIZE, VC_HEADER_BODY_SIZE);
    for (int layer = 0; layer < spec.layerCount; layer++) {
        const XtsLayerKey& lk = ctx.layers[layer];
        unsigned char T[16] = {0};
        blockCipherEncryptBlock(lk.tweakKey, T, T);
        for (int blk = 0; blk < 28; blk++) {
            unsigned char* bp = body + blk * 16;
            unsigned char tmp[16];
            for (int j = 0; j < 16; j++) tmp[j] = bp[j] ^ T[j];
            blockCipherDecryptBlock(lk.dataKeyDec, tmp, tmp);
            for (int j = 0; j < 16; j++) bp[j] = tmp[j] ^ T[j];
            xtsMultiplyTweak(T);
        }
    }
    return true;
}

int main(int argc, char** argv) {
    const uint64_t V = 1048576;
    const unsigned char pw[] = "Passw0rd!";
    const size_t pwLen = sizeof(pw) - 1;
    for (CascadeId c : {CascadeId::kAes, CascadeId::kAesTwofishSerpent}) {
        for (bool hidden : {false, true}) {
            std::vector<unsigned char> img(V, 0xAB);                     // sentinel: anything untouched stays 0xAB
            unsigned char body[VC_HEADER_BODY_SIZE];
            makeBody(body, c, hidden, hidden ? V - 131072 - 262144 : 131072, hidden ? 262144 : V - 262144, hidden ? 3 : 1);
            auto writeAt = [&](uint64_t off, const unsigned char* d, size_t n) {
                if (off + n > img.size()) return false; memcpy(img.data() + off, d, n); return true; };
            assert(vcApplyRestoredHeader(body, c, HashId::kSha512, pw, pwLen, 1, hidden, V, writeAt) == VcRestoreApplyResult::kOk);
            const uint64_t prim = hidden ? 65536 : 0, back = hidden ? V - 65536 : V - 131072;
            const uint64_t otherPrim = hidden ? 0 : 65536, otherBack = hidden ? V - 131072 : V - 65536;
            // only the matching header and ITS backup were written; the other volume's slots are untouched
            for (size_t i = 0; i < 512; i++) assert(img[otherPrim + i] == 0xAB && img[otherBack + i] == 0xAB);
            // each copy decrypts to the original header, and the two copies are independent encryptions
            unsigned char d1[VC_HEADER_BODY_SIZE], d2[VC_HEADER_BODY_SIZE];
            assert(decryptSector(c, HashId::kSha512, pw, pwLen, 1, &img[prim], d1) && !memcmp(d1, body, sizeof d1));
            assert(decryptSector(c, HashId::kSha512, pw, pwLen, 1, &img[back], d2) && !memcmp(d2, body, sizeof d2));
            assert(memcmp(&img[prim], &img[back], 512) != 0);
            assert(memcmp(&img[prim], body, 64) != 0);
            if (argc > 1 && c == CascadeId::kAes) {
                char path[512]; snprintf(path, sizeof path, "%s_%s.bin", argv[1], hidden ? "hidden" : "normal");
                FILE* f = fopen(path, "wb"); fwrite(img.data(), 1, img.size(), f); fclose(f);
            }
        }
    }
    // refusals
    unsigned char body[VC_HEADER_BODY_SIZE];
    makeBody(body, CascadeId::kAes, false, 131072, 786432, 1);
    memcpy(body + VC_KEY_OFFSET_MASTER + 32, body + VC_KEY_OFFSET_MASTER, 32);          // identical XTS key halves
    auto noWrite = [](uint64_t, const unsigned char*, size_t) { return true; };
    assert(vcApplyRestoredHeader(body, CascadeId::kAes, HashId::kSha512, pw, pwLen, 1, false, V, noWrite) == VcRestoreApplyResult::kVulnerableKey);
    makeBody(body, CascadeId::kAes, false, 131072, 786432, 1);
    assert(vcApplyRestoredHeader(body, CascadeId::kAes, HashId::kSha512, pw, pwLen, 1, false, 1000, noWrite) == VcRestoreApplyResult::kContainerTooSmall);
    auto failWrite = [](uint64_t, const unsigned char*, size_t) { return false; };
    assert(vcApplyRestoredHeader(body, CascadeId::kAes, HashId::kSha512, pw, pwLen, 1, false, V, failWrite) == VcRestoreApplyResult::kIoError);
    printf("vc_header_backup_test: all assertions passed\n");
    return 0;
}
