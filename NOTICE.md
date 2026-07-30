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

See `docs/DECISIONS.md` for a note on FFmpeg, previously vendored here and
since removed in favor of the `video_player` plugin below.

## Flutter/Dart (`pubspec.yaml`)

| Package | License | Notes |
|---|---|---|
| `video_player` | BSD-3-Clause | Official Flutter plugin. On Android, backed by AndroidX Media3/ExoPlayer (Apache-2.0), which decodes via the OS's own `MediaCodec` -- no bundled codec binaries of any kind. |
| `path_provider`, `local_auth`, `flutter_secure_storage`, `url_launcher`, `wakelock_plus`, `package_info_plus`, `sensors_plus`, `flutter_staggered_grid_view`, `archive`, `path`, `vector_math`, `flutter_launcher_icons` | BSD-3-Clause / MIT (each individually) | Standard Flutter-community/AOSP-adjacent packages. No proprietary or copyleft-incompatible terms. |
| `pointycastle`, `encrypt` | BSD-3-Clause / MIT | Pure-Dart crypto libraries (`encrypt` wraps `pointycastle`). |

See `docs/DECISIONS.md` for packages that were evaluated and rejected
(`fvp`, `syncfusion_flutter_pdfviewer`/`syncfusion_flutter_pdf`, `pdfrx`)
and why none of them ship in this project.

## Vendored web assets (`android/app/src/main/assets/`)

| Component | Upstream | License | Version | Status |
|---|---|---|---|---|
| pdf.js (`pdfjs/pdf.min.mjs`, `pdfjs/pdf.worker.min.mjs`, `pdfjs/viewer.{html,css,js}`) | mozilla/pdf.js | Apache-2.0 (confirmed in the `@licstart` header of the vendored file itself) | 6.2.108 | Free license, but **vendored pre-minified** rather than built from source by this repo's build -- see the `AntiFeatures`/comment block in `metadata/com.aeidolon.vaultexplorer.yml` for the open F-Droid "build from source" question this raises. Loaded into a sandboxed, no-network `WebView` (`PdfViewerPlugin.kt`) with vault bytes streamed in over a method channel; nothing is fetched from the internet at runtime. |

This is what actually backs the in-app PDF viewer
(`lib/features/browser/viewer/pdf_viewer_screen.dart` + `PdfViewerPlugin.kt`).

## Distribution notes

- All GPL/LGPL native components are built from their original, unmodified
  upstream source at the pinned commit via CMake `FetchContent`
  (`android/app/src/main/cpp/CMakeLists.txt`) -- nothing is shipped as a
  prebuilt binary in the native (`cpp/`) part of this repository,
  satisfying GPL "source availability" and F-Droid's "buildable from
  source" requirement simultaneously.
- If you fork this project and modify any GPL-licensed component in place,
  you must publish your modified source per the GPL's terms.