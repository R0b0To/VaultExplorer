# VaultExplorer

[![Flutter](https://img.shields.io/badge/Flutter-%5E3.12.0-02569B?style=flat&logo=flutter)](https://flutter.dev)
[![Android](https://img.shields.io/badge/Android-8.0%2B%20%28API%2026%2B%29-3DDC84?style=flat&logo=android)](https://developer.android.com)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Donate](https://img.shields.io/badge/Ko--Fi-Support%20Project-FF5E5B?style=flat&logo=ko-fi)](https://ko-fi.com/K3K2ND3Y8)

> **An Android file manager for encrypted containers and vaults — no PC required.**

**VaultExplorer** allows you to mount, browse, and manage VeraCrypt, LUKS, Cryptomator, and gocryptfs volumes directly on your Android device. Built with Flutter and powered by a custom C++ native cryptographic & filesystem engine (mbedTLS + FatFs + NTFS-3G + libext2fs), everything is decrypted and re-encrypted entirely on-device with zero plaintext temporary files written to disk.

---

## 📸 Overview & Screenshots

<p align="center">
<img width="250" alt="Screenshot_1" src="https://github.com/user-attachments/assets/be881af4-d607-4522-b389-c1553416c64b" />
  <img width="250" alt="Screenshot_3" src="https://github.com/user-attachments/assets/4b13dc9c-c1ec-4067-b15b-de1fdbd24e89" />
  <img width="250" alt="Screenshot_2" src="https://github.com/user-attachments/assets/ed55b96a-5fee-4b65-bc81-f0345e3c208f" /> 
</p>

---

## ✨ Features

### 🔐 Supported Formats & Encryption
- **Block-Level Containers**: Native support for **VeraCrypt** (`.hc`) and **LUKS1 / LUKS2** containers with automatic format detection.
- **Directory-Based Vaults**: Native support for **Cryptomator** (Format 7 & 8) and **gocryptfs** directory-level vaults, fully cross-compatible with desktop and mobile clients.
- **Robust Ciphers**: AES-256-XTS, Serpent, Twofish, Camellia, and Kuznyechik — including VeraCrypt’s cascaded cipher options (15 total cipher combinations).
- **Key Derivation Functions (KDF)**: PBKDF2 (SHA-512, SHA-256, Whirlpool, Streebog, BLAKE2s-256) and memory-hard Argon2id.
- **LUKS Flexibility**: Compatible with AES, Serpent, Twofish, Camellia, or Kuznyechik in `xts-plain64` mode using PBKDF2 or Argon2id/Argon2i keyslots.
- **Parallel Auto-Detection**: Live multi-threaded key derivation testing with real-time progress indicators and key/cipher caching for near-instant re-unlocks.
- **Keyfiles & Hidden Volumes**: Supports password mixing (VeraCrypt) or keyfile-only / passphrase options (`cryptsetup`). Hidden volumes are dynamically resolved on unlock.
- **Multi-Mount**: Simultaneously mount up to **8 containers or directory vaults** from local storage, `content://` URIs, or external USB OTG drives.

### 💾 Filesystems & Storage
- **Broad Filesystem Support**: In-memory read/write capabilities for **FAT32**, **exFAT**, **NTFS**, and **ext2/ext3/ext4** (auto-detected upon mounting).
- **USB OTG Support**: Mount containers directly from external USB flash drives/hard drives without requiring root privileges. Includes partition table parsing (MBR/GPT) and instant auto-lock on OTG disconnection.
- **Container Creation**: Create and format brand new encrypted containers directly on-device in any supported filesystem.

### 📁 File & Security Management
- **Intuitive File Explorer**: Modern file browser with breadcrumb navigation, grid/list view toggles, instant search, filtering, and sorting options.
- **Batch Clipboard Operations**: Move, copy, rename, delete, or batch-export files with background progress tracking and conflict handling.
- **Built-in Password Manager**: Store and manage encrypted vault items (passwords, payment cards, notes, identities) with field reveals and secure single-tap copying.
- **Media Streaming**: Native internal video/audio player (supporting `.srt`/`.vtt` subtitles, speed control, loop) and image viewer (zoom, pan, rotation, slideshow) with **on-the-fly streaming** via virtual file descriptors (no temporary unencrypted file creation).
- **Android SAF Integration**: Integrates with Android's Storage Access Framework (`DocumentsProvider`), allowing third-party apps to access mounted vault contents safely.

### 🛡️ Privacy & App Security
- **App Master Password**: Optional app-wide master key protection featuring exponential lockout backoff surviving app force-kills.
- **Biometric & Pattern Unlock**: Secure container keys using Android Biometrics (Fingerprint/Face) backed by Android Keystore hardware security modules.
- **Auto-Lock Timers**: Customizable background auto-lock time triggers per container or system-wide.
- **Screen & Data Protection**: Screenshot blocking option (`FLAG_SECURE`) and encrypted thumbnail caching (or thumbnail cache suppression).

---

## ⚙️ Building from Source

### Requirements
- **Flutter SDK**: `>= 3.12.0`
- **Android SDK**: API 26+ (Android 8.0 Oreo or newer)
- **Android NDK**: Configured in `android/app/build.gradle` / `flutter.ndkVersion`
- **CMake**: `3.18+`

### Build Steps

1. **Clone the repository**:
```bash
git clone https://github.com/R0b0To/VaultExplorer.git
cd VaultExplorer
```

2. **Fetch Flutter dependencies**:
```bash
flutter pub get
```

3. **Build the APK**:
```bash
flutter build apk --release
```
> *Note: CMake will automatically download and compile the native C++ dependencies (`mbedTLS`, `FatFs`, `NTFS-3G`, `libext2fs`, `cJSON`, and `VeraCrypt 1.26.29` primitives) during the build step.*

---

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/K3K2ND3Y8)