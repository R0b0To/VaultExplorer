# VaultExplorer Automation Setup Guide (Tasker & MacroDroid)

VaultExplorer supports background automation via Android Broadcast Intents. You can unlock/lock vaults, import/export files and whole folders, take a photo or record video straight into a vault, and securely wipe plaintext source files -- all without opening the UI.

Every intent is sent as a **Broadcast** to VaultExplorer's receiver, which returns an `AUTOMATION_RESULT` broadcast with status and diagnostics.

---

## 1. Enable Automation for Your Vault

1. Open **VaultExplorer** and navigate to your vault's settings (or tap the vault card settings icon).
2. Tap **Automation**.
3. Under **Automation access**, select your desired tier:
   - **Off**: Automation cannot access this vault.
   - **Unlock / lock only (Lifecycle)**: Permits `UNLOCK_VAULT` and `LOCK_VAULT` actions.
   - **Unlock / lock + file import-export (Full)**: Permits all file-level actions -- `IMPORT_FILE`, `EXPORT_FILE`, `IMPORT_FOLDER`, `EXPORT_FOLDER`.
4. *(Optional)* **Automation Password**: Set a password if you want `UNLOCK_VAULT` to mount unattended without requiring the automation task to supply the password in plaintext.
5. *(Optional, only shown once the tier above is set to Full)* **Allow camera capture**: a separate switch that unlocks `TAKE_PHOTO`, `START_RECORDING`, and `STOP_RECORDING` for this vault. It's off by default even at Full tier -- a photo taken this way needs no on-screen indication at all, so it's a bigger trust decision than file import/export and gets its own explicit opt-in. Turning tier back down from Full and later back up to Full clears this switch again; you'll need to re-enable it.
6. Copy your **API Token** and **Vault URI** displayed on the screen.

---

## 2. Intent Target Configuration

Every intent sent to VaultExplorer must target the explicit Broadcast Receiver component:

| Setting | Value |
| :--- | :--- |
| **Package** | `com.aeidolon.vaultexplorer` |
| **Class / Component** | `com.aeidolon.vaultexplorer.automation.VaultAutomationReceiver` |
| **Target Type** | **Broadcast** *(Not Activity or Service!)* |

> ⚠️ **Important**: In **MacroDroid**, set **Intent Type** to **Broadcast**. Setting it to *Activity* will result in `unable to find explicit activity class`. In **Tasker**, set **Target** to **Broadcast Receiver**.

---

## 3. Broadcast Actions & Extras

All actions require `api_token`. Vault-specific actions also require `vault_uri`.

### `UNLOCK_VAULT`
Mounts the vault so files can be accessed or imported/exported.

- **Action**: `com.aeidolon.vaultexplorer.action.UNLOCK_VAULT`
- **Extras**:
  - `api_token` *(String, required)*: Your shared API token.
  - `vault_uri` *(String, required)*: The target vault URI.
  - `password` *(String, optional)*: Vault password. If omitted, falls back to the stored automation password.
  - `pim` *(Int, optional)*: VeraCrypt Personal Iteration Multiplier (e.g. `485`). Default: `0` (uses default algorithm iterations).
  - `keyfile_uris` *(String, optional)*: Pipe-delimited list of keyfile paths or content URIs (e.g. `/storage/emulated/0/keys/key1.bin|/storage/emulated/0/keys/key2.bin`). If omitted, falls back to pre-registered keyfiles configured in vault settings.
  - `cipher_id` *(Int, optional)*: Cipher algorithm ID hint (e.g. `1` for AES). Default: `255` (auto-detect all ciphers). Supplying this skips trial-and-error decryption passes and speeds up mounting.
  - `hash_id` *(Int, optional)*: Hash algorithm ID hint (e.g. `4` for SHA-512). Default: `255` (auto-detect).
  - `read_only` *(Boolean, optional)*: Mount in read-only mode (`true` / `false`). Default: `false`.

*Note: If the vault is already mounted, it returns `OK` immediately.*

---

### `LOCK_VAULT`
Unmounts and locks the vault, purging decrypted session material from memory.

- **Action**: `com.aeidolon.vaultexplorer.action.LOCK_VAULT`
- **Extras**:
  - `api_token` *(String, required)*
  - `vault_uri` *(String, required)*

---

### `IMPORT_FILE`
Imports a file (or batch of files matching a glob pattern) from the host filesystem directly into the encrypted vault. Requires the **Full** tier and an unlocked vault.

- **Action**: `com.aeidolon.vaultexplorer.action.IMPORT_FILE`
- **Extras**:
  - `api_token` *(String, required)*
  - `vault_uri` *(String, required)*
  - `source_path` *(String, required)*: Either an absolute file/folder path on the device (e.g. `/storage/emulated/0/DCIM/Camera/IMG_001.jpg`), or a `content://` SAF URI.
  - `vault_path` *(String, required)*: Relative destination path or directory in the vault. Any missing parent folders inside the vault are created automatically.
  - `pattern` *(String, optional)*: Glob wildcard pattern (e.g. `*.xlsx`, `HOSPITAL_RECEIPT_*`, `**/*.pdf`). When specified, `source_path` is treated as a directory and all matching files are imported in a single batch.
  - `recursive` *(Boolean, optional)*: Whether glob matching traverses subdirectories. Default: `true`.
  - `delete_source` *(Boolean, optional)*: If `true`, wipes matched source files upon successful import. For a raw filesystem path this is a secure overwrite-then-delete; for a `content://` source it's a normal provider delete.

---

### `EXPORT_FILE`
Exports a decrypted file from the vault to the host filesystem, OR streams it directly in-memory to another app without writing decrypted bytes to flash storage. Requires the **Full** tier and an unlocked vault.

- **Action**: `com.aeidolon.vaultexplorer.action.EXPORT_FILE`
- **Extras**:
  - `api_token` *(String, required)*
  - `vault_uri` *(String, required)*
  - `vault_path` *(String, required)*: Relative path inside the vault to read.
  - `dest_path` *(String, optional)*: Either an absolute destination *file* path on the host filesystem, or a `content://` SAF *tree* (folder) URI. (Required unless `stream_mode=true`).
  - `pattern` *(String, optional)*: Glob pattern to export matching files in batch.
  - `recursive` *(Boolean, optional)*: Whether glob matching traverses subdirectories. Default: `true`.
  - `stream_mode` *(Boolean, optional)*: **Zero-Disk Decrypted Data Streaming**. If `true`, VaultExplorer creates an ephemeral in-memory pipe and returns a single-use `stream_uri` in `AUTOMATION_RESULT` (see Section 6 for Termux recipe). No plaintext is ever written to disk storage.

---

### `IMPORT_FOLDER`
Recursively imports an entire folder (and everything inside it) into the vault with optional glob filtering. Requires the **Full** tier and an unlocked vault.

- **Action**: `com.aeidolon.vaultexplorer.action.IMPORT_FOLDER`
- **Extras**:
  - `api_token` *(String, required)*
  - `vault_uri` *(String, required)*
  - `source_path` *(String, required)*: Absolute folder path on the device, or a `content://` SAF *tree* URI.
  - `vault_path` *(String, optional)*: Destination folder inside the vault. Omit, or leave empty, to import into the vault root.
  - `pattern` *(String, optional)*: Glob pattern (e.g. `*.pdf`, `{jpg,png}`) to import only matching files.
  - `recursive` *(Boolean, optional)*: Whether traversal enters subdirectories. Default: `true`.
  - `delete_source` *(Boolean, optional)*: Same semantics as `IMPORT_FILE`'s `delete_source`, applied per file.

One file failing doesn't abort the rest -- it's best-effort, non-blocking batch execution. Check `result_code`/`result_message` and count extras (`matched_count`, `succeeded_count`, `failed_count`, `skipped_count`).

---

### `EXPORT_FOLDER`
Recursively exports a vault folder (and everything inside it) out to the host filesystem with optional glob filtering. Requires the **Full** tier and an unlocked vault.

- **Action**: `com.aeidolon.vaultexplorer.action.EXPORT_FOLDER`
- **Extras**:
  - `api_token` *(String, required)*
  - `vault_uri` *(String, required)*
  - `vault_path` *(String, optional)*: Source folder inside the vault. Omit, or leave empty, to export the whole vault.
  - `dest_path` *(String, required)*: Absolute destination folder path on the device, or a `content://` SAF tree URI. Created automatically if it doesn't exist yet.
  - `pattern` *(String, optional)*: Glob wildcard filter (e.g. `*.docx`).
  - `recursive` *(Boolean, optional)*: Default `true`.

Same best-effort, per-file semantics as `IMPORT_FOLDER`.

---

### `TAKE_PHOTO`
Captures a single photo directly through the device camera and saves it straight into the vault -- no preview, no UI, nothing shown on screen. Requires the **Full** tier *and* the separate **Allow camera capture** switch (see Section 1), plus an unlocked vault.

- **Action**: `com.aeidolon.vaultexplorer.action.TAKE_PHOTO`
- **Extras**:
  - `api_token` *(String, required)*
  - `vault_uri` *(String, required)*
  - `vault_path` *(String, optional)*: Destination path inside the vault. If omitted, a name like `IMG_20260823_153000.jpg` is generated at the vault root (matching the in-app camera's own naming), with a numeric suffix added if that name is already taken.
  - `camera_facing` *(String, optional)*: `back` (default) or `front`.

Camera and microphone permission must already be granted to VaultExplorer beforehand (open the app's own camera screen once to trigger the system permission prompt) -- automation has no way to show that prompt itself. See `PERMISSION_DENIED` / `CAMERA_UNAVAILABLE` below for how that surfaces.

---

### `START_RECORDING`
Starts recording video (with audio, by default) directly into the vault, and keeps recording until a matching `STOP_RECORDING` arrives. Same tier/opt-in requirements as `TAKE_PHOTO`.

- **Action**: `com.aeidolon.vaultexplorer.action.START_RECORDING`
- **Extras**:
  - `api_token` *(String, required)*
  - `vault_uri` *(String, required)*
  - `vault_path` *(String, optional)*: Destination path inside the vault. If omitted, a name like `VID_20260823_153000.mp4` is generated at the vault root, same collision handling as `TAKE_PHOTO`.
  - `camera_facing` *(String, optional)*: `back` (default) or `front`.
  - `video_quality` *(String, optional)*: `hd` / `fhd` (default) / `uhd`.
  - `record_audio` *(Boolean, optional)*: Default `true`.

Only one automation-triggered recording can be in progress at a time (across all vaults) -- a second `START_RECORDING` while one is already running gets `BUSY`. Because this needs a real, ongoing camera session, Android requires a persistent notification while it's active (unlike `TAKE_PHOTO`, which is fast enough to need none at all) -- the notification has its own **Stop** button too, in case your automation task never gets to send `STOP_RECORDING`. As a further backstop, a recording auto-stops and saves on its own after **3 hours** if nothing tells it to stop -- so a missed trigger loses at most the tail end, not the whole recording.

---

### `STOP_RECORDING`
Stops the in-progress automation recording started by `START_RECORDING` and finalizes it into the vault.

- **Action**: `com.aeidolon.vaultexplorer.action.STOP_RECORDING`
- **Extras**:
  - `api_token` *(String, required)*
  - `vault_uri` *(String, required)*: Must match the vault the current recording is writing into.

On success, the `AUTOMATION_RESULT` broadcast includes an extra `duration_ms` *(Long)* with the recording's length. A long recording's finalize step (streaming the whole file into the vault) can take a little while -- if VaultExplorer gives up waiting and reports `ERROR`/a timeout message, the save may still complete moments later in the background; the broadcast reply and the actual data landing in the vault aren't strictly the same guarantee.

---

### `WIPE_FILE`
Securely zeroes out and deletes any plaintext file on the device storage.

- **Action**: `com.aeidolon.vaultexplorer.action.WIPE_FILE`
- **Extras**:
  - `api_token` *(String, required)*
  - `source_path` *(String, required)*: Absolute filesystem path to wipe.

---

## 4. Reading Results (`AUTOMATION_RESULT`)

VaultExplorer broadcasts a response intent for every processed action:

- **Action**: `com.aeidolon.vaultexplorer.action.AUTOMATION_RESULT`
- **Received Extras**:
  - `original_action` *(String)*: The action that was executed.
  - `result_code` *(String)*: Status code:
    - `OK`: Action completed successfully.
    - `AUTH_FAIL`: Invalid credentials or decryption failure.
    - `NOT_MOUNTED`: The vault is locked and must be unlocked first.
    - `FORBIDDEN`: Action not allowed by the vault's automation tier (or, for the camera actions, the separate **Allow camera capture** switch isn't on).
    - `INVALID_ARGS`: Missing or malformed parameters/paths.
    - `ERROR`: General failure or I/O exception.
    - `PARTIAL` *(batch operations only)*: The folder or glob batch finished, but at least one file failed. Check `result_message` and the count extras below.
    - `PERMISSION_DENIED` *(`TAKE_PHOTO` / `START_RECORDING` only)*: Camera/microphone permission isn't granted on-device. Automation can't trigger the system permission prompt itself -- open VaultExplorer's own camera screen once to grant it, then retry.
    - `CAMERA_UNAVAILABLE` *(`TAKE_PHOTO` / `START_RECORDING` only)*: The camera couldn't be opened -- commonly because something else (e.g. VaultExplorer's own in-app camera screen) already has it open, or a hardware/driver error. Also returned when an OEM device policy or MDM profile has disabled the camera hardware (`CAMERA_DISABLED`).
    - `BUSY` *(`START_RECORDING` only)*: An automation recording is already in progress.
    - `NOT_RECORDING` *(`STOP_RECORDING` only)*: Nothing is currently recording, or the in-progress recording belongs to a different vault than the one named in `vault_uri`.
  - `result_message` *(String)*: Human-readable message or error details.
  - `duration_ms` *(Long, only present on a successful `STOP_RECORDING`)*: Length of the recording that was just saved, in milliseconds.
  - `matched_count` *(Int, batch operations)*: Number of files matched by glob pattern (or total files traversed when no `pattern` is set).
  - `succeeded_count` *(Int, batch operations)*: Number of files successfully imported/exported.
  - `failed_count` *(Int, batch operations)*: Number of files that failed mid-operation (I/O error, permission denied, etc.).
  - `skipped_count` *(Int, batch operations)*: Number of files skipped (e.g. destination already exists, pattern excluded, or zero-byte files).
  - `stream_uri` *(String, only present when `stream_mode=true` on `EXPORT_FILE`)*: Single-use `content://` URI to read decrypted bytes directly from memory. See Section 6 for Termux recipe.

> 💡 **Tip**: If your automation tool receives **no response at all**, verify your `api_token`. Requests with invalid or missing tokens are discarded silently to prevent token brute-forcing.

---

## 5. Typical Automation Workflow: Camera / File Sync

A standard task chain unlocks the vault, imports the file (with optional secure wipe of the original), and locks the vault:

```
[Trigger] (e.g., New photo taken / Schedule)

├─► Send Broadcast: UNLOCK_VAULT
│   (Wait for AUTOMATION_RESULT: result_code == "OK" or 1s delay)
│
├─► Send Broadcast: IMPORT_FILE (source_path, vault_path, delete_source=true)
│   (Wait for AUTOMATION_RESULT: result_code == "OK")
│
└─► Send Broadcast: LOCK_VAULT
```

### Variant: whole-folder sync with glob filter

Swap `IMPORT_FILE` for `IMPORT_FOLDER` and add a `pattern` to batch-import only matching files. With `delete_source=true` the originals are securely wiped after each successful transfer:

```
IMPORT_FOLDER
  source_path   = /storage/emulated/0/DCIM/Camera
  vault_path    = Photos
  pattern       = *.{jpg,jpeg,png,heic}
  delete_source = true
```

Check `succeeded_count` / `failed_count` in the result broadcast to know whether everything landed safely.

### Variant: direct capture (no separate camera app involved)

Skips the OS camera / gallery step entirely -- VaultExplorer takes the photo or video itself, straight into the vault. Requires the **Allow camera capture** switch from Section 1.

```
[Trigger] (e.g., NFC tag, geofence, a specific charger plugged in)

├─► Send Broadcast: UNLOCK_VAULT
│   (Wait for AUTOMATION_RESULT: result_code == "OK")
│
├─► Send Broadcast: TAKE_PHOTO (camera_facing=front)
│   (Wait for AUTOMATION_RESULT)
│
└─► Send Broadcast: LOCK_VAULT
```

For a recording instead of a single photo, replace the middle step with `START_RECORDING`, then a *separate* trigger later in the same task (or a different profile entirely) sends `STOP_RECORDING` before the final `LOCK_VAULT` -- remember the 3-hour auto-stop safety net from Section 3 covers you if that second trigger never fires.

---

## 6. Recipe Examples

### MacroDroid Setup

1. Add an action: **Connectivity** ➔ **Send Intent**.
2. Configure:
   - **Target**: `Broadcast`
   - **Package**: `com.aeidolon.vaultexplorer`
   - **Class**: `com.aeidolon.vaultexplorer.automation.VaultAutomationReceiver`
   - **Action**: `com.aeidolon.vaultexplorer.action.UNLOCK_VAULT` *(or desired action)*
3. Add **Extra Parameters**:
   - Parameter 1: Name `api_token`, Value: `<YOUR_TOKEN>`
   - Parameter 2: Name `vault_uri`, Value: `<YOUR_VAULT_URI>`
   - *(Add action-specific parameters as needed)*

### Tasker Setup

1. Add action: **System** ➔ **Send Intent**.
2. Configure:
   - **Action**: `com.aeidolon.vaultexplorer.action.UNLOCK_VAULT` *(or desired action)*
   - **Package**: `com.aeidolon.vaultexplorer`
   - **Class**: `com.aeidolon.vaultexplorer.automation.VaultAutomationReceiver`
   - **Target**: `Broadcast Receiver`
   - **Extra**:
     ```text
     api_token:<YOUR_TOKEN>
     vault_uri:<YOUR_VAULT_URI>
     ```

### Glob Pattern Syntax Reference

The `pattern` extra uses an offline glob engine with the following syntax:

| Pattern | Matches |
| :--- | :--- |
| `*` | Any characters within a single directory level (no `/`) |
| `**` | Any characters including path separators (cross-directory) |
| `?` | Exactly one character (not `/`) |
| `[a-z]` | Any character in a range |
| `[!a-z]` | Any character **not** in a range |
| `{jpg,png,gif}` | Any of the comma-separated alternatives |

Pattern matching is **case-insensitive** by default. Examples:

- `*.pdf` — all PDFs in the immediate folder
- `**/*.pdf` — all PDFs in the folder and all subdirectories
- `REPORT_202[4-9]_*.xlsx` — spreadsheets from 2024–2029
- `{IMG,VID}_*.{jpg,mp4}` — camera files with standard naming

### Zero-Disk Decrypted Data Streaming (Termux / CLI Recipe)

Use `stream_mode=true` on `EXPORT_FILE` to read decrypted bytes directly from memory into another process without writing decrypted bytes to flash storage:

**Step 1 — Request the stream in Tasker / shell:**
```bash
am broadcast \
  -a com.aeidolon.vaultexplorer.action.EXPORT_FILE \
  -n com.aeidolon.vaultexplorer/.automation.VaultAutomationReceiver \
  --es api_token "<YOUR_TOKEN>" \
  --es vault_uri "<YOUR_VAULT_URI>" \
  --es vault_path "reports/Q4_2025.pdf" \
  --ez stream_mode true
```

**Step 2 — Capture `stream_uri` from `AUTOMATION_RESULT`:**
```bash
# stream_uri format: content://com.aeidolon.vaultexplorer.stream/stream/<session_token>
STREAM_URI="<captured stream_uri>"
```

**Step 3 — Consume the stream within 5 minutes (single-use):**
```bash
# Termux: pipe decrypted stream directly to any tool -- zero disk footprint
termux-saf-read "$STREAM_URI" | gpg --encrypt -r user@example.com > Q4_encrypted.pdf
# Or calculate hash without touching disk:
termux-saf-read "$STREAM_URI" | sha256sum
```

> ⚠️ **Stream constraints**: Each `stream_uri` is single-use and expires after **5 minutes**. A maximum of **8 concurrent streams** are permitted. Backpressure ensures memory consumption remains bounded (<128 KB) regardless of file size.

---

## 7. OEM Background Service Survival

For device-specific instructions on keeping the background foreground service alive on Samsung, Xiaomi, OnePlus, and Pixel devices, see the [OEM Setup Guide](file:///c:/Users/Aeido/Documents/Projects/vaultexplorer/docs/oem-setup-guide.md).

---

## 8. Important Notes & Gotchas

- **File Paths**: `source_path`/`dest_path` (on `IMPORT_FILE`, `EXPORT_FILE`, `IMPORT_FOLDER`, `EXPORT_FOLDER`) accept either a real absolute filesystem path (e.g. `/storage/emulated/0/...`) or a `content://` SAF URI. The SAF form only works if VaultExplorer *already holds a persisted permission grant* for that exact URI -- typically because you picked that same folder through one of VaultExplorer's own folder pickers at some point. Android has no mechanism for a broadcast Intent to hand over a fresh grant for a URI the app has never seen before, so an arbitrary `content://` value from a task you've never connected to VaultExplorer will just fail (`INVALID_ARGS`/`ERROR`), not silently do nothing. When you don't already have such a grant, a raw filesystem path is simpler and always works.
- **Tiers**: `IMPORT_FILE`, `EXPORT_FILE`, `IMPORT_FOLDER`, and `EXPORT_FOLDER` all require the **Full** automation tier. `Lifecycle` only permits `UNLOCK_VAULT` and `LOCK_VAULT`. `TAKE_PHOTO`, `START_RECORDING`, and `STOP_RECORDING` require Full tier *and* the separate **Allow camera capture** switch -- see Section 1.
- **Camera actions are genuinely silent**: `TAKE_PHOTO` shows nothing on screen at all -- no notification, no shutter UI. `START_RECORDING`/`STOP_RECORDING` do show a persistent notification while recording (Android requires this for any app using the camera in the background), with its own manual Stop button. Neither depends on VaultExplorer's app UI being open; both work from a cold start as long as the vault has a stored automation password (see `UNLOCK_VAULT`) and camera/microphone permission was already granted once from within the app.
- **Folder syncs are best-effort**: `IMPORT_FOLDER`/`EXPORT_FOLDER` don't abort on the first failed file -- check for `result_code == "PARTIAL"` if you need to know whether everything actually made it across.
- **Token Invalidation**: Regenerating your API token in VaultExplorer immediately invalidates existing tasks until updated.
- **USB Storage**: Automation is currently not supported on hardware USB OTG-mounted drives.