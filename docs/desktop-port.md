# Desktop port (Linux first, Windows next)

Status: **work in progress.** The native engine builds and passes its smoke test on Linux. The Dart
host is written but has not yet been run inside Flutter. Windows is partly prepared (see below).

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

1. One-time: generate the runner (it does not exist yet, the repo only has `android/`):

       flutter create --platforms=linux .

2. Bundle the engine library: add to `linux/CMakeLists.txt`, next to the other `install()` calls:

       set(VE_ENGINE_LIB "${CMAKE_CURRENT_SOURCE_DIR}/../build/desktop-engine/libvaultexplorer_engine.so")
       install(FILES "${VE_ENGINE_LIB}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)

   (or point `VE_ENGINE_LIBRARY` at the .so while developing).

3. `flutter pub get && flutter run -d linux`

On first run expect some rough edges: methods the desktop host does not implement yet reply `null`
and are logged once in debug builds as `[desktop-engine] not implemented yet: <method>`. Paste
those lines back and they become the to-do list.

## What works (design scope of this cut)

Add a vault (multi-select file picker), probe, unlock (VeraCrypt / LUKS / BitLocker / plain block
images, keyfiles, hidden-volume protection, cached derived keys passed through), unlock progress
events, cancel, **create** (VeraCrypt, LUKS1/2, optional embedded hidden volume; built under a
temporary name next to the destination and renamed into place only when complete), browse, read,
write, create directory, rename, delete, set mtime, copy between volumes, space info, lock.

## Not yet

- Folder vaults (Cryptomator / gocryptfs / CryFS) -- still Kotlin, so their add and create flows do
  nothing on desktop; they need porting to C++.
- Import / export / split-join / archive / thumbnails / media / PDF / camera -- need their
  desktop backends; copy/import/export progress events are drained but not yet forwarded.
- Pre-flight free-space check on create (Android reports `INSUFFICIENT_SPACE`; desktop just fails).
- Windows: all 41 engine C++ files pass a MinGW syntax check and the POSIX shims exist
  (`ffi/compat/`, `ffi/ve_win_platform.cpp`), but 16 C files still need work (Endian.h guard, ntfs-3g
  POSIX bits, Argon2 threading) and nothing has been linked or run there. Use MSYS2 UCRT64.
- macOS / iOS: not started.
