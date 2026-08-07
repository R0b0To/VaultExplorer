# VaultExplorer

[![Flutter](https://img.shields.io/badge/Flutter-%5E3.12.0-02569B?style=flat&logo=flutter)](https://flutter.dev)
[![Android](https://img.shields.io/badge/Android-8.0%2B%20%28API%2026%2B%29-3DDC84?style=flat&logo=android)](https://developer.android.com)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Donate](https://img.shields.io/badge/Ko--Fi-Support%20Project-FF5E5B?style=flat&logo=ko-fi)](https://ko-fi.com/K3K2ND3Y8)

> **An Android file manager, and viewer for encrypted containers, drives, and directory vaults — no PC required.**

**VaultExplorer** allows you to mount, browse, create, edit, and manage encrypted volumes directly on your Android device. It supports **VeraCrypt**, **LUKS1 / LUKS2**, **BitLocker**, **Cryptomator**, **gocryptfs**, and **CryFS** volumes, as well as **VHD / VHDX** virtual disk images. Built with Flutter and powered by a custom high-performance C++ native engine (*mbedTLS + FatFs + NTFS-3G + libext2fs + Dislocker*), everything is decrypted and re-encrypted on-the-fly in memory with zero unencrypted temporary files written to host storage.

---

## 📸 Screenshots

<p align="center">
  <img width="250" alt="Dashboard" src="https://github.com/user-attachments/assets/1c981b1d-3d98-4b07-a275-fe78c6263815" />
  <img width="250" alt="File Explorer" src="https://github.com/user-attachments/assets/70dd6300-c260-4573-a01a-43e522e6a4e0" />
  <img width="250" alt="Media Viewer" src="https://github.com/user-attachments/assets/19f5f121-80a2-452f-9bad-ad054f5ed306" /> 
  <img width="250" alt="File Explorer" src="https://github.com/user-attachments/assets/9fa0e98d-3183-41ff-a160-8c9972df582d" />
  <img width="250" alt="Media Viewer" src="https://github.com/user-attachments/assets/192a91e3-001b-4b9f-bf95-936201b6814f" /> 
</p>

---

## ✨ Features & Architecture

### 🔐 Volume & Encryption Systems

#### Block-Level Containers & Disk Images
*   **VeraCrypt (`.hc`)**: Standard & embedded Hidden Volume support, custom PIM, additive keyfiles, multi-layer cipher cascades, and in-place password modification.
*   **LUKS1 & LUKS2**: Full support for `xts-plain64` volumes. Keyslots backed by **PBKDF2** or memory-hard **Argon2id / Argon2i**. Supports passphrases or binary keyfiles (`cryptsetup --key-file`).
*   **BitLocker**: Decrypt and re-encrypt BitLocker partitions and BitLocker To Go volumes using user passwords or 48-digit numerical recovery keys (powered by a custom `dislocker` C++ virtual I/O engine).
*   **VHD & VHDX Images**: Native Block Allocation Table (BAT) translation for both **fixed** and **dynamic (expandable)** virtual hard disk images hosting VeraCrypt, LUKS, or BitLocker filesystems.

#### Directory-Based Vaults
*   **Cryptomator**: Full support for **Vault Formats 7 & 8** (ciphers `SIV_GCM` and `SIV_CTRMAC`). Handles masterkey scrypt unwrapping, base32 directory ID hashing, and long-filename shortening (`.c9s` / `name.c9r`).
*   **gocryptfs**: Modern default format support (`GCMIV128`, `DirIV`, `EMENames`, `LongNames`, `Raw64`, `HKDF`). Features EME filename encryption and 4KB chunk-level AES-GCM streaming.
*   **CryFS**: Format `0.10` support with dual-layer scrypt config unwrapping, block sharding storage, Merkle data tree indexing (`CryfsDataTree`), and directory blob serialization (`CryfsDirBlob`). Supports `xchacha20-poly1305`, `aes-256-gcm`, `aes-128-gcm`, `aes-256-cfb`, and `aes-128-cfb`.

---

### 🗝️ Cryptographic Algorithms & Native Primitives

*   **Block & Stream Ciphers**: AES-256, AES-128, Serpent, Twofish, Camellia, Kuznyechik, and XChaCha20-Poly1305.
*   **Cipher Modes**: XTS, GCM, CTR, CFB, EME (wide-block filename encryption), and AES-SIV (synthetic IV).
*   **VeraCrypt Cascades**: All 15 single and multi-layer cipher combinations (e.g., AES-Twofish-Serpent, Kuznyechik-Serpent-Camellia, Camellia-Kuznyechik).
*   **Key Derivation Functions (KDF)**: PBKDF2 with SHA-512, SHA-256, Whirlpool, Streebog (512-bit), or BLAKE2s-256, alongside Argon2id/i and scrypt.
*   **Hardware Acceleration**: Built with ARMv8 Cryptography Extensions (`-march=armv8-a+crypto+sha2`) in mbedTLS for near-instant PBKDF2/AES execution on modern ARM CPUs.
*   **Parallel Auto-Detect Engine**: Multi-threaded C++ header derivation testing candidate KDFs and ciphers concurrently with real-time progress callbacks to the UI.

---

### 🚀 POSIX Storage Acceleration

*   **POSIX File System Bypass**: Directory vaults (Cryptomator, gocryptfs, CryFS) automatically use direct POSIX file I/O when `MANAGE_EXTERNAL_STORAGE` or direct path access is granted, bypassing slow Android Storage Access Framework (SAF) document tree queries.
*   **Up to 1000x Speedup**: Massive performance gains for directory listing, reading, and writing—essential for CryFS vaults with tens of thousands of sharded block files.

---

### 💾 Filesystems & USB OTG Driver

*   **Native Filesystem Engines**:
    *   **FAT12 / FAT16 / FAT32 & exFAT** via ChaN's FatFs.
    *   **NTFS** via Tuxera NTFS-3G (includes embedded `mkntfs` formatter).
    *   **ext2 / ext3 / ext4** via e2fsprogs `libext2fs`.
*   **Custom USB OTG Mass Storage Driver**: Built-in SCSI Bulk-Only Transport (BOT) driver operating directly over Android's USB Host API (no root required). Supports 10-byte and 16-byte CDBs with dynamic sector-chunk backoff (1024 down to 8 sectors) for maximum hardware compatibility, MBR partition parsing, and instant auto-locking upon drive disconnection.
*   **On-Device Volume Creation**: Format and initialize brand-new VeraCrypt, LUKS1, LUKS2, Cryptomator, gocryptfs, or CryFS containers directly on device storage or raw USB drives (Quick Format or Full zero-fill).
*   **Multi-Mount Manager**: Simultaneously mount up to **8 active volume slots**.

---

### ☁️ Cloud Storage & Remote Vault Access (via SAF)

Although VaultExplorer intentionally has **zero internet permissions** for complete data privacy, you can still access encrypted containers and directory vaults hosted on cloud services through Android's Storage Access Framework (SAF):
*   **Native Cloud Document Providers**: Official cloud apps like **Google Drive** and **pCloud** automatically act as system Document Providers when installed on your Android device. VaultExplorer can open, read, edit, and save encrypted vaults directly from these cloud providers via SAF.
*   **Sync Bridge Apps (e.g., Round-Sync)**: For cloud services without native SAF document providers (or for protocols like WebDAV, Nextcloud, SFTP, S3, OneDrive, Dropbox, etc.), you can use open-source bridge applications like **Round-Sync** (Rclone for Android). Round-Sync can expose remote cloud storages as a local Document Provider or synced SAF directory, bridging them straight into VaultExplorer.

---

### 📁 In-Vault Studio, Media Streaming & Editors

*   **Multi-Layout File Explorer**: Detailed List, Grid, and Masonry view modes with gesture-based pinch-to-zoom column adjustments, breadcrumbs, search term highlighting, and instant folder size calculations.
*   **Direct Vault Camera**: Capture photos and record video (H.264 / HEVC) directly into encrypted containers without writing unencrypted temporary files to host storage.
*   **PDF Viewer**: Native rendering via `pdfrx` (PDFium/FFI) with in-document text search and match navigation, streamed directly from the encrypted volume through a custom byte-range reader — no plaintext PDF is ever written to host storage.
*   **Web & HTML Viewer**: Isolated `WebView` platform view rendering HTML, CSS, JavaScript, and linked web assets directly out of the vault via a local secure origin (`https://vault-local.internal`).
*   **Built-In Text Editor**: Create, edit, and save plain text, code, or markdown files directly inside encrypted volumes.
*   **In-Vault ZIP Archive Browser**: Inspect and extract `.zip` archive contents directly inside an encrypted volume without unencrypting archives to the host filesystem.
*   **Advanced Media Streaming**: Stream video and audio (AndroidX Media3/ExoPlayer via the `video_player` plugin, `.srt`/`.vtt` subtitles, custom speed, double-tap seek, audio visualizer) and view photos (pinch-to-zoom, 90° rotation, slideshow, gallery carousel overlay, diagnostics sheet).
*   **Encrypted Item Vault**: Store Passwords, Bank Accounts, Payment Cards, Secure Notes, Identities, and Software Licenses directly inside the volume as encrypted JSON objects with customizable key-value fields and secret masking.
*   **Android SAF Provider & Subfolder Mounts**: Expose entire mounted containers or specific subfolders (`subFolderMounts`) as Android Storage Access Framework (SAF) roots (`ContainerDocumentsProvider`), allowing third-party Android apps to open and save files inside unlocked volumes via AppFuse proxy descriptors.

---

### 🛡️ Security & Privacy

*   **Zero Internet Permission**: The application binary does not request or possess network access (`android.permission.INTERNET` is completely absent). Any cloud storage access is safely brokered through Android's system Document Providers (SAF).
*   **Master Lock**: Protect the entire app with a Master Password, Biometric Unlock (Fingerprint / Face via Android Keystore), or Pattern Lock backed by exponential lockout backoff surviving app force-kills.
*   **Hardware-Bound Key Caching**: Optional AES-256-GCM key caching stored securely in the hardware-backed Android Keystore for instant re-unlocks.
*   **3-Tier Thumbnail Cache**: In-Memory LRU $\rightarrow$ AES-256-GCM Encrypted Disk/In-Container Cache $\rightarrow$ Native Generation. Can be completely disabled for maximum privacy.
*   **Screen & Clipboard Protection**: Prevents screenshots and task-switcher previews (`FLAG_SECURE`) with automatic corrupt clipboard clearing upon app focus.

---

## 🛠️ Native C++ Engine Dependencies

VaultExplorer pins and compiles all C++ native dependencies directly during build time:

| Library | Version / Commit | Purpose |
| :--- | :--- | :--- |
| **mbedTLS** | v3.6.0 | AES, SHA-1/2, HMAC, PBKDF2, Argon2id, hardware crypto extensions |
| **libavif & libgav1** | Pinned Commit | Native AVIF image decoding engine |
| **FatFs** | 4.0.4 | FAT12 / FAT16 / FAT32 / exFAT filesystem backend |
| **NTFS-3G** | Release Tag | Full read/write NTFS filesystem driver & `mkntfs` volume formatter |
| **e2fsprogs** | v1.47.4 (`libext2fs`) | Full read/write ext2, ext3, and ext4 filesystem engine |
| **Dislocker** | Patch overlay | BitLocker FVE & BitLocker To Go decryption and re-encryption |
| **VeraCrypt** | 1.26.29 (Primitives) | Twofish, Serpent, Camellia, Kuznyechik, Whirlpool, Streebog, BLAKE2s |
| **cJSON** | v1.7.18 | High-speed JSON parsing for LUKS2 & Cryptomator metadata |

---

## ⚙️ Building from Source

### Prerequisites
*   **Flutter SDK**: `>= 3.12.0`
*   **Android SDK**: API level 26+ (Android 8.0 Oreo or newer)
*   **Android NDK**: Installed via Android Studio SDK Manager
*   **CMake**: `3.18.0+`

### Build Steps

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/R0b0To/VaultExplorer.git
    cd VaultExplorer
    ```

2.  **Fetch Flutter packages**:
    ```bash
    flutter pub get
    ```

3.  **Build Release APK**:
    ```bash
    flutter build apk --release
    ```

> *Note: CMake will automatically fetch and compile all native C++ libraries during the build step.*

---

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/K3K2ND3Y8)