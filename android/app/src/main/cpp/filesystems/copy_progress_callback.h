#pragma once

#include <cstdint>
#include <functional>

// Invoked after each successfully-written buffer chunk during a whole-file
// native copy (fatCopyFile / ntfsCopyFile / extCopyFile / fsCopyFile's
// cross-filesystem fallback), with the number of bytes just written --
// NOT a running total. Callers that want a cumulative figure sum the
// deltas themselves (this matches how FileOperation._addTransferredBytes
// already accumulates on the Dart side for the old chunked-copy fallback,
// so the native fast path now feeds the same accumulator instead of
// crediting the whole file in one shot at the end).
//
// Deliberately a plain std::function rather than anything JNI-shaped:
// fs_ops.h's header comment already establishes that this layer takes no
// JNIEnv*/JNI type so it stays callable and testable without the JVM.
// filesystem_bridge.cpp is the only place that ever constructs one of
// these that actually touches JNI (it wraps reportCopyProgress() from
// jni_callbacks.h in a lambda over opId) -- fat_backend.cpp/ntfs_backend.cpp/
// ext_backend.cpp/fs_ops.cpp just call whatever callable they were handed.
using CopyProgressCallback = std::function<void(uint64_t bytesWritten)>;
