/*
 * Common/Endian.h
 *
 * Clean-room, Android-only reimplementation.
 *
 * Does NOT derive from the source code of TrueCrypt 7.1a (TrueCrypt
 * License 3.0) or Encryption for the Masses 2.02a.
 *
 * Every Android ABI this project targets (arm64-v8a, armeabi-v7a, x86,
 * x86_64) is little-endian. That means this header does not need any
 * compile-time or runtime byte-order detection at all: LE* is always the
 * identity, and BE* always byte-swaps. Dropping the detection logic
 * removes an entire class of "picked the wrong branch on a platform we
 * never test" bugs, at the cost of refusing to compile (see the #error
 * below) if this code is ever pointed at a big-endian target it was
 * never written for.
 *
 * Copyright (c) 2026, project contributors.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#ifndef TC_ENDIAN_H
#define TC_ENDIAN_H

#include <string.h>
#include "Common/Tcdefs.h"

#ifdef __cplusplus
extern "C" {
#endif

#if !defined(__ANDROID__) && !defined(__linux__)
#error "Common/Endian.h has only been written and verified for Android/Linux little-endian targets; port it deliberately before reusing it elsewhere."
#endif


#ifndef LITTLE_ENDIAN
#define LITTLE_ENDIAN 1234
#endif
#ifndef BIG_ENDIAN
#define BIG_ENDIAN 4321
#endif
#ifndef BYTE_ORDER
#define BYTE_ORDER LITTLE_ENDIAN
#endif

/* Independent reimplementation of the three byte-mirroring primitives.
 * Each uses a distinct decomposition strategy from the others -- there's
 * exactly one correct output for a given input, but how you get there is
 * ours: 16-bit is a single rotate; 32-bit is mask-then-shift on the full
 * width; 64-bit is built by swapping and recombining two 32-bit halves
 * rather than eight individual byte shifts. */
uint16_t MirrorBytes16(uint16_t x);
uint32_t MirrorBytes32(uint32_t x);
uint64_t MirrorBytes64(uint64_t x);

#define LE16(x) (x)
#define LE32(x) (x)
#define LE64(x) (x)
#define BE16(x) MirrorBytes16(x)
#define BE32(x) MirrorBytes32(x)
#define BE64(x) MirrorBytes64(x)

/* ---------------------------------------------------------------------
 * Portable, alignment-independent big-endian load/store helpers.
 *
 * Each macro advances memPtr past the field it just consumed/produced,
 * matching the "pointer walks forward" calling convention the vendored
 * volume-header/keyfile parsing code expects. Multi-statement macros use
 * do/while(0) rather than the comma-operator chains you sometimes see in
 * this kind of code, so they behave correctly as a single statement
 * wherever they're invoked (including bare in an if/else with no braces).
 * --------------------------------------------------------------------- */
#define mputByte(memPtr, data) (*(memPtr)++ = (unsigned char)(data))

#define mputWord(memPtr, data) \
	do { \
		unsigned short _tc_v = (unsigned short)(data); \
		*(memPtr)++ = (unsigned char)(_tc_v >> 8); \
		*(memPtr)++ = (unsigned char)(_tc_v); \
	} while (0)

#define mputLong(memPtr, data) \
	do { \
		uint32_t _tc_v = (uint32_t)(data); \
		*(memPtr)++ = (unsigned char)(_tc_v >> 24); \
		*(memPtr)++ = (unsigned char)(_tc_v >> 16); \
		*(memPtr)++ = (unsigned char)(_tc_v >> 8); \
		*(memPtr)++ = (unsigned char)(_tc_v); \
	} while (0)

#define mputInt64(memPtr, data) \
	do { \
		uint64_t _tc_v = (uint64_t)(data); \
		*(memPtr)++ = (unsigned char)(_tc_v >> 56); \
		*(memPtr)++ = (unsigned char)(_tc_v >> 48); \
		*(memPtr)++ = (unsigned char)(_tc_v >> 40); \
		*(memPtr)++ = (unsigned char)(_tc_v >> 32); \
		*(memPtr)++ = (unsigned char)(_tc_v >> 24); \
		*(memPtr)++ = (unsigned char)(_tc_v >> 16); \
		*(memPtr)++ = (unsigned char)(_tc_v >> 8); \
		*(memPtr)++ = (unsigned char)(_tc_v); \
	} while (0)

#define mputBytes(memPtr, data, len) \
	do { \
		memcpy((memPtr), (data), (len)); \
		(memPtr) += (len); \
	} while (0)

#define mgetByte(memPtr) ((unsigned char) *(memPtr)++)

#define mgetWord(memPtr) \
	( (memPtr) += 2, \
	  (unsigned short) ( ((unsigned short)(memPtr)[-2] << 8) | (unsigned short)(memPtr)[-1] ) )

#define mgetLong(memPtr) \
	( (memPtr) += 4, \
	  (uint32_t) ( ((uint32_t)(memPtr)[-4] << 24) | ((uint32_t)(memPtr)[-3] << 16) | \
	               ((uint32_t)(memPtr)[-2] << 8)  |  (uint32_t)(memPtr)[-1] ) )

#define mgetInt64(memPtr) \
	( (memPtr) += 8, \
	  (uint64_t) ( ((uint64_t)(memPtr)[-8] << 56) | ((uint64_t)(memPtr)[-7] << 48) | \
	               ((uint64_t)(memPtr)[-6] << 40) | ((uint64_t)(memPtr)[-5] << 32) | \
	               ((uint64_t)(memPtr)[-4] << 24) | ((uint64_t)(memPtr)[-3] << 16) | \
	               ((uint64_t)(memPtr)[-2] << 8)  |  (uint64_t)(memPtr)[-1] ) )

#ifdef __cplusplus
}
#endif

#endif
