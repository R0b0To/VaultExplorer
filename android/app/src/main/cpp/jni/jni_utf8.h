// jstring (UTF-16) -> UTF-8 std::string, for bridges that hand cleartext paths to portable C++.
//
// Deliberately NOT GetStringUTFChars: that speaks "modified UTF-8" and corrupts 4-byte
// characters (emoji in file names). Same conversion foldervault_bridge.cpp uses internally.
#pragma once

#include <jni.h>

#include <cstdint>
#include <string>

inline std::string jniStringToUtf8(JNIEnv* env, jstring js) {
    if (!js) return std::string();
    const jchar* u = env->GetStringChars(js, nullptr);
    const jsize n = env->GetStringLength(js);
    std::string out;
    out.reserve(static_cast<size_t>(n));
    for (jsize i = 0; i < n; i++) {
        uint32_t cp = u[i];
        if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < n && u[i + 1] >= 0xDC00 && u[i + 1] <= 0xDFFF) {
            cp = 0x10000 + ((cp - 0xD800) << 10) + (u[i + 1] - 0xDC00);
            i++;
        } else if (cp >= 0xD800 && cp <= 0xDFFF) {
            cp = 0xFFFD;   // lone surrogate
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
    env->ReleaseStringChars(js, u);
    return out;
}
