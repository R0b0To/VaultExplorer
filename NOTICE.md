# Third-party components

Vault Explorer itself is licensed under the GNU General Public License v3.0
(see LICENSE).

This covers three different kinds of dependency, checked differently:

- **Native code compiled directly into `libvaultexplorer.so`** (the
  `android/app/src/main/cpp` tree) must be GPL-compatible, because it
  becomes part of one combined binary work.
- **AndroidX/Gradle dependencies** (`android/app/build.gradle.kts`) are
  separately-compiled Kotlin/Java libraries pulled in at build time --
  not compiled into `libvaultexplorer.so` -- used for native platform
  views (PDF, video/camera) and SAF file access.
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
| mbedTLS | Mbed-TLS/mbedtls | Apache-2.0 OR GPL-2.0-or-later (dual, since 3.6.0) | 068ff080 (v3.6.7; was v3.6.0, same LTS branch) | OK |
| libavif & libgav1 | AOMediaCodec/libavif, chromium/libgav1 | BSD-2-Clause / Apache-2.0 | c5240fc7 / c05bf9be | OK |
| ChaN's FatFs | stm32duino/FatFs | 1-clause-BSD-equivalent custom notice | cef1acad (4.0.4) | OK |
| NTFS-3G (libntfs-3g + ntfsprogs) | tuxera/ntfs-3g | GPL-2.0-or-later | d327833e | OK |
| e2fsprogs -- `lib/ext2fs`, `lib/e2p` | tytso/e2fsprogs | LGPL-2.0 | 7ee1d505 (v1.47.4) | OK |
| dislocker (BitLocker) | Aorimn/dislocker | GPL-2.0-or-later | 38dab031 | OK |
| cJSON | DaveGamble/cJSON | MIT | acc76239 (v1.7.18) | OK |
| libarchive (archive/ZIP/7-Zip/RAR/TAR browser engine, `archive/`) | libarchive/libarchive | BSD-2-Clause | 27cbc782 (v3.8.9) | OK |
| bzip2 (libarchive filter) | libarchive/bzip2 | bzip2 license (BSD-style permissive) | tag `bzip2-1.0.8` | OK |
| xz / liblzma (libarchive filter) | tukaani-project/xz | 0BSD | 4b73f2ec (v5.8.3) | OK |
| zstd (libarchive filter) | facebook/zstd | BSD-3-Clause OR GPL-2.0-or-later (dual, at your option) | f8745da6 (v1.5.7) | OK |
| BoringSSL (AES-256 ZIP / RAR5 passphrase support for libarchive) | google/boringssl | ISC (new code) + OpenSSL License/SSLeay License (ported OpenSSL code) -- all permissive | ef0c0723 | OK |
| VeraCrypt crypto primitives -- `Twofish.c`, `Serpent.c`, `Camellia.c`, `kuznyechik.c`, `Whirlpool.c`, `blake2s.c`, `cpu.c`, Argon2 | veracrypt/VeraCrypt | Per-file permissive: Twofish (Gladman permissive), Serpent/Whirlpool/kuznyechik/cpu.c (public domain), Camellia (BSD-2-clause/NTT), blake2/Argon2 (CC0 or Apache-2.0, at your option) | d26216c2 (1.26.29) | OK, individually |
| `Common/Tcdefs.h` and `Common/Endian.c`/`Common/Endian.h` | project contributors (clean-room; no longer sourced from veracrypt/VeraCrypt) | GPL-3.0-or-later, matching this project's own LICENSE | n/a -- written in-repo, host-tested via `cpp/Common/test/test_endian.c` | OK |

Archive-engine note: `archive/archive_engine.cpp` (this project's own libarchive
wrapper, GPLv3-or-later like the rest of the project) replaces the pure-Dart
`archive` package as the actual ZIP/7-Zip/RAR/TAR/gzip/bzip2/xz/zstd browsing
mechanism -- see the Flutter/Dart table below for `archive`'s narrower
remaining role.

## AndroidX/Gradle (`android/app/build.gradle.kts`)

PDF and video/camera viewing were moved off Flutter plugins (`pdfrx`,
`video_player`) and onto native Kotlin platform views backed directly by
these AndroidX/Jetpack libraries, so they're audited here instead of under
Flutter/Dart below. All are decoded via the OS's own `MediaCodec`/PDF
renderer -- no bundled codec or PDF-parsing binaries of any kind, and
nothing unencrypted is written to disk; content streams from the vault
engine straight into these views.

| Component | License | Notes |
|---|---|---|
| `androidx.documentfile:documentfile` | Apache-2.0 | Backs the "Open in other apps" SAF integration and directory-vault access. |
| `androidx.media3:media3-exoplayer`, `-ui`, `-session`, `-datasource` (1.11.0) | Apache-2.0 | Native video/audio playback, replacing the Flutter `video_player` plugin. |
| `androidx.pdf:pdf-viewer-fragment`, `:pdf-core` (1.0.0-alpha19) | Apache-2.0 | Jetpack PDF viewer, replacing the Flutter `pdfrx` plugin. Alpha API, pinned version. |
| `com.google.android.material:material` (1.13.0) | Apache-2.0 | Material Components for the native platform-view UI. |
| `androidx.exifinterface:exifinterface` (1.3.7) | Apache-2.0 | EXIF metadata reading for photos inside a vault. |

## Flutter/Dart (`pubspec.yaml`)

| Package | License | Notes |
|---|---|---|
| `intl`, `path_provider`, `local_auth`, `path`, `meta` | BSD-3-Clause | Official Flutter-team / Dart-team packages. |
| `flutter_staggered_grid_view` | MIT | Masonry file-explorer view. |
| `dynamic_color` | Apache-2.0 | Material You theming. |
| `material_ui` | BSD-3-Clause | Official Flutter-team Material widget library, decoupled from the `flutter` SDK into its own pub.dev package as of Flutter 3.47; replaces `package:flutter/material.dart` imports project-wide. |
| `flutter_riverpod` | MIT | State management / DI container (Riverpod, by rrousselGit). |
| `riverpod_annotation` | MIT | Annotations consumed by `flutter_riverpod`; no separate codegen at runtime. |

`archive` (MIT) is present only as a transitive/test-time package now -- it
is not a direct `pubspec.yaml` dependency and ships in no release code
path; its one remaining use is in
`test/features/browser/controllers/file_browser_navigation_controller_test.dart`,
which uses it to synthesize a ZIP byte blob as a fixture for testing the
native `ArchiveService`. The actual ZIP/archive-browsing feature is the
native libarchive engine (see the Native table above), not this package.

`flutter_launcher_icons` is a dev-only build tool (generates launcher icon
assets at build time) and ships no code in the release APK, so it isn't
listed above. The same applies to `build_runner`, `riverpod_generator`,
`riverpod_lint` (all MIT, by rrousselGit /
dart-lang / invertase), and to the test-only mocking packages
`path_provider_platform_interface`/`plugin_platform_interface` (both
BSD-3-Clause, official Flutter-team packages): none of these are packaged
into the release binary.

## Distribution notes

- All GPL/LGPL native components are built from their original, unmodified
  upstream source at the pinned commit via CMake `FetchContent`
  (`android/app/src/main/cpp/CMakeLists.txt`) -- nothing is shipped as a
  prebuilt binary in the native (`cpp/`) part of this repository.
- If you fork this project and modify any GPL-licensed component in place,
  you must publish your modified source per the GPL's terms.