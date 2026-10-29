// Desktop stand-in for <android/log.h>.
//
// The engine logs through __android_log_print (usually via a local LOGI macro).
// On desktop those lines go to ve_log_dispatch() (ffi/ve_engine.cpp), which is
// a no-op unless the host calls ve_set_log_enabled(1) -- logging is OFF by
// default because engine log lines can name volume ids, paths and sizes, and
// this is a privacy-focused app.
#pragma once

#include <cstdarg>
#include <cstdio>

enum {
    ANDROID_LOG_UNKNOWN = 0,
    ANDROID_LOG_DEFAULT,
    ANDROID_LOG_VERBOSE,
    ANDROID_LOG_DEBUG,
    ANDROID_LOG_INFO,
    ANDROID_LOG_WARN,
    ANDROID_LOG_ERROR,
    ANDROID_LOG_FATAL,
    ANDROID_LOG_SILENT,
};

extern "C" int ve_log_enabled(void);
extern "C" void ve_log_dispatch(int prio, const char* tag, const char* message);

inline int __android_log_print(int prio, const char* tag, const char* fmt, ...) {
    if (!ve_log_enabled()) return 0;
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    std::vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    ve_log_dispatch(prio, tag, buf);
    return 0;
}
