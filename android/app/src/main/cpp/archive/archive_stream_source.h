#pragma once

#include <cstdint>
#include <cstddef>
#include <functional>

// The archive engine's only point of contact with "how do I get bytes for
// this archive". Deliberately std::function-based rather than JNI-shaped,
// matching fs_ops.h/copy_progress_callback.h's convention: this layer takes
// no JNIEnv*/JNI type so it stays callable and testable without the JVM.
// archive_engine_test.cpp constructs one over a plain in-memory buffer;
// jni/archive_bridge.cpp (once the interop layer for exposing this to Dart
// is settled -- see the accompanying writeup) is the only place that will
// ever wrap a real container's stream in one of these, and it should do so
// directly against filesystems::fsOpenStream/fsReadStream/fsCloseStream --
// i.e. native-to-native, with no JNI/Dart round trip per chunk. Everything
// in archive_engine.cpp only ever sees this struct.
struct ArchiveStreamSource {
    // Reads up to `length` bytes starting at absolute `offset` into `dest`.
    // Returns the number of bytes actually read (may be less than `length`
    // only at EOF; a short read anywhere else is treated as an I/O error by
    // the engine), or a negative value on I/O error. Stateless/pread-style
    // on purpose: archive_engine.cpp tracks "current position" itself
    // (advanced by libarchive's read callback, jumped by its seek
    // callback) and always calls this with an absolute offset, which maps
    // directly onto fsReadStream(volId, handle, offset, dest, length) in
    // the real implementation -- no separate seek() needed on this side.
    std::function<int64_t(uint64_t offset, uint8_t* dest, size_t length)> read;

    // Total size of the underlying file, in bytes. Needed to clamp
    // SEEK_END-relative seeks and to reject reads/skips that run past
    // the end of the file.
    std::function<uint64_t()> size;
};
