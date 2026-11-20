// Host-side test for containers/vc_header_validate.h (upstream's header acceptance rules).
//   g++ -std=c++17 -I<cpp> -I<cpp>/containers containers/test/vc_header_validate_test.cpp containers/container_header.cpp -o t && ./t
#include "../vc_header_validate.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <initializer_list>

uint32_t container_crc32(const unsigned char* d, size_t n) {   // standard CRC-32 (zlib)
    uint32_t c = 0xFFFFFFFFu;
    for (size_t i = 0; i < n; i++) { c ^= d[i]; for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320u & (0u - (c & 1u))); }
    return ~c;
}
static void put16(unsigned char* b, int off, unsigned v) { b[off] = v >> 8; b[off + 1] = v & 0xFF; }
static void put32(unsigned char* b, int off, uint32_t v) { for (int i = 0; i < 4; i++) b[off + i] = (v >> (24 - 8 * i)) & 0xFF; }
static void put64(unsigned char* b, int off, uint64_t v) { for (int i = 0; i < 8; i++) b[off + i] = (v >> (56 - 8 * i)) & 0xFF; }

static void make(unsigned char* b, unsigned version, unsigned required, uint32_t sector, uint64_t hidden = 0) {
    memset(b, 0, VC_HEADER_BODY_SIZE);
    memcpy(b, "VERA", 4);
    put16(b, VC_HDR_OFF_VERSION, version);
    put16(b, VC_HDR_OFF_REQUIRED_VERSION, required);
    put64(b, VC_HDR_OFF_HIDDEN_VOL_SIZE, hidden);
    put64(b, VC_HDR_OFF_VOLUME_SIZE, 786432);
    put64(b, VC_HDR_OFF_KEY_SCOPE_START, 131072);
    put64(b, VC_HDR_OFF_KEY_SCOPE_SIZE, 786432);
    put32(b, VC_HDR_OFF_SECTOR_SIZE, sector);
    for (int i = 0; i < 64; i++) b[VC_KEY_OFFSET_MASTER + i] = (unsigned char)(i * 7 + 1);
    put32(b, VC_HDR_OFF_KEY_CRC, container_crc32(b + VC_KEY_OFFSET_MASTER, VC_HDR_KEY_CRC_COVERAGE_LEN));
    put32(b, VC_HDR_OFF_HEADER_CRC, container_crc32(b, VC_HDR_CRC_COVERAGE_LEN));
}

int main() {
    unsigned char b[VC_HEADER_BODY_SIZE];
    ParsedHeaderFields f;
    make(b, 5, 0x010b, 512);
    assert(vcAcceptDecryptedHeader(b, &f) && f.sectorSize == 512 && f.volumeSize == 786432 &&
           f.encryptedAreaStart == 131072 && !f.isHiddenVolume());
    // 1024/2048/4096-byte sectors are valid, other values are not
    for (uint32_t s : {512u, 1024u, 2048u, 4096u}) { make(b, 5, 0x010b, s); assert(vcAcceptDecryptedHeader(b, &f) && f.sectorSize == s); }
    for (uint32_t s : {0u, 256u, 511u, 513u, 1000u, 4097u, 8192u}) { make(b, 5, 0x010b, s); assert(!vcAcceptDecryptedHeader(b, &f)); }
    // hidden volume header
    make(b, 5, 0x010b, 512, 524288); assert(vcAcceptDecryptedHeader(b, &f) && f.isHiddenVolume());
    // format version: 1..5 accepted, 0 and >5 refused (upstream: HigherVersionRequired)
    make(b, 0, 0x010b, 512); assert(!vcAcceptDecryptedHeader(b, &f));
    make(b, 6, 0x010b, 512); assert(!vcAcceptDecryptedHeader(b, &f));
    // formats older than 5 have no sector-size field (always 512) -- whatever sits there is ignored
    make(b, 4, 0x010b, 777); assert(vcAcceptDecryptedHeader(b, &f) && f.sectorSize == 512);
    make(b, 2, 0x010b, 777); assert(vcAcceptDecryptedHeader(b, &f) && f.sectorSize == 512);
    // the header CRC only exists from format version 4 on
    make(b, 3, 0x010b, 512); b[VC_HDR_OFF_HEADER_CRC] ^= 0xFF; assert(vcAcceptDecryptedHeader(b, &f));
    make(b, 5, 0x010b, 512); b[VC_HDR_OFF_HEADER_CRC] ^= 0xFF; assert(!vcAcceptDecryptedHeader(b, &f));
    // key-area CRC always has to match
    make(b, 5, 0x010b, 512); b[VC_KEY_OFFSET_MASTER + 3] ^= 1; assert(!vcAcceptDecryptedHeader(b, &f));
    // minimum program version above ours is refused, equal/lower accepted
    make(b, 5, VC_PROGRAM_VERSION, 512); assert(vcAcceptDecryptedHeader(b, &f));
    make(b, 5, VC_PROGRAM_VERSION + 1, 512); assert(!vcAcceptDecryptedHeader(b, &f));
    // magic
    make(b, 5, 0x010b, 512); b[0] = 'T'; assert(!vcAcceptDecryptedHeader(b, &f));
    printf("vc_header_validate_test: all assertions passed\n");
    return 0;
}
