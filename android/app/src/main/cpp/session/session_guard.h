#pragma once

#include <jni.h>

bool requireActiveSession(int volumeId, const char* operation);
void throwNotUnlocked(JNIEnv* env, int volumeId, const char* operation);
bool isVolumeReadOnly(int volumeId);
void throwReadOnly(JNIEnv* env, int volumeId, const char* operation);