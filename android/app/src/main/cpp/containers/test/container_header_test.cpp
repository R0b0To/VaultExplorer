#include "../container_header.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <vector>

namespace {
std::vector<unsigned char> makeSector(unsigned char fill = 0) {
    return std::vector<unsigned char>(512, fill);
}

std::vector<unsigned char> makeFatLikeSector() {
    auto sector = makeSector();
    sector[0] = 0xEB;
    sector[1] = 0x3C;
    sector[2] = 0x90;
    sector[11] = 0x00;
    sector[12] = 0x02; // 512 bytes per sector (valid)
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

void testValidFatSectorAccepted() {
    auto sector = makeFatLikeSector();
    assert(isValidBootSector(sector.data()));
}

void testValidExfatSectorAccepted() {
    auto sector = makeExfatSector();
    assert(isValidBootSector(sector.data()));
}

void test4kBytesPerSectorIsAccepted() {
    auto sector = makeFatLikeSector();
    sector[11] = 0x00;
    sector[12] = 0x10; // 4096 bytes per sector (valid)
    assert(isValidBootSector(sector.data()));
}

void testE9JumpOpcodeAcceptedWhenBytesPerSectorIs512() {
    auto sector = makeSector();
    sector[0] = 0xE9;
    sector[11] = 0x00;
    sector[12] = 0x02;
    sector[510] = 0x55;
    sector[511] = 0xAA;
    assert(isValidBootSector(sector.data()));
}

void testMissingSignatureIsRejectedEvenWithOtherwiseValidFields() {
    auto sector = makeFatLikeSector();
    sector[511] = 0x00;
    assert(!isValidBootSector(sector.data()));
}

void testSingleFlippedSignatureByteIsRejected() {
    auto sector = makeFatLikeSector();
    sector[510] = 0x54;
    assert(!isValidBootSector(sector.data()));
}

void testAllZeroSectorIsRejected() {
    auto sector = makeSector(0x00);
    assert(!isValidBootSector(sector.data()));
}

void testAllOnesSectorIsRejected() {
    auto sector = makeSector(0xFF);
    assert(!isValidBootSector(sector.data()));
}

void testSignatureAloneWithoutJumpOpcodeIsRejected() {
    auto sector = makeSector();
    sector[0] = 0x12;
    sector[1] = 0x34;
    sector[2] = 0x56;
    sector[510] = 0x55;
    sector[511] = 0xAA;
    assert(!isValidBootSector(sector.data()));
}

void testExfatOemStringCorruptedByOneByteIsRejectedAsExfatButStillFallsThroughToJumpCheck() {
    auto sector = makeExfatSector();
    sector[3] = 'X';
    sector[11] = 0; sector[12] = 0;
    assert(!isValidBootSector(sector.data()));
}

void testFatLikeSectorWithWrongBytesPerSectorIsRejected() {
    auto sector = makeFatLikeSector();
    sector[11] = 0x00;
    sector[12] = 0x01; // 256 bytes per sector (invalid)
    assert(!isValidBootSector(sector.data()));
}

void testBytesPerSectorIsReadLittleEndianNotBigEndian() {
    auto sector = makeFatLikeSector();
    sector[11] = 0x02;
    sector[12] = 0x00; // 2 bytes per sector (invalid)
    assert(!isValidBootSector(sector.data()));
}

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
    unsigned char data[16] = {
        0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
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
    unsigned char data[4] = {0x00, 0x00, 0x00, 0x01};
    assert(readHeaderBE32(data, 0) == 1U);
    assert(readHeaderBE32(data, 0) != 0x01000000U);
}
}

int main() {
    testValidFatSectorAccepted();
    testValidExfatSectorAccepted();
    test4kBytesPerSectorIsAccepted();
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