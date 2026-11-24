// Whether two open descriptors refer to the same file on disk.
//
// The expand / grow tools must refuse a container file that is currently unlocked (containerFileIsUnlocked), and the
// only reliable test is file identity, not the path: the same file can be reached through a link, a bind mount or
// another spelling.
//
//   * POSIX: same device and inode (fstat).
//   * Windows: the CRT's st_ino is always 0, so comparing (st_dev, st_ino) would call EVERY pair of files on one
//     drive "the same file" and refuse every expansion while any vault on that drive is unlocked. The answer comes
//     from GetFileInformationByHandle (volume serial number + file index) in ffi/ve_win_platform.cpp, the one
//     translation unit that may include <windows.h>.
//
// Header-only on purpose, like platform/engine_log.h: host tests compile single engine files without linking
// anything else.
#pragma once

#include <sys/stat.h>
#include <sys/types.h>

#if defined(_WIN32)
// 1 same file, 0 different files (or either descriptor is not open), -1 the OS could not say.
extern "C" int ve_win_same_file(int fdA, int fdB);
#endif

// True when [fdA] and [fdB] are the same file. Biased towards "yes" when the platform cannot tell on Windows
// (callers use this to refuse work that would be unsafe on an open container); on POSIX a failed fstat means "no",
// exactly as the inline comparison this replaces behaved.
inline bool engineDescriptorsShareFile(int fdA, int fdB) {
#if defined(_WIN32)
    return ve_win_same_file(fdA, fdB) != 0;
#else
    struct stat a{};
    struct stat b{};
    return fstat(fdA, &a) == 0 && fstat(fdB, &b) == 0 && a.st_dev == b.st_dev && a.st_ino == b.st_ino;
#endif
}
