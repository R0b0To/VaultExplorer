// Host-side test, no Android toolchain required:
// g++ -std=c++17 container_header_test.cpp ../container_header.cpp -o container_header_test
//
// isValidBootSector/readHeaderBE64/readHeaderBE32 are the first line of
// defense against treating a corrupted or foreign 512-byte sector as a
// legitimate filesystem/container header. These tests focus on exactly the
// corruption cases that matter in practice: a single flipped signature
// byte, a truncated-looking sector that's actually fine, and adjacent
// fields in a decrypted header never bleeding into each other.
#include "../container_header.h"

#include <cassert>
#include <cstdio>
#include <cstring>
#include <vector>

namespace {

std::vector<unsigned char> makeSector(unsigned char fill = 0) {
    return std::vector<unsigned char>(512, fill);
}

// A structurally valid FAT/NTFS-style boot sector: 0xEB jump opcode,
// bytesPerSector = 512 at offset 11-12 (little-endian), 0x55AA signature.
std::vector<unsigned char> makeFatLikeSector() {
    auto sector = makeSector();
    sector[0] = 0xEB;
    sector[1] = 0x3C;
    sector[2] = 0x90;
    sector[11] = 0x00; // bytesPerSector low byte
    sector[12] = 0x02; // bytesPerSector high byte -> 0x0200 = 512
    sector[510] = 0x55;
    sector[511] = 0xAA;
    return sector;
}

std::vector<unsigned char> makeExfatSector() {
    auto sector = makeSector();
    sector[0] = 0xEB;
    sector[1] = 0x76;
    sector[2] = 0x90;
    std::memcpy(&sector[3], "EXFAT   ", 8);
    sector[510] = 0x55;
    sector[511] = 0xAA;
    return sector;
}

// --- isValidBootSector(): the 0x55AA signature is necessary but not
// sufficient -- a corrupted sector can easily still carry a correct
// signature by chance (or a foreign/non-filesystem 512 bytes that happens
// to end that way), so the boot-code-opcode/OEM-name checks matter too. ---

void testValidFatSectorAccepted() {
    auto sector = makeFatLikeSector();
    assert(isValidBootSector(sector.data()));
}

void testValidExfatSectorAccepted() {
    auto sector = makeExfatSector();
    assert(isValidBootSector(sector.data()));
}

void testE9JumpOpcodeAcceptedWhenBytesPerSectorIs512() {
    auto sector = makeSector();
    sector[0] = 0xE9; // the other legal short-jump opcode besides 0xEB
    sector[11] = 0x00;
    sector[12] = 0x02;
    sector[510] = 0x55;
    sector[511] = 0xAA;
    assert(isValidBootSector(sector.data()));
}

void testMissingSignatureIsRejectedEvenWithOtherwiseValidFields() {
    auto sector = makeFatLikeSector();
    sector[511] = 0x00; // corrupt just the last signature byte
    assert(!isValidBootSector(sector.data()));
}

void testSingleFlippedSignatureByteIsRejected() {
    auto sector = makeFatLikeSector();
    sector[510] = 0x54; // one bit off from 0x55
    assert(!isValidBootSector(sector.data()));
}

void testAllZeroSectorIsRejected() {
    // The single most common "corruption" shape in practice: a block that
    // was never written, or was zeroed out by a failed/partial write.
    auto sector = makeSector(0x00);
    assert(!isValidBootSector(sector.data()));
}

void testAllOnesSectorIsRejected() {
    // The other common failure shape: an erased-but-unwritten flash sector.
    auto sector = makeSector(0xFF);
    assert(!isValidBootSector(sector.data()));
}

void testSignatureAloneWithoutJumpOpcodeIsRejected() {
    // 0x55AA present, but byte 0 is neither 0xEB, 0xE9, nor the exFAT
    // pattern -- e.g. random/corrupted data that happens to end right.
    auto sector = makeSector();
    sector[0] = 0x12;
    sector[1] = 0x34;
    sector[2] = 0x56;
    sector[510] = 0x55;
    sector[511] = 0xAA;
    assert(!isValidBootSector(sector.data()));
}

void testExfatOemStringCorruptedByOneByteIsRejectedAsExfatButStillFallsThroughToJumpCheck() {
    // Corrupt one byte of "EXFAT   " -- the exFAT-specific branch must not
    // match, and since bytesPerSector at [11:12] is left as zero (0x0000,
    // not 512), the generic 0xEB fallback must not match either.
    auto sector = makeExfatSector();
    sector[3] = 'X'; // "XXFAT   " instead of "EXFAT   "
    sector[11] = 0; sector[12] = 0; // not 512
    assert(!isValidBootSector(sector.data()));
}

void testFatLikeSectorWithWrongBytesPerSectorIsRejected() {
    // 0xEB jump opcode present and signature present, but bytesPerSector
    // decodes to something other than 512 -- e.g. a 4K-sector image, which
    // this app's FAT reader (fixed at 512-byte sectors) can't safely trust
    // as a match for this check's purpose.
    auto sector = makeFatLikeSector();
    sector[11] = 0x00;
    sector[12] = 0x10; // 0x1000 = 4096, not 512
    assert(!isValidBootSector(sector.data()));
}

void testBytesPerSectorIsReadLittleEndianNotBigEndian() {
    // Regression guard: swapping the two bytes must NOT also read as 512
    // (0x0002 = 2, not 512) -- if this function ever accidentally read the
    // field big-endian, a corrupted-looking sector could slip through.
    auto sector = makeFatLikeSector();
    sector[11] = 0x02;
    sector[12] = 0x00; // swapped -> decodes to 2, not 512
    assert(!isValidBootSector(sector.data()));
}

// --- readHeaderBE64/readHeaderBE32: exact byte-order and offset behavior,
// since a decrypted VeraCrypt header's fields are adjacent and a wrong
// offset/width silently produces a plausible-looking but wrong number
// rather than an obvious crash. ---

void testReadHeaderBE64KnownValue() {
    unsigned char data[8] = {0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08};
    assert(readHeaderBE64(data, 0) == 0x0102030405060708ULL);
}

void testReadHeaderBE64AllZero() {
    unsigned char data[8] = {0, 0, 0, 0, 0, 0, 0, 0};
    assert(readHeaderBE64(data, 0) == 0ULL);
}

void testReadHeaderBE64AllOnes() {
    unsigned char data[8] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
    assert(readHeaderBE64(data, 0) == 0xFFFFFFFFFFFFFFFFULL);
}

void testReadHeaderBE64RespectsOffsetWithoutReadingNeighboringFieldBytes() {
    // Two adjacent 8-byte fields, as they'd appear in a real decrypted
    // header: the second field's read must never bleed a byte from the
    // first (a classic off-by-one that corrupts an adjacent field).
    unsigned char data[16] = {
        0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, // field 0
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, // field 1 = 1
    };
    assert(readHeaderBE64(data, 0) == 0xAAAAAAAAAAAAAAAAULL);
    assert(readHeaderBE64(data, 8) == 1ULL);
}

void testReadHeaderBE32KnownValue() {
    unsigned char data[4] = {0xDE, 0xAD, 0xBE, 0xEF};
    assert(readHeaderBE32(data, 0) == 0xDEADBEEFU);
}

void testReadHeaderBE32RespectsOffset() {
    unsigned char data[8] = {0x00, 0x00, 0x00, 0x00, 0x12, 0x34, 0x56, 0x78};
    assert(readHeaderBE32(data, 4) == 0x12345678U);
}

void testReadHeaderBE32DoesNotMisreadAsLittleEndian() {
    // A corrupted or wrong-endian header producer is exactly the case this
    // guards against -- if this ever silently read little-endian instead,
    // every downstream size/offset field would be wrong by a byte-swap,
    // not by a crash.
    unsigned char data[4] = {0x00, 0x00, 0x00, 0x01};
    assert(readHeaderBE32(data, 0) == 1U);       // big-endian: correct
    assert(readHeaderBE32(data, 0) != 0x01000000U); // NOT little-endian
}

} // namespace

int main() {
    testValidFatSectorAccepted();
    testValidExfatSectorAccepted();
    testE9JumpOpcodeAcceptedWhenBytesPerSectorIs512();
    testMissingSignatureIsRejectedEvenWithOtherwiseValidFields();
    testSingleFlippedSignatureByteIsRejected();
    testAllZeroSectorIsRejected();
    testAllOnesSectorIsRejected();
    testSignatureAloneWithoutJumpOpcodeIsRejected();
    testExfatOemStringCorruptedByOneByteIsRejectedAsExfatButStillFallsThroughToJumpCheck();
    testFatLikeSectorWithWrongBytesPerSectorIsRejected();
    testBytesPerSectorIsReadLittleEndianNotBigEndian();
    testReadHeaderBE64KnownValue();
    testReadHeaderBE64AllZero();
    testReadHeaderBE64AllOnes();
    testReadHeaderBE64RespectsOffsetWithoutReadingNeighboringFieldBytes();
    testReadHeaderBE32KnownValue();
    testReadHeaderBE32RespectsOffset();
    testReadHeaderBE32DoesNotMisreadAsLittleEndian();
    std::printf("container_header_test: all tests passed\n");
    return 0;
}
