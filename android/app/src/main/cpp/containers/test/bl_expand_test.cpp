// Host-side test for containers/bl_expand.h (no NDK needed).
//
// The synthetic volume below is built by an independent routine (buildVolume) that follows the on-disk layout
// documented in bl_expand.h, then blExpandVolume() rewrites it. The result is checked three ways:
//   1. with bl_expand.h's own validators (after-write read-back),
//   2. with an independent validator written here (checkIndependently),
//   3. with dislocker's own code when compiled in (-DBL_EXPAND_TEST_WITH_DISLOCKER): its crc32() and its
//      Microsoft-style AES-CCM decrypt_key(), which only succeeds when the MAC matches.
//
// Build (from the cpp/ directory; MBEDTLS_DIR = an mbedTLS 3.6 checkout/install, LIB = its static crypto lib):
//   g++ -std=c++17 -I$MBEDTLS_DIR/include containers/test/bl_expand_test.cpp $LIB -o bl_expand_test
// With the dislocker cross-check (DISLOCKER = the fetched upstream tree, OVERLAY = app overlay headers dir):
//   gcc -c -w -D_GNU_SOURCE -Dcrc32=dis_crc32 -I$DISLOCKER/include -I$MBEDTLS_DIR/include $DISLOCKER/src/encryption/{decrypt,crc32,diffuser,aes-xts}.c
//   g++ -std=c++17 -DBL_EXPAND_TEST_WITH_DISLOCKER -I$MBEDTLS_DIR/include -I$DISLOCKER/include ... (see CMakeLists.txt)
#include "../bl_expand.h"

#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#ifdef BL_EXPAND_TEST_WITH_DISLOCKER
extern "C" {
unsigned int dis_crc32(const unsigned char* s, const unsigned int len);
int decrypt_key(unsigned char* input, unsigned int input_size, unsigned char* mac, unsigned char* nonce,
                unsigned char* key, unsigned int keybits, void** output);
}
#endif

using blexp::rd16; using blexp::rd32; using blexp::rd64;
using blexp::wr16; using blexp::wr32; using blexp::wr64;

static const uint64_t kOld = 8ull << 20;         // 8 MiB volume
static const uint32_t kSector = 512;
static const uint64_t kOffsets[3] = {1ull << 20, 3ull << 20, 5ull << 20};
static const size_t kBlock = 0x300;              // metadata block size (multiple of 16)

struct Image {
    std::vector<unsigned char> data;
    BlExpandIo io;
    int setSizeCalls = 0, writes = 0;
    std::vector<uint64_t> writeOffsets;
    int failWriteAt = -1;                         // fail the n-th write (0-based), -1 = never
};

static void bindIo(Image& img) {
    img.io.readAt = [&img](uint64_t off, unsigned char* out, size_t len) {
        if (off + len > img.data.size()) return false;
        std::memcpy(out, &img.data[off], len);
        return true;
    };
    img.io.writeAt = [&img](uint64_t off, const unsigned char* d, size_t len) {
        if (img.failWriteAt >= 0 && img.writes == img.failWriteAt) { img.writes++; return false; }
        if (off + len > img.data.size()) return false;
        std::memcpy(&img.data[off], d, len);
        img.writeOffsets.push_back(off);
        img.writes++;
        return true;
    };
    img.io.setSize = [&img](uint64_t n) { img.data.resize(n, 0); img.setSizeCalls++; return true; };
    img.io.sync = [] { return true; };
}

// Independent construction of one sealed metadata copy (does not call bl_expand.h helpers except for the primitives
// mbedTLS/CRC, which are verified against dislocker separately).
static void buildVolume(Image& img, const unsigned char* vmk, uint16_t state = 4, uint64_t volSize = kOld) {
    img.data.assign(kOld, 0xA5);
    unsigned char* vbr = img.data.data();
    std::memset(vbr, 0, 512);
    std::memcpy(vbr + 3, "-FVE-FS-", 8);
    wr16(vbr + 0x0B, kSector);
    static const unsigned char kClassicGuid[16] = {0x3b, 0xd6, 0x67, 0x49, 0x29, 0x2e, 0xd8, 0x4a,
                                                   0x83, 0x99, 0xf6, 0xa3, 0x39, 0xe3, 0xd0, 0x01};
    std::memcpy(vbr + 0xA0, kClassicGuid, 16);
    for (int i = 0; i < 3; i++) wr64(vbr + 0xB0 + 8 * i, kOffsets[i]);
    vbr[510] = 0x55; vbr[511] = 0xAA;

    std::vector<unsigned char> block(kBlock, 0);
    std::memcpy(block.data(), "-FVE-FS-", 8);
    wr16(&block[8], kBlock >> 4);
    wr16(&block[10], 2);
    wr16(&block[12], state);
    wr16(&block[14], state);
    wr64(&block[16], volSize);
    for (int i = 0; i < 3; i++) wr64(&block[32 + 8 * i], kOffsets[i]);
    wr64(&block[56], 0x600000);
    wr32(&block[0x40], kBlock - 0x40);            // dataset size
    wr32(&block[0x44], 1);
    wr32(&block[0x48], 0x30);
    wr32(&block[0x4C], kBlock - 0x40);
    wr32(&block[0x60], 41);                       // next_counter
    wr16(&block[0x64], 0x8001);                   // algorithm
    for (size_t i = 0x70; i < kBlock; i++) block[i] = static_cast<unsigned char>(i * 7 + 3);   // fake datums

    // Validation record: size 88, version 2, CRC, nested datum header, sealed SHA-256.
    std::vector<unsigned char> val(blexp::kValRecordLen, 0);
    wr16(&val[0], 88); wr16(&val[2], 2);
    wr16(&val[8], 80); wr16(&val[10], 0); wr16(&val[12], 5);
    unsigned char plain[44] = {0};
    wr16(plain + 0, 44); wr16(plain + 2, 0); wr16(plain + 4, 1); wr16(plain + 6, 0x0001);
    wr16(plain + 8, 0x2005); wr16(plain + 10, 0);
    assert(blexp::sha256(block.data(), block.size(), plain + 12));
    unsigned char nonce[12];
    for (int i = 0; i < 12; i++) nonce[i] = static_cast<unsigned char>(0x30 + i);
    unsigned char enc[44], mac[16];
    mbedtls_ccm_context ccm; mbedtls_ccm_init(&ccm);
    assert(mbedtls_ccm_setkey(&ccm, MBEDTLS_CIPHER_ID_AES, vmk, 256) == 0);
    assert(mbedtls_ccm_encrypt_and_tag(&ccm, 44, nonce, 12, nullptr, 0, plain, enc, mac, 16) == 0);
    mbedtls_ccm_free(&ccm);
    std::memcpy(&val[16], nonce, 12); std::memcpy(&val[28], mac, 16); std::memcpy(&val[44], enc, 44);
    wr32(&val[4], blexp::crc32(block.data(), block.size()));

    for (int i = 0; i < 3; i++) {
        std::memcpy(&img.data[kOffsets[i]], block.data(), block.size());
        std::memcpy(&img.data[kOffsets[i] + block.size()], val.data(), val.size());
    }
    bindIo(img);
}

// Independent validator for the final state of copy i: CRC, sealed hash, header fields.
static bool checkIndependently(const Image& img, int i, const unsigned char* vmk, uint64_t expectVolSize,
                               uint32_t expectCounter) {
    const unsigned char* b = &img.data[kOffsets[i]];
    const unsigned char* v = b + kBlock;
    if (rd64(b + 16) != expectVolSize) return false;
    if (rd32(b + 0x60) != expectCounter) return false;
    if (blexp::crc32(b, kBlock) != rd32(v + 4)) return false;
#ifdef BL_EXPAND_TEST_WITH_DISLOCKER
    if (dis_crc32(b, kBlock) != rd32(v + 4)) return false;           // dislocker's CRC agrees
#endif
    unsigned char plain[44];
    mbedtls_ccm_context ccm; mbedtls_ccm_init(&ccm);
    mbedtls_ccm_setkey(&ccm, MBEDTLS_CIPHER_ID_AES, vmk, 256);
    const int rc = mbedtls_ccm_auth_decrypt(&ccm, 44, v + 16, 12, nullptr, 0, v + 44, plain, v + 28, 16);
    mbedtls_ccm_free(&ccm);
    if (rc != 0) return false;
    unsigned char digest[32];
    mbedtls_sha256(b, kBlock, digest, 0);
    if (std::memcmp(digest, plain + 12, 32) != 0) return false;
#ifdef BL_EXPAND_TEST_WITH_DISLOCKER
    {   // dislocker's own MS-style CCM decryption must accept the rebuilt record (it verifies the MAC itself)
        unsigned char encCopy[44], macCopy[16], nonceCopy[12], keyCopy[32];
        std::memcpy(encCopy, v + 44, 44); std::memcpy(macCopy, v + 28, 16);
        std::memcpy(nonceCopy, v + 16, 12); std::memcpy(keyCopy, vmk, 32);
        void* out = nullptr;
        if (!decrypt_key(encCopy, 44, macCopy, nonceCopy, keyCopy, 256, &out)) return false;
        const bool same = std::memcmp(out, plain, 44) == 0;
        std::free(out);   // dis_malloc == malloc in the test stubs
        if (!same) return false;
    }
#endif
    return true;
}

#ifdef BL_EXPAND_TEST_WITH_DISLOCKER
// Minimal stand-ins for the dislocker support code decrypt.c links against.
extern "C" {
void* dis_malloc(size_t size) { return std::calloc(1, size); }
int dis_printf(int, const char*, ...) { return 0; }
void hexdump(int, uint8_t*, size_t) {}
void xor_buffer(unsigned char* buf1, const unsigned char* buf2, unsigned char* output, size_t size) {
    unsigned char* tmp = output ? output : buf1;
    for (size_t i = 0; i < size; ++i) tmp[i] = buf1[i] ^ buf2[i];
}
void diffuserA_decrypt(...) {}
void diffuserB_decrypt(...) {}
int dis_aes_crypt_xts(...) { return 0; }
}
#endif

int main() {
    unsigned char vmk[32];
    for (int i = 0; i < 32; i++) vmk[i] = static_cast<unsigned char>(i * 5 + 1);
    unsigned char wrongVmk[32]; std::memcpy(wrongVmk, vmk, 32); wrongVmk[7] ^= 1;
    const uint64_t kFiletime = 133800000000000000ull;

    // 0. CRC-32 matches the standard check value.
    { const unsigned char s[] = "123456789"; assert(blexp::crc32(s, 9) == 0xCBF43926u); }

    // 1. Happy path: file smaller than the target is extended; all three copies rewritten; counter bumped.
    {
        Image img; buildVolume(img, vmk);
        const uint64_t before = img.data.size();
        const std::vector<unsigned char> vbrBefore(img.data.begin(), img.data.begin() + 512);
        uint64_t o = 0, n = 0;
        const uint64_t req = 20ull * 1024 * 1024 + 777;                 // not sector aligned -> rounds down
        assert(blExpandVolume(vmk, 32, before, req, kFiletime, img.io, &o, &n) == BlExpandResult::kOk);
        const uint64_t want = (req / kSector) * kSector;
        assert(o == kOld && n == want);
        assert(img.setSizeCalls == 1 && img.data.size() == want);
        assert(img.writeOffsets.size() == 3);
        assert(img.writeOffsets[0] == kOffsets[2] && img.writeOffsets[2] == kOffsets[0]);   // last copy first
        for (int i = 0; i < 3; i++) assert(checkIndependently(img, i, vmk, want, 42));
        // everything outside the three metadata regions is untouched (VBR and filler); the file tail is the new space
        for (size_t i = 0; i < before; i++) {
            bool inMeta = false;
            for (int k = 0; k < 3; k++)
                if (i >= kOffsets[k] && i < kOffsets[k] + kBlock + blexp::kValRecordLen) inMeta = true;
            if (!inMeta) { unsigned char exp = i < 512 ? vbrBefore[i] : 0xA5; assert(img.data[i] == exp); }
        }
        // the recorded volume size is what a key-less reader sees
        uint64_t sz = 0; uint32_t ss = 0;
        assert(blReadEncryptedVolumeSize(img.io, img.data.size(), sz, ss) == BlExpandResult::kOk);
        assert(sz == want && ss == kSector);
        // a second expand to the same size is a no-op error; to a larger size works again (counter now 43 -> 44)
        assert(blExpandVolume(vmk, 32, img.data.size(), want, kFiletime + 1, img.io) == BlExpandResult::kNotLarger);
        assert(blExpandVolume(vmk, 32, img.data.size(), want + 4096, kFiletime + 2, img.io) == BlExpandResult::kOk);
        for (int i = 0; i < 3; i++) assert(checkIndependently(img, i, vmk, want + 4096, 43));
    }

    // 2. File already extended earlier (retry after an interrupted run): no setSize call, volume grows to the file.
    {
        Image img; buildVolume(img, vmk);
        img.data.resize(kOld + (4 << 20), 0);
        assert(blExpandVolume(vmk, 32, img.data.size(), img.data.size(), kFiletime, img.io) == BlExpandResult::kOk);
        assert(img.setSizeCalls == 0);
        for (int i = 0; i < 3; i++) assert(checkIndependently(img, i, vmk, kOld + (4 << 20), 42));
    }

    // 3. Refusals leave the image byte-for-byte unchanged.
    {
        Image img; buildVolume(img, vmk);
        const std::vector<unsigned char> snapshot = img.data;
        assert(blExpandVolume(wrongVmk, 32, kOld, kOld * 2, kFiletime, img.io) == BlExpandResult::kInvalidMetadata);
        assert(blExpandVolume(vmk, 32, kOld, kOld, kFiletime, img.io) == BlExpandResult::kNotLarger);
        assert(blExpandVolume(vmk, 32, kOld, kOld - 4096, kFiletime, img.io) == BlExpandResult::kNotLarger);
        assert(blExpandVolume(vmk, 31, kOld, kOld * 2, kFiletime, img.io) == BlExpandResult::kInvalidMetadata);
        assert(blExpandVolume(vmk, 32, kOld - 4096, kOld * 2, kFiletime, img.io) != BlExpandResult::kOk);   // host smaller than volume
        assert(img.data == snapshot && img.setSizeCalls == 0 && img.writes == 0);

        Image notBl; buildVolume(notBl, vmk); std::memcpy(&notBl.data[3], "NTFS    ", 8);
        assert(blExpandVolume(vmk, 32, kOld, kOld * 2, kFiletime, notBl.io) == BlExpandResult::kNotBitLocker);

        Image eow; buildVolume(eow, vmk);                                // encrypt-on-write GUID -> not expandable
        static const unsigned char kEowGuid[16] = {0x3b, 0x4d, 0xa8, 0x92, 0x80, 0xdd, 0x0e, 0x4d,
                                                   0x9e, 0x4e, 0xb1, 0xe3, 0x28, 0x4e, 0xae, 0xd8};
        std::memcpy(&eow.data[0xA0], kEowGuid, 16);
        assert(blExpandVolume(vmk, 32, kOld, kOld * 2, kFiletime, eow.io) == BlExpandResult::kNotExpandable);
        assert(eow.writes == 0 && eow.setSizeCalls == 0);

        Image enc; buildVolume(enc, vmk, /*state=*/2);                  // switching encryption
        assert(blExpandVolume(vmk, 32, kOld, kOld * 2, kFiletime, enc.io) == BlExpandResult::kNotExpandable);

        Image badCrc; buildVolume(badCrc, vmk);                          // every copy corrupted -> nothing to trust
        for (int i = 0; i < 3; i++) badCrc.data[kOffsets[i] + 0x100] ^= 0xFF;
        assert(blExpandVolume(vmk, 32, kOld, kOld * 2, kFiletime, badCrc.io) == BlExpandResult::kInvalidMetadata);

        Image badSeal; buildVolume(badSeal, vmk);                        // block changed but CRC patched up: seal catches it
        for (int i = 0; i < 3; i++) {
            badSeal.data[kOffsets[i] + 0x100] ^= 0xFF;
            wr32(&badSeal.data[kOffsets[i] + kBlock + 4], blexp::crc32(&badSeal.data[kOffsets[i]], kBlock));
        }
        assert(blExpandVolume(vmk, 32, kOld, kOld * 2, kFiletime, badSeal.io) == BlExpandResult::kInvalidMetadata);

        Image meta; buildVolume(meta, vmk);                              // a copy outside the volume -> refuse
        wr64(&meta.data[0xB0], kOld + 4096);
        assert(blExpandVolume(vmk, 32, kOld, kOld * 2, kFiletime, meta.io) == BlExpandResult::kInvalidMetadata);
    }

    // 4. One torn (CRC-failing) copy is tolerated and repaired; the others are rewritten from a verified copy.
    {
        Image img; buildVolume(img, vmk);
        img.data[kOffsets[0] + 0x120] ^= 0x55;                           // tear copy 0
        assert(blExpandVolume(vmk, 32, kOld, kOld * 2, kFiletime, img.io) == BlExpandResult::kOk);
        for (int i = 0; i < 3; i++) assert(checkIndependently(img, i, vmk, kOld * 2, 42));
    }

    // 5. A failed write is reported, and the first copy (written last) still describes the old, valid volume.
    {
        Image img; buildVolume(img, vmk); img.failWriteAt = 1;          // third copy written fine, second fails
        assert(blExpandVolume(vmk, 32, kOld, kOld * 2, kFiletime, img.io) == BlExpandResult::kIoError);
        uint64_t sz = 0; uint32_t ss = 0;
        assert(blReadEncryptedVolumeSize(img.io, img.data.size(), sz, ss) == BlExpandResult::kOk);
        assert(sz == kOld);                                              // readers still see the old size
        img.failWriteAt = -1; img.writes = 0;                            // retry succeeds and heals the mix
        assert(blExpandVolume(vmk, 32, img.data.size(), kOld * 2, kFiletime + 5, img.io) == BlExpandResult::kOk);
        for (int i = 0; i < 3; i++) assert(checkIndependently(img, i, vmk, kOld * 2, 42));
    }

    // 6. 4096-byte sectors round the target down to 4096.
    {
        Image img; buildVolume(img, vmk); wr16(&img.data[0x0B], 4096);
        assert(blExpandVolume(vmk, 32, kOld, kOld + 10000, kFiletime, img.io) == BlExpandResult::kOk);
        assert(rd64(&img.data[kOffsets[0] + 16]) == kOld + 8192);
    }

    std::puts("bl_expand_test: OK");
    return 0;
}
