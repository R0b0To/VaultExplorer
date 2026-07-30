# Audit: scoping the Tcdefs.h / Endian.h / Endian.c replacement

## Method

Rather than guessing at what a "typical" VeraCrypt build needs, this was
scoped against the actual pinned commit (`d26216c294fdfb090ee856f6195c294176defa1d`,
VeraCrypt 1.26.29):

1. Downloaded the real source tree at that commit
   (`codeload.github.com/veracrypt/VeraCrypt/tar.gz/<commit>`).
2. Starting from the exact 14 files `CMakeLists.txt` compiles --
   `Crypto/{Twofish,Serpent,Camellia,kuznyechik,Whirlpool,Streebog,blake2s,cpu}.c`
   and `Crypto/Argon2/src/{argon2,core,ref,opt_sse2,opt_avx2,blake2/blake2b}.c`
   -- did a textual BFS over `#include "..."` directives, resolving each
   against the same search-dir list CMake actually passes
   (`VC_CRYPTO_DIR`, `VC_SRC_DIR`, `VC_ARGON2_DIR/include`, `VC_ARGON2_DIR/src`,
   plus "same directory as the including file", which always wins for
   quoted includes regardless of `-I` order). This produced 43 local
   headers/sources actually reachable from the real build.
3. Grepped all 43 for `TrueCrypt License` to find every tainted file, not
   just the 3 initially suspected.
4. Grepped the same 43 for every symbol Tcdefs.h/Endian.h could plausibly
   provide (integer typedefs, `LL()`, `BOOL`/`TRUE`/`FALSE`, `burn()`,
   `TC_THROW_FATAL_EXCEPTION`, `MirrorBytes*`, `LE*`/`BE*`, `mput*`/`mget*`,
   `BYTE_ORDER`/`LITTLE_ENDIAN`/`BIG_ENDIAN`, etc.) to get the real usage
   surface rather than porting the whole ~300-line original header.

**Known gap at the time this audit was written:** this was a textual/grep-based
BFS, not a real compiler-driven `-M`/`-MM` preprocessor dependency scan (no
Android NDK toolchain was available to run one in the environment this
audit was done in). Textual BFS can't evaluate `#ifdef` conditions, so it
errs toward *over*-inclusion (dead branches get walked too) rather than
under-inclusion, and every finding below was cross-checked by hand against
the specific `#if` guard it sits in.

**Update:** the project has since been built with a real Android NDK
toolchain and compiles and runs successfully with these replacement files
in place, closing the gap above -- the findings in this document held up
against an actual build, not just the textual analysis.

## Findings: tainted files in the reachable set

| File | Reached via | Resolution |
|---|---|---|
| `Common/Tcdefs.h` | Nearly every compiled file, transitively | Replaced (`Common/Tcdefs.h` in this project) |
| `Common/Endian.h` | Same | Replaced (`Common/Endian.h` in this project) |
| `Common/Endian.c` | Directly compiled by `CMakeLists.txt` | Replaced (`Common/Endian.c` in this project) |
| `Common/Crypto.h` | Only `Camellia.c`, inside `#if CRYPTOPP_BOOL_X64 && !defined(CRYPTOPP_DISABLE_ASM)` (its hand-written x86-64 assembly path) | **Not replaced -- avoided.** `CMakeLists.txt` defines `CRYPTOPP_DISABLE_ASM` (also `CRYPTOPP_DISABLE_SSE2`/`SSSE3`/`SHANI` for the same reason on other paths), so this branch, and everything it pulls in, never compiles. Camellia falls back to its portable C implementation later in the same file. |
| `Crypto/Aes_hw_cpu.h` | Only reachable *through* `Common/Crypto.h` above | Moot once `Common/Crypto.h` is unreachable |

No other file in the 43-file reachable set carries the TrueCrypt License
notice.

## Symbol surface actually required (post CRYPTOPP_DISABLE_ASM)

Grepped directly from the real, non-Windows build surface at the pinned
commit:

- Types: `int8/16/32/64`, `uint8/16/32/64`, `uint_8t/16t/32t/64t`,
  `TC_LARGEST_COMPILER_UINT`, `__int8/16/32/64`
- `LL(x)` (64-bit literal suffix -- heavily used by Whirlpool/Streebog
  S-box table initializers)
- `BOOL` / `TRUE` / `FALSE`
- `TC_NO_COMPILER_INT64` (never defined on this target -- we always have a
  real 64-bit type via `<stdint.h>`)
- `TC_THROW_FATAL_EXCEPTION` (one call site, in `Whirlpool.c`'s
  GCC-4.4.7-workaround branch, which itself only compiles under
  `CRYPTOPP_BOOL_SSE2_ASM_AVAILABLE` -- effectively dead on this target,
  but implemented anyway as `abort()`)
- `BYTE_ORDER`, `LITTLE_ENDIAN`, `BIG_ENDIAN` -- see "Bugs found & fixed"
  below. **This is the single most important entry in this whole table --
  it has been silently dropped twice during rewrites of this header. Do
  not drop it a third time.**
- `MirrorBytes16/32/64`, `LE16/32/64`, `BE16/32/64`
- `mputByte/Word/Long/Int64/Bytes`, `mgetByte/Word/Long/Int64` (grepped as
  unused by the current 14 compiled files, kept anyway for drop-in
  compatibility if more `VC_CRYPTO_DIR` sources get added later)

`VC_MIN`/`VC_MAX`, `UINT64_STRUCT`, `volatile_memcpy`, `FAST_ERASE64`: not
hit by the current 14-file build surface either, kept for the same
future-compatibility reason -- they're trivial and carry no taint risk.

## Bugs found & fixed during this audit

### Bug 1 (2026-07-28): missing BYTE_ORDER macros

The first draft of `Common/Endian.h` defined `LE16/32/64`/`BE16/32/64` but
not `BYTE_ORDER`/`LITTLE_ENDIAN`/`BIG_ENDIAN` themselves. Several vendored
files test those three directly, e.g. `Whirlpool.c`'s `HashMultipleBlocks()`:

```c
#if BYTE_ORDER == BIG_ENDIAN
    WhirlpoolTransform(ctx->state, input);
#else
    CorrectEndianness(dataBuf, input, 64);
    WhirlpoolTransform(ctx->state, dataBuf);
#endif
```

With all three undefined, the preprocessor treats them as `0`, so
`BYTE_ORDER == BIG_ENDIAN` evaluated as `0 == 0` -- true -- taking the
big-endian branch (skipping `CorrectEndianness()`) on our actually
little-endian ABIs. `blake2s.c` has one instance of the same pattern but
happened to land on the correct branch by the same coincidence, purely
because that particular site tests `== LITTLE_ENDIAN` rather than
`== BIG_ENDIAN`.

Fixed by defining all three explicitly (matching the traditional BSD/glibc
`<endian.h>` values: `LITTLE_ENDIAN 1234`, `BIG_ENDIAN 4321`,
`BYTE_ORDER LITTLE_ENDIAN`), so these checks are deterministic instead of
accidental.

### Bug 2 (2026-07-29): the same fix got dropped in a rewrite

`Common/Endian.h`/`.c`/`Tcdefs.h` were later rewritten wholesale (cleaner
`uint16_t`-based types, `do { } while(0)` macros instead of comma-operator
chains -- a real improvement) without carrying Bug 1's fix forward. Same
root cause, same consequence, caught again by re-diffing against this
document rather than by `test_endian.c`, because `test_endian.c` only
exercised `Common/Endian.h`'s own public API (`LE*`/`BE*`/`MirrorBytes*`),
never the three raw macros that `Whirlpool.c` reads directly -- so a
header that's internally self-consistent but missing those three defines
still passed every test in the file.

Fixed the same way, and additionally: `test_endian.c` now has a
`#if !defined(BYTE_ORDER) || !defined(LITTLE_ENDIAN) || !defined(BIG_ENDIAN)`
/ `#error` at the top of `main()`, so a third regression fails the *build*
of the test harness, not just a runtime check someone has to remember to
read the output of. If you regenerate these files again, that `#error`
is the tripwire -- if it fires, this is why.

## CMake wiring bug found & fixed (2026-07-28)

`CMakeLists.txt` compiled `${VC_COMMON_DIR}/Endian.c` (the FetchContent'd,
still-tainted original) instead of this directory's `Endian.c`. CMake
source lists are literal paths, not include-search results, so adding the
replacement files here didn't actually substitute them -- the original
kept compiling successfully right alongside the unused replacement, which
is why the build succeeding wasn't evidence the swap had taken effect.
Fixed by pointing the source list entry at this directory's `Endian.c`
instead (`Common/Endian.c`, resolved relative to `CMAKE_CURRENT_SOURCE_DIR`
by CMake's default source-path handling). Re-verified still correct as of
2026-07-29 -- only one `Endian.c` reference remains in `CMakeLists.txt`.