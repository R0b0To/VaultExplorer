# VaultExplorer Automation Setup Guide (Tasker & MacroDroid)

VaultExplorer supports background automation via Android Broadcast Intents. You can unlock/lock vaults, import/export files and whole folders, take a photo or record video straight into a vault, stream decrypted files directly through memory without flash writes, and securely wipe plaintext source files -- all without opening the UI.

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

> ⚠️ **Important**: In **MacroDroid**, set **Intent Target** to **Broadcast**. Setting it to *Activity* will result in `unable to find explicit activity class`. In **Tasker**, set **Target** to **Broadcast Receiver**.

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
  - `cipher_id` *(Int, optional)*: Cipher algorithm ID hint (e.g. `0` for AES). Default: `255` (auto-detect all ciphers). Supplying this skips trial-and-error decryption passes and speeds up mounting.
  - `hash_id` *(Int, optional)*: Hash algorithm ID hint (e.g. `0` for SHA-512). Default: `255` (auto-detect).
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
Exports a decrypted file from the vault to the host filesystem, OR streams it directly through memory without writing decrypted bytes to flash storage. Requires the **Full** tier and an unlocked vault.

- **Action**: `com.aeidolon.vaultexplorer.action.EXPORT_FILE`
- **Extras**:
  - `api_token` *(String, required)*
  - `vault_uri` *(String, required)*
  - `vault_path` *(String, required)*: Relative path inside the vault to read.
  - `dest_path` *(String, optional)*: Either an absolute destination *file* path on the host filesystem, or a `content://` SAF *tree* (folder) URI. (Required unless `stream_mode=true`).
  - `pattern` *(String, optional)*: Glob pattern to export matching files in batch.
  - `recursive` *(Boolean, optional)*: Whether glob matching traverses subdirectories. Default: `true`.
  - `stream_mode` *(Boolean, optional)*: **Zero-Disk Decrypted Data Streaming**. If `true`, VaultExplorer creates a memory-backed seekable proxy file descriptor and returns a `stream_uri` in `AUTOMATION_RESULT`. The stream supports **random-access seeking (`lseek`)** and multi-pass reading (for 2-pass image decoders, video players, and PDF viewers) during its 5-minute validity window without writing plaintext to flash storage.

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
    - `FORBIDDEN`: Action not allowed by the vault's automation tier (or, for camera actions, the separate **Allow camera capture** switch isn't on).
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
  - `stream_uri` *(String, only present when `stream_mode=true` on `EXPORT_FILE`)*: Temporary `content://` URI to read or view decrypted bytes directly through memory without flash writes.

> 💡 **Tip**: If your automation tool receives **no response at all**, verify your `api_token`. Requests with invalid or missing tokens are discarded silently to prevent token brute-forcing.

---

## 5. Typical Automation Workflows

### Standard Sync: Camera / File Sync
A standard task chain unlocks the vault, imports the file (with optional secure wipe of the original), and locks the vault:

[Trigger] (e.g., New photo taken / Schedule)

├─► Send Broadcast: UNLOCK_VAULT │ (Wait for AUTOMATION_RESULT: result_code ==
"OK" or 1s delay) │ ├─► Send Broadcast: IMPORT_FILE (source_path, vault_path,
delete_source=true) │ (Wait for AUTOMATION_RESULT: result_code == "OK") │ └─►
Send Broadcast: LOCK_VAULT


### Variant: Whole-folder sync with glob filter
Swap `IMPORT_FILE` for `IMPORT_FOLDER` and add a `pattern` to batch-import only matching files. With `delete_source=true` the originals are securely wiped after each successful transfer:

IMPORT_FOLDER source_path = /storage/emulated/0/DCIM/Camera vault_path = Photos
pattern = *.{jpg,jpeg,png,heic} delete_source = true


### Variant: Direct capture (no separate camera app involved)
Skips the OS camera / gallery step entirely -- VaultExplorer takes the photo or video itself, straight into the vault. Requires the **Allow camera capture** switch from Section 1.

[Trigger] (e.g., NFC tag, geofence, a specific charger plugged in)

├─► Send Broadcast: UNLOCK_VAULT │ (Wait for AUTOMATION_RESULT: result_code ==
"OK") │ ├─► Send Broadcast: TAKE_PHOTO (camera_facing=front) │ (Wait for
AUTOMATION_RESULT) │ └─► Send Broadcast: LOCK_VAULT


---

## 6. Recipe Examples

### MacroDroid Setup

In MacroDroid, use a **2-Macro** setup: one macro to send requests, and another macro to listen for `AUTOMATION_RESULT`.

#### Macro 1: "Send Action" (e.g. Unlock or Request Stream)
1. Add Action ➔ **Connectivity ➔ Send Intent**.
2. Configure:
   * **Target**: `Broadcast` *(⚠️ Do not select Activity!)*
   * **Action**: `com.aeidolon.vaultexplorer.action.EXPORT_FILE` *(or desired action)*
   * **Package**: `com.aeidolon.vaultexplorer`
   * **Class**: `com.aeidolon.vaultexplorer.automation.VaultAutomationReceiver`
   * **Extra 1** (`String`): `api_token` = `<YOUR_TOKEN>`
   * **Extra 2** (`String`): `vault_uri` = `<YOUR_VAULT_URI>`
   * **Extra 3** (`String`): `vault_path` = `document.pdf`
   * **Extra 4** (`Boolean`): `stream_mode` = `true` *(or set `dest_path` for normal file export)*

#### Macro 2: "Catch & Process Results"
1. Add Trigger ➔ **Device Events ➔ Intent Received**:
   * **Action**: `com.aeidolon.vaultexplorer.action.AUTOMATION_RESULT`
   * **Extra name**: `stream_uri` *(or `result_code`)*
   * **Extra value to match**: `*`
   * **Save to variable**: Create a String variable (e.g. `stream_url`)
2. Add Action ➔ **Notification ➔ Display Dialog**:
   * Text: `Result: {v=stream_url}`
3. *(Optional, for stream mode)* Add Action ➔ **Connectivity ➔ Send Intent**:
   * **Target**: `Activity`
   * **Action**: `android.intent.action.VIEW`
   * **Data**: `{v=stream_url}`
   * **MIME Type**: `*/*` *(or `application/pdf`, `image/jpeg`, `text/plain`)*
   * **Flags**: `FLAG_GRANT_READ_URI_PERMISSION` *(or value `1`)*

---

### Tasker Setup

1. Add action ➔ **System ➔ Send Intent**:
   * **Action**: `com.aeidolon.vaultexplorer.action.EXPORT_FILE`
   * **Package**: `com.aeidolon.vaultexplorer`
   * **Class**: `com.aeidolon.vaultexplorer.automation.VaultAutomationReceiver`
   * **Target**: `Broadcast Receiver`
   * **Extra**:
     ```text
     api_token:<YOUR_TOKEN>
     vault_uri:<YOUR_VAULT_URI>
     vault_path:document.pdf
     stream_mode:true
     ```
2. Create a Profile with **Event ➔ System ➔ Intent Received**:
   * **Action**: `com.aeidolon.vaultexplorer.action.AUTOMATION_RESULT`
   * In the linked task, read `%stream_uri`, `%result_code`, or `%result_message`.

---

### Zero-Disk Decrypted Data Streaming (CLI & Shell)

Use `stream_mode=true` on `EXPORT_FILE` to stream decrypted files directly into memory-backed file descriptors:

#### Step 1 — Request the stream in PowerShell / Bash:
```bash
adb shell "am broadcast -a com.aeidolon.vaultexplorer.action.EXPORT_FILE -n com.aeidolon.vaultexplorer/.automation.VaultAutomationReceiver --es api_token '<YOUR_TOKEN>' --es vault_uri '<YOUR_VAULT_URI>' --es vault_path 'photos/image.jpg' --ez stream_mode true"

Step 2 — Read or view the stream:

Option A: Open directly in your device's image, video, or PDF viewer:

adb shell "am start -a android.intent.action.VIEW -d '<STREAM_URI>' -t 'image/jpeg' --grant-read-uri-permission" 

Option B: Pipe directly to PC or CLI tools (Termux / Linux):

# Save directly to PC without touching Android flash storage:
adb exec-out content read --uri "<STREAM_URI>" > image.jpg
```
# Or compute hash on-device:
termux-saf-read "<STREAM_URI>" | sha256sum

⚠️ Stream constraints: Stream sessions remain valid for 5 minutes and allow
multiple random-access reads (such as image EXIF parsing followed by pixel
rendering) before expiring. Up to 16 concurrent streams are supported
simultaneously.

Glob Pattern Syntax Reference

The pattern extra uses an offline glob engine with the following syntax:

| Pattern         | Matches                                                    |
| :-------------- | :--------------------------------------------------------- |
| `*`             | Any characters within a single directory level (no `/`)    |
| `**`            | Any characters including path separators (cross-directory) |
| `?`             | Exactly one character (not `/`)                            |
| `[a-z]`         | Any character in a range                                   |
| `[!a-z]`        | Any character **not** in a range                           |
| `{jpg,png,gif}` | Any of the comma-separated alternatives                    |

Pattern matching is case-insensitive by default. Examples:

  - *.pdf — all PDFs in the immediate folder
  - **/*.pdf — all PDFs in the folder and all subdirectories
  - REPORT_202[4-9]_*.xlsx — spreadsheets from 2024–2029
  - {IMG,VID}_*.{jpg,mp4} — camera files with standard naming

## 7. OEM Background Service Survival

For device-specific instructions on keeping the background foreground service
alive on Samsung, Xiaomi, OnePlus, and Pixel devices, see the OEM Setup Guide.

## 8. Important Notes & Gotchas

  - Windows / PowerShell Quoting: When passing vault URIs containing parentheses
    (e.g. primary%3Avault%20(1)) through adb shell, enclose the entire argument
    string in single quotes (e.g. adb shell "am broadcast ... --es vault_uri
    'content://...'"). Otherwise, PowerShell will strip the quotes and Android's
    shell will crash with an unexpected ( syntax error.
  - File Paths: source_path/dest_path accept either a real absolute filesystem
    path (e.g. /storage/emulated/0/...) or a content:// SAF URI. The SAF form
    only works if VaultExplorer already holds a persisted permission grant for
    that exact URI. When you don't already have such a grant, a raw filesystem
    path is simpler and always works.
  - Tiers: IMPORT_FILE, EXPORT_FILE, IMPORT_FOLDER, and EXPORT_FOLDER all
    require the Full automation tier. Lifecycle only permits UNLOCK_VAULT and
    LOCK_VAULT. TAKE_PHOTO, START_RECORDING, and STOP_RECORDING require Full
    tier and the separate Allow camera capture switch -- see Section 1.
  - Camera actions are genuinely silent: TAKE_PHOTO shows nothing on screen at
    all -- no notification, no shutter UI. START_RECORDING/STOP_RECORDING do
    show a persistent notification while recording (Android requires this for
    any app using the camera in the background), with its own manual Stop
    button.
  - Folder syncs are best-effort: IMPORT_FOLDER/EXPORT_FOLDER don't abort on the
    first failed file -- check for result_code == "PARTIAL" if you need to know
    whether everything actually made it across.
  - Stream Mode vs SAF Mounting: Zero-Disk Decrypted Streams (stream_mode=true)
    provide ephemeral, read-only in-memory streams ideal for viewers, CLI pipes,
    and exports. For interactive 2-way text/code editing where changes must save
    back to the vault, use VaultExplorer's DocumentsProvider mount instead.
  - Token Invalidation: Regenerating your API token in VaultExplorer immediately
    invalidates existing tasks until updated.
  - USB Storage: Automation is currently not supported on hardware USB
    OTG-mounted drives.

