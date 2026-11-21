#pragma once

#include <shared_mutex>

#include "volume_state.h"

// Exclusive-path mount check/establish. Caller must already hold
// volumes[volId].mutex as a std::unique_lock (exclusive) -- this is the
// original entry point, still used directly by writers (which take the
// lock exclusively anyway). Performs the actual mount/remount when needed,
// so it mutates VolumeState (fsMounted, fsType, fatfs/ntfsVol/extFs) and must
// never run while any other thread could be reading those same fields.
bool ensureMounted(int volId);

// Makes everything the volume has acknowledged durable WITHOUT tearing anything down: dirty
// file streams, dirty filesystem metadata, then the backing store (USB cache + device barrier,
// composite carriers, fd write-behind buffer). Returns false if any step failed. Nothing is
// closed or freed, so a failure leaves the volume exactly as usable as before and the call can
// simply be repeated. This is the first half of a lock (jni/session_bridge.cpp).
bool flushVolumeForLock(int volId);

// Tears the mounted filesystem down and flushes the volume's backing store.
// Returns true only when every step succeeded: closing the filesystem (FatFs unregister,
// ntfs_umount, ext2fs_flush/close) AND the backing-store flush. On false, anything the backing
// store still holds is STILL pending (usbCache, fdWriteBuffer: nothing is discarded here), so
// the caller can retry or deliberately discard it.
//
// [keepOnFailure] is for the lock path. libext2fs does not free a filesystem whose close
// failed, so with it an ext filesystem stays mounted (fsMounted/extFs untouched) for a retry.
// FatFs and ntfs-3g give no such choice (ntfs_umount always frees the volume), so those are
// unmounted regardless. Callers that just want the filesystem gone leave it false.
//
// Apart from that ext case a false return leaves the filesystem unmounted (fsMounted == false)
// while the session stays open. That is a consistent, usable state: every filesystem entry
// point calls ensureMounted() first, which remounts on demand by reading through the same
// usbCache -- so the still-pending bytes are visible to the remount -- and a retried lock
// simply runs this function again (it is idempotent).
bool unmountVolume(int volId, bool keepOnFailure = false);