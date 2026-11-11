// gocryptfs (v2 on-disk format) building blocks. Exposed in a header so the
// host tests can exercise each piece against known-answer vectors; everything
// the app uses goes through fv_vault.h.
#pragma once

#include <memory>
#include <set>
#include <string>

#include "fv_crypto.h"
#include "fv_engine.h"
#include "fv_vault.h"

namespace fv::gocryptfs {

constexpr const char* kConfigName = "gocryptfs.conf";
// Not a gocryptfs file: the backup VaultExplorer's Check & Repair keeps of the config.
constexpr const char* kConfigBakName = "gocryptfs.conf.bak";
constexpr const char* kDirIvName = "gocryptfs.diriv";
constexpr const char* kLongNamePrefix = "gocryptfs.longname.";
constexpr const char* kLongNameSuffix = ".name";
constexpr size_t kNameMax = 255;           // longest cleartext name (nametransform.NameMax)
constexpr size_t kLongNameFileMax = 344;   // largest legal gocryptfs.longname.*.name (255 padded to 256, base64)
constexpr size_t kDirIvLen = 16;

struct CipherInfo {
    const char* hkdfInfo;
    size_t contentKeyLen;
    size_t nonceLen;
};
const CipherInfo& cipherInfo(GocryptfsCipher c);

struct Config {
    Bytes encryptedKey;
    Bytes scryptSalt;
    uint32_t scryptN = 0, scryptR = 0, scryptP = 1;
    uint32_t scryptKeyLen = 32;
    int version = 0;
    std::string creator;                     // "Creator" (informational; preserved on rewrite)
    std::vector<std::string> featureFlags;   // file order preserved
    int longNameMax = 0;                     // "LongNameMax"; 0 = unset (names are hashed above 255 bytes)
    GocryptfsCipher cipher = GocryptfsCipher::Aes256Gcm;
    bool plaintextNames = false;

    bool hasFlag(const std::string& f) const;
    bool hasDirIV() const { return hasFlag("DirIV"); }
    // Without the HKDF flag (gocryptfs <= 1.2) the master key is used as-is for every purpose and the
    // config's own EncryptedKey uses a 96-bit nonce.
    bool hasHkdf() const { return hasFlag("HKDF"); }
    // Without Raw64 (gocryptfs <= 1.6) names and long-name hashes are padded base64.
    bool raw64() const { return hasFlag("Raw64"); }
    // -fido2: the scrypt input is a hmac-secret from a hardware token, not a password.
    bool fido2() const { return hasFlag("FIDO2"); }
    // "-deterministic-names": no DirIV flag => no gocryptfs.diriv files, every directory uses the all-zero IV.
    bool deterministicNames() const { return !plaintextNames && !hasDirIV(); }
    // Applies the same checks as gocryptfs' ConfFile.Validate(). Throws Error(InvalidVault).
    static Config parse(const std::string& jsonText);
    std::string toJson() const;
};

// scrypt (+ HKDF, for vaults that have the flag) unwrap of the 32-byte master key. Throws WrongPassword /
// InvalidVault / Unsupported (FIDO2).
Secret unlockMasterkey(const Config& cfg, const uint8_t* pw, size_t pwLen);
// [hkdf] must match the vault's HKDF flag, otherwise gocryptfs cannot unlock the result.
Bytes wrapMasterkey(const Secret& masterkey, const uint8_t* pw, size_t pwLen, const Bytes& salt,
                    uint32_t N, uint32_t R, uint32_t P, uint32_t keyLen, bool hkdf = true);

// The two keys a session needs, derived from the master key the way gocryptfs' cryptocore does:
// HKDF-SHA256 with a per-purpose info string, or -- vaults without the HKDF flag -- the master key
// itself (AES-SIV: its SHA-512, since it needs 64 bytes).
struct SessionKeys {
    Secret nameKey;      // empty for plaintext names
    Secret contentKey;
};
SessionKeys deriveSessionKeys(const Config& cfg, const Secret& masterkey);

class NameCryptor {
public:
    // raw64: unpadded base64 (feature flag Raw64). Older vaults use padded base64 for names *and* for the
    // hash in gocryptfs.longname.<hash>.
    NameCryptor(const Secret& nameKey, int longNameMax, bool plaintextNames, bool raw64 = true);
    // Throws Error(Unsupported) if [plain] is not a legal name (see isValidName).
    std::string encryptName(const std::string& plain, const uint8_t dirIv[16]) const;
    // Throws Error(Auth) for anything that is not a valid encrypted name -- including base64 that is
    // not in canonical form (gocryptfs rejects malleable encodings).
    std::string decryptName(const std::string& cipherName, const uint8_t dirIv[16]) const;
    std::string hashLongName(const std::string& cipherName) const;
    // True if [cipherName] has to be stored as gocryptfs.longname.<hash> + .name.
    bool isOverLongNameLimit(const std::string& cipherName) const;
    bool plaintextNames() const { return plaintext_; }
    bool raw64() const { return raw64_; }
    int longNameMax() const { return longNameMax_; }

    // nametransform.IsValidName: non-empty, <= 255 bytes, no NUL or '/', not "." / "..". (Like
    // gocryptfs it allows newlines and U+FFFD; only the UTF-8 requirement below is ours.)
    static bool isValidName(std::string_view name);
    // True for names the OS/Java/Dart layers can carry: valid + well-formed UTF-8.
    static bool isRepresentableName(std::string_view name);
    // gocryptfs.longname.<hash>  (the content file)
    static bool isLongNameContent(std::string_view physicalName);
    // gocryptfs.longname.<hash>.name  (the sidecar holding the full encrypted name)
    static bool isLongNameFile(std::string_view physicalName);
private:
    Secret key_;
    int longNameMax_;
    bool plaintext_;
    bool raw64_;
};

class ContentFormat : public FileFormat {
public:
    static constexpr size_t kHeaderLen = 18;
    static constexpr size_t kChunk = 4096;
    ContentFormat(const Secret& contentKey, GocryptfsCipher cipher);

    size_t headerSize() const override { return kHeaderLen; }
    size_t cleartextChunk() const override { return kChunk; }
    size_t ciphertextChunk() const override { return nonceLen_ + kChunk + 16; }
    std::shared_ptr<FileKey> newHeader(Bytes& encoded) const override;
    std::shared_ptr<FileKey> decodeHeader(const uint8_t* p, size_t n) const override;
    void encrypt(const FileKey& k, uint64_t first, const uint8_t* in, size_t n, uint8_t* out) const override;
    void decrypt(const FileKey& k, uint64_t first, const uint8_t* in, size_t n, uint8_t* out) const override;
    int64_t cleartextSize(int64_t physicalSize) const override;

    GocryptfsCipher cipher() const { return cipher_; }
    // Single-chunk primitives (public for known-answer tests).
    void sealChunk(const uint8_t fileId[16], uint64_t chunkNo, const uint8_t* nonce,
                   const uint8_t* pt, size_t n, uint8_t* out) const;
    void openChunk(const uint8_t fileId[16], uint64_t chunkNo,
                   const uint8_t* ct, size_t n, uint8_t* out) const;
    const Secret& contentKey() const { return contentKey_; }
private:
    GocryptfsCipher cipher_;
    size_t nonceLen_;
    Secret contentKey_;
    std::unique_ptr<crypto::AeadKey> aead_;   // GCM / XChaCha
    Secret sivEnc_, sivMac_;                   // AES-SIV halves
};

}  // namespace fv::gocryptfs
