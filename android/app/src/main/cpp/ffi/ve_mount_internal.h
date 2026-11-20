// Engine-internal hooks for the desktop mount layer (not part of the public C ABI).
#pragma once

#include <cstdint>

// Facts about an unlocked slot that the mount layer needs and the public ABI does not expose.
//   folderVault     -- the slot is a gocryptfs / Cryptomator / CryFS vault (sequential, finish-on-close writes)
//   caseInsensitive -- names compare case-insensitively (FAT / exFAT / NTFS)
//   readOnly        -- the slot was unlocked read-only (or became read-only, e.g. hidden-volume protection)
// Returns false if `vol` has no active session.
bool ve_internal_vol_traits(int32_t vol, bool* folderVault, bool* caseInsensitive, bool* readOnly);

// Unmounts every OS mount that exposes `vol` (gracefully, then forcibly) and commits pending writes.
// Called by ve_lock before key material is wiped. Defined in ve_mount_fuse.cpp / ve_mount_stub.cpp.
void ve_internal_unmount_volume(int32_t vol);

#include <string>
// Records the reason for the most recent failed mount/unmount (readable through ve_mount_last_error) and logs it.
// Defined in ve_mount_fuse.cpp; shared by the Linux (FUSE) and Windows (WinFsp) glue.
void ve_mount_set_error(const std::string& message);
