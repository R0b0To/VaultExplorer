// Host-side test for jni_password_utf8.h (Java String -> the UTF-8 bytes VeraCrypt hashes):
//   g++ -std=c++17 -Ijni/test/mock -Ijni jni/test/jni_password_utf8_test.cpp -lmbedcrypto -o t && ./t
#include "jni_password_utf8.h"
#include <cassert>
#include <cstdio>
#include <vector>

static std::string conv(std::vector<jchar> u) {
    _jstring js{u.data(), static_cast<jsize>(u.size())};
    JNIEnv_ env;
    char* r = vcGetPasswordUtf8(&env, &js);
    assert(r != nullptr);
    std::string out(r);
    vcReleasePasswordUtf8(r);
    return out;
}

int main() {
    assert(conv({'a', 'b', 'c'}) == "abc");
    assert(conv({0x00E4, 0x6F22}) == "\xC3\xA4\xE6\xBC\xA2");                    // ä, 漢 (BMP: same as modified UTF-8)
    assert(conv({'a', 0xD83D, 0xDE00, 'b'}) == "a\xF0\x9F\x98\x80" "b");          // U+1F600 -> ONE 4-byte sequence (JNI would give 6 bytes)
    assert(conv({0xD800, 0xDC00}) == "\xF0\x90\x80\x80");                         // U+10000
    assert(conv({0xDBFF, 0xDFFF}) == "\xF4\x8F\xBF\xBF");                         // U+10FFFF
    assert(conv({0xD83D}) == "\xEF\xBF\xBD");                                     // lone high surrogate -> U+FFFD
    assert(conv({0xDE00, 'x'}) == "\xEF\xBF\xBD" "x");                            // lone low surrogate
    assert(conv({}) == "");
    JNIEnv_ env;
    assert(vcGetPasswordUtf8(&env, nullptr) == nullptr);
    vcReleasePasswordUtf8(nullptr);
    printf("jni_password_utf8_test: all assertions passed\n");
    return 0;
}
