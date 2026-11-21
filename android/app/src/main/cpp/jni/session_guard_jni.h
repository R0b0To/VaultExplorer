#pragma once

#include <jni.h>

#include "session/session_guard.h"   // the portable checks, so a JNI file needs just this one include

// Throw IllegalStateException with the "NOT_UNLOCKED: ..." / "READ_ONLY: ..." messages Kotlin
// matches on. They were part of session_guard.cpp; they are JNI, so they live under jni/.
void throwNotUnlocked(JNIEnv* env, int volumeId, const char* operation);
void throwReadOnly(JNIEnv* env, int volumeId, const char* operation);
