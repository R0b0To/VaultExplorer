// Windows (MinGW-w64) POSIX type / call stand-ins for the vendored C dependencies (ntfs-3g, dislocker).
// Force-included into C translation units on _WIN32 only; C-compatible, and deliberately free of
// <windows.h> (see ve_win_compat.h for why).
//
// What it provides is the minimum those libraries need to COMPILE for paths the engine never takes on
// Windows: ntfs-3g's own unix_io.c (the engine supplies its own device operations over the container
// file), its uid/gid security mapping, and dislocker's terminal prompt. fcntl() byte-range locking is
// therefore a no-op that reports success, and getuid()/getgid() answer 0.
#pragma once

#if defined(_WIN32)

#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>

#ifndef VE_WIN_IDS_DEFINED
#define VE_WIN_IDS_DEFINED
typedef unsigned int uid_t;
typedef unsigned int gid_t;
#endif

/* Implemented in ffi/ve_win_platform.cpp (C linkage). */
#include <stdio.h>
unsigned int getuid(void);
unsigned int geteuid(void);
unsigned int getgid(void);
unsigned int getegid(void);
ssize_t pread(int fd, void* buf, size_t count, off_t offset);
ssize_t pwrite(int fd, const void* buf, size_t count, off_t offset);
int fsync(int fd);
int fdatasync(int fd);
long random(void);
int ffs(int i);
char* basename(char* path);  /* libmingwex provides it; <libgen.h> is not always on the include path */
void srandom(unsigned int seed);
int ioctl(int fd, unsigned long request, ...);
int fork(void);
int setsid(void);
ssize_t getline(char** lineptr, size_t* n, FILE* stream);

#ifndef S_IFSOCK
#define S_IFSOCK 0140000
#endif
#ifndef S_IFLNK
#define S_IFLNK 0120000
#endif
#ifndef S_ISSOCK
#define S_ISSOCK(m) (((m) & S_IFMT) == S_IFSOCK)
#endif
#ifndef S_ISLNK
#define S_ISLNK(m) (((m) & S_IFMT) == S_IFLNK)
#endif
#ifndef S_ISUID
#define S_ISUID 0004000
#define S_ISGID 0002000
#define S_ISVTX 0001000
#endif
#ifndef S_IRGRP
#define S_IRGRP 0000040
#define S_IWGRP 0000020
#define S_IXGRP 0000010
#define S_IROTH 0000004
#define S_IWOTH 0000002
#define S_IXOTH 0000001
#endif

#ifndef F_RDLCK
#define F_RDLCK 0
#define F_WRLCK 1
#define F_UNLCK 2
#define F_GETLK 5
#define F_SETLK 6
#define F_SETLKW 7
struct flock {
    short l_type;
    short l_whence;
    long long l_start;
    long long l_len;
    int l_pid;
};
static inline int fcntl(int fd, int cmd, ...) { (void)fd; (void)cmd; return 0; }
#endif

#endif /* _WIN32 */
