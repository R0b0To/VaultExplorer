// The desktop engine's one slot table (not part of the public C ABI).
//
// Every unlocked volume -- a block-device container (VeraCrypt, LUKS, BitLocker, composite) or a folder
// vault (gocryptfs, Cryptomator, CryFS) -- sits in one slot of one vm::VolumeManager, addressed by the same
// number the C ABI calls `vol`. The generic ve_* file calls (list, read, write, delete, streams, ...) are
// thin wrappers over that manager, so locking, safe close and "which family is this" live in one place
// (volman/README.md). The pieces of the engine that are about *sessions* rather than files -- unlock, lock,
// password change, repair -- still talk to the engine's own state (volumes[]) and only register or remove
// the slot here.
#pragma once

#include <cstdint>

#include "ve_engine.h"
#include "volman/vm_manager.h"

// The process-wide manager, FF_VOLUMES slots. Created on first use.
vm::VolumeManager& ve_internal_volumes();

// Registers the block-device session the engine just unlocked into volumes[volId] (and mounted) so the
// generic file calls can reach it. False when the slot is already taken by a live volume -- the caller then
// locks the session again instead of leaving a decrypted one nobody can reach.
bool ve_internal_attach_block(int32_t volId);

// Called by an unlock that is about to put a container into `volId`, before it derives any key. Detaches a
// container still registered there (the new session replaces it) and returns true; false when the slot holds
// an unlocked folder vault, which a container must not take over.
bool ve_internal_prepare_block_slot(int32_t volId);

// What the folder-vault side keeps next to the manager: the format of a vault slot (a VE_FORMAT_* code, or
// -1 for any other slot) and the whole-file transfers that work on host paths. Defined in ve_foldervault.cpp.
namespace vefv {
int32_t containerFormat(int32_t vol);
int32_t importFile(int32_t vol, const char* vaultPath, const char* hostSource, int32_t opId);
int32_t exportFile(int32_t vol, const char* vaultPath, const char* hostDest, int32_t opId);
int32_t vaultInfo(int32_t vol, ve_vault_info* out);
}  // namespace vefv
