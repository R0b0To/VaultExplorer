// Host-side test, no Android toolchain required:
//   g++ -std=c++17 utf16le_password_test.cpp -o utf16le_password_test && ./utf16le_password_test
//
// Regression coverage for utf16le_from_utf8() (crypto/utf16le_password.h),
// the shared implementation behind dislocker/encoding.c's toutf16() and
// crypto/single_file_crypto.cpp's utf8ToUtf16Le(). The truncated-sequence
// case here is the exact shape of the OOB read this function's
// predecessor (toutf16(), before it was hardened) had.
#include "../utf16le_password.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <vector>

// Runs the conversion with an output buffer sized to the documented
// worst case, then returns exactly the bytes written (so tests can
// compare without caring about unused tail capacity).
static std::vector<uint8_t> convert(const std::vector<uint8_t> &in) {
    std::vector<uint8_t> out(utf16le_password_max_output_size(in.size()));
    const size_t written = utf16le_from_utf8(in.data(), in.size(), out.data(), out.size());
    out.resize(written);
    return out;
}

static std::vector<uint8_t> u16le(std::initializer_list<uint16_t> units) {
    std::vector<uint8_t> out;
    for (uint16_t u : units) {
        out.push_back((uint8_t)(u & 0xFF));
        out.push_back((uint8_t)((u >> 8) & 0xFF));
    }
    return out;
}

int main() {
    // Empty input -> empty output, no crash.
    {
        const std::vector<uint8_t> in;
        assert(convert(in).empty());
    }

    // Plain ASCII password.
    {
        const std::vector<uint8_t> in = {'h', 'u', 'n', 't', 'e', 'r', '2'};
        const auto expected = u16le({'h', 'u', 'n', 't', 'e', 'r', '2'});
        assert(convert(in) == expected);
    }

    // Multi-byte (2-byte and 3-byte) sequences: e.g. "café€" —
    // U+0063 U+0061 U+0066 U+00E9 U+20AC.
    {
        const std::vector<uint8_t> in = {
            'c', 'a', 'f',
            0xC3, 0xA9,             // U+00E9 'é' (2-byte)
            0xE2, 0x82, 0xAC        // U+20AC '€' (3-byte)
        };
        const auto expected = u16le({'c', 'a', 'f', 0x00E9, 0x20AC});
        assert(convert(in) == expected);
    }

    // The original bug: a truncated multi-byte sequence at the very end
    // of the buffer (a lone 3-byte lead with only 1 continuation byte
    // following, then nothing). Must not read past `in_len`, and must
    // return only the bytes that decoded cleanly before the truncation.
    {
        const std::vector<uint8_t> in = {'p', 'w', 0xE2, 0x82}; // truncated 3-byte seq
        const auto expected = u16le({'p', 'w'});
        assert(convert(in) == expected);
    }

    // Truncated 2-byte sequence as the very last byte.
    {
        const std::vector<uint8_t> in = {'x', 0xC3};
        const auto expected = u16le({'x'});
        assert(convert(in) == expected);
    }

    // Truncated 4-byte sequence missing all continuation bytes.
    {
        const std::vector<uint8_t> in = {0xF0};
        assert(convert(in).empty());
    }

    // Invalid continuation byte (second byte isn't 10xxxxxx): the whole
    // malformed sequence is dropped, not decoded from garbage bits.
    {
        const std::vector<uint8_t> in = {'a', 0xC3, 0x41, 'b'}; // 0x41='A', not a continuation byte
        const auto expected = u16le({'a', 'b'});
        assert(convert(in) == expected);
    }

    // Invalid lead byte (0xFF is never valid UTF-8) is skipped on its own.
    {
        const std::vector<uint8_t> in = {'a', 0xFF, 'b'};
        const auto expected = u16le({'a', 'b'});
        assert(convert(in) == expected);
    }

    // Astral character (emoji), as it actually arrives from JNI's
    // modified UTF-8 / CESU-8: pre-split into a surrogate pair, each half
    // encoded as its own 3-byte sequence -- U+1F600 (😀) as ED A0 BD ED
    // B8 80, never as a real 4-byte sequence. Must decode to the correct
    // UTF-16LE surrogate pair (0xD83D, 0xDE00). This is the case
    // documented at length in utf16le_password.h: don't "fix" this into
    // rejecting encoded surrogates, or this assertion is what breaks.
    {
        const std::vector<uint8_t> in = {'p', 'w', 0xED, 0xA0, 0xBD, 0xED, 0xB8, 0x80};
        const auto expected = u16le({'p', 'w', 0xD83D, 0xDE00});
        assert(convert(in) == expected);
    }

    // A real (non-modified) 4-byte UTF-8 sequence for the same character
    // also decodes correctly, via the 4-byte-lead branch, for callers
    // that ever do feed real UTF-8 -- U+1F600 as F0 9F 98 80.
    {
        const std::vector<uint8_t> in = {0xF0, 0x9F, 0x98, 0x80};
        const auto expected = u16le({0xD83D, 0xDE00});
        assert(convert(in) == expected);
    }

    // Output-capacity ceiling is respected even if a caller under-sizes
    // the buffer: with out_cap forced to 2 bytes, only the first code
    // unit is written, not a partial/overflowing one.
    {
        const std::vector<uint8_t> in = {'a', 'b', 'c'};
        std::vector<uint8_t> out(2, 0xAA);
        const size_t written = utf16le_from_utf8(in.data(), in.size(), out.data(), out.size());
        assert(written == 2);
        assert(out[0] == 'a' && out[1] == 0);
    }

    // Null in/out pointers return 0 rather than crashing.
    {
        uint8_t dummy[4];
        assert(utf16le_from_utf8(nullptr, 3, dummy, sizeof(dummy)) == 0);
        assert(utf16le_from_utf8(dummy, 3, nullptr, sizeof(dummy)) == 0);
    }

    printf("utf16le_password_test: all assertions passed\n");
    return 0;
}
