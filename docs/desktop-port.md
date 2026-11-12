# Desktop port (Linux first, Windows next)

Status: **work in progress.** The native engine builds and passes its smoke test on Linux. The Dart
host is written but has not yet been run inside Flutter. Windows is partly prepared (see below).

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
Windows: please run the test there once (below). The Flutter side (runner, bundling, file dialogs, secret
store) has not been tried on Windows at all.

Build the engine (either way produces the same DLL):

    scripts/build_desktop_engine_windows.sh                # from Linux, cross-compiling with MinGW-w64
    # or, natively in an MSYS2 UCRT64 shell:
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
thumbnails and previews** (Flutter codecs, PNG output, IMAGE_TOO_LARGE guard), **open with / open link /
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

## Folder vaults (gocryptfs / Cryptomator / CryFS) -- Linux

Main (v1.50) moved the three formats into a platform-neutral C++ core (`foldervault/`, linked as
`foldervault_core`); the desktop engine reaches it through `ffi/ve_foldervault.cpp`, the desktop twin of
`jni/foldervault_bridge.cpp` (same open/create semantics; `fv::PosixStorage` over an ordinary directory).

An unlocked vault is parked in a **volume slot** (the same slot ids containers use; Dart allocates them).
`ve_engine.cpp` asks `vefv::isSlot(vol)` at the top of every file-level call and forwards to the vault, so
list / read / write / rename / delete / mkdir / set-mtime / import / export / streams / space info / lock work
on it unchanged. `ve_copy_file` between any mix of container and vault slots streams through memory in 2 MiB
steps (and finishes the destination vault file). Format-specific calls: `ve_fv_probe / unlock / create /
change_password / migrate_cryptomator / info / list_symlinks / read_symlink / hidden_entry_count /
finish_write / batch` (ABI 8, `ve_engine.h`). `ve_fv_unlock` takes `backup_key_files` (Cryptomator `.bkup` copies of
the key files on read-write unlocks; the per-vault choice lives in `<app support>/vault_open_prefs.json`, default on) and
`ve_fv_probe_cryptomator` is the password-free format check behind the "upgrade this vault" tile.

**Symbolic links** (`ve_list_symlinks / ve_read_symlink / ve_create_symlink`) are generic: they work on any unlocked slot,
so Cryptomator vaults and native ext/NTFS containers answer through the same calls. Links stay out of `ve_list_directory`;
a link to a folder is listed as `LD|0|mtime|name`.

- **A chunk-written file only becomes valid after `finishWrite`**, and chunks must arrive in order from offset 0
  (the core's contract; the Dart layer already calls `finishWrite` on Android). Skipping it left the engine
  smoke test hanging until timeout -- why was not investigated.
- Dart: `pick*Vault` uses `file_selector.getDirectoryPath`; CryFS keeps its per-vault integrity state in
  `<app support>/cryfs-state` (it must survive restarts). A wrong password surfaces as `AUTH_FAIL` /
  `INCORRECT_PASSWORD`, anything else as `INVALID_VAULT`.
- The CryFS derived key (Android's "remember" fast path) is not surfaced: there is no keystore on desktop.
- The NFC filename normaliser hook (`fv::setNfcNormalizer`) is not installed, so only non-ASCII names that
  arrive in decomposed form are affected (see `foldervault/README.md`).
- **Windows:** not available yet. `foldervault/fv_storage.cpp` is POSIX-only (`opendir`, `fstatat`, `statvfs`,
  `utimensat`), so the core is not built there and `ve_fv_*` answer "not available" (`ve_fv_supported()==0`,
  `VE_NO_FOLDERVAULT`). It needs a Win32 storage backend.
- Tested: `ve_smoke_test fv` (also part of the default run) creates, unlocks, writes, lists, renames, copies
  (inside the vault and to/from a real VeraCrypt container), streams, exports/imports, mounts read-only, locks
  and re-unlocks, and changes the password, for all three formats.

## Not yet

- Engine-channel coverage: of the 375 methods the Dart layer calls, the desktop host answers 107 and answers
  45 Android-only ones with a harmless default; **228 still reply `null`**. Many are Android-only (camera 26,
  Media3 23, audio recorder 12, panic 11, disguise 10, automation 10, PiP 6, quick capture 7). The ones worth
  doing for desktop: repair / check / header tools (`vault_repair_api`, 11, including
  `checkFolderVault` / `repairFolderVault`), archives (`vault_archive_api`, 8 -- the libarchive engine is already
  in the build, it only needs ABI functions), PDF (8), audio editing (4), `mountContainerFolder` /
  `createUsbContainer` / pickers in `vault_lifecycle_api`, and part of `vault_file_io_api` (36, e.g. video
  thumbnails, `getMediaFileSize`).
- In-place growth (new in this main): `expandVeraCryptContainer`, `expandLuksContainer`, `growVeraCryptFileSystem`,
  `growLuksFileSystem`. The engine already has `fsGrowToFit` (NTFS and ext2/3/4; FAT/exFAT report unsupported); it only needs
  ABI functions and host handlers, plus the container-file extension step for the two `expand*` calls.
- Windows: folder vaults (above), the new ext resize sources (`e2fsprogs/resize`, `filesystems/ext_resize_glue.c`) under
  MinGW, and re-running the engine smoke test after the rebase.
- Archives, video thumbnails, media playback, PDF, camera, video/audio editing -- need their
  desktop backends (they are platform code on Android).
- Import: per-filesystem file-name validation and the post-import SHA-256 read-back verification
  (the engine still rejects an illegal name when it writes it).
- Share sheet; JPEG/WebP encoding for the image editor (PNG only for now).
- Pre-flight free-space check on create (Android reports `INSUFFICIENT_SPACE`; desktop just fails).
- Windows: the engine was validated under Wine on v1.39 (see "Windows" above; re-run it after the rebase); the
  Flutter app on Windows is untested.
- macOS / iOS: not started.
