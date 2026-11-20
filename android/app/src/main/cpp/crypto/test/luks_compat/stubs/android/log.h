#pragma once
#include <cstdio>
#define ANDROID_LOG_INFO 4
#ifdef HARNESS_VERBOSE
#define __android_log_print(prio, tag, ...) (fprintf(stderr, "[%s] ", tag), fprintf(stderr, __VA_ARGS__), fputc('\n', stderr), 0)
#else
#define __android_log_print(prio, tag, ...) ((void)0)
#endif
