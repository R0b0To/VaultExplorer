# VaultExplorer [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/K3K2ND3Y8)

**A native Android file manager for VeraCrypt encrypted containers — no PC required.**

VaultExplorer lets you mount, browse, and manage VeraCrypt volumes directly on your Android device. Built with Flutter and a custom C++ crypto engine (mbedTLS + FatFs), it decrypts and re-encrypts data fully on-device with zero temporary plaintext files on device storage.

---

## Features

### Encryption & Compatibility
- Full **AES-256-XTS** decryption and encryption matching the VeraCrypt standard
- **PBKDF2-SHA512** key derivation with configurable PIM support
- Compatible with containers created by the desktop VeraCrypt application
- Supports both **FAT32** and **exFAT** formatted volumes
- Create new VeraCrypt containers directly from the app
- Up to **8 containers** can be mounted simultaneously

### File Management
- Browse directories with breadcrumb navigation
- **List view** and **gallery/grid view** with live thumbnails
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
- Optional **master password** to lock the app on launch, with exponential backoff after repeated failures
- **Biometric unlock** as an alternative to typing the master password
- Per-container unlock methods: manual password, remembered password, biometrics, or a **drawn pattern**
- Per-container auto-lock timer, custom display name, and Documents Provider toggle
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
  ├── Settings — master password, biometric, per-container config
  └── VaultExplorerApi — MethodChannel bridge to Kotlin

Android (Kotlin)
  ├── MainActivity — MethodChannel handler, SAF file picker, import/export
  ├── VeraCryptSession / VeraCryptBridge — per-volume session registry & locking
  ├── VeraCryptEngine — JNI wrapper for the C++ engine
  └── VeraCryptDocumentsProvider — Android Documents Provider (ContentProvider)

C++ (NDK)
  ├── vaultexplorer.cpp — crypto session, FatFs disk hooks, all JNI entry points
  ├── mbedTLS v3.6.0 — AES-XTS, PBKDF2-SHA512
  └── ChaN FatFs — FAT32 / exFAT read/write with UTF-8 LFN support
```

---

## Requirements

- Android 6.0+ (API 23)
- Android 8.0+ (API 26) required for video thumbnail generation
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
| `local_auth` | Biometric / fingerprint unlock |
| `flutter_secure_storage` | Master password, saved container passwords, pattern hashes |
| `encrypt` / `pointycastle` | AES-GCM thumbnail cache, SHA-256 pattern hashing |
| `permission_handler` | Storage permission handling |
| `mbedTLS 3.6.0` | AES-256-XTS, PBKDF2-SHA512 (C++) |
| `ChaN FatFs` | FAT32 / exFAT filesystem (C++) |

---

## How It Works

1. **Unlock**: The app reads the 512-byte VeraCrypt header from the container file, derives the header key via PBKDF2-SHA512, decrypts the header with AES-XTS, and extracts the master key.
2. **Mount**: FatFs is initialised with custom `disk_read`/`disk_write` hooks that transparently decrypt/encrypt 512-byte sectors on every I/O call using the master key.
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
