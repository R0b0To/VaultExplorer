// Windows stand-in for <grp.h>: ntfs-3g's uid/gid <-> SID mapping looks groups up here; on Windows the
// answer is always "no such group".
#pragma once
struct group {
    char* gr_name;
    char* gr_passwd;
    unsigned int gr_gid;
    char** gr_mem;
};
static inline struct group* getgrgid(unsigned int gid) { (void)gid; return 0; }
static inline struct group* getgrnam(const char* name) { (void)name; return 0; }
