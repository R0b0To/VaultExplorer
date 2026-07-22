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
#include <android/log.h>

#include "ff.h" // FF_VOLUMES

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_C++", __VA_ARGS__)

// Debug-level, separately-tagged timing logs — see io/virtual_block_device.cpp
// for the full rationale (disk_read/disk_write timing). Kept here too since
// a couple of JNI entry points log against the same "VaultExplorer_Timing" tag.
#define LOGD_TIMING(...) __android_log_print(ANDROID_LOG_DEBUG, "VaultExplorer_Timing", __VA_ARGS__)

#define MAX_VOLUMES FF_VOLUMES

// Reads a jintArray of keyfile fds into a std::vector<int>. Used by
// deriveKeyMaterialNative (crypto_bridge.cpp), unlockAndListNative /
// unlockUsbAndListNative (session_bridge.cpp), and every container-creation /
// password-change entry point (container_lifecycle_bridge.cpp).
std::vector<int> extractKeyfileFds(JNIEnv* env, jintArray arr);
