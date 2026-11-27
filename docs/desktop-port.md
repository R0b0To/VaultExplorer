# Desktop port (Linux first, Windows next)

Status: **work in progress.** The native engine builds and passes its smoke test on Linux. The Dart
host is written but has not yet been run inside Flutter. Windows is partly prepared (see below).

**Raw drives (ABI 14).** The desktop app can mount an encrypted disk or partition (BitLocker, VeraCrypt, LUKS) picked from the list of drives of the computer (see "Raw drives" below). `VE_ABI_VERSION` is 14: `ve_list_block_devices` and `ve_unlock_device` are new, on top of the composite-container calls of ABI 13.

**Update for v1.66.0 (ABI 13).** The numbers and file lists below that mention v1.50 / ABI 8 are history; the engine
library is at `VE_ABI_VERSION` 14 (`ffi/ve_engine.h`; ABI 10 added the `ve_archive_*` calls, ABI 11 the repair, header-backup and folder-vault check calls, ABI 12 the container tools: expand, grow the file system, hidden volume in an existing volume, ABI 13 composite containers, ABI 14 raw drives). Method coverage is now measured, not counted by hand:
`test/core/engine/desktop/desktop_method_coverage_test.dart` diffs `ChannelMethods` against the host, the crypto
handler, the Android-only defaults and the two explicit lists in `lib/core/engine/desktop/desktop_method_support.dart`
(see "Engine-channel coverage" under "Not yet"). CI (`ci.yml`, job `desktop_engine_linux`) now builds the Linux engine,
runs `ve_smoke_test` and `ve_mount_test`, and builds the Linux app.

**Expand, grow and hidden volume in an existing volume (Phase 1c).** `ffi/ve_tools.cpp` exposes eight calls over the same
`containers/container_create.cpp` / `container_expand_bitlocker.cpp` code Android's `container_lifecycle_bridge.cpp` calls:
`ve_expand_veracrypt`, `ve_expand_luks`, `ve_expand_bitlocker`, `ve_grow_veracrypt_fs`, `ve_grow_luks_fs`,
`ve_grow_bitlocker_fs`, `ve_hidden_analyze` and `ve_hidden_create_in_existing` (a params struct, like `ve_create`). The fd-taking
calls close every descriptor they are given on every path, invalid-argument paths included (checked in the smoke test with
`fcntl`); the worker isolate opens the container and the keyfiles itself, keyfiles first. Passwords cross as raw UTF-8 bytes and
are wiped on every side. `DesktopVolumeTools` (`desktop_volume_tools.dart`) is what `VeraCryptToolsHandlers.kt` does around the
native calls: argument validation, the outcome-to-error-code mapping with Android's messages (`PASSWORD_INCORRECT`,
`NOT_EXPANDABLE`, `NOT_LARGER`, `KEYFILE_ERROR`, `NOT_LUKS`, `INVALID_HEADER`, `CONTAINER_IN_USE`, `NOT_BITLOCKER`,
`DISK_UNSUPPORTED`, `PARTITION_UNSUPPORTED`, `UNSUPPORTED_FS`, `NO_SPACE`, `INVALID_VOLUME`, `IO_ERROR`) and the
`fsStatus` / `fsName` result map. An unlocked container file is refused (`CONTAINER_IN_USE`) by file identity, not by path
(`platform/file_identity.h`). Nothing here depends on mounting.
Windows note: the CRT reports `st_ino` as 0, so the old `(st_dev, st_ino)` comparison would have called every file on one drive
"the same file" and refused every expansion while any vault on that drive was unlocked; the Windows branch now asks the OS
(`GetFileInformationByHandle`, `ve_win_same_file` in `ve_win_platform.cpp`) and fails closed. Tested by the "tools" section of
`ve_smoke_test` (`./ve_smoke_test tools`: VeraCrypt expand + grow on ext4, NTFS and FAT, keyfile-only credential, LUKS1 and LUKS2,
a hidden volume added to an existing volume and unlocked afterwards, refusal while unlocked, wrong password, not-larger,
invalid arguments with descriptor-closing checks, BitLocker refusals) and `desktop_volume_tools_test.dart` (fake engine).
Not exercised: the BitLocker *success* paths (no BitLocker fixture), containers over 2 GiB on Windows, the Windows file-identity
call itself, and the Dart side (no Dart SDK where this was written; run `flutter test` and `flutter analyze`).

**Composite containers (Phase 1d).** One standard VeraCrypt volume spread over several ordinary files ("carriers": images, videos,
anything that is not an archive) that each keep their own content and carry their share of the volume after it. `ffi/ve_composite.cpp`
exposes `ve_composite_profile` (read-only: sizes the carriers in the canonical order, the record layout is in `ve_engine.h`),
`ve_composite_create` and `ve_composite_unlock` (params structs) over the same `containers/carrier_profiler.cpp`,
`composite_map.cpp` and `container_create_composite.cpp` that Android's `jni/composite_bridge.cpp` calls, in the same sequence
(canonical order, profile, derive the extents, then create or unlock; unlock mounts the file system the way `ve_unlock` does). Carriers
cross as host paths and the engine's carrier cache opens them itself (`io/host_file.h`, Windows-safe); only the keyfiles are
descriptors, and the ownership rule is the one the other calls follow (the call closes them on every path). `DesktopComposite`
(`desktop_composite.dart`) is what `CompositeContainerHandlers.kt` does around the native calls: argument checks (`INVALID_ARGS`,
`MAX_CONTAINERS`), the profile map `VaultCompositeApi` decodes (`PROFILE_FAILED` when it cannot be produced), create answering true or
false, and unlock failing with `AUTH_FAIL` whose message and details are the engine's reason (`INCORRECT_PASSWORD_OR_INVALID_CONTAINER`,
`COMPOSITE_CARRIERS_INCOMPLETE`, `NO_EXTENTS_DETECTED`, `KEYFILE_FAILED`, `FILESYSTEM_MOUNT_FAILED`), or `CANCELLED`. A composite
session is registered as `composite:<first carrier exactly as the app gave it>`, the key the app saves, so lock, status, auto-lock and
the optional OS exposure treat it like any other session. Differences from Android that the app cannot see: `payloadOffsets` is not
needed (the engine reads each carrier's own header-keyed trailer), `extentLengths` only says how much capacity was asked for (its
sum), the unlock result lists the root (Android's is empty), and create takes no operation id (the shared code ignores it too, so there
is no progress or cancel on either platform). Two things changed in code shared with Android, both fixes: `createCompositeContainer` /
`prepareCompositeSession` leaked the keyfile descriptors on their early returns (a scope guard now closes them until
`applyKeyfilesToPassword` takes them over), and desktop `ve_composite_create` refuses a volume that is too small (under 300 KiB), a
password over 128 bytes, or no credential at all BEFORE touching any carrier, because the shared create grows every carrier file first
and only then checks size and password length. Smoke-tested by `./ve_smoke_test composite`: profile (formats, tiers, alignment, files
untouched, invalid arguments), create refusals that leave every carrier byte-identical, create over three carriers of three formats,
unlock in three different carrier orders with files written in one session read back in the next, wrong password, missing carrier, a
plain file (no key derivation), read-only unlock (write refused, carriers untouched), keyfile-only create and unlock, and descriptor
closing on every failure path; `desktop_composite_test.dart` covers the Dart half with a fake engine. A session slot is held for the
duration of a composite call, so two composite calls never pick the same free slot (a normal unlock started at the same moment is not
coordinated with them, as on Android). **Split containers are not done**: `unlockSplitContainer` stays in
`desktopPendingMethods`. Android's `unlockSplitContainer` is a plain delegate to `unlockContainer` and the app does not call it; real
split support there is in the unlock path (a FUSE-backed joined source), and a composite is not equivalent (it is VeraCrypt-standard
only and every part would have to carry a trailer). On desktop it needs an engine-level joined source that feeds the normal unlock
for any format; that is the remaining half of Phase 1d. The "Container splitter" tool (split and join to files) works.
Not exercised: the Dart side (no Dart SDK where this was written; run `flutter test` and `flutter analyze`), Windows, and the Android build
of the shared-code change.

**Check & Repair and header backup (Phase 1b).** `ffi/ve_repair.cpp` wraps `containers/container_repair.cpp` (diagnose and
restore an unmounted container file, diagnose and check a mounted volume's file system, export and restore the header
region) and `ffi/ve_foldervault.cpp` gains `ve_fv_check` / `ve_fv_repair` over `foldervault/fv_check.cpp` plus
`ve_fv_config_file_name` / `ve_fv_validate_config`. The fd-taking calls close the descriptor they are given, exactly like
the JNI layer (a call refused for bad arguments, or by an unreadable keyfile, closes the container descriptor too; the
smoke test checks it); the worker isolate opens the files (so no descriptor crosses an isolate or leaks) and keyfile descriptors are
opened before the target's. `DesktopRepair` (`desktop_repair.dart`) is what `RepairHandlers.kt`,
`HeaderBackupHandlers.kt` and `FolderVaultChecker.kt` do around the native calls: argument mapping, the outcome-to-error-code
mapping (`PASSWORD_INCORRECT`, `PASSWORD_REQUIRED`, `INVALID_VAULT`, `BACKUP_INVALID`, `SIZE_MISMATCH`,
`UNRECOGNIZED_FILE`, `HEADER_UNREADABLE`, ...), the report maps, and the config-file restore (validated, then written beside
the vault's copy and renamed over it). The live repair log is `VE_EVENT_REPAIR_LOG`, forwarded to Dart as `onRepairLog`.
A mounted folder vault is used as the credential by slot (`session_vol`), so its keys never leave the process. The folder
vault is addressed by path and CryFS gets the same `localStateDir` / `tempDir` as unlock. Tested by
`desktop_repair_test.dart` (fake engine) and the folder-vault section of `ve_smoke_test` (check structure-only / wrong password
/ deep / slot credential, refused repair without credentials, config name and validation, for all three formats). Not yet
exercised here: the container-file calls against real VeraCrypt/LUKS files (the engine's own tests cover container_repair),
and Windows (`container_repair.cpp` uses `pread` on a CRT descriptor; Phase 3 verifies that path).

**Archives (Phase 1a).** `ffi/ve_archive.cpp` exposes the archive engine that was already compiled
into the desktop library: `ve_archive_scan`, `ve_archive_extract_entry` (to memory, a host file or a vault file) and
`ve_archive_extract_all` (to a host folder or a vault folder, with progress and cancel). A source is a vault file or a host
file; split sets (`.7z.001`, `.z01` + `.zip`) are found next to the opened file with `std::filesystem` or `ve_list_directory`.
Everything goes through the public `ve_*` stream/write calls, so folder vaults work and **no plaintext is staged on disk
for an in-vault archive** (Android's JNI path is block-volume only and stages folder-vault archives to cache files).
`desktop_archive.dart` maps the eight `VaultArchiveApi` methods plus `pickArchiveFile` and `pickExtractFolder` (the generic
folder picker the extract/export/tool screens share) onto those calls. Browse staging (`archiveStageBrowseEntry`) is the one
place a plaintext file exists: a private, owner-only directory under `$XDG_RUNTIME_DIR` (else the system temp folder), only
`archive_browse_*` files directly inside it can be discarded, removed when the vault locks and at shutdown, purged after a
crash. Tested by `ve_archive_test` (CMake host test, real libarchive, fake vault: short stream reads, split sets,
folder-vault finish semantics, cancel and failure cleanup; also clean under ASan/UBSan) and
`desktop_archive_test.dart`.

`ve_archive_create` writes archives from vault or host sources into a host file or a vault file, or as split parts
(zip `name.z01 ... name.zip`, 7z `name.7z.001 ...`; a part never replaces an existing file, and a failed or cancelled
run removes what it wrote). Sources are opened only while the archive is working on them. The 7z and ISO writers assemble
their output in a temporary file found through `$TMPDIR` (`TMP`/`TEMP` on Windows), so the call takes a `temp_dir`:
`DesktopArchive.createArchive` makes a private folder under the system temp directory for the duration of the call and
removes it afterwards (Android points the same variable at its app cache). Progress is in source bytes, as on Android.
Known gaps: per-filesystem name sanitising when extracting to Windows (reserved names, `?*"<>|`) -- the engine rejects
`..` and `:`, but a name the host file system cannot hold fails that extraction; and, observed with libarchive 3.7.2 under
LeakSanitizer, a cancelled ZIP creation leaks about 280 KB inside the engine's cancel path (`archive_write_fail` followed
by `archive_write_free` in `archiveCreate`; the vendored libarchive was not checked, and the engine is shared with
Android, so it is not changed here).

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

Install `nasm` and `make` too (`sudo apt install nasm make`; MSYS2: `nasm`, `make`, `diffutils`): libjpeg-turbo (image
thumbnails, see "Image thumbnails") and FFmpeg (video thumbnails, see "Video thumbnails") build their SIMD / assembly
code with NASM, and FFmpeg has its own `./configure` + `make`. Without NASM the build still works, with a CMake
warning, and decoding is slower; without `make` the engine is built without native video thumbnails (CMake warns, the
desktop code uses libmpv for them). The native thumbnailers have host tests:

    cmake --build build/desktop-engine --target thumb_test video_thumb_test
    build/desktop-engine/thumb_test                                                              # images
    build/desktop-engine/video_thumb_test android/app/src/main/cpp/imaging/test/fixtures         # videos

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
    pacman -S --needed mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-nasm make diffutils git
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
- Not applicable on desktop: Android's USB host mode (a drive is opened as a disk by the OS instead, see "Raw drives"), the Android file-descriptor tricks.
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

Ending the app runs a clean-up first (`AppLifecycleListener.onExitRequested`): every unlocked vault is
locked (its key material wiped in the engine) and any decrypted "open with" copies are deleted, rather than
relying on the next start's purge. A crash or kill -9 still falls back to that purge. The app asks to exit
when its last window closes with `ServicesBinding.exitApplication(AppExitType.cancelable)`, never
`required`: a required exit skips the question and so skips this clean-up.

### Windows of the app (Linux and Windows)

Every window is a peer, as in a desktop file manager: closing the first one does not close the others, and the
app ends when the last one is gone.

- `main()` starts the app with `runWidget`, not `runApp`, when `DesktopWindowing.ensureReady()` succeeds. Nothing is
  drawn in the runner's own window (it is never shown: the runners only show it after its first frame). The root
  is `DesktopAppHost`, a `ViewCollection` of the main window (`VaultExplorerApp`) and the secondary windows
  (`SecondaryWindows`: file manager windows, vault settings).
- `DesktopWindowPolicy` holds the rules (pure Dart, tested without Flutter): the main window closing closes the
  windows that only serve it (vault settings) and leaves the independent ones (file manager windows); the app ends
  when no main window and no independent window is left; a lock brings the main window back (it draws the lock
  gate) *before* closing the others, or the app would exit instead of locking.
- `MainShell` is more than a page: while it is on screen it answers the file manager windows
  (`FileManagerEnvironment`), forwards lifecycle changes to the auto-lock, and carries out the app lock. If the main
  window is closed while file manager windows stay open, `DesktopSessionKeeper` takes those three jobs over from the
  app's providers, so the remaining windows keep working and stay auto-locked. It lets go when a lock reopens the
  main window.
- Without native windows (Android, `VE_MULTI_WINDOW=0`, or an embedder that refuses them) the app runs in the
  runner's single window exactly as before. If only the main window cannot be created, it is drawn in the runner's
  window instead, and closing it ends the app.

## Folder vaults (gocryptfs / Cryptomator / CryFS) -- Linux and Windows

Main (v1.50) moved the three formats into a platform-neutral C++ core (`foldervault/`, linked as
`foldervault_core`); the desktop engine reaches it through `ffi/ve_foldervault.cpp`, the desktop twin of
`jni/foldervault_bridge.cpp` (same open/create semantics; `fv::PosixStorage` over an ordinary directory).

An unlocked vault is parked in a **volume slot** (the same slot ids containers use; Dart allocates them).
The slot table is the engine's one `vm::VolumeManager` (`ffi/ve_volumes.h`); a vault is a `vm::FolderVaultVolume` in
it and a container a `vm::BlockVolume`, so the file-level calls in `ve_engine.cpp` need no per-family branch: list / read /
write / rename / delete / mkdir / set-mtime / streams / space info / lock work on either. Whole-file import / export
reach the vault through `vefv::importFile` / `exportFile` (host paths, with progress), and `ve_write_file_at` /
`ve_truncate` answer `VE_ERR_UNSUPPORTED` for a vault (its writer is sequential). `ve_copy_file` between any mix of container and vault slots streams through memory in 2 MiB
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
- The NFC filename normaliser hook (`fv::setNfcNormalizer`) is installed by `ffi/ve_nfc.cpp` (utf8proc, fetched in
  `CMakeLists.txt`, desktop only), so Cryptomator names written in decomposed form open by their composed form as
  on Android; `ve_smoke_test fv` checks it. A name that is not valid UTF-8 is left as it is (see `foldervault/README.md`).
- **Windows:** `foldervault/fv_storage_win.cpp` is the Win32 twin of the POSIX-only `fv_storage.cpp` (same
  `fv::PosixStorage` interface; UTF-16 paths in the `\\?\` form, so no MAX_PATH limit and no DOS device names;
  path segments with `\`, `:` or wildcards are refused; only real symlinks / junctions count as links, not OneDrive
  placeholders). The few raw host-file calls in the CryFS code and in import/export go through `foldervault/fv_os.h`
  (UTF-8 -> UTF-16, binary mode; plain POSIX calls elsewhere). CMake builds the core on Windows (the `VE_NO_FOLDERVAULT` stubs are gone: the engine cannot be built
  without it). Before this, every `ve_fv_*` call was a stub (`ve_fv_supported()==0`, probe "not a vault"),
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

### Image thumbnails

`getImageThumbnail` / `getImageThumbnailWithSize` (and the large-image preview, which asks for 2048 px) are made by
the engine itself, in C++, the way Android's BitmapFactory path does it (ABI 15: `ve_image_thumbnail`,
`ve_image_thumbnail_file`, `ve_image_thumbnail_mem`; the decoding is `imaging/thumb.cpp`, platform-neutral, with a
host test):

```
host -> DesktopImages (desktop_images.dart)
          |- DesktopNativeThumbnails (desktop_native_thumbnails.dart): a pool of its own, min(cores-1, 8) workers
          |     '- one blocking native call: read through a 256 KiB read-ahead, decode, shrink, encode
          '- Flutter's codecs, only for what the engine does not handle (GIF, BMP, ICO, animated WebP, CMYK JPEG)
             or when the native pool cannot run: whole file read into Dart, dart:ui, PNG out
```

- **JPEG** is decoded at 1/2, 1/4 or 1/8 size straight from the DCT (libjpeg-turbo's scaled IDCT), as much as keeps
  the result at least the thumbnail's size, then box-filtered to the exact size. The entropy decode still reads
  every byte of the file, so a photo costs a few tens of milliseconds at 24 MP, not a few. **PNG** is decoded row by
  row into a streaming box filter (memory is proportional to the thumbnail; only an interlaced PNG needs the whole
  picture). **WebP** is scaled inside libwebp while decoding. EXIF orientation is applied and the reported source
  size is the upright one, as on Android.
- The answer is a JPEG of the requested quality, or a PNG when some pixel is really not opaque (the Flutter route
  always answered PNG; a transparent picture still shows its transparency).
- Thumbnails run in their own worker pool, so a screen full of tiles never queues a directory listing or an unlock
  behind it, and no file is copied across an isolate boundary: only the few-KB result is.
- Size guards mirror Android's contract: a source above 256 MiB, or one whose decode would need more than 1 GiB
  (a progressive JPEG or interlaced PNG; a baseline JPEG and a plain PNG stream and have no such limit) answers
  `IMAGE_TOO_LARGE`; running out of memory answers `OUT_OF_MEMORY`. All decoders in flight share a 1.5 GiB budget,
  so several big ones take turns instead of exhausting the machine.
- Local-storage items and the temp files of archive previews (`isLocalStorage`) are read from the host path. The
  Flutter route ignored that flag and failed on them.
- The desktop capability tier (which sizes the Dart-side thumbnail concurrency and caches) is now "LOW" only up to 2
  logical processors, "HIGH" from 6 (it was 4 and 8): a computer is not a phone.
- Codecs (desktop engine only, pinned, in `imaging_deps.cmake`): libjpeg-turbo (built through ExternalProject,
  because its CMakeLists refuses `add_subdirectory`), libpng (compiled from source against the engine's zlib),
  libwebp (decoder linked into the engine; the encoder only into the host test). They are listed in NOTICE.md.
  Android builds none of this.
- Not done natively: GIF / BMP / ICO / TIFF (Flutter fallback), animated WebP (Flutter shows the first frame), ICC
  colour profiles, HEIC / AVIF / JPEG XL (neither route can decode them).

### Video thumbnails

`getVideoThumbnail` / `getVideoThumbnailWithSize` are made by the engine itself where it can (ABI 16:
`ve_video_thumbnail`, `ve_video_thumbnail_file`; `imaging/video_thumb.cpp` on a minimal static FFmpeg, built by
`ffmpeg_deps.cmake`), and by libmpv only for what the engine cannot open. Android uses MediaMetadataRetriever, which
is also a native decode with no player.

```
host -> DesktopVideoThumbnails (desktop_video_thumbnails.dart: which frame(s), slots, cancel on lock)
          |- native: DesktopNativeThumbnails.videoVaultFile / videoHostFile   (the thumbnail pool; one blocking call)
          |     '- ve_video_thumbnail: open the container through the vault stream, decode ONE keyframe, scale, rotate,
          |        blank check, JPEG out -- the whole frame-selection strategy runs in that one call
          |- grabFrameWithMpv   (mpv_frame_grabber.dart: fresh paused Player + VideoController, first picture,
          |                      Player.screenshot as JPEG, player disposed)      <- only when native says "unsupported"
          '- nativeFrameDecoder (video_frame_decoder.dart: that mpv frame goes to the thumbnail pool for scaling,
                                  the 8x8 blank check and a small JPEG; Flutter's decodeVideoFrame is its fallback)
```

- **Why**: the libmpv route started a whole player (software renderer, texture, a media-server session, 20 s timeout)
  for every frame it wanted -- the start of the video, and again for every blank-frame retry -- driven from the UI
  isolate, two at a time. The native route costs the container header plus one keyframe, with no UI-isolate work and
  no media server, and several run at once on worker threads. Measured on one slow core of a cloud Xeon (not
  representative of a desktop): about 20-35 ms per thumbnail for 1080p H.264 and about 110-160 ms for 4K HEVC; the
  libmpv route was not measured.
- **What the engine decodes** (`ffmpeg_deps.cmake`, software only): MP4/MOV, Matroska/WebM, AVI, MPEG-PS/TS, FLV,
  ASF, Ogg, IVF with H.264, HEVC, VP8, VP9, MPEG-4 part 2, MPEG-1/2, H.263, WMV/VC-1, MJPEG, Theora, ProRes. **AV1 is
  not in the list** (FFmpeg's own AV1 decoder is hardware-only; software needs dav1d): the engine answers
  "unsupported" and the libmpv route makes that thumbnail, as it does for any other container or codec outside the
  list. An engine built without `make` has no FFmpeg at all and answers "unsupported" for everything.
- Rotation recorded in the container (phones), the pixel aspect ratio and the colour matrix / range (BT.601, BT.709,
  BT.2020) are applied, so a portrait phone video is upright and HD video has the right colours; the reported source
  size is the picture as shown. HDR is not tone-mapped (it looks flatter than in a player). It decodes the nearest
  keyframe at or before the chosen point (never a delta frame), skips the loop filter and decodes on one thread.
- Frame choice follows Android: `firstFrame` = the start; `frameAtPercentage` = `framePosition` of the duration
  (clamped to 5%..90%); `hybrid` (default) = the start, and if that frame is blank (`isLikelyBlank`, a port of the
  Kotlin heuristic) the first non-blank frame at `framePosition`, 25% or 45%. An explicit `timeUs` (the video editor)
  is used as is and never retried; one past the end gives the last keyframe.
- At most 2 native video thumbnails at a time (so a burst, such as the editor's film strip, cannot fill the thumbnail
  pool and hold image tiles back), and 2 libmpv players for the fallback. A locked vault drops its queued requests
  and the result of a running one. A source that cannot be read, or a video with no decodable picture, answers
  `null` (placeholder icon), as for an Android `FRAME_FAILED`; the whole call has a 20 s deadline.
- The libmpv route: the loopback media server session of the file (so nothing decrypted touches storage), or a
  `file:` URL for local-storage items and the temp copies archive previews use; the player gets the same lock-down as
  playback (`cache-on-disk` off and verified, sidecar loading off, protocol whitelist) plus software decode and
  rendering, no audio output and a 16 MiB read-ahead cap.
- Tests: `imaging/test/video_thumb_test.cpp` on the tiny videos of `imaging/test/fixtures` (regenerated by
  `make_fixtures.sh`): every container and codec, the three rotations, pixel aspect, colours, frame selection with a
  black start, AV1 / audio-only / garbage / truncated / unreadable sources, many threads. The Dart side:
  `desktop_native_thumbnails_test.dart` (native first, libmpv only on "unsupported", the concurrency cap, cancel on
  lock), `video_thumbnail_logic_test.dart` and `desktop_video_thumbnails_test.dart`. The mpv and `dart:ui` adapters
  have **not been run inside Flutter**: they follow `desktop_video_backend.dart` and `desktop_images.dart` closely, but
  `Player.screenshot` and the first-frame signal of an off-screen `VideoController` are the first things to check on
  a real Linux / Windows build -- and they matter much less now that they are only the fallback.

## Not yet

- Engine-channel coverage: `ChannelMethods` has 283 methods. The desktop host answers 155 of them (including the
  crypto primitives), gives 42 more an Android-only default (`_androidOnlyDefaults`), lists 66 as Android-only
  (`desktopAndroidOnlyMethods`: automation, panic, quick capture, share sheet, formatting a USB drive, SAF, APK install, Jetpack PDF, ...)
  and 20 as pending (`desktopPendingMethods`, grouped by the plan phase that delivers them:
  split containers, AVIF, PDF, comic/EPUB, image probing, audio/video editing). The coverage test fails when a method is in none of these places or is in two of them, so the split above
  stays true; run it to see the current numbers. These counts cover the one engine channel only. Camera, Media3,
  picture-in-picture, brightness, panorama, disguise mode and the platform views use their own channels, which the
  desktop binding passes to Flutter (they throw `MissingPluginException` on desktop unless the Dart caller is guarded).
  Answered since the earlier counts: `getAppVersion` (the version name from `desktop_host_info.dart`; a test keeps it
  equal to `pubspec.yaml`), `getContainerSizeInfo` (file size, plus free space from `df -Pk` on Linux or PowerShell
  on Windows, `null` when unknown), `resolveRawStoragePath`, `exportAppSettingsFile` / `importAppSettingsFile`
  (`file_selector` dialogs), `writeBackFile` (the same `ve_import_file` call the import path uses), and explicit
  "unsupported" answers for the sensitive-clipboard pair (the Dart caller falls back to Flutter's clipboard) and
  `setKeepScreenOn`.
- Windows: folder vaults on a real Windows machine (above), the new ext resize sources (`e2fsprogs/resize`, `filesystems/ext_resize_glue.c`) under
  MinGW, and re-running the engine smoke test after the rebase.
- PDF, camera, video/audio editing -- need their
  desktop backends (they are platform code on Android). Video **playback** and **thumbnails** are done (below);
  scrub-preview frames, picture-in-picture and background playback / media session are not.
- Import (`desktop_transfers.dart`, rules in `desktop_import_policy.dart`): names are checked with Android's two
  rule sets (encrypted vault for a folder vault, the conservative union for a disk-image container); a name that
  cannot be held is skipped and reported (`onImportItemSkipped`); siblings that differ only by case on a
  case-insensitive destination get unique names; every file is hashed before it is written and read back out of the
  vault afterwards, and "delete after import" is only offered after a complete run whose read-back matched. The
  rules are checked against the same known-answer table as Android (`test/fixtures/import_policy_golden.tsv`). Not
  yet: progress events while the read-back runs, and the same checks for export.
- Share sheet; JPEG/WebP encoding for the image editor (PNG only for now).
- Pre-flight free-space check on create (Android reports `INSUFFICIENT_SPACE`; desktop just fails).
- Windows: the engine was validated under Wine on v1.39 (see "Windows" above; re-run it after the rebase); the
  Flutter app on Windows is untested.
- macOS / iOS: not started.

## Raw drives (BitLocker, VeraCrypt, LUKS disks and partitions)

"Mount existing container" opens a file picker, so a disk or partition cannot be chosen there. "Mount drive" (desktop's
counterpart of Android's "Mount USB drive", same sheet) lists the disks the OS knows and unlocks the one you pick.

How it works. The engine already unlocks a raw device (`session/session_prepare.cpp`, `prepareUsbSession`): it scans the
MBR/GPT partitions for LUKS and BitLocker, then tries VeraCrypt at the start of the device and of every partition (with the
hidden-volume header). It reads and writes in 512-byte sectors through the `usbReadSectors` / `usbWriteSectors` /
`usbSyncDevice` hooks, keyed by volume slot. On Android those call into Kotlin; on desktop `ffi/ve_callbacks.cpp` forwards
them to `ffi/ve_raw_device.cpp`, which keeps one open device per slot.

| File | Role |
|---|---|
| `ffi/ve_raw_device.{h,cpp}` | slot registry, the 512-byte view of a device whose real sector is larger (4Kn: read-modify-write), BitLocker/LUKS probing for the list, JSON |
| `ffi/ve_rawdev_posix.cpp` | Linux: `open` (`O_EXCL` for a writable block device), `BLKGETSIZE64`/`BLKSSZGET`, `pread`/`pwrite`/`fsync`, `/sys/block` listing with stable `/dev/disk/by-id` paths |
| `ffi/ve_rawdev_win.cpp` | Windows: `\\.\PhysicalDriveN`, sector-aligned I/O, `FlushFileBuffers`; includes `<windows.h>` and no engine header |
| `ve_list_block_devices`, `ve_unlock_device` | the C ABI (ABI 14). `ve_lock` also closes the device |

On the Dart side the three USB channel methods are answered by `DesktopEngineHost`: `listUsbDevices` (the disk list),
`requestUsbPermission` (a re-check: desktop has no permission dialog) and `unlockUsbContainer`. A drive is addressed as
`usb:<device path>`, like an Android USB source, so cards, re-unlock and lock need no special case. Formatting a drive
(`createUsbContainer`, `getUsbDeviceCapacity`) stays Android-only.

What to know:

- **Permission.** Linux needs root, membership of the `disk` group, or a udev rule; Windows needs an elevated process. The
  list shows disks it cannot open, and the unlock says why. (Unprivileged access through udisks2 `OpenDevice` is not done.)
- **Safety.** A writable open of a Linux block device is exclusive (`O_EXCL`): the kernel refuses it while the disk or one of
  its partitions is mounted, and the unlock reports that; mount read-only to look anyway. The list tags disks that are
  mounted and the disk that carries the running OS. On Windows the OS blocks writes to the sectors of a mounted volume.
- **Disk images.** A regular file is accepted as a "disk" by `ve_unlock_device`; the native smoke test uses that to run
  without root (`ve_smoke_test device`: whole-device VeraCrypt, raw LUKS2, an MBR image with a VeraCrypt partition).
  `ve_raw_device_test` covers the sector adapter, bounds, the same-device guard and the probing against a fake disk.
- **Limits.** VeraCrypt *system* encryption (header at sector 62 of the boot drive) is not handled by the engine. On 4Kn disks
  whole-device volumes work, but the engine's partition scan assumes 512-byte sectors, so volumes inside partitions are not
  found. A raw LUKS/BitLocker volume with no partition table (for example `/dev/sdb1` on its own) is tried on desktop only
  (`VE_DESKTOP_RAW_DEVICES` in `session_prepare.cpp`). The Windows `PhysicalDriveN` number can change between boots, so a saved
  Windows drive may need to be picked again (Linux keeps a stable by-id path).
