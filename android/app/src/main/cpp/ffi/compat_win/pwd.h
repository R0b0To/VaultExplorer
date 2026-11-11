// Windows stand-in for <pwd.h>: ntfs-3g's uid/gid <-> SID mapping looks users up here, and on Windows the
// answer is always "no such user" (the engine mounts with a fixed ownership instead).
#pragma once
struct passwd {
    char* pw_name;
    char* pw_passwd;
    unsigned int pw_uid;
    unsigned int pw_gid;
    char* pw_gecos;
    char* pw_dir;
    char* pw_shell;
};
static inline struct passwd* getpwuid(unsigned int uid) { (void)uid; return 0; }
static inline struct passwd* getpwnam(const char* name) { (void)name; return 0; }
