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
| mbedTLS | Mbed-TLS/mbedtls | Apache-2.0 OR GPL-2.0-or-later (dual, since 3.6.0) | 2ca6c285 (v3.6.0) | OK |
| libavif & libgav1 | AOMediaCodec/libavif, chromium/libgav1 | BSD-2-Clause / Apache-2.0 | c5240fc7 / c05bf9be | OK |
| ChaN's FatFs | stm32duino/FatFs | 1-clause-BSD-equivalent custom notice | cef1acad (4.0.4) | OK |
| NTFS-3G (libntfs-3g + ntfsprogs) | tuxera/ntfs-3g | GPL-2.0-or-later | d327833e | OK |
| e2fsprogs -- `lib/ext2fs`, `lib/e2p` | tytso/e2fsprogs | LGPL-2.0 | 7ee1d505 (v1.47.4) | OK |
| dislocker (BitLocker) | Aorimn/dislocker | GPL-2.0-or-later | 38dab031 | OK |
| cJSON | DaveGamble/cJSON | MIT | acc76239 (v1.7.18) | OK |
| VeraCrypt crypto primitives -- `Twofish.c`, `Serpent.c`, `Camellia.c`, `kuznyechik.c`, `Whirlpool.c`, `blake2s.c`, `cpu.c`, Argon2 | veracrypt/VeraCrypt | Per-file permissive: Twofish (Gladman permissive), Serpent/Whirlpool/kuznyechik/cpu.c (public domain), Camellia (BSD-2-clause/NTT), blake2/Argon2 (CC0 or Apache-2.0, at your option) | d26216c2 (1.26.29) | OK, individually |
| `Common/Tcdefs.h` and `Common/Endian.c`/`Common/Endian.h` | project contributors (clean-room; no longer sourced from veracrypt/VeraCrypt) | GPL-3.0-or-later, matching this project's own LICENSE | n/a -- written in-repo, see `cpp/Common/AUDIT.md` | **OK -- see `cpp/Common/AUDIT.md` for two rewrite regressions found & fixed here** |

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
| `intl`, `path_provider`, `local_auth`, `path` | BSD-3-Clause | Official Flutter-team / Dart-team packages. |
| `archive` | MIT | ZIP browsing and the Split & Join tool. |
| `flutter_staggered_grid_view` | MIT | Masonry file-explorer view. |
| `dynamic_color` | Apache-2.0 | Material You theming. |
| `flutter_riverpod` | MIT | State management / DI container (Riverpod, by rrousselGit). |
| `riverpod_annotation` | MIT | Annotations consumed by `flutter_riverpod`; no separate codegen at runtime. |

`flutter_launcher_icons` is a dev-only build tool (generates launcher icon
assets at build time) and ships no code in the release APK, so it isn't
listed above. The same applies to `build_runner`, `riverpod_generator`,
`riverpod_lint` (all MIT, by rrousselGit /
dart-lang / invertase): these run only at build time to generate
`*.g.dart` provider code and lint the analyzer, and are not packaged into
the release binary.

## Distribution notes

- All GPL/LGPL native components are built from their original, unmodified
  upstream source at the pinned commit via CMake `FetchContent`
  (`android/app/src/main/cpp/CMakeLists.txt`) -- nothing is shipped as a
  prebuilt binary in the native (`cpp/`) part of this repository.
- If you fork this project and modify any GPL-licensed component in place,
  you must publish your modified source per the GPL's terms.