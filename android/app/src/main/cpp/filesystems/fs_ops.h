#pragma once

// Small common interface over the three mounted-filesystem backends
// (FAT/exFAT via FatFs, NTFS via NTFS-3G, ext2/3/4 via libext2fs).
//
// Every jni/filesystem_bridge.cpp JNI entry point used to branch on
// volumes[volId].fsType inline, with FAT/NTFS/ext logic for the same
// operation living side-by-side in the same function. These functions are
// that dispatch, pulled out to one place: filesystem_bridge.cpp now calls a
// single fsXxx(...) function per operation and handles only JNI marshalling
// (jstring/jbyteArray conversion, exception throwing) — the per-filesystem
// implementations live in filesystems/{fat,ntfs,ext}_backend.cpp, unchanged
// in behavior from their original inline form.
//
// All functions take a plain volId and look up volumes[volId] themselves,
// matching the convention already used by recursiveFatFolderSize /
// recursiveNtfsFolderSize / recursiveExtFolderSize / listNtfsDirectory.
// None of this takes a JNIEnv* or any JNI type — that keeps it callable
// (and testable) without the JVM, and keeps JNI concerns entirely inside
// filesystem_bridge.cpp.
//
// Every function here assumes the caller already holds volumes[volId].mutex
// and has already called ensureMounted(volId) successfully — same
// precondition every original inline branch assumed implicitly.

#include <cstdint>
#include <string>
#include <vector>

// ── Directory listing ──────────────────────────────────────────────────
// Appends "name|size|mtime" entries to outResults ("[DIR] " prefix for
// directories, matching the wire format the Kotlin side already parses).
// pathSuffix is "" (or "/") for the container root.
void fsListDirectory(int volId, const std::string& pathSuffix,
                      std::vector<std::string>& outResults);

// ── Size queries ───────────────────────────────────────────────────────
// Both return 0 on any failure (path not found, wrong type, ...) — same
// zero-on-failure convention the original inline code used, so callers
// can't distinguish "empty file" from "not found" here any more than they
// could before this split.
uint64_t fsGetFileSize(int volId, const std::string& path);
uint64_t fsGetFolderSize(int volId, const std::string& path);

// ── Whole/partial file I/O ─────────────────────────────────────────────
// fsReadFileChunk: on success, outBuffer is resized to the number of bytes
// actually read (which may be less than length, e.g. at EOF) and returns
// true. On failure/zero bytes read, returns false and outBuffer is left
// empty.
bool fsReadFileChunk(int volId, const std::string& path, uint64_t offset,
                      size_t length, std::vector<uint8_t>& outBuffer);

// fsWriteFileChunk: writes exactly `length` bytes from `data` at `offset`,
// creating the file if it doesn't exist. Matches the original semantics of
// truncate-on-offset-0 (a write starting at offset 0 replaces the file's
// contents rather than just overwriting the first `length` bytes).
bool fsWriteFileChunk(int volId, const std::string& path, uint64_t offset,
                      const uint8_t* data, size_t length);

// fsWriteBackFile / fsExtractFile: copy a whole file across the JNI
// boundary via a host-filesystem path (used for "share/open externally"
// and "import from device storage" flows) rather than chunk-by-chunk.
bool fsWriteBackFile(int volId, const std::string& targetPath, const std::string& sourceHostPath);
bool fsExtractFile(int volId, const std::string& targetPath, const std::string& destHostPath);

// ── Directory-entry mutation ───────────────────────────────────────────
bool fsDeleteFile(int volId, const std::string& path);
bool fsCreateDirectory(int volId, const std::string& path);
bool fsRenameFile(int volId, const std::string& oldPath, const std::string& newPath);
bool fsSetLastModifiedTime(int volId, const std::string& path, uint64_t epochSeconds);

// ── Volume-level info ──────────────────────────────────────────────────
// Leaves both outputs at 0 if the volume's fsType doesn't match any known
// backend (shouldn't happen once ensureMounted() has succeeded).
void fsGetSpaceInfo(int volId, uint64_t& outTotalBytes, uint64_t& outFreeBytes);

// ── Streaming read handles (used for media playback) ───────────────────
// The returned handle is one of FIL*/NtfsStream*/ExtStream* under the
// hood, already pushed onto the matching volumes[volId].open*Streams
// vector by fsOpenStream — same ownership/storage model as before this
// split (session_bridge.cpp's lockNative and virtual_block_device.cpp's
// unmountVolume still walk those vectors directly to force-close anything
// left open, and are unaffected by this header). Callers only ever pass
// the handle back into fsReadStream/fsCloseStream; nothing outside
// filesystems/*_backend.cpp needs to know its real type, matching how
// filesystem_bridge.cpp treated it as an opaque jlong before.
void* fsOpenStream(int volId, const std::string& path);
// Returns bytes read, or -1 if `handle` isn't a currently-open handle for
// this volume, or on any I/O error.
int32_t fsReadStream(int volId, void* handle, uint64_t offset, uint8_t* dest, size_t length);
void fsCloseStream(int volId, void* handle);
