# VaultExplorer — Architecture

---

## 1. System overview

VaultExplorer is an Android app (Flutter UI + Kotlin platform layer + C++
native engine) that mounts, browses, and edits encrypted containers and
directory vaults **entirely on-device**, decrypting only into memory and
writing zero plaintext temp files to host storage. It supports two
structurally different families of encrypted volume:

| Family | Formats | Session lives in |
|---|---|---|
| **Block-device containers** | VeraCrypt, LUKS1, LUKS2, BitLocker (+ VHD/VHDX wrapping) | C++ `VolumeState` slot array, driven through the `NativeEngine` JNI shim |
| **Directory-based vaults** | Cryptomator, gocryptfs, CryFS | Pure-Kotlin `VaultBackend` session objects in `VaultBackendRegistry` |

Both families are unified above the crypto layer by **`volId`** (an `Int`,
`0..7`): every caller — Dart, `ContainerFileSystem`, the SAF
`ContainerDocumentsProvider`, the automation `BroadcastReceiver` (§5.4) —
addresses an unlocked volume by its `volId` and never needs to know which
of the two families is actually serving it. That unification point is
`ContainerEngine` (§3.3).

### 1.1 Layers

```
Flutter/Dart UI  ──MethodChannel──▶  MainActivity + *Handlers (Kotlin)
                                            │
                                            ▼
                              ContainerEngine  (format-neutral facade)
                               │                        │
                               ▼                        ▼
                    VaultBackendRegistry        NativeEngine (JNI shim)
                    (Cryptomator/gocryptfs/            │
                     CryFS — pure Kotlin)               ▼
                                              VolumeState[8] (C++)
                                              FatFs / NTFS-3G / libext2fs /
                                              dislocker / mbedTLS
```

- **Dart** owns UI state, per-container persisted settings
  (`ContainerRepository`), and app-level lock policy
  (`SessionLockController`). It holds no cryptographic material and no
  session state of its own — a locked container in Dart is just the
  *absence* of a `volId` it can use.
- **Kotlin** owns the `MethodChannel` surface, the executor/thread topology,
  the per-`volId` session registries (both of them — see §3.2), SAF
  (`ContainerDocumentsProvider`), USB mass-storage device access, the
  pure-Kotlin directory-vault backends, and the automation `BroadcastReceiver`
  entry point (§5.4), which reaches the same `ContainerEngine`/session
  registries without going through the `MethodChannel` at all.
- **C++** owns the actual cryptographic sessions for block-device formats,
  the on-disk filesystem engines, and all key material for that family.

### 1.2 In-vault viewers

Photos, video/audio, PDF, HTML, and text/code are all viewable without
leaving the vault, streamed straight from the decrypted engine with no
plaintext temp file. Video/audio and PDF are native Kotlin platform views
rather than Flutter plugins — video via AndroidX Media3/ExoPlayer, PDF via
the AndroidX Jetpack PDF library (`androidx.pdf`) — both decode through the
OS's own codec/renderer.

---

## 2. Ownership & invariants

These are invariants that call sites are expected to already know and that
new code must not violate. Each is traceable to specific enforcement code.

1. **A `volId` has exactly one owner at a time, and ownership is decided by
   which registry has an entry for it.** `ContainerEngine` (§3.3) checks
   `VaultBackendRegistry` first; a miss falls through to `NativeEngine`. A
   `volId` must never appear in both registries simultaneously.

2. **File descriptors passed into JNI keyfile/session calls are
   consumed, not borrowed.** `NativeEngine`'s doc comment is explicit: for
   every `*Fds`/`fd` parameter, "the native side takes ownership ... and
   closes every fd ... whether derivation succeeds or fails — callers must
   not touch or close them again afterward." `NativeOpSupport.openKeyfileFds`
   is the one place that opens these on the Kotlin side, and it already
   closes any partially-opened batch on failure *before* the ownership
   handoff — i.e. ownership only transfers once all fds in the batch opened
   successfully.

3. **Cryptographic key material is explicitly zeroized, not just freed, on
   lock.** `VolumeState::reset()` calls `mbedtls_platform_zeroize()` on
   `preservedDerivedKey` before `delete[]`. Do not reintroduce a plain
   `delete[]` or a Kotlin-side `ByteArray` that isn't wiped when adding new
   preserved-key paths.

4. **A rename/create that targets an already-occupied name must fail
   closed, never silently delete what's there.** Enforced independently in
   all three native filesystem backends (`fat_backend.cpp`,
   `ntfs_backend.cpp`, `ext_backend.cpp`) and mirrored at the Dart/UI layer
   by `checkEntryConflict()` in `entry_conflict.dart` for early, specific
   error messages. The native check is authoritative (it also covers races
   and non-UI callers, e.g. SAF); the Dart check exists only for a better
   error message before the round-trip.

5. **A filename is validated, never mutated.**
   `FilesystemNameValidator.kt` (Kotlin) and `filesystem_type.dart`'s
   `FilesystemRules` (Dart) classify a name and return every reason it's
   invalid; they never return a different string than they were given.
   `illegal_char_input_formatter.dart` and `raw_entry.dart` follow the same
   rule at the input-formatting and directory-listing-parsing layers
   respectively. The Kotlin and Dart validators are intentionally
   hand-maintained mirrors of each other across the JNI boundary rather
   than a single shared implementation — unifying them is tracked as open
   follow-up work, not yet done.

6. **A `FileSize` is never negative** (`file_size.dart`) — a defensive
   invariant at the value-type level, because both native filesystem
   backends and Cryptomator/gocryptfs/CryFS's own metadata can
   theoretically produce inconsistent data on a corrupted or
   maliciously-crafted volume.

7. **The directory-entry wire format carries an explicit type tag; type is
   never inferred from the name.** `encodeDirEntryWire()` /
   `DirEntryWire.kt` are the single encode/decode point shared by all three
   native filesystem backends — do not hand-build the `"<F|D>|..."` string
   anywhere else.

8. **Per-volume locking (§3.2) guards the native call; the Kotlin
   session-metadata map is a separate concern with its own protection.**
   `ContainerSessionRegistry.activeSessions` is a `ConcurrentHashMap`
   specifically because it's written from the UI thread on unlock and from
   a background executor thread on lock — the per-volId lock only guards
   the native call, never this map. Do not reason about `activeSessions`
   thread-safety by pointing at `locks[volId]`; they are unrelated.

9. **Exactly one of the two launcher `activity-alias` components
   (`VaultLauncherAlias` / `ZipExplorerAlias`) is enabled at any time, never
   zero or both.** `DisguiseModeHandlers.handleSetMode` is the only place
   allowed to call `PackageManager.setComponentEnabledSetting` for either of
   them, and it always flips both in the same call. Do not add a second
   call site that toggles only one side — the app becomes unreachable from
   the launcher, or shows two icons and defeats the disguise.

10. **Mask Mode's on/off state is never separately persisted anywhere in
    Dart — it is always re-derived from live `PackageManager`
    component-enabled state.** There is no `bool` for it in `AppSettings`,
    `AppSecureStorage`, or any other Dart-side store. `DisguiseModeApi.getMode()`
    is the only source of truth, and it queries the native side fresh every
    time. A separately persisted flag could drift from actual launcher
    state, and a plaintext record of "this app has an active disguise"
    would itself be a fingerprint that partially defeats the purpose of
    having one.

11. **The automation API token, per-vault tier, and automation-only stored
    password live in their own Keystore-backed store — never in the
    Dart-exposed `SecureStorageHandlers` store, and never in the
    biometric-gated fast-unlock key cache.** `AutomationSettings` uses its
    own Keystore alias and prefs file (AES/GCM) for exactly this reason: a
    bug in, or a future export-all feature on, the general secure-storage
    path can't surface automation credentials, and an unattended automation
    unlock reaches a narrower credential surface than an interactive
    biometric unlock does.

---

## 3. Concurrency & threading model

Four independent locking/executor layers exist, at different granularities,
for different reasons. None of them is redundant with another, but none of
them stands in for the *Kotlin-side* session map either (§2 rule 8).

### 3.1 Executors (Kotlin, `MainActivity`)

Four fixed-size thread pools, sized per-device by `DeviceCapabilityProfiler`
rather than hardcoded. `DeviceCapabilityProfiler.classify()` computes a
LOW/MEDIUM/HIGH tier once per process
(`ActivityManager.isLowRamDevice`, `memoryClass`, CPU core count) and
`resizeExecutorPools()` applies it via
`ThreadPoolExecutor.setCorePoolSize`/`setMaximumPoolSize`. The same tier
feeds Dart-side cache budgets (`FullResImageCache.resize`,
`ThumbnailCacheService`), so memory and thread budgets scale together off
one signal.

| Executor | Purpose | LOW / MEDIUM / HIGH tier size |
|---|---|---|
| `ioExecutor` | General Tier-2 file/directory ops, unlock/create/lock, import/export | 2 / 4 / 6 |
| `imageThumbnailExecutor` | Image thumbnail generation | 1 / 2 / 3 |
| `videoThumbnailExecutor` | Video thumbnail generation (frame extraction is heavier; kept smaller) | 1 / 1 / 2 |
| `fullResExecutor` | Full-resolution media-viewer reads | 1 / 2 / 3 |

Every `MethodChannel` handler follows the same shape via
`NativeOpSupport.runNativeOp`: look up `volId` from the URI (failing fast
with `NOT_MOUNTED` if it isn't currently unlocked), run the native call on
an executor, and report back via `result.success`/`result.error` **on the UI
thread** (`activity.runOnUiThread`). Flutter's `MethodChannel` requires
replies on the platform thread; nothing here may complete a `Result` off the
UI thread.

### 3.2 Per-volume locks (Kotlin + C++)

- **Kotlin:** `ContainerSessionRegistry.locks` is an `Array` of
  `ReentrantReadWriteLock(fair = true)`, one per volume slot (`MAX_VOLUMES`,
  currently 8). `ContainerFileSystem` is the single chokepoint for all
  stateless native calls — every Tier-2 call from `MainActivity`,
  `ContainerDocumentsProvider`, and the automation `BroadcastReceiver`
  passes through here so that locking and error dispatch live in exactly
  one place. Reads use `withReadLock`; writes use `withWriteLock`.
- **Lock-skip for directory vaults:** `getFileSize` and `readFileChunk` in
  `ContainerFileSystem` skip the per-volId lock for backends where
  `VaultBackend.skipsPerVolumeLock == true` — those backends' underlying
  I/O does not require the FAT/NTFS/ext-style serialization the lock
  provides.
- **C++:** `VolumeState::mutex` guards the native session struct itself
  (`session_guard.cpp`'s `requireActiveSession`/`isVolumeReadOnly` both take
  it). Two narrower mutexes exist *inside* `VolumeState`, deliberately kept
  separate from the top-level one: `ioBufMutex` (per-batch I/O buffer) and
  `decryptedBlockCacheMutex` — both scoped narrowly so one file's
  read/write does not serialize unrelated directory listings or other
  files' metadata lookups on the same volume. A global `slotAllocMutex`
  guards allocation of a free slot in the `volumes[8]` array itself,
  separate from any individual volume's mutex.

### 3.3 Format dispatch (no lock, just a registry lookup)

`ContainerEngine` — the format-neutral native engine boundary — is not a
concurrency primitive but is central to the thread story: every Tier-2 call
checks `VaultBackendRegistry.get(volId)` first (Cryptomator/gocryptfs/CryFS,
backed by a `ConcurrentHashMap`) and falls through to `NativeEngine` (JNI →
`VolumeState`) if that lookup misses. `ContainerEngine.lock(volId)` follows
the same branch: remove-and-close the Kotlin backend if one exists,
otherwise call `NativeEngine.lockNative`. Tier-1 (unlock/create/change-
password) stays VeraCrypt/LUKS/BitLocker-specific by design — the directory
vaults have no block-device layer for that facade to drive and are opened
directly from their own vault classes in `MainActivity`.

### 3.4 Dart side

Dart is effectively single-threaded from this system's point of view: it
has no locks because it holds no session state. Cross-cutting async
coordination is handled by two small, specific-purpose primitives instead
of ad-hoc `Future`/`Timer` juggling:

- **`ListenerRegistry<T>`** — every native→Dart event stream (unlock
  progress, import progress, USB detach, container-locked, screen-off) is a
  typed instance of this. `notify()` iterates a *snapshot*
  (`List.of(_listeners)`) specifically so a listener that adds/removes
  another listener mid-dispatch cannot throw a concurrent-modification
  error.
- **`PriorityTaskQueue`** / **`ByteBudgetCache`** — bound how many
  in-flight decrypt+transfer calls can queue up on the native `ioExecutor`
  from a single fast-scrolling widget (media viewer, thumbnail grid), since
  there is no cancellation once `invokeMethod` has been sent — the only
  lever Dart has is never submitting the call in the first place. Requests
  for the currently-visible item are prioritized over adjacent/prefetch
  requests rather than served FIFO, and a currently-playing media item is
  treated differently from a merely-visible one for caching/eviction
  purposes.

### 3.5 Mask Mode

Introduces no new locks, executors, or registries. `getMode`/`setMode`
(`DisguiseModeHandlers`) run directly on the calling thread —
`PackageManager.getComponentEnabledSetting`/`setComponentEnabledSetting` are
synchronous local IPC to `system_server`, short enough that they do not need
`ioExecutor` the way file/crypto ops do.

### 3.6 Automation

`VaultAutomationReceiver` has no `Activity` to hand work off to the way
`MainActivity`'s handlers use its `ioExecutor`, so it gets its own strictly
serial `Executors.newSingleThreadExecutor()` rather than sharing a pool —
automation actions are expected to run in the order they were fired (e.g.
unlock, then import, then lock), and a single-thread executor gets that
ordering for free. It also keeps its own `HandlerThread`/`Handler` for FUSE
callbacks on block-device unlocks, separate from `MainActivity`'s
equivalent, for the same "no Activity to share it with" reason. Every
`onReceive` immediately calls `goAsync()` and dispatches onto that executor,
finishing the pending result in a `finally` block so the receiver never
blocks the system's main thread while a vault unlocks.

---

## 4. Container lifecycle

State is tracked per `volId`, not globally — up to `MAX_VOLUMES` (8)
containers can be in the *Unlocked* state simultaneously, each independently
progressing through its own lifecycle.

```
                     ┌─────────┐
        ┌───────────▶│ Locked  │◀────────────────────────────┐
        │            └────┬────┘                              │
        │                 │ unlockContainer /                  │
        │                 │ unlockUsbContainer /                │
        │                 │ unlock*Vault                        │
        │                 ▼                                     │
        │           ┌───────────┐   onUnlockStarted /           │
        │           │ Unlocking │──▶ onUnlockProgress events     │
        │           └─────┬─────┘   (attempted/total/cipher/    │
        │      auth fail /│ hash — auto-detect cascade)         │
        │      invalid    │ success                             │
        │      container  ▼                                     │
        │               ┌───────────┐        USB detach /          │
        │  cancelUnlock  │Unlocked │───▶  screen-off auto-lock /  │
        │  (best-effort, │(rw/RO) │      lockContainer /          │
        │   next hash/   └─────┬───┘      app-lock enforcement ──┘
        │   cipher       import/export,
        │   boundary)    file I/O, SAF
        │                exposure, subfolder
        └────────────────mounts, camera capture,
                          in-vault editors, etc.
```

### 4.1 States

- **Locked** — no entry in `ContainerSessionRegistry.activeSessions` for
  this `volId`. This is the default/rest state; a `volId` here is free for
  `getFreeVolumeId()` to hand to the next unlock request.
- **Unlocking** — a `volId` has been reserved (`getFreeVolumeId()` or the
  existing `volId` for a re-unlock of an already-known URI) and
  `onUnlockStarted` has fired, but the session is not yet registered. For
  auto-detect unlocks (`cipherId`/`hashId` == 255), the native side tries
  cipher/hash combinations and reports progress via `onUnlockProgress`
  (`attempted`/`total`/current `cipherId`/`hashId`/`slot`). This is the one
  state with a **cancellation path**: `requestCancelUnlockNative` asks an
  in-flight derivation to abort at its next hash/cipher combination
  boundary — best-effort, bounded by roughly one PBKDF2 round, not instant.
  Automation unlocks (§5.4) go through the same state and the same
  `ContainerLifecycleCore` entry points as an interactive unlock; there is
  no separate "headless" unlock path.
- **Unlocked** — a `ContainerSession` exists in `activeSessions`. Two
  sub-states affect behavior throughout the file-I/O layer:
  - **read-write** (default)
  - **read-only** (`readOnly: true` on the session) — enforced natively;
    write attempts throw and are translated to the `READ_ONLY` error code by
    `NativeOpSupport.dispatchNativeError`, not merely hidden in the UI.
- **Locked (again)** — reachable from Unlocked via any of: explicit
  `lockContainer`, USB device physical detach
  (`onUsbContainerDetached` → auto-lock), screen-off auto-lock policy
  (`SessionLockController`, if `lockContainersOnScreenLock` or a master
  password is set and `autoLockMins == 0`), or resume-after-away-too-long
  (`autoLockMins` elapsed while backgrounded). All paths funnel through the
  same native `lock`/session-removal code (§3.3), so there is one teardown
  implementation regardless of trigger.

### 4.2 Terminal error outcomes (Unlocking → Locked, no session created)

| Error code | Meaning |
|---|---|
| `AUTH_FAIL` | Wrong password/keyfiles, or not a recognized container at all |
| `MAX_CONTAINERS` | All 8 volume slots already occupied |
| `CANCELLED` | User-requested cancellation completed |
| `INVALID_ARGS` | Missing required parameters (password+filePath, etc.) |
| `INVALID_VAULT` | Folder picked doesn't contain a recognized vault config |
| `KDF_FAILED` | Key derivation itself failed (not a wrong-password case) |

### 4.3 Errors reachable only from Unlocked (operation-level, not lifecycle)

| Error code | Meaning |
|---|---|
| `NOT_MOUNTED` | URI doesn't currently map to any `volId` |
| `NOT_UNLOCKED` | `volId` resolved, but the native side's own session check (`requireActiveSession`) failed — a defense-in-depth check independent of the Kotlin registry |
| `READ_ONLY` | Write attempted against a read-only-mounted volume |
| `C++_ERROR` | Catch-all native failure, message passed through |

### 4.4 Background persistence

`VaultKeepAliveService` is a foreground service that keeps mounted vaults
alive while the app is backgrounded — it adds no new lifecycle state and no
new transition. Its only job is stopping the OS from reclaiming the process
while one or more `volId`s are Unlocked and `MainActivity` isn't in the
foreground; without it, an Unlocked session doesn't transition to Locked,
it simply vanishes when the process dies, with no teardown at all. The
existing lock triggers in §4.1 (explicit lock, USB detach, screen-off
policy, `autoLockMins`) are unaffected either way and remain the only paths
that actually move a `volId` back to Locked. It is started/stopped by the
same code paths that unlock/lock a container, on both the `MethodChannel`
and automation (§5.4) sides.

Background camera recording (continuing a capture after the screen turns
off or the app is minimized) uses its own separate foreground service,
`VaultCameraRecordingService` (type `camera|microphone`) — required by the
OS, which tears down an unfocused app's camera/mic connection on Android 9+
unless a matching foreground service is running. It is independent of
`VaultKeepAliveService` and only runs while a recording is in progress.

---

## 5. Public API surface

The stable cross-language contract for interactive use is a single
`MethodChannel` (`com.aeidolon.vaultexplorer/engine`); every method name is
a constant in **`ChannelMethods`** (Dart) mirrored 1:1 by a Kotlin
`ChannelMethods` object inside `MainActivity` — that pairing is the API
contract and both sides must be updated together. Automation (§5.4) is a
separate, headless entry point that does not go through this channel, and
Mask Mode (§6.3) has its own dedicated channel.

### 5.1 Dart → native (method calls)

| Group | Methods |
|---|---|
| Container lifecycle | `pickContainer`, `pickKeyfiles`, `createContainer`, `unlockContainer`, `lockContainer`, `updateContainerSettings`, `cancelUnlock`, `changeContainerPassword`, `mountContainerFolder`, `unmountContainerFolder`, `getMountedContainerFolders`, `hasAllFilesAccess`, `requestAllFilesAccess` |
| Directory vaults (Cryptomator/gocryptfs/CryFS) | `pick/unlock/create*Vault` × 3 formats, plus `isGocryptfsVault`/`isCryfsVault` |
| File I/O | `decryptFile`, `exportFileToStorage`, `exportFilesToFolder`, `importFile`, `importFolder`, `cancelImport`, `deleteImportSources`, `getFileSize`, `getFolderSize`, `readFileChunk`, `writeFileChunk`, `finishWrite`, `writeBackFile`, `getSpaceInfo`, `getMediaFileSize`/`readMediaFileChunk` (routed to `fullResExecutor`) |
| Directory ops | `listDirectory`, `createDirectory`, `renameFile`, `deleteFile`, `setLastModifiedTime` |
| Media/thumbnails | `openWithApp`, `get{Image,Video}Thumbnail[WithSize]`, `setPlaybackActive` |
| Crypto | `hashPassword`, `deriveDerivedKey`, `storeDerivedKey`, `loadDerivedKey`, `clearDerivedKey` |
| Security | `setSecureScreen` |
| USB | `listUsbDevices`, `requestUsbPermission`, `unlockUsbContainer`, `createUsbContainer`, `getUsbDeviceCapacity` |
| System | `documentExists`, `warmContainer`, `getDeviceCapabilityProfile` |

### 5.2 Native → Dart (event callbacks)

Via the same channel's method-call handler in reverse — see
`VaultExplorerApi.initMethodCallHandler`:

`onAppSelected`, `onUsbContainerDetached`, `onScreenOff`, `onUnlockStarted`,
`onUnlockProgress`, `onImportProgress`, `onCameraPermissionResult`,
`onTrimMemory`. Each has a corresponding typed `ListenerRegistry` (or, for
`onTrimMemory`, a direct call into `CacheCoordinator.trimAll`) — see §3.4.
`VaultAutomationUnlockedBridge` (§5.4) delivers a similar unlocked-vault
notification to the dashboard when a Flutter engine happens to be attached,
but it is not part of this method-call handler and does not require one.

### 5.3 Kotlin-internal facades (not exposed to Dart directly)

- **`ContainerEngine`** — format-neutral Tier-1/Tier-2 facade (§3.3). This is
  the API every new file-operation or lifecycle feature should target, not
  `NativeEngine` directly.
- **`NativeEngine`** — raw 1:1 JNI shim. App code must use `ContainerEngine`,
  never this object directly. Two call tiers: **Tier 1** (session
  establishment: takes a real fd + password + PIM) and **Tier 2**
  (stateless, `volId`-only; the C++ side throws
  `IllegalStateException("NOT_UNLOCKED: ...")` via `requireActiveSession` if
  there's no active session).
- **`VaultBackend`** — the interface every pure-Kotlin directory-vault
  session implements, so `ContainerEngine` can dispatch to any of the three
  without a per-format branch at most call sites.
- **`ContainerFileSystem`** — the locking chokepoint in front of
  `ContainerEngine` for Tier-2 calls (§3.2); `MainActivity`,
  `ContainerDocumentsProvider` (SAF), and `VaultAutomationReceiver` all call
  through here, not `ContainerEngine` directly, so locking and error
  dispatch stay centralized.

### 5.4 Automation (broadcast receiver)

`VaultAutomationReceiver` (Beta) is a headless entry point for
Tasker/MacroDroid-style automation apps to control a vault without the
Flutter UI or an `Activity` present at all — it runs off a dedicated
single-thread executor (§3.6) and reaches `ContainerLifecycleCore`/
`ContainerFileSystem` directly, alongside the `MethodChannel` path rather
than through it.

| Action | Requires tier | Purpose |
|---|---|---|
| `ACTION_UNLOCK_VAULT` | LIFECYCLE | Unlock a vault opted in to automation; dispatches to the block-device or directory-vault path per `AutomationSettings.getFormat`. Starts `VaultKeepAliveService`. No hidden-volume or keyfile support. |
| `ACTION_LOCK_VAULT` | LIFECYCLE | Lock a vault; stops `VaultKeepAliveService` if no session remains active anywhere. |
| `ACTION_IMPORT_FILE` | FULL | Import a real filesystem path into the vault, with an option to securely wipe the source afterward. |
| `ACTION_EXPORT_FILE` | FULL | Export a path from inside the vault to a real filesystem path. |
| `ACTION_WIPE_FILE` | *(not vault-gated)* | Securely deletes an arbitrary plaintext path outside any vault — e.g. an `EXPORT_FILE` destination once a script has finished processing it. Still requires a valid API token. |

Every action requires the per-install API token (`AutomationSettings`,
§2 rule 11) **and** the target vault opted in to the tier that action
needs — both are checked before any vault state is touched, and a
bad/missing token gets no reply broadcast at all, so a probing app can't
even learn the feature is configured. Every successful or failed action
replies on `ACTION_AUTOMATION_RESULT` with a result code
(`OK`/`AUTH_FAIL`/`NOT_MOUNTED`/`FORBIDDEN`/`INVALID_ARGS`/`ERROR`) and
message, as an ordinary broadcast an automation profile can branch a task
chain on.

---

## 6. Mask Mode

A presentation-layer disguise: the Android launcher shows either the real
"Vault Explorer" identity or an innocuous "Archive Explorer" identity,
determined by which of two `activity-alias` components is currently
enabled (§2 rule 9). Both aliases target the same `MainActivity` — this is
never a second process, a second Activity class, or a second copy of the
Flutter engine, just a different launcher icon/label pointing at the same
app. Mask Mode is independent of cryptographic session state; a `volId`
being Unlocked or Locked is unrelated to which launcher identity is active.

While the decoy identity is active, the app functions as a real, usable
zip archive browser (`DecoyArchiveExplorerScreen`) — listing and extracting
.zip files from the device's public Downloads folder uses plain filesystem
access and zero container/vault involvement.

### 6.1 State machine

```
    ┌────────────────────┐                        ┌────────────────────┐
    │   Vault identity   │   setMode(decoy)       │   Decoy identity   │
    │ VaultLauncherAlias │ ─────────────────────▶│ ZipExplorerAlias   │
    │      enabled       │◀───────────────────── │      enabled       │
    └─────────┬──────────┘   setMode(vault)       └─────────┬──────────┘
              │           (AppSettingsScreen toggle,                  │
              │            both directions, explicit only)            │
              │                                                       │
    boots into LockGateScreen                     boots into DecoyArchiveExplorerScreen
    (→ VaultDashboard on auth)                    (functional zip archive browser)
                                                             │
                                                hold app-bar title 2s
                                                (HiddenVaultTrigger)
                                                             │
                                                             ▼
                                               Navigator.push(LockGateScreen)
                                              (pushed on top of decoy UI)
```

- **Vault identity** — `VaultLauncherAlias` enabled, `ZipExplorerAlias`
  disabled. Manifest default on a fresh install. `_DisguiseModeGate` boots
  straight into `LockGateScreen`.
- **Decoy identity** — `ZipExplorerAlias` enabled, `VaultLauncherAlias`
  disabled. `_DisguiseModeGate` boots into `DecoyArchiveExplorerScreen`
  instead.
- The only transition between the two is `DisguiseModeApi.setMode`, called
  from exactly one place (`AppSettingsScreen._setDiscreteMode`), always with
  a confirmation dialog. Nothing else in the app may call `setMode` — in
  particular, the hidden trigger deliberately does **not** call it: reaching
  the real vault from inside the decoy UI is a one-session, in-app affair,
  not a change to the disguise state.
- There is no error sub-state: `setMode` either succeeds or throws (surfaced
  as a snackbar by the Settings screen), and a failed toggle leaves the
  alias state unchanged.

### 6.2 Recents/task-switcher label

Android's recent-apps ("Overview") card shows a title independent of the
launcher icon. `applyDisguiseModeTaskSwitcherLabel()` (`vault_explorer_app.dart`)
calls `SystemChrome.setApplicationSwitcherDescription` both at cold-start
resolution (`_DisguiseModeGate._resolveMode`) and immediately after a
successful `setMode` — otherwise a disguised launcher icon could still be
exposed by a "Vault Explorer" card in the task switcher.

### 6.3 Public API surface (`disguise_channel`)

A dedicated `MethodChannel`
(`com.aeidolon.vaultexplorer/disguise_channel`), separate from the main
engine channel documented in §5. Method names are constants in
`DisguiseChannelMethods` (Kotlin), mirrored 1:1 by `DisguiseModeApi` (Dart).

| Method | Direction | Purpose |
|---|---|---|
| `getMode` | Dart → native | Reads live `PackageManager` component-enabled state; returns `"vault"`/`"decoy"` (§2 rule 10 — never cached) |
| `setMode` | Dart → native | Atomically flips both aliases (§2 rule 9); `DONT_KILL_APP` preserves running engine/session state |

There are currently no native → Dart events on this channel — Mask Mode
has no asynchronous native-side progress to report.

---

## 7. Notable implementation choices

Assorted decisions worth knowing before touching the relevant code, each
with its evidence file(s) so you can read the reasoning in place rather
than take this summary on faith:

- **Thumbnail/full-res concurrency is priority-tiered, not FIFO, and
  playback-aware** (`priority_task_queue.dart`, `full_res_image_cache.dart`)
  — see §3.4.
- **Cache byte-budgets and executor pool sizes both scale off
  `DeviceCapabilityProfiler`'s device tier** (`full_res_image_cache.dart`,
  `priority_task_queue.dart`, `CacheCoordinator`, `DeviceCapabilityProfiler.kt`)
  — one signal drives both, computed once per process — see §3.1.
- **The on-disk (L2) thumbnail cache is byte-budgeted with a default 100 MB
  cap, enforced on startup** (`thumbnail_cache_service.dart`,
  `defaultMaxAppCacheBytes`).
- **Unlock sheets dismiss the on-screen keyboard on tap-outside via an
  opaque overlay**, applied identically to local and USB unlock flows
  (`unlock_sheet.dart`, `usb_unlock_sheet.dart`, `advanced_params_panel.dart`).
- **The native crypto/filesystem engine's automated regression tests are
  plain host-side C++ binaries** — `g++`-buildable, `assert`-based, zero
  Android toolchain required, registered with CTest and gated behind
  `if(NOT ANDROID)` (`CMakeLists.txt`, `crypto/test/kdf_table_test.cpp`,
  `io/test/sector_batching_test.cpp`, `test/fs_scan_test.cpp`).
- **`file_browser_screen.dart`'s selection-mode and sort-mode state live in
  reusable `SelectionMixin<T>`/`SortMixin<T>` mixins**, not inline in the
  screen's `State` class (`lib/features/browser/mixins/`).
- **The decoy reader's old "Open PDF File" picker code
  (`pickLocalPdfFile()` in `disguise_mode_api.dart`, and the `localUri`/
  `PdfSearchConfig.decoy` parameters on `PdfViewerBase`) is unreferenced** —
  the decoy identity is `DecoyArchiveExplorerScreen` only and has no PDF
  entry point. Safe to remove; not yet done.

---

## Cross-references

Section numbers above (`§2 rule 9`, `§3.4`, etc.) are the citation format
used in code comments elsewhere in the repo — keep them in sync if you
renumber a section. Some existing code comments predate this document and
cite an older `ADR-NNN` numbering scheme that no longer has a corresponding
section here; if you find one, use its surrounding code context (not the
number) to figure out what it's referring to, and consider updating the
comment to point at the current section number instead.
