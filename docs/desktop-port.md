# Desktop port (Linux first, Windows next)

Status: **work in progress.** The native engine builds and passes its smoke test on Linux. The Dart
host is written but has not yet been run inside Flutter. Windows is partly prepared (see below).

**Update for v1.66.0 (ABI 9).** The numbers and file lists below that mention v1.50 / ABI 8 are history; the engine
library is at `VE_ABI_VERSION` 9 (`ffi/ve_engine.h`). Method coverage is now measured, not counted by hand:
`test/core/engine/desktop/desktop_method_coverage_test.dart` diffs `ChannelMethods` against the host, the crypto
handler, the Android-only defaults and the two explicit lists in `lib/core/engine/desktop/desktop_method_support.dart`
(see "Engine-channel coverage" under "Not yet"). CI (`ci.yml`, job `desktop_engine_linux`) now builds the Linux engine,
runs `ve_smoke_test` and `ve_mount_test`, and builds the Linux app.

**Rebased onto the latest v1.50.0 main** (the second 1.50.0 snapshot, which adds in-place ext/NTFS grow, Cryptomator
symlinks, the Cryptomator key-file backup option and the format probe). The port was first written against v1.39.0;
it now sits on top of main:
main's versions of every shared file are kept (they carry fixes the old snapshot lacks, e.g. the
container-creation header randomisation and the `-1 = missing` file-size contract) and only the port's
own edits are re-applied. Re-verified since the rebase: the Linux engine (FAT / exFAT / NTFS / ext4, hidden
volumes, password change, crypto, digests, single-file tool, folder vaults, native ext4/NTFS symlinks). **Not** re-verified: the
Windows build/Wine run (it predates the rebase), and all Dart (no Flutter SDK was available: run
`flutter pub get` -- `pubspec.lock` was not regenerated -- then `flutter analyze` first).

## How it fits together

```
Dart UI + VaultXxxApi classes        (unchanged)
        |  MethodChannel (engine channel)
        v
desktop_engine_binding.dart          custom WidgetsFlutterBinding: answers ONLY the engine channel
        |                            in-process; every other channel goes to Flutter as usual
        v
desktop_engine_host.dart             same method names / argument + result shapes as the Kotlin handlers
        |  EngineWorkerPool (4 isolates, least-loaded dispatch)
        v
ve_native.dart                       dart:ffi bindings (blocking, isolate-only)
        |
        v
libvaultexplorer_engine              C ABI: android/app/src/main/cpp/ffi/ve_engine.h
        |
        v
the same C++ engine Android uses     (session/, io/, containers/, filesystems/, crypto/)
```

Android is untouched: the JNI bridges and Kotlin are not involved on desktop, and
`VAULTEXPLORER_DESKTOP` defaults to OFF.

## Build and test the engine (Linux)

    scripts/build_desktop_engine.sh
    build/desktop-engine/ve_smoke_test fat exfat ntfs ext4     # expect: "N checks, 0 failed"

## Run the app on Linux

0. Linux packages for the secret store (saved vaults and credentials live in the OS keyring):

       sudo apt install libsecret-1-dev libjsoncpp-dev      # build time
       # runtime: a keyring service must be running (gnome-keyring, or KWallet on KDE)

1. The runner already exists (`linux/`) and `linux/CMakeLists.txt` bundles
   `build/desktop-engine/libvaultexplorer_engine.so` next to the app, so build the engine first
   (`scripts/build_desktop_engine.sh`). Point `VE_ENGINE_LIBRARY` at the .so instead while developing.

2. `flutter pub get && flutter run -d linux`  (regenerates `linux/flutter/generated_plugin*` for the
   plugins this version of the app uses)

**Dev loop.** The engine is a separate build. After changing anything under
`android/app/src/main/cpp/`, re-run `scripts/build_desktop_engine.sh`, then either rebuild the app
(the bundle only gets the new `.so` when the Linux build runs) or skip the bundling step while
developing:

    VE_ENGINE_LIBRARY=$PWD/build/desktop-engine/libvaultexplorer_engine.so flutter run -d linux

If the app reports the engine is "out of date" (ABI mismatch) or `undefined symbol: ve_...`, the `.so`
in the bundle is older than the Dart code: rebuild the engine and the app.

On first run expect some rough edges: methods the desktop host does not implement yet reply `null`
and are logged once in debug builds as `[desktop-engine] not implemented yet: <method>`. Paste
those lines back and they become the to-do list.

## Windows

Status: the engine builds as a self-contained `vaultexplorer_engine.dll` and **passes the full engine smoke
test (300 checks: FAT / exFAT / NTFS / ext4, creation, hidden volumes, password change, crypto, digests,
single-file tool) when run under Wine.** That is a strong signal, not a substitute for running it on real
Windows: please run the test there once (below). The Flutter runner has now launched on Windows with
`VE_ENGINE_LIBRARY`; DLL bundling, file dialogs and the secret store still need a fuller check.

Build the engine (either way produces the same DLL):

    scripts/build_desktop_engine_windows.sh                # from Linux, cross-compiling with MinGW-w64
    # or, natively in an MSYS2 UCRT64 shell (install these tools once):
    pacman -S --needed mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja mingw-w64-ucrt-x86_64-gcc git
    cmake -S android/app/src/main/cpp -B build/desktop-engine-win -G Ninja -DVAULTEXPLORER_DESKTOP=ON -DCMAKE_BUILD_TYPE=Release
    cmake --build build/desktop-engine-win --target vaultexplorer ve_smoke_test

Check it on a Windows machine: copy `vaultexplorer_engine.dll` and `ve_smoke_test.exe` somewhere and run
`ve_smoke_test.exe fat exfat ntfs ext4` (takes a few minutes; expect `N checks, 0 failed`).

Run the app on Windows:

1. `flutter create --platforms=windows .`
2. Bundle the DLL: in `windows/CMakeLists.txt`, next to the other `install()` calls:

       set(VE_ENGINE_DLL "${CMAKE_CURRENT_SOURCE_DIR}/../build/desktop-engine-win/vaultexplorer_engine.dll")
       install(FILES "${VE_ENGINE_DLL}" DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)

   (or set `VE_ENGINE_LIBRARY` to the DLL's full path while developing).
3. `flutter pub get && flutter run -d windows`

For repeat builds from PowerShell, run `scripts/build_windows.ps1 -Run`. It prepares Flutter packages when
`.dart_tool/package_config.json` is missing, rebuilds `vaultexplorer_engine.dll` with the MSYS2 UCRT64 toolchain,
builds the Flutter Windows app, copies the DLL next to the runner, and optionally starts it. Add `-PubGet` to
force a package refresh, `-Configuration Release` for a release build, or `-Msys2Root <path>` when MSYS2 is not
installed under `C:\Tools\msys64`, `C:\msys64` or `C:\msys2`. The script checks whether the runner or DLL is locked and stops with a message; close the app before rebuilding. It checks for the
MSYS2 UCRT64 CMake, Ninja, GCC and G++ tools but does not install them; see the package command above.

What the Windows port changed, and why (all behind the desktop/Windows switches, so Android is unchanged):

- POSIX stand-ins: `pread` / `pwrite` over CRT descriptors, `getline`, `random()` (backed by the OS CSPRNG),
  stub `ioctl` / `fcntl` / `getuid` ..., and header stand-ins (`ffi/compat_win/`: termios, pwd, grp,
  sys/ioctl, sys/select, arpa/inet). They only exist so the vendored C code (ntfs-3g, e2fsprogs,
  dislocker) compiles and links; the engine does not use those paths on Windows. `ffi/compat_win` is added
  to the include path on Windows only: on Linux it would shadow real system headers.
- Host files are opened through `hostOpen()` (`io/host_file.h`): plain `open()` on Android / Linux, but on
  Windows a UTF-8 path in binary mode. The C runtime's default text mode corrupts any binary file (it
  translates CR/LF and treats byte 0x1A as end-of-file) and cannot open non-ASCII paths. Caught by the
  import/export round-trip in the smoke test.
- `Common/Endian.h` allows little-endian Windows explicitly (it deliberately refuses unknown platforms).
- zlib is vendored (MinGW has none); libarchive is built without a regex library (MinGW has none).
- Not applicable on Windows: raw USB mass-storage access, the Android file-descriptor tricks.
- Newer MinGW compilers (GCC 14+) make several legacy-C constructs hard errors (implicit function
  declarations, int/pointer conversions). The vendored C libraries still contain a few, so the desktop build
  declares the POSIX functions they use (`ffi/compat/ve_win_types.h`, force-included into every vendored C
  target) and keeps `-Wno-error=` for the remaining legacy patterns on those targets only. A strict-mode
  pass over all 568 vendored C files (compile commands re-run with the implicit-declaration / int-conversion /
  pointer-type diagnostics forced to errors) is clean apart from what those flags cover.

## What works (design scope of this cut)

Add a vault (multi-select file picker), probe, unlock (VeraCrypt / LUKS / BitLocker / plain block
images, keyfiles, hidden-volume protection, cached derived keys passed through), unlock progress
events, cancel, **create** (VeraCrypt, LUKS1/2, optional embedded hidden volume; built under a
temporary name next to the destination and renamed into place only when complete), browse, read,
write, create directory, rename, delete, set mtime, copy between volumes, space info, vault information
screen, lock. **Import** (pick files or a folder, conflict resolution skip / overwrite / keep both,
free-space guard, progress, cancel, delete-sources-after-import) and **export** (to a folder, "save as",
extract-to-path), with the same progress and per-item events the Android handlers push. **Image
thumbnails and previews** (Flutter codecs, PNG output, IMAGE_TOO_LARGE guard), **full-resolution images in the
viewer** (`getMediaFileSize` / `readMediaFileChunk`, which the viewers use in place of `getFileSize` /
`readFileChunk`), **video thumbnails** (see "Video thumbnails" below), **open with / open link /
open local file** via the desktop's default handler.

**Crypto primitives** (`hashPassword`, `hashPasswordSha256`, `pbkdf2`, `hmac`, `scrypt`, `argon2id`,
`aesGcmEncrypt/Decrypt`, `aesCbcDecrypt`, `xchacha20Poly1305Open`) run in the native engine, the same
implementations Android uses (`ffi/ve_crypto.cpp`), so app-lock hashes, the encrypted thumbnail cache and
authenticator-backup imports behave identically. The engine smoke test checks them against reference
vectors generated by independent libraries (hashlib, argon2-cffi, cryptography, PyNaCl). The cached
derived-key and biometric-key calls are Android Keystore features and answer "none / unsupported".

**Change password** (VeraCrypt and LUKS1/2; PIM, keyfiles) and the **checksum tool** (MD5 / SHA-1 /
SHA-256 / SHA-512 in one pass over a vault file or a host file; also what the thumbnail cache uses to
derive its keys). LUKS reports a wrong old password as `AUTH_FAIL`; a failed change leaves the old
password working (covered by the engine smoke test).

**Single-file encryption tool** (`encryptSingleFile` / `decryptSingleFile`: .vxenc / .aes, passwords and
keyfiles, progress, cancel): the output is built under a temporary name beside the destination and
renamed into place only when complete, so a wrong password or a cancel never leaves a partial file. The
tool refuses to write over its own source file.

**Container splitter** (`splitContainer` / `joinContainer`): plain file I/O in Dart, same part naming
(`<name>.001`, `<name>.part1`), `manifest.json`, progress and cancel semantics as Android. A cancelled split
keeps the finished parts and drops the in-flight one; a join is written under a temporary name and renamed
into place when complete. (Mounting a split container directly without joining it is a separate feature
and is not ported yet.)

**Privacy note on "open with":** Android streams the file to the other app through a pipe, so no plaintext
reaches storage. A desktop app can only be given a file, so one decrypted copy is written to a
contained, owner-only directory (under `$XDG_RUNTIME_DIR` when available), deleted when the vault is
locked or the engine shuts down, and purged on the next start after a crash. Links are limited to
http / https / mailto. The app's secret store (`readSecure` / `writeSecure` / ... / `containsKeySecure`) is backed by
the OS keyring, so saved vaults and credentials persist; without a keyring service the writes fail soft
(`false`) and a one-time hint is printed.

Closing the window runs a clean-up first (`AppLifecycleListener.onExitRequested`): every unlocked vault is
locked (its key material wiped in the engine) and any decrypted "open with" copies are deleted, rather than
relying on the next start's purge. A crash or kill -9 still falls back to that purge.

## Folder vaults (gocryptfs / Cryptomator / CryFS) -- Linux and Windows

Main (v1.50) moved the three formats into a platform-neutral C++ core (`foldervault/`, linked as
`foldervault_core`); the desktop engine reaches it through `ffi/ve_foldervault.cpp`, the desktop twin of
`jni/foldervault_bridge.cpp` (same open/create semantics; `fv::PosixStorage` over an ordinary directory).

An unlocked vault is parked in a **volume slot** (the same slot ids containers use; Dart allocates them).
`ve_engine.cpp` asks `vefv::isSlot(vol)` at the top of every file-level call and forwards to the vault, so
list / read / write / rename / delete / mkdir / set-mtime / import / export / streams / space info / lock work
on it unchanged. `ve_copy_file` between any mix of container and vault slots streams through memory in 2 MiB
steps (and finishes the destination vault file). Format-specific calls: `ve_fv_probe / unlock / create /
change_password / migrate_cryptomator / info / list_symlinks / read_symlink / hidden_entry_count /
finish_write / batch` (`ve_engine.h`). `ve_fv_unlock` takes `backup_key_files` (Cryptomator `.bkup` copies of
the key files on read-write unlocks; the per-vault choice lives in `<app support>/vault_open_prefs.json`, default on) and
`ve_fv_probe_cryptomator` is the password-free format check behind the "upgrade this vault" tile.

**Symbolic links** (`ve_list_symlinks / ve_read_symlink / ve_create_symlink`) are generic: they work on any unlocked slot,
so Cryptomator vaults and native ext/NTFS containers answer through the same calls. Links stay out of `ve_list_directory`;
a link to a folder is listed as `LD|0|mtime|name`.

- **A chunk-written file only becomes valid after `finishWrite`**, and chunks must arrive in order from offset 0
  (the core's contract; the Dart layer already calls `finishWrite` on Android). Skipping it left the engine
  smoke test hanging until timeout. Cause (read from `foldervault/fv_engine.cpp`, not yet reproduced under a debugger):
  `ChunkedFileEngine::writeFileChunk` marks the path as "writing" and keeps the encrypted file open in `openWrites_`;
  only `finishWrite`, a failed chunk, `writeFrom` replacing a stale handle, or `close()` clears the mark.
  `readFileChunk` starts with `waitNotWriting(path)`, an untimed condition-variable wait, so the first read of a path
  whose write was never finished blocks forever. That is deliberate (a reader must never see a half-written file),
  but it means a Dart-side failure or cancel between chunks wedges every reader of that path, and with a fixed
  worker pool a few such reads would stall the whole engine. The FUSE layer is safe because it finishes the write
  on release. A fix belongs with Phase 2: give the slot owner an idle timeout that aborts abandoned writes, or an
  explicit abort entry point for cancelled copies.
- Dart: `pick*Vault` uses `file_selector.getDirectoryPath`; CryFS keeps its per-vault integrity state in
  `<app support>/cryfs-state` (it must survive restarts). A wrong password surfaces as `AUTH_FAIL` /
  `INCORRECT_PASSWORD`, anything else as `INVALID_VAULT`.
- The CryFS derived key (Android's "remember" fast path) is not surfaced: there is no keystore on desktop.
- The NFC filename normaliser hook (`fv::setNfcNormalizer`) is not installed, so only non-ASCII names that
  arrive in decomposed form are affected (see `foldervault/README.md`).
- **Windows:** `foldervault/fv_storage_win.cpp` is the Win32 twin of the POSIX-only `fv_storage.cpp` (same
  `fv::PosixStorage` interface; UTF-16 paths in the `\\?\` form, so no MAX_PATH limit and no DOS device names;
  path segments with `\`, `:` or wildcards are refused; only real symlinks / junctions count as links, not OneDrive
  placeholders). The few raw host-file calls in the CryFS code and in import/export go through `foldervault/fv_os.h`
  (UTF-8 -> UTF-16, binary mode; plain POSIX calls elsewhere). CMake builds the core on Windows and no longer defines
  `VE_NO_FOLDERVAULT`. Before this, every `ve_fv_*` call was a stub (`ve_fv_supported()==0`, probe "not a vault"),
  which showed up as "no config file found" / "folder not empty". `foldervault_storage_test` (CMake target; also
  runs on Linux) covers the empty-folder -> create -> detect -> unlock -> work -> unlock-again cycle for all three
  formats plus Unicode and over-long paths: 310 checks on Linux, 321 on Windows **under Wine** (not real Windows --
  no NTFS sharing rules, antivirus or OneDrive -- and not through the Flutter UI).
- Tested: `ve_smoke_test fv` (also part of the default run) creates, unlocks, writes, lists, renames, copies
  (inside the vault and to/from a real VeraCrypt container), streams, exports/imports, mounts read-only, locks
  and re-unlocks, and changes the password, for all three formats.

## Video playback (Linux and Windows)

Status: written against the media_kit / libmpv sources and the engine's read path, the loopback server is
tested (`test/core/engine/desktop/desktop_media_server_test.dart`), but the Flutter side has **not been compiled
or run** (no Flutter SDK or desktop where it was written): run `flutter pub get && flutter analyze`, then play a
few files.

```
media viewer -> NativeVideoController -> VideoPlaybackBackend
                                           |- NativeMedia3Controller   (Android, unchanged)
                                           '- DesktopVideoBackend      (Linux / Windows: libmpv via media_kit)
                                                  |  http://127.0.0.1:<port>/<token>/video.<ext>
                                                  v
                                            DesktopMediaServer  --pool 'read'--> engine (decrypts)
```

- **Nothing decrypted touches storage.** The player reads a loopback HTTP URL, served by `DesktopMediaServer`
  (`desktop_media_server.dart`) straight from the unlocked vault with `Range` support. The socket exists only
  while a video is open, is bound to 127.0.0.1, and each session has its own random 128-bit token in the path;
  `Host` must be 127.0.0.1/localhost with the right port. A session ends when the player closes it, when its
  vault is locked (the host calls `closeVolume` before `ve_lock`) and at exit.
- **mpv hardening** (`DesktopVideoBackend._lockDownPlayer`): media_kit turns on mpv's `cache-on-disk`, which
  would spool the decrypted stream into a temp file -- it is switched off and playback is refused if mpv does not
  confirm that. Only the `http` / `tcp` protocols are allowed (`file` for plain local-storage items), so a
  container referencing other files or URLs cannot make mpv read them; sidecar subtitle / audio auto-loading is off.
- **What maps over:** play / pause / seek / speed / loop / volume, A-B loop (mpv `ab-loop-a/b`), audio and
  subtitle track selection (embedded text subtitles reach the viewer's own caption layer through
  `captionText`), volume boost and the 10-band equalizer (an mpv `lavfi` filter chain, `audioFilterChain`),
  decoder mode (`hwdec`: auto -> `auto-safe`, hardware -> `auto`, software / ffmpeg -> `no`), resume position
  (`Media.start`), diagnostics (hwdec, codecs, dropped frames).
- **Not on desktop:** scrub-preview frames (the viewer hides the preview), picture-in-picture, background
  playback / media notification, graphical (PGS / VobSub) subtitles in the viewer's caption layer.
- **Dependencies** (see NOTICE.md): `media_kit`, `media_kit_video`, `media_kit_libs_linux`,
  `media_kit_libs_windows_video`. Linux: `sudo apt install libmpv-dev` to build, `libmpv2` at run time. Windows:
  the libs package downloads libmpv while building (needs Developer Mode for symlinks, and 7-Zip/tar available).
  Without libmpv the app still runs; opening a video shows an "install libmpv" error. `pubspec.lock` was not
  regenerated.

### Video thumbnails

`getVideoThumbnail` / `getVideoThumbnailWithSize` take one frame out of the same libmpv the player uses (Android
uses MediaMetadataRetriever; the engine has no video decoder of its own):

```
host -> DesktopVideoThumbnails (desktop_video_thumbnails.dart: which frame(s), slots, cancel on lock)
          |- grabFrameWithMpv   (mpv_frame_grabber.dart: fresh paused Player + VideoController, first picture,
          |                      Player.screenshot as JPEG, player disposed)
          '- decodeVideoFrame   (video_frame_decoder.dart: scale-while-decoding to the target size, PNG out,
                                  8x8 "is this frame blank" check)
```

- Source: the loopback media server session of the file (so nothing decrypted touches storage), or a `file:` URL
  for local-storage items and the temp copies archive previews use. The player gets the same lock-down as
  playback (`cache-on-disk` off and verified, sidecar loading off, protocol whitelist) plus: software decode and
  rendering, no audio output, and a 16 MiB read-ahead cap (mpv's default would pull ~150 MiB of the vault through
  the decryption per thumbnail).
- Frame choice follows Android: `firstFrame` = time 0; `frameAtPercentage` = `framePosition` of the duration
  (clamped to 5%..90%, needs a second open once the duration is known); `hybrid` (default) = time 0, and if that
  frame is blank (`isLikelyBlankFrame`, a port of the Kotlin heuristic) the first non-blank frame at
  `framePosition`, 25% or 45%. An explicit `timeUs` (the video editor) is used as is.
- At most 2 players at a time; a locked vault drops its queued requests. Any failure answers `null`, which the Dart
  side treats as "no thumbnail for this video" (placeholder icon), exactly as for an Android `FRAME_FAILED`.
- Thumbnails are PNG (like image thumbnails), so they are larger than Android's JPEG ones in the cache.
- The pure parts (`video_thumbnail_logic.dart`, `desktop_video_thumbnails.dart`) are covered by
  `test/core/engine/desktop/video_thumbnail_logic_test.dart` and `desktop_video_thumbnails_test.dart`. The mpv and
  `dart:ui` adapters have **not been run inside Flutter**: they follow `desktop_video_backend.dart` and
  `desktop_images.dart` closely, but `Player.screenshot` and the first-frame signal of an off-screen
  `VideoController` are the first things to check on a real Linux / Windows build.

## Not yet

- Engine-channel coverage: `ChannelMethods` has 281 methods. The desktop host answers 121 of them (including the
  crypto primitives), gives 42 more an Android-only default (`_androidOnlyDefaults`), lists 66 as Android-only
  (`desktopAndroidOnlyMethods`: automation, panic, quick capture, share sheet, USB, SAF, APK install, Jetpack PDF, ...)
  and 52 as pending (`desktopPendingMethods`, grouped by the plan phase that delivers them: archives, repair and header
  backup, expansion and hidden volumes, composite/split containers, AVIF, PDF, comic/EPUB, image probing, audio/video
  editing). The coverage test fails when a method is in none of these places or is in two of them, so the split above
  stays true; run it to see the current numbers. These counts cover the one engine channel only. Camera, Media3,
  picture-in-picture, brightness, panorama, disguise mode and the platform views use their own channels, which the
  desktop binding passes to Flutter (they throw `MissingPluginException` on desktop unless the Dart caller is guarded).
  Answered since the earlier counts: `getAppVersion` (the version name from `desktop_host_info.dart`; a test keeps it
  equal to `pubspec.yaml`), `getContainerSizeInfo` (file size, plus free space from `df -Pk` on Linux or PowerShell
  on Windows, `null` when unknown), `resolveRawStoragePath`, `exportAppSettingsFile` / `importAppSettingsFile`
  (`file_selector` dialogs), `writeBackFile` (the same `ve_import_file` call the import path uses), and explicit
  "unsupported" answers for the sensitive-clipboard pair (the Dart caller falls back to Flutter's clipboard) and
  `setKeepScreenOn`.
- In-place growth (new in this main): `expandVeraCryptContainer`, `expandLuksContainer`, `growVeraCryptFileSystem`,
  `growLuksFileSystem`. The engine already has `fsGrowToFit` (NTFS and ext2/3/4; FAT/exFAT report unsupported); it only needs
  ABI functions and host handlers, plus the container-file extension step for the two `expand*` calls.
- Windows: folder vaults on a real Windows machine (above), the new ext resize sources (`e2fsprogs/resize`, `filesystems/ext_resize_glue.c`) under
  MinGW, and re-running the engine smoke test after the rebase.
- Archives, PDF, camera, video/audio editing -- need their
  desktop backends (they are platform code on Android). Video **playback** and **thumbnails** are done (below);
  scrub-preview frames, picture-in-picture and background playback / media session are not.
- Import: per-filesystem file-name validation and the post-import SHA-256 read-back verification
  (the engine still rejects an illegal name when it writes it).
- Share sheet; JPEG/WebP encoding for the image editor (PNG only for now).
- Pre-flight free-space check on create (Android reports `INSUFFICIENT_SPACE`; desktop just fails).
- Windows: the engine was validated under Wine on v1.39 (see "Windows" above; re-run it after the rebase); the
  Flutter app on Windows is untested.
- macOS / iOS: not started.
