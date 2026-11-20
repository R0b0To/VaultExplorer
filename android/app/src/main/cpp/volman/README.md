# volman -- one volume interface and slot table, in portable C++

The layer that makes every unlocked volume look the same to a front-end:
`vm::Volume` is the operation set (list, chunked read/write, `importStream`,
batching, space/info, optional native read streams) and `vm::VolumeManager`
is the slot table plus every operation addressed by slot. Platform-neutral
C++20: **no JNI, no Android, no Flutter**. Android's JNI layer and a desktop
front-end (FUSE, CLI, FFI) are meant to sit on the same calls.

```
vm_volume.h        vm::Volume -- the interface; Status, Observer, ByteSource, SpaceInfo, InfoItem
vm_manager.h/.cpp  vm::VolumeManager -- slots, forwarding by slot, streams, copyFile   (volman_core)
vm_foldervault.*   FolderVaultVolume -- an fv::Vault (gocryptfs / Cryptomator / CryFS) as a vm::Volume   (volman_core)
vm_block_volume.*  BlockVolume -- an engine-mounted block-device volume as a vm::Volume   (needs the engine)
vm_xfer.*          VolumeFileSource + hashVolumeFile -- a vault file as a byte source; its digests in one native pass   (volman_core, uses ../xfer)
test/vm_tests.cpp        in-memory volume tests + real vaults behind the manager
test/vm_block_tests.cpp  BlockVolume on the real volumes[] table with a fake filesystem layer, beside real vaults
```

`vm_block_volume.cpp` needs the engine (`session/volume_state.h`, `filesystems/fs_ops.h`,
`io/virtual_block_device.h`), so it is compiled into the target that has the engine -- the
Android library today, a desktop engine target later -- not into `volman_core`.

## Using it

```cpp
vm::VolumeManager mgr;                                   // 8 slots
auto a = fv::openGocryptfs(storageA, pwA, nA, false, env);
auto b = fv::openCryptomator(storageB, pwB, nB, false, env);
int ia = mgr.attach(vm::wrapFolderVault(std::move(a.vault)), "/vaults/a");
int ib = mgr.attach(vm::wrapFolderVault(std::move(b.vault)), "/vaults/b");

std::vector<std::string> wire;
mgr.listDirectory(ia, "docs", wire);                     // "F|<size>|<mtimeSecs>|<name>", "D|..."
mgr.copyFile(ia, "docs/a.bin", ib, "in/a.bin", &observer);   // through memory, no temp file
mgr.close(ia);                                           // slot is NotUnlocked from here on
```

## Rules

- **Volumes lock internally.** The manager only guards its own tables, so no
  lock is held across a transfer and a long copy never stalls listings.
  `close()` empties the slot first (new calls see `NotUnlocked`), ends the
  volume's streams, then lets the volume drain calls already running.
- **No plaintext on disk.** `copyFile` reads a chunk from the source, hands it
  to the destination's `importStream` and wipes it. It is deliberately not a
  `writeFileChunk` loop: CryFS's incremental writer stages data in a scratch file.
- **A copy is all or nothing.** A short read fails the copy instead of ending it;
  a failed or cancelled copy deletes what it created under the destination path;
  copying a file onto itself fails without touching it.
- **Never throws.** `vm::Volume` reports failure as `false` / `-1` / `nullopt`
  (the folder-vault adapter turns `fv::Error` into that).
- Directory listings use the wire format of `filesystems/dir_entry_wire.h`; the
  type tag is explicit, never inferred from a name.

- **A volume can die behind the manager's back.** `Volume::alive()` goes false when its
  container was locked or its vault closed by someone else; the manager answers `NotUnlocked`
  and frees the slot on the next `reserveSlot()` / `attach()` (or `reapDead()`). A
  `BlockVolume` is tied to the unlock session it was made for (`VolumeState::sessionEpoch`), so
  it never starts serving a different container unlocked into the same engine slot.
- **`BlockVolume::close()` only detaches.** Locking a container (lock policy, flush, key wipe)
  belongs to the session layer.
- **Destroying a manager closes its volumes but notifies no listeners.**

## Not done yet

- Kotlin still does most of the dispatch: only the cross-volume copy (`ContainerFileSystem`) goes
  through `NativeVolumeManager`. Listing, per-chunk I/O, read streams, `ContainerEngine`'s
  routing and `ContainerSessionRegistry`'s locks move over one operation at a time.
- Container-level info (format, cipher, KDF) and the lock/unlock flow itself are not in the
  manager; `BlockVolume::info()` reports only the mounted filesystem's label.
