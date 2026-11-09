#pragma once

#include <shared_mutex>

#include "volume_state.h"

// Exclusive-path mount check/establish. Caller must already hold
// volumes[volId].mutex as a std::unique_lock (exclusive) -- this is the
// original entry point, still used directly by writers (which take the
// lock exclusively anyway) and internally by ensureMountedShared's
// upgrade path below. Performs the actual mount/remount when needed, so it
// mutates VolumeState (fsMounted, fsType, fatfs/ntfsVol/extFs) and must
// never run while any other thread could be reading those same fields.
bool ensureMounted(int volId);

// Shared-path mount check for read-only bridge operations (directory
// listing, file/folder size, chunked reads, free-space queries, stream
// open). Caller must already hold volumes[volId].mutex as a
// std::shared_lock when calling this. Fast path (by far the common case:
// the volume is already healthily mounted) just re-checks the same health
// conditions ensureMounted() does and returns true without ever touching
// exclusive locking, so concurrent readers don't serialize against each
// other here.
//
// Only when a (re)mount is actually needed does this drop the caller's
// shared lock and re-acquire volumes[volId].mutex exclusively to call
// ensureMounted() -- std::shared_mutex has no atomic upgrade-in-place, so
// there's a brief window between releasing shared and acquiring exclusive
// where another thread could run first. That's fine here: ensureMounted()
// already re-checks fsMounted/fsType/ntfsVol/extFs itself as its very
// first step (the same "did someone else already fix this" check any
// double-checked-locking pattern needs), so a second thread arriving to
// find the volume already remounted just returns true immediately without
// redoing the work. Callers get back a shared lock re-acquired on the same
// mutex, matching what they held before the call -- see the .cpp for the
// exact lock hand-off.
bool ensureMountedShared(int volId, std::shared_lock<std::shared_mutex>& lock);

// Tears the mounted filesystem down and flushes the volume's backing store.
// Returns false when the flush/sync of a USB device failed: the buffered writes
// are then STILL pending in volume.usbCache (nothing is discarded here), so the
// caller can retry or deliberately discard them. Everything else returns true.
//
// A false return leaves the filesystem unmounted (fsMounted == false) while the
// session stays open. That is a consistent, usable state: every filesystem entry
// point calls ensureMounted() first, which remounts on demand by reading through
// the same usbCache -- so the still-pending bytes are visible to the remount --
// and a retried lock simply runs this function again (it is idempotent).
bool unmountVolume(int volId);