# VaultExplorer [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/K3K2ND3Y8)

**A native Android file manager for encrypted containers — no PC required.**

VaultExplorer lets you mount, browse, and manage VeraCrypt and LUKS encrypted volumes directly on your Android device. Built with Flutter and a custom C++ crypto engine (mbedTLS + FatFs + NTFS-3G + libext2fs), it decrypts and re-encrypts data fully on-device with zero temporary plaintext files on device storage.

---

## Features

### Encryption & Compatibility
- Support for **VeraCrypt** containers (`.hc` files) **and native LUKS1 / LUKS2 containers** (as created by Linux `cryptsetup`) — container format is auto-detected at unlock time, no need to tell the app which kind of volume you're opening
- Full **AES-256-XTS** decryption and encryption matching the VeraCrypt/LUKS standard
- Additional ciphers and cascades: **Serpent**, **Twofish**, **Camellia**, and **Kuznyechik**, plus the cascaded combinations VeraCrypt supports — AES-Twofish, Serpent-AES, Twofish-Serpent, AES-Twofish-Serpent, Serpent-Twofish-AES, Camellia-Kuznyechik, Camellia-Serpent, Kuznyechik-AES, Kuznyechik-Serpent-Camellia, Kuznyechik-Twofish (15 cipher/cascade combinations in total)
- Multiple key-derivation options: PBKDF2 with **SHA-512**, SHA-256, Whirlpool, Streebog, or BLAKE2s-256, plus the memory-hard **Argon2id** KDF used by newer VeraCrypt volumes
- LUKS1 and LUKS2 volumes are supported with AES, Serpent, Twofish, Camellia, or Kuznyechik in `xts-plain64` mode, PBKDF2 or Argon2id/Argon2i keyslot KDFs, and standard AF-splitting keyslot recovery — including LUKS2's per-segment sector size and IV-tweak offset
- **Auto-detect mode** tries every cipher/hash combination in parallel when the algorithm isn't known, with a live "trying combination X of Y" progress indicator and the ability to cancel mid-search
- Once a container has been unlocked, its matched cipher/hash is remembered so the next unlock skips straight to the right combination
- **Keyfile support** — mix one or more files into the password using VeraCrypt's own pool-mixing algorithm for VeraCrypt volumes (including keyfile-only, passwordless volumes), or supply a keyfile as a direct passphrase replacement for LUKS volumes, matching `cryptsetup --key-file` semantics
- **Hidden volume** detection — a hidden VeraCrypt volume nested inside an outer container is discovered automatically at unlock time, with no separate "mount hidden volume" step
- **PBKDF2** key derivation with configurable PIM support
- Compatible with containers created by the desktop VeraCrypt application and by Linux `cryptsetup`
- Up to **8 containers** can be mounted simultaneously, from container files, `content://` documents, or USB mass-storage devices

### Filesystem Support
- Read and write **FAT32**, **exFAT**, **NTFS**, and **ext2 / ext3 / ext4** volumes inside a mounted container — the filesystem is detected automatically at mount time, independent of the container format (VeraCrypt or LUKS)
- Create new containers formatted as FAT32, exFAT, NTFS, or ext2/ext3/ext4 directly from the app
- Full read/write support for each filesystem: directory listing, file create/read/write/delete/rename, directory creation, and timestamp updates

### USB Drive Support
- Mount VeraCrypt or LUKS volumes living on a USB OTG flash drive or external SSD — no root, no PC
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
- Optional **derived-key caching** in the Android Keystore, so biometric/pattern unlock can skip the expensive PBKDF2/Argon2id pass entirely on repeat unlocks
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
  ├── ContainerSessionRegistry / ContainerFileSystem — session registry & locking
  ├── ContainerEngine — format-neutral façade over the JNI implementation
  ├── UsbMassStorageDevice / UsbBlockBridge — USB Mass Storage (Bulk-Only Transport) client
  ├── UnlockProgressBridge — pushes cipher/hash auto-detect progress to Dart
  └── ContainerDocumentsProvider — Android Documents Provider (ContentProvider)

C++ (NDK)
  ├── vaultexplorer.cpp — native orchestration, crypto sessions, disk hooks, JNI exports
  ├── session_prepare.cpp — VeraCrypt/LUKS session establishment (header auto-detect, key derivation)
  ├── container_create.cpp — new-container header formatting for VeraCrypt, LUKS, and hidden volumes
  ├── volume_state / block_io — shared unlocked-volume lifecycle and file/USB backing-store transport
  ├── jni_runtime / jni_callbacks — JNI lifetime, progress, and USB upcalls
  ├── container_{format,header,utils} — format IDs, decrypted-header decoding, and common data utilities
  ├── {fat,ntfs,ext}_backend — filesystem-specific helpers (FAT32/exFAT, NTFS, ext2/3/4)
  ├── crypto/cascade.{h,cpp} — cipher-agnostic AES-XTS + multi-layer cascade chaining (AES, Serpent, Twofish, Camellia, Kuznyechik)
  ├── crypto/cipher_shim.{h,cpp} — uniform adapter over the block ciphers and SHA-512/256, Whirlpool, Streebog, BLAKE2s-256, Argon2id
  ├── crypto/kdf_table.cpp — per-hash PBKDF2 iteration-count table + Argon2id parameter derivation
  ├── crypto/keyfile_mixing.h — VeraCrypt-compatible keyfile pool mixing
  ├── crypto/luks_header.{h,cpp} — LUKS1/LUKS2 header + JSON metadata parsing, keyslot AF-merge and master-key recovery
  ├── mbedTLS v3.6.0 — AES primitives, PBKDF2-HMAC-SHA512/256, AES-XTS, LUKS AF-diffusion base64
  ├── ChaN FatFs — FAT32 / exFAT read/write with UTF-8 LFN support
  ├── NTFS-3G — NTFS read/write, routed through a custom encrypted device backend
  ├── libext2fs (e2fsprogs) — ext2/ext3/ext4 read/write, routed through a custom encrypted I/O manager
  └── cJSON — LUKS2 JSON metadata parsing
```

---

## Requirements

- Android 6.0+ (API 23)
- Video thumbnails use a faster scaled-frame extraction path on Android 8.1+ (API 27), falling back automatically to standard frame extraction on older versions
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

The C++ engine is built automatically by CMake during the Android build. mbedTLS, FatFs, NTFS-3G, libext2fs, cJSON, and the VeraCrypt crypto primitives are fetched via `FetchContent` at build time — no manual dependency setup required.

---

## Dependencies

| Package | Purpose |
|---|---|
| `path_provider` | App document/cache directory access |
| `video_player` / `fvp` | Video and audio playback (FFmpeg-backed) |
| `local_auth` | Biometric / fingerprint unlock |
| `flutter_secure_storage` | Master password, saved container passwords, pattern hashes, cached derived keys |
| `encrypt` / `pointycastle` | AES-GCM thumbnail cache, SHA-256 pattern hashing |
| `url_launcher` | Opening external links (GitHub, Ko-fi, etc.) |
| `wakelock_plus` | Keeps the screen on during media playback |
| `package_info_plus` | App version display in Settings |
| `vector_math` | Zoom/pan matrix math for the video player's pinch and double-tap gestures |
| `mbedTLS 3.6.0` | AES-256-XTS, PBKDF2-HMAC-SHA512/256 (C++) |
| `ChaN FatFs` | FAT32 / exFAT filesystem (C++) |
| `NTFS-3G` | NTFS filesystem, including the embedded `mkntfs` formatter (C++) |
| `e2fsprogs` (`libext2fs`) | ext2 / ext3 / ext4 filesystem (C++) |
| `cJSON` | LUKS2 JSON metadata parsing (C++) |

Container/keyfile picking, video thumbnail generation, and biometric-key storage are implemented natively in Kotlin (SAF intents, `MediaMetadataRetriever`, Android Keystore) rather than through Flutter plugins.

VeraCrypt crypto primitives are fetched by CMake from the pinned VeraCrypt 1.26.29 source release. This includes Serpent, Twofish, Camellia, Kuznyechik, Whirlpool, Streebog, BLAKE2s, and Argon2id, without carrying a local fork of those sources.

---

## How It Works

1. **Unlock**: For VeraCrypt containers, the app reads the 512-byte header (and, if present, the hidden-volume header slot) from the container file or USB partition, derives the header key via PBKDF2 or Argon2id — optionally mixed with keyfiles — and decrypts the header with AES-XTS (or the selected cascade) to extract the master key. When the cipher/hash isn't specified, every supported combination is tried in parallel. For LUKS1/LUKS2 containers, the app is detected by magic bytes, parses the binary or JSON metadata, derives each active keyslot's key (PBKDF2 or Argon2id/Argon2i), decrypts and AF-merges the keyslot's key material, and verifies the resulting candidate master key against the stored digest.
2. **Mount**: FatFs, NTFS-3G, or libext2fs is initialised with custom disk I/O hooks that transparently decrypt/encrypt sectors (or LUKS "sector-size" data units) on every I/O call using the recovered master key, honoring whichever cipher cascade or LUKS cipher mode was matched. The filesystem itself (FAT32/exFAT/NTFS/ext2/3/4) is auto-detected from the decrypted boot sector.
3. **Browse**: All file and directory operations go through the matching filesystem driver over the encrypted disk layer — plaintext data never touches device storage.
4. **Stream (Documents Provider)**: For external apps, a `ProxyFileDescriptor` serves read/write calls chunk-by-chunk directly through the JNI engine, enabling seamless integration with Android's system file picker.

---

## Limitations

- **Android only** (the native engine uses Android JNI / NDK APIs)

---

## License

GNU General Public License v3.0. See [LICENSE](LICENSE) for the full text.

---

## Acknowledgements

- [VeraCrypt](https://veracrypt.fr) — the open-source disk encryption standard this app is compatible with
- [LUKS / cryptsetup](https://gitlab.com/cryptsetup/cryptsetup) — the Linux disk encryption standard this app is compatible with
- [Mbed TLS](https://github.com/Mbed-TLS/mbedtls) — embedded TLS and crypto library
- [ChaN FatFs](http://elm-chan.org/fsw/ff/) — lightweight FAT/exFAT filesystem module
- [NTFS-3G](https://github.com/tuxera/ntfs-3g) — NTFS filesystem driver
- [e2fsprogs / libext2fs](https://github.com/tytso/e2fsprogs) — ext2/ext3/ext4 filesystem library
- [cJSON](https://github.com/DaveGamble/cJSON) — lightweight JSON parser used for LUKS2 metadata
