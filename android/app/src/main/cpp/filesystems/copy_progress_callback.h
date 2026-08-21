#pragma once

#include <cstdint>
#include <functional>

// Invoked after each successfully-written buffer chunk during a whole-file
// native copy or write-back (fatCopyFile / ntfsCopyFile / extCopyFile /
// fsCopyFile's cross-filesystem fallback, and fatWriteBackFile /
// ntfsWriteBackFile / extWriteBackFile / fsWriteBackFile), with the number
// of bytes just written -- NOT a running total. Callers that want a
// cumulative figure sum the deltas themselves (this matches how
// FileOperation._addTransferredBytes and ImportProgressBridge's chunk
// tracking already accumulate on their respective sides).
//
// Return value doubles as the cancellation signal: return true to keep
// going, false to abort. The four loops check this once per iteration --
// same cadence as the progress report, so cancellation lands within one
// buffer's worth of latency instead of only between whole files/items.
// On an abort the caller unwinds exactly like an I/O error (partial dest
// file deleted), no separate cancellation code path needed in the loops.
//
// Deliberately a plain std::function rather than anything JNI-shaped:
// fs_ops.h's header comment already establishes that this layer takes no
// JNIEnv*/JNI type so it stays callable and testable without the JVM.
// filesystem_bridge.cpp is the only place that ever constructs one of
// these that actually touches JNI (it wraps reportCopyProgress/
// isCopyCancelled or reportImportChunkProgress/isImportCancelled from
// jni_callbacks.h in a lambda over opId) -- fat_backend.cpp/ntfs_backend.cpp/
// ext_backend.cpp/fs_ops.cpp just call whatever callable they were handed.
using CopyProgressCallback = std::function<bool(uint64_t bytesWritten)>;
