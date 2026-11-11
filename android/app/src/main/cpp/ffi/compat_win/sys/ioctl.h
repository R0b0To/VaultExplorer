// Windows stand-in for <sys/ioctl.h>: nothing in the engine issues ioctls on Windows (a container's size comes
// from the file itself). The request-number macros exist so code that merely builds ioctl numbers compiles;
// ioctl() itself is a stub (ffi/ve_win_platform.cpp) that always fails with ENOTTY.
#pragma once
#define _IOC(dir, type, nr, size) (((unsigned long)(dir) << 30) | ((unsigned long)(size) << 16) | ((unsigned long)(type) << 8) | (unsigned long)(nr))
#define _IO(type, nr) _IOC(0, (type), (nr), 0)
#define _IOR(type, nr, size) _IOC(2, (type), (nr), sizeof(size))
#define _IOW(type, nr, size) _IOC(1, (type), (nr), sizeof(size))
#define _IOWR(type, nr, size) _IOC(3, (type), (nr), sizeof(size))
#ifdef __cplusplus
extern "C" int ioctl(int fd, unsigned long request, ...);
#else
int ioctl(int fd, unsigned long request, ...);
#endif
