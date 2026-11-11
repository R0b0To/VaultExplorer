// Windows stand-in for <termios.h>. Only dislocker's interactive password prompt (xstd/xstdio.c, user_pass.c)
// refers to it, to switch terminal echo off; the engine never calls that prompt (the password always arrives
// as an argument), so the calls report "no terminal" and everything compiles unchanged.
#pragma once
typedef unsigned int tcflag_t;
typedef unsigned char cc_t;
#define NCCS 32
struct termios {
    tcflag_t c_iflag, c_oflag, c_cflag, c_lflag;
    cc_t c_cc[NCCS];
};
#define ECHO 0x0008u
#define ICANON 0x0002u
#define VMIN 6
#define VTIME 5
#define TCSANOW 0
#define TCSAFLUSH 2
static inline int tcgetattr(int fd, struct termios* t) { (void)fd; (void)t; return -1; }
static inline int tcsetattr(int fd, int when, const struct termios* t) { (void)fd; (void)when; (void)t; return -1; }
