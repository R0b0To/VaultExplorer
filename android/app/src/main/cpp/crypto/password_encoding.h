#pragma once
// Password byte encoding, backwards-compatibility side.
//
// VeraCrypt hashes the password as standard UTF-8. Builds of this app before the
// JNI encoding fix (jni/jni_bridge_common.h: vcGetPasswordUtf8) obtained the bytes
// from env->GetStringUTFChars(), i.e. JNI "modified UTF-8": every supplementary-
// plane character (emoji, rare CJK, ...) was written as TWO 3-byte surrogate
// sequences instead of one 4-byte sequence. Passwords made only of BMP characters
// are identical in both encodings, so only a password containing such a character
// ever produced a volume that desktop VeraCrypt cannot open.
//
// To keep those volumes openable, a failed header trial is retried once with the
// legacy bytes (see deriveAndValidateHeader). Changing the password afterwards
// re-encrypts the header with the standard encoding.
#include <cstddef>
#include <cstdint>
#include <cstring>

// Converts standard UTF-8 [in] to the legacy modified-UTF-8 bytes, truncated to
// [outCap] bytes exactly like the old 128-byte password limit did. Returns the
// number of bytes written, or 0 when there is nothing to retry (no 4-byte
// sequence in [in], or [in] is implausibly long).
inline size_t vcLegacyPasswordBytes(const unsigned char* in, size_t inLen,
                                    unsigned char* out, size_t outCap) {
    if (in == nullptr || out == nullptr || inLen == 0 || inLen > 256) return 0;
    bool has4 = false;
    for (size_t i = 0; i < inLen; i++) {
        if (in[i] >= 0xF0 && in[i] <= 0xF4) { has4 = true; break; }
    }
    if (!has4) return 0;

    unsigned char tmp[512];   // 4 -> 6 bytes at worst: 1.5 * 256 = 384
    size_t n = 0;
    bool converted = false;
    for (size_t i = 0; i < inLen;) {
        const unsigned char b = in[i];
        if (b >= 0xF0 && b <= 0xF4 && i + 3 < inLen &&
            (in[i + 1] & 0xC0) == 0x80 && (in[i + 2] & 0xC0) == 0x80 && (in[i + 3] & 0xC0) == 0x80) {
            const uint32_t cp = (static_cast<uint32_t>(b & 0x07) << 18) |
                                (static_cast<uint32_t>(in[i + 1] & 0x3F) << 12) |
                                (static_cast<uint32_t>(in[i + 2] & 0x3F) << 6) |
                                 static_cast<uint32_t>(in[i + 3] & 0x3F);
            if (cp >= 0x10000 && cp <= 0x10FFFF) {
                const uint32_t c = cp - 0x10000;
                const uint32_t units[2] = { 0xD800u | (c >> 10), 0xDC00u | (c & 0x3FF) };
                for (uint32_t u : units) {
                    tmp[n++] = static_cast<unsigned char>(0xE0 | (u >> 12));
                    tmp[n++] = static_cast<unsigned char>(0x80 | ((u >> 6) & 0x3F));
                    tmp[n++] = static_cast<unsigned char>(0x80 | (u & 0x3F));
                }
                i += 4;
                converted = true;
                continue;
            }
        }
        tmp[n++] = b;
        i++;
    }
    if (!converted) return 0;
    const size_t w = n < outCap ? n : outCap;
    std::memcpy(out, tmp, w);
    std::memset(tmp, 0, sizeof(tmp));
    return w;
}
