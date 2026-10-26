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
| **Block-device containers** | VeraCrypt, LUKS1, LUKS2, BitLocker (+ VHD/VHDX wrapping), Composite | C++ `VolumeState` slot array, driven through the `NativeEngine` JNI shim |
| **Directory-based vaults** | Cryptomator, gocryptfs, CryFS | Pure-Kotlin `VaultBackend` session objects in `VaultBackendRegistry` |

**Composite** (`containers/container_create_composite.*`, `containers/composite_block_device.*`,
`jni/composite_bridge.cpp`) is not a third family -- it is a VeraCrypt-format
volume (same cipher/hash/filesystem choices as VeraCrypt above) whose blocks
live across several ordinary carrier files instead of one file/device. A
`CompositeBlockDevice` (`pread`/`pwrite` over a list of `CarrierExtent`s, one
per carrier fd) sits in front of the same `VolumeState` slot used by every
other block-device format, so it is unified by `volId` the same way. Carrier
data is appended past each file's real content as a high-entropy "blind
trailer" (`carrier_profiler.cpp`'s `probeBlindTrailer`), not a distinct
header signature, so a composite carrier is not identifiable as such by
format inspection alone -- every carrier must be supplied together to
reassemble and unlock the volume.

Both families are unified above the crypto layer by **`volId`** (an `Int`,
`0..7`): every caller — Dart, `ContainerFileSystem`, the SAF
`ContainerDocumentsProvider`, the automation `BroadcastReceiver` (§5.4) —
addresses an unlocked volume by its `volId` and never needs to know which
of the two families is actually serving it. That unification point is
`ContainerEngine` (§3.3).

A third, independent native subsystem — the **archive engine**
(`archive/archive_engine.cpp`, native libarchive) — sits outside this
`volId` session model entirely. (libarchive is fetched at a pinned commit and patched at configure time by
`archive/patches/libarchive-7zip-encryption.patch`: upstream's 7-Zip writer
ignores a passphrase and writes an unprotected archive, and its reader refuses
encrypted streams, so the patch adds 7zAES — AES-256-CBC, key derived like
7-Zip's — to both creation and reading. Creation can optionally encrypt the
archive header too (`7zip:header-encryption=1`, 7-Zip's "encrypt file names",
which the archive dialog offers for 7z with a password); reading handles
encrypted headers and AES+codec+filter chains. `archive/test/archive_engine_test.cpp` fails if the
patch is missing.) Its only point of contact with "how do I
get bytes for this archive" is `ArchiveStreamSource`, a small pread-style
struct (`read(offset, dest, length)` + `size()`) with no JNI/Dart type in
sight — `jni/archive_bridge.cpp` is the only place that wraps a real
source in one, either a vault's `fsReadStream(volId, ...)` for an archive
inside an unlocked container or a plain fd for one on real device storage.
Because the engine only ever sees that struct, the same code path serves
"browse a ZIP inside a vault" and "browse a ZIP on the SD card" (Mask
Mode, §6) without knowing which case it's in. See §5.1 for its API
surface.

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

The media viewer's player has a 10-band graphic equalizer (31 Hz–16 kHz,
±12 dB per band, plus a preamp and a clipping guard) that applies to both
video and audio. It is a software `AudioProcessor`
(`AudioEqualizerProcessor`, filter maths in `EqualizerDsp.kt`) inside
ExoPlayer's `DefaultAudioSink`, not Android's `android.media.audiofx.Equalizer`:
the platform effect's band layout differs between devices (and some audio
stacks ignore it), whereas this one sounds the same everywhere and also covers
FFmpeg-decoded audio, because every audio renderer shares the one sink
(`HighPerformanceRenderersFactory.buildAudioSink`). Float output is kept off
there on purpose — `DefaultAudioSink` skips custom processors on its float
path. The settings are global (`MediaViewerToolbarConfig.equalizer`), sent as an
`equalizer` argument to the player channel's `initialize` and live through
`setEqualizer`; the player defaults to *off* on every `initialize`, so the
video/audio editors never apply it. The band layout is declared in both Dart
(`kEqualizerBandFrequenciesHz`) and Kotlin (`EqualizerDsp.BAND_FREQUENCIES_HZ`);
`audio_equalizer_settings_test.dart` fails if the two drift apart.

### 1.3 Feature areas outside the vault core

These sit on top of the engine rather than inside it: each is a Flutter
feature folder that talks to the same `MethodChannel` through a
`core/api` slice, and none of them holds key material or session state of
its own (§2).

**Item Vault (`lib/features/vault_item`).** A built-in password manager.
`VaultItemsService` reads and writes one JSON-encoded `VaultItem` per file
inside a mounted container, so the container's own encryption is the only
protection and the decrypted item exists in memory only while it is viewed
or edited. The item's type is the file extension (`password`, `paymentCard`,
`identity`, `secureNote`, `bankAccount`, `softwareLicense`, `authenticator`);
`isVaultItemFileName` in `file_browser_predicates.dart` is the check, and
`authenticator_registry_controller.dart` and `password_interchange_service.dart`
each keep a deliberate small copy of it rather than importing across features.

**Authenticator (`lib/features/authenticator`).** An AppBar button
(`AppBarAuthenticatorButton`, shown on the dashboard) opens a screen listing
every TOTP-capable Item Vault entry across all currently mounted vaults.
`AuthenticatorRegistry` scans each mounted vault and publishes results
incrementally, so a small vault's codes appear before a large vault finishes;
it also tracks which vaults are mid-scan so the UI can show per-vault loading
state. An entry's identity is its volume slot plus its path, so it does not
survive a lock/unlock cycle (slots are reused). The registry rescans one vault
when an item in it is saved or deleted (`refreshContainer`) and all vaults on
`refreshAll`. Codes come from `TotpEngine` (`core/utils/totp_engine.dart`):
RFC 6238 TOTP, RFC 4226 HOTP (the counter is stored on the item as
`hotp_counter` and only advances when the person asks for a new code, via
`AuthenticatorRegistry.advanceHotpCounter`) and Steam Guard, with SHA-1,
SHA-256 or SHA-512. The HMAC is computed natively through
`VaultCryptoApi.hmac`; no third-party Dart hashing is involved. Importing
from other apps goes through the codecs in
`lib/data/services/password_interchange/` (Aegis, andOTP, 2FAS, Raivo, LastPass
Authenticator, Ente Auth, Google Authenticator migration, `otpauth://` lists,
plus Bitwarden, Proton, KDBX and CSV), registered in
`PasswordFormatRegistry`. The encrypted backup formats share the helpers in
`authenticator_backup_crypto.dart`, which call the native crypto API on the
engine channel; `openAesCbc` validates key size, IV length and block alignment
itself before calling native code, because the native handler reports a bad
padding block (a wrong password) and a malformed input as the same error.

**Video editor (`lib/features/video_editor`).** Lossless trim, cut and merge:
the selected segments are stream-copied, not re-encoded. Dart side:
`VaultVideoEditApi` (`videoEditProbe`, `videoEditExport`, `cancelVideoEdit`);
native side: `VideoEditHandlers` is the channel plumbing and
`LosslessVideoCutter` does the cutting. `videoEditExport` takes the source,
a list of `[startUs, endUs]` segments, a `merge` flag (one output holding every
segment, or one output per segment) and the output paths (container-relative
for a vault, absolute for local storage). The *source* is never copied out: for
a vault it is read through `ContainerMediaDataSource`, decrypting on demand.
The *output* is the exception to "no plaintext temp file": `MediaMuxer` needs a
real seekable file, so each output is muxed into a temp file in the app's
cache directory (prefix `vx_vid_`) and then moved into the vault with
`writeBackFile`. The temp file is zero-filled and deleted as soon as it has
been copied, and again in `finally`; `VaultVideoRecorder.sweepOrphanedTempFiles`
wipes any that a crash or force-stop leaves behind at the next startup. The
archive handlers and the recording pipeline use the same temp-then-wipe
sequence. Local storage (the decoy's plain-folder file manager) is the same
flow with real paths in and out.

**Audio editor (`lib/features/audio_editor`).** The audio sibling of the video
editor, with the same lossless model (segments, keep / cut-out, undo, merge or
separate outputs, replace original) and a waveform timeline instead of a
filmstrip. It reuses the video editor's segment controller (an empty keyframe
list, since any audio frame can start a cut), range math and segments sheet.
Dart side: `VaultAudioEditApi` (`audioEditProbe`, `audioEditWaveform`,
`audioEditExport`, `cancelAudioEdit`, progress via `onAudioEditProgress`);
native side: `AudioEditHandlers` (plumbing, same temp-file / rollback rules as
`VideoEditHandlers`, temp files named `vx_vid_aud_cut_*.mp4` so the same
startup sweep covers them), `LosslessAudioCutter` (cutting) and
`AudioWaveformExtractor` (decodes through `MediaCodec` straight off the
extractor into 0..255 peak buckets, time-boxed to 60 s; `complete` is false if
it ran out). `MediaMuxer` only writes AAC (`.m4a`), Opus (`.ogg`, API 30+, else
WebM) and Vorbis (WebM), so MP3 (concatenated frames) and WAV (PCM re-wrapped
in a new header, cut to the exact sample) have small hand-written writers.
Everything else (FLAC, WMA, AC-3, AMR, PCM in odd containers, ...) can't be
copied, so `AudioReencoder` decodes it with `MediaCodec`, trims to the exact
frame and encodes AAC-LC into an `.m4a` (audio is cheap to re-encode, unlike
video). The probe reports `reencode: true` so the editor says so before
exporting; it reports `cutSupported: false` only when the device has no decoder
for the file or the sample rate can't be encoded (176.4 / 192 kHz), and such a
file can still be played in the editor. Wider than stereo is cut to the front
pair. Tags, cover art and chapters are not carried over. The pure parts (output planning, WAV header, PCM slicing, peak
accumulation) live in `AudioEditMath.kt` so they are unit-tested on the JVM.

**Image editor (`lib/features/image_editor`).** Loads the whole file through
`VaultFileIoApi.readWholeFile`, decodes it in Dart (AVIF frames via the native
`decodeAvifFrame`), keeps edits as an in-memory document with annotations, and
encodes the result natively with `encodeImage`. `SaveImageSheet` offers two
outcomes: write a new file with a validated, de-conflicted name and leave the
original untouched, or replace the original file's bytes; either way the write
goes back into the vault through `writeWholeFile`.

**Document scanner (`lib/features/camera/scan`, `cpp/docscan`).** A third
mode in `CameraCaptureScreen`'s mode toggle (the quick-capture screen opts out
through the `supportsDocumentScan` hook on `CaptureScreenStateMixin`). Two
paths run on the same camera session:

- *Live outline.* `VaultCameraSession.setScanMode(enable, document = true)`
  reuses the analysis `YUV_420_888` reader that QR scanning uses; each Y plane
  goes to `docscan::detectFromGray` (~320 px working size, throttled to ~10 fps)
  and the result is rotated by the sensor orientation into the upright frame
  before a `document_quad` event reaches Dart. The analysis size is chosen to
  match the preview's aspect, so a quad maps 1:1 onto the preview; the overlay
  is drawn in the uncropped preview box and hidden for the front camera (mirrored
  preview).
- *Capture.* The shutter takes the normal full-resolution JPEG and hands it to
  `DocumentScanPlugin` (channel `com.aeidolon.vaultexplorer/docscan`, owned and
  disposed by `VaultCameraPlugin`, one worker thread). `detect` decodes the
  photo upright (EXIF applied) at ~1600 px, runs `detectFromRgba` (including a
  sub-pixel edge-fitting stage) and returns that same upright preview, so the
  corners always line up with the pixels the editor shows. After the user
  adjusts corners, picks a filter and rotation in `DocumentScanEditorScreen`,
  `process` decodes just large enough, warps the quad to a page (aspect ratio
  recovered from the perspective, not guessed from side lengths), applies the
  filter and returns a JPEG. The page then travels as an ordinary
  `CapturedMediaItem` (`isScan`) through the existing tray, review and save.

The native core is dependency-free C++17 (no OpenCV), so the app's
build-from-pinned-source property is unchanged. It generates candidate quads
from thresholded regions, a descending Canny sensitivity ladder and the
interior of edge outlines (after a median filter that removes text and noise
without softening real edges), fits an enclosing quadrilateral to each convex
hull and scores it by area, corner angles and how much of each side lies on a
real perpendicular edge. Frame-border samples are excluded from that score:
the dark padding added around the frame would otherwise make any frame-sized
quad look perfectly supported. Filters (`Color`, `Gray`, `BlackWhite`) divide
by a smooth paper-colour estimate to remove shadows. The JNI surface is five
functions in `jni/docscan_bridge.cpp` plus `nativeDetectDocument`, so the
detector can be replaced without touching Kotlin or Dart.

Saving: with the PDF toggle on (default) all scanned pages of a session become
one `SCAN_<timestamp>.pdf`; otherwise each is a `SCAN_<timestamp>.jpg`. The
PDF writer (`docscan/doc_pdf.cpp`) embeds each JPEG verbatim, reads its size and
channel count from the JPEG header (never from the caller), and writes no
metadata. A page the review screen's editor turned into a PNG is re-encoded as
JPEG in Kotlin and the build retried; a failed PDF keeps every page on screen.

Invariants (§2) hold: pixels move only as byte arrays and direct buffers, no
temp files are created, there is no network access, and the editor, being a
route above the camera screen, hides itself when `cameraCaptureLockProvider`
reports the container locked. Native tests: `docscan/test/doc_scan_test.cpp`
(host-side, in the `if(NOT ANDROID)` list in `CMakeLists.txt`); Dart:
`test/features/camera/scan/scan_geometry_test.dart`.

### 1.4 Android Share Sheet Integration

An opt-in feature that lets other apps share one or more files straight into a
vault via `ACTION_SEND` / `ACTION_SEND_MULTIPLE`. Native side:
`ShareIntentHandlers` (toggling the alias, deciding whether an incoming
intent should be acted on, extracting its metadata) and `VaultShareActivity`
(a dedicated activity in an isolated task window that inherits the Flutter
engine and handlers from `MainActivity`, so `finish()` removes only that
task). `ImportExportHandlers.handlePrepareShareImport` turns the result into
an actual import, reusing the same `pickedFilesByToken` bookkeeping as
`handlePickImportFiles`. Dart side: `lib/features/share_import`. Channel
methods: `setShareTargetEnabled`/`isShareTargetEnabled` (the opt-in),
`checkPendingShareRequest`, `cancelPendingShareRequest`, `returnToSharingApp`
and `prepareShareImport`.

- **No native lock check.** Whether the app is currently asking for a master
  password is a Dart-owned UI-navigation concept (§1.1), so native code never
  tries to observe it. An incoming share waits in `IncomingShareBridge` until
  the screen that is actually on top asks for it (`MainShell.initState`,
  which only runs once `LockGateScreen` has let the person through).
- **Mask Mode routes, it doesn't drop.** While the decoy identity is active,
  metadata goes to `LocalIncomingShareBridge` instead -- a separate buffer
  that only the decoy file manager (`lib/features/decoy/local/decoy_share_import_flow.dart`)
  drains, with plain storage and no auth prompt, so the decoy behaves like a
  genuine file manager receiving a file. Reaching the real vault with a shared
  file while disguised still goes through `HiddenVaultTrigger`.
- **Exactly one share-target alias is enabled at a time.** `ShareTargetAlias`
  (real identity) and `ShareTargetDecoyAlias` (decoy identity) are kept in sync
  with Mask Mode by `DisguiseModeHandlers.syncShareTargetIdentity`, the same
  way the launcher aliases are (§6).

### 1.5 Sharing files and folders out

The outgoing counterpart of §1.4: the Share action in the browser hands files
-- and folders -- from whatever container is open to the app the person
picks. Dart calls `VaultFileIoApi.shareFiles` (vault containers and SAF
trees) or `VaultLocalShareApi.shareLocalFiles` (plain on-disk storage in the
decoy's local explorer); native side builds `ACTION_SEND` /
`ACTION_SEND_MULTIPLE` over URIs from the provider that fits the source.

- **Files** are never copied or staged. Vault files stream through a proxy
  file descriptor onto the live session (`ContainerShareProvider`); SAF files
  go out as their own document URI; plain local files through the
  `FileProvider`.
- **Folders** are shared as one `<name>.zip`, because the share sheet has no
  notion of a directory. `FolderZipWriter` walks the subtree and writes the
  archive into a pipe (`FolderZipPipe`) whose read end the provider returns,
  so the zip is never staged on disk. The folder itself is the archive's
  top-level entry and empty subfolders are kept. Entry type is passed
  explicitly (`directoryPaths`), never inferred from a name. The writer
  reaches storage only through its `Source` interface, one per backend:
  `ContainerFolderSource` (vault, inside `ContainerShareProvider`),
  `RawFolderSource` (plain files) and `SafFolderSource` (SAF trees); the last
  two are served by `StorageFolderShareProvider`.
- **SAF folders are walked by document id, not by path.** The browsing helpers
  in `SafStorageManager` match names case-insensitively and turn a provider
  error into an empty listing -- harmless for browsing, but an archive would
  silently lose a subfolder. `SafFolderSource` addresses every child by the
  exact id its provider reported and throws on any provider failure. The
  root folder's id is resolved by the share action from the listing the
  person just picked it from and travels inside the share URI. A provider
  that says it is still loading is waited on; one that hands out a
  non-seekable descriptor is archived to end of stream
  (`FolderZipWriter.UNKNOWN_SIZE`).
- **Item Vault pseudo-files are left out of a shared vault folder** (Dart
  passes their extensions as `skipExtensions`), matching multi-select share,
  which already refuses to hand them out as loose files. Not applicable to
  SAF or local storage, which never hold them.
- **A failed folder share must look failed.** A truncated listing
  (`System:TRUNCATED`), a read error, an unlistable folder, an unsafe entry
  name or a vault that starts locking throws; the archive is then never
  finalized (no central directory is written, so unzippers reject it) and the
  pipe is closed with an error. Existing export paths flag truncation and
  carry on; a share has no side channel for that flag, so it refuses instead.
- **A vault folder share never blocks locking.** The writer holds a
  `ContainerDocumentIoRegistry` lease, and polls `isLockPending` between
  chunks so auto-lock aborts it rather than waiting for a large archive.
- **Routing in the browser keys on `isRawLocal`, not `isLocalStorage`.** A SAF
  tree is also a negative-`volId` "local" container, but it has no real path
  to hand the local share API; it goes through `shareFiles`' SAF channel.
- The archive's length is unknown up front and the descriptor isn't
  seekable; that is fine for the copy-to-end readers a share sheet targets.
  `StorageFolderShareProvider` is a plain read-only provider with
  `exported=false`; a URI grant matches the exact URI, so a receiver can't
  retarget one.

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

12. **Case-sensitivity is a policy when comparing names and a fact when
    deciding whether a write is safe — and the policy is never more
    permissive than the fact.** `namesAreCaseSensitive()` (in
    `mounted_container_filesystem.dart`) says how conflict detection,
    conflict-plan keys, unique-name generation and the name dialogs compare
    names in a container; it follows `resolveFilesystemType()` and so the
    `kAllowCaseDistinctNamesInExtContainers` switch. `isDestinationCaseSensitive()`
    (Dart) and `FilesystemNameValidator.destinationIsCaseSensitive()` (Kotlin)
    say what the destination filesystem *really* does with "Notes" and "notes":
    true for ext volumes and the encrypted folder-vault formats, false for
    FAT/exFAT/NTFS, device storage, and anything unknown. Every path that
    writes names to a destination guards on the fact, never the policy:
    `FileOperationService._run` / `_copyEntry`, the Kotlin import recursion,
    both export paths, and the archive-extract plan
    (`ArchiveService.caseSafeExtractPlan`) all give a later entry that would
    replace an earlier one on a case-insensitive destination a unique name
    ("notes (1)", the same result as choosing "keep both" on a conflict), so
    a case-distinct name that is legal in the source can never silently
    overwrite a file in the destination and nothing is dropped or refused. The real filesystem of a
    disk-image volume is read from `getVaultInfo()["fileSystem"]` once at mount
    (`VolumeFilesystemRegistry`, filled in `onContainerMounted` /
    `onUsbContainerReconnected`, cleared in `onContainerLocked`); an unrecorded
    volume is treated as unknown, i.e. case-insensitive. Dart decides the
    policy and sends it with each import pick; Kotlin does not re-derive it.

13. **Biometric unlock never outlives the biometrics it was set up with.**
    It is a `local_auth` prompt in front of credentials held in Keystore
    storage whose keys are not tied to the user's biometrics, so Android
    would not invalidate anything when a fingerprint or face is enrolled.
    Every biometric-protected thing (the master lock, each vault) therefore
    owns a *sentinel* Keystore key (`BiometricKeyHandlers`): per-use
    `BIOMETRIC_STRONG` authentication with
    `setInvalidatedByBiometricEnrollment(true)`, used for nothing else.
    `BiometricEnrollmentGuard` checks it before every biometric prompt is
    offered and again before the result is accepted (lock gate, both unlock
    controllers, the vault settings sheet, the master-lock settings
    verification). An invalidated *or missing* sentinel fails closed: the
    master lock goes back to the master password, and a vault goes back to a
    manual password with its saved password, PIM, keyfile list and cached
    derived key removed (`ContainerRepository.revertBiometricsToPassword`).
    A Keystore error refuses that attempt but is not evidence of a change, so
    nothing is switched off. Sentinels are per thing and are only ever
    replaced when the person turns biometrics on again, so re-enabling one
    can never make another, older one look valid. Any new code path that
    releases saved credentials after a biometric prompt must go through the
    guard.

---

## 3. Concurrency & threading model

Four independent locking/executor layers exist, at different granularities,
for different reasons. None of them is redundant with another, but none of
them stands in for the *Kotlin-side* session map either (§2 rule 8).

### 3.1 Executors (Kotlin, `MainActivity` and `VideoThumbnailCoordinator`)

Four fixed-size thread pools, sized per-device by `DeviceCapabilityProfiler`
rather than hardcoded. `DeviceCapabilityProfiler.classify()` computes a
LOW/MEDIUM/HIGH tier once per process
(`ActivityManager.isLowRamDevice`, `memoryClass`, CPU core count) and
`resizeExecutorPools()` applies it via
`ThreadPoolExecutor.setCorePoolSize`/`setMaximumPoolSize`. The same tier
feeds Dart-side cache budgets (`FullResImageCache.resize`,
`ThumbnailCacheService`), so memory and thread budgets scale together off
one signal. `ioExecutor` and `fullResExecutor` are owned by `MainActivity`;
the two thumbnail pools are `VideoThumbnailCoordinator.imageExecutor` and
`.videoExecutor` (`container/VideoThumbnailCoordinator.kt`), which
`MainActivity` only references and resizes. `MainActivity` also holds a
separate fixed 2-thread `pdfExecutor` that is *not* resized by the tier.

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
  (`onUsbContainerDetached` → auto-lock), or one of the automatic policies
  in `SessionLockController`. The automatic policies only apply while
  `lockContainersOnScreenLock` is on (they do **not** depend on a master
  password — that only gates the separate *app lock*, below):
  - **screen off** — locks immediately if `autoLockMins <= 0` or
    `autoLockScreenLockOnly` is set; otherwise arms an `autoLockMins`
    countdown;
  - **resume after backgrounding** — locks if `autoLockMins == 0` or the
    time away reached `autoLockMins`; ignored entirely when
    `autoLockScreenLockOnly` is set (only a real screen-off counts);
  - **foreground inactivity timer** — armed for `autoLockMins` when that is
    positive and `autoLockScreenLockOnly` is off. All of these timers are
    skipped while media is playing, and `isLockSuppressed` (a depth counter)
    suppresses screen-off locking.
  Independent of that app-wide toggle, individual containers can override
  the policy: "Immediately" containers lock on any screen-off or
  background-resume, and "Screen Lock Only" containers
  (`ContainerRecord.autoCloseScreenLockOnly`) lock on a genuine screen-off
  only. There is also a per-container inactivity timer
  (`VaultDashboardController.scheduleAutoClose`).
  The *app lock* (the master-password gate, `performAppLock`) is a separate
  mechanism with its own settings (`lockAppOnScreenLock`,
  `appLockAfterMins`, `appLockScreenLockOnly`) and requires a master
  password. All container-lock paths funnel through the same native
  `lock`/session-removal code (§3.3), so there is one teardown
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

Background playback of vault and local-storage media (audio/video continuing with the app
minimized or the screen off, with a media notification and lock screen
controls) is split three ways. `NativePlayerManager` still owns the single
ExoPlayer; `VaultPlaybackSession` owns the Media3 `MediaSession` wrapped
around it (`VaultSessionPlayer`) and the playback window; and
`VaultMediaPlaybackService` (type `mediaPlayback`) owns only the notification
and the foreground state. It applies to items opened from the media viewer,
whether out of an unlocked vault or from local storage (including Mask Mode's
file manager); the viewer opts in per `initialize` call, and the video editor,
camera review and archive preview are unchanged.

- **Lock coupling.** Vault playback is bound to a `volId`. `ContainerSessionRegistry`
  reports every session removal, so any path in §4.1 that moves that `volId`
  to Locked stops the player and removes the notification. Local-storage items
  have a negative `volId` that never appears in the registry and are not bound
  to any vault, so no lock path ends them. The foreground
  service adds no lock trigger and does not delay one: the existing timers
  and screen-off policy apply as before. The one adjustment is in
  `SessionLockController`: media still playing when the app returns to the
  foreground counts as activity for a *timed* `autoLockMins`, as foreground
  playback already does (not for "Immediately", per-container overrides or
  the app-lock gate).
- **File names stay private by default.** The session publishes a generic
  title (the decoy identity in Mask Mode), playlist position, and never tags
  embedded in the media. The Media Player Controls setting can opt in to
  publishing decrypted file names to the notification and MediaSession
  metadata, which may be shown by lock-screen and connected media controls.
  The notification's public version remains generic. In either mode,
  `VaultSessionPlayer` replaces the player's merged metadata, both as a getter
  and in `onMediaMetadataChanged` events. The generic title says "vault" only
  for vault items; local-storage items get a neutral "Playing media" line.
- **Stop is a standard control.** The notification carries a Stop action
  (Android 12 and below build their controls from it), and the `MediaSession`
  publishes a Stop media button preference bound to `Player.COMMAND_STOP`
  (Android 13+ builds the lock screen / quick settings controls from the
  session and has no built-in Stop slot). It must be a *player* command: with
  no `MediaSessionService` the platform session never learns about custom
  session commands, so Media3 would drop a custom-command Stop button as
  unavailable. Stop (from either surface, or a headset / car stop key) ends
  playback natively and emits a `mediaSessionAction` `stop` event; the viewer
  answers by closing itself, which is its normal exit (position saved, player
  released), so the app never resumes on a dead player. Swiping the paused
  notification away only ends the session (`ACTION_DISMISS`) and leaves the
  viewer open.
- **Foreground state is held explicitly.** The Dart viewer releases and
  recreates the player on every item change, which would drop a Media3-managed
  foreground state and make background auto-advance impossible on Android 12+
  (no foreground-service starts from the background). The service therefore
  stays foreground while playing and for a short linger afterwards, and the
  playback window outlives a released player for a grace period.
- **Previous / Next** are playlist operations owned by Dart: the viewer
  reports availability and position (`setMediaNavigation`) and receives
  presses as a `mediaSessionAction` player event. Changing items rebinds the
  existing MediaSession to the new player so the notification remains open.
- While the activity is stopped the video track is disabled, so only audio is
  decoded; it is re-enabled on `onStart`.

---

## 5. Public API surface

The stable cross-language contract for interactive use is a single
`MethodChannel` (`com.aeidolon.vaultexplorer/engine`); every method name is
a constant in **`ChannelMethods`** (Dart) mirrored by a Kotlin
`ChannelMethods` object inside `MainActivity` — that pairing is the API
contract and both sides must be updated together. The two lists are
exact mirrors except that `onTrimMemory` exists only on the Dart side. Dart
code that calls the engine channel uses the `ChannelMethods` constants rather
than string literals, and the channel's name is spelled out in exactly one
place, `lib/core/api/vault_engine_channel.dart`. Code with a `ref` takes the
channel from `vaultEngineChannelProvider`; the few plain const objects that
can't (`AppSecureStorage`, `ThumbnailCacheService`, `LogcatService`,
`FileOperationService.withEngineEvents`, `authenticator_backup_crypto`) use the
`kVaultEngineChannel` constant. That list is an allow-list enforced in CI by
`scripts/check_code_boundaries.py`, which also rejects raw method-name strings
in engine-channel files and empty `catch` blocks. Automation (§5.4) is a
separate, headless entry point that does not go through this channel, and
Mask Mode (§6.3) has its own dedicated channel.

### 5.1 Dart → native (method calls)

This is organized by group below rather than listed exhaustively —
`ChannelMethods` currently defines 238 constants in Kotlin and 239 in Dart
(the extra one is `onTrimMemory`); the groups below are a guide to them, and
not every constant is spelled out by name.

| Group | Methods |
|---|---|
| Container lifecycle | `pickContainer`, `pickKeyfiles`, `createContainer`, `unlockContainer`, `lockContainer`, `updateContainerSettings`, `cancelUnlock`, `changeContainerPassword`/`changeLuksContainerPassword`, `mountContainerFolder`, `unmountContainerFolder`, `getMountedContainerFolders`, `getActiveContainerSessions`, `hasAllFilesAccess`, `requestAllFilesAccess`, `detectsAsPlainDiskImage` |
| Directory vaults (Cryptomator/gocryptfs/CryFS) | `pick/unlock/create*Vault` × 3 formats, plus `change*VaultPassword`, `isGocryptfsVault`/`isCryfsVault` |
| Composite containers (§1) | `profileCarriers` (scan candidate carrier files and report allocatable space at a given growth %), `createCompositeContainer`, `unlockCompositeContainer` |
| File I/O | `decryptFile`, `exportFileToStorage`, `exportFilesToFolder`, `importFile`, `importFolder`, `pickImportFiles`/`pickImportFolder`, `cancelImport`/`cancelExport`/`cancelPickedImport`, `deleteImportSources`, `getFileSize`, `getFolderSize`, `readFileChunk`, `writeFileChunk`, `beginBatchWrite`/`endBatchWrite`, `beginBatchDelete`/`endBatchDelete`, `finishWrite`, `writeBackFile`, `getSpaceInfo`, `getVaultInfo`, `getMediaFileSize`/`readMediaFileChunk` (routed to `fullResExecutor`) |
| Directory ops | `listDirectory`, `createDirectory`, `renameFile`, `copyFile`/`cancelCopy`/`clearCopyState`, `deleteFile`, `setLastModifiedTime` |
| Media/thumbnails | `openWithApp`, `shareFile`, `get{Image,Video}Thumbnail[WithSize]`, `setPlaybackActive`, `getAvifInfo`/`decodeAvifFrame`, `encodeImage` (image editor, §1.3) |
| Video editor (§1.3) | `videoEditProbe`, `videoEditExport`, `cancelVideoEdit` |
| Audio editor (§1.3) | `audioEditProbe`, `audioEditWaveform`, `audioEditExport`, `cancelAudioEdit` |
| Native PDF viewer (`pdf/`, backs the AndroidX Jetpack platform view, NOTICE.md) | `openPdf`, `getPdfPageSize`, `renderPdfPage`, `closePdf`, `isJetpackPdfViewerSupported`, `register/revokeJetpackPdfSession`, `printPdf` |
| Document viewer (`officeviewer/`, platform view `com.aeidolon.vaultexplorer/office_viewer`) | No main-channel methods. The per-view channel has one call, `loadDocument` (bytes, extension, theme colours, notes label), which converts DOCX/PPTX/XLSX, ODT/ODP/ODS and legacy PPT text to a script-free HTML page in pure Kotlin (own XML reader, no third-party code) and loads it into a WebView that serves only that in-memory page and its images: JS, storage, file access and network off, CSP `default-src 'none'`. Decrypted bytes are read in Dart (`readWholeFile`, so local storage works too), converted off the UI thread, and never written to disk; errors come back as `ENCRYPTED` / `TOO_LARGE` / `UNSUPPORTED` |
| Archive engine (native libarchive, see §1) | `archiveScanVault`/`archiveScanLocal`, `archiveExtractVaultEntry`/`archiveExtractVaultAll`/`archiveExtractLocalEntry`, `archiveCreate`, `archiveStageBrowseEntry`/`archiveDiscardBrowseFile`, plus `pickArchiveFile`/`pickExtractFolder` |
| Header backup & repair ("Check & Repair" tool) | `diagnoseUnmountedContainerFile`, `diagnoseMountedVolumeFilesystem`, `runMountedVolumeFilesystemCheck`, `exportContainerHeader`, `restoreBackupHeaderUnmounted`/`restoreContainerHeaderRegion`, `pickFolderVaultForRepair`, `checkFolderVault`, `repairFolderVault`, `resolveFolderVaultConfigFile`/`restoreFolderVaultConfig` |
| Split & Join | `splitContainer`, `joinContainer`, `cancelSplitJoin`, `unlockSplitContainer` |
| Single-file crypto ("Encrypt/Decrypt Files" tool) | `encryptSingleFile`, `decryptSingleFile`, `pickCryptoFiles` |
| Hash Verifier | `computeExternalFileHash`/`cancelHashCompute`, `hashBytesSha256`/`hashBytesMd5`, `begin/update/finish/discardHashSession`, `readExternalFileBytes`/`writeExternalFileBytes` |
| Crypto | `hashPassword`/`hashPasswordSha256`, `aesGcmEncrypt`/`aesGcmDecrypt`, `aesCbcDecrypt`, `hmac`, `pbkdf2`, `scrypt`, `argon2id`, `xchacha20Poly1305Open` (the primitives the password-interchange codecs, §1.3, build on), `deriveDerivedKey`, `storeDerivedKey`, `loadDerivedKey`, `clearDerivedKey`, `setDerivedKeyExpiry`/`getDerivedKeyExpiry`, `purgeExpiredDerivedKeys` |
| Secure storage | `read/write/deleteSecure`, `deleteAllSecure`, `readAllSecure`, `containsKeySecure` |
| Automation settings (per-vault, gates §5.4) | `get/regenerateAutomationToken`, `getAutomationVaultConfig`, `setAutomationTier`, `set/getAutomationPassword`/`Keyfiles`/`Pim`, `setAutomationCaptureEnabled` |
| Share sheet (§1.4) | `setShareTargetEnabled`/`isShareTargetEnabled`, `checkPendingShareRequest`, `cancelPendingShareRequest`, `returnToSharingApp`, `prepareShareImport` |
| Document providers & SAF storage | `safListDirectory`, `safCheckTreeAccess`, `safGetFileSize`, `safReadFileChunk`/`safWriteFileChunk`, `safCreateFile`/`safCreateDirectory`, `safRenameFile`, `safDeleteFile`, `safCopyFile`, `safGetSpaceInfo`, `safGetThumbnail`, `safOpenWithApp`, `safShareFiles`, `safGetDocumentUri`, `getStorageVolumes`, `getMirrorPushActivity` |
| Panic & quick capture | `getPanicSettings`, `setPanicTier`, `setQuickTileEnabled`, `triggerPanic`, the `*PanicKit*` and `*PanicBootTrigger*` settings calls, `getQuickCaptureSettings`, `setQuickCaptureTileEnabled`, `checkPendingQuickCaptureRequest`, `requestPinQuickCaptureShortcut` |
| Security | `setSecureScreen`, `setDebugLogging`, `setRecentsSnapshotBlocked`, `notifyResumedFramePainted`, `set/clearSensitiveClipboardText` |
| Background service & camera | `syncBackgroundService`, `updateBackgroundServiceProgress`, `start/stopBackgroundRecording` |
| Local/decoy file ops (plain device storage, no vault involved) | `getLocalFileUri`, `openLocalFileWithApp`, `shareLocalFile` |
| USB | `listUsbDevices`, `requestUsbPermission`, `unlockUsbContainer`, `createUsbContainer`, `getUsbDeviceCapacity`, `set/isUsbAttachPromptEnabled` |
| System | `documentExists`, `warmContainer`, `getDeviceCapabilityProfile`, `probeContainerFormat`, `getAppVersion`, `getAndroidSdkInt`, `launchUrl`, `installApk`, `getApkIcon`, `hasOverlayPermission`/`requestOverlayPermission`, `setNotificationLocale`, `exportLogFile` (in-app log viewer), `setKeepScreenOn`, `requestNotificationPermission`, `exportAppSettingsFile`/`importAppSettingsFile` |

### 5.2 Native → Dart (event callbacks)

Via the same channel's method-call handler in reverse — see
`VaultExplorerApi.initMethodCallHandler`:

The handler currently dispatches 25 event names: `onAppSelected`,
`onUsbContainerDetached`, `onScreenOff`, `onUnlockStarted`,
`onUnlockProgress`, `onImportProgress`, `onCameraPermissionResult`,
`onTrimMemory`, `onBackgroundRecordingStopRequested`, `onCopyProgress`,
`onExportItemFinished`, `onExportProgress`, `onHashProgress`,
`onHiddenVolumeProtectionTriggered`, `onImportItemFinished`,
`onIncomingShareRequest`, `onNotificationPermissionResult`,
`onPanicCredentialsPurged`, `onPanicSessionPurged`, `onQuickCaptureRequested`,
`onRepairLog`, `onSplitJoinProgress`, `onStoragePermissionResult`,
`onVaultAutomationUnlocked`, and `onVaultForceLocked`. The first eight each
have a corresponding typed `ListenerRegistry` (or, for `onTrimMemory`, a
direct call into `CacheCoordinator.trimAll`) — see §3.4.
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
| `ACTION_SYNC_VAULT` | FULL | Run every unlock-sync or live-watch rule for an already-unlocked writable vault; uses the foreground automation notification. Successful cold automation unlocks also run these rules before returning the unlock result. |
| `ACTION_LOCK_VAULT` | LIFECYCLE | Lock a vault; stops `VaultKeepAliveService` if no session remains active anywhere. |
| `ACTION_IMPORT_FILE` | FULL | Import a real filesystem path into the vault, with an option to securely wipe the source afterward; batch mode supports include/exclude globs. |
| `ACTION_EXPORT_FILE` | FULL | Export a path from inside the vault to a real filesystem path; batch mode supports include/exclude globs. |
| `ACTION_IMPORT_FOLDER` | FULL | Import every included file under a real folder into the vault (`VaultAutomationFolderOps.importFolder`), optionally recursive with `EXTRA_PATTERN` and `EXTRA_EXCLUDE_PATTERN` globs (`GlobMatcher`). Replies with per-file matched/succeeded/failed/skipped counts, not just one outcome. |
| `ACTION_EXPORT_FOLDER` | FULL | Export a vault folder to a real destination folder, with the same include/exclude glob, recursive, and count-summary shape as `IMPORT_FOLDER`. |
| `ACTION_TAKE_PHOTO` | FULL, **and** the vault's separate camera-capture opt-in (`AutomationSettings.canCapture`/`setAutomationCaptureEnabled`) | Headless photo capture straight into the vault via `VaultAutomationCaptureBridge`. |
| `ACTION_START_RECORDING` / `ACTION_STOP_RECORDING` | FULL + capture opt-in, same as `TAKE_PHOTO` | Headless video capture. Owned end-to-end by `VaultAutomationRecordingService` — a foreground service (type `camera\|microphone`) that *is* the recording, unlike the UI-driven `VaultCameraRecordingService` (§4.4), because a broadcast-triggered capture has no Activity/Flutter engine to own a camera session. Auto-stops after a 3-hour safety cap (finalizing what was captured) if `STOP_RECORDING` never arrives. |
| `ACTION_START_AUDIO_RECORDING` / `ACTION_STOP_AUDIO_RECORDING` | FULL + capture opt-in, same as `TAKE_PHOTO` (audio shares the one switch — video already records the mic under it) | Headless audio-only capture. Runs in the *same* `VaultAutomationRecordingService` as video, selected by `EXTRA_AUDIO_ONLY`, so the single recording slot (`isRecording`) is shared and a start while either kind is running gets `BUSY`; each STOP refuses the other kind via `currentIsAudioOnly` (`NOT_RECORDING`). The service declares only the `microphone` foreground type in this mode (claiming `camera` throws on Android 14+ without the camera permission). Starts through the same invisible `VaultAutomationCaptureActivity` trampoline (the mic has the same while-in-use restriction), which checks only `RECORD_AUDIO`. Records with `VaultAudioRecorder` to a cache temp file; on stop it streams into the vault via `VaultVideoRecorder.streamFileToSinkAndWipe` then calls `ContainerFileSystem.finishWrite` (the commit step directory vaults need), all on the service's own executor. A failed write discards the take. Start failures map through `outcomeForAudioError` (`PERMISSION_DENIED` / `MIC_UNAVAILABLE` / `ERROR`). Same 3-hour safety cap. |
| `ACTION_WIPE_FILE` | *(not vault-gated)* | Securely deletes an arbitrary plaintext path outside any vault — e.g. an `EXPORT_FILE` destination once a script has finished processing it. Still requires a valid API token. |

The camera-capture opt-in is separate from and additional to the FULL tier
itself — unlike file import/export, a photo/recording needs no on-screen
indication at all, so it is off by default even for a vault already fully
opted in to automation, and must be turned on explicitly per vault.

Every action requires the per-install API token (`AutomationSettings`,
§2 rule 11) **and** the target vault opted in to the tier (and, for
capture, the opt-in) that action needs — both are checked before any
vault state is touched, and a bad/missing token gets no reply broadcast at
all, so a probing app can't even learn the feature is configured. Every
successful or failed action replies on `ACTION_AUTOMATION_RESULT` with a
result code — `OK`/`PARTIAL`/`AUTH_FAIL`/`NOT_MOUNTED`/`FORBIDDEN`/
`INVALID_ARGS`/`ERROR`/`BUSY`/`PERMISSION_DENIED`/`CAMERA_UNAVAILABLE`/
`NOT_RECORDING` — and message, as an ordinary broadcast an automation profile can branch a task
chain on. `PARTIAL` is specific to the folder actions (some files
succeeded, some failed); `BUSY`/`PERMISSION_DENIED`/`CAMERA_UNAVAILABLE`/`NOT_RECORDING` are
specific to the camera actions (`PERMISSION_DENIED` means the camera or
microphone permission hasn't been granted to the app).

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

While the decoy identity is active, `DecoyArchiveExplorerScreen` hosts
`DecoyFileManagerScreen`, which reuses the *same* file-browser UI
(`BrowserTabsShell`, hosted as the app root, and everything under
`features/browser/`) that browses
an unlocked vault — toolbar, settings, bookmarks, thumbnails, the native
PDF/media viewers, and the image/text editors all work identically, just
pointed at real device storage instead of a vault. `local_file_io_backend.dart`
and the local-storage branches added throughout `vault_file_io_api.dart` are
what let the same screen serve both without knowing the difference. This
replaces an older, separately-built `DecoyLocalExplorerScreen` (no longer
used) and an even older design where the decoy surface was just a zip
archive browser scoped to the device's public Downloads folder — the decoy
identity is now a genuinely usable local file manager for the device's real
storage, not a narrower archive-only view. A ZIP/archive browser is still
one of the things it can do (`decoy_archive_explorer_screen.dart`, reusing the
same native libarchive engine as §1), but it is one file-type view among
several now, not the whole of the decoy surface. Either way this is plain
filesystem access to real device storage with zero container/vault
involvement.

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
    (→ VaultDashboard on auth)                    (full local file manager, §6)
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

- **The file browser is a workspace of tabs hosted by one shell**
  (`lib/features/browser/`). `BrowserTabs` (`browser_tabs_provider.dart`) owns
  the tab list, the active tab and the back-history of one workspace, keyed by
  a `BrowserTabsConfig`. A tab is a `HomeTab` (the Dashboard) or a `FolderTab`,
  identified by a process-unique `TabId` that is never reused and that also
  keys every per-tab provider (navigation, selection, sort, search).
  `BrowserTabsShell` (`browser_tabs_host.dart`) is the only owner of window
  chrome (app bar, tab strip, drawer, FAB, bottom bar), the pager and the
  dual-pane layout. Each `DirectoryContentView` (one viewport per folder tab)
  hands its app bar, FAB and bottom bar to `BrowserChromeHub`
  (`browser_chrome_hub.dart`), which exposes the active tab's to the shell, and
  learns from the hub which tabs are on screen. *Active* (focused) decides who
  gets back, chrome and auto-lock activity; *visible* (active, or the second
  pane in dual-pane) decides who must keep its listing fresh. Decoy mode hosts
  the same shell with `appRoot: true`: no Home tab, closing the last tab
  reopens the primary storage, and back at the root leaves the app. There is no
  separate standalone browser screen. System back returns the person to where
  they started (`resolveBrowserBack` in `browser_back_policy.dart`): selection
  and search first, then folder depth; at the root of a tab opened from a Home
  tile (`BrowserTabOrigin.home`) it shows Home again, while a tab opened from
  the drawer, a folder action or a menu stops at its root. On Home, the first
  back asks for a second press and only then leaves the app, with or without
  other tabs open. Tests: `browser_tabs_provider_test.dart`,
  `browser_chrome_hub_test.dart`, `browser_back_policy_test.dart`.
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
- **Thumbnail settings resolve in exactly one place** (`resolveThumbnailSettings`
  in `thumbnail_settings_resolver.dart`). Cache mode and quality always travel
  together as a `ThumbnailSettings` value. Two scopes exist: *vaults* (an
  app-wide default in `FileManagerToolbarConfig.default*`, plus an optional
  per-vault override on `ContainerRecord` where both fields null = "Use global
  default", so changing the default reaches every vault that follows it) and
  *Local Storage + the decoy file manager* (one shared slot,
  `FileManagerToolbarConfig.localStorage*`, which never inherits the vault
  default). Every settings screen renders `ThumbnailSettingsTiles`; consumers
  of thumbnails only ever see the resolved value.
- **Unlock sheets dismiss the on-screen keyboard on tap-outside via an
  opaque overlay**, applied identically to local and USB unlock flows
  (`unlock_sheet.dart`, `usb_unlock_sheet.dart`, `advanced_params_panel.dart`).
- **The native crypto/filesystem engine's automated regression tests are
  plain host-side C++ binaries** — `g++`-buildable, `assert`-based, zero
  Android toolchain required, registered with CTest and gated behind
  `if(NOT ANDROID)` (`CMakeLists.txt`). Eleven tests are registered today —
  `composite_block_device_test`, `sector_batching_test`, `fs_scan_test`,
  `kdf_table_test`, `decrypted_block_cache_test`, `cryfs_block_cipher_test`,
  `utf16le_password_test`, `container_header_test`,
  `container_utils_crc32_test`, `chunked_block_device_test`, and
  `archive_engine_test` (only when its target exists). A few further test
  sources (`io/test/mbr_builder_test.cpp`,
  `containers/test/usb_create_diagnostics_test.cpp`) are self-contained,
  build with plain `g++ -std=c++17`, and pass, but are not registered with
  CTest.
- **The ext2/3/4 and NTFS backends have their own host tests that run the real
  backend code against real images, with independent tools as oracles**
  (`filesystems/test/ext_backend_test.cpp` with `e2fsck`, and
  `filesystems/test/ntfs_backend_test.cpp` with `ntfsfix`, `ntfsls` and
  `ntfscat`; built and run by `run_ext_backend_test.sh` /
  `run_ntfs_backend_test.sh`; the `native_ext_backend_tests` and
  `native_ntfs_backend_tests` CI jobs). Only the bottom of the stack is faked:
  FatFs's `disk_read`/`disk_write` seam (ext) and `physicalRead`/
  `physicalWrite` (NTFS), which in the app decrypt container sectors, are
  implemented over plain image files, so mount, format (`formatExtVolume`, and
  the embedded `mkntfs` for NTFS), the encrypted-sector I/O managers and every
  `ext*`/`ntfs*` operation are production code. The NTFS test builds ntfs-3g
  at the commit `CMakeLists.txt` pins, with the same generated `config.h` and
  file list, into a cache directory. They are separate scripts rather than
  CTest targets on purpose: the `native_host_tests` job builds an explicit
  target list, and the ext test needs the system `libext2fs-dev`/`e2fsprogs`
  rather than the vendored, Android-targeted e2fsprogs build.
  Between them they pin behaviours that were broken before the tests existed:
  deleting an ext directory freed neither its inode nor its parent link; a
  directory could be moved into its own subtree (ext and NTFS), detaching it
  from the root; writes could target a directory (ext and NTFS); ext `mkdir`
  onto an existing name leaked an inode; names over the filesystem limit were
  silently truncated to a shorter, different name (ext and NTFS); copying an ext
  file onto itself emptied it; NTFS mutations on a read-only volume reported
  success while changing nothing; and a second `mkntfs` in the same process
  failed or walked freed memory (`filesystems/mkntfs_embedded.c.in` resets its
  global state). Not covered: the BitLocker, VHD/VHDX and cipher layers, FAT,
  and Windows' own `chkdsk` (`ntfsfix` is a much weaker check than `e2fsck`).
- **`file_browser_screen.dart`'s selection-mode and sort-mode state live in
  reusable `SelectionMixin<T>`/`SortMixin<T>` mixins**, not inline in the
  screen's `State` class (`lib/features/browser/mixins/`).
- **The decoy reader's old "Open PDF File" picker code has been removed,
  and this note's own final claim has since gone stale in turn.**
  `pickLocalPdfFile()` in `disguise_mode_api.dart` had no Dart caller and no
  corresponding Kotlin-side channel handler, so it was dead on both ends;
  it's been deleted. (`PdfViewerBase`'s `localUri` parameter is still very
  much live — it's the general local-file entry point used outside the
  decoy flow — so it was left alone. The `PdfSearchConfig.decoy` reference
  this note used to make no longer matches any class in the codebase; that
  part of the note was itself stale.) This note used to conclude that the
  decoy identity had no PDF entry point at all — that stopped being true
  once decoy mode was rearchitected onto `DecoyFileManagerScreen` (§6): it
  now shares the same viewer stack as an unlocked vault, PDF included.
- **Composite containers (§1) are a real, shipped container format, not a
  prototype.** They're reachable from the ordinary "pick a container"
  dashboard flow (auto-detected via `carrier_profiler.cpp`'s blind-trailer
  probe) as well as from Tools → Composite Container
  (`composite_create_sheet.dart`). One current gap: `changeContainerPassword`
  has no composite path — `container_config_sheet.dart` explicitly blocks
  password change for a record where `isCompositeSource == true` rather than
  attempting it.
- **SAF-backed containers (e.g. a folder shared from a cloud-storage bridge
  app) are read/written through a local mirror, not directly against the
  `ContentResolver` on every call.** `MirrorSyncCoordinator`/`MirrorRegistry`
  (`android/app/src/main/kotlin/.../saf/`) keep a per-session copy under the
  app's own storage and pull/push against the real SAF document lazily; a
  cold read of a file at or above `LARGE_FILE_STREAM_THRESHOLD_BYTES` (8 MB)
  streams directly from the real document instead of blocking on a full
  pull first, so opening a large file for playback/seeking doesn't wait on
  downloading it in full.
- **Auto-sync (`lib/features/sync/`) keeps its rules and ledger inside the
  vault, compares each side with its own last-synced state, and never writes
  a file in place.** Rules live in `/.vaultexplorer/sync_config.json` and the
  ledger in `/.vaultexplorer/sync_ledger.json` (encrypted at rest; that folder
  is never synced); a device's SAF/path target for a rule is kept in
  `AppSecureStorage` under the vault's `vaultSyncId` + rule id. The ledger is
  JSON, not SQLite: the app has no database dependency and a vault file has no
  real path SQLite could open. `ThreeWayReconciler` decides per path from
  (vault, target, ledger baseline); after every transfer the destination's
  *real* post-write size/mtime is recorded, so storage that restamps mtimes on
  write (SAF, cryptors) never causes a bounce. `SyncExecutor` copies to
  `<name>.vexp_tmp` and swaps it in (`name → name.vexp_old`, `tmp → name`,
  delete old) because a rename onto an occupied name must fail (§2 rule 4);
  leftovers from an interrupted run are repaired at the next scan. A vault lock
  reaches the engine through `SyncLockBarrier`, consulted from
  `VaultLifecycleApi.lockContainer` next to `ActiveRecordingRegistry`; locks
  that bypass `lockContainer` (force-lock, panic, USB unplug) can't wait, and
  the engine tolerates the volume vanishing under it. Deletions are opt-in per
  rule and held back when a listing looks incomplete (unreadable or truncated
  folders, an unexpectedly empty side, or a mass deletion). "Keep in sync while
  unlocked" (`live_watch_service.dart`, `rule_watcher.dart`) is a debounced
  trigger plus a poll: there is no native change event for vault content, so the
  vault side is signalled by finished in-app file operations and device folders
  by `Directory.watch`, but the poll -- whose interval grows with the cost of the
  last run -- is what guarantees the two sides converge. A run that finds
  nothing to do is a scan and no writes, so a spurious trigger can't loop. Rules
  are edited per vault folder from that folder's action sheet
  (`sync_rule_editor_sheet.dart`); a run is only shown in the dashboard banner and
  the keep-alive notification once it has files to transfer, and the notification
  text is counts-only because Mask Mode shows it under the disguised identity.

---

## Cross-references

Section numbers above (`§2 rule 9`, `§3.4`, etc.) are the citation format
used in code comments elsewhere in the repo — keep them in sync if you
renumber a section. Some existing code comments predate this document and
cite an older `ADR-NNN` numbering scheme that no longer has a corresponding
section here; if you find one, use its surrounding code context (not the
number) to figure out what it's referring to, and consider updating the
comment to point at the current section number instead.
