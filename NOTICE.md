# Third-party components

Vault Explorer itself is licensed under the GNU General Public License v3.0
(see LICENSE).

This covers three different kinds of dependency, checked differently:

- **Native code compiled directly into `libvaultexplorer.so`** (the
  `android/app/src/main/cpp` tree) must be GPL-compatible, because it
  becomes part of one combined binary work.
- **AndroidX/Gradle dependencies** (`android/app/build.gradle.kts`) are
  separately-compiled Kotlin/Java libraries and prebuilt AAR artifacts
  pulled in at build time via Gradle -- not compiled into
  `libvaultexplorer.so` -- used for native platform views (PDF, video/camera,
  audio playback and editing with software decoder fallbacks), background
  work execution (WorkManager), and SAF file access.
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
| libyuv (AVIF color-space conversion/scaling, pulled in transitively) | chromium/libyuv | BSD-3-Clause | 644251f2 -- not pinned by this project's own `CMakeLists.txt`; this is the commit libavif's own `cmake/Modules/LocalLibyuv.cmake` fetches when `AVIF_LIBYUV` is set to `LOCAL` (see below) | OK, added -- was previously missing from this table |
| ChaN's FatFs | stm32duino/FatFs | 1-clause-BSD-equivalent custom notice | cef1acad (4.0.4) | OK |
| NTFS-3G (libntfs-3g + ntfsprogs) | tuxera/ntfs-3g | GPL-2.0-or-later | d327833e | OK |
| e2fsprogs -- `lib/ext2fs`, `lib/e2p` | tytso/e2fsprogs | LGPL-2.0 | 7ee1d505 (v1.47.4) | OK |
| dislocker (BitLocker) | Aorimn/dislocker | GPL-2.0-or-later | 38dab031 | OK |
| cJSON | DaveGamble/cJSON | MIT | acc76239 (v1.7.18) | OK |
| ZXing-C++ (offline QR/barcode decoding, `jni/qr_bridge.cpp`) | zxing-cpp/zxing-cpp | Apache-2.0 | 287c85df (v3.1.1); readers only, writers/examples disabled in `CMakeLists.txt` | OK, added -- was previously missing from this table |
| libarchive (archive/ZIP/7-Zip/RAR/TAR browser engine, `archive/`) | libarchive/libarchive | BSD-2-Clause | 27cbc782 (v3.8.9) | OK |
| bzip2 (libarchive filter) | libarchive/bzip2 | bzip2 license (BSD-style permissive) | tag `bzip2-1.0.8` | OK |
| xz / liblzma (libarchive filter) | tukaani-project/xz | 0BSD | 4b73f2ec (v5.8.3) | OK |
| zstd (libarchive filter) | facebook/zstd | BSD-3-Clause OR GPL-2.0-or-later (dual, at your option) | f8745da6 (v1.5.7) | OK |
| BoringSSL (AES-256 ZIP / RAR5 passphrase support for libarchive) | google/boringssl | ISC (new code) + OpenSSL License/SSLeay License (ported OpenSSL code) -- all permissive | ef0c0723 | OK |
| VeraCrypt crypto primitives -- `Twofish.c`, `Serpent.c`, `Camellia.c`, `kuznyechik.c`, `Whirlpool.c`, `Streebog.c`, `blake2s.c`, `cpu.c`, Argon2 | veracrypt/VeraCrypt | Per-file permissive: Twofish (Gladman permissive), Serpent/Whirlpool/kuznyechik/cpu.c (public domain), Camellia (BSD-2-clause/NTT), Streebog (BSD-2-clause, Alexey Degtyarev), blake2/Argon2 (CC0 or Apache-2.0, at your option) | d26216c2 (1.26.29) | OK, individually |
| `Common/Tcdefs.h` and `Common/Endian.c`/`Common/Endian.h` | project contributors (clean-room; no longer sourced from veracrypt/VeraCrypt) | GPL-3.0-or-later, matching this project's own LICENSE | n/a -- written in-repo. A host test exists at `cpp/Common/test/test_endian.c`, but in this snapshot it does not compile as shipped (a `LE*/BE*` inside a block comment ends the comment early, and the build line in its header needs `-I../..` rather than `-I..`) and it is not registered in CMake or CI | OK |

Archive-engine note: `archive/archive_engine.cpp` (this project's own libarchive
wrapper, GPLv3-or-later like the rest of the project) replaces the pure-Dart
`archive` package as the actual ZIP/7-Zip/RAR/TAR/gzip/bzip2/xz/zstd browsing
mechanism -- see the Flutter/Dart table below for `archive`'s narrower
remaining role.

libyuv note: this project's `CMakeLists.txt` sets `AVIF_LIBYUV` to `LOCAL`
for the libavif build (`android/app/src/main/cpp/CMakeLists.txt`). libavif
does not vendor libyuv itself for that setting -- its own
`cmake/Modules/LocalLibyuv.cmake` runs a further `FetchContent_Declare` for
`chromium.googlesource.com/libyuv/libyuv` at a commit pinned inside *that*
file, and the result is statically linked into `libvaultexplorer.so`. It is
listed here because it ends up in the same combined binary as everything
else in this table, even though no file in this repository names it
directly.

## AndroidX/Gradle (`android/app/build.gradle.kts`)

PDF, video/camera, and audio playback and editing are handled by native Kotlin
platform views and background services backed directly by these AndroidX/Jetpack
and Media3 libraries, audited here instead of under Flutter/Dart below. Media
playback and waveform extraction primarily use the OS's hardware-accelerated
`MediaCodec` and the Jetpack PDF renderer.

To support audio and video formats not universally guaranteed by device chipsets
(such as AC-3, E-AC-3, DTS, or AV1 on older hardware), the player and waveform
extractor integrate `nextlib-media3ext` (`io.github.anilbeesetti:nextlib-media3ext`),
an open-source Media3 extension providing software decoders via FFmpeg and dav1d.
`nextlib` is pulled as a prebuilt AAR from Maven Central containing free-software
native shared libraries built in upstream CI. Content streams directly from
decrypted vault memory straight into these views -- nothing unencrypted is
written to disk.

| Component | License | Notes |
|---|---|---|
| `androidx.work:work-runtime-ktx` (2.12.0) | Apache-2.0 | Powers daily scheduled background vault sync (`ScheduledVaultSyncService` / `ScheduledVaultSyncWorker`). |
| `androidx.documentfile:documentfile` (1.0.1) | Apache-2.0 | Backs the "Open in other apps" SAF integration and directory-vault access. |
| `androidx.media3:media3-exoplayer`, `-ui`, `-session`, `-datasource` (1.11.1) | Apache-2.0 | Native video/audio playback, playlist coordination, and background playback session controls (`VaultMediaPlaybackService`). Pinned version 1.11.1. |
| `androidx.media3:media3-inspector` (1.11.1) | Apache-2.0 | Media track inspection and container parsing used by the audio editor and cutter pipelines. |
| `io.github.anilbeesetti:nextlib-media3ext` (1.11.1-0.16.0) | GPL-3.0 | Media3 extension adding software decoder renderers (`NextRenderersFactory`). Fetched as a prebuilt AAR from Maven Central (see distribution notes below). Source is public at `github.com/anilbeesetti/nextlib`. |
| ↳ `FFmpeg` (bundled in nextlib) | LGPL-3.0-or-later | Built in nextlib CI with `--enable-version3`, without `--enable-gpl` or `--enable-nonfree` (LGPLv3+ configuration). Provides software decoders for AC-3, E-AC-3, DTS, TrueHD, etc. Also directly driven for PCM sample decoding in the audio waveform extractor. |
| ↳ `dav1d` (bundled in nextlib) | BSD-2-Clause | High-performance AV1 video decoder. |
| ↳ `mbedTLS` (bundled in nextlib) | Apache-2.0 OR GPL-2.0-or-later | Cryptographic backend for FFmpeg network/TLS protocols. |
| `androidx.pdf:pdf-viewer-fragment`, `:pdf-core` (1.0.0-alpha19) | Apache-2.0 | Jetpack PDF viewer, replacing the Flutter `pdfrx` plugin. Alpha API, pinned version. |
| `com.google.android.material:material` (1.13.0) | Apache-2.0 | Material Components for the native platform-view UI. |
| `androidx.exifinterface:exifinterface` (1.3.7) | Apache-2.0 | EXIF metadata reading for photos inside a vault. |

### In-repo Media & Decoder Integration Code

The app contains two specialized native Kotlin adapters written to bridge Media3 and nextlib:

- `io.github.anilbeesetti.nextlib.media3ext.ffdecoder.FfmpegPcmDecoder`: In-repo Kotlin class
  placed inside nextlib's package namespace to access its package-private `FfmpegAudioDecoder`.
  Provides non-blocking decode-to-PCM streaming for `AudioWaveformExtractor`, enabling waveform
  generation for AC-3, E-AC-3, and DTS streams on devices lacking hardware codecs.
- `com.aeidolon.vaultexplorer.engine.SeekableAc3Extractor`: In-repo Kotlin extractor wrapper around
  Media3's `Ac3Extractor` that computes a `ConstantBitrateSeekMap` from the first frame's bitrate,
  making raw `.ac3` and `.eac3` elementary streams seekable during in-app playback and audio editing.

## Flutter/Dart (`pubspec.yaml`)

| Package | License | Notes |
|---|---|---|
| `intl`, `path_provider`, `local_auth`, `path`, `meta` | BSD-3-Clause | Official Flutter-team / Dart-team packages. |
| `flutter_staggered_grid_view` | MIT | Masonry file-explorer view. |
| `dynamic_color` | Apache-2.0 | Material You theming. |
| `material_ui` | BSD-3-Clause | Official Flutter-team Material widget library, decoupled from the `flutter` SDK into its own pub.dev package as of Flutter 3.47; replaces `package:flutter/material.dart` imports almost everywhere in this project (one file, `lib/features/share_import/share_import_flow.dart`, still imports `package:flutter/material.dart` directly -- not a licensing concern either way since both come from the Flutter SDK/its own packages, just noted so this table doesn't overstate how complete the migration is). |
| `flutter_riverpod` | MIT | State management / DI container (Riverpod, by rrousselGit). |
| `riverpod_annotation` | MIT | Annotations consumed by `flutter_riverpod`; no separate codegen at runtime. |
| `re_editor` | MIT | In-app text/code editor widget (`reqable.com`), vendored in-tree under `packages/re_editor` with local performance patches (see `packages/re_editor/PATCHES.md`). Bounded paragraph cache, fast line lookup, and skipped isolate serialization for non-code files. Upstream license retained. |
| `re_highlight` | MIT | `re_editor`'s syntax-highlighting engine (Dart port of `highlight.js`, itself BSD-3-Clause upstream -- the Dart translation is independently MIT-licensed by `reqable.com`). Supplies the bundled language grammars and color themes used by the editor. |
| `isolate_manager` | MIT | Transitive dependency of `re_editor`; runs syntax highlighting off the UI isolate for large files. |
| `kpasslib` | MIT | KeePass KDBX 3/4 reading and writing for Item Vault import/export (`kdbx_codec.dart`). Uses pure-Dart `archive` and `crypto` internally for KDBX block compression and key derivation. |
| `csv` | MIT | CSV parsing/encoding for password import/export (`csv_codec.dart`). No dependencies. |

`crypto` (BSD-3-Clause) was originally used for TOTP calculation and Bitwarden export
decryption; both were migrated to native C++ (`VaultCryptoApi.hmac` / OpenSSL BoringSSL
in `libvaultexplorer.so`). The package is now kept only under `dev_dependencies` as an
independent reference check for `test/helpers/reference_hmac_crypto.dart`, and is pulled
transitively by `kpasslib`. It is not imported directly by any release Dart code in `lib/`.

`archive` (MIT) is not a direct `pubspec.yaml` dependency. It is pulled in transitively
by `kpasslib` (for KDBX stream compression) and used in
`test/features/browser/controllers/file_browser_navigation_controller_test.dart` to
synthesize a mock ZIP byte fixture for testing `ArchiveService`. All user-facing archive
browsing (ZIP, 7-Zip, RAR, TAR, GZ, BZ2, XZ, ZSTD) is handled exclusively by the native
libarchive engine (`android/app/src/main/cpp/archive/`).

Dev-only tooling and test packages include `flutter_launcher_icons` (generates icons at
build time), `build_runner`, `riverpod_generator`, `riverpod_lint` (all MIT), `test`,
`fake_async`, `flutter_lints`, and the mocking packages
`path_provider_platform_interface`/`plugin_platform_interface` (BSD-3-Clause); on the
Android side, `junit:junit`, `org.robolectric:robolectric`, `org.json:json`, and
`androidx.test:core` are used only for local JVM tests (`testImplementation`). None of
these test or build-time tools ship in the release APK.

## Bundled assets & Fonts

| Component | Upstream | License | Notes |
|---|---|---|---|
| JetBrains Mono (Regular, Bold, Italic) | `JetBrains/JetBrainsMono` | SIL Open Font License 1.1 | Bundled as the code editor's monospace typeface (`assets/fonts/JetBrainsMono-*.ttf`), falling back to the platform's system monospace font if it fails to load. Full license text kept at `assets/licenses/JetBrainsMono-OFL.txt`. Satisfies OFL condition by not being sold on its own. |
| EFF Large Wordlist | Electronic Frontier Foundation (EFF), Joseph Bonneau | CC-BY-3.0 US | Bundled Diceware wordlist (`assets/data/eff_large_wordlist.txt`, 7,776 words) used by `KeyfilePassphraseGeneratorService` to generate cryptographically strong passphrases and keyfile passphrases. |

## Distribution notes

- **Native C++ code (`cpp/`)**: All native components compiled directly into
  `libvaultexplorer.so` (`android/app/src/main/cpp/CMakeLists.txt`) are built from
  original, unmodified upstream source at pinned Git commits via CMake `FetchContent`.
  Nothing is shipped as a prebuilt binary in the `cpp/` directory of this repository.
- **Prebuilt native libraries from Maven Central (`nextlib-media3ext`)**:
  `nextlib-media3ext` is consumed as a prebuilt AAR artifact from Maven Central
  (`io.github.anilbeesetti:nextlib-media3ext:1.11.1-0.16.0`). This is permitted under
  F-Droid's Inclusion Policy, which allows prebuilt FLOSS binaries from trusted Maven
  repositories including Maven Central. The artifact contains native shared libraries
  (`libnextlib-media3ext.so`, FFmpeg, `libdav1d.so`) built from unmodified FLOSS sources
  in nextlib's CI under GPL-3.0 / LGPL-3.0-or-later / BSD-2-Clause terms. The dependency
  version is strictly pinned for reproducible builds.
- **Vendored Dart packages**: `packages/re_editor` is vendored locally in the repository
  with its upstream MIT license and README retained. All local performance modifications
  are explicitly documented in `packages/re_editor/PATCHES.md`.
- **Copyleft obligations**: Vault Explorer itself is GPLv3. If you fork this project
  and modify any GPL- or LGPL-licensed component in place, you must publish your
  modified source per the terms of the GNU General Public License v3.0 or LGPLv3.