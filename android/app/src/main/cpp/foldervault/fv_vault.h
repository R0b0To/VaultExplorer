// Public API of the folder-vault core: one fv::Vault per unlocked vault,
// produced by the open/create functions below. The method set mirrors the
// Kotlin `VaultBackend` interface the engines used to implement, so the
// Android layer is a thin adapter and a desktop front-end (FUSE, CLI, ...)
// can sit on the same calls.
#pragma once

#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "fv_common.h"
#include "fv_storage.h"

namespace fv {

enum class VaultFormat { Gocryptfs, Cryptomator, Cryfs };

// Source of plaintext for imports (an InputStream on Android).
struct ByteSource {
    virtual ~ByteSource() = default;
    // Returns bytes read (>0), 0 at end of stream, <0 on error.
    virtual int64_t read(uint8_t* buf, size_t n) = 0;
};

// Observer for long transfers. The host maps these to whatever progress and
// cancellation machinery it has (Android: Copy/Export progress bridges).
struct Progress {
    virtual ~Progress() = default;
    // Plaintext bytes just encrypted into the vault (import / copy-in).
    virtual void onWriteBack(uint64_t /*bytes*/) {}
    // Plaintext bytes just decrypted out of the vault (export / copy-out).
    virtual void onExtract(uint64_t /*bytes*/) {}
    virtual bool cancelled() { return false; }
};

// Snapshot of the key material a live vault holds, for the Check & Repair
// tooling that still runs in Kotlin. Format-specific layout, documented in
// fv_vault.cpp next to each exporter.
struct KeyExport {
    VaultFormat format;
    std::vector<std::pair<std::string, Bytes>> fields;
    std::vector<std::pair<std::string, std::string>> strings;
};

// One entry of Vault::info(); typed so the host can hand the UI real ints/bools.
struct InfoItem {
    enum class Kind { Str, Int, Bool } kind = Kind::Str;
    std::string key;
    std::string value;   // "true"/"false" for Bool, decimal for Int
};

class Vault {
public:
    virtual ~Vault() = default;

    virtual VaultFormat format() const = 0;
    virtual bool readOnly() const = 0;

    // ---- namespace (paths are cleartext, '/'-separated) ----------------
    virtual bool listDirectory(const std::string& path, std::vector<DirEntry>& out) = 0;
    virtual bool createDirectory(const std::string& path) = 0;
    virtual bool renameFile(const std::string& from, const std::string& to) = 0;
    virtual bool setLastModifiedTime(const std::string& path, int64_t epochSeconds) = 0;
    virtual bool deleteFile(const std::string& path) = 0;
    virtual int64_t getFileSize(const std::string& path) = 0;      // -1 if missing / a directory
    virtual int64_t getFolderSize(const std::string& path) = 0;

    // ---- content --------------------------------------------------------
    // nullopt = failure; an empty vector = EOF / empty file.
    virtual std::optional<Bytes> readFileChunk(const std::string& path, int64_t offset, int length) = 0;
    // Incremental writer: chunks must arrive in order starting at 0; the file
    // becomes visible/valid at finishWrite().
    virtual bool writeFileChunk(const std::string& path, int64_t offset, const uint8_t* data, size_t len) = 0;
    virtual bool finishWrite(const std::string& path) = 0;
    virtual bool writeBackFile(const std::string& path, const std::string& sourceFile, Progress* progress) = 0;
    virtual bool importStream(const std::string& path, ByteSource& source, Progress* progress) = 0;
    virtual bool extractFile(const std::string& path, const std::string& destFile, Progress* progress) = 0;

    // ---- batching / caches ---------------------------------------------
    virtual void beginBatchWrite() = 0;
    virtual void endBatchWrite() = 0;
    virtual void beginBatchDelete() = 0;
    virtual void endBatchDelete() = 0;
    virtual void invalidateCache(const std::string& path) = 0;

    virtual bool spaceInfo(int64_t& total, int64_t& free) = 0;
    virtual std::vector<InfoItem> info() = 0;
    virtual KeyExport exportKeys() = 0;

    // Stops accepting work, aborts open writes, waits for in-flight calls and
    // wipes all key material. Idempotent.
    virtual void close() = 0;
};

// ---- open / create / change password --------------------------------------

// Produces the Storage a session should run on. Open/unlock first runs on
// the "bootstrap" storage it is given (to read the config and verify the
// password); only after that succeeds is this called, so hosts can defer
// expensive per-session setup -- Android's SAF mirror -- until the password
// is known to be right. May throw fv::Error. Empty = keep the bootstrap.
using StorageFactory = std::function<std::shared_ptr<Storage>()>;

enum class OpenStatus { Ok, WrongPassword, InvalidVault };

struct OpenResult {
    OpenStatus status = OpenStatus::InvalidVault;
    std::unique_ptr<Vault> vault;   // set when status == Ok
    std::string message;            // human-readable reason when not Ok
    Secret derivedKey;              // CryFS: scrypt output, for the "remember" fast path
};

struct PlainResult {
    OpenStatus status = OpenStatus::InvalidVault;
    std::string message;
};

// Host-supplied context a vault may need beyond its Storage.
struct HostEnv {
    // CryFS keeps its per-install integrity bookkeeping (client id, known
    // block versions) outside the vault; this is the directory for it
    // (Android: filesDir/cryfs_localstate). Required for CryFS.
    std::string cryfsLocalStateDir;
    // Where incremental-write scratch files go (default: system temp).
    std::string tempDir;
};

enum class GocryptfsCipher { Aes256Gcm, XChaCha20Poly1305, AesSiv };

// Quick, password-free probe: does the root look like this format?
bool looksLikeGocryptfs(Storage& s);
bool looksLikeCryptomator(Storage& s);
bool looksLikeCryfs(Storage& s);

struct GocryptfsCreateOptions {
    GocryptfsCipher cipher = GocryptfsCipher::Aes256Gcm;
    bool plaintextNames = false;
};
struct CryfsCreateOptions {
    std::string cipher = "xchacha20-poly1305";
    int blocksizeBytes = 32 * 1024;
};

// [password] is raw UTF-8 bytes. The caller keeps ownership and wipes it.
OpenResult openGocryptfs(std::shared_ptr<Storage> s, const uint8_t* pw, size_t pwLen, bool readOnly, const HostEnv& env, const StorageFactory& sessionStorage = {});
// create* only writes the vault's on-disk skeleton through [s]; unlock it with open*
// afterwards (that is what lets the host choose its session storage after creation).
PlainResult createGocryptfs(Storage& s, const uint8_t* pw, size_t pwLen, const GocryptfsCreateOptions& o);
PlainResult changeGocryptfsPassword(Storage& s, const uint8_t* oldPw, size_t oldLen, const uint8_t* newPw, size_t newLen);

OpenResult openCryptomator(std::shared_ptr<Storage> s, const uint8_t* pw, size_t pwLen, bool readOnly, const HostEnv& env, const StorageFactory& sessionStorage = {});
PlainResult createCryptomator(Storage& s, const uint8_t* pw, size_t pwLen);
PlainResult changeCryptomatorPassword(Storage& s, const uint8_t* oldPw, size_t oldLen, const uint8_t* newPw, size_t newLen);

OpenResult openCryfs(std::shared_ptr<Storage> s, const uint8_t* pw, size_t pwLen, bool readOnly, const HostEnv& env, const StorageFactory& sessionStorage = {});
OpenResult openCryfsWithCombinedKey(std::shared_ptr<Storage> s, const uint8_t* key, size_t keyLen, bool readOnly, const HostEnv& env, const StorageFactory& sessionStorage = {});
PlainResult createCryfs(Storage& s, const uint8_t* pw, size_t pwLen, const CryfsCreateOptions& o, const HostEnv& env);
PlainResult changeCryfsPassword(Storage& s, const uint8_t* oldPw, size_t oldLen, const uint8_t* newPw, size_t newLen);

}  // namespace fv
