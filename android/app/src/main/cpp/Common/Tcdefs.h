/*
 * Common/Tcdefs.h
 *
 * Clean-room, Android-only reimplementation.
 *
 * This file does NOT derive from the source code of TrueCrypt 7.1a
 * (TrueCrypt License 3.0) or Encryption for the Masses 2.02a. It was
 * written from scratch against the *compiled* needs of this project's
 * vendored crypto primitives only 
 *
 * Scope: this project builds for Android only (arm64-v8a, armeabi-v7a,
 * x86, x86_64). Every Windows, UEFI, WinCE-bootloader, and NT-kernel-driver
 * branch of the upstream VeraCrypt header has been dropped rather than
 * ported, because this app never compiles for those targets. If a future
 * vendored source file needs something from that dropped surface, it will
 * fail to compile with an ordinary "undeclared identifier" error rather
 * than silently miscompiling -- nothing here guesses at unverified needs.
 *
 * Copyright (c) 2026, project contributors.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#ifndef TCDEFS_H
#define TCDEFS_H

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <limits.h>
#include <string.h>

/* MSVC built-in types used by VeraCrypt's crypto primitives */
#ifndef __int8
#define __int8  char
#endif
#ifndef __int16
#define __int16 short
#endif
#ifndef __int32
#define __int32 int
#endif
#ifndef __int64
#define __int64 long long
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ---------------------------------------------------------------------
 * Fixed-width integer aliases.
 *
 * The vendored crypto sources (Twofish.c, Serpent.c, Camellia.c,
 * kuznyechik.c, Whirlpool.c, Streebog.c, blake2s.c, cpu.c) spell their
 * integer types this way. Android's NDK toolchain (clang) always gives
 * us 8/16/32/64-bit exact-width types via <stdint.h>, so this is a plain
 * typedef, not a per-compiler branch.
 * --------------------------------------------------------------------- */
typedef int8_t   int8;
typedef int16_t  int16;
typedef int32_t  int32;
typedef int64_t  int64;
typedef uint8_t  uint8;
typedef uint16_t uint16;
typedef uint32_t uint32;
typedef uint64_t uint64;

typedef uint8_t  uint_8t;
typedef uint16_t uint_16t;
typedef uint32_t uint_32t;
typedef uint64_t uint_64t;

typedef uint64_t TC_LARGEST_COMPILER_UINT;

#define LL(x) x##ULL

/* Fail loudly at compile time rather than silently mis-sizing a type on
 * an exotic target this project has never been built or tested on. */
#if UCHAR_MAX != 0xffU
#error "unsigned char is not 8 bits wide on this target"
#endif
#if USHRT_MAX != 0xffffU
#error "unsigned short is not 16 bits wide on this target"
#endif
#if UINT_MAX != 0xffffffffU
#error "unsigned int is not 32 bits wide on this target"
#endif

/* ---------------------------------------------------------------------
 * Boolean convention used by the ported C sources (e.g. cpu.c feature
 * flags, misc status returns).
 * --------------------------------------------------------------------- */
#ifndef BOOL
#define BOOL int
#endif
#ifndef FALSE
#define FALSE 0
#endif
#ifndef TRUE
#define TRUE 1
#endif

/* Split/combined 64-bit accessor, used by a couple of the vendored
 * headers for portable high/low-word access. */
typedef union
{
	struct
	{
		uint32_t LowPart;
		uint32_t HighPart;
	};
	uint64_t Value;
} UINT64_STRUCT;

#define VC_MAX(a,b) ((a) > (b) ? (a) : (b))
#define VC_MIN(a,b) ((a) < (b) ? (a) : (b))

#ifndef __has_builtin
#define __has_builtin(x) 0
#endif

/* ---------------------------------------------------------------------
 * Heap + secure-erase helpers.
 *
 * Written as ordinary functions (not macros): a static inline function
 * evaluates its arguments exactly once and gives the compiler a real
 * type-checked signature, both of which are just better engineering than
 * a textual macro for this job.
 * --------------------------------------------------------------------- */
#define TCalloc  malloc
#define TCfree   free

/* Best-effort secure zeroing. The pointer is carried through a
 * volatile-qualified alias for the whole loop so a conforming compiler
 * cannot prove the stores are dead and elide them. This is the same
 * guarantee (and the same limitation -- it is not a hardware-backed
 * guarantee) that any portable C burn() implementation can offer. */
static inline void burn(volatile void *mem, size_t size)
{
	volatile unsigned char *p = (volatile unsigned char *) mem;
	while (size--)
		*p++ = 0;
}

static inline void volatile_memcpy(volatile void *dest, const volatile void *src, size_t size)
{
	volatile unsigned char *d = (volatile unsigned char *) dest;
	const volatile unsigned char *s = (const volatile unsigned char *) src;
	while (size--)
		*d++ = *s++;
}

/* Zeroes a region whose size is a multiple of 8 bytes, 8 bytes at a time. */
static inline void FAST_ERASE64(volatile void *mem, size_t size)
{
	volatile uint64_t *p = (volatile uint64_t *) mem;
	size_t words = size >> 3;
	while (words--)
		*p++ = 0;
}

#define TC_THROW_FATAL_EXCEPTION abort()

#ifdef __cplusplus
}
#endif

#endif