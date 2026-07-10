# VaultExplorer [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/K3K2ND3Y8)

**A native Android file manager for VeraCrypt encrypted containers — no PC required.**

VaultExplorer lets you mount, browse, and manage VeraCrypt volumes directly on your Android device. Built with Flutter and a custom C++ crypto engine (mbedTLS + FatFs), it decrypts and re-encrypts data fully on-device with zero temporary plaintext files on device storage.

---

## Features

### Encryption & Compatibility
- Full **AES-256-XTS** decryption and encryption matching the VeraCrypt standard
- Additional ciphers and cascades: **Serpent**, **Twofish**, and the cascaded combinations VeraCrypt supports (AES-Twofish, Serpent-AES, Twofish-Serpent, AES-Twofish-Serpent, Serpent-Twofish-AES)
- Multiple hash algorithms for key derivation: **SHA-512**, SHA-256, Whirlpool, Streebog, and BLAKE2s-256
- **Auto-detect mode** tries every cipher/hash combination in parallel when the algorithm isn't known, with a live "trying combination X of Y" progress indicator and the ability to cancel mid-search
- Once a container has been unlocked, its matched cipher/hash is remembered so the next unlock skips straight to the right combination
- **Keyfile support** — mix one or more files into the password using VeraCrypt's own pool-mixing algorithm, including keyfile-only (passwordless) volumes
- **Hidden volume** detection — a hidden volume nested inside an outer container is discovered automatically at unlock time, with no separate "mount hidden volume" step
- **PBKDF2** key derivation with configurable PIM support
- Compatible with containers created by the desktop VeraCrypt application
- Supports both **FAT32** and **exFAT** formatted volumes
- Create new VeraCrypt containers directly from the app
- Up to **8 containers** can be mounted simultaneously, from container files, `content://` documents, or USB mass-storage devices

### USB Drive Support
- Mount VeraCrypt volumes living on a USB OTG flash drive or external SSD — no root, no PC
- Automatic MBR/GPT partition scanning to locate the right partition, with the previously-matched partition remembered for faster reconnects
- Detects physical USB disconnects instantly and cleanly locks the affected container

### File Management
- Browse directories with breadcrumb navigation
- **List view** and **gallery/grid view** with live thumbnails (pinch to change grid density)
- Multi-select batch operations: copy, move, delete, rename, export — with a persistent progress sheet and per-item conflict resolution (skip / overwrite / keep both)
- **Cross-container clipboard** — copy or move files between two mounted volumes
- Import files and entire folder trees from device storage; export back out
- Search and filter (images/video/audio/documents) within the current directory
- Sort by name, size, type, or date

### Password Manager (Vault Items)
- Store passwords, payment cards, identities, secure notes, bank accounts, and software licenses as individually encrypted items inside the container
- Field-level reveal/hide and copy-to-clipboard for sensitive values
- Favourites and per-item metadata (created/modified)

### Media Viewer
- Built-in image viewer with pinch-to-zoom, double-tap zoom, and rotation
- Video/audio playback via `video_player` (FFmpeg-backed via `fvp`), with `.srt`/`.vtt` subtitle support
- Slideshow mode, shuffle, and folder filtering (current folder or recursive)
- Playback speed control, double-tap seek, loop/advance modes, mute

### Android Integration
- Exposes mounted containers as a **Documents Provider** — files show up in Android's system file picker
- Proxy file descriptor streaming — apps read/write directly to the encrypted volume with no plaintext intermediary on disk
- Open files in external apps via `ACTION_VIEW`, with remembered per-extension app preferences

### Security & App Settings
- Optional **master password** to lock the app on launch, with exponential backoff after repeated failures (lockout state survives a force-kill of the app)
- **Biometric unlock** as an alternative to typing the master password
- Per-container unlock methods: manual password, remembered password, biometrics, or a **drawn pattern**
- Optional **derived-key caching** in the Android Keystore, so biometric/pattern unlock can skip the expensive PBKDF2 pass entirely on repeat unlocks
- App-wide auto-lock after a period of inactivity or on screen lock, plus a separate per-container auto-close timer
- Custom per-container display name and Documents Provider toggle
- Configurable **thumbnail caching**: OS app cache (encrypted, fast) or inside the container (fully at-rest encrypted), or disabled entirely
- Screenshot blocking (`FLAG_SECURE`)

### Screenshots

<p align="center">
  <img width="250" alt="Screenshot_1783428063" src="https://github.com/user-attachments/assets/2267accb-aae3-4ce6-8fae-bd09bfebd3c1" />
  <img width="250" alt="Screenshot_1783428136" src="https://github.com/user-attachments/assets/a7ac12c5-6481-423d-a930-098ef5da3283" /> 
   <img width="250" alt="Screenshot_1783428136" src="https://github.com/user-attachments/assets/154c1dcf-e448-46ab-ad9d-2d92ad10fbe3" />

</p>
---

## Architecture

```
Flutter (Dart)
  ├── Dashboard — mount/lock containers, clipboard status strip
  ├── File Browser — list/grid, breadcrumbs, selection, search, sort, file ops
  ├── Vault Items — password-manager-style encrypted records
  ├── Media Viewer — images, video, audio, slideshow
  ├── Unlock — file & USB unlock sheets (password, biometric, pattern, keyfiles)
  ├── Settings — master password, biometric, per-container config
  └── VaultExplorerApi — MethodChannel bridge to Kotlin

Android (Kotlin)
  ├── MainActivity — MethodChannel handler, SAF file picker, import/export
  ├── VeraCryptSession / VeraCryptBridge — per-volume session registry & locking
  ├── VeraCryptEngine — JNI wrapper for the C++ engine
  ├── UsbMassStorageDevice / UsbBlockBridge — USB Mass Storage (Bulk-Only Transport) client
  ├── UnlockProgressBridge — pushes cipher/hash auto-detect progress to Dart
  └── VeraCryptDocumentsProvider — Android Documents Provider (ContentProvider)

C++ (NDK)
  ├── vaultexplorer.cpp — crypto session, header parsing (incl. hidden volumes), FatFs disk hooks, all JNI entry points
  ├── crypto/cascade.{h,cpp} — cipher-agnostic AES-XTS + multi-layer cascade chaining
  ├── crypto/cipher_shim.{h,cpp} — uniform adapter over AES/Serpent/Twofish and SHA-512/256, Whirlpool, Streebog, BLAKE2s-256
  ├── crypto/kdf_table.cpp — per-hash PBKDF2 iteration-count table
  ├── crypto/keyfile_mixing.h — VeraCrypt-compatible keyfile pool mixing
  ├── mbedTLS v3.6.0 — AES primitives, PBKDF2-HMAC-SHA512/256
  └── ChaN FatFs — FAT32 / exFAT read/write with UTF-8 LFN support
```

---

## Requirements

- Android 6.0+ (API 23)
- Android 8.0+ (API 26) required for video thumbnail generation
- USB OTG support on-device (and a USB OTG cable/adapter) for USB drive mounting
- NDK support (CMake build)

---

## Building

### Prerequisites
- Flutter SDK `^3.12.0`
- Android NDK (version specified in `flutter.ndkVersion`)
- CMake 3.18+

### Steps

```bash
git clone https://github.com/R0b0To/VaultExplorer.git
cd vaultexplorer
flutter pub get
flutter build apk --release
```

The C++ engine is built automatically by CMake during the Android build. mbedTLS and FatFs are fetched via `FetchContent` at build time — no manual dependency setup required.

---

## Dependencies

| Package | Purpose |
|---|---|
| `file_picker` | SAF-based container file selection |
| `path_provider` | App document/cache directory access |
| `video_player` / `fvp` | Video and audio playback (FFmpeg-backed) |
| `get_thumbnail_video` | Video thumbnail generation helpers |
| `local_auth` | Biometric / fingerprint unlock |
| `flutter_secure_storage` | Master password, saved container passwords, pattern hashes, cached derived keys |
| `encrypt` / `pointycastle` | AES-GCM thumbnail cache, SHA-256 pattern hashing |
| `permission_handler` | Storage permission handling |
| `url_launcher` | Opening external links (GitHub, Ko-fi, etc.) |
| `wakelock_plus` | Keeps the screen on during media playback |
| `package_info_plus` | App version display in Settings |
| `mbedTLS 3.6.0` | AES-256-XTS, PBKDF2-HMAC-SHA512/256 (C++) |
| `ChaN FatFs` | FAT32 / exFAT filesystem (C++) |

VeraCrypt crypto primitives are fetched by CMake from the pinned VeraCrypt 1.26.29 source release. This includes Serpent, Twofish, Camellia, Kuznyechik, Whirlpool, Streebog, BLAKE2s, and Argon2id, without carrying a local fork of those sources.

---

## How It Works

1. **Unlock**: The app reads the 512-byte VeraCrypt header (and, if present, the hidden-volume header slot) from the container file or USB partition, derives the header key via PBKDF2 — optionally mixed with keyfiles — and decrypts the header with AES-XTS (or the selected cascade) to extract the master key. When the cipher/hash isn't specified, every supported combination is tried in parallel.
2. **Mount**: FatFs is initialised with custom `disk_read`/`disk_write` hooks that transparently decrypt/encrypt 512-byte sectors on every I/O call using the master key, honoring whichever cipher cascade the header specified.
3. **Browse**: All file and directory operations go through FatFs over the encrypted disk layer — plaintext data never touches device storage.
4. **Stream (Documents Provider)**: For external apps, a `ProxyFileDescriptor` serves read/write calls chunk-by-chunk directly through the JNI engine, enabling seamless integration with Android's system file picker.

---

## Limitations

- **Android only** (the native engine uses Android JNI / NDK APIs)

---

## Acknowledgements

- [VeraCrypt](https://veracrypt.fr) — the open-source disk encryption standard this app is compatible with
- [Mbed TLS](https://github.com/Mbed-TLS/mbedtls) — embedded TLS and crypto library
- [ChaN FatFs](http://elm-chan.org/fsw/ff/) — lightweight FAT/exFAT filesystem module
