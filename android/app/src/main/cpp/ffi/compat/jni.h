// Desktop stand-in for <jni.h>.
//
// The engine core (session/, io/, containers/, filesystems/) never calls into a
// JVM itself, but a few of its headers and one translation unit still *name*
// JNI types:
//
//   * jni/jni_callbacks.h declares the callback API the engine uses for
//     progress / cancellation (and the JNI class/method globals behind it);
//   * session/session_guard.{h,cpp} has throwNotUnlocked(JNIEnv*, ...), which
//     only the Android JNI bridges call.
//
// On desktop there is no JVM, so this directory is put FIRST on the include path
// and supplies just enough of the type names for those files to compile
// unchanged. ThrowNew() is a deliberate no-op: nothing on the desktop path ever
// reaches it (the C ABI in ffi/ve_engine.cpp reports errors via return codes).
//
// ffi/ve_callbacks.cpp provides the real desktop implementation of the
// jni_callbacks.h API (no JVM involved).
#pragma once

typedef struct JavaVM_ JavaVM;
typedef void* jclass;
typedef void* jmethodID;
typedef void* jobject;
typedef int jint;

struct JNIEnv_ {
    void ThrowNew(jclass, const char*) {}
};
typedef JNIEnv_ JNIEnv;
