#pragma once
#include <jni.h>
#include <cstdint>
#include <cstring>
#include <string>
#include "mbedtls/platform_util.h"

// ── Password text -> bytes, exactly as VeraCrypt (and cryptsetup) hash it ────
// JNI's GetStringUTFChars() returns *modified* UTF-8: every supplementary-plane
// character (emoji, rare CJK, ...) comes out as two separate 3-byte surrogate
// sequences (CESU-8) instead of one 4-byte UTF-8 sequence. Desktop VeraCrypt
// hashes standard UTF-8, so a password containing such a character would not
// unlock a volume made on desktop (nor the other way round). Anything that
// feeds a password into a VeraCrypt/LUKS/BitLocker key derivation must come
// through here instead. BMP-only passwords are byte-identical either way.
// Lone surrogates become U+FFFD (what WideCharToMultiByte(CP_UTF8) yields).
// Returns a NUL-terminated heap copy (nullptr for a null jstring); release it
// with vcReleasePasswordUtf8(), which wipes it.
inline char* vcGetPasswordUtf8(JNIEnv* env, jstring s) {
    if (s == nullptr) return nullptr;
    const jsize n = env->GetStringLength(s);
    if (n == 0) {                       // empty password: valid, and nothing to convert
        char* empty = new char[1];
        empty[0] = '\0';
        return empty;
    }
    const jchar* u = env->GetStringChars(s, nullptr);
    if (u == nullptr) return nullptr;
    std::string out;
    out.reserve(static_cast<size_t>(n) * 3 + 1);
    for (jsize i = 0; i < n; i++) {
        uint32_t cp = u[i];
        if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < n && u[i + 1] >= 0xDC00 && u[i + 1] <= 0xDFFF) {
            cp = 0x10000 + ((cp - 0xD800) << 10) + (static_cast<uint32_t>(u[i + 1]) - 0xDC00);
            i++;
        } else if (cp >= 0xD800 && cp <= 0xDFFF) {
            cp = 0xFFFD;
        }
        if (cp < 0x80) {
            out.push_back(static_cast<char>(cp));
        } else if (cp < 0x800) {
            out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else if (cp < 0x10000) {
            out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else {
            out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        }
    }
    env->ReleaseStringChars(s, u);
    char* r = new char[out.size() + 1];
    std::memcpy(r, out.data(), out.size());
    r[out.size()] = '\0';
    if (!out.empty()) mbedtls_platform_zeroize(&out[0], out.size());
    return r;
}

inline void vcReleasePasswordUtf8(const char* p) {
    if (p == nullptr) return;
    mbedtls_platform_zeroize(const_cast<char*>(p), std::strlen(p));
    delete[] p;
}
