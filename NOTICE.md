# Third-party components

Vault Explorer itself is licensed under the GNU General Public License v3.0
(see LICENSE).

This covers two different kinds of dependency, checked differently:

- **Native code compiled directly into `libvaultexplorer.so`** (the
  `android/app/src/main/cpp` tree) must be GPL-compatible, because it
  becomes part of one combined binary work.
- **Flutter/Dart packages** (`pubspec.yaml`) are linked at the Dart/Flutter
  level, mostly calling into their own separately-compiled native code
  (e.g. via platform channels or FFI) rather than being compiled into
  `libvaultexplorer.so` itself. They still all need to be genuinely free
  software for the F-Droid "all bundled code must be free software"
  requirement, and for the project's own GPLv3 claim to mean what it says,
  even where the GPL's linking rules are looser than for the native code
  above.

All entries below were checked directly against upstream sources/licenses
(not just pub.dev's summary badge or a repo's README claim).

## Native (`cpp/`) -- compiled into `libvaultexplorer.so`

| Component | Upstream | License | Pinned | Status |
|---|---|---|---|---|
| mbedTLS | Mbed-TLS/mbedtls | Apache-2.0 OR GPL-2.0-or-later (dual, since 3.6.0) | 2ca6c285 (v3.6.0) | OK |
| ChaN's FatFs | stm32duino/FatFs | 1-clause-BSD-equivalent custom notice | cef1acad (4.0.4) | OK |
| NTFS-3G (libntfs-3g + ntfsprogs) | tuxera/ntfs-3g | GPL-2.0-or-later | d327833e | OK |
| e2fsprogs -- `lib/ext2fs`, `lib/e2p` (the only e2fsprogs code this build compiles) | tytso/e2fsprogs | **LGPL-2.0** per upstream `NOTICE`, confirmed in file headers (`lib/ext2fs/ext2fs.h`, `alloc.c`, etc: *"redistributed under the terms of the GNU Library General Public License, version 2"*). `lib/uuid` is BSD-3-Clause, `lib/et`/`lib/ss` are MIT. | 7ee1d505 (v1.47.4) | OK -- LGPL permits linking into a differently-licensed binary |
| dislocker (BitLocker) | Aorimn/dislocker | GPL-2.0-or-later | 38dab031 | OK |
| cJSON | DaveGamble/cJSON | MIT | acc76239 (v1.7.18) | OK |
| Oboe | google/oboe | Apache-2.0 | a81bb9f8 (1.10.0) | OK |
| AndroidX DocumentFile | androidx.documentfile | Apache-2.0 | via Gradle | OK |
| VeraCrypt crypto primitives -- `Twofish.c`, `Serpent.c`, `Camellia.c`, `kuznyechik.c`, `Whirlpool.c`, `blake2s.c`, `cpu.c`, Argon2 | veracrypt/VeraCrypt | Per-file permissive: Twofish (Gladman permissive), Serpent/Whirlpool/kuznyechik/cpu.c (public domain), Camellia (BSD-2-clause/NTT), blake2/Argon2 (CC0 or Apache-2.0, at your option) | d26216c2 (1.26.29) | OK, individually |
| `Common/Tcdefs.h` and `Common/Endian.c`/`Common/Endian.h` | project contributors (clean-room; no longer sourced from veracrypt/VeraCrypt) | GPL-3.0-or-later, matching this project's own LICENSE | n/a -- written in-repo, see `cpp/Common/AUDIT.md` | **OK -- see `cpp/Common/AUDIT.md` for two rewrite regressions found & fixed here** |

**FFmpeg has been removed entirely** (previously vendored/built from source
by `scripts/build_ffmpeg_android.sh`; video playback is now handled by the
`video_player` Flutter plugin below instead). If ffmpeg is ever
reintroduced, re-add its row here and re-verify the build script this
notice used to reference no longer exists in this repo.

## Flutter/Dart (`pubspec.yaml`)

| Package | License | Notes |
|---|---|---|
| `video_player` | BSD-3-Clause | Official Flutter plugin. On Android, backed by AndroidX Media3/ExoPlayer (Apache-2.0), which decodes via the OS's own `MediaCodec` -- no bundled codec binaries of any kind. |
| `pdfrx` | MIT | Built on PDFium (Apache-2.0, Google/Chromium). Genuinely free software, no commercial/community-license gate -- a real fix over the two packages below. |
| `path_provider`, `local_auth`, `flutter_secure_storage`, `url_launcher`, `wakelock_plus`, `package_info_plus`, `sensors_plus`, `flutter_staggered_grid_view`, `archive`, `path`, `vector_math`, `flutter_launcher_icons` | BSD-3-Clause / MIT (each individually) | Standard Flutter-community/AOSP-adjacent packages. No proprietary or copyleft-incompatible terms. |
| `pointycastle`, `encrypt` | BSD-3-Clause / MIT | Pure-Dart crypto libraries (`encrypt` wraps `pointycastle`). |

**Removed, and why:**
- **`fvp`** (was: video playback). BSD-3-Clause itself, but it's a thin
  wrapper around `libmdk` ("mdk-sdk"), which is a **prebuilt, closed-source,
  license-key-gated binary SDK** downloaded from a third party at build
  time -- proprietary software, not free software, regardless of there
  being a no-cost tier for Flutter apps. It also bundles its own opaque
  FFmpeg build internally, so removing FFmpeg from this project and adding
  `fvp` would have net *reintroduced* an FFmpeg dependency with less
  visibility into it than the from-source build this project used to have.
- **`syncfusion_flutter_pdfviewer`, `syncfusion_flutter_pdf`** (were: PDF
  viewing). Proprietary. Usable only under a paid commercial license or
  Syncfusion's "Community License," which is conditioned on the licensee
  having under $1M annual revenue, under 5 developers, and under 10 total
  employees -- a legal eligibility gate, not a price tag. A GPLv3 project
  depending on a revenue/headcount-gated SDK is incoherent as free
  software: anyone exercising their GPLv3 right to fork and rebuild this
  repo would also need to independently qualify for or purchase that
  license. Replaced by `pdfrx`, above.

**Known residual item, not a license problem:** `pdfrx` (via
`pdfium_dart`/`pdfium_flutter`) downloads a **prebuilt PDFium binary** at
build time on every platform including Android, rather than building
PDFium from source. Unlike the two removed packages above, this is not a
proprietary-license issue -- PDFium's own license is clean (Apache-2.0) --
it's the same category of concern the original vendored FFmpeg had before
this project switched to building it from source: F-Droid's "build
everything from source" inclusion policy, not GPL/free-software status.
Building PDFium from source yourself is a much heavier lift than FFmpeg
was (Chromium's own GN/depot_tools build system, multi-hour CI, gigabytes
of toolchain), so treat this as "verify F-Droid's current stance on
PDFium-based apps before submission," not as a blocker on the level the
two removed packages were.

## Distribution notes

- All GPL/LGPL native components are built from their original, unmodified
  upstream source at the pinned commit via CMake `FetchContent`
  (`android/app/src/main/cpp/CMakeLists.txt`) -- nothing is shipped as a
  prebuilt binary in the native (`cpp/`) part of this repository,
  satisfying GPL "source availability" and F-Droid's "buildable from
  source" requirement simultaneously.
- If you fork this project and modify any GPL-licensed component in place,
  you must publish your modified source per the GPL's terms.
