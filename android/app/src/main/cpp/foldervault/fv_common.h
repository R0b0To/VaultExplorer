// foldervault -- platform-neutral core of VaultExplorer's folder-vault
// engines (gocryptfs, Cryptomator, CryFS).
//
// This directory has NO Android, JNI or Flutter dependency on purpose: the
// Android app reaches it through jni/foldervault_bridge.cpp, and a desktop
// build can link the very same sources and talk to it through fv::Vault
// (fv_vault.h) over fv::PosixStorage (fv_storage.h). Anything that is
// platform policy (SAF, the mirror sync, per-volume locks, progress UI)
// lives behind the small interfaces in fv_storage.h / fv_vault.h.
#pragma once

#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace fv {

using Bytes = std::vector<uint8_t>;

// Failure categories. Public Vault methods never let these escape (they
// return false / nullopt like the Kotlin VaultBackend they replace did);
// open/create/changePassword report them through OpenResult.
enum class Err {
    Io,
    NotFound,
    Exists,
    Auth,          // chunk / header / block authentication failed
    InvalidVault,  // structurally not what it should be
    WrongPassword,
    ReadOnly,
    Unsupported,
    Cancelled,
    Closed,
    Rollback,      // CryFS integrity (error 24/25 equivalent)
};

class Error : public std::runtime_error {
public:
    Error(Err code, const std::string& msg) : std::runtime_error(msg), code_(code) {}
    Err code() const { return code_; }
private:
    Err code_;
};

// One entry of a virtual (cleartext) or physical directory listing.
struct DirEntry {
    std::string name;
    bool isDir = false;
    int64_t size = 0;      // cleartext size for virtual entries, 0 for dirs
    int64_t mtimeMs = 0;   // milliseconds since the epoch
    // Cryptomator only, and only ever set by Vault::listSymlinks: the entry is a symbolic link, not a
    // file or a folder. [size] is then the byte length of the link target. Plain listDirectory() never
    // returns such entries, so a consumer that does not know about symlinks cannot trip over one.
    bool isSymlink = false;
};

// ---- small helpers shared by every format -----------------------------

// Wipes memory in a way the optimiser cannot elide.
void secureZero(void* p, size_t n);

// Byte container that wipes itself on destruction; use for key material.
class Secret {
public:
    Secret() = default;
    explicit Secret(size_t n) : data_(n, 0) {}
    explicit Secret(const Bytes& b) : data_(b) {}
    Secret(const uint8_t* p, size_t n) : data_(p, p + n) {}
    Secret(const Secret&) = default;
    Secret(Secret&& o) noexcept : data_(std::move(o.data_)) { o.data_.clear(); }
    Secret& operator=(const Secret& o) { if (this != &o) { wipe(); data_ = o.data_; } return *this; }
    Secret& operator=(Secret&& o) noexcept { if (this != &o) { wipe(); data_ = std::move(o.data_); o.data_.clear(); } return *this; }
    ~Secret() { wipe(); }
    uint8_t* data() { return data_.data(); }
    const uint8_t* data() const { return data_.data(); }
    size_t size() const { return data_.size(); }
    bool empty() const { return data_.empty(); }
    const Bytes& bytes() const { return data_; }
    void wipe() { if (!data_.empty()) secureZero(data_.data(), data_.size()); data_.clear(); }
private:
    Bytes data_;
};

// Virtual-path arithmetic (mirrors saf/VaultPathUtils.kt exactly).
std::string normalizePath(std::string_view p);               // trims '/' on both ends
std::string parentOf(std::string_view normalized);
std::string nameOf(std::string_view normalized);
std::string joinPath(std::string_view parent, std::string_view name);
std::vector<std::string> splitSegments(std::string_view p);  // drops empty segments

// Little-endian / big-endian integer helpers.
inline uint16_t readU16LE(const uint8_t* p) { return (uint16_t)(p[0] | (p[1] << 8)); }
inline uint32_t readU32LE(const uint8_t* p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }
inline uint64_t readU64LE(const uint8_t* p) { return (uint64_t)readU32LE(p) | ((uint64_t)readU32LE(p + 4) << 32); }
inline void writeU16LE(uint8_t* p, uint16_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); }
inline void writeU32LE(uint8_t* p, uint32_t v) { for (int i = 0; i < 4; i++) p[i] = (uint8_t)(v >> (8 * i)); }
inline void writeU64LE(uint8_t* p, uint64_t v) { for (int i = 0; i < 8; i++) p[i] = (uint8_t)(v >> (8 * i)); }
inline void writeU64BE(uint8_t* p, uint64_t v) { for (int i = 0; i < 8; i++) p[i] = (uint8_t)(v >> (8 * (7 - i))); }
inline void writeU32BE(uint8_t* p, uint32_t v) { for (int i = 0; i < 4; i++) p[i] = (uint8_t)(v >> (8 * (3 - i))); }

// Text codecs.
std::string toHex(const uint8_t* p, size_t n);
bool fromHex(std::string_view s, Bytes& out);                 // case-insensitive
std::string base64Encode(const uint8_t* p, size_t n, bool urlSafe, bool pad);
bool base64Decode(std::string_view s, Bytes& out);            // accepts std + url alphabet, optional padding
std::string base32Encode(const uint8_t* p, size_t n);         // RFC 4648, no padding

// True if [s] is well-formed UTF-8 (no overlongs, surrogates or > U+10FFFF).
bool isValidUtf8(std::string_view s);

// Unicode NFC normalisation hook. The core cannot carry the Unicode tables:
// the host installs one (Android: java.text.Normalizer through JNI; desktop:
// ICU / utf8proc). Pure-ASCII input never needs it and bypasses the hook.
using NormalizerFn = std::string (*)(const std::string& utf8);
void setNfcNormalizer(NormalizerFn fn);
std::string nfc(const std::string& utf8);

// Leveled logging hook (host installs one; default is silent).
enum class LogLevel { Debug, Info, Warn, Error };
using LogFn = void (*)(LogLevel, const char* tag, const std::string& msg);
void setLogger(LogFn fn);
void logMsg(LogLevel lvl, const char* tag, const std::string& msg);

}  // namespace fv
