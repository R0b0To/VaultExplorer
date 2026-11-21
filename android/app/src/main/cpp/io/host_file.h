#pragma once

// Opening a HOST file (a path on the device's / computer's own filesystem, as opposed to a descriptor the
// caller already holds) for the engine's import / export routines and the composite-carrier readers.
//
//   POSIX (Android, Linux): exactly ::open(path, flags, mode) -- no behavior change.
//   Windows: the C runtime's plain open() is wrong twice over for this job:
//     * it defaults to TEXT mode, which translates CR/LF and treats a 0x1A byte as end-of-file, silently
//       truncating or altering any binary file (a container, a photo, a PDF ...);
//     * it takes the ANSI code page, so a path with non-ASCII characters cannot be opened at all.
//   ve_host_open() (ffi/ve_win_platform.cpp) takes a UTF-8 path and opens it in binary mode.

#include <fcntl.h>

#if defined(_WIN32)
extern "C" int ve_host_open(const char* utf8_path, int flags, int mode);
inline int hostOpen(const char* path, int flags, int mode = 0644) { return ve_host_open(path, flags, mode); }
#else
#include <unistd.h>
inline int hostOpen(const char* path, int flags, int mode = 0644) { return ::open(path, flags, mode); }
#endif
