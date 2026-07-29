/*
 * test/test_endian.c
 *
 * Independent test-vector harness for the clean-room Common/Tcdefs.h and
 * Common/Endian.h/.c replacement. Vectors here were computed by hand /
 * from a plain byte-array reference (see comments per test), NOT derived
 * from or copied against the original TrueCrypt-derived implementation,
 * so a passing run demonstrates correctness against the spec rather than
 * "matches what the old code happened to do."
 *
 * Build & run:
 *   gcc -std=c99 -Wall -Wextra -I.. -o test_endian test_endian.c ../Common/Endian.c
 *   ./test_endian
 */

#include <stdio.h>
#include <string.h>
#include "Common/Endian.h"

static int failures = 0;

#define CHECK(cond, desc) \
	do { \
		if (!(cond)) { \
			printf("FAIL: %s\n", desc); \
			failures++; \
		} else { \
			printf("ok:   %s\n", desc); \
		} \
	} while (0)

int main(void)
{
	/* ---- BYTE_ORDER/LITTLE_ENDIAN/BIG_ENDIAN must be real, distinct,
	   defined macros -- NOT just derivable from LE*/BE* above.
	   Whirlpool.c and blake2s.c test `#if BYTE_ORDER == ...` directly; if
	   these are left undefined, that evaluates as `0 == 0` (true) for
	   *every* comparison, silently taking the wrong branch on our actual
	   little-endian targets. This exact regression has happened twice
	   already during rewrites of this header -- see AUDIT.md -- so this
	   is a compile-time #error, not just a runtime CHECK, precisely so a
	   future rewrite that drops these three lines fails the build instead
	   of failing silently in the field. ---- */
#if !defined(BYTE_ORDER) || !defined(LITTLE_ENDIAN) || !defined(BIG_ENDIAN)
#error "BYTE_ORDER/LITTLE_ENDIAN/BIG_ENDIAN missing from Common/Endian.h -- see the comment right above this #error, and AUDIT.md"
#endif
	CHECK(BYTE_ORDER == LITTLE_ENDIAN, "BYTE_ORDER == LITTLE_ENDIAN on this target");
	CHECK(LITTLE_ENDIAN != BIG_ENDIAN, "LITTLE_ENDIAN and BIG_ENDIAN are distinct values");

	/* ---- MirrorBytes16: 0x1234 -> 0x3412 (swap the two bytes) ---- */
	CHECK(MirrorBytes16(0x1234) == 0x3412, "MirrorBytes16(0x1234) == 0x3412");
	CHECK(MirrorBytes16(0x0000) == 0x0000, "MirrorBytes16(0x0000) == 0x0000");
	CHECK(MirrorBytes16(0xFFFF) == 0xFFFF, "MirrorBytes16(0xFFFF) == 0xFFFF");
	CHECK(MirrorBytes16(0x00FF) == 0xFF00, "MirrorBytes16(0x00FF) == 0xFF00");
	CHECK(MirrorBytes16(MirrorBytes16(0xBEEF)) == 0xBEEF, "MirrorBytes16 is its own inverse (0xBEEF)");

	/* ---- MirrorBytes32: byte-reverse 0x12 34 56 78 -> 0x78 56 34 12 ---- */
	CHECK(MirrorBytes32(0x12345678UL) == 0x78563412UL, "MirrorBytes32(0x12345678) == 0x78563412");
	CHECK(MirrorBytes32(0x00000001UL) == 0x01000000UL, "MirrorBytes32(0x00000001) == 0x01000000");
	CHECK(MirrorBytes32(0xDEADBEEFUL) == 0xEFBEADDEUL, "MirrorBytes32(0xDEADBEEF) == 0xEFBEADDE");
	CHECK(MirrorBytes32(MirrorBytes32(0x01234567UL)) == 0x01234567UL, "MirrorBytes32 is its own inverse (0x01234567)");

	/* ---- MirrorBytes64: byte-reverse 01 23 45 67 89 AB CD EF ---- */
	CHECK(MirrorBytes64(0x0123456789ABCDEFULL) == 0xEFCDAB8967452301ULL,
	      "MirrorBytes64(0x0123456789ABCDEF) == 0xEFCDAB8967452301");
	CHECK(MirrorBytes64(0x0000000000000001ULL) == 0x0100000000000000ULL,
	      "MirrorBytes64(1) == 0x0100000000000000");
	CHECK(MirrorBytes64(MirrorBytes64(0xCAFEBABEDEADBEEFULL)) == 0xCAFEBABEDEADBEEFULL,
	      "MirrorBytes64 is its own inverse (0xCAFEBABEDEADBEEF)");

	/* ---- LE-macros vs BE-macros on a little-endian Android build:
	   LE is identity, BE matches MirrorBytes ---- */
	CHECK(LE32(0x12345678UL) == 0x12345678UL, "LE32 is identity");
	CHECK(BE32(0x12345678UL) == MirrorBytes32(0x12345678UL), "BE32 == MirrorBytes32");
	CHECK(LE64(0x0123456789ABCDEFULL) == 0x0123456789ABCDEFULL, "LE64 is identity");
	CHECK(BE64(0x0123456789ABCDEFULL) == MirrorBytes64(0x0123456789ABCDEFULL), "BE64 == MirrorBytes64");

	/* ---- mput-macros / mget-macros round trip, independent of the mirror functions ---- */
	{
		unsigned char buf[32];
		unsigned char *p = buf;
		const unsigned char *g;

		mputByte(p, 0xAB);
		mputWord(p, 0x1234);
		mputLong(p, 0xDEADBEEFUL);
		mputInt64(p, 0x0011223344556677ULL);
		CHECK((p - buf) == (1 + 2 + 4 + 8), "mput* advanced the pointer by 15 bytes total");

		/* Big-endian-on-the-wire layout check, byte by byte. */
		CHECK(buf[0] == 0xAB, "mputByte wrote 0xAB");
		CHECK(buf[1] == 0x12 && buf[2] == 0x34, "mputWord wrote big-endian 0x1234");
		CHECK(buf[3] == 0xDE && buf[4] == 0xAD && buf[5] == 0xBE && buf[6] == 0xEF,
		      "mputLong wrote big-endian 0xDEADBEEF");
		CHECK(buf[7] == 0x00 && buf[8] == 0x11 && buf[9] == 0x22 && buf[10] == 0x33 &&
		      buf[11] == 0x44 && buf[12] == 0x55 && buf[13] == 0x66 && buf[14] == 0x77,
		      "mputInt64 wrote big-endian 0x0011223344556677");

		g = buf;
		CHECK(mgetByte(g) == 0xAB, "mgetByte reads back 0xAB");
		CHECK(mgetWord(g) == 0x1234, "mgetWord reads back 0x1234");
		CHECK(mgetLong(g) == 0xDEADBEEFUL, "mgetLong reads back 0xDEADBEEF");
		CHECK(mgetInt64(g) == 0x0011223344556677ULL, "mgetInt64 reads back 0x0011223344556677");
		CHECK((g - buf) == (1 + 2 + 4 + 8), "mget* advanced the pointer by 15 bytes total");
	}

	/* ---- mputBytes round trip of a raw block ---- */
	{
		unsigned char src[5] = { 1, 2, 3, 4, 5 };
		unsigned char buf[5];
		unsigned char *p = buf;
		mputBytes(p, src, sizeof(src));
		CHECK(memcmp(buf, src, sizeof(src)) == 0, "mputBytes copies the block verbatim");
		CHECK((p - buf) == 5, "mputBytes advances the pointer by len");
	}

	/* ---- burn() actually zeroes memory ---- */
	{
		unsigned char secret[16];
		int i;
		for (i = 0; i < 16; i++) secret[i] = (unsigned char) (0xA0 + i);
		burn(secret, sizeof(secret));
		{
			int all_zero = 1;
			for (i = 0; i < 16; i++) if (secret[i] != 0) all_zero = 0;
			CHECK(all_zero, "burn() zeroes every byte of the buffer");
		}
	}

	/* ---- Twofish-key-schedule-shaped usage: reading a 256-bit key as
	   eight LE32 32-bit words must round-trip against a plain memcpy
	   reference, matching how Twofish.c's twofish_set_key() consumes
	   the key material via LE32(in_key[i]). ---- */
	{
		unsigned char key[32];
		uint32_t words[8], ref[8];
		int i;
		for (i = 0; i < 32; i++) key[i] = (unsigned char) (i * 7 + 1);
		memcpy(words, key, sizeof(words));
		for (i = 0; i < 8; i++) ref[i] = LE32(words[i]);
		/* On a little-endian host, LE32 must be a no-op, so ref[] must
		   equal a byte-for-byte little-endian reconstruction done here
		   independently of the header under test. */
		for (i = 0; i < 8; i++)
		{
			uint32_t expect = (uint32_t) key[4*i] | ((uint32_t) key[4*i+1] << 8) |
			                  ((uint32_t) key[4*i+2] << 16) | ((uint32_t) key[4*i+3] << 24);
			CHECK(ref[i] == expect, "LE32 word read matches independent little-endian reconstruction");
		}
	}

	printf("\n%s (%d failure%s)\n", failures == 0 ? "ALL TESTS PASSED" : "TESTS FAILED",
	       failures, failures == 1 ? "" : "s");
	return failures == 0 ? 0 : 1;
}
