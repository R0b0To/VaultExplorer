// Host-test stand-in for <jni.h>, so the test needs no JDK. The headers the
// ext backend pulls in (io/usb_block_cache.h -> jni/jni_callbacks.h) only
// declare JNI globals; nothing here is called.
#pragma once
// Minimal stand-in for <jni.h> so the host test needn't depend on a JDK.
typedef struct JNIEnv_ JNIEnv;
typedef struct JavaVM_ JavaVM;
typedef void* jclass;
typedef void* jmethodID;
typedef void* jobject;
typedef int jint;
