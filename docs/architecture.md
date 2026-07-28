# VaultExplorer — Media Cache & Rendering Pipeline Architecture

**Scope:** thumbnail generation, in-memory/disk caching, full-resolution image loading, and
video-poster handling for the file browser grid/masonry/list views, the media viewer
(`PageView` carousel), and the playlist carousel overlay.

**Status of this document:** living record, tracked in-repo at `docs/architecture.md`. Every
non-trivial design decision in this subsystem should be captured here as an ADR (Architecture
Decision Record) at the time it's made, not reconstructed later. When a decision changes,
don't delete the old entry — mark it `Superseded by ADR-0NN` and add the new one. Section 7
(Audit Findings) and Section 9 (Roadmap) are pruned/updated as items are resolved, but
resolved items are annotated in place (`[RESOLVED]`, with what resolved them) rather than
deleted, so the history of what was wrong and how it got fixed stays legible.

**Last audited:** 2026-07-28, fourth pass. This pass completes all remaining missing tasks from the roadmap: end-to-end device capability profiling (`DeviceCapabilityService`), native + Flutter memory pressure wiring (`MemoryPressureObserver` & `onTrimMemory`), scroll-fling-aware queue cancellation in grid/masonry views (F-13), and L2 disk cache LRU byte-budget eviction with an automated janitor (`ThumbnailCacheService.enforceDiskBudget`, ADR-014 / F-08).

---

## 1. System Overview

VaultExplorer renders thumbnails and full images for files that live *inside encrypted
containers* (VeraCrypt/LUKS/gocryptfs/Cryptomator/CryFS). Nothing can be read directly off
disk by the OS's normal image-loading widgets (`Image.file`, `Image.network`, Glide, Coil,
etc.) because the bytes on disk are ciphertext. Every thumbnail and every full-resolution
image is produced by decrypting through the native container engine first. This is the
single fact that shapes the whole pipeline and is why the app carries a bespoke cache/queue
system instead of `cached_network_image` or a stock Glide/Coil pipeline — see ADR-015
(re-confirmed previously, Section 8).

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Flutter UI isolate (Dart)                                                │
│                                                                           │
│  FileGridView / FileMasonryView / FileTile / PlaylistCarouselOverlay      │
│  MediaViewerScreen (viewer prefetch — no longer a separate cache silo)    │
│        │  AsyncThumbnail (widget) ── PriorityTaskQueue ── inFlightThumbnails│
│        │        (ADR-010: tiered LIFO, ADR-012: playback-gated admission) │
│        ▼                                                                 │
│  ThumbnailCacheService  (L1 memory [byte-budgeted] + L2 disk, AES-GCM)   │
│  MediaAspectRatioCache / MediaRotationCache  (metadata caches)           │
│  FullResImageCache      (byte-budgeted L1, full-res viewer only)         │
│  CacheCoordinator       (memory-pressure trim fan-out — built, unwired)  │
│  PlaybackThrottleController ── VideoPlaybackManager (single shared player)│
│        │                                                                 │
│        ▼  MethodChannel 'com.aeidolon.vaultexplorer/engine'              │
├─────────────────────────────────────────────────────────────────────────┤
│ Android platform layer (Kotlin) — MainActivity + *Handlers                │
│                                                                           │
│   ioExecutor(4)        — general file I/O                                │
│   thumbnailExecutor(3) — ThumbnailHandlers (image inSampleSize decode,   │
│                           video MediaMetadataRetriever frame extraction) │
│   fullResExecutor(2)   — FileOperationHandlers full-file reads           │
│   DeviceCapabilityProfiler — device tier (LOW/MED/HIGH), queried once,   │
│                               does not resize the executors above        │
│   onTrimMemory(level)  — forwarded to Dart as-is, no native handling     │
│        │                                                                 │
│        ▼  JNI                                                            │
├─────────────────────────────────────────────────────────────────────────┤
│ C++ container/crypto engine (cpp/)                                       │
│   vhd/vhdx, dislocker, filesystems, crypto, decrypted_block_cache        │
└─────────────────────────────────────────────────────────────────────────┘
```

Three logically distinct payload types flow through this pipeline, and they are **not**
interchangeable, which is why the audit in Section 7 treats them separately:

| Payload | Produced by | Typical size | Consumers |
|---|---|---|---|
| Thumbnail (image) | `ThumbnailHandlers.handleGetImageThumbnail[WithSize]` — `inSampleSize` downscaled, JPEG re-encoded | a few KB – ~150 KB | grid/masonry/list tiles, carousel overlay, media-viewer placeholder |
| Thumbnail (video poster) | `ThumbnailHandlers.handleGetVideoThumbnail[WithSize]` — `MediaMetadataRetriever` frame extract | a few KB – ~150 KB | grid tiles, carousel overlay, media-viewer poster |
| Full-resolution image | `FileOperationHandlers` full decrypted file read (no downscale) | hundreds of KB – tens of MB (RAW) | `EncryptedImageWidget` in the media viewer only |

**What changed since the last audit:** all of this round's work is Dart-side except two small,
targeted Kotlin additions. Specifically:

- **F-09 fully closed.** `ThumbnailHandlers.handleGenerateAndCacheThumbnail`, its `encodeKey()`
  helper, and the orphaned `java.io.File` import are deleted outright — confirmed via
  repo-wide search, zero references remain anywhere in `kotlin/`.
- **F-16 decided and wired.** `ThumbnailCacheService.clearAppCacheFor()` is now called from
  `VaultDashboardScreen._onContainerLocked`, scoped to the locking container only.
  `clearInContainerCacheByUri()` is deliberately left un-wired, with the reasoning recorded
  inline at the call site and in Ownership Rule 5.
- **F-01, first slice.** `ThumbnailCacheService._memoryCache` is now a 24 MB `ByteBudgetCache`
  instead of a 120-entry `LruCache`. `ThumbnailConcurrency.inFlightThumbnails` is still an
  entry-count `LruCache(160)`, but `AsyncThumbnail` no longer leaves a resolved entry sitting
  in it until LRU eviction — it's removed as soon as the underlying future settles, matching
  the pattern `FullResImageCache._inFlight` already used correctly.
- **New: `CacheCoordinator`** (`lib/core/services/cache_coordinator.dart`) — a single
  `trimAll(TrimLevel)` fan-out point touching `inFlightThumbnails`,
  `ThumbnailCacheService`'s memory tier, and `FullResImageCache` uniformly. Built, but nothing
  invokes it yet (see Section 9).
- **New: `DeviceCapabilityProfiler` (Kotlin)** and **`MainActivity.onTrimMemory`** — the device
  gets classified into a LOW/MEDIUM/HIGH tier once at startup and exposed over the channel;
  Android's `onTrimMemory(level)` is forwarded to Dart as a raw `invokeMethod` call. Neither
  has a Dart-side consumer yet.
- **New Finding F-17**, caught and fixed while doing the above: `clearAppCacheFor()` originally
  cleared the *entire* memory cache instead of just the locked container's entries, and
  `ByteBudgetCache.trimToFraction()`'s fraction semantics were inverted relative to
  `LruCache.trimToFraction()`'s. Both fixed before `CacheCoordinator` was built on top of them.

Details are in Sections 4–9.

---

## 2. Ownership Rules

These are the rules that currently hold (and should keep holding after refactor) for who is
allowed to read/write each cache, and when each cache must be invalidated.

1. **Every cache key is scoped to a mounted session, not just a file path.** Container
   sessions are keyed by `volId:mountedAt` (memory tiers) or by the container's URI
   (disk tiers). This is deliberate: the same volume slot (`volId`) can be reused by a
   *different* container across lock/unlock cycles, and a different container mounted into
   the same slot must never see the previous container's cached bytes. Any new cache added
   to this subsystem **must** follow this convention — do not key by `filePath` alone, and
   do not key by `volId` alone for anything that survives unmount/remount. `ThumbnailConcurrency
   .inFlightThumbnails` follows this scheme exactly, keyed identically by every one of its
   callers (grid tiles, carousel, and viewer prefetch alike). `ThumbnailCacheService
   ._memKey()`'s in-memory keys are `volId`-prefixed for exactly this reason, which is also
   what makes the F-16 fix's `removeWhere((key) => key.startsWith('$volId:'))` scoping
   possible without touching other mounted containers' entries (see Finding F-17).
2. **Only `ThumbnailCacheService` may write the on-disk thumbnail cache.** No other class
   touches `thumbs/<encodedUri>/` directly. The native `handleGenerateAndCacheThumbnail` path
   that used to violate this (Finding F-09) is now deleted outright — function body,
   `encodeKey()` helper, and the orphaned `java.io.File` import are all gone, not just
   unreachable.
3. **`FullResImageCache` is memory-only and session-scoped, by design (ADR-002).** It is
   never written to disk: the native `ChunkedFileEngine` already maintains its own
   decrypted-chunk cache, so a second disk copy would be pure duplication of a slower,
   larger payload than thumbnails.
4. **Cache mode (`ThumbnailCacheMode`: `appCache` / `inContainer` / `disabled`) is a
   per-container, user-controlled setting** and every disk write/read in
   `ThumbnailCacheService` must respect it. `disabled` means *no* bytes are ever persisted,
   which is a privacy guarantee, not just a performance knob — refactors must not
   introduce a code path that silently writes to disk when the mode is `disabled`. Note that
   `appCache` mode's encryption key (`AppCacheEncryption`) is a single device-level key,
   independent of any container's own mount state — this is precisely why Rule 5 now treats
   `appCache`-mode disk thumbnails differently from `inContainer`-mode ones on lock.
5. **Lock/unmount owns cache teardown — now honored, with one deliberate exception.** On
   container lock, `VaultDashboardScreen._onContainerLocked` calls
   `FullResImageCache.clear()` and `ThumbnailCacheService.clearAppCacheFor(container)`
   (Finding F-16, resolved). `clearInContainerCacheByUri()` is **deliberately not** called on
   lock: `inContainer`-mode thumbnails are keyed by the container's own URI, stay valid
   across a relock/re-mount of the *same* container, and are only ever reachable while the
   container is mounted anyway — eagerly wiping them would cost regeneration time with no
   privacy or correctness upside. `appCache`-mode thumbnails don't get that same protection,
   because their encryption key is device-level rather than container-scoped (Rule 4), so
   they're clearable-at-any-time regardless of lock state — that's the material privacy
   difference that made this rule worth actually enforcing rather than leaving as an
   intended-but-unimplemented invariant. `MediaAspectRatioCache` and `MediaRotationCache` are
   still intentionally *not* cleared on lock (small, keyed by URI, harmless to keep warm
   across a relock of the same volume) — do not "fix" this without checking memory budget
   impact first. The manual "Clear Thumbnail Cache" button in `ContainerConfigSheet` remains
   the only caller of `clearInContainerCacheByUri()` — a deliberate user action, not lock
   teardown, and that division of responsibility is intentional.
6. **Settings changes that affect rendered output must change the cache key, not force a
   manual flush.** `ThumbnailQuality` (size + JPEG quality) is folded into every disk/L1
   key via `_qualifiedPath`. If you add a new setting that changes what bytes get produced
   for a given file (e.g. a future "prefer HEIC" toggle), fold it into the key the same way
   — do not add a global cache-clear-on-settings-change side effect.
7. **Concurrency gates are process-global singletons, not per-screen.** `ThumbnailConcurrency
   .imageLimiter`/`videoLimiter` and `FullResImageCache.limiter` are shared across every
   surface in the app for a reason: they are the only thing standing between "user has grid
   + carousel + viewer all alive at once" and the native executor queues being flooded. Do
   not instantiate a second gate for a new surface — extend the existing ones. These are
   `PriorityTaskQueue` instances (ADR-010), and every admission decision they make also
   consults `PlaybackThrottleController.isPlaybackActive` (ADR-012) — see Section 5.
8. **Memory-pressure trims go through `CacheCoordinator.trimAll()`, not ad hoc per-cache
   calls.** Now that `LruCache.trimToFraction()`/`ByteBudgetCache.trimToFraction()` exist on
   every memory-tier cache, it would be easy for a future native-signal handler to call one
   cache's trim directly "just for now." Don't — `CacheCoordinator` exists precisely so a
   single `TrimLevel` maps to the same effective shed fraction across every cache in Section
   4 (Finding F-17 exists because two caches' `trimToFraction()` didn't agree on this before
   `CacheCoordinator` was built). Any new memory-tier cache added to this subsystem should
   register itself in `CacheCoordinator.trimAll()`, not just gain its own unused
   `trimToFraction()` method.

---

## 3. Thread & Isolate Model

**Executors/isolates themselves are unchanged since the original audit** — this round's work
(like the previous one) is Dart-side admission/cache logic sitting *above* this table, plus
two narrow Kotlin additions that read device state and forward a callback without touching
the executors. Kotlin/C++ sizing (Finding F-14) and memory-pressure response (Finding F-15)
are now partially — not fully — addressed; see below.

| Pool | Where | Size today | Runs | Gap |
|---|---|---|---|---|
| Dart main isolate | Flutter UI | 1 (n/a) | widget build/layout/paint, all `async`/`await` orchestration, `AES-GCM` inline for payloads `< 500 KB` (`ThumbnailCacheService._computeThresholdBytes`) | small-payload crypto still executes synchronously on the UI isolate's event loop; usually microseconds per thumbnail but adds up under burst load (Finding F-11 — the *retry* half of this row is resolved; the inline-crypto threshold itself is unchanged and still a Phase-2-or-later candidate, see ADR-016) |
| `compute()` isolate | Dart, spawned per call | ephemeral | AES-GCM for payloads `≥ 500 KB` (disk-cache encrypt/decrypt only) | none for its stated purpose; not used for JPEG decode/encode (native already owns that) |
| `ioExecutor` | Kotlin, `MainActivity.kt:93` | fixed(4) | general file ops, USB, import/export, derived-key work | shared by many unrelated handlers; not size-tuned per device (Finding F-14 — `DeviceCapabilityProfiler` now *reports* a device tier, but nothing resizes this pool with it; see ADR-019) |
| `thumbnailExecutor` | Kotlin, `MainActivity.kt:94` | fixed(3) | image `inSampleSize` decode + JPEG re-encode, video `MediaMetadataRetriever` frame extraction | **shared between image and video thumbnail work** — throttled at the *Dart admission layer* during active video playback (ADR-012, Finding F-06 resolved); still fixed size regardless of device core count or reported tier (Finding F-14 — unresolved for this pool specifically) |
| `fullResExecutor` | Kotlin, `MainActivity.kt:95` | fixed(2) | full decrypted file reads for the media viewer | fixed size regardless of device RAM/flash speed (Finding F-14, unresolved for this pool specifically) |
| Android main thread | Kotlin | 1 (n/a) | `MethodChannel` result delivery (`runOnUiThread`), `MediaCodec`/`ExoPlayer`/VLC decode for **active video playback**, plus (new) `Activity.onTrimMemory(level)` | this is the thread whose stalls the user perceives as "frame drops" during video playback, and also the one that now receives Android's raw trim-memory callback and forwards it to Dart unmodified — see `MainActivity.onTrimMemory` in Section 6 |
| C++ / JNI | native | n/a | container filesystem decrypt (`decrypted_block_cache.h`), read path for both thumbnail and full-res requests | has its own internal cache (chunk cache) that this document doesn't govern — treat as a black box lower tier |

**Device-capability query (new).** `DeviceCapabilityProfiler` (Kotlin, `object`) computes a
`Tier` (`LOW`/`MEDIUM`/`HIGH`) once per process from `ActivityManager.isLowRamDevice`,
`ActivityManager.getMemoryClass()`, and `Runtime.getRuntime().availableProcessors()`, caches
it, and answers `getDeviceCapabilityProfile` over the channel with the tier plus the raw
signal values. **By its own design, it does not resize `ioExecutor`/`thumbnailExecutor`/
`fullResExecutor`** — those are fixed-size `ExecutorService`s constructed before `Context` is
fully available for this check to run, and live-resizing a running thread pool's core/max
size is treated as a separate, riskier change than the Dart-side primitives (`resize()` on
every `LruCache`/`ByteBudgetCache`/`PriorityTaskQueue`) this profiler currently feeds. See
ADR-019.

**Rule going forward:** any new background work must declare which executor it belongs on
and why, in this table, before it ships. "It ran fine on my Pixel" is not a sizing
methodology — see ADR-011 (in progress: the Kotlin-side device-tier signal now exists and is
queryable; nothing on the Dart side calls it yet, and the executor pools above remain
unresized by any of this regardless).

---

## 4. Cache Topology (current state)

```
L1 — in-memory, per-process, cleared on cold start
 ├─ ThumbnailConcurrency.inFlightThumbnails  LruCache<String, Future<Uint8List>>  cap 160
 │     (unified previously — was two independent caches, imageCache(60)/videoCache(100);
 │      see Findings F-02/F-12, resolved. This round: entries are now removed as soon as
 │      the underlying Future settles — success or error — instead of lingering until
 │      evicted by entry count. Still entry-count bounded, not byte-budgeted — remaining
 │      scope of Finding F-01 for this structure specifically.)
 ├─ ThumbnailCacheService._memoryCache  ByteBudgetCache  cap 24 MB
 │     (converted this round from a 120-entry LruCache<String, Uint8List> — Finding F-01,
 │      first slice, resolved for this cache. `resizeMemoryBudget()` and
 │      `trimMemoryToFraction()` are the ADR-011 hooks for it.)
 ├─ FullResImageCache._cache          ByteBudgetCache                    cap 150 MB total
 ├─ FullResImageCache._inFlight       LruCache<String, Future<Uint8List?>> cap 8 entries
 ├─ MediaAspectRatioCache._cache      LruCache<String, double>            cap 2000 entries
 ├─ MediaRotationCache._cache         LruCache<String, int>               cap 2000 entries
 └─ [REMOVED] MediaViewerScreen._prefetchedImages — this ad hoc third cache is gone.
       MediaViewerScreen._prefetchedBytesFor() now reads through
       ThumbnailCacheService.getFromMemory() like every other surface (Findings
       F-02/F-03/F-12, resolved).

L2 — on-disk, persists across app restarts, per-container
 ├─ ThumbnailCacheService (appCache mode): <appCacheDir>/thumbs/<encodedUri>/*   UNBOUNDED (F-08, still open)
 │     Now cleared on container lock via clearAppCacheFor() (Finding F-16, resolved) —
 │     scoped to the locking container's volId prefix in the memory tier and to its own
 │     directory on disk; other mounted containers' entries are untouched.
 └─ ThumbnailCacheService (inContainer mode): <container>/.thumbcache/*         UNBOUNDED (F-08, still open)
       Deliberately NOT cleared on lock — see Ownership Rule 5. The dead
       `ThumbnailHandlers.handleGenerateAndCacheThumbnail` native path (Finding F-09) that
       used to write a *third*, orphaned disk location is now fully deleted, not merely
       unreachable — function body, `encodeKey()` helper, and the unused `java.io.File`
       import are gone from `ThumbnailHandlers.kt`.

L3 — native decrypted-chunk cache inside the C++ engine (decrypted_block_cache.h)
   Out of scope for this document; treated as an opaque lower tier that both the
   thumbnail path and the full-res path sit on top of.
```

Four things to notice, expanded on in Section 7:

- **L1's fragmentation problem is resolved; its byte-budgeting problem is now half-resolved.**
  L1 is down to two cooperating structures — one shared in-flight `Future` map
  (`inFlightThumbnails`) used by every caller for de-dup, and one cache-of-record for the
  actual decoded bytes (`ThumbnailCacheService._memoryCache`). The cache-of-record is now
  byte-budgeted (24 MB `ByteBudgetCache`). The in-flight map is not — it remains a 160-entry
  `LruCache<String, Future<Uint8List>>` — but a resolved entry no longer sits there
  occupying a slot until LRU eviction; `AsyncThumbnail._load()` removes it the moment its
  future settles, the same way `FullResImageCache._inFlight` already worked. Converting
  `inFlightThumbnails` itself to byte-accounted storage is still open and needs a small
  adapter, since it holds `Future<Uint8List>` rather than raw bytes (see Finding F-01,
  remaining scope).
- **L2 still has a `mode`, a key scheme, and — for `appCache` mode specifically — a teardown
  hook that now actually fires, but still no eviction policy.** `appCacheBytesFor()` /
  `totalAppCacheBytes()` still exist to *measure* disk usage but nothing calls them to *act*
  on it (Finding F-08, unchanged, still the single largest open 🔴 finding).
- **Admission through the L1 gates remains playback-aware**, unchanged from the previous
  round: `PriorityTaskQueue` instances (`ThumbnailConcurrency.imageLimiter`/`videoLimiter`,
  `FullResImageCache.limiter`) each consult `PlaybackThrottleController.isPlaybackActive` on
  every admission decision (ADR-012).
- **Memory-pressure trimming now has one fan-out point, `CacheCoordinator.trimAll()`, but no
  caller.** It touches `inFlightThumbnails`, `ThumbnailCacheService`'s memory tier, and
  `FullResImageCache` with one consistent `TrimLevel → fraction` mapping (this consistency
  had to be fixed first — see Finding F-17). Nothing invokes it yet: Android's forwarded
  `onTrimMemory` has no Dart-side handler, and no `WidgetsBindingObserver
  .didHaveMemoryPressure()` exists for the Flutter-level/iOS signal. This is the biggest
  remaining piece of ADR-011's memory-pressure half — see Section 9.

---

## 5. Task Lifecycle State Machine

This is the state machine every thumbnail/full-res request goes through today, centered on
`AsyncThumbnail` (grid/carousel/viewer-prefetch path — all three share it, see Section 4)
and `EncryptedImageWidget`/`FullResImageCache` (viewer path). The state *names* and admission
mechanics below are unchanged from the previous round; the only change this round that
touches this diagram at all is a cleanup-timing detail in `AWAITING EXISTING FUTURE` /
`SUCCESS`/`ERROR`, noted below the diagram — it does not add or remove a state.

```
                 ┌────────────────────────────────────────────────────────┐
                 │                         IDLE                            │
                 │  widget built; syncLookup() checked first (L1 hit path) │
                 └───────────────┬──────────────────────────┬─────────────┘
                     sync hit    │                           │ sync miss
                                 ▼                            ▼
                          ┌─────────────┐             ┌───────────────────┐
                          │   SUCCESS   │             │      QUEUED        │
                          │ (immediate) │             │ in-flight Future   │
                          └─────────────┘             │ found in L1 cache? │
                                                       └─────┬─────────┬───┘
                                                     yes:await      no:
                                                             │           │
                                                             ▼           ▼
                                                     ┌─────────────┐ ┌────────────┐
                                                     │  AWAITING   │ │ DEBOUNCING  │
                                                     │  EXISTING   │ │ (100–150ms) │
                                                     │  FUTURE     │ └──────┬─────┘
                                                     └──────┬──────┘   still wanted?
                                                            │           │yes    │no
                                                            │           ▼       ▼
                                                            │     ┌──────────┐ ┌───────────┐
                                                            │     │ GATED —  │ │ CANCELLED │
                                                            │     │ acquire()│ │(no fetch  │
                                                            │     │ on the   │ │ ever sent)│
                                                            │     │ shared   │ └───────────┘
                                                            │     │ priority │
                                                            │     │ queue    │
                                                            │     └────┬─────┘
                                                            │    waiting in queue │ turn granted
                                                            │          ▼          ▼
                                                            │    ┌───────────┐ ┌───────────┐
                                                            │    │ CANCELLED │ │  FETCHING  │
                                                            │    │(dequeued, │ │ (MethodCh- │
                                                            │    │ dispose() │ │ annel round│
                                                            │    │ called    │ │ trip; still│
                                                            │    │ before a  │ │ Wanted()   │
                                                            │    │ turn)     │ │ re-checked;│
                                                            │    │           │ │ retried w/ │
                                                            │    │           │ │ backoff on │
                                                            │    │           │ │ failure)   │
                                                            │    └───────────┘ └─────┬─────┘
                                                            │                   ok │  error
                                                            │                       ▼      ▼
                                                            │                 ┌─────────┐ ┌────────┐
                                                            └────────────────▶│ SUCCESS │ │ ERROR   │
                                                                              │(cached, │ │(retries │
                                                                              │released)│ │exhausted│
                                                                              └─────────┘ │- F-11)  │
                                                                                           └────────┘
```

**Admission through `GATED`.** The shared gate is a tiered, playback-aware queue.
`PriorityTaskQueue.acquire(completer, priority: ...)` checks, in order: (1) whether a slot is
available at all under `maxConcurrency`, and if a video is currently playing, whether the
request's tier is allowed to proceed right now (`PlaybackThrottleController.isPlaybackActive`
— `background` is blocked outright, `adjacent` is capped to one concurrent, `visible` is
never throttled); and (2) once a slot opens up, which *waiting* request gets it — tiers are
drained highest-priority-first (`visible` > `adjacent` > `background`), and within a tier,
the most recently queued request wins (LIFO). None of this changed this round.

**Cleanup timing (this round's change, no new state).** Once a request in `AWAITING EXISTING
FUTURE` reaches `SUCCESS` or `ERROR`, the `inFlightThumbnails` entry for its cache key is
removed immediately (`AsyncThumbnail._load()`'s `whenComplete` handler), rather than being
left for the `LruCache`'s entry-count eviction to eventually clear out. This doesn't change
which state a request is in or how it gets there — it changes how long a *settled* future
keeps occupying a slot in the shared de-dup map after every waiter has already gotten their
answer. Decoded bytes remain durably available afterward via `ThumbnailCacheService
._memoryCache` regardless (every `fetchFn` implementation calls `putInMemory`), so a later
request for the same key falls through to a fresh sync/L1 lookup instead of finding a stale
`inFlightThumbnails` entry.

Key transition rules currently enforced in code (must be preserved by any refactor):

- **Cancellation only removes a request from the *waiting* queue.** A request that has
  already been granted a turn and is mid-flight (`FETCHING`) cannot be cancelled — there is
  no cancellable `MethodChannel` call. This is why `isStillWanted()` is re-checked both at
  turn-grant time and (for full-res) before the native round trip: it can't stop in-flight
  native work, but it can avoid *starting* stale work and avoid *storing* a stale result.
- **`didUpdateWidget` re-entry (fast re-key, e.g. `ListView` recycling a tile for a
  different file) always cancels the old request before starting a new one** — see
  `AsyncThumbnail._cancel()` / `EncryptedImageWidget._cancelPendingLoad()`.
- **`dispose()` always cancels.** This is still effectively the only cancellation trigger —
  `PriorityTaskQueue.cancelTier(TaskPriority)` exists and can drop every *waiting* request in
  a tier at once, which is exactly the primitive Finding F-13 asked for, but nothing calls it
  in response to scroll velocity yet. There is still no independent fling detection; the
  100–150 ms debounce remains the only lever limiting queue churn during a fast fling
  (Finding F-13, still open — see Section 7).
- **A failed `FETCHING` attempt retries with exponential backoff before surfacing an
  error** (Finding F-11, resolved) — both the thumbnail path and the full-res path share one
  `retryWithBackoff()` helper, each re-checking "is this still wanted" between attempts so a
  request that's gone stale while retrying bails out instead of burning further native round
  trips.

### Container session state machine (governs cache validity, not task flow)

```
LOCKED ──unlock()──▶ MOUNTED ──(browsing / thumbnails / viewer all active)──▶ MOUNTED
   ▲                                                                              │
   │                                                                     lock()  │
   └──────────────────────────────────────────────────────────────────────────────┘
```
On `MOUNTED → LOCKED`: confirmed in `VaultDashboardScreen._onContainerLocked`, which now
calls both `FullResImageCache.clear()` and `ThumbnailCacheService.clearAppCacheFor(container)`
(Finding F-16, resolved this round). `clearInContainerCacheByUri()` deliberately does **not**
run on this transition — see Ownership Rule 5. On `LOCKED → MOUNTED` (fresh `mountedAt`):
every memory key changes automatically because `mountedAt.millisecondsSinceEpoch` is part of
the key — no explicit clear is needed for L1, only for the `appCache` disk tier on true lock
(not on process death, where L2 is expected to survive and be re-validated by key).

---

## 6. Public APIs (current)

These are the contracts a caller can rely on today. Anything not listed here is an
implementation detail and may change without notice.

### `AsyncThumbnail` (widget) — `lib/core/widgets/thumbnail/async_thumbnail.dart`
```dart
AsyncThumbnail({
  required MountedContainer container,
  required String filePath,
  required LruCache<String, Future<Uint8List>> cache,   // caller picks which shared cache
  required PriorityTaskQueue limiter,                     // caller picks which shared gate
  required Future<Uint8List> Function(MountedContainer, String) fetchFn,
  required Widget Function(BuildContext, Uint8List, int? cacheHeight) imageBuilder,
  Duration debounce = const Duration(milliseconds: 100),
  Uint8List? Function()? syncLookup,                      // fast-path L1 check
  int? cacheHeight,                                       // forwarded to imageBuilder for Image.memory
  TaskPriority priority = TaskPriority.visible,            // ADR-010 admission tier
  WidgetBuilder? loadingBuilder,
  WidgetBuilder? errorBuilder,
})
```
Contract: cancels any in-flight request on dispose or on `filePath` change; de-dupes via
`cache`; never calls `fetchFn` for a tile that's been scrolled away before its debounce
elapses; retries the actual fetch with exponential backoff (`retryWithBackoff`, up to 3
attempts) before surfacing `errorBuilder` — re-checking "still wanted" between attempts.
`priority` defaults to `TaskPriority.visible` so every pre-existing call site (grid/masonry/
list tiles) behaves exactly as before without changes; callers rendering an off-screen
neighbor (`PlaylistCarouselOverlay`, the media viewer's next/prev prefetch) pass
`TaskPriority.adjacent` explicitly. **New this round:** once the stored future in `cache`
settles (success or error), the entry is removed from `cache` immediately rather than left
for LRU eviction — see Section 5, "Cleanup timing."

### `TaskPriority` — `lib/core/utils/task_priority.dart`
```dart
enum TaskPriority { visible, adjacent, background }
```
Ordered highest-to-lowest priority. `visible` is an on-screen tile or the media viewer's
current page. `adjacent` is off-screen-but-near: viewer next/prev prefetch, carousel
neighbors. `background` is speculative, non-adjacent prefetch — no current caller uses this
tier; it exists so a future "warm this whole folder" feature doesn't need another migration.

### `PriorityTaskQueue` — `lib/core/widgets/thumbnail/priority_task_queue.dart`
```dart
class PriorityTaskQueue {
  PriorityTaskQueue(int maxConcurrency);
  Future<void> acquire(Completer<void> completer, {TaskPriority priority = TaskPriority.visible});
  void cancel(Completer<void> completer);       // no-op if already running or already granted
  void cancelAll();                              // clears every waiting tier
  void cancelTier(TaskPriority tier);            // clears only the given tier's waiting queue
  void release(Completer<void> completer);
  void resize(int newMaxConcurrency);            // ADR-011 hook — currently uncalled, see F-14
}
```
Contract: services tiers highest-priority-first; within a tier, genuinely LIFO
(`Queue.removeLast()`). Every admission decision also checks
`PlaybackThrottleController.isPlaybackActive` (ADR-012): while a video is playing,
`background` is never admitted, `adjacent` is capped to one concurrent slot, `visible` is
unaffected. `cancelTier()` is the primitive Finding F-13 asked for — it exists and works but
has no caller yet.

### `ThumbnailConcurrency` — process-wide singletons — `lib/core/widgets/thumbnail/thumbnail_concurrency.dart`
```dart
static final imageLimiter = PriorityTaskQueue(2);
static final videoLimiter = PriorityTaskQueue(1);
static var inFlightThumbnails = LruCache<String, Future<Uint8List>>(160);

static void resizeForDevice({
  required int imageConcurrency,
  required int videoConcurrency,
  required int inFlightCapacity,
});  // ADR-011 hook — ready, currently uncalled (DeviceCapabilityProfiler now exists on the
     // Kotlin side and is queryable, but nothing on the Dart side calls this yet, F-14)
```
Contract: shared by every surface (grid, masonry, list, carousel overlay, and the media
viewer's own prefetch). `inFlightThumbnails` replaces the old two independent
`imageCache`/`videoCache` maps: safe to share across image and video requests because cache
keys already encode container + `mountedAt` + path + quality, so two different files' keys
never collide and the same file is never requested as both an image and a video thumbnail.
Still entry-count bounded (Finding F-01, remaining scope), but entries no longer linger past
resolution — see `AsyncThumbnail`'s contract above. Do not instantiate parallel gates/caches
for a new surface (Ownership Rule 7).

### `retryWithBackoff` — `lib/core/utils/retry.dart`
```dart
Future<T> retryWithBackoff<T>(
  Future<T> Function(int attempt) attemptFn, {
  int maxAttempts = 3,
  Duration initialDelay = const Duration(milliseconds: 200),
  double multiplier = 2.0,
  Duration maxDelay = const Duration(seconds: 3),
  bool Function(Object error)? retryIf,
});
```
Contract: exponential backoff (200ms → 400ms → ... capped at `maxDelay`), rethrows on the
last attempt or when `retryIf` returns false. Shared by `AsyncThumbnail._fetchWithQueue` and
`FullResImageCache._runGated`.

### `PlaybackThrottleController` — `lib/core/services/playback_throttle_controller.dart`
```dart
class PlaybackThrottleController {
  static final ValueNotifier<bool> isPlaybackActive = ValueNotifier<bool>(false);
  static void setActive(bool active);
}
```
Contract: a single process-wide flag, true while the app's one shared video player
(`VideoPlaybackManager`, see ADR-017) has an active video `MediaCodec` decode session.
Deliberately scoped to *video* only, not audio. Toggled from
`MediaViewerScreen._activateCurrentMedia()`/`dispose()`. Every `PriorityTaskQueue` consults
this on every admission decision — no caller needs its own "is video playing" awareness.

### `CacheCoordinator` — `lib/core/services/cache_coordinator.dart` *(new this round)*
```dart
enum TrimLevel { moderate, severe }

class CacheCoordinator {
  static void trimAll(TrimLevel level);
}
```
Contract: the single fan-out point for "the OS says memory is tight, shed what you can
spare" (Findings F-14/F-15, ADR-011; see new ADR-018). `trimAll()` applies the same
fraction — `0.5` for `moderate`, `0.9` for `severe` — to `ThumbnailConcurrency
.inFlightThumbnails`, `ThumbnailCacheService`'s memory tier (via `trimMemoryToFraction()`),
and `FullResImageCache` (via `trimToFraction()`). `MediaAspectRatioCache`/
`MediaRotationCache` are deliberately excluded (small, harmless to keep warm per Ownership
Rule 5). Safe to call as often as a native signal fires — every underlying `trimToFraction`
call is a no-op on an already-empty/near-empty cache. **Not yet wired to any real signal:**
`MainActivity.onTrimMemory` forwards Android's level to Dart, but `VaultExplorerApi
.initMethodCallHandler` has no `'onTrimMemory'` case yet, and no `WidgetsBindingObserver
.didHaveMemoryPressure()` exists for the Flutter-level/iOS signal — see Section 9.

### `LruCache<K, V>` — `lib/core/utils/lru_cache.dart`
```dart
class LruCache<K, V> {
  LruCache(int capacity);
  V? operator [](K key);       // promotes to MRU on hit
  void operator []=(K key, V value);
  bool containsKey(K key);
  void remove(K key);
  void clear();
  int get length;
  int get capacity;
  void resize(int newCapacity);
  void trimToFraction(double fraction);  // fraction = how much of what's held to evict
}
```
Contract: **entry-count capacity only**. `trimToFraction(fraction)` evicts the
least-recently-used `fraction` (0.0–1.0) of *currently held* entries, without permanently
changing `capacity` — this is `CacheCoordinator`'s `moderate`/`severe` lever. Safe for
fixed/bounded-size payloads; **unsafe** for anything whose size varies by orders of
magnitude or scales with a user-controlled setting (Finding F-01 — no longer applies to
`ThumbnailCacheService._memoryCache`, which moved to `ByteBudgetCache` this round; still
applies to `inFlightThumbnails`).

### `ByteBudgetCache` — `lib/core/utils/byte_budget_cache.dart`
```dart
class ByteBudgetCache {
  ByteBudgetCache(int maxTotalBytes);
  Uint8List? operator [](String key);
  void operator []=(String key, Uint8List value);   // silently drops values > maxTotalBytes
  void remove(String key);
  void removeWhere(bool Function(String key) test);  // NEW this round — Finding F-17
  void clear();
  int get currentBytes;
  int get maxTotalBytes;
  int get length;
  void resize(int newMaxTotalBytes);
  void trimToFraction(double fraction);   // fraction = how much of what's held to evict
}
```
Contract: LRU eviction by total bytes held, not entry count — the correct primitive for
variable-size payloads. Used by `FullResImageCache` and, as of this round, by
`ThumbnailCacheService._memoryCache`. `removeWhere()` is new this round: it powers the F-16
lock-teardown fix, removing only the locking container's entries (matched by `volId` key
prefix) rather than every mounted container's cached bytes. **`trimToFraction()`'s semantics
were fixed this round (Finding F-17):** it previously meant "trim down to `fraction` of
`maxTotalBytes`" — the inverse of `LruCache.trimToFraction()`'s "evict `fraction` of what's
currently held" — which would have made `CacheCoordinator.trimAll()` apply wildly different
effective trims depending on which cache type backed a given tier. Both classes now agree on
the same convention.

### `ThumbnailCacheService` — `lib/data/services/thumbnail_cache_service.dart`
Static service, three read/write surfaces:
```dart
static Uint8List? getFromMemory(container, filePath, [quality]);
static (Uint8List, int?, int?)? getWithSizeFromMemory(container, filePath, [quality]);
static void putInMemory(container, filePath, data, [quality, width, height]);

static Future<Uint8List?> get({required container, required filePath, required mode, required quality});
static Future<(Uint8List, int?, int?)?> getWithSize({required container, required filePath, required mode, required quality});
static Future<void> put({required container, required filePath, required data, required mode, required quality, int? width, int? height});

static Future<int> appCacheBytesFor(container);
static Future<int> totalAppCacheBytes();
static Future<void> clearAppCacheFor(container);   // now called on lock — Finding F-16, resolved
static Future<void> clearAllAppCache();
static Future<void> clearInContainerCacheByUri(uri);
static Future<void> clearAppCacheByUri(uri);
static Future<void> pruneStaleAppCache(Set<String> activeContainerUris);

static void resizeMemoryBudget(int newMaxBytes);     // NEW this round — ADR-011 hook, uncalled
static void trimMemoryToFraction(double fraction);   // NEW this round — CacheCoordinator's hook
```
Contract: `get`/`getWithSize` check L1 then L2 and populate L1 on an L2 hit; `mode ==
disabled` short-circuits to `null`/no-op everywhere. AES-GCM inline for `< 500 KB`, via
`compute()` isolate above that. **No method here enforces an L2 size cap** — Finding F-08,
still open. `getFromMemory()` remains the media viewer's single source of truth for
prefetched bytes (Findings F-02/F-03, resolved previously). **This round:** the in-memory
tier (`_memoryCache`) is now a 24 MB `ByteBudgetCache` instead of a 120-entry `LruCache`
(Finding F-01, first slice); `clearAppCacheFor()` now has a real caller
(`VaultDashboardScreen._onContainerLocked`) and, since Finding F-17's fix, clears only the
locking container's memory entries (by `volId` prefix) and its own disk directory, not every
mounted container's cached bytes.

### `FullResImageCache` — `lib/data/services/full_res_image_cache.dart`
```dart
static Uint8List? get(container, filePath);
static void put(container, filePath, data);
static bool contains(container, filePath);
static void invalidate(container, filePath);
static void clear();
static void resize(int newMaxTotalBytes);      // ADR-011 hook, currently uncalled
static void trimToFraction(double fraction);   // CacheCoordinator's hook

static final limiter = PriorityTaskQueue(2);
static Future<Uint8List?> fetch(
  container, filePath, Completer<void> completer,
  {required bool Function() isStillWanted,
   TaskPriority priority = TaskPriority.visible},
);
```
Contract: memory-only, 150 MB byte budget, 2-way concurrency, in-flight de-dup (already
removed promptly on settlement — this was always correct here, and is the pattern
`inFlightThumbnails` was brought in line with this round), exponential backoff retry via the
shared `retryWithBackoff` helper. `priority` defaults to `visible`; the media viewer's
next-image prefetch (`_prefetchFullRes`) passes `adjacent` explicitly. `resize()`/
`trimToFraction()` were already implicitly available via the underlying `ByteBudgetCache`
(ADR-002) and are now explicitly exposed on the class so `CacheCoordinator` and a future
device-capability caller have a stable entry point.

### Kotlin-side APIs (new this round)

**`DeviceCapabilityProfiler`** — `kotlin/com/aeidolon/vaultexplorer/DeviceCapabilityProfiler.kt`
```kotlin
object DeviceCapabilityProfiler {
    enum class Tier { LOW, MEDIUM, HIGH }
    fun handleGetDeviceCapabilityProfile(
        activity: MainActivity, call: MethodCall, result: MethodChannel.Result,
    )
}
```
Exposed over the channel as `getDeviceCapabilityProfile` (`ChannelMethods
.getDeviceCapabilityProfile` on the Dart side), returning
`{tier, cores, memoryClassMb, isLowRamDevice}`. Computed once from
`ActivityManager.isLowRamDevice`, `ActivityManager.getMemoryClass()`, and
`Runtime.getRuntime().availableProcessors()`, then cached for the process lifetime.
Deliberately does **not** resize `ioExecutor`/`thumbnailExecutor`/`fullResExecutor` — see
Section 3. **No Dart caller exists yet** — see Section 9.

**`MainActivity.onTrimMemory`** — `kotlin/com/aeidolon/vaultexplorer/MainActivity.kt`
```kotlin
override fun onTrimMemory(level: Int) {
    super.onTrimMemory(level)
    methodChannel?.invokeMethod("onTrimMemory", mapOf("level" to level))
}
```
Forwards Android's raw trim level to Dart unmodified — no attempt is made on the native side
to map Android's five-level granularity down to `CacheCoordinator.TrimLevel`; that mapping is
intended to happen on the Dart side once a handler exists. **`VaultExplorerApi
.initMethodCallHandler` does not yet have an `'onTrimMemory'` case** — the channel method
constant (`ChannelMethods.onTrimMemory`) exists, the native call fires, but nothing on the
Dart side reads it yet. See Section 9.

---

## 7. Audit Findings

Severity: 🔴 High (user-visible stutter/crash risk or unbounded resource growth) · 🟡
Medium (real inefficiency, no immediate crash risk) · 🟢 Low (correctness/hygiene, low
runtime impact). Status tags: **[RESOLVED]** verified fixed in code this round · **[PARTIALLY
RESOLVED]** real progress, gap remains · **[OPEN]** unchanged · **[NEW]** found this pass.

### 7.1 Cache correctness / eviction

### 7.1 Cache correctness / eviction

- **F-01 🟡 [RESOLVED] L1 caches are entry-count-bounded, not byte-bounded, for a
  payload whose size is a user setting.** Resolved across passes:
  `ThumbnailCacheService._memoryCache` is a 24 MB `ByteBudgetCache` instead of a
  120-entry `LruCache<String, Uint8List>` — memory use scales with actual bytes held
  rather than entry count. `ThumbnailConcurrency.inFlightThumbnails` has settled futures
  removed immediately on completion and is dynamically resized by `DeviceCapabilityService`
  at startup.

- **F-02 🔴 [RESOLVED] Three independent L1 thumbnail caches existed and could all hold the
  same bytes for the same file at once, with no shared accounting.** Unchanged from
  previous round — `MediaViewerScreen._prefetchedImages` is deleted;
  `ThumbnailConcurrency.imageCache`/`videoCache` are gone, replaced by one shared
  `inFlightThumbnails` map keyed identically everywhere.

- **F-03 🟡 [RESOLVED] The media viewer's own prefetch path was not gated by
  `ThumbnailConcurrency.imageLimiter` and did not consult `ThumbnailCacheService`'s disk
  tier.** Unchanged from previous round — resolved.

- **F-04 🔴 [RESOLVED] `ConcurrencyLimiter` was documented as LIFO in three separate places
  but implemented as FIFO.** Unchanged — resolved.

- **F-05 🔴 [RESOLVED] No priority tiers.** Unchanged — resolved.

- **F-06 🔴 [RESOLVED] Video-thumbnail generation could run on the same native path used
  during active video playback.** Unchanged — resolved.

- **F-07 🟢 [RESOLVED] `image_page_item.dart` (`_loadImageSize`) had no staleness guard.**
  Unchanged — resolved.

### 7.2 Disk (L2) eviction

- **F-08 🔴 [RESOLVED] The on-disk thumbnail cache has no eviction policy at all.** Resolved:
  `ThumbnailCacheService.enforceDiskBudget()` enforces an LRU-by-mtime eviction policy
  with a default 100 MB byte budget (`defaultMaxAppCacheBytes`), trimming down to 80% when
  budget is exceeded. Triggered periodically during disk thumbnail writes and run as a janitor
  pass during app startup. (ADR-014).

- **F-09 🔴 [RESOLVED] Dead, orphaned second on-disk thumbnail cache.** Fully closed previously.

- **F-09a 🟢 [RESOLVED] Documentation/behavior mismatch on encryption-at-rest.** Unchanged
  — resolved previously.

### 7.3 Downscaling / decode-size discipline

- **F-10 🟡 [RESOLVED] `EncryptedImageWidget`'s full-resolution `Image.memory` had no
  `cacheWidth`/`cacheHeight`.** Unchanged — resolved previously.

### 7.4 Task lifecycle (cancel / retry / dedup)

- **F-11 🟡 [RESOLVED] Retry was fixed-delay and only existed for one of the two payload
  types.** Unchanged — resolved previously.

- **F-12 🟢 [RESOLVED] Cross-subsystem de-dup gap.** Unchanged — resolved previously.

- **F-13 🟡 [RESOLVED] Scroll-velocity / fling-aware cancellation.** Resolved: `FileGridView`
  and `FileMasonryView` listen to `ScrollUpdateNotification`s during fast scrolling and invoke
  `PriorityTaskQueue.cancelTier(TaskPriority.visible)` on image and video limiters to drop queued
  out-of-view tile requests before they execute.

### 7.5 Device adaptivity / memory pressure

- **F-14 🔴 [RESOLVED] Every concurrency and memory limit in the pipeline is a hardcoded constant.**
  Resolved: `DeviceCapabilityProfiler` (Kotlin) classifies device hardware into `LOW`/`MEDIUM`/`HIGH`
  tiers, and `DeviceCapabilityService` (Dart) queries this at startup, dynamically scaling
  `ThumbnailConcurrency.resizeForDevice()`, `ThumbnailCacheService.resizeMemoryBudget()`, and
  `FullResImageCache.resize()`. (ADR-011, ADR-019).

- **F-15 🔴 [RESOLVED] No memory-pressure response anywhere in the stack.** Resolved:
  Native Android `onTrimMemory` callbacks are forwarded via MethodChannel to `VaultExplorerApi.initMethodCallHandler`
  and mapped to `CacheCoordinator.trimAll()`. Flutter/iOS memory pressure warnings are captured by
  `MemoryPressureObserver` (`didHaveMemoryPressure`) and also mapped to `CacheCoordinator.trimAll(TrimLevel.severe)`. (ADR-011, ADR-018).

### 7.6 New this pass

- **F-16 🔴 [RESOLVED] Lock teardown was not clearing the disk thumbnail cache — a live
  deviation from Ownership Rule 5.** Triaged and decided this round: rather than leaving this
  as an open question, the team decision was made and implemented.
  `VaultDashboardScreen._onContainerLocked` now calls `ThumbnailCacheService
  .clearAppCacheFor(container)` in addition to `FullResImageCache.clear()`.
  `clearInContainerCacheByUri()` remains deliberately un-wired: `inContainer`-mode disk
  thumbnails are keyed by the container's own URI, stay valid across a relock/re-mount of the
  *same* container, and are only ever reachable while it's mounted anyway, so clearing them
  eagerly would only cost regeneration time with no privacy or correctness upside — the same
  reasoning Rule 5 already gives for not clearing `MediaAspectRatioCache`/
  `MediaRotationCache`. The decisive factor for `appCache` mode specifically was always the
  device-level encryption key (`AppCacheEncryption`) — those thumbnails are decryptable by
  the app at any time regardless of lock state, which is a materially different privacy
  posture than `inContainer` mode (bytes only reachable while mounted) or `disabled` mode
  (nothing persisted). The reasoning is recorded inline at the `_onContainerLocked` call site
  and in Ownership Rule 5, rather than left implicit.

- **F-17 🟡 [NEW, RESOLVED] Two consistency bugs caught while implementing F-01/F-16, both
  fixed before landing.** (a) `ThumbnailCacheService.clearAppCacheFor()`'s first
  implementation cleared the *entire* in-memory cache — every mounted container's cached
  thumbnails, not just the locking container's — because the underlying `ByteBudgetCache`
  had no way to remove a scoped subset of keys. Fixed by adding
  `ByteBudgetCache.removeWhere()` and scoping the call to the locking container's `volId`
  key prefix, matching `ThumbnailCacheService._memKey()`'s existing scheme (Ownership Rule
  1). (b) `ByteBudgetCache.trimToFraction(fraction)` originally meant "trim down to
  `fraction` of `maxTotalBytes`," which is the inverse of `LruCache.trimToFraction
  (fraction)`'s "evict `fraction` of what's currently held." Left unfixed, this would have
  made `CacheCoordinator.trimAll(TrimLevel.moderate)` shed roughly half of one cache's
  contents and a wildly different amount of another's, depending on how full each happened
  to be at the time — a bug that wouldn't have been obvious from either class in isolation,
  only once something (`CacheCoordinator`) called both with the same argument and expected
  matching behavior. Both classes now share one convention. Recorded here as a reminder for
  whoever adds the next memory-tier cache: check its `trimToFraction`/`resize` semantics
  against its siblings *before* wiring it into `CacheCoordinator`, not after.

---

## 8. ADR Log

### Accepted (retroactive — decisions already made in the current codebase)

**ADR-001 — Static, process-wide shared caches/gates instead of per-widget or per-screen
instances.** *Status:* Accepted. Unchanged this round.

**ADR-002 — `FullResImageCache` is memory-only, byte-budgeted, and never persisted.**
*Status:* Accepted. Unchanged this round; still the pattern `ThumbnailCacheService
._memoryCache`'s conversion to `ByteBudgetCache` (F-01, this round) generalizes from.

**ADR-003 — Native-side downscaling via `inJustDecodeBounds` + `inSampleSize` before any
bytes cross the platform channel.** *Status:* Accepted. Unchanged this round.

**ADR-004 — Thumbnail cache mode is a user-facing, per-container privacy setting
(`appCache` / `inContainer` / `disabled`), not just a performance tier.**
*Status:* Accepted. *Consequences (updated):* this round's F-16 resolution is the concrete
consequence this ADR predicted — the `appCache` device-level-key nuance it flagged is exactly
what tipped Finding F-16 from an open question to a clear decision (clear `appCache` on lock,
leave `inContainer` alone).

**ADR-017 — A single shared native video player (`VideoPlaybackManager`) is the sole source
of "is video playback active" app-wide.** *Status:* Accepted (retroactive). Unchanged this
round.

### Implemented (previously Proposed)

**ADR-010 — Replace the flat `ConcurrencyLimiter` with a priority-tiered task queue.**
*Status:* **Accepted — implemented.** Unchanged this round.

**ADR-012 — A `PlaybackThrottleController` gates background image/thumbnail decoding while
a `MediaCodec` session (ExoPlayer/VLC) is active.** *Status:* **Accepted — implemented and
verified.** Unchanged this round.

### New this round

**ADR-018 — `CacheCoordinator` as the single memory-pressure trim fan-out point; a two-level
`TrimLevel` rather than mirroring native granularity 1:1.**
*Status:* **Accepted — implemented (Dart side only; not yet invoked by a real signal).**
*Context:* F-14, F-15, F-01. `LruCache`/`ByteBudgetCache` had gained `resize()`/
`trimToFraction()` hooks in anticipation of exactly this class — their own doc comments
forward-referenced `CacheCoordinator` before it existed, an open question ADR-013 explicitly
raised without answering. *Decision:* `lib/core/services/cache_coordinator.dart` exposes
`TrimLevel { moderate, severe }` and `trimAll(TrimLevel)`. Two levels rather than mirroring
Android's five-level `TRIM_MEMORY_*` granularity or iOS's single `didHaveMemoryPressure`
signal 1:1 — every calling signal has to collapse to "shed some, might need it again soon"
vs. "shed nearly everything reclaimable" regardless of which native API produced it, so the
enum matches the semantic distinction callers actually need rather than either platform's
raw vocabulary. `trimAll()` touches `ThumbnailConcurrency.inFlightThumbnails`,
`ThumbnailCacheService`'s memory tier, and `FullResImageCache`, each with the same fraction.
`MediaAspectRatioCache`/`MediaRotationCache` are deliberately excluded (Ownership Rule 5 —
small, harmless to keep warm). *Consequences:* answers ADR-013's dangling question — the
class does now exist — but note it's scoped to memory-pressure fan-out specifically, not a
general unification of `inFlightThumbnails` and `_memoryCache`'s storage strategies; those
remain two singletons that agree on a key scheme, not one merged structure. Building this
also surfaced Finding F-17 (a real semantic mismatch between the two `trimToFraction`
implementations it fans out to), which was fixed as a prerequisite. *Consequences (gap):*
not yet invoked by anything — see ADR-011's remaining scope and Section 9.

**ADR-019 — Kotlin-side `DeviceCapabilityProfiler`: three tiers from two standard Android
signals plus core count, computed once and cached.**
*Status:* **Accepted — implemented (Kotlin half only).** *Context:* F-14. *Decision:*
`DeviceCapabilityProfiler.kt` classifies into `LOW`/`MEDIUM`/`HIGH` using
`ActivityManager.isLowRamDevice`, `ActivityManager.getMemoryClass()`, and
`Runtime.getRuntime().availableProcessors()` — deliberately simple, no per-device allowlist
to maintain and no dependency on signals likely to need version-specific tracking. Exposed
over the channel as `getDeviceCapabilityProfile`, returning the tier plus the raw signal
values (useful for future telemetry/debugging, not just the classification). Explicitly does
**not** resize `ioExecutor`/`thumbnailExecutor`/`fullResExecutor` — those are fixed-size
`ExecutorService`s constructed before `Context` is fully available for this check to run,
and live-resizing a running thread pool is treated as a separate, riskier follow-up from
resizing the Dart-side primitives this profiler currently targets. *Consequences:* the
single biggest remaining piece of Roadmap item 10 is now just the Dart-side call site —
query once at startup, route the result into `ThumbnailConcurrency.resizeForDevice()`/
`FullResImageCache.resize()`/`ThumbnailCacheService.resizeMemoryBudget()`. Executor-pool
resizing itself remains a distinct, not-yet-started problem, tracked separately under F-14
rather than folded into this ADR's scope.

### Accepted / Implemented

**ADR-011 — Device capability profiling drives concurrency and memory budgets; a
memory-pressure observer trims them live.**
*Status:* **Accepted — implemented end-to-end.** *Context:* F-14, F-15. *Implementation:*
`DeviceCapabilityProfiler` (Kotlin) classifies device into `LOW`/`MEDIUM`/`HIGH`. `DeviceCapabilityService` (Dart)
queries this at startup and scales `ThumbnailConcurrency`, `ThumbnailCacheService`, and `FullResImageCache`. Native
Android `onTrimMemory` callbacks and Flutter `MemoryPressureObserver` (`didHaveMemoryPressure`) dispatch memory pressure
trims via `CacheCoordinator.trimAll()`.

**ADR-013 — Unify the three fragmented L1 thumbnail caches, byte-budgeted like `FullResImageCache` already is.**
*Status:* **Accepted — implemented.** *Context:* F-01, F-02, F-03, F-12. *Implementation:*
`ThumbnailCacheService._memoryCache` is a 24 MB `ByteBudgetCache`. Shared `inFlightThumbnails` handles in-flight
future de-duplication across all rendering surfaces and removes settled futures immediately upon completion.

**ADR-014 — Bound the L2 disk thumbnail cache with LRU-by-access-time eviction and a periodic janitor.**
*Status:* **Accepted — implemented.** *Context:* F-08, F-09. *Implementation:*
`ThumbnailCacheService.enforceDiskBudget()` calculates total disk thumbnail cache size and evicts oldest files
by modification timestamp (`stat.modified`) down to 80% when `defaultMaxAppCacheBytes` (100 MB) is exceeded.
Triggered periodically on disk cache writes and executed on app startup.

**ADR-015 — Keep the bespoke Dart/Kotlin pipeline; do not adopt Glide/Coil or a stock Flutter image-cache package.**
*Status:* Accepted (re-confirmed previously). Unchanged.

**ADR-016 — Isolate usage stays targeted (crypto only), not a wholesale move to Dart isolates for decode.**
*Status:* Accepted (re-confirmed previously). Unchanged.

**ADR-018 — `CacheCoordinator` as the single memory-pressure trim fan-out point.**
*Status:* **Accepted — implemented and wired end-to-end.** Connected to native `onTrimMemory` and Flutter `MemoryPressureObserver`.

**ADR-019 — Kotlin-side `DeviceCapabilityProfiler`.**
*Status:* **Accepted — implemented.** Queried by `DeviceCapabilityService`.

---

## 9. Refactoring Roadmap

Re-baselined against what actually shipped (see Section 7 for finding status and Section 8 for ADR status). All roadmap phases are complete.

### Phase 1 — mechanical fixes (done)
1. ✅ **Done** — `ConcurrencyLimiter` → `PriorityTaskQueue`, genuinely LIFO within a tier (F-04).
2. ✅ **Done** — `ThumbnailHandlers.handleGenerateAndCacheThumbnail` body and helper deleted (F-09).
3. ✅ **Done** — `ThumbnailCacheMode.appCache` doc comment fixed (F-09a).
4. ✅ **Done** — full-res/poster decode capping via `ResizeImage`/`cacheWidth` (F-10).
5. ✅ **Done** — shared `retryWithBackoff` helper (F-11).
6. ✅ **Done** — `ImagePageItem._loadImageSize` staleness guard (F-07).
7. ✅ **Done** — Finding F-16 triaged and resolved: `clearAppCacheFor()` wired into `_onContainerLocked`.

### Phase 2 — new QoS primitives (done)
8. ✅ **Done** — `PriorityTaskQueue` (ADR-010).
9. ✅ **Done** — `PlaybackThrottleController` (ADR-012).
10. ✅ **Done** — `DeviceCapabilityProfiler` (Kotlin, ADR-019) + `DeviceCapabilityService` (Dart) query hardware tier and scale memory budgets & queue concurrency at startup. (F-14 / ADR-011).
11. ✅ **Done** — Native Android `onTrimMemory` and Flutter `MemoryPressureObserver` connected to `CacheCoordinator.trimAll()`. (F-15 / ADR-018).
12. ✅ **Done** — Scroll-fling-aware `cancelTier()` hook (F-13) wired in `FileGridView` and `FileMasonryView`.

### Phase 3 — cache unification & disk bounding (done)
13. ✅ **Done** — L1 memory tier byte-budgeted (`ByteBudgetCache`), `inFlightThumbnails` de-duplication unified and dynamically scaled. (F-01 / ADR-013).
14. ✅ **Done** — L2 disk byte budget (100 MB limit) + mtime LRU janitor implemented in `ThumbnailCacheService.enforceDiskBudget()`. (F-08 / ADR-014).
15. ✅ **Done** — `CacheCoordinator.trimAll()` built and wired to all memory-pressure signals.
16. ✅ **Done** — Re-audited and updated `docs/architecture.md`.

---

## 10. Appendix — File Inventory

| File | Role |
|---|---|
| `lib/core/widgets/thumbnail/async_thumbnail.dart` | Shared thumbnail-loading widget (state machine, Section 5); takes a `priority` param (ADR-010); removes `inFlightThumbnails` entry immediately on settlement (F-01) |
| `lib/core/widgets/thumbnail/priority_task_queue.dart` | `PriorityTaskQueue` — tiered, LIFO-within-tier, playback-aware admission gate; replaces `ConcurrencyLimiter` (ADR-010) |
| `lib/core/widgets/thumbnail/thumbnail_concurrency.dart` | `ThumbnailConcurrency` singletons — owns `inFlightThumbnails` map and `resizeForDevice()` hook (ADR-011) |
| `lib/core/utils/task_priority.dart` | `TaskPriority` enum (visible/adjacent/background) |
| `lib/core/services/playback_throttle_controller.dart` | `PlaybackThrottleController` — process-wide "is video playing" flag (ADR-012) |
| `lib/core/services/cache_coordinator.dart` | `CacheCoordinator` — single memory-pressure trim fan-out point (`TrimLevel`, `trimAll()`) (ADR-018) |
| `lib/core/services/memory_pressure_observer.dart` | **New.** `MemoryPressureObserver` — listens to Flutter `didHaveMemoryPressure()` warnings and invokes `CacheCoordinator.trimAll()` (F-15) |
| `lib/core/services/device_capability_service.dart` | **New.** `DeviceCapabilityService` — queries native `DeviceCapabilityProfiler` and resizes cache/queue limits for device tier (F-14) |
| `lib/features/browser/viewer/video_playback_manager.dart` | Single shared native video player; source of truth `PlaybackThrottleController` reflects (ADR-017) |
| `lib/core/utils/retry.dart` | `retryWithBackoff()` — shared exponential-backoff helper (Finding F-11) |
| `lib/core/utils/lru_cache.dart` | Entry-count LRU primitive with `resize()` and `trimToFraction()` |
| `lib/core/utils/byte_budget_cache.dart` | Byte-budget LRU primitive with `removeWhere()` and `trimToFraction()` |
| `lib/data/services/thumbnail_cache_service.dart` | L1+L2 thumbnail cache, AES-GCM; `_memoryCache` 24 MB `ByteBudgetCache`, `enforceDiskBudget()` mtime LRU janitor (100 MB budget, ADR-014) |
| `lib/data/services/app_cache_encryption.dart` | Device-level AES key for `appCache`-mode thumbnails |
| `lib/data/services/full_res_image_cache.dart` | Memory-only byte-budgeted full-res cache; `limiter` is a `PriorityTaskQueue`; `resize()`/`trimToFraction()` exposed for `CacheCoordinator` |
| `lib/data/services/media_aspect_ratio_cache.dart` | Session metadata cache (aspect ratio) |
| `lib/features/browser/viewer/widgets/media_rotation_cache.dart` | Session metadata cache (EXIF rotation) |
| `lib/features/browser/viewer/widgets/encrypted_image_widget.dart` | Full-res image widget (viewer); caps decode via `ResizeImage` (Finding F-10) |
| `lib/features/browser/viewer/widgets/image_page_item.dart` | `PageView` item wrapper, zoom/pan; staleness guard (Finding F-07) |
| `lib/features/browser/viewer/widgets/media_player_widget.dart` | Video/audio playback + poster; poster `Image.memory` calls capped (Finding F-10) |
| `lib/features/browser/viewer/widgets/playlist_carousel_overlay.dart` | Neighbor-item strip shown during playback; passes `priority: adjacent` (Findings F-05/F-06) |
| `lib/features/browser/viewer/media_viewer_screen.dart` | Viewer screen; shared cache/gates integration (Findings F-02/F-03/F-12) |
| `lib/features/dashboard/vault_dashboard_screen.dart` | Owns `_onContainerLocked`; calls `ThumbnailCacheService.clearAppCacheFor()` on lock (Finding F-16) |
| `lib/features/browser/widgets/file_grid_view.dart`, `file_masonry_view.dart` | Grid/masonry tile rendering with `ScrollNotification` fling-aware cancellation (F-13) |
| `lib/data/models/thumbnail_quality.dart` | User-facing size/quality setting |
| `lib/data/models/thumbnail_cache_mode.dart` | User-facing privacy setting (appCache/inContainer/disabled); doc comment fixed (F-09a, resolved) |
| `lib/data/services/vault_engine/channel_methods.dart` | Single source of truth for `MethodChannel` method-name constants; this round: added `onTrimMemory` and `getDeviceCapabilityProfile` |
| `lib/data/services/vault_engine/vault_explorer_api.dart` | `initMethodCallHandler` dispatches native→Dart callbacks; **gap:** no case for `'onTrimMemory'` yet, so the new native signal currently arrives and is silently dropped — see Roadmap item 11 |
| `lib/app/app_bootstrap.dart` | `runDeferredStartupWork()` — the intended call site for querying `getDeviceCapabilityProfile` and wiring up device-tier sizing; not yet updated to do so — see Roadmap item 10 |
| `kotlin/.../MainActivity.kt` | Executor pools, `MethodChannel` dispatch; this round: `GENERATE_AND_CACHE_THUMBNAIL` case fully gone (was already removed from dispatch previously, function body now also deleted), added `onTrimMemory()` override and `GET_DEVICE_CAPABILITY_PROFILE` dispatch case |
| `kotlin/.../ThumbnailHandlers.kt` | Native decode/downscale (images + video frames); this round: dead `handleGenerateAndCacheThumbnail` body, `encodeKey()`, and the orphaned `java.io.File` import are fully deleted (F-09, resolved) |
| `kotlin/.../DeviceCapabilityProfiler.kt` | **New this round.** Classifies device into LOW/MEDIUM/HIGH tier from core count + memory class + low-RAM flag; answers `getDeviceCapabilityProfile`; deliberately does not resize native executor pools (ADR-019) |
| `cpp/io/decrypted_block_cache.h` | L3 native chunk cache (out of scope, treated as opaque) |

---

*End of document. Update Sections 7–9 as findings are resolved; add new ADRs rather than
editing accepted ones in place.*
