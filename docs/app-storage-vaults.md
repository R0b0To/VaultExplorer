# App storage vaults and moving vaults (Android)

A vault can live in **app storage**, the app's private `<filesDir>/vaults` folder, instead of at a
location the user picked, and any vault can be moved in or out of it.

"Internal Storage" elsewhere in the app means the device's shared volume. This feature is always
called **App storage** in the UI to keep the two apart.

## What is stored where

| Vault kind | In app storage |
|---|---|
| Container file (VeraCrypt, LUKS, ...) | `<filesDir>/vaults/<name>` |
| Folder vault (Cryptomator, gocryptfs, CryFS) | `<filesDir>/vaults/<name>/` |

A vault there is addressed by a plain `file:///data/user/<n>/<pkg>/files/vaults/<name>` URI, so every code
path that already handled `file://` (unlock, lock, session registry, document provider, automation) works
unchanged. `AppStorageVaultUri` (Dart) recognises these URIs for the UI only; every destructive operation is
re-checked natively against the real directory (`AppVaultStore.isInside`, which resolves `..` and symlinks).

Needing no storage permission and being invisible to other apps is the point. The cost: the vault is gone if
the app is uninstalled, its data is cleared, or the **tier-3 panic purge** runs (it shreds all of `dataDir`,
including `files/vaults`; `StorageShredder` is deliberately untouched). Android backup is disabled, so there is
no copy. The create sheet, the move dialog and the README say so.

## Moving a vault

`VaultRelocationService` (pure Dart, tested with fakes) drives three steps. The order is the safety property:

1. **Copy and verify** (`relocateToAppStorage` / `relocateFromAppStorage`). The vault is copied, then read back
   and compared by SHA-256 per file, with no missing or extra entries. The source is hashed as it is read, so
   a truncated read is also caught (`TreeCopier.copyFile` checks the bytes read against the reported length).
   The copy is built under a hidden `.part-*` name and renamed into place only when complete. The original is
   not touched. Any failure removes the partial copy and changes nothing.
2. **Switch** (`ContainerRepository.relocate`). The record keeps its place in the list and everything stored
   under the old URI (saved password, pattern/PIN hash, keyfiles, document-provider folders, PIM, bookmarks) is
   re-saved under the new one, then the old URI's state is removed. If saving fails, the new registration is
   rolled back and the old one is untouched, and the service then discards the copy.
3. **Finish** (`finalizeRelocation`). The original is deleted (optional, default on) and the old location's
   native automation grant is cleared. By now the vault already works from its new location, so a failure here
   only leaves the original behind.

Crash analysis: killed during 1, the original is intact and registered (a stray `.part-*` is swept on the next
`getAppStorageInfo`). Killed between 1 and 2, the original is intact and registered and the copy is an
unregistered duplicate. Killed between 2 and 3, the vault works from the new location and the original is a
stray file. Never neither.

`finalizeRelocation` and `discardRelocationCopy` only act on copies **this process** made and verified
(`verifiedCopies`), so a confused caller cannot make them delete arbitrary files. After a restart they refuse.

### Policy decisions inside the move

* **Biometrics.** The Keystore sentinel behind biometric unlock detects a fingerprint enrolled after setup, and
  creating a new one trusts whatever is enrolled *now*. So `RepositoryRelocationRecordStore` checks the old
  sentinel first and only re-arms for the new location if it still passes; otherwise (or if Android refuses the
  new key) the vault falls back to its password.
* **Lockout.** Failed pattern/PIN attempts and a running lockout move with the vault
  (`PatternUnlockThrottle.carryOver`, `PinUnlockThrottle.carryOver`), so a move is not a way to reset them.
* **Cached derived key.** Cleared for the old location (the cache is content-fingerprinted but its expiry is
  keyed by URI) and re-created at the next unlock.
* **Automation access** (Tasker etc.) is reset, not carried over: it is an explicit per-vault grant with a stored
  password, and a move should not silently re-issue it. The user is told.
* The Cryptomator "back up key files" preference is copied to the new location when the copy is verified (the
  Dart side forgets the old location's preferences when it switches the record, before step 3).

### What cannot be moved

USB (`usb:`) and composite (`composite:`) vaults, the parts of a split container (rejoin first), **unlocked
vaults** (lock first), and a folder that has no vault config file. A move out of app storage
into a folder requires an **empty** folder.

## Removing a vault from app storage

Forgetting the list entry would strand the files where nothing can reach them, so "Remove" on such a vault is
labelled **Delete**, asks for confirmation (with "Move out instead"), deletes the files, and only then removes
the entry, with no undo bar (`removeAppStorageVault`, `VaultDashboardController.removeVaultNow`). Creating a
vault in app storage always saves its record (the "Remember" switch is forced on and disabled); if the record
cannot be saved, the new files are deleted again.

## Channel API (`VaultStorageApi`)

`getAppStorageInfo`, `createAppStorageContainer`, `createAppStorageFolderVault`, `relocateToAppStorage`,
`relocateFromAppStorage`, `finalizeRelocation`, `discardRelocationCopy`, `deleteAppStorageVault`. Progress and
cancellation reuse the Split/Join channel on an opId range of their own (`0x50000000`).
`VaultStorageApi` is a separate class from `VaultLifecycleApi` because the latter is implemented by the desktop
engine and many test fakes.

Folder vaults needed `FolderVaultOpener` to accept a local directory (`VaultRoot`), plus local branches in
`handleDocumentExists`, the folder-vault header backup/restore handlers and the derived-key fingerprint.

## Known limitations

* Unregistered vaults in app storage (the two crash windows above) are not adopted back into the list: guessing
  a container's format wrongly and then offering "Delete" could cost someone their only copy. They only waste
  space; empty reservations and `.part-*` leftovers are swept.
* A very large move runs in the foreground; if Android kills the app mid-copy the move simply did not happen.
* Per-vault view preferences keyed by URI that are not part of the record (for example the remembered music-mode
  hint) start fresh at the new location.
* Tier-3 panic overwrites app-storage vaults like everything else under `dataDir`; a multi-GB vault makes that
  slower. Credentials are cleared first.
