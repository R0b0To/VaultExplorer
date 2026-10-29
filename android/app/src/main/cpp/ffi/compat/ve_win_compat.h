// Windows (MinGW-w64) POSIX shims for the engine -- DECLARATIONS ONLY.
//
// Force-included (-include) into every engine C++ translation unit on _WIN32; a no-op
// elsewhere. The engine addresses containers through plain C file descriptors and uses
// pread/pwrite (~190 call sites) for positional I/O, which MinGW's C runtime lacks.
// They are implemented in ffi/ve_win_platform.cpp.
//
// Deliberately NOT included here: <windows.h>. It must never be force-included engine-wide
// because it collides with the ntfs-3g headers (`typedef enum BOOL`, DELETE/ERROR-style
// macros). Only ffi/ve_win_platform.cpp sees it.
//
// These are real functions, not function-like macros: the engine has C++ classes with
// member functions literally named pread/pwrite (composite / VHD / VHDX block devices),
// which a `#define pread(a,b,c,d)` would mangle.
#pragma once

#if defined(_WIN32) && defined(__cplusplus)

#include <errno.h>
#include <fcntl.h>
#include <io.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#ifndef O_CLOEXEC
#  define O_CLOEXEC 0
#endif
#ifndef O_LARGEFILE
#  define O_LARGEFILE 0
#endif

// Build with _FILE_OFFSET_BITS=64 (the engine already does) so off_t is 64-bit.
ssize_t pread(int fd, void* buf, size_t count, off_t offset);
ssize_t pwrite(int fd, const void* buf, size_t count, off_t offset);
ssize_t pread64(int fd, void* buf, size_t count, int64_t offset);
ssize_t pwrite64(int fd, const void* buf, size_t count, int64_t offset);
int fsync(int fd);
int fdatasync(int fd);

#include <stdlib.h>
#include <time.h>

// localtime_r: MinGW has the secure localtime_s with swapped argument order.
static inline struct tm* localtime_r(const time_t* t, struct tm* out) {
    return localtime_s(out, t) == 0 ? out : nullptr;
}

// posix_memalign: 64-bit Windows malloc() already returns 16-byte-aligned memory, which is
// all the engine asks for (ntfs_backend.cpp's AlignedBuffer, released with free()).
// Anything stricter would need _aligned_malloc/_aligned_free, which free() cannot release.
static inline int posix_memalign(void** out, size_t alignment, size_t size) {
    if (!out || alignment > 16) return EINVAL;
    void* p = malloc(size ? size : 1);
    if (!p) return ENOMEM;
    *out = p;
    return 0;
}

#endif  // _WIN32 && __cplusplus
