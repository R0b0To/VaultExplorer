# Third-party components

Vault Explorer itself is licensed under the GNU General Public License v3.0
(see LICENSE). It statically links the components below into a single
native library (`libvaultexplorer.so`); all of them must therefore be
GPL-compatible.

All entries below were checked directly against the actual pinned commits
(not just repo-level README claims) via `raw.githubusercontent.com` on
2026-07-27.

| Component | Upstream | License | Pinned | Status |
|---|---|---|---|---|
| mbedTLS | Mbed-TLS/mbedtls | Apache-2.0 OR GPL-2.0-or-later (dual, since 3.6.0) | 2ca6c285 (v3.6.0) | OK |
| ChaN's FatFs | stm32duino/FatFs | 1-clause-BSD-equivalent custom notice | cef1acad (4.0.4) | OK |
| NTFS-3G (libntfs-3g + ntfsprogs) | tuxera/ntfs-3g | GPL-2.0-or-later | d327833e | OK |
| e2fsprogs -- `lib/ext2fs`, `lib/e2p` (the only e2fsprogs code this build compiles) | tytso/e2fsprogs | **LGPL-2.0** per upstream `NOTICE`, confirmed in file headers (`lib/ext2fs/ext2fs.h`, `alloc.c`, etc: *"redistributed under the terms of the GNU Library General Public License, version 2"*). `lib/uuid` is BSD-3-Clause, `lib/et`/`lib/ss` are MIT. | 7ee1d505 (v1.47.4) | OK -- LGPL permits linking into a differently-licensed binary |
| dislocker (BitLocker) | Aorimn/dislocker | GPL-2.0-or-later | 38dab031 | OK |
| cJSON | DaveGamble/cJSON | MIT | acc76239 (v1.7.18) | OK |
| Oboe | google/oboe | Apache-2.0 | a81bb9f8 (1.10.0) | OK |
| FFmpeg (avcodec/avformat/avutil/swscale/swresample) | ffmpeg.org | LGPL-2.1-or-later -- built here with no `--enable-gpl`/`--enable-nonfree`, no libx264/fdk-aac, dynamically linked as `.so` | 8.1.2, built from source by `scripts/build_ffmpeg_android.sh` | OK |
| AndroidX DocumentFile | androidx.documentfile | Apache-2.0 | via Gradle | OK |
| VeraCrypt crypto primitives -- `Twofish.c`, `Serpent.c`, `Camellia.c`, `kuznyechik.c`, `Whirlpool.c`, `blake2s.c`, `cpu.c`, Argon2 | veracrypt/VeraCrypt | Per-file permissive: Twofish (Gladman permissive), Serpent/Whirlpool/kuznyechik/cpu.c (public domain), Camellia (BSD-2-clause/NTT), blake2/Argon2 (CC0 or Apache-2.0, at your option) | d26216c2 (1.26.29) | OK, individually |
| `Common/Tcdefs.h` and `Common/Endian.c`/`Common/Endian.h` | project contributors (clean-room; no longer sourced from veracrypt/VeraCrypt) | GPL-3.0-or-later, matching this project's own LICENSE | n/a -- written in-repo, see `cpp/Common/AUDIT.md` | **OK -- replaced 2026-07-27** |

## Resolved: `Tcdefs.h` / `Endian.h` / `Endian.c`

The three files above previously compiled the TrueCrypt-License-3.0-tainted
text verbatim into `libvaultexplorer.so` (`CMakeLists.txt` built
`${VC_COMMON_DIR}/Endian.c` directly, and `Common/Tcdefs.h` was transitively
`#include`d by every file under `VC_CRYPTO_DIR`). That has been fixed by
remediation option 2 from the previous version of this notice: a clean-room
reimplementation of exactly the symbols the compiled crypto sources use,
scoped by reading the actual upstream source at the pinned commit (not
guessed), verified against independent test vectors, and wired into the
build via a one-line `CMakeLists.txt` change. See `cpp/Common/AUDIT.md` for
the full scoping methodology, including an explicit note on where a true
compiler-driven `-M`/`-MM` audit wasn't possible in the environment this
rewrite was produced in and what was done in its place.

As a side effect of being Android-only, the replacement also drops:
- All Windows/UEFI/NT-kernel-driver branches of the original header (this
  project never builds for those targets).
- All big-endian byte-order detection logic (every Android ABI this
  project ships for -- `arm64-v8a`, `armeabi-v7a`, `x86`, `x86_64` -- is
  little-endian, so the detection collapsed to a single hard-coded answer,
  with a loud `#error` if that assumption is ever violated).

With this fixed, no remaining bundled component is flagged non-free, so
this repo's GPLv3 LICENSE claim and F-Droid "all bundled code must be free
software" requirement both hold as of this commit.

## Distribution notes

- All GPL/LGPL components are built from their original, unmodified upstream
  source at the pinned commit via CMake `FetchContent`
  (`android/app/src/main/cpp/CMakeLists.txt`) or the dedicated build script
  (`scripts/build_ffmpeg_android.sh`) -- nothing is shipped as a prebuilt
  binary in this repository, satisfying GPL "source availability" and
  F-Droid's "buildable from source" requirement simultaneously.
- If you fork this project and modify any GPL-licensed component in place,
  you must publish your modified source per the GPL's terms.