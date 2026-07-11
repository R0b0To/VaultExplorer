#pragma once

#include <jni.h>

bool requireActiveSession(int volumeId, const char* operation);
void throwNotUnlocked(JNIEnv* env, int volumeId, const char* operation);
