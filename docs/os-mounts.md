# OS mounts (desktop)

The desktop equivalent of Android's "expose this folder through the DocumentsProvider": an unlocked vault,
or one folder of it, becomes a real directory, so the file manager and every other program can use it.

Status: **Linux works and is tested end to end.** The **Windows (WinFsp) backend is written and compiles but
has never been run** (no Windows/WinFsp available where it was written): treat it as a first draft to test on
a real machine. The Dart wiring has not been compiled either (no Dart SDK was available).

## Design

```
file manager / any program
        |  POSIX (open/read/write/rename/...)
   kernel FUSE
        |
ve_mount_fuse.cpp   libfuse3, loaded with dlopen -> thin translation, mount lifecycle
        |
ve_mount_fs.cpp     MountFs: platform-neutral file layer (paths, dir cache, handles, write model)
        |  public C ABI only (ve_*)
   volume slot      FAT/exFAT/NTFS/ext containers  +  gocryptfs / Cryptomator / CryFS vaults
```

It is file-level on purpose. VeraCrypt exposes a decrypted *block device* and lets the kernel mount a
filesystem on it; that cannot work for folder vaults (no block device), would bypass the engine's own
userspace filesystems, and needs root. This mirrors Android's `ContainerDocumentsProvider` instead, and
works the same for every format behind a slot.

The Windows glue (`ffi/ve_mount_winfsp.cpp`) is a second thin translation layer over the same `MountFs`,
using WinFsp's FUSE 3 compatibility API: same operation set, same `-errno` results (WinFsp's "Windows"
environment maps the CRT's errno values, which MinGW uses). `winfsp-x64.dll` is loaded at run time from
WinFsp's install dir (the header's `FSP_FUSE_API_CALL` macro is overridden to resolve each function lazily),
so the engine DLL still loads without WinFsp and `ve_mount_supported` says why mounting is unavailable.

## Write model

* Block containers: real random-access writes (`ve_write_file_at`, `ve_truncate`); consecutive writes are
  coalesced (1 MiB) so a 128 KiB FUSE write is not a directory commit.
* Folder vaults accept chunks in order from offset 0 plus `ve_fv_finish_write`, and a file only appears at
  that point. A handle is therefore either
  * **Stream**: a new or truncated file written front to back, sent straight to the vault; or
  * **Buffered**: anything else (modify in place, write after commit): the file is held in memory
    (default cap 256 MiB per open file, `max_buffer_mb`) and rewritten on flush.
* The one pattern that cannot be honoured: seeking backwards inside a Stream that has already handed the
  data to the vault (beyond the unsent 1 MiB window). It fails with EIO instead of corrupting the file.
* CryFS lays chunks over the old content (keeps a longer tail), unlike gocryptfs/Cryptomator which start a
  fresh file at offset 0. For CryFS a truncating open therefore removes the old file first, which is what
  POSIX `O_TRUNC` means anyway.
* Plaintext never touches host storage from the mount layer. **Exception (existing engine behaviour):**
  CryFS stages in-flight writes in a scratch file under the `temp_dir` given to `ve_fv_unlock`; make sure
  that directory is RAM-backed (e.g. under `$XDG_RUNTIME_DIR`).

## Lifecycle (copied from Cryptomator's jfuse / fuse-nio-adapter, adapted)

* `ve_mount` returns only after the kernel has actually asked the filesystem something (a probe `stat`).
* Unmount is polite first (`fusermount3 -u`, refused with `VE_ERR_BUSY` while files are open), forced only
  on request. `ve_lock` always unmounts first (polite, then forced) so keys are never wiped under a live
  mount, and open files cannot keep a locked vault alive.
* `-o auto_unmount` lets the kernel clean up if the process dies; a dead mount left by a crash is detached
  and reused on the next mount.
* A mount ejected from outside (file manager, `fusermount3 -u`) is detected; Dart polls `ve_list_mounts`
  every 2 s and reaps it. (`ve_set_mount_callback` exists for a push model.)
* The FUSE loop is single-threaded: the engine serialises each volume behind one lock anyway.
* Requires `libfuse3` + `fusermount3` at runtime and `libfuse3-dev` headers at build time (libfuse3 itself
  is never linked; without the headers the engine builds with mounts disabled and
  `ve_mount_supported` says why).

## C ABI (ABI version 9)

`ve_write_file_at`, `ve_truncate`, `ve_create_empty_file`, `ve_mount_supported`, `ve_mount`, `ve_unmount`,
`ve_list_mounts`, `ve_set_mount_callback`, `ve_mount_last_error`; result codes `VE_ERR_UNSUPPORTED` (9),
`VE_ERR_BUSY` (10). Details are in `ffi/ve_engine.h`.

Dart: `ve_native.dart` (bindings), `engine_worker_pool.dart` (ops `mountSupported` / `mount` / `unmount` /
`listMounts`), `desktop_mounts.dart` (mount point policy `~/.local/share/VaultExplorer/mnt/<name>`,
bookkeeping, eject watcher), and `desktop_engine_host.dart` answers the three existing channel methods
(`mountContainerFolder`, `unmountContainerFolder`, `getMountedContainerFolders`).

## What triggers a mount (desktop)

| In the app | What happens on desktop |
| --- | --- |
| "Document provider" on a container (unlock sheet, or settings of an unlocked container) | the whole vault is mounted at unlock / immediately, and the mount folder is opened |
| Expose a folder (browser) | that folder is mounted and opened; remembered folders (`autoMountFolders`) are re-mounted at unlock without opening a window |
| Un-expose / lock | unmounted (`ve_lock` always unmounts first) |

Mounts live under `~/.local/share/VaultExplorer/mnt/<name>` (a hidden path) and, on Linux, are listed in the
file manager's sidebar -- see below.

## Sidebar entry (Linux)

A FUSE mount is not a "device" to Dolphin or Nautilus, so it does not appear by itself. `ffi/ve_mount_places.cpp`
(like Cryptomator's `integrations-linux`) adds it to:

* KDE Dolphin: `$XDG_DATA_HOME/user-places.xbel` (an XBEL bookmark tagged with its own metadata owner)
* GTK file managers (Nautilus, Thunar, Nemo, PCManFM...): `$XDG_CONFIG_HOME/gtk-3.0/bookmarks`

Only files that already exist are touched; writes are atomic; the entry is removed on unmount, eject and lock;
entries a crashed run left behind are removed the next time anything is mounted (a small record is kept in
`$XDG_STATE_HOME/VaultExplorer/mounts.txt`). Set `VE_NO_PLACES=1` to turn it off. Tested with fake home
directories (`ve_mount_test places`, and through the real-mount test).

## If nothing happens

1. The engine was built with FUSE: the CMake output must say `FUSE 3 headers found`; or
   `nm -D libvaultexplorer_engine.so | grep ve_mount` must list `ve_mount`.
2. At runtime: `which fusermount3`, `ls -l /dev/fuse`, `ldconfig -p | grep libfuse3`.
3. Run the app from a terminal and look for `[desktop-mounts]` lines -- they give the reason
   ("libfuse3 not found", "mount point is not empty", "this engine build has no OS-mount support", ...).
4. Flatpak / Snap sandboxes cannot use FUSE without extra permissions.
5. Is it really mounted? `mount | grep vaultexplorer` and `ls ~/.local/share/VaultExplorer/mnt`. If it is, but the
   sidebar shows nothing, check that `~/.local/share/user-places.xbel` (Dolphin) or
   `~/.config/gtk-3.0/bookmarks` exists -- they are only edited when they already exist.
6. The app and the engine must agree on the ABI: `kVeAbiVersion` in `ve_native.dart` must equal
   `VE_ABI_VERSION` in `ve_engine.h` (both 9).

## Windows (WinFsp) specifics

* Needs WinFsp installed on the machine (Core component) and, to build, its headers (Developer component, or
  `-DVE_WINFSP_INCLUDE_DIR=<winfsp>/inc`). The headers are not vendored: WinFsp is GPLv3 with a FLOSS
  exception, so check that against this project's license before shipping anything that bundles it.
* Mount point: a drive letter (`X:`, chosen from Z: downwards by the Dart side) or a directory that does
  **not exist yet** (WinFsp creates it; an existing empty directory is removed first). Dart uses drive
  letters, which appear in Explorer at once.
* Teardown order (jfuse#176): `fuse3_exit` only stops the loop; `fuse3_unmount` / `fuse3_destroy` run after
  the loop thread has exited. A graceful unmount is refused while files are open (WinFsp has no equivalent
  of `fusermount3 -u` failing with EBUSY, so it is decided from the open-handle count).
* Overwrite arrives as `truncate(path, 0, fi)`, not `O_TRUNC`; create arrives as `create` with
  `O_CREAT|O_EXCL|O_RDWR`. Both are handled by `MountFs`.
* Folder vaults on Windows use `foldervault/fv_storage_win.cpp` (see `docs/desktop-port.md`); only tested under Wine
  so far. They mount through the same `MountFs` slot path as on Linux.
* Unverified: everything that needs a running WinFsp (mount, Explorer behaviour, eject detection, lock while
  mounted). The code compiles against WinFsp's real headers with MinGW only.
* This repo's own Windows cross-build did not complete on Ubuntu 24.04's MinGW (pre-existing, unrelated to
  mounts): `ext_backend.cpp` uses POSIX `setenv`/`unsetenv` (not in MinGW-w64; a two-line `_putenv_s` shim
  fixes it) and `mkntfs_embedded.c` fails to compile. Check that your Windows toolchain builds them.

## Tests

```sh
cmake -S android/app/src/main/cpp -B build -G Ninja -DVAULTEXPLORER_DESKTOP=ON
cmake --build build --target ve_mount_test
build/ve_mount_test                       # file layer on fat exfat ntfs ext4 gocryptfs cryptomator cryfs
build/ve_mount_test --os-mount fat ext4 ntfs gocryptfs cryptomator cryfs   # real kernel mounts
```

`--os-mount` drives the mount with `cp`, `cmp`, `sed -i`, `dd conv=notrunc`, `truncate`, `mv`, `rm`,
`diff -r`, and checks busy-unmount, external eject and lock-while-mounted. Every client call runs in a child
process with a hard timeout, and a watchdog aborts only the test's own FUSE connection if it overruns --
this process is both FUSE server and (through children) client, so a bug would otherwise wedge it.

## Known limits / follow-ups

* Windows: see above (untested on real Windows; folder vaults only exercised under Wine).
* macOS not covered.
* Reads go through `ve_read_file_chunk` per request (open/seek/read/close inside the backend); the
  stream API would be cheaper for large sequential reads.
* No xattrs, no `fallocate` modes other than plain extend, `chmod`/`chown` are accepted and ignored.
* NTFS: ntfs-3g prints "Could not delete inode cache entry" on unlink/rename (also in the unmodified
  smoke test), and in some runs "Index lookup failed" / "Failed to sync FILE_NAME" -- all checks pass, but
  run `ntfsfix`/`ntfsck` on a vault used heavily through a mount before trusting it.
