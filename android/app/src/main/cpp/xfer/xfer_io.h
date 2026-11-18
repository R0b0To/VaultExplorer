// Byte-stream primitives shared by the transfer helpers (hashing, split/join).
//
// Deliberately tiny and free of any platform type: a source or sink is whatever the host
// has -- a host file (xfer_host.h), a vault file (volman/vm_xfer.h), an Android
// InputStream bridged over JNI. Nothing here knows about files, paths or JNI.
#pragma once

#include <cstddef>
#include <cstdint>

namespace xfer {

// Pull-style source of bytes.
struct ByteSource {
    virtual ~ByteSource() = default;
    // Bytes read (> 0), 0 at end of stream, < 0 on error.
    virtual int64_t read(uint8_t* buf, size_t n) = 0;
};

// Push-style destination that can take back what it wrote.
struct ByteSink {
    virtual ~ByteSink() = default;
    virtual bool write(const uint8_t* data, size_t n) = 0;
    // Flushes and finishes the output. False = it could not be completed.
    virtual bool close() = 0;
    // Gives up: closes and removes whatever was written, best effort. Safe after a failed
    // write or close(), and a no-op after a successful close().
    virtual void discard() = 0;
};

// Progress and cancellation of a long operation.
struct Observer {
    virtual ~Observer() = default;
    // `done` of `total` bytes (total 0 = unknown).
    virtual void onProgress(uint64_t /*done*/, uint64_t /*total*/) {}
    // Polled between chunks; true aborts the operation.
    virtual bool cancelled() { return false; }
};

enum class Result { Ok, Failed, Cancelled };

// Chunk size of every copy loop here (the Kotlin handlers' copyBufferSize was of this order).
constexpr size_t kChunkBytes = 1024 * 1024;

}  // namespace xfer
