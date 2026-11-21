// Folder-vault (gocryptfs / Cryptomator / CryFS) slots for the desktop C ABI.
//
// An unlocked folder vault occupies a volume slot, like a container. ve_engine.cpp asks isSlot(vol)
// at the top of every file-level entry point and, when true, forwards to the functions below
// instead of the block-device filesystem layer -- so callers address both families through the
// same slot ids (the rule the whole app is built on). The Windows build compiles these as stubs
// (isSlot() is always false) until foldervault/fv_storage.cpp has a Win32 storage backend.
#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

#include "ve_engine.h"

namespace vefv {

bool isSlot(int32_t vol);
// Closes (waiting for in-flight calls, wiping keys) and forgets the slot. No-op if it is not one.
void closeSlot(int32_t vol);
// VE_FORMAT_* for a folder-vault slot, or -1.
int32_t containerFormat(int32_t vol);

// Every function below returns a VE_* code (sizes return the value, or a negative -VE_* code,
// except fileSize which keeps the block path's "-1 = missing" convention). They assume isSlot(vol).
int32_t list(int32_t vol, const char* path, ve_buffer* out);
int64_t fileSize(int32_t vol, const char* path);
int64_t folderSize(int32_t vol, const char* path);
int32_t readChunk(int32_t vol, const char* path, int64_t offset, int32_t length, std::vector<uint8_t>& out);
int32_t writeChunk(int32_t vol, const char* path, int64_t offset, const uint8_t* data, size_t len);
// A file written chunk by chunk only becomes visible once finishWrite() has been called for it.
int32_t finishWrite(int32_t vol, const char* path);
int32_t remove(int32_t vol, const char* path);
int32_t makeDirectory(int32_t vol, const char* path);
int32_t rename(int32_t vol, const char* from, const char* to);
int32_t setLastModified(int32_t vol, const char* path, int64_t epochSeconds);
int32_t listSymlinks(int32_t vol, const char* path, ve_buffer* out);
int32_t readSymlink(int32_t vol, const char* path, ve_buffer* out);
int32_t createSymlink(int32_t vol, const char* path, const char* target);
int32_t importFile(int32_t vol, const char* vaultPath, const char* hostSource, int32_t opId);
int32_t exportFile(int32_t vol, const char* vaultPath, const char* hostDest, int32_t opId);
int32_t spaceInfo(int32_t vol, uint64_t* total, uint64_t* freeBytes);
int32_t vaultInfo(int32_t vol, ve_vault_info* out);

// Streams: cheap (path + vault) handles; reads go through readChunk. A lock invalidates them.
int64_t openStream(int32_t vol, const char* path);
int32_t readStream(int32_t vol, int64_t handle, int64_t offset, uint8_t* dest, int32_t length);
void closeStream(int32_t vol, int64_t handle);

bool isReadOnly(int32_t vol);

}  // namespace vefv
