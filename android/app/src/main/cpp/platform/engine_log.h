// Logging for the portable engine (session/, io/, filesystems/, containers/, crypto/, ...).
//
// Engine files used to include <android/log.h> and define their own
//     #define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "TAG", __VA_ARGS__)
// which tied every one of them to the NDK. They now say
//     #define LOGI(...) ENGINE_LOG_INFO("TAG", __VA_ARGS__)
// and this header decides what that means:
//   * on Android it IS that same __android_log_print call, so nothing changes in the app;
//   * anywhere else it goes to a sink the host installs with engineLogSetSink(), and without one
//     it does nothing (what the host test stubs for <android/log.h> already did).
#pragma once

#if defined(__ANDROID__)

#include <android/log.h>

#define ENGINE_LOG_INFO(tag, ...) __android_log_print(ANDROID_LOG_INFO, tag, __VA_ARGS__)
#define ENGINE_LOG_WARN(tag, ...) __android_log_print(ANDROID_LOG_WARN, tag, __VA_ARGS__)
#define ENGINE_LOG_ERROR(tag, ...) __android_log_print(ANDROID_LOG_ERROR, tag, __VA_ARGS__)

#else

#include <atomic>
#include <cstdarg>
#include <cstdio>

enum EngineLogLevel { ENGINE_LOG_LEVEL_INFO = 0, ENGINE_LOG_LEVEL_WARN = 1, ENGINE_LOG_LEVEL_ERROR = 2 };

// Receives one formatted message (no trailing newline). May be called from any thread.
using EngineLogSink = void (*)(int level, const char* tag, const char* message);

// Header-only on purpose: the host tests compile single engine files without linking anything else.
// The slot is atomic, so a sink can be installed (or replaced) while other threads are logging.
inline std::atomic<EngineLogSink>& engineLogSinkSlot() {
    static std::atomic<EngineLogSink> sink{nullptr};   // one instance across translation units (inline function)
    return sink;
}
inline void engineLogSetSink(EngineLogSink sink) { engineLogSinkSlot().store(sink); }

#if defined(__GNUC__)
__attribute__((format(printf, 3, 4)))
#endif
inline void engineLog(int level, const char* tag, const char* fmt, ...) {
    EngineLogSink sink = engineLogSinkSlot().load();
    if (!sink) return;
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    std::vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    sink(level, tag, buf);
}

#define ENGINE_LOG_INFO(tag, ...) engineLog(ENGINE_LOG_LEVEL_INFO, tag, __VA_ARGS__)
#define ENGINE_LOG_WARN(tag, ...) engineLog(ENGINE_LOG_LEVEL_WARN, tag, __VA_ARGS__)
#define ENGINE_LOG_ERROR(tag, ...) engineLog(ENGINE_LOG_LEVEL_ERROR, tag, __VA_ARGS__)

#endif
