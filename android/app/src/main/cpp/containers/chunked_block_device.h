#pragma once

// A byte-addressable virtual block device backed by fixed-size (default
// 4 MB) chunk files, each independently readable/writable through a pair
// of caller-supplied callbacks. This is the native counterpart of
// VaultSync Bridge's remote 4 MB `.chk` chunk layout (see
// docs/architecture.md ADR-031 §8 and ConvertVolumeActivity's splitter on
// the Bridge side) — VeraCrypt/LUKS/BitLocker sector I/O never needs to
// know its backing store is chunked at all; that's exactly what this
// class exists to hide.
//
// Deliberately dependency-free (no JNI, no Android headers, no VolumeState
// knowledge) so it's usable from a plain host-side unit test
// (containers/test/chunked_block_device_test.cpp) the same way
// io/decrypted_block_cache.h and io/sector_batching.h are.
//
// NOTE on current integration status: as of this writing,
// ContainerEngine.unlockRemoteChunked's actual production I/O path goes
// through a Kotlin-side AppFuse `ProxyFileDescriptorCallback`
// (`CloudChunkProxyCallback`) so that the *existing*, already-audited
// `prepareSession(fd, ...)` / `disk_read`/`disk_write`-via-`pread`/`pwrite`
// code can be reused completely unmodified for header parsing and mounted
// I/O alike (mirrors the precedent VolumeState::bitlockerProxyFd already
// sets for USB-backed BitLocker sessions — see that field's doc comment
// in volume_state.h). This class, plus its io/block_io.cpp wiring behind
// VolumeState::isCloudChunkedSource, is the direct in-process alternative
// to that FUSE round trip: available, unit-tested, and wired end-to-end
// at the physicalRead/physicalWrite layer, but not yet the path
// `unlockRemoteChunked` switches a volume onto. Swapping it in is a
// follow-up performance change once there's real device profiling to
// justify it (see Phase 6's benchmark table) — not a correctness gap.
#include <cstdint>
#include <functional>
#include <mutex>

constexpr uint64_t DEFAULT_CHUNK_SIZE_BYTES = 4ull * 1024 * 1024; // 4 MB

// Returns false on any unrecoverable failure (caller treats that as an
// I/O error, same as physicalRead/physicalWrite's own bool contract).
// A chunk that is legitimately absent on the remote (sparse) is NOT a
// failure — readFn is expected to zero-fill outBuf and return true, per
// IVaultCloudBridgeService.openRemoteChunkForRead's own doc comment.
typedef std::function<bool(uint64_t chunkIndex, uint64_t offsetInChunk, unsigned char* outBuf, size_t len)> ChunkReadFn;
typedef std::function<bool(uint64_t chunkIndex, uint64_t offsetInChunk, const unsigned char* inBuf, size_t len)> ChunkWriteFn;

class ChunkedBlockDevice {
public:
    ChunkedBlockDevice(uint64_t totalVolumeSizeBytes,
                       uint32_t chunkSizeNumBytes,
                       ChunkReadFn readFn,
                       ChunkWriteFn writeFn);

    // Splits [byteOffset, byteOffset+len) into per-chunk sub-ranges and
    // calls readFn/writeFn once per touched chunk. A request that never
    // crosses a chunk boundary (the common case: disk_read/disk_write's
    // own MAX_SECTORS_PER_BATCH already caps a single physicalRead/Write
    // call at 4 MB, matching the default chunk size) makes exactly one
    // callback invocation.
    bool pread(uint64_t byteOffset, unsigned char* outBuf, size_t len);
    bool pwrite(uint64_t byteOffset, const unsigned char* inBuf, size_t len);

    uint64_t totalSize() const { return totalVolumeSizeBytes_; }
    uint32_t chunkSize() const { return chunkSizeNumBytes_; }

private:
    uint64_t totalVolumeSizeBytes_;
    uint32_t chunkSizeNumBytes_;
    ChunkReadFn readFn_;
    ChunkWriteFn writeFn_;
    // Held across the whole pread()/pwrite() call, including the
    // readFn_/writeFn_ invocations — mirrors VolumeState::ioBufMutex,
    // which virtual_block_device.cpp already holds across a blocking
    // physicalRead/physicalWrite call for the same reason (§ that file's
    // getVolIoBuf usage). Serializes this volume's chunk I/O onto one
    // request at a time rather than letting concurrent disk_read/
    // disk_write calls race JNI round-trips for the same volume; cross-
    // volume and cross-provider concurrency is governed separately by
    // the Bridge's own SyncConcurrency/RateLimitPolicy on the other side
    // of that round trip.
    std::mutex ioMutex_;
};
