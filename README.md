# VaultExplorer

[![Android](https://img.shields.io/badge/Android-8.0%2B%20%28API%2026%2B%29-3DDC84?style=flat&logo=android)](https://developer.android.com)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Donate](https://img.shields.io/badge/Ko--Fi-Support%20Project-FF5E5B?style=flat&logo=ko-fi)](https://ko-fi.com/K3K2ND3Y8)

> Mount, browse, and manage encrypted containers and vaults on Android — no PC required.

VaultExplorer opens VeraCrypt, LUKS, BitLocker, VHD/VHDX, Cryptomator, gocryptfs, and CryFS volumes directly on your device. A native C++ engine decrypts and re-encrypts everything in memory — no unencrypted temp files are ever written to disk, and the app has no internet permission at all.

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
| **Cryptomator** | Vault formats 7 & 8 |
| **gocryptfs** | AES-256-GCM or XChaCha20-Poly1305 |
| **CryFS** | Format 0.10+, AES or XChaCha20-Poly1305 |

Filesystems read/written inside containers: FAT12/16/32, exFAT, NTFS, and ext2/3/4.

---

## Features

- **File explorer** — list, grid, and masonry views, breadcrumbs, search, instant folder sizes
- **Built-in viewers** — photos, video/audio (subtitles, speed control), PDF (with search), HTML, and a text/code editor, plus ZIP browsing — all streamed straight from the encrypted volume
- **Vault camera** — shoot photos and video directly into a container
- **Item vault** — passwords, cards, bank accounts, notes, identities, and licenses stored as encrypted entries, like a password manager built into the container
- **Cloud access** — open containers straight from Google Drive or pCloud, or from any compatible bridge app (e.g. [RSAF](https://github.com/chenxiaolong/RSAF) or [Round-Sync](https://github.com/newhinton/Round-Sync)) for WebDAV, S3, Dropbox, and more — the app itself never touches the network
- **Open in other apps** — expose an unlocked container, or just one subfolder, so other apps can open and save files in it directly
- **USB OTG** — read and write USB drives without root
- **Create & format** new volumes on device storage or a USB drive
- **Up to 8 volumes** mounted at once

### Tools tab

- **Keyfile & Passphrase Generator** — Diceware passphrases, custom passwords, high-entropy keyfiles
- **Encrypt / Decrypt Files** — protect individual files without a full container
- **Hash Verifier** — check large files against MD5/SHA checksums
- **Vault Sync** — compare two vaults, copy over what's missing or newer
- **Storage Analyzer** & **Duplicate Finder** — see what's using space and clear out byte-identical duplicates
- **Split & Join** — split a container into chunks, or rejoin them
- **Check & Repair** — diagnose header or filesystem issues

---

## Security & privacy

- No `INTERNET` permission — the app cannot make a network request, period
- Nothing unencrypted ever touches disk; decryption and re-encryption happen only in memory
- Master lock via password, biometric, or pattern, with exponential lockout backoff that survives force-kills
- Optional hardware-backed key caching (Android Keystore, AES-256-GCM) for instant re-unlock
- Screenshots and task-switcher previews are blocked; clipboard is cleared automatically on focus
- **Mask Mode** — disguise the app as a working zip-archive browser; hold the title for 3 seconds to reach your real vault

---

## Install

Download the APK for your device's architecture (arm64, armeabi, or x64) from [Releases](https://github.com/R0b0To/VaultExplorer/releases). Requires Android 8.0 (API 26) or newer.

### Build from source

```bash
git clone https://github.com/R0b0To/VaultExplorer.git
cd VaultExplorer
flutter pub get
flutter build apk --release
```

Needs Flutter 3.12+, Android SDK 26+, the NDK, and CMake 3.18+. CMake fetches and compiles all native C++ dependencies automatically — see [NOTICE.md](NOTICE.md) for exact versions and licenses.

---

## License

GPLv3 — see [LICENSE](LICENSE).

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/K3K2ND3Y8)