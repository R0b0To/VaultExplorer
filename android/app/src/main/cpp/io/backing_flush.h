#pragma once
// One definition of "make everything below the filesystem durable" for a volume, so FatFs
// (disk_ioctl CTRL_SYNC), the NTFS device sync, libext2fs' io flush and the lock path cannot
// disagree about what a failed flush is. Header-only so the host tests can run the real thing
// (filesystems/test/ext_backend_test.cpp).
//
// Returns false when acknowledged bytes are NOT known to be on the backing store:
//   * USB source:  the write cache could not be flushed or the device barrier failed. The cache
//                  keeps the bytes pending, so a later call can retry.
//   * composite:   the carrier files could not be synced.
//   * fd:          the write-behind buffer could not be written. FdWriteBuffer keeps the bytes
//                  on failure (a retry rewrites the whole range), but VolumeState::reset() drops
//                  them, so a caller that ignores this result and then resets loses data.
// fsync of the fd stays best-effort: some fd types reject it with EINVAL, which says nothing
// about the data. errno is left as the flush set it.
#include <cerrno>
#include <unistd.h>
#include "volume_state.h"

inline bool flushVolumeBacking(VolumeState& v, int volId) {
    if (v.isUsbSource) return v.usbCache.sync(volId);
    if (v.isCompositeSource && v.composite) return v.composite->sync();
    if (v.fd >= 0) {
        const bool flushed = v.fdWriteBuffer.flush(v.fd);
        const int flushErrno = errno;  // before fsync can overwrite it
        fsync(v.fd);
        errno = flushErrno;
        return flushed;
    }
    return true;
}
