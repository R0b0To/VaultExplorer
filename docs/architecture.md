# VaultExplorer — Architecture

> **Status note (reconstruction, 2026-07-30):** This file was missing from the
> repository snapshot this document was generated from, despite being cited
> by path (`docs/architecture.md`) in ~50 code comments across the Dart,
> Kotlin, and C++ layers — including specific section numbers (`§5.3`,
> `§5.4`) and ADR numbers up to ADR-020. It has been reconstructed from those
> in-code citations plus direct source inspection, so every claim below is
> traceable to a specific file. **It is not a full replacement for whatever
> the original document said** — ADR numbers **001, 006–009, 013, 015–018**
> are referenced nowhere else in the tree and could not be recovered; they
> are listed as open gaps in §4 rather than invented. If the original file
> exists somewhere (old branch, teammate's machine, deleted PR), diff it
> against this one before treating this as canonical.
>
> **Update (same day):** ADR-021 and ADR-022 were added as part of executing
> the companion `docs/tech-debt.md` Phase 0/1 items — this file is current
> with the source tree as of those fixes, not just a historical
> reconstruction.

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
`ContainerDocumentsProvider` — addresses an unlocked volume by its `volId`
and never needs to know which of the two families is actually serving it.
That unification point is `ContainerEngine` (§3.3).

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
  the per-`volId` session registries (both of them — see §2.2), SAF
  (`ContainerDocumentsProvider`), USB mass-storage device access, and the
  pure-Kotlin directory-vault backends.
- **C++** owns the actual cryptographic sessions for block-device formats,
  the on-disk filesystem engines, and all key material for that family.

---

## 2. Ownership rules

These are invariants that call sites are expected to already know and that
new code must not violate. Each is traceable to specific enforcement code.

1. **A `volId` has exactly one owner at a time, and ownership is decided by
   which registry has an entry for it.** `ContainerEngine` (§3.3) checks
   `VaultBackendRegistry` first; a miss falls through to `NativeEngine`. A
   `volId` must never appear in both registries simultaneously — nothing
   currently enforces this as an invariant beyond call discipline (see
   Finding TD-3 in the tech-debt report).

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
   `preservedDerivedKey` before `delete[]`. This is a hard-fought property —
   don't reintroduce a plain `delete[]` or a Kotlin-side `ByteArray` that
   isn't wiped when adding new preserved-key paths.

4. **A rename/create that targets an already-occupied name must fail
   closed, never silently delete what's there (ADR-004).** Enforced
   independently in all three native filesystem backends
   (`fat_backend.cpp`, `ntfs_backend.cpp`, `ext_backend.cpp`) and mirrored at
   the Dart/UI layer by `checkEntryConflict()` in
   `entry_conflict.dart` for early, specific error messages. The native
   check is the one that actually matters (it also covers races and
   non-UI callers, e.g. SAF); the Dart check exists only for a better error
   message before the round-trip.

5. **A filename is validated, never mutated (ADR-002).**
   `FilesystemNameValidator.kt` / `filesystem_type.dart`'s `FilesystemRules`
   classify a name and return every reason it's invalid; they never return a
   different string than they were given. `illegal_char_input_formatter.dart`
   and `raw_entry.dart` follow the same rule at the input-formatting and
   directory-listing-parsing layers respectively. If you're tempted to
   "helpfully" strip/replace an illegal character, that's the bug ADR-002
   was written to prevent.

6. **A `FileSize` is never negative** (`file_size.dart`, ADR-002 ownership
   rule #6) — a defensive invariant at the value-type level, because both
   native filesystem backends and Cryptomator/gocryptfs/CryFS's own metadata
   can theoretically produce inconsistent data on a corrupted or
   maliciously-crafted volume.

7. **The directory-entry wire format carries an explicit type tag; type is
   never inferred from the name (ADR-003).** `encodeDirEntryWire()` /
   `DirEntryWire.kt` are the single encode/decode point shared by all three
   native filesystem backends — don't hand-build the `"<F|D>|..."` string
   anywhere else.

8. **Per-volume locking (§3.2) guards the native call; the Kotlin
   session-metadata map is a separate concern with its own protection.**
   `ContainerSessionRegistry.activeSessions` is a `ConcurrentHashMap` (ADR-021)
   specifically because it's written from the UI thread on unlock and from a
   background executor thread on lock — the per-volId lock only ever guarded
   the native call, never this map. Don't reason about `activeSessions`
   thread-safety by pointing at `locks[volId]`; they're unrelated.

---

## 3. Thread model

Three independent locking layers exist, at three different granularities,
for three different reasons. None of them is redundant with another, but
none of them stands in for the *Kotlin-side* session map either (§2 rule 8).

### 3.1 Executors (Kotlin, `MainActivity`)

Four fixed-size thread pools, sized per-device by `DeviceCapabilityProfiler`
(ADR-019, ADR-011) rather than hardcoded:

| Executor | Purpose | LOW / MEDIUM / HIGH tier size |
|---|---|---|
| `ioExecutor` | General Tier-2 file/directory ops, unlock/create/lock, import/export | 2 / 4 / 6 |
| `imageThumbnailExecutor` | Image thumbnail generation | 1 / 2 / 3 |
| `videoThumbnailExecutor` | Video thumbnail generation (frame extraction is heavier; kept smaller) | 1 / 1 / 2 |
| `fullResExecutor` | Full-resolution media-viewer reads | 1 / 2 / 3 |

`DeviceCapabilityProfiler.classify()` computes the tier once
(`ActivityManager.isLowRamDevice`, `memoryClass`, CPU core count) and caches
it for the process lifetime; `resizeExecutorPools()` applies it via
`ThreadPoolExecutor.setCorePoolSize`/`setMaximumPoolSize`. The same tier
feeds Dart-side cache budgets (`FullResImageCache.resize`,
`ThumbnailCacheService`) so memory and thread budgets scale together — see
`getDeviceCapabilityProfile()`'s doc comment citing ADR-019 directly.

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
  currently 8). `ContainerFileSystem` is the documented "single chokepoint
  for all stateless native calls" — every Tier-2 call from both
  `MainActivity` and `ContainerDocumentsProvider` passes through here so
  that locking and error dispatch live in exactly one place. Reads use
  `withReadLock`; writes use `withWriteLock`. `withLock` (write lock) is
  `@Deprecated` in favor of the explicit read/write variants — new code
  should never call it.
- **Deliberate perf carve-out for Cryptomator/gocryptfs:** `getFileSize` and
  `readFileChunk` in `ContainerFileSystem` skip the per-volId lock for
  backends where `VaultBackend.skipsPerVolumeLock == true` (ADR-022) — those
  two backends' underlying I/O doesn't need the FAT/NTFS/ext-style
  serialization the lock exists for. This used to be implemented as a
  runtime string match on `session.javaClass.simpleName` against
  `"Cryptomator"`/`"Gocryptfs"` — but `session` there was always a
  `ContainerSession` (the generic per-volId registry entry, §6.3), never the
  actual `CryptomatorSession`/`GocryptfsSession` backend instance, so the
  check was permanently false and the carve-out never fired in practice.
  Fixed in ADR-022; see `docs/tech-debt.md` TD-6 for the full history.
- **C++:** `VolumeState::mutex` guards the native session struct itself
  (`session_guard.cpp`'s `requireActiveSession`/`isVolumeReadOnly` both take
  it). Two narrower mutexes exist *inside* `VolumeState` deliberately kept
  separate from the top-level one: `ioBufMutex` (per-batch I/O buffer) and
  `decryptedBlockCacheMutex` — both documented as intentionally scoped
  narrowly so one file's read/write doesn't serialize unrelated directory
  listings or other files' metadata lookups on the same volume. A global
  `slotAllocMutex` guards allocation of a free slot in the `volumes[8]`
  array itself, separate from any individual volume's mutex.

### 3.3 Format dispatch (no lock, just a registry lookup)

`ContainerEngine` — "format-neutral native engine boundary" — is not a
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
  another listener mid-dispatch — e.g. during widget dispose — can't throw a
  concurrent-modification error.
- **`PriorityTaskQueue`** (ADR-010) / **`ByteBudgetCache`** — bound how many
  in-flight decrypt+transfer calls can queue up on the native `ioExecutor`
  from a single fast-scrolling widget (media viewer, thumbnail grid), since
  there is no cancellation once `invokeMethod` has been sent — the only
  lever Dart has is never submitting the call in the first place. See
  `FullResImageCache`'s "Concurrency gate" section for the fullest
  explanation of *why* this exists (a documented pre-fix problem, not
  speculative).

---

## 4. ADR log

Reconstructed from in-code citations. Each entry lists the files that cite
or implement it; read those for full context — this log summarizes rather
than replaces the reasoning already written at the call sites.

| ADR | Title | Status | Primary evidence |
|---|---|---|---|
| 001 | *unrecovered* | — | No in-tree citation found. |
| **002** | Filesystem name validation classifies, never mutates | Accepted | `FilesystemNameValidator.kt`, `filesystem_type.dart`, `name_validation.dart`, `illegal_char_input_formatter.dart`, `path_components.dart`, `file_size.dart`, `raw_entry.dart`, `browser_dialogs.dart`, `vault_item_edit_screen.dart` |
| **003** | Directory-entry wire format carries an explicit type tag (not inferred from name) | Accepted | `dir_entry_wire.h`, `DirEntryWire.kt`, `raw_entry.dart` |
| **004** | Create/rename fails closed on name collision instead of silently unlinking the destination | Accepted | `ext_backend.cpp` (also implemented in `fat_backend.cpp`/`ntfs_backend.cpp` per the same comment), `entry_conflict.dart` |
| **005** | Kotlin/Dart filename validators are intentionally hand-maintained mirrors, not shared code, across the JNI boundary; tracked as future unification work | Accepted, with open follow-up (item 3) | `FilesystemNameValidator.kt`, `filesystem_type.dart`, `mounted_container_filesystem.dart` |
| 006–009 | *unrecovered* | — | No in-tree citation found. |
| **010** | Thumbnail/full-res concurrency is priority-tiered (visible vs. adjacent/prefetch), not FIFO | Accepted | `priority_task_queue.dart`, `full_res_image_cache.dart` (`PriorityTaskQueue`) |
| **011** | Cache byte-budgets and executor pool sizes scale off `DeviceCapabilityProfiler`'s device tier | Accepted | `full_res_image_cache.dart`, `priority_task_queue.dart`, `CacheCoordinator` (Finding F-15 companion) |
| **012** | Media caching/limiting is playback-aware (a currently-playing item is treated differently from a merely-visible one) | Accepted | `full_res_image_cache.dart` citing `ThumbnailConcurrency`'s limiter shape |
| 013 | *unrecovered* | — | No in-tree citation found. |
| **014** | On-disk (L2) thumbnail cache is byte-budgeted with a default 100 MB cap, enforced on startup | Accepted | `thumbnail_cache_service.dart` (`defaultMaxAppCacheBytes`, Finding F-08) |
| 015–018 | *unrecovered* | — | No in-tree citation found. |
| **019** | Device capability (RAM/core-count tier) is profiled once per process and drives both native executor sizing and Dart cache sizing from one signal | Accepted | `DeviceCapabilityProfiler.kt`, `getDeviceCapabilityProfile()` in `vault_explorer_api_container_lifecycle.dart` |
| **020** | Unlock sheets dismiss the on-screen keyboard on tap-outside via an opaque overlay, applied identically to local and USB unlock flows | Accepted | `unlock_sheet.dart`, `usb_unlock_sheet.dart`, `advanced_params_panel.dart` |
| **021** | `ContainerSessionRegistry.activeSessions` is a `ConcurrentHashMap`, not a plain map, because it's mutated from both the UI thread (unlock) and a background executor thread (lock) with no other synchronization covering it | Accepted (2026-07-30) | `ContainerSessionRegistry.kt`; mirrors the precedent already set by `VaultBackendRegistry.sessions` (`VaultBackend.kt`) |
| **022** | Backend-specific lock-skip behavior (§3.2) is a `VaultBackend.skipsPerVolumeLock` property, not a runtime string match on a session's class name | Accepted (2026-07-30) | `VaultBackend.kt`, `CryptomatorSession.kt`, `GocryptfsSession.kt`, `ContainerFileSystem.kt` |

**Companion findings log** (referenced as `Finding F-NN` alongside some
ADRs above, evidently a separate audit trail): **F-01** (byte-budgeted L1
thumbnail cache sizing), **F-07** (stale-decode guard in the image pager for
fast swipe-past-and-back), **F-08** (L2 disk cache budget, paired with
ADR-014), **F-10** (bounding `Image.memory`'s decode target below the
interactive zoom ceiling so Skia doesn't over-decode), **F-11** (unifying
full-res and thumbnail retry backoff curves — see `retry.dart`), **F-15**
(`CacheCoordinator.trimAll`, paired with ADR-011). **F-02–F-06, F-09,
F-12–F-14 are unrecovered** for the same reason as the ADR gaps above.

> Recommendation: when this document is adopted as the real
> `docs/architecture.md`, renumber nothing. Leave the gaps exactly as
> listed — a future ADR-021 should stay ADR-021 — so existing code comments
> that already cite specific numbers keep pointing at the right entries.

---

## 5. Container lifecycle state machine

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
        │           ┌───────────┐        USB detach /            │
        │  cancelUnlock  │Unlocked │───▶  screen-off auto-lock /  │
        │  (best-effort, │(rw/RO) │      lockContainer /          │
        │   next hash/   └─────┬───┘      app-lock enforcement ──┘
        │   cipher       import/export,
        │   boundary)    file I/O, SAF
        │                exposure, subfolder
        └────────────────mounts, camera capture,
                          in-vault editors, etc.
```

### 5.1 States

- **Locked** — no entry in `ContainerSessionRegistry.activeSessions` for
  this `volId`. This is the default/rest state; a `volId` here is free for
  `getFreeVolumeId()` to hand to the next unlock request.
- **Unlocking** — a `volId` has been reserved (`getFreeVolumeId()` or the
  existing `volId` for a re-unlock of an already-known URI) and
  `onUnlockStarted` has fired, but the session isn't registered yet. For
  auto-detect unlocks (`cipherId`/`hashId` == 255), the native side tries
  cipher/hash combinations and reports progress via `onUnlockProgress`
  (`attempted`/`total`/current `cipherId`/`hashId`/`slot`). This is the one
  state with a **cancellation path**: `requestCancelUnlockNative` asks an
  in-flight derivation to abort "at its next hash/cipher combination
  boundary" — explicitly documented as best-effort and bounded by roughly
  one PBKDF2 round, not instant.
- **Unlocked** — a `ContainerSession` exists in `activeSessions`. Two
  sub-states that affect behavior throughout the file-I/O layer:
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
  implementation regardless of *why* the container is being locked.

### 5.2 Terminal error outcomes (Unlocking → Locked, no session created)

| Error code | Meaning |
|---|---|
| `AUTH_FAIL` | Wrong password/keyfiles, or not a recognized container at all |
| `MAX_CONTAINERS` | All 8 volume slots already occupied |
| `CANCELLED` | User-requested cancellation completed |
| `INVALID_ARGS` | Missing required parameters (password+filePath, etc.) |
| `INVALID_VAULT` | Folder picked doesn't contain a recognized vault config |
| `KDF_FAILED` | Key derivation itself failed (not a wrong-password case) |

### 5.3 Errors reachable only from Unlocked (operation-level, not lifecycle)

| Error code | Meaning |
|---|---|
| `NOT_MOUNTED` | URI doesn't currently map to any `volId` |
| `NOT_UNLOCKED` | `volId` resolved, but the native side's own session check (`requireActiveSession`) failed — a defense-in-depth check independent of the Kotlin registry |
| `READ_ONLY` | Write attempted against a read-only-mounted volume |
| `C++_ERROR` | Catch-all native failure, message passed through |

---

## 6. Public API surface

The only stable cross-language contract is the single `MethodChannel`
(`com.aeidolon.vaultexplorer/engine`); every method name is a constant in
**`ChannelMethods`** (Dart) mirrored 1:1 by a Kotlin `ChannelMethods` object
inside `MainActivity` — that pairing is the actual API contract and both
sides must be updated together.

### 6.1 Dart → native (method calls)

| Group | Methods |
|---|---|
| Container lifecycle | `pickContainer`, `pickKeyfiles`, `createContainer`, `unlockContainer`, `lockContainer`, `updateContainerSettings`, `cancelUnlock`, `changeContainerPassword`, `mountContainerFolder`, `unmountContainerFolder`, `getMountedContainerFolders`, `hasAllFilesAccess`, `requestAllFilesAccess` |
| Directory vaults (Cryptomator/gocryptfs/CryFS) | `pick/unlock/create*Vault` × 3 formats, plus `isGocryptfsVault`/`isCryfsVault`, `finishWriteIfCryptomator` |
| File I/O | `decryptFile`, `exportFileToStorage`, `exportFilesToFolder`, `importFile`, `importFolder`, `cancelImport`, `deleteImportSources`, `getFileSize`, `getFolderSize`, `readFileChunk`, `writeFileChunk`, `writeBackFile`, `getSpaceInfo`, `getMediaFileSize`/`readMediaFileChunk` (routed to `fullResExecutor` specifically) |
| Directory ops | `listDirectory`, `createDirectory`, `renameFile`, `deleteFile`, `setLastModifiedTime` |
| Media/thumbnails | `openWithApp`, `get{Image,Video}Thumbnail[WithSize]`, `setPlaybackActive` |
| Crypto | `hashPassword`, `deriveDerivedKey`, `storeDerivedKey`, `loadDerivedKey`, `clearDerivedKey` |
| Security | `setSecureScreen` |
| USB | `listUsbDevices`, `requestUsbPermission`, `unlockUsbContainer`, `createUsbContainer`, `getUsbDeviceCapacity` |
| System | `documentExists`, `warmContainer`, `getDeviceCapabilityProfile` |

### 6.2 Native → Dart (event callbacks, via the same channel's method-call
handler in reverse — see `VaultExplorerApi.initMethodCallHandler`)

`onAppSelected`, `onUsbContainerDetached`, `onScreenOff`, `onUnlockStarted`,
`onUnlockProgress`, `onImportProgress`, `onCameraPermissionResult`,
`onTrimMemory`. Each has a corresponding typed `ListenerRegistry` (or, for
`onTrimMemory`, a direct call into `CacheCoordinator.trimAll`) — see §3.4.

### 6.3 Kotlin-internal facades (not exposed to Dart directly)

- **`ContainerEngine`** — format-neutral Tier-1/Tier-2 facade (§3.3). This is
  the API every new file-operation or lifecycle feature should be added to,
  not `NativeEngine` directly.
- **`NativeEngine`** — raw 1:1 JNI shim. Internal comment: *"App code must
  use `ContainerEngine`, never this object directly."* Two call tiers:
  **Tier 1** (session establishment: takes a real fd + password + PIM) and
  **Tier 2** (stateless, `volId`-only; the C++ side throws
  `IllegalStateException("NOT_UNLOCKED: ...")` via `requireActiveSession` if
  there's no active session).
- **`VaultBackend`** — the interface every pure-Kotlin directory-vault
  session implements, so `ContainerEngine` can dispatch to any of the three
  without a per-format branch at most call sites.
- **`ContainerFileSystem`** — the locking chokepoint in front of
  `ContainerEngine` for Tier-2 calls (§3.2); both `MainActivity` and
  `ContainerDocumentsProvider` (SAF) call through here, not `ContainerEngine`
  directly, specifically so locking/error-dispatch stay centralized.

---

## 7. Cross-references

This document's §4 numbering is the same numbering already used throughout
the codebase — grep for `ADR-0` or `Finding F-` to find every call site that
cites a specific entry. If you add a new architectural decision, give it the
next unused number (currently **021**) rather than reusing any of the
unrecovered gaps, and cite it the same way existing code does:
`// See docs/architecture.md ADR-021.`
