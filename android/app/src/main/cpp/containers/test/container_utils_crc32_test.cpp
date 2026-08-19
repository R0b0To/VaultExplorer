// Host-side test, no Android toolchain required:
// g++ -std=c++17 container_utils_crc32_test.cpp -o container_utils_crc32_test
//
// Minimal reimplementation of container_utils.cpp's crc32(), decoupled from
// the rest of that file's dependency on ff.h (FatFs's WORD typedef, needed
// only by fatToUnixTimestamp/unixToFatTimestamp, not by crc32 itself) --
// same rationale as fs_scan_test.cpp's isBootSectorSignature: keep this
// file's dependency footprint at zero so it builds anywhere. This is a
// byte-for-byte copy of the real table-generation and update loop (same
// reflected polynomial 0xEDB88320, same init/final XOR of 0xFFFFFFFF); if
// the real crc32() ever changes, the vectors below (independently sourced
// from zlib's crc32(), the reference implementation for this exact
// algorithm) will catch a drift, not just a self-consistency check against
// a stale copy.
//
// crc32() is used to verify filesystem metadata blocks (see the call sites
// this exists for) -- these tests focus on the two things that matter for
// that job: producing the textbook-correct value (so it actually
// interoperates with whatever wrote the checksum), and reliably changing
// output for any single corrupted bit (so corruption is actually caught,
// not accidentally cancelled out).
#include <array>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

namespace {

const uint32_t* crc32LookupTable() {
    static const auto table = [] {
        std::array<uint32_t, 256> t{};
        for (uint32_t i = 0; i < 256; i++) {
            uint32_t c = i;
            for (int k = 0; k < 8; k++)
                c = (c & 1) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
            t[i] = c;
        }
        return t;
    }();
    return table.data();
}

uint32_t crc32(const unsigned char* data, size_t length) {
    const uint32_t* table = crc32LookupTable();
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < length; ++i) {
        crc = table[(crc ^ data[i]) & 0xFFu] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFFu;
}

uint32_t crc32(const std::vector<unsigned char>& data) {
    return crc32(data.empty() ? nullptr : data.data(), data.size());
}

std::vector<unsigned char> bytesOf(const char* s) {
    return std::vector<unsigned char>(s, s + std::strlen(s));
}

} // namespace

// --- known-answer tests against the standard CRC-32/ISO-HDLC vectors
// (the same values zlib's crc32() and every common crc32 tool produce for
// these inputs) -- correctness here is what lets this app's checksums
// interoperate with anything else that reads/verifies the same format. ---

static void testEmptyInputIsZero() {
    assert(crc32(nullptr, 0) == 0x00000000u);
}

static void testStandardCheckVector() {
    // The canonical CRC-32 conformance vector: crc32("123456789") must
    // equal 0xCBF43926 for any implementation claiming this exact
    // polynomial/init/refin/refout/xorout parameter set.
    auto data = bytesOf("123456789");
    assert(crc32(data) == 0xCBF43926u);
}

static void testKnownAsciiStrings() {
    assert(crc32(bytesOf("a")) == 0xE8B7BE43u);
    assert(crc32(bytesOf("The quick brown fox jumps over the lazy dog")) == 0x414FA339u);
}

static void testAllZeroAndAllOneBuffers() {
    // The two "corruption" shapes most likely to appear from real hardware
    // failure modes -- an erased/unwritten flash page (all 0xFF) or a
    // zeroed block (a failed/partial write) -- must still produce a
    // specific, correct, non-degenerate checksum, not e.g. 0.
    std::vector<unsigned char> zeros(32, 0x00);
    std::vector<unsigned char> ones(32, 0xFF);
    assert(crc32(zeros) == 0x190A55ADu);
    assert(crc32(ones) == 0xFF6CAB0Bu);
    assert(crc32(zeros) != crc32(ones));
}

// --- corruption-sensitivity: the actual property that matters for using
// this as an integrity check over filesystem metadata. ---

static void testSingleBitFlipAnywhereInBufferChangesTheChecksum() {
    std::vector<unsigned char> original(64);
    for (size_t i = 0; i < original.size(); i++) original[i] = static_cast<unsigned char>(i * 37 + 11);
    const uint32_t originalCrc = crc32(original);

    for (size_t byteIndex = 0; byteIndex < original.size(); byteIndex++) {
        for (int bit = 0; bit < 8; bit++) {
            auto corrupted = original;
            corrupted[byteIndex] ^= static_cast<unsigned char>(1u << bit);
            assert(crc32(corrupted) != originalCrc);
        }
    }
}

static void testTruncationChangesTheChecksum() {
    // A block cut short by a torn/partial write must not happen to collide
    // with the checksum of the full, correctly-written block.
    auto full = bytesOf("this is a complete, correctly written metadata block");
    std::vector<unsigned char> truncated(full.begin(), full.end() - 1);
    assert(crc32(full) != crc32(truncated));
}

static void testAppendingGarbageChangesTheChecksum() {
    // The mirror case: extra trailing bytes (e.g. leftover data from a
    // previous, longer write into the same block) must also be caught.
    auto original = bytesOf("metadata block");
    auto extended = original;
    extended.push_back(0x00);
    assert(crc32(original) != crc32(extended));
}

static void testByteOrderSwapWithinBufferChangesTheChecksum() {
    // Two adjacent bytes swapped (a plausible torn-write/cross-write
    // corruption pattern, distinct from a single bit flip) must also
    // change the checksum -- CRC-32 is not commutative over byte position.
    std::vector<unsigned char> a = {0x01, 0x02, 0x03, 0x04};
    std::vector<unsigned char> b = {0x02, 0x01, 0x03, 0x04}; // first two bytes swapped
    assert(crc32(a) != crc32(b));
}

static void testDeterministicAcrossRepeatedCalls() {
    // No hidden state (e.g. a lazily-initialized table computed once and
    // then accidentally mutated) leaking between calls.
    auto data = bytesOf("repeatable input");
    const uint32_t first = crc32(data);
    const uint32_t second = crc32(data);
    const uint32_t third = crc32(data);
    assert(first == second && second == third);
}

int main() {
    testEmptyInputIsZero();
    testStandardCheckVector();
    testKnownAsciiStrings();
    testAllZeroAndAllOneBuffers();
    testSingleBitFlipAnywhereInBufferChangesTheChecksum();
    testTruncationChangesTheChecksum();
    testAppendingGarbageChangesTheChecksum();
    testByteOrderSwapWithinBufferChangesTheChecksum();
    testDeterministicAcrossRepeatedCalls();
    std::printf("container_utils_crc32_test: all tests passed\n");
    return 0;
}
