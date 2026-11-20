// Host-side test for crypto/password_encoding.h:
//   g++ -std=c++17 -I<cpp> crypto/test/password_encoding_test.cpp -o password_encoding_test && ./password_encoding_test
#include "../password_encoding.h"
#include <cassert>
#include <cstdio>
#include <cstring>

static size_t legacy(const char* s, unsigned char* out, size_t cap) {
    return vcLegacyPasswordBytes(reinterpret_cast<const unsigned char*>(s), strlen(s), out, cap);
}

int main() {
    unsigned char out[256];
    // nothing to retry: ASCII, Latin, CJK within the BMP (identical in standard and modified UTF-8)
    assert(legacy("correct horse battery staple", out, sizeof out) == 0);
    assert(legacy("p\xC3\xA4ssw\xC3\xB6rd", out, sizeof out) == 0);            // "passwörd" (2-byte sequences)
    assert(legacy("\xE6\xBC\xA2\xE5\xAD\x97", out, sizeof out) == 0);          // BMP CJK (3-byte sequences)
    // U+1F600 (F0 9F 98 80) -> surrogates D83D DE00 -> ED A0 BD  ED B8 80
    const unsigned char smiley[] = {0xED, 0xA0, 0xBD, 0xED, 0xB8, 0x80};
    size_t n = legacy("\xF0\x9F\x98\x80", out, sizeof out);
    assert(n == 6 && memcmp(out, smiley, 6) == 0);
    // mixed: "a<U+1F600>b" keeps the surrounding bytes
    n = legacy("a\xF0\x9F\x98\x80" "b", out, sizeof out);
    assert(n == 8 && out[0] == 'a' && memcmp(out + 1, smiley, 6) == 0 && out[7] == 'b');
    // U+10000 (F0 90 80 80) -> D800 DC00 -> ED A0 80  ED B0 80 ; U+10FFFF -> DBFF DFFF -> ED AF BF ED BF BF
    const unsigned char first[] = {0xED, 0xA0, 0x80, 0xED, 0xB0, 0x80};
    n = legacy("\xF0\x90\x80\x80", out, sizeof out);
    assert(n == 6 && memcmp(out, first, 6) == 0);
    const unsigned char last[] = {0xED, 0xAF, 0xBF, 0xED, 0xBF, 0xBF};
    n = legacy("\xF4\x8F\xBF\xBF", out, sizeof out);
    assert(n == 6 && memcmp(out, last, 6) == 0);
    // truncated like the old 128-byte limit: only the first [cap] bytes are produced
    n = legacy("\xF0\x9F\x98\x80\xF0\x9F\x98\x80", out, 8);
    assert(n == 8 && memcmp(out, smiley, 6) == 0 && out[6] == 0xED && out[7] == 0xA0);
    // a stray lead byte without continuation bytes is not a 4-byte sequence: nothing to convert
    assert(legacy("abc\xF0" "x", out, sizeof out) == 0);
    printf("password_encoding_test: all assertions passed\n");
    return 0;
}
