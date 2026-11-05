// gocryptfs (v2 on-disk format) building blocks. Exposed in a header so the
// host tests can exercise each piece against known-answer vectors; everything
// the app uses goes through fv_vault.h.
#pragma once

#include <memory>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "fv_crypto.h"
#include "fv_engine.h"
#include "fv_vault.h"

namespace fv::gocryptfs {

constexpr const char* kConfigName = "gocryptfs.conf";
constexpr const char* kConfigBakName = "gocryptfs.conf.bak";
constexpr const char* kDirIvName = "gocryptfs.diriv";
constexpr const char* kLongNamePrefix = "gocryptfs.longname.";
constexpr const char* kLongNameSuffix = ".name";

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
    std::vector<std::string> featureFlags;   // file order preserved
    int longNameMax = 0;
    GocryptfsCipher cipher = GocryptfsCipher::Aes256Gcm;
    bool plaintextNames = false;
    std::optional<Fido2Params> fido2;   // set exactly when the FIDO2 feature flag is present

    bool hasFlag(const std::string& f) const;
    bool hasDirIV() const { return hasFlag("DirIV"); }
    // Throws Error(InvalidVault) with the same messages the Kotlin parser used.
    static Config parse(const std::string& jsonText);
    std::string toJson() const;
};

// scrypt + HKDF unwrap of the 32-byte master key. Throws WrongPassword /
// InvalidVault.
Secret unlockMasterkey(const Config& cfg, const uint8_t* pw, size_t pwLen);
Bytes wrapMasterkey(const Secret& masterkey, const uint8_t* pw, size_t pwLen, const Bytes& salt,
                    uint32_t N, uint32_t R, uint32_t P, uint32_t keyLen);

class NameCryptor {
public:
    NameCryptor(const Secret& nameKey, int longNameMax, bool plaintextNames);
    std::string encryptName(const std::string& plain, const uint8_t dirIv[16]) const;
    // Throws Error(Auth) for anything that is not a valid encrypted name.
    std::string decryptName(const std::string& cipherName, const uint8_t dirIv[16]) const;
    std::string hashLongName(const std::string& cipherName) const;
    bool isOverLongNameLimit(const std::string& cipherName) const;
    bool plaintextNames() const { return plaintext_; }
    int longNameMax() const { return longNameMax_; }
private:
    Secret key_;
    int longNameMax_;
    bool plaintext_;
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
