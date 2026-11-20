#pragma once
// Minimal stand-in for <jni.h> -- just the calls jni_password_utf8.h makes -- so the
// conversion can be unit-tested on the host.
#include <cstdint>
#include <cstddef>
typedef int32_t jint;
typedef jint jsize;
typedef uint16_t jchar;
typedef unsigned char jboolean;
struct _jstring { const jchar* data; jsize len; };
typedef _jstring* jstring;
struct JNIEnv_ {
    jsize GetStringLength(jstring s) { return s->len; }
    const jchar* GetStringChars(jstring s, jboolean*) { return s->data; }
    void ReleaseStringChars(jstring, const jchar*) {}
};
typedef JNIEnv_ JNIEnv;
