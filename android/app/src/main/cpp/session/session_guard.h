#pragma once

// Portable guards for operations addressed by volume slot. The JNI exception helpers that
// used to live here (throwNotUnlocked / throwReadOnly) are in jni/session_guard_jni.h.

// False (with a log line) when `volumeId` has no unlocked session.
bool requireActiveSession(int volumeId, const char* operation);
bool isVolumeReadOnly(int volumeId);
