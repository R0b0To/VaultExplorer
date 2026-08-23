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
Imports a file from the host filesystem directly into the encrypted vault. Requires the **Full** tier and an unlocked vault.

- **Action**: `com.aeidolon.vaultexplorer.action.IMPORT_FILE`
- **Extras**:
  - `api_token` *(String, required)*
  - `vault_uri` *(String, required)*
  - `source_path` *(String, required)*: Either an absolute path on the device (e.g. `/storage/emulated/0/DCIM/Camera/IMG_001.jpg`), or a `content://` SAF URI (see the SAF note below).
  - `vault_path` *(String, required)*: Relative destination path in the vault (e.g. `Photos/IMG_001.jpg` or `/Photos/IMG_001.jpg`). Any missing parent folders inside the vault are created automatically.
  - `delete_source` *(Boolean, optional)*: If `true`, wipes `source_path` upon successful import. For a raw filesystem path this is a secure overwrite-then-delete; for a `content://` source it's a normal provider delete (most SAF providers, especially cloud ones, don't expose local bytes to overwrite).

---

### `EXPORT_FILE`
Exports a decrypted file from the vault to the host filesystem. Requires the **Full** tier and an unlocked vault.

- **Action**: `com.aeidolon.vaultexplorer.action.EXPORT_FILE`
- **Extras**:
  - `api_token` *(String, required)*
  - `vault_uri` *(String, required)*
  - `vault_path` *(String, required)*: Relative path inside the vault to read.
  - `dest_path` *(String, required)*: Either an absolute destination *file* path on the host filesystem, or a `content://` SAF *tree* (folder) URI to create the file inside -- see the SAF note below for why the two forms differ.

---

### `IMPORT_FOLDER`
Recursively imports an entire folder (and everything inside it) into the vault. Requires the **Full** tier and an unlocked vault.

- **Action**: `com.aeidolon.vaultexplorer.action.IMPORT_FOLDER`
- **Extras**:
  - `api_token` *(String, required)*
  - `vault_uri` *(String, required)*
  - `source_path` *(String, required)*: Absolute folder path on the device, or a `content://` SAF *tree* URI -- see the SAF note below.
  - `vault_path` *(String, optional)*: Destination folder inside the vault. Omit, or leave empty, to import into the vault root.
  - `delete_source` *(Boolean, optional)*: Same semantics as `IMPORT_FILE`'s `delete_source`, applied per file.

One file failing doesn't abort the rest -- it's best-effort, so a nightly sync profile doesn't stop cold on one bad file. Check `result_code`/`result_message` (see `PARTIAL` below) to see whether anything failed.

---

### `EXPORT_FOLDER`
Recursively exports a vault folder (and everything inside it) out to the host filesystem. Requires the **Full** tier and an unlocked vault.

- **Action**: `com.aeidolon.vaultexplorer.action.EXPORT_FOLDER`
- **Extras**:
  - `api_token` *(String, required)*
  - `vault_uri` *(String, required)*
  - `vault_path` *(String, optional)*: Source folder inside the vault. Omit, or leave empty, to export the whole vault.
  - `dest_path` *(String, required)*: Absolute destination folder path on the device, or a `content://` SAF tree URI. Created automatically if it doesn't exist yet.

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
    - `PARTIAL` *(`IMPORT_FOLDER` / `EXPORT_FOLDER` only)*: The folder operation finished, but at least one file failed -- `result_message` gives the ok/failed counts.
    - `PERMISSION_DENIED` *(`TAKE_PHOTO` / `START_RECORDING` only)*: Camera/microphone permission isn't granted on-device. Automation can't trigger the system permission prompt itself -- open VaultExplorer's own camera screen once to grant it, then retry.
    - `CAMERA_UNAVAILABLE` *(`TAKE_PHOTO` / `START_RECORDING` only)*: The camera couldn't be opened -- commonly because something else (e.g. VaultExplorer's own in-app camera screen) already has it open, or a hardware/driver error.
    - `BUSY` *(`START_RECORDING` only)*: An automation recording is already in progress.
    - `NOT_RECORDING` *(`STOP_RECORDING` only)*: Nothing is currently recording, or the in-progress recording belongs to a different vault than the one named in `vault_uri`.
  - `result_message` *(String)*: Human-readable message or error details.
  - `duration_ms` *(Long, only present on a successful `STOP_RECORDING`)*: Length of the recording that was just saved, in milliseconds.

> 💡 **Tip**: If your automation tool receives **no response at all**, verify your `api_token`. Requests with invalid or missing tokens are discarded silently to prevent token brute-forcing.

---

## 5. Typical Automation Workflow: Camera / File Sync

A standard task chain unlocks the vault, imports the file (with optional secure wipe of the original), and locks the vault:

[Trigger] (e.g., New photo taken / Schedule)

├─► Send Broadcast: UNLOCK_VAULT

(Wait for AUTOMATION_RESULT: result_code == "OK" or 1s delay)

├─► Send Broadcast: IMPORT_FILE (source_path, vault_path, delete_source=true)

(Wait for AUTOMATION_RESULT: result_code == "OK")


└─► Send Broadcast: LOCK_VAULT


### Variant: whole-folder sync

Same shape, just swap `IMPORT_FILE` for `IMPORT_FOLDER` (with `delete_source=true` if you want the originals wiped after a successful sync) to mirror an entire camera roll or download folder into the vault in one task, instead of chaining one `IMPORT_FILE` per photo.

### Variant: direct capture (no separate camera app involved)

Skips the OS camera / gallery step entirely -- VaultExplorer takes the photo or video itself, straight into the vault. Requires the **Allow camera capture** switch from Section 1.

[Trigger] (e.g., NFC tag, geofence, a specific charger plugged in)

├─► Send Broadcast: UNLOCK_VAULT

(Wait for AUTOMATION_RESULT: result_code == "OK")

├─► Send Broadcast: TAKE_PHOTO (camera_facing=front)

(Wait for AUTOMATION_RESULT)

└─► Send Broadcast: LOCK_VAULT

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

---

## 7. Important Notes & Gotchas

- **File Paths**: `source_path`/`dest_path` (on `IMPORT_FILE`, `EXPORT_FILE`, `IMPORT_FOLDER`, `EXPORT_FOLDER`) accept either a real absolute filesystem path (e.g. `/storage/emulated/0/...`) or a `content://` SAF URI. The SAF form only works if VaultExplorer *already holds a persisted permission grant* for that exact URI -- typically because you picked that same folder through one of VaultExplorer's own folder pickers at some point. Android has no mechanism for a broadcast Intent to hand over a fresh grant for a URI the app has never seen before, so an arbitrary `content://` value from a task you've never connected to VaultExplorer will just fail (`INVALID_ARGS`/`ERROR`), not silently do nothing. When you don't already have such a grant, a raw filesystem path is simpler and always works.
- **Tiers**: `IMPORT_FILE`, `EXPORT_FILE`, `IMPORT_FOLDER`, and `EXPORT_FOLDER` all require the **Full** automation tier. `Lifecycle` only permits `UNLOCK_VAULT` and `LOCK_VAULT`. `TAKE_PHOTO`, `START_RECORDING`, and `STOP_RECORDING` require Full tier *and* the separate **Allow camera capture** switch -- see Section 1.
- **Camera actions are genuinely silent**: `TAKE_PHOTO` shows nothing on screen at all -- no notification, no shutter UI. `START_RECORDING`/`STOP_RECORDING` do show a persistent notification while recording (Android requires this for any app using the camera in the background), with its own manual Stop button. Neither depends on VaultExplorer's app UI being open; both work from a cold start as long as the vault has a stored automation password (see `UNLOCK_VAULT`) and camera/microphone permission was already granted once from within the app.
- **Folder syncs are best-effort**: `IMPORT_FOLDER`/`EXPORT_FOLDER` don't abort on the first failed file -- check for `result_code == "PARTIAL"` if you need to know whether everything actually made it across.
- **Token Invalidation**: Regenerating your API token in VaultExplorer immediately invalidates existing tasks until updated.
- **USB Storage**: Automation is currently not supported on hardware USB OTG-mounted drives.