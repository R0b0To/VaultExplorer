# VaultExplorer Automation Setup Guide (Tasker & MacroDroid)

VaultExplorer supports background automation via Android Broadcast Intents. You can unlock/lock vaults, import/export files, and securely wipe plaintext source files without opening the UI.

Every intent is sent as a **Broadcast** to VaultExplorer's receiver, which returns an `AUTOMATION_RESULT` broadcast with status and diagnostics.

---

## 1. Enable Automation for Your Vault

1. Open **VaultExplorer** and navigate to your vault's settings (or tap the vault card settings icon).
2. Tap **Automation**.
3. Under **Automation access**, select your desired tier:
   - **Off**: Automation cannot access this vault.
   - **Unlock / lock only (Lifecycle)**: Permits `UNLOCK_VAULT` and `LOCK_VAULT` actions.
   - **Unlock / lock + file import-export (Full)**: Permits all actions including `IMPORT_FILE` and `EXPORT_FILE`.
4. *(Optional)* **Automation Password**: Set a password if you want `UNLOCK_VAULT` to mount unattended without requiring the automation task to supply the password in plaintext.
5. Copy your **API Token** and **Vault URI** displayed on the screen.

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
  - `source_path` *(String, required)*: Absolute path on the device (e.g. `/storage/emulated/0/DCIM/Camera/IMG_001.jpg`). *Do not use `content://` URIs.*
  - `vault_path` *(String, required)*: Relative destination path in the vault (e.g. `Photos/IMG_001.jpg` or `/Photos/IMG_001.jpg`).
  - `delete_source` *(Boolean, optional)*: If `true`, securely overwrites and wipes `source_path` upon successful import.

---

### `EXPORT_FILE`
Exports a decrypted file from the vault to the host filesystem. Requires the **Full** tier and an unlocked vault.

- **Action**: `com.aeidolon.vaultexplorer.action.EXPORT_FILE`
- **Extras**:
  - `api_token` *(String, required)*
  - `vault_uri` *(String, required)*
  - `vault_path` *(String, required)*: Relative path inside the vault to read.
  - `dest_path` *(String, required)*: Absolute destination path on the host filesystem.

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
    - `FORBIDDEN`: Action not allowed by the vault's automation tier.
    - `INVALID_ARGS`: Missing or malformed parameters/paths.
    - `ERROR`: General failure or I/O exception.
  - `result_message` *(String)*: Human-readable message or error details.

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

- **File Paths**: `source_path` and `dest_path` must be real absolute filesystem paths (e.g. `/storage/emulated/0/...`), not SAF `content://` URIs.
- **Tiers**: `IMPORT_FILE` and `EXPORT_FILE` require the **Full** automation tier. `Lifecycle` only permits `UNLOCK_VAULT` and `LOCK_VAULT`.
- **Token Invalidation**: Regenerating your API token in VaultExplorer immediately invalidates existing tasks until updated.
- **USB Storage**: Automation is currently not supported on hardware USB OTG-mounted drives.
