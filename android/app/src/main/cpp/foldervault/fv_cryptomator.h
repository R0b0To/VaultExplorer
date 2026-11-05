// Cryptomator vault format 7 / 8 building blocks (SIV_CTRMAC / SIV_GCM).
#pragma once

#include <memory>
#include <string>

#include "fv_crypto.h"
#include "fv_engine.h"
#include "fv_vault.h"

namespace fv::cryptomator {

constexpr const char* kVaultFile = "vault.cryptomator";
constexpr const char* kMasterkeyFile = "masterkey.cryptomator";
constexpr const char* kDataDir = "d";
constexpr int kDefaultShortening = 220;
constexpr int kCurrentVaultFormat = 8;
constexpr const char* kCurrentCipherCombo = "SIV_GCM";

// 64 bytes: encKey (32) || macKey (32).
class Masterkey {
public:
    Masterkey() = default;
    explicit Masterkey(Secret raw) : raw_(std::move(raw)) {
        if (raw_.size() != 64) throw Error(Err::InvalidVault, "Masterkey must be 64 bytes");
    }
    const uint8_t* enc() const { return raw_.data(); }
    const uint8_t* mac() const { return raw_.data() + 32; }
    const Secret& raw() const { return raw_; }
private:
    Secret raw_;
};

struct MasterkeyFile {
    int version = 999;
    Bytes scryptSalt;
    int scryptCostParam = 0, scryptBlockSize = 0;
    Bytes primaryMasterKey, hmacMasterKey, versionMac;
    static MasterkeyFile parse(const std::string& jsonText);   // throws InvalidVault
};
// Throws WrongPassword / InvalidVault.
Masterkey unlockMasterkey(const MasterkeyFile& f, const uint8_t* pw, size_t pwLen);
std::string lockMasterkey(const Masterkey& mk, const uint8_t* pw, size_t pwLen, int vaultVersion);

struct VaultConfig {
    int vaultFormat = 8;
    std::string cipherCombo = "SIV_GCM";
    int shorteningThreshold = kDefaultShortening;
};
// Verifies the JWT signature with the masterkey. Throws InvalidVault.
VaultConfig verifyVaultConfig(const std::string& jwt, const Masterkey& mk);
std::string createVaultConfig(int format, const std::string& combo, int threshold, const Masterkey& mk, const std::string& vaultId);

class NameCryptor {
public:
    explicit NameCryptor(const Masterkey& mk) : mk_(mk) {}
    // 32 base32 chars: the directory's location under d/ is <2>/<30>.
    std::string hashDirectoryId(const std::string& dirId) const;
    std::string encryptFilename(const std::string& cleartext, const std::string& dirId) const;
    // Throws Error(Auth).
    std::string decryptFilename(const std::string& ciphertext, const std::string& dirId) const;
private:
    const Masterkey& mk_;
};

enum class Combo { SivGcm, SivCtrMac };

class ContentFormat : public FileFormat {
public:
    ContentFormat(const Masterkey& mk, Combo combo);
    size_t headerSize() const override { return headerSize_; }
    size_t cleartextChunk() const override { return 32 * 1024; }
    size_t ciphertextChunk() const override { return nonceLen_ + 32 * 1024 + tagLen_; }
    std::shared_ptr<FileKey> newHeader(Bytes& encoded) const override;
    std::shared_ptr<FileKey> decodeHeader(const uint8_t* p, size_t n) const override;
    void encrypt(const FileKey& k, uint64_t first, const uint8_t* in, size_t n, uint8_t* out) const override;
    void decrypt(const FileKey& k, uint64_t first, const uint8_t* in, size_t n, uint8_t* out) const override;
    int64_t cleartextSize(int64_t physicalSize) const override;
    Combo combo() const { return combo_; }
private:
    const Masterkey& mk_;
    Combo combo_;
    size_t nonceLen_, tagLen_, headerSize_;
    std::unique_ptr<crypto::AeadKey> headerAead_;   // GCM: masterkey enc key
};

}  // namespace fv::cryptomator
