#include "session_guard_jni.h"

#include <cstdio>

#include "jni_callbacks.h"

void throwNotUnlocked(JNIEnv* env, int volumeId, const char* operation) {
    char message[160];
    snprintf(message, sizeof(message), "NOT_UNLOCKED: volume %d has no active session (%s)",
             volumeId, operation);
    env->ThrowNew(g_illegalStateExceptionClass, message);
}

void throwReadOnly(JNIEnv* env, int volumeId, const char* operation) {
    char message[160];
    snprintf(message, sizeof(message), "READ_ONLY: volume %d is mounted read-only (%s)",
             volumeId, operation);
    env->ThrowNew(g_illegalStateExceptionClass, message);
}
