// Host-OS file primitives with UTF-8 paths, for the few places the format engines touch the host filesystem
// directly instead of going through a Storage (CryFS's local integrity state, importing / exporting host files).
//
//   POSIX (Android, Linux): the plain calls, exactly as the call sites used them before -- no behavior change.
//   Windows: the C runtime's open()/fopen()/rename() take the ANSI code page (a path with non-ASCII characters
//   cannot be opened) and default to TEXT mode (CR/LF translation, 0x1A as end-of-file), so every one of these
//   converts the UTF-8 path to UTF-16 and works in binary mode. They are defined in fv_storage_win.cpp.
#pragma once

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <string>

#include <fcntl.h>
#if !defined(_WIN32)
#include <unistd.h>
#endif

#if defined(_WIN32) && !defined(O_CLOEXEC)
#define O_CLOEXEC 0   // Windows descriptors are created non-inheritable by osOpen() itself
#endif

namespace fv {

#if defined(_WIN32)

// open(2): binary, non-inheritable. [mode] is only used with O_CREAT.
int osOpen(const char* utf8Path, int flags, int mode);
std::FILE* osFopen(const char* utf8Path, const char* mode);
int osUnlink(const char* utf8Path);
// rename(2) semantics for files: an existing destination file is replaced.
int osRename(const char* utf8From, const char* utf8To);
// mkdir -p (separators may be '/' or '\\'). true if the directory exists afterwards.
bool osMkdirs(const std::string& utf8Path);
// pread/pwrite: positional I/O that does not depend on (and may move) the descriptor's file pointer.
// Return the byte count (0 at EOF for reads) or -1 on error, like the POSIX calls.
int64_t osPread(int fd, void* buf, size_t n, int64_t offset);
int64_t osPwrite(int fd, const void* buf, size_t n, int64_t offset);
int osFsync(int fd);
int osFileno(std::FILE* f);
// An anonymous read/write scratch file in [utf8Dir] (the system temp directory if empty): the descriptor is all
// there is -- the file disappears when it is closed (POSIX: mkstemp + unlink; here: delete-on-close). -1 on error.
int osMakeScratch(const std::string& utf8Dir);

#else

inline int osOpen(const char* p, int flags, int mode) { return ::open(p, flags, mode); }
inline std::FILE* osFopen(const char* p, const char* mode) { return std::fopen(p, mode); }
inline int osUnlink(const char* p) { return ::unlink(p); }
inline int osRename(const char* a, const char* b) { return ::rename(a, b); }
inline int64_t osPread(int fd, void* buf, size_t n, int64_t off) { return (int64_t)::pread(fd, buf, n, (off_t)off); }
inline int64_t osPwrite(int fd, const void* buf, size_t n, int64_t off) { return (int64_t)::pwrite(fd, buf, n, (off_t)off); }
inline int osFsync(int fd) { return ::fsync(fd); }
inline int osFileno(std::FILE* f) { return ::fileno(f); }

#endif

}  // namespace fv
