# VaultExplorer

[![Android](https://img.shields.io/badge/Android-8.0%2B%20%28API%2026%2B%29-3DDC84?style=flat&logo=android)](https://developer.android.com)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Donate](https://img.shields.io/badge/Ko--Fi-Support%20Project-FF5E5B?style=flat&logo=ko-fi)](https://ko-fi.com/K3K2ND3Y8)

> Mount, browse, and manage encrypted containers and vaults on Android — no PC required.

VaultExplorer opens VeraCrypt, LUKS, BitLocker, VHD/VHDX, Cryptomator, gocryptfs, and CryFS volumes directly on your device. A native C++ engine decrypts and re-encrypts in memory wherever it can, and the app has no internet permission at all. The few operations that need a real scratch file (recording video, exporting, archive work) keep it briefly in the app's private cache and zero-wipe it afterwards.

---

## Screenshots

<p align="center">
  <img width="250" alt="Dashboard" src="https://github.com/user-attachments/assets/1c981b1d-3d98-4b07-a275-fe78c6263815" />
  <img width="250" alt="File Explorer" src="https://github.com/user-attachments/assets/70dd6300-c260-4573-a01a-43e522e6a4e0" />
  <img width="250" alt="Media Viewer" src="https://github.com/user-attachments/assets/19f5f121-80a2-452f-9bad-ad054f5ed306" /> 
  <img width="250" alt="File Explorer" src="https://github.com/user-attachments/assets/9fa0e98d-3183-41ff-a160-8c9972df582d" />
  <img width="250" alt="Media Viewer" src="https://github.com/user-attachments/assets/192a91e3-001b-4b9f-bf95-936201b6814f" /> 
</p>

---

## Supported formats

| Format | Details |
|---|---|
| **VeraCrypt** | Standard & hidden volumes, custom PIM, keyfiles, every cipher/cascade (AES, Serpent, Twofish, Camellia, Kuznyechik), in-place password change |
| **LUKS1 / LUKS2** | `xts-plain64`, PBKDF2 or Argon2id/i, passphrase or keyfile |
| **BitLocker** | Password or 48-digit recovery key, including BitLocker To Go |
| **VHD / VHDX** | Fixed-size and dynamically expanding images that can hold a VeraCrypt, LUKS, or BitLocker volume |
| **Cryptomator** | Vault formats 7 & 8 (SIV_GCM / SIV_CTRMAC) |
| **gocryptfs** | Format v2, AES-256-GCM or XChaCha20-Poly1305 |
| **CryFS** | Format 0.10+, AES or XChaCha20-Poly1305 |

Filesystems read/written inside containers: FAT12/16/32, exFAT, NTFS, and ext2/3/4.

---

## Features

- **File explorer** — detailed list, columned list, grid (square, landscape, or portrait), and masonry views with folder thumbnail previews, natural sort order, breadcrumbs, search, instant folder sizes, and a per-container customizable toolbar. A sidebar drawer gives quick access to your storage locations and vault actions, and the dashboard shows free/total storage for each container without unlocking it
- **Built-in viewers** — photos, video/audio (subtitles, speed control, seek-bar scrub previews, brightness and volume swipe gestures), PDF (with search), HTML, Markdown, and a text/code editor — all streamed straight from the encrypted volume. APKs stored in a vault show their icon and can be handed to the system installer
- **Image editor** — crop, rotate, freehand draw, add text labels, and a redaction/blackout box for photos inside a vault, without ever writing a plaintext temp file
- **Archive browser** — open ZIP, 7-Zip, RAR (RAR4/RAR5), TAR, gzip, bzip2, xz, and zstd archives in place (including password-protected ZIP/RAR5), extract individual entries or everything, and create new ZIP (with optional AES-256 password), 7-Zip, TAR (plain, gzip, xz, zstd, or lzma), ISO9660, or CPIO archives — with image thumbnails inside archives, powered by a native libarchive engine, both inside a vault and for archives on regular device storage
- **Vault camera** — shoot photos and video directly into a container, with optional background recording that keeps going after the screen turns off or the app is minimized. An optional Quick Settings tile and home screen shortcut open the camera in one tap (you still pick and unlock a vault before anything is saved); turn them on in Settings
- **Item vault** — passwords, cards, bank accounts, notes, identities, and licenses stored as encrypted entries, like a password manager built into the container
- **Cloud & external storage** — open containers straight from Google Drive or pCloud, or from any compatible bridge app (e.g. [RSAF](https://github.com/chenxiaolong/RSAF) or [Round-Sync](https://github.com/newhinton/Round-Sync)) for WebDAV, S3, Dropbox, and more — the app itself never touches the network. Local storage, SD cards, and other document providers can also be added as storage locations and browsed with the same file manager
- **Open in other apps** — expose an unlocked container, or just one subfolder, so other apps can open and save files in it directly, or share files straight from the file manager through Android's Share menu; an optional background service keeps a vault mounted so this keeps working after you leave VaultExplorer
- **Share Sheet Integration** — let other apps hand files to VaultExplorer through Android's Share menu, straight into a folder you pick inside a vault. Off by default; turn it on in Settings
- **Automation (Beta)** — a local broadcast-intent API lets Tasker or MacroDroid unlock/lock a vault, import or export individual files or whole folders (glob-filterable), securely wipe files, trigger the vault camera (photo or start/stop video) headlessly, and fire an emergency lock or purge — all with no UI interaction required. Off by default; each vault opts in separately to a permission tier and is gated by an API token, and camera capture needs its own explicit opt-in on top of that. See [`docs/vaultexplorer-automation-setup.md`](docs/vaultexplorer-automation-setup.md) for setup
- **Auto-sync** — keep a vault or folder in sync with with another folder on your device or on a document provider — when the vault unlocks and, optionally, while it stays open — as a one-way backup, a one-way import, or two-way. Rules live inside the vault (encrypted), conflicts keep both versions by default, and if you sync deletions they pause automatically when a folder looks unexpectedly empty
- **Emergency panic & duress** — three purge tiers (lock vaults and forget remembered passwords; also wipe credentials, master lock, and settings; or also shred the app's own storage and request uninstall) that never touch your container files. Trigger them from a Quick Settings tile, a PanicKit app such as Ripple or Wasted, an automation broadcast, an armed one-shot reboot trigger, or by entering a separate duress PIN, pattern, or password on the lock screen
- **USB OTG** — read and write USB drives without root
- **Create & format** new volumes on device storage or a USB drive
- **Composite containers** — spread a VeraCrypt-format volume across several ordinary photo/video/audio/document files instead of one container file. Each carrier's data is appended past its real content as high-entropy "growth" (5%–20%+, your choice of stealth vs. capacity), indistinguishable from normal file noise, and every carrier has to be present to unlock. Create or unlock one from the dashboard like any other container, or from the Tools tab
- **Up to 8 volumes** mounted at once
- **Themes & settings** — Material You dynamic colors and a pure-black theme, a categorized settings hub, and settings export/import (preferences and file manager layout only; never passwords, keys, or your container list)

### Tools tab

- **Keyfile & Passphrase Generator** — Diceware passphrases, custom passwords, high-entropy keyfiles
- **Encrypt / Decrypt Files** — protect individual files without a full container
- **Hash Verifier** — check large files against MD5/SHA checksums
- **Vault Sync** — compare two folders — in vaults, on device storage, or on a document provider — and copy over what's missing or newer
- **Storage Analyzer** & **Duplicate Finder** — see what's using space and clear out byte-identical duplicates
- **Split & Join** — split a container into chunks, or rejoin them
- **Composite Container** — embed and mount an encrypted vault across multiple media files (see Features above)
- **Check & Repair** — diagnose header or filesystem issues
- **Header Backup** — back up a container's header (or a folder vault's config file) to an external file, and restore from it later

---

## Security & privacy

- No `INTERNET` permission — the app cannot make a network request, period
- Decryption and re-encryption happen in memory; opened files are streamed straight to the built-in viewers. Where an operation genuinely needs a plaintext scratch file (video recording, exports, archives, the file encrypt/decrypt tool), it stays in the app's private cache, is overwritten with zeros and deleted when done, and anything a crash leaves behind is wiped at next launch
- Master lock via password, PIN, pattern, or biometric, with exponential lockout backoff that survives force-kills. Removing the master password requires the master password itself (biometrics can't bypass it), saved credentials can never be revealed in plain text, and PIM values are obfuscated during unlock
- Optional key caching in the Android Keystore (AES-GCM, hardware-backed where the device supports it) for instant re-unlock
- Task-switcher previews are blocked while the app is in the background, and the screen is blanked the instant the app is backgrounded so a stale unlocked frame can't flash on resume. Blocking screenshots (`FLAG_SECURE`) is an optional setting, off by default
- Copying a password from the Item Vault marks the clipboard entry sensitive on Android 13+ and auto-clears it 30 seconds later if left untouched; the app also sanitizes corrupted clipboard data from other apps on window focus
- Android backup is disabled for the app, so nothing it stores is copied to a cloud backup
- **Mask Mode** — disguise the app as a genuinely usable local file manager for your device's real storage (browse, open, and edit files, including archives — none of it touches any vault or encryption code); hold the title for 2 seconds to reach your real vault

See [PRIVACY_POLICY.md](PRIVACY_POLICY.md) for exactly what the app accesses and what leaves your device only at your request.

---

## Install

Download the APK for your device's architecture (arm64, armeabi, or x64) from [Releases](https://github.com/R0b0To/VaultExplorer/releases). Requires Android 8.0 (API 26) or newer.

### Build from source

```bash
git clone --recurse-submodules https://github.com/R0b0To/VaultExplorer.git
cd VaultExplorer
.flutter/bin/flutter pub get
.flutter/bin/flutter build apk --release
```

Flutter itself is vendored as a pinned git submodule (`.flutter/`) rather than something you install separately — if you already cloned without `--recurse-submodules`, run `git submodule update --init` first. You'll also need the Android SDK (26+), Java 21, and CMake 3.18+; the NDK (pinned to r28c) is installed automatically via Gradle. CMake fetches and compiles all native C++ dependencies automatically — see [NOTICE.md](NOTICE.md) for exact versions and licenses.


---

## License

GPLv3 — see [LICENSE](LICENSE).

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/K3K2ND3Y8)