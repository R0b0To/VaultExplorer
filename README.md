# VaultExplorer

[![Flutter](https://img.shields.io/badge/Flutter-%5E3.12.0-02569B?style=flat&logo=flutter)](https://flutter.dev)
[![Android](https://img.shields.io/badge/Android-8.0%2B%20%28API%2026%2B%29-3DDC84?style=flat&logo=android)](https://developer.android.com)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Donate](https://img.shields.io/badge/Ko--Fi-Support%20Project-FF5E5B?style=flat&logo=ko-fi)](https://ko-fi.com/K3K2ND3Y8)

> **An Android file manager for encrypted containers, drives, and directory vaults — no PC required.**

**VaultExplorer** allows you to mount, browse, create, and manage encrypted volumes directly on your Android device. It supports **VeraCrypt**, **LUKS1 / LUKS2**, **BitLocker**, **Cryptomator**, and **gocryptfs** volumes, as well as **VHD / VHDX** disk image files. Built with Flutter and powered by a custom C++ native engine (*mbedTLS + FatFs + NTFS-3G + libext2fs + Dislocker*), everything is decrypted and re-encrypted on-the-fly in memory with zero unencrypted temporary files written to disk.

---

## 📸 Screenshots

<p align="center">
  <img width="250" alt="Screenshot_1" src="https://github.com/user-attachments/assets/be881af4-d607-4522-b389-c1553416c64b" />
  <img width="250" alt="Screenshot_3" src="https://github.com/user-attachments/assets/4b13dc9c-c1ec-4067-b15b-de1fdbd24e89" />
  <img width="250" alt="Screenshot_2" src="https://github.com/user-attachments/assets/ed55b96a-5fee-4b65-bc81-f0345e3c208f" /> 
</p>

---

## ✨ Features & Architecture

### 🔐 Supported Formats & Encryption Systems

#### Block-Level Containers & Disk Images
*   **VeraCrypt (`.hc`)**: Standard & embedded Hidden Volume support, custom PIM, additive keyfiles, and volume password changes.
*   **LUKS1 & LUKS2**: Full support for `xts-plain64` volumes. Keyslots backed by **PBKDF2** or memory-hard **Argon2id / Argon2i**. Supports passphrase or keyfile substitution (`cryptsetup --key-file`).
*   **BitLocker**: Decrypt and re-encrypt BitLocker partitions and BitLocker To Go volumes using user passwords or 48-digit numerical recovery keys (powered by an integrated `dislocker` backend).
*   **VHD & VHDX Images**: Native Block Allocation Table (BAT) translation for both **fixed** and **dynamic (expandable)** virtual hard disk images containing VeraCrypt, LUKS, or BitLocker partitions.

#### Directory-Based Vaults
*   **Cryptomator**: Supports **Vault Format 7 & 8** (cipher combos `SIV_GCM` and `SIV_CTRMAC`). Handles masterkey scrypt unwrapping, base32 directory ID hashing, and long-filename shortening (`.c9s` / `name.c9r`).
*   **gocryptfs**: Modern default vault format support (`GCMIV128`, `DirIV`, `EMENames`, `LongNames`, `Raw64`, `HKDF`). EME filename encryption and 4KB chunk-level AES-GCM streaming.

---

### 🗝️ Cryptographic Algorithms & Ciphers

*   **Block Ciphers**: AES-256, Serpent, Twofish, Camellia, and Kuznyechik.
*   **VeraCrypt Cascades**: All 15 single and multi-layer cipher combinations (e.g. AES-Twofish-Serpent, Kuznyechik-Serpent-Camellia, Camellia-Kuznyechik).
*   **Key Derivation Functions (KDF)**: PBKDF2 with SHA-512, SHA-256, Whirlpool, Streebog (512-bit), or BLAKE2s-256, alongside Argon2id and scrypt.
*   **Parallel Auto-Detect Engine**: Multi-threaded C++ header derivation testing fast algorithms concurrently before memory-hard Argon2id iterations, with real-time UI progress.

---

### 💾 Filesystems & USB OTG Integration

*   **Filesystem Drivers**: Native C++ implementations of **FAT32**, **exFAT** (via ChaN FatFs), **NTFS** (via Tuxera NTFS-3G), and **ext2 / ext3 / ext4** (via e2fsprogs `libext2fs`).
*   **Custom USB OTG Mass Storage Driver**: Built-in SCSI Bulk-Only Transport (BOT) driver operating over Android’s USB Host API. No root required. Parses MBR/GPT partition tables and auto-locks volumes on device ejection.
*   **On-Device Format & Creation**: Create and format brand-new VeraCrypt, LUKS1, LUKS2, Cryptomator, or gocryptfs containers/vaults directly on internal storage or raw USB flash drives (with Quick Format or Full zero-fill options).
*   **Multi-Mount Manager**: Mount up to **8 active volume slots** simultaneously.

---

### 📁 Explorer, Media Streaming & Built-In Password Manager

*   **File Explorer**: Grid, detailed list, and compact view modes with breadcrumb navigation, instant search text highlighting, folder-size calculation, and custom sorting.
*   **In-Vault ZIP Archive Browser**: Directly view and extract `.zip` archive contents inside an encrypted container without unencrypting the archive to host storage.
*   **Background File Operations**: Multi-threaded copy, move, import, and delete engine with LIFO queue prioritisation, pre-flight free-space calculation, conflict resolution sheets, and rollback on disk-full.
*   **Integrated Media Viewer**: On-the-fly streaming for video/audio (FFmpeg-backed `fvp` engine, `.srt`/`.vtt` closed captions, playback speed, double-tap seek, audio visualizers) and images (pinch-to-zoom, 90° rotation, slideshow, gallery carousel) using virtual file handles.
*   **Encrypted Item Vault**: Store logins, payment cards, secure notes, identities, bank accounts, and software licenses directly inside the vault as encrypted native JSON objects.
*   **Android SAF Provider**: Integrates with Android's Storage Access Framework (`ContainerDocumentsProvider`), allowing third-party apps to securely open and save files inside unlocked containers via AppFuse proxy descriptors.

---

### 🛡️ App Security & Privacy

*   **Zero Internet Permission**: The app does not request or require network access (`android.permission.INTERNET` is absent).
*   **Master Lock**: App-wide access protection with Master Password, Biometric Unlock (Fingerprint / Face via Android Keystore), or Pattern Lock, backed by exponential lockout backoff surviving app force-kills.
*   **Hardware-Bound Key Caching**: Fast re-unlocks via AES-256-GCM derived key caching stored in the hardware-backed Android Keystore.
*   **3-Tier Thumbnail Cache**: In-Memory LRU $\rightarrow$ AES-GCM Encrypted Disk/In-Container Cache $\rightarrow$ Native Generation. Can be completely disabled for total privacy.
*   **Screen & Clipboard Protection**: Screenshot/task-switcher preview blocking (`FLAG_SECURE`) and automatic clipboard sanitisation.

---

## 🛠️ Native Architecture & Dependencies

VaultExplorer's native C++ library (`libvaultexplorer.so`) statically compiles and bundles vetted cryptographic and filesystem dependencies:

```
VaultExplorer Native Engine (libvaultexplorer)
 ├── mbedTLS (v3.6.0)           ─ Hardware-accelerated AES/SHA-2 & PBKDF2
 ├── VeraCrypt Primitives       ─ Twofish, Serpent, Camellia, Kuznyechik, Whirlpool, Streebog, BLAKE2s, Argon2
 ├── Dislocker                  ─ BitLocker metadata parsing and FVEK decryption
 ├── ChaN FatFs (v4.0.4)        ─ FAT12 / FAT16 / FAT32 / exFAT driver
 ├── Tuxera NTFS-3G (edge)      ─ Full NTFS read/write driver & embedded mkntfs
 ├── e2fsprogs / libext2fs      ─ ext2 / ext3 / ext4 driver
 └── cJSON (v1.7.18)            ─ LUKS2 JSON metadata parser
```

---

## ⚙️ Building from Source

### Prerequisites
*   **Flutter SDK**: `>= 3.12.0`
*   **Android SDK**: API level 26+ (Android 8.0 Oreo or newer)
*   **Android NDK**: Installed via Android Studio SDK Manager (version specified in Gradle)
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

> *Note: During the build, CMake will automatically pull and compile the native C++ dependencies (`mbedTLS`, `FatFs`, `NTFS-3G`, `libext2fs`, `Dislocker`, `cJSON`, and `VeraCrypt 1.26.29` source primitives).*

---

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/K3K2ND3Y8)