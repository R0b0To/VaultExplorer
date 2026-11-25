// Platform-neutral volume abstraction: the one set of operations a front-end
// needs from *any* unlocked volume, whatever family it belongs to.
//
// The Android app used to get this unification from Kotlin (`ContainerEngine`
// dispatching between `VaultBackendRegistry` and `NativeEngine`, with
// `ContainerSessionRegistry` holding the per-volume locks). That made the
// unification point a per-platform rewrite. `vm::Volume` + `vm::VolumeManager`
// (vm_manager.h) move it into C++ with no JNI, Android or Flutter dependency,
// so Android's JNI layer and a desktop front-end (FUSE, CLI, FFI) sit on the
// same calls.
//
// Contract shared by every implementation:
//   * Paths are cleartext, '/'-separated, relative to the volume root.
//   * Directory listings use the entry wire format of
//     filesystems/dir_entry_wire.h ("<F|D>|<size>|<mtimeSecs>|<name>"; links
//     "L|" / "LD|" only from listSymlinks). The type tag is explicit, never
//     inferred from a name.
//   * Implementations lock internally. A caller never takes a lock around a
//     call, and any two calls may run concurrently. close() waits for calls
//     that are already running.
//   * Methods never throw; a failure is `false` / -1 / nullopt.
#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace vm {

using Bytes = std::vector<uint8_t>;

enum class Family { BlockDevice, FolderVault };

// Outcome of a VolumeManager operation. NotUnlocked is separate from Failed
// because hosts report it differently (Android throws FileNotFoundException,
// "container not unlocked"; a CLI prints a different message).
enum class Status { Ok, Failed, NotUnlocked, Cancelled };
inline bool ok(Status s) { return s == Status::Ok; }

// Progress and cancellation for long transfers. The host maps it to whatever
// it has (Android: CopyProgressBridge / CopyCancellation keyed by opId).
struct Observer {
    virtual ~Observer() = default;
    // Plaintext bytes moved since the previous call.
    virtual void onBytes(uint64_t /*bytes*/) {}
    // Polled between chunks; true aborts the transfer.
    virtual bool cancelled() { return false; }
};

// Pull-style source of plaintext (an InputStream on Android, a file or pipe
// on desktop).
struct ByteSource {
    virtual ~ByteSource() = default;
    // Bytes read (> 0), 0 at end of stream, < 0 on error.
    virtual int64_t read(uint8_t* buf, size_t n) = 0;
};

struct SpaceInfo {
    int64_t total = -1;
    int64_t free = -1;
};

// One entry of Volume::info(); typed so the host can hand the UI real ints and bools.
struct InfoItem {
    enum class Kind { Str, Int, Bool } kind = Kind::Str;
    std::string key;
    std::string value;   // "true"/"false" for Bool, decimal for Int
};

// Wipes memory in a way the optimiser cannot elide (used for plaintext buffers).
void secureZero(void* p, size_t n);

class Volume {
public:
    virtual ~Volume() = default;

    virtual Family family() const = 0;
    virtual bool readOnly() const = 0;
    // False once the volume was locked behind the manager's back (a block-device
    // volume whose container the session layer locked, say). The manager then
    // answers NotUnlocked for its slot and frees the slot on its next sweep.
    // Must not block: it is called while the manager decides about slots.
    virtual bool alive() const { return true; }

    // ---- namespace ------------------------------------------------------
    // false = the folder could not be read; an unreadable folder must never
    // look like an empty one (callers cache and sync against listings).
    virtual bool listDirectory(const std::string& path, std::vector<std::string>& wire) = 0;
    // Symbolic links of one folder, wire kind "L"/"LD". Never part of listDirectory().
    virtual bool listSymlinks(const std::string& /*path*/, std::vector<std::string>& wire) { wire.clear(); return true; }
    virtual std::optional<std::string> readSymlink(const std::string& /*path*/) { return std::nullopt; }
    virtual bool createSymlink(const std::string& /*path*/, const std::string& /*target*/) { return false; }
    // Entries present on disk but not listed (sync-conflict copies, ...); -1 = cannot tell.
    virtual int hiddenEntryCount(const std::string& /*path*/) { return -1; }
    // A file already in the way makes this fail; it never overwrites. Whether
    // creating a folder that already exists succeeds is up to the engine (the
    // folder vaults treat it as success, like `mkdir -p`).
    virtual bool createDirectory(const std::string& path) = 0;
    virtual bool renameFile(const std::string& from, const std::string& to) = 0;
    virtual bool setLastModifiedTime(const std::string& path, int64_t epochSeconds) = 0;
    virtual bool deleteFile(const std::string& path) = 0;
    virtual int64_t getFileSize(const std::string& path) = 0;     // -1: missing, a directory, or unreadable
    virtual int64_t getFolderSize(const std::string& path) = 0;

    // ---- content --------------------------------------------------------
    // true with `out` holding 0..length bytes (empty = end of file); false = failure.
    virtual bool readFileChunk(const std::string& path, int64_t offset, size_t length, Bytes& out) = 0;
    // Incremental writer: a write at offset 0 replaces the file, later chunks
    // arrive in order; the file is valid once finishWrite() returned true.
    virtual bool writeFileChunk(const std::string& path, int64_t offset, const uint8_t* data, size_t len) = 0;
    virtual bool finishWrite(const std::string& /*path*/) { return true; }
    // Writes the whole of `src` to `path`, creating or replacing the file. The
    // default drives writeFileChunk()/finishWrite(); engines with a better
    // path (a folder vault's chunked writer) override it. `obs` may be null.
    virtual bool importStream(const std::string& path, ByteSource& src, Observer* obs);

    // Creates an empty file, or empties an existing one. The default is the
    // incremental writer's own spelling of it (a zero-length write at offset 0,
    // then finishWrite()), so it works for every family; engines with a native
    // call override it.
    virtual bool createEmptyFile(const std::string& path);

    // ---- optional: in-place (random-access) writes ---------------------
    // Only a volume that can overwrite part of an existing file says so. The
    // OS-mount layer needs it (a program writing through a mount does real
    // random-access I/O); the folder vaults cannot offer it (their writer is
    // sequential, finish-on-close) and keep the defaults.
    virtual bool supportsRandomWrites() const { return false; }
    // `offset` must be <= the current size (grow with truncateFile() first).
    virtual bool writeFileAt(const std::string& /*path*/, int64_t /*offset*/, const uint8_t* /*data*/, size_t /*len*/) { return false; }
    // Sets the size of an existing file; growing zero-fills.
    virtual bool truncateFile(const std::string& /*path*/, int64_t /*size*/) { return false; }

    // True when names compare case-insensitively (FAT, exFAT, NTFS). A host that
    // exposes the volume through an OS mount needs it to resolve names the way
    // the filesystem itself does.
    virtual bool caseInsensitive() const { return false; }

    // ---- batching / caches ---------------------------------------------
    virtual void beginBatchWrite() {}
    virtual void endBatchWrite() {}
    virtual void beginBatchDelete() {}
    virtual void endBatchDelete() {}
    virtual void invalidateCache(const std::string& /*path*/) {}

    virtual bool spaceInfo(SpaceInfo& out) = 0;
    virtual std::vector<InfoItem> info() = 0;

    // ---- native read streams (optional) --------------------------------
    // A volume with a real handle-based reader (a mounted filesystem's open
    // file) says so here; every other volume gets a stream emulated by
    // VolumeManager with positioned readFileChunk() calls.
    virtual bool hasNativeStreams() const { return false; }
    // Only called when hasNativeStreams(); nullopt = the file could not be opened.
    virtual std::optional<uint64_t> openStream(const std::string& /*path*/) { return std::nullopt; }
    // Bytes read, 0 at end of file, -1 on error / unknown handle.
    virtual int64_t readStream(uint64_t /*handle*/, uint64_t /*offset*/, uint8_t* /*dst*/, size_t /*n*/) { return -1; }
    virtual void closeStream(uint64_t /*handle*/) {}

    // Stops accepting work, waits for calls in flight and wipes key material.
    // Idempotent.
    virtual void close() = 0;
};

}  // namespace vm
