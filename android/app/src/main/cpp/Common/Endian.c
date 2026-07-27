/*
 * Common/Endian.c
 *
 * Clean-room, Android-only reimplementation.
 *
 * Does NOT derive from the source code of TrueCrypt 7.1a (TrueCrypt
 * License 3.0) or Encryption for the Masses 2.02a.
 *
 * Copyright (c) 2026, project contributors.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "Tcdefs.h"
#include "Common/Endian.h"

uint16_t MirrorBytes16(uint16_t x)
{
	/* Single rotate-by-8 covers the whole 16-bit swap in one step. */
	return (uint16_t) ((x >> 8) | (x << 8));
}

uint32_t MirrorBytes32(uint32_t x)
{
	/* Mask each byte lane out to its home position, then OR the four
	 * lanes back together -- no intermediate "n" accumulator, unlike a
	 * byte-at-a-time build-up. */
	return  ((x & 0x000000FFu) << 24) |
	        ((x & 0x0000FF00u) << 8)  |
	        ((x & 0x00FF0000u) >> 8)  |
	        ((x & 0xFF000000u) >> 24);
}

uint64_t MirrorBytes64(uint64_t x)
{
	/* Split into two 32-bit halves, mirror each half independently with
	 * the primitive above, then swap the halves' positions when
	 * recombining. Four masks touch each half instead of eight touching
	 * the full 64 bits, and there's no shared running accumulator
	 * between the two halves. */
	uint32_t hi = MirrorBytes32((uint32_t) (x >> 32));
	uint32_t lo = MirrorBytes32((uint32_t) (x & 0xFFFFFFFFu));
	return ((uint64_t) lo << 32) | (uint64_t) hi;
}
