***

# VaultExplorer [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/K3K2ND3Y8)

**An Android file manager for encrypted containers and vaults — no PC required.**

Mount, browse, and manage VeraCrypt, LUKS, Cryptomator, and gocryptfs volumes directly on your Android device. Built with Flutter and a custom cryptographic engine (mbedTLS + FatFs + NTFS-3G + libext2fs), everything is decrypted and re-encrypted on-device with no plaintext temporary files written to disk.

---

## Features

### Supported Formats & Encryption
- **Block-Level Containers**: VeraCrypt (`.hc`) and native LUKS1 / LUKS2 containers with format auto-detection.
- **Directory-Based Vaults**: Cryptomator (format 7/8) and gocryptfs directories. Compatible with desktop and official mobile clients.
- **Robust Cipher Support**: AES-256-XTS, Serpent, Twofish, Camellia, and Kuznyechik, including VeraCrypt's cascaded options (15 total combinations).
- **Key Derivation (KDF)**: PBKDF2 (SHA-512, SHA-256, Whirlpool, Streebog, BLAKE2s-256) or memory-hard Argon2id.
- **LUKS Flexibility**: Works with AES, Serpent, Twofish, Camellia, or Kuznyechik in `xts-plain64` mode using PBKDF2 or Argon2id/Argon2i keyslots.
- **Parallel Auto-Detect**: Tests cipher/hash combinations in parallel with a live progress indicator, caching successful matches for faster subsequent unlocks.
- **Keyfiles & Hidden Volumes**: Supports password mixing (VeraCrypt) or keyfile-only/passphrase options matching `cryptsetup`. Hidden volumes are resolved during unlock.
- **Multi-Mount**: Open up to 8 containers or directories simultaneously from storage, `content://` providers, or USB OTG.

### Filesystems & Storage
- **Broad File Systems**: Read/write support for FAT32, exFAT, NTFS, and ext2/ext3/ext4 (auto-detected on mount).
- **USB OTG Mounting**: Mount containers directly from external drives without root. Includes partition scanning (MBR/GPT) and instant lock-on-disconnect.
- **Container Creation**: Create new encrypted containers formatted to any supported filesystem.

### File & Password Management
- **Intuitive File Browser**: Breadcrumb navigation, list/grid views, search, filter, and multiple sort orders.
- **Clipboard & Batch Actions**: Batch copy, move, rename, delete, or export with progress tracking and conflict resolution.
- **Built-in Password Manager**: Store and manage encrypted items (passwords, cards, notes, identities). Includes field reveal, secure copy, and favorites.

### Media Viewer & Android Integration
- **Media Playback**: Built-in player for video/audio (supporting `.srt`/`.vtt` subtitles, loop, and speed control) and images (zoom, rotate, slideshows).
- **Android SAF Integration**: Mounted volumes integrate into the system Documents Provider, letting you open files directly in external apps.
- **On-The-Fly Streaming**: Streams data through a proxy file descriptor without writing plaintext files to physical storage.

### Security & Privacy
- **Master Password**: Optional master password with exponential lockout backoff that persists across app force-kills.
- **Biometric & Pattern Unlock**: Secure individual containers using biometrics or patterns, with optional Keystore-backed key storage.
- **Timers**: App-wide and per-container customizable auto-lock timers.
- **Leak Protection**: Screenshot blocking and secure thumbnail caching options (app cache, in-container, or disabled).

---

## Screenshots

<p align="center">
  <img width="250" alt="Screenshot_1" src="https://github.com/user-attachments/assets/2267accb-aae3-4ce6-8fae-bd09bfebd3c1" />
  <img width="250" alt="Screenshot_2" src="https://github.com/user-attachments/assets/a7ac12c5-6481-423d-a930-098ef5da3283" /> 
  <img width="250" alt="Screenshot_3" src="https://github.com/user-attachments/assets/154c1dcf-e448-46ab-ad9d-2d92ad10fbe3" />
</p>

---

## Requirements

- Android 8.0+ (API 26)
- USB OTG support (for USB drive mounting)
- NDK / CMake (for compiling the C++ engine)

---

## Building

```bash
git clone https://github.com/R0b0To/VaultExplorer.git
cd vaultexplorer
flutter pub get
flutter build apk --release
```

Requires Flutter SDK `^3.12.0`, the Android NDK version pinned in `flutter.ndkVersion`, and CMake 3.18+. The C++ engine builds automatically via CMake; mbedTLS, FatFs, NTFS-3G, libext2fs, cJSON, and the VeraCrypt crypto primitives are fetched at build time.

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
  ├── Cryptomator & gocryptfs — directory-based vault backends (metadata/filename decryption)
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

1. **Unlock** — Reads metadata/headers, derives the key (using PBKDF2/Argon2id, auto-detecting parameters if unspecified), and verifies it. For LUKS containers, keyslot metadata is parsed and derived before verifying against the digest.
2. **Mount** — 
   - *Block-Level (VeraCrypt/LUKS)*: FatFs, NTFS-3G, or libext2fs runs over custom disk I/O hooks to decrypt/encrypt individual sectors.
   - *Directory-Level (Cryptomator/gocryptfs)*: Translates and decrypts filenames and file payloads on-the-fly.
3. **Browse** — File operations pass through the virtual file system; plaintext data never touches physical storage.
4. **Stream** — External apps access files via a `ProxyFileDescriptor` connected to the JNI engine.

---

## Limitations

- Android only (utilizes Android JNI and NDK APIs)

---

## License

GPL-3.0 — see [LICENSE](LICENSE).

---

## Acknowledgements

- [VeraCrypt](https://veracrypt.fr), [LUKS / cryptsetup](https://gitlab.com/cryptsetup/cryptsetup), [gocryptfs](https://nuetzlich.net/gocryptfs/) — the encryption standards this app is compatible with
- [Mbed TLS](https://github.com/Mbed-TLS/mbedtls), [ChaN FatFs](http://elm-chan.org/fsw/ff/), [NTFS-3G](https://github.com/tuxera/ntfs-3g), [e2fsprogs / libext2fs](https://github.com/tytso/e2fsprogs), [cJSON](https://github.com/DaveGamble/cJSON) — libraries this app is built on
