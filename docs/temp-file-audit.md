# Temporary Disk File Usage Audit & Refactor

Audit of everywhere VaultExplorer wrote sensitive data to a temp/cache file
on host disk, classified by risk, with a refactoring plan and the status of
each finding after this pass. Findings are numbered `TF-01`..`TF-08` and
referenced from code comments at each fixed call site, so anyone reading the
code later lands back here.

## How to read this

- **Status: Fixed** — refactored to Category A/B (in-memory / encrypted
  staging) in this pass. No plaintext temp file remains for that path.
- **Status: Hardened** — the temp file is unavoidable (Category D: a native
  library genuinely requires a real file path), but cleanup now zero-fills
  before deleting instead of a plain `delete()`.
- **Status: Compliant (no change needed)** — reviewed and already correct
  (Category B encrypted staging, or Category B/D done right with
  stream/pipe/secure-wipe already in place). Listed so the pattern is
  visible and future code can be held to the same bar.
- **Status: Backlog** — confirmed finding, not yet fixed in this pass.
  Recommended approach included.
- **Status: Not reviewed** — flagged by the initial grep sweep as a
  `createTempFile`/`cacheDir` hit but not opened and inspected this pass.
  Listed so it isn't silently dropped; needs a follow-up look before anyone
  assumes it's fine.

---

## Critical: Plaintext Disk Spill

| ID | Location | What it did | Status |
|----|----------|-------------|--------|
| TF-01 | `lib/features/browser/viewer/text_editor_screen.dart` | Decrypted the file to a `cb_edit_*` temp file, read it, let the user edit it *on disk*, wrote edits back to that same file, then re-encrypted from it | **Fixed** |
| TF-02 | `lib/data/models/archive_context.dart`, `lib/data/services/archive_service.dart` | Decrypted an archive to an `archive_browse_*` temp file before parsing it, even though the `archive` package decodes fully into memory anyway | **Fixed** |
| TF-03 | Same files + `lib/features/browser/archive_file_viewer.dart`, `lib/features/decoy/decoy_archive_*.dart` | Every entry a user opened or extracted from an archive was written to an `archive_extract_*` temp file first, even though `ArchiveContext` already held the bytes in memory from parsing | **Fixed** |
| TF-05 | `lib/data/services/vault_engine/vault_explorer_api_file_io.dart::createEmptyFile`, Kotlin `ContainerDocumentsProvider.kt::createDocument` | Created an empty (`cb_empty_*` / `vc_new_*`) scratch file on disk purely to hand a path to `writeBackFile`, for what is *always* zero bytes of content | **Fixed** (both Dart and Kotlin sides) |
| TF-06 | Kotlin `ContainerDocumentsProvider.kt::openDocumentThumbnail` | Decrypted the source image to a `thumb_*` temp file so `BitmapFactory.decodeFile` could read it, when `BitmapFactory.decodeByteArray` does the same job from memory | **Fixed**, with a size-thresholded fallback (see Category C below) |
| TF-07 | Kotlin `ContainerEngine.kt::importStream` | Streams an imported file to a `vc_import_*` temp file so the C++ `NativeEngine` (VeraCrypt/LUKS/BitLocker) can `writeBackFile` from a real path | **Hardened** (Category D — see below) |
| TF-08 | `lib/features/tools/services/container_tool_service.dart::runBatchFileCrypto` | The standalone file-encrypt/decrypt tool stages plaintext in `vx_crypto_in_*`/`vx_crypto_out_*` dirs around the native crypto engine call | **Hardened** (Category D — see below) |
| — | Kotlin `cryfs/CryfsSession.kt` (`cryfs_write_*.tmp`, line ~168) | Materializes the *full current plaintext* of a CryFS-backed file into a cache-dir scratch file to support random-offset writes, before re-encrypting on `finishWrite`; cleaned up with plain `.delete()` at lines 31, 100, 208 | **Backlog** — see below |

## Medium: Encrypted Staging / Excess Wear (reviewed, compliant)

These write to a temp/staging file, but the bytes on disk are ciphertext,
not plaintext — the app's own encrypted container format, not the
underlying document. No plaintext spill; listed for completeness and
because `VaultItemsService`'s pattern is what `writeWholeFile` (added in
this pass) generalizes.

| Location | What it does |
|----------|--------------|
| `lib/data/services/vault_items_service.dart` (`saveItem`) | Writes vault metadata to a `<path>.tmp` path *inside the encrypted container* (ciphertext at rest), then atomically renames over the real path. This is the pattern `VaultExplorerApi.writeWholeFile` (new, see below) generalizes for every other in-memory writer. |
| Kotlin `engine/ChunkedFileEngine.kt` (`vault_write_*.tmp`, line ~345) | Buffers less-than-one-chunk of cleartext in a RAM `ByteArrayOutputStream`, encrypts each full chunk, and only ever writes *already-encrypted* chunks to the temp file. Shared write-buffering engine behind (at least) the gocryptfs/cryptomator-style backends. |
| Kotlin `LocalSplitFuseCallback.kt` (`split_rw_mirror_*`, line ~581) | Mirrors a split-container **part** (already ciphertext — a chunk of an encrypted VeraCrypt/LUKS container image) to a local dir for random-access read-write, only as a fallback when the SAF document provider backing storage doesn't support seekable RW. |

## Low / Constrained (Category D) — reviewed, already correct

Cited as the reference pattern other Category D code should match.

| Location | Why it's constrained | Why it's fine as-is |
|----------|----------------------|----------------------|
| Kotlin `ContainerDocumentsProvider.kt::openDocument` | Hands a real file to any app requesting to open a vault document via SAF | Uses `StorageManager.openProxyFileDescriptor` with a FUSE-style proxy callback — genuine stream-to-stream, **zero temp files**, even for arbitrarily large files |
| Kotlin `ExternalOpenBridge.kt` ("open with app") | Third-party apps need a real `content://` Uri | Builds the Uri via `DocumentsContract` pointing at the same `ContainerDocumentsProvider` above — no separate extraction step |
| Kotlin `ImportExportHandlers.kt` (`export_*`) | Export has to produce a real file for the user to save/share | Already wipes via `SecureFileWipe.secureDeleteFile` (2 call sites) |
| Kotlin `camera/VaultVideoRecorder.kt` | `MediaRecorder`/`MediaCodec` hard-require a real output file descriptor | Already zero-fills before delete (own local copy of the same logic as `SecureFileWipe`; worth de-duplicating onto the shared utility as a follow-up, but not a security issue) |

---

## Refactoring approach used

### Category A (Memory-First) — TF-01, TF-02, TF-03, TF-05, TF-06

The app already had chunked read/write platform-channel calls
(`readFileChunk` / `writeFileChunk`, capped at 64 MB/call — see
`FileOperationHandlers.kt::MAX_CHUNK_BYTES`) sitting next to the
file-path-based `decryptFile` / `writeBackFile` calls. The fix was almost
always "use the chunk API in a loop instead of the path-based one":

- Added `VaultExplorerApi.readWholeFile()` / `writeWholeFile()`
  (`lib/data/services/vault_engine/vault_explorer_api_file_io.dart`):
  loop `readFileChunk`/`writeFileChunk` into/out of a Dart `Uint8List`,
  8 MB per call. `writeWholeFile` stages into a `<path>.tmp` **inside the
  vault** (ciphertext, Category B) and renames into place, generalizing
  the pattern `VaultItemsService.saveItem` already used.
- `ArchiveContext` (`lib/data/models/archive_context.dart`) now takes the
  archive's `Uint8List` bytes directly instead of a `tempFilePath`, and
  `extractEntry`/`extractAll` return `Uint8List`/`Map<String, Uint8List>`
  pulled straight out of the already-in-memory `Archive` object — nothing
  is written to disk to open or browse an archive.
- `ArchiveFileViewer` takes `bytes` instead of a `File`, using
  `Image.memory`/`utf8.decode` instead of `Image.file`/`file.readAsString`.
- Every call site (`file_browser_screen.dart`, both decoy archive screens,
  `decoy_archive_extract.dart`) updated to match. `decoy_archive_extract.dart`
  now writes extracted bytes straight to their real destination file with no
  intermediate temp copy — the "Extract to Downloads" feature's whole point
  is a real file at the end, so that direct write is the correct end state,
  not a finding.
- `ContainerDocumentsProvider.kt::createDocument` writes an empty chunk via
  `ContainerFileSystem.writeFileChunk(volId, path, 0, ByteArray(0))` and
  then explicitly calls the new `ContainerFileSystem.finishWrite(volId,
  path)` wrapper (added alongside `writeFileChunk`/`writeBackFile`) — this
  matters because `writeBackFile`'s native implementation used to call
  `finishWrite` internally, and skipping it silently no-ops on
  Cryptomator/gocryptfs vaults.
- `ContainerDocumentsProvider.kt::openDocumentThumbnail` reads the source
  into a `ByteArray` (`readFileChunk` loop, 4 MB/call) and decodes with
  `BitmapFactory.decodeByteArray` for both the bounds-only and real decode
  passes — same two-pass downsampling as before, no temp file.

**A correctness bug caught along the way:** the original
`createEmptyFile`/`createDocument` used `writeBackFile`, whose native
implementation calls `finishWrite` internally for backends that need their
write buffer flushed (Cryptomator, gocryptfs — see
`ContainerEngine.kt::finishWrite`'s doc comment: *"required for Cryptomator
and Gocryptfs to flush their write buffers"*). Swapping to `writeFileChunk`
directly, my first pass on both the Dart and Kotlin sides dropped that
`finishWrite` call — which would have silently no-op'd empty-file creation
on those two backends. Caught by re-reading `finishWrite`'s doc comment
before considering the fix done; both sides now call it explicitly.

### Category B (Encrypted Staging) — used by writeWholeFile, not touched elsewhere

`writeWholeFile`'s `<path>.tmp` staging file lives inside the encrypted
container, so it's ciphertext at rest — this is the correct existing
pattern (`VaultItemsService`), just reused instead of reinvented.

### Category C (Adaptive Threshold) — TF-06

`openDocumentThumbnail` decodes in-memory for sources up to 32 MB
(`THUMBNAIL_MEMORY_THRESHOLD_BYTES`), comfortably above any realistic
thumbnail source image. Above that, it falls back to the original
`extractToFile` + `BitmapFactory.decodeFile` path — still real, but now
routed through `SecureFileWipe.secureDeleteFile` on cleanup either way, and
commented as an explicit Category C boundary rather than a silent
threshold.

### Category D (Unavoidable, Hardware/Library-Constrained) — TF-07, TF-08

Two places call directly into native libraries that only accept real file
paths — a compiled crypto/container engine (C++, JNI), not something Dart
can hand a stream or pipe to without a much larger native rewrite:

- **TF-08**, `container_tool_service.dart::runBatchFileCrypto` — the
  standalone encrypt/decrypt tool's underlying cipher implementations read
  and write real files. Added `lib/core/utils/secure_temp_file.dart`
  (`SecureTempFile.wipeAndDeleteDir`, mirroring the Kotlin
  `SecureFileWipe.kt` already used elsewhere in the app) and wired it into
  the existing `finally` block, replacing a plain `deleteSync(recursive:
  true)`. Documented in-line why the temp dir can't be eliminated.
- **TF-07**, `ContainerEngine.kt::importStream` — same story for the
  VeraCrypt/LUKS/BitLocker import path via `NativeEngine.writeBackFile`.
  Cleanup swapped from `tempFile.delete()` to
  `SecureFileWipe.secureDeleteFile(tempFile)`.

  **Known remaining gap, not fixed this pass:** the temp file is created
  with `File.createTempFile("vc_import_", ".tmp")` — no explicit directory
  argument, unlike every other temp file in this codebase (which all pass
  `context.cacheDir` explicitly). This falls back to the `java.io.tmpdir`
  JVM system property, which the Android runtime is not guaranteed to set
  to a private, writable location on every OS version/OEM — a known
  historical Android footgun. Fixing it properly means threading a
  `Context` (or a pre-resolved private dir) through
  `ImportExportHandlers` → `ContainerFileSystem` → `ContainerEngine`
  (a plain singleton `object` today with no `Context` reference). That's a
  cross-file signature change I didn't make blind in an environment
  without an Android toolchain to compile-check it — recommended as
  follow-up work, done with the actual build available to verify.

---

## Backlog: not fixed this pass

### `CryfsSession.kt` write scratch file (`cryfs_write_*.tmp`)

Every write to a CryFS-backed file materializes that file's **full current
plaintext** into a cache-dir scratch file (`File.createTempFile("cryfs_write_",
".tmp", context.cacheDir)`, line ~168) so it can support writes at an
arbitrary offset before re-encrypting the whole blob on `finishWrite`.
Cleanup is a plain `.delete()` at three sites (lines 31, 100, 208) — no
zero-fill.

This is the same class of finding as TF-08/TF-07 (Category D: the CryFS
blob model doesn't have a partial-update primitive, so *some* real buffer
holding the file's plaintext is probably unavoidable for files that don't
fit comfortably in memory) — but unlike those two, it wasn't hardened in
this pass. Recommended next step, in order of effort:

1. **Quick, low-risk win:** swap the three `.delete()` calls for
   `SecureFileWipe.secureDeleteFile()`, matching every other Category D
   temp file in the app. Self-contained to `CryfsSession.kt`.
2. **Larger, higher-value fix:** for files under an adaptive threshold
   (say the same 20-50 MB range used elsewhere), replace the on-disk
   scratch file with an in-memory `ByteArray` buffer instead — same
   Category A/C treatment already applied to TF-01/TF-02/TF-03/TF-06.
   Only files above the threshold would still need the disk-backed
   scratch file. This needs closer reading of how `pendingWrites` and
   `finishWrite` interact with the rest of `CryfsSession` before changing
   it, which is why it's flagged rather than attempted blind here.

### Not reviewed this pass

The initial grep sweep also surfaced these `createTempFile`/`cacheDir`
call sites; they weren't opened and inspected, so they're neither
confirmed findings nor confirmed compliant — flagged so they aren't
silently assumed fine:

- Kotlin `ThumbnailHandlers.kt` — a *second*, Dart-channel-facing
  thumbnail code path, distinct from `ContainerDocumentsProvider.kt`'s
  SAF-facing `openDocumentThumbnail` (TF-06, fixed). May have the same
  temp-file-for-`BitmapFactory.decodeFile` pattern; not checked.
- Kotlin `PendingActivityResult.kt` — flagged by the initial `cacheDir`
  grep; purpose not inspected.
- `VaultPdfContentProvider.kt` / PDF viewer plumbing, and the HTML
  viewer's asset-stream handling — referenced in passing while tracing
  `openWithApp` (which does stream cleanly via a proxy fd), but not
  opened directly. Worth a dedicated pass rather than assuming they match
  the good `openDocument` pattern just because they're neighbors of it.

---

## Files touched this pass

**Dart**
- `lib/core/utils/secure_temp_file.dart` (new)
- `lib/data/services/vault_engine/vault_explorer_api.dart` (import cleanup)
- `lib/data/services/vault_engine/vault_explorer_api_file_io.dart`
  (`createEmptyFile` fix; added `readWholeFile`/`writeWholeFile`)
- `lib/features/browser/viewer/text_editor_screen.dart`
- `lib/data/models/archive_context.dart` (rewritten)
- `lib/data/services/archive_service.dart` (rewritten)
- `lib/features/browser/archive_file_viewer.dart` (rewritten)
- `lib/features/browser/file_browser_screen.dart` (call site)
- `lib/features/decoy/decoy_archive_extract.dart` (rewritten)
- `lib/features/decoy/decoy_archive_browse_screen.dart` (call sites)
- `lib/features/decoy/decoy_archive_explorer_screen.dart` (call sites + comments)
- `lib/features/tools/services/container_tool_service.dart` (secure wipe)

**Kotlin**
- `android/app/src/main/kotlin/com/aeidolon/vaultexplorer/ContainerDocumentsProvider.kt`
  (`createDocument`, `openDocumentThumbnail`)
- `android/app/src/main/kotlin/com/aeidolon/vaultexplorer/ContainerFileSystem.kt`
  (added `finishWrite` wrapper)
- `android/app/src/main/kotlin/com/aeidolon/vaultexplorer/ContainerEngine.kt`
  (`importStream` secure wipe + documented gap)

## Verification performed

No Android/Flutter toolchain was available in this environment to run
`flutter analyze` or a Gradle build, so verification was manual:

- Brace/paren balance check on every edited file.
- Every removed symbol (`tempFilePath`, `File(...)` params on
  `ArchiveFileViewer`, `decryptFile`/`writeBackFile` in the text editor)
  grepped across the whole `lib/` tree to confirm no stale call sites were
  left behind.
- Every new/changed method call (`writeFileChunk`, `finishWrite`,
  `finishWriteIfCryptomator`, `readFileChunk`, `getFileSize`,
  `SecureFileWipe.secureDeleteFile`) checked against its actual declared
  signature in the codebase before use.
- Every l10n key referenced in edited widgets confirmed present in
  `lib/l10n/generated/app_localizations_en.dart`.

**This has not been compiled or run.** Recommended before merging:
`flutter analyze`, a full Gradle build, and manual testing of: opening and
editing a text file, browsing/extracting a zip from a vault, browsing a zip
in decoy mode, creating a new empty file via a SAF-connected app, thumbnail
generation for a large (>32 MB) image, and one run of the standalone
encrypt/decrypt tool.
