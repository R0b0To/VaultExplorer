#pragma once

// Shared declarations for the VeraCryptEngine JNI bridge, split by domain
// across crypto_bridge.cpp / session_bridge.cpp / container_lifecycle_bridge.cpp
// / filesystem_bridge.cpp (see io/virtual_block_device.cpp for the FatFs
// diskio + crypto-dispatch layer these all sit on top of).
//
// This header exists ONLY for the handful of things genuinely shared across
// more than one of those files. Anything used by a single bridge file stays
// `static` in that file, same as it was in the original monolithic
// vaultexplorer.cpp.

#include <jni.h>
#include <vector>
#include <exception>
#include <android/log.h>

#include "ff.h" // FF_VOLUMES

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

// Debug-level, separately-tagged timing logs — see io/virtual_block_device.cpp
// for the full rationale (disk_read/disk_write timing). Kept here too since
// a couple of JNI entry points log against the same "VaultExplorer_Timing" tag.
#define LOGD_TIMING(...) __android_log_print(ANDROID_LOG_DEBUG, "VaultExplorer_Timing", __VA_ARGS__)

#define MAX_VOLUMES FF_VOLUMES

// ── JNI exception safety ────────────────────────────────────────────────
// An uncaught C++ exception crossing a JNIEXPORT function back into the JVM
// is undefined behavior, not a catchable Java exception -- in practice it
// tends to crash the whole app rather than fail one operation. Nothing in
// this codebase throws on a reachable path today (no .at(), no stoi, one
// throw total, in crypto/thread_pool.h's ThreadPool::enqueue guard), so this
// is prophylactic rather than a fix for an observed crash. But
// io/virtual_block_device.cpp's parallelCryptoLoop deliberately propagates
// worker-thread exceptions via future::get() instead of swallowing them --
// "fail loud rather than silently corrupt plaintext" -- and today "loud"
// means undefined behavior at this boundary. These macros make it a real
// Java exception instead, so future code (here or in a worker thread) can
// throw and get a controlled failure.
//
// Usage: wrap the body of a JNIEXPORT function --
//
//   extern "C" JNIEXPORT jint JNICALL
//   Java_..._someFunction(JNIEnv* env, jobject, ...) {
//       JNI_TRY
//       ... existing body, unchanged ...
//       JNI_CATCH_RETURN(-1)   // value returned if an exception was caught
//   }
//
// or JNI_CATCH_VOID for a `void`-returning entry point. `env` must be a
// named parameter (rename an unused `JNIEnv*,` to `JNIEnv* env,` if needed).
#define JNI_TRY try {

#define JNI_CATCH_RETURN(onExceptionValue) \
    } catch (const std::exception& e) { \
        LOGI("uncaught C++ exception at JNI boundary: %s", e.what()); \
        if (!env->ExceptionCheck()) { \
            jclass _jniExClass = env->FindClass("java/lang/RuntimeException"); \
            if (_jniExClass) env->ThrowNew(_jniExClass, e.what()); \
        } \
        return (onExceptionValue); \
    } catch (...) { \
        LOGI("uncaught non-standard C++ exception at JNI boundary"); \
        if (!env->ExceptionCheck()) { \
            jclass _jniExClass = env->FindClass("java/lang/RuntimeException"); \
            if (_jniExClass) env->ThrowNew(_jniExClass, "native exception (non-std::exception type)"); \
        } \
        return (onExceptionValue); \
    }

#define JNI_CATCH_VOID \
    } catch (const std::exception& e) { \
        LOGI("uncaught C++ exception at JNI boundary: %s", e.what()); \
        if (!env->ExceptionCheck()) { \
            jclass _jniExClass = env->FindClass("java/lang/RuntimeException"); \
            if (_jniExClass) env->ThrowNew(_jniExClass, e.what()); \
        } \
    } catch (...) { \
        LOGI("uncaught non-standard C++ exception at JNI boundary"); \
        if (!env->ExceptionCheck()) { \
            jclass _jniExClass = env->FindClass("java/lang/RuntimeException"); \
            if (_jniExClass) env->ThrowNew(_jniExClass, "native exception (non-std::exception type)"); \
        } \
    }

// Reads a jintArray of keyfile fds into a std::vector<int>. Used by
// deriveKeyMaterialNative (crypto_bridge.cpp), unlockAndListNative /
// unlockUsbAndListNative (session_bridge.cpp), and every container-creation /
// password-change entry point (container_lifecycle_bridge.cpp).
std::vector<int> extractKeyfileFds(JNIEnv* env, jintArray arr);
