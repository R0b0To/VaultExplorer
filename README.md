# VaultExplorer [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/K3K2ND3Y8)

**A native Android file manager for encrypted containers — no PC required.**

Mount, browse, and manage VeraCrypt and LUKS encrypted volumes directly on your Android device. Built with Flutter and a custom C++ crypto engine (mbedTLS + FatFs + NTFS-3G + libext2fs) — everything is decrypted and re-encrypted on-device, with zero plaintext temp files written to disk.

---

## Features

### Encryption
- **VeraCrypt** (`.hc`) and native **LUKS1 / LUKS2** containers — format is auto-detected, no need to specify which
- **AES-256-XTS**, plus Serpent, Twofish, Camellia, and Kuznyechik, including VeraCrypt's cascaded combinations (15 cipher/cascade options total)
- Key derivation via PBKDF2 (SHA-512, SHA-256, Whirlpool, Streebog, BLAKE2s-256) or the memory-hard **Argon2id**
- LUKS1/LUKS2 support AES, Serpent, Twofish, Camellia, or Kuznyechik in `xts-plain64` mode, with PBKDF2 or Argon2id/Argon2i keyslots
- **Auto-detect** tries every cipher/hash combo in parallel with a live progress indicator, and remembers the match for faster future unlocks
- **Keyfiles** — additive password mixing (VeraCrypt) or direct passphrase replacement (LUKS), matching `cryptsetup --key-file`
- **Hidden volumes** are detected automatically at unlock, no extra step needed
- Configurable **PIM**
- Mount up to **8 containers** at once, from files, `content://` documents, or USB drives

### Filesystems
- Read/write **FAT32, exFAT, NTFS, ext2/ext3/ext4** — auto-detected on mount
- Create new containers in any of the above

### USB Drives
- Mount VeraCrypt/LUKS volumes on a USB OTG drive, no root or PC needed
- Automatic MBR/GPT partition scanning; remembers the matched partition for faster reconnects
- Detects disconnects instantly and locks the container

### File Management
- Breadcrumb navigation, list and grid views with live thumbnails
- Batch copy/move/delete/rename/export with progress tracking and conflict resolution
- Cross-container clipboard, device import/export, search & filter, multiple sort orders

### Password Manager
- Encrypted vault items: passwords, cards, identities, notes, bank accounts, software licenses
- Field-level reveal/hide, copy-to-clipboard, favourites

### Media Viewer
- Images (zoom, rotate) and video/audio (`.srt`/`.vtt` subtitles)
- Slideshow, shuffle, folder filtering, playback speed, seek, loop/advance

### Android Integration
- Mounted containers appear in the system **Documents Provider**
- Proxy file streaming — no plaintext intermediary on disk
- Open files in external apps, with remembered per-extension preferences

### Security
- Optional **master password** with exponential lockout backoff (persists across force-kills)
- **Biometric** or **pattern** unlock per container, plus optional Keystore-cached derived keys
- App-wide and per-container auto-lock timers
- Configurable thumbnail caching (app cache, in-container, or disabled)
- Screenshot blocking

### Screenshots

<p align="center">
  <img width="250" alt="Screenshot_1783428063" src="https://github.com/user-attachments/assets/2267accb-aae3-4ce6-8fae-bd09bfebd3c1" />
  <img width="250" alt="Screenshot_1783428136" src="https://github.com/user-attachments/assets/a7ac12c5-6481-423d-a930-098ef5da3283" /> 
   <img width="250" alt="Screenshot_1783428136" src="https://github.com/user-attachments/assets/154c1dcf-e448-46ab-ad9d-2d92ad10fbe3" />
</p>

---

## Requirements

- Android 8.0+ (API 26)
- USB OTG support for USB drive mounting
- NDK / CMake (for building)

---

## Building

```bash
git clone https://github.com/R0b0To/VaultExplorer.git
cd vaultexplorer
flutter pub get
flutter build apk --release
```

Requires Flutter SDK `^3.12.0`, the Android NDK version pinned in `flutter.ndkVersion`, and CMake 3.18+. The C++ engine builds automatically via CMake; mbedTLS, FatFs, NTFS-3G, libext2fs, cJSON, and the VeraCrypt crypto primitives are fetched at build time — no manual setup needed.

---

## Architecture

```
Flutter (Dart)
  ├── Dashboard, File Browser, Vault Items, Media Viewer, Unlock, Settings
  └── VaultExplorerApi — MethodChannel bridge to Kotlin

Android (Kotlin)
  ├── MainActivity — MethodChannel handler, SAF pickers, import/export
  ├── ContainerSessionRegistry / ContainerFileSystem — session registry & locking
  ├── ContainerEngine — format-neutral façade over the JNI implementation
  ├── UsbMassStorageDevice / UsbBlockBridge — USB Mass Storage client
  ├── UnlockProgressBridge — pushes auto-detect progress to Dart
  └── ContainerDocumentsProvider — Documents Provider (ContentProvider)

C++ (NDK)
  ├── vaultexplorer.cpp — orchestration, crypto sessions, disk hooks, JNI exports
  ├── session_prepare.cpp — VeraCrypt/LUKS session establishment
  ├── container_create.cpp — new-container/hidden-volume creation
  ├── {fat,ntfs,ext}_backend — filesystem-specific helpers
  ├── crypto/cascade, cipher_shim, kdf_table, keyfile_mixing, luks_header
  ├── mbedTLS, ChaN FatFs, NTFS-3G, libext2fs, cJSON
```

---

## Dependencies

| Package | Purpose |
|---|---|
| `path_provider` | App document/cache directories |
| `video_player` / `fvp` | Video/audio playback (FFmpeg-backed) |
| `local_auth` | Biometric unlock |
| `flutter_secure_storage` | Passwords, pattern hashes, cached derived keys |
| `encrypt` / `pointycastle` | Thumbnail cache encryption, pattern hashing |
| `url_launcher` | External links |
| `wakelock_plus` | Keep screen on during playback |
| `package_info_plus` | App version display |
| `vector_math` | Video zoom/pan gesture math |
| `mbedTLS 3.6.0` | AES-XTS, PBKDF2 (C++) |
| `ChaN FatFs` | FAT32/exFAT (C++) |
| `NTFS-3G` | NTFS + `mkntfs` formatter (C++) |
| `e2fsprogs` (`libext2fs`) | ext2/ext3/ext4 (C++) |
| `cJSON` | LUKS2 JSON metadata (C++) |

Container/keyfile picking, video thumbnails, and biometric key storage are native Kotlin (SAF intents, `MediaMetadataRetriever`, Android Keystore) rather than Flutter plugins.

VeraCrypt crypto primitives (Serpent, Twofish, Camellia, Kuznyechik, Whirlpool, Streebog, BLAKE2s, Argon2id) are fetched by CMake from the pinned VeraCrypt 1.26.29 release.

---

## How It Works

1. **Unlock** — Read the header, derive the key (PBKDF2/Argon2id, auto-detecting cipher/hash if unspecified), decrypt to recover the master key. LUKS containers instead parse keyslot metadata, derive and AF-merge each keyslot, and verify against the stored digest.
2. **Mount** — FatFs, NTFS-3G, or libext2fs runs over custom disk I/O hooks that transparently decrypt/encrypt every sector using the recovered key.
3. **Browse** — File operations go through the matching filesystem driver; plaintext never touches device storage.
4. **Stream** — External apps read/write via a `ProxyFileDescriptor` straight through the JNI engine.

---

## Limitations

- Android only (uses Android JNI / NDK APIs)

---

## License

GPL-3.0 — see [LICENSE](LICENSE).

---

## Acknowledgements

- [VeraCrypt](https://veracrypt.fr), [LUKS / cryptsetup](https://gitlab.com/cryptsetup/cryptsetup) — the encryption standards this app is compatible with
- [Mbed TLS](https://github.com/Mbed-TLS/mbedtls), [ChaN FatFs](http://elm-chan.org/fsw/ff/), [NTFS-3G](https://github.com/tuxera/ntfs-3g), [e2fsprogs / libext2fs](https://github.com/tytso/e2fsprogs), [cJSON](https://github.com/DaveGamble/cJSON) — libraries this app is built on
