#include "fv_gocryptfs.h"

#include <algorithm>
#include <cstring>

#include "fv_json.h"
#include "crypto/eme.h"
#include "crypto/siv.h"

namespace fv::gocryptfs {

static const CipherInfo kGcm = {"AES-GCM file content encryption", 32, 16};
static const CipherInfo kXChaCha = {"XChaCha20-Poly1305 file content encryption", 32, 24};
static const CipherInfo kSiv = {"AES-SIV file content encryption", 64, 16};

const CipherInfo& cipherInfo(GocryptfsCipher c) {
    switch (c) {
        case GocryptfsCipher::XChaCha20Poly1305: return kXChaCha;
        case GocryptfsCipher::AesSiv: return kSiv;
        default: return kGcm;
    }
}

// ------------------------------------------------------------------ config --

bool Config::hasFlag(const std::string& f) const {
    return std::find(featureFlags.begin(), featureFlags.end(), f) != featureFlags.end();
}

static const json::Value& need(const json::Value& obj, const char* key) {
    const json::Value* v = obj.find(key);
    if (!v) throw Error(Err::InvalidVault, std::string("gocryptfs.conf is missing \"") + key + "\"");
    return *v;
}

static Bytes needB64(const json::Value& obj, const char* key) {
    const json::Value& v = need(obj, key);
    Bytes out;
    if (!v.isString() || !base64Decode(v.asString(), out))
        throw Error(Err::InvalidVault, std::string("gocryptfs.conf field \"") + key + "\" is not valid base64");
    return out;
}

Config Config::parse(const std::string& text) {
    json::Value root;
    try {
        root = json::parse(text);
    } catch (const Error& e) {
        throw Error(Err::InvalidVault, std::string("gocryptfs.conf is not valid JSON: ") + e.what());
    }
    if (!root.isObject()) throw Error(Err::InvalidVault, "gocryptfs.conf is not valid JSON: not an object");

    Config c;
    const json::Value* ver = root.find("Version");
    c.version = ver && ver->isInt() ? (int)ver->asInt() : -1;
    if (c.version != 2)
        throw Error(Err::InvalidVault, "Unsupported on-disk format version " + std::to_string(c.version) + " (only 2 is supported)");

    const json::Value& scrypt = need(root, "ScryptObject");
    if (const json::Value* ff = root.find("FeatureFlags")) {
        for (const auto& it : ff->items()) {
            if (!it.isString()) throw Error(Err::InvalidVault, "gocryptfs.conf FeatureFlags must be strings");
            if (!c.hasFlag(it.asString())) c.featureFlags.push_back(it.asString());
        }
    }

    bool gcmIv = c.hasFlag("GCMIV128"), xchacha = c.hasFlag("XChaCha20Poly1305");
    bool aessiv = c.hasFlag("AESSIV"), plain = c.hasFlag("PlaintextNames");

    std::vector<std::string> problems;
    if (!c.hasFlag("HKDF")) problems.push_back("missing HKDF");
    if (!plain) {
        if (!c.hasFlag("EMENames")) problems.push_back("missing EMENames");
        if (!c.hasFlag("Raw64")) problems.push_back("missing Raw64");
    }
    static const std::set<std::string> known = {"GCMIV128", "XChaCha20Poly1305", "AESSIV", "DirIV", "EMENames",
                                                "LongNames", "Raw64", "HKDF", "PlaintextNames", "FIDO2"};
    std::string unsupported;
    for (auto& f : c.featureFlags) if (!known.count(f)) unsupported += (unsupported.empty() ? "" : ", ") + f;
    if (!unsupported.empty()) problems.push_back("unsupported feature flags [" + unsupported + "]");

    // internal/configfile/validate.go: AESSIV *requires* GCMIV128, XChaCha20Poly1305
    // conflicts with both GCMIV128 and AESSIV.
    if (xchacha && aessiv) problems.push_back("XChaCha20Poly1305 conflicts with AESSIV");
    else if (xchacha && gcmIv) problems.push_back("XChaCha20Poly1305 conflicts with GCMIV128");
    else if (aessiv && !gcmIv) problems.push_back("AESSIV requires GCMIV128");
    else if (!xchacha && !gcmIv) problems.push_back("missing a content cipher feature flag");

    if (!problems.empty()) {
        std::string joined;
        for (size_t i = 0; i < problems.size(); i++) joined += (i ? "; " : "") + problems[i];
        throw Error(Err::InvalidVault, "Unsupported gocryptfs feature flags: " + joined +
                    ". This app supports standard vaults created with AES-256-GCM, XChaCha20-Poly1305 or AES-SIV.");
    }
    c.cipher = xchacha ? GocryptfsCipher::XChaCha20Poly1305 : (aessiv ? GocryptfsCipher::AesSiv : GocryptfsCipher::Aes256Gcm);

    c.encryptedKey = needB64(root, "EncryptedKey");
    c.scryptSalt = needB64(scrypt, "Salt");
    c.scryptN = (uint32_t)need(scrypt, "N").asInt();
    c.scryptR = (uint32_t)need(scrypt, "R").asInt();
    c.scryptP = (uint32_t)need(scrypt, "P").asInt();
    c.scryptKeyLen = (uint32_t)need(scrypt, "KeyLen").asInt();
    if (const json::Value* l = root.find("LongNameMax")) c.longNameMax = (int)l->asInt();
    c.plaintextNames = plain;
    return c;
}

std::string Config::toJson() const {
    json::Value scrypt = json::Value::object();
    scrypt.set("Salt", json::Value::string(base64Encode(scryptSalt.data(), scryptSalt.size(), false, true)));
    scrypt.set("N", json::Value::integer(scryptN));
    scrypt.set("R", json::Value::integer(scryptR));
    scrypt.set("P", json::Value::integer(scryptP));
    scrypt.set("KeyLen", json::Value::integer(scryptKeyLen));
    json::Value flags = json::Value::array();
    for (auto& f : featureFlags) flags.push(json::Value::string(f));
    json::Value root = json::Value::object();
    root.set("Creator", json::Value::string("VaultExplorer"));
    root.set("EncryptedKey", json::Value::string(base64Encode(encryptedKey.data(), encryptedKey.size(), false, true)));
    root.set("ScryptObject", std::move(scrypt));
    root.set("Version", json::Value::integer(2));
    root.set("FeatureFlags", std::move(flags));
    if (longNameMax > 0) root.set("LongNameMax", json::Value::integer(longNameMax));
    return root.dump(2);
}

// --------------------------------------------------------------- masterkey --

static constexpr size_t kMkNonce = 16, kTag = 16;

Secret unlockMasterkey(const Config& cfg, const uint8_t* pw, size_t pwLen) {
    Secret hash = crypto::scrypt(pw, pwLen, cfg.scryptSalt.data(), cfg.scryptSalt.size(), cfg.scryptN, cfg.scryptR,
                                 cfg.scryptP ? cfg.scryptP : 1, cfg.scryptKeyLen);
    Secret gcmKey = crypto::hkdfSha256(hash.data(), hash.size(), "AES-GCM file content encryption", 32);
    const Bytes& blob = cfg.encryptedKey;
    if (blob.size() <= kMkNonce + kTag) throw Error(Err::InvalidVault, "EncryptedKey blob too short");
    bool zero = true;
    for (size_t i = 0; i < kMkNonce; i++) if (blob[i]) { zero = false; break; }
    if (zero) throw Error(Err::WrongPassword, "Wrong password for this vault.");
    crypto::AeadKey key(crypto::AeadKind::AesGcm, gcmKey.data(), gcmKey.size());
    uint8_t aad[8] = {0};   // block number 0, no file id
    Secret out(blob.size() - kMkNonce - kTag);
    if (!key.open(blob.data(), kMkNonce, aad, 8, blob.data() + kMkNonce, blob.size() - kMkNonce, out.data()))
        throw Error(Err::WrongPassword, "Wrong password for this vault.");
    return out;
}

Bytes wrapMasterkey(const Secret& mk, const uint8_t* pw, size_t pwLen, const Bytes& salt,
                    uint32_t N, uint32_t R, uint32_t P, uint32_t keyLen) {
    Secret hash = crypto::scrypt(pw, pwLen, salt.data(), salt.size(), N, R, P ? P : 1, keyLen);
    Secret gcmKey = crypto::hkdfSha256(hash.data(), hash.size(), "AES-GCM file content encryption", 32);
    crypto::AeadKey key(crypto::AeadKind::AesGcm, gcmKey.data(), gcmKey.size());
    Bytes out(kMkNonce + mk.size() + kTag);
    crypto::randomKey(out.data(), kMkNonce);
    uint8_t aad[8] = {0};
    if (!key.seal(out.data(), kMkNonce, aad, 8, mk.data(), mk.size(), out.data() + kMkNonce))
        throw Error(Err::Io, "masterkey encryption failed");
    return out;
}

// -------------------------------------------------------------------- names --

NameCryptor::NameCryptor(const Secret& nameKey, int longNameMax, bool plaintext)
    : key_(nameKey), longNameMax_(longNameMax), plaintext_(plaintext) {}

std::string NameCryptor::encryptName(const std::string& plain, const uint8_t dirIv[16]) const {
    if (plaintext_) return plain;
    size_t pad = 16 - (plain.size() % 16);
    Bytes padded(plain.begin(), plain.end());
    padded.insert(padded.end(), pad, (uint8_t)pad);
    Bytes out(padded.size());
    if (!eme_transform(key_.data(), key_.size(), dirIv, padded.data(), out.data(), padded.size(), true))
        throw Error(Err::Io, "EME encryption failed");
    return base64Encode(out.data(), out.size(), true, false);
}

std::string NameCryptor::decryptName(const std::string& cipherName, const uint8_t dirIv[16]) const {
    if (plaintext_) return cipherName;
    for (char c : cipherName) {   // Raw64: URL-safe alphabet only
        bool ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '=';
        if (!ok) throw Error(Err::Auth, "Malformed base64 filename: " + cipherName);
    }
    Bytes raw;
    if (!base64Decode(cipherName, raw)) throw Error(Err::Auth, "Malformed base64 filename: " + cipherName);
    if (raw.empty() || raw.size() % 16 != 0) throw Error(Err::Auth, "Malformed ciphertext filename: " + cipherName);
    Bytes padded(raw.size());
    if (!eme_transform(key_.data(), key_.size(), dirIv, raw.data(), padded.data(), raw.size(), false))
        throw Error(Err::Auth, "EME decryption failed");
    uint8_t padLen = padded.back();
    if (padLen == 0 || padLen > 16 || padLen > padded.size()) throw Error(Err::Auth, "invalid PKCS7 padding");
    for (size_t i = padded.size() - padLen; i < padded.size(); i++)
        if (padded[i] != padLen) throw Error(Err::Auth, "invalid PKCS7 padding");
    std::string clear((const char*)padded.data(), padded.size() - padLen);
    bool bad = !isValidUtf8(clear) || clear.find("\xEF\xBF\xBD") != std::string::npos ||
               clear.find('/') != std::string::npos || clear.find('\0') != std::string::npos ||
               clear.find('\n') != std::string::npos || clear.find('\r') != std::string::npos ||
               clear == "." || clear == "..";
    if (bad) throw Error(Err::Auth, "Invalid decrypted filename (corrupted ciphertext or wrong diriv): " + cipherName);
    return clear;
}

std::string NameCryptor::hashLongName(const std::string& cipherName) const {
    Bytes d = crypto::hash(crypto::Md::Sha256, (const uint8_t*)cipherName.data(), cipherName.size());
    return std::string(kLongNamePrefix) + base64Encode(d.data(), d.size(), true, false);
}

bool NameCryptor::isOverLongNameLimit(const std::string& cipherName) const {
    if (plaintext_) return false;
    int max = longNameMax_ > 0 ? longNameMax_ : 255;
    return (int)cipherName.size() > max;
}

// ------------------------------------------------------------ content format --

namespace {
struct GFileKey : FileKey {
    uint8_t fileId[16];
};
}  // namespace

ContentFormat::ContentFormat(const Secret& key, GocryptfsCipher cipher)
    : cipher_(cipher), nonceLen_(cipherInfo(cipher).nonceLen), contentKey_(key) {
    if (key.size() != cipherInfo(cipher).contentKeyLen)
        throw Error(Err::Unsupported, "gocryptfs content key has the wrong length for this cipher");
    if (cipher == GocryptfsCipher::AesSiv) {
        // RFC 5297: LEFT half = K1 (S2V / CMAC), RIGHT half = K2 (CTR).
        sivMac_ = Secret(key.data(), 32);
        sivEnc_ = Secret(key.data() + 32, 32);
    } else {
        aead_ = std::make_unique<crypto::AeadKey>(
            cipher == GocryptfsCipher::XChaCha20Poly1305 ? crypto::AeadKind::XChaCha20Poly1305 : crypto::AeadKind::AesGcm,
            key.data(), key.size());
    }
}

std::shared_ptr<FileKey> ContentFormat::newHeader(Bytes& encoded) const {
    auto k = std::make_shared<GFileKey>();
    crypto::randomFast(k->fileId, 16);
    encoded.assign(kHeaderLen, 0);
    encoded[0] = 0x00;
    encoded[1] = 0x02;
    std::memcpy(encoded.data() + 2, k->fileId, 16);
    return k;
}

std::shared_ptr<FileKey> ContentFormat::decodeHeader(const uint8_t* p, size_t n) const {
    if (n < kHeaderLen) throw Error(Err::Auth, "File header too short");
    uint16_t version = (uint16_t)((p[0] << 8) | p[1]);
    if (version != 2) throw Error(Err::Auth, "Unsupported file format version " + std::to_string(version));
    auto k = std::make_shared<GFileKey>();
    std::memcpy(k->fileId, p + 2, 16);
    return k;
}

static void makeAad(uint8_t aad[24], uint64_t chunkNo, const uint8_t fileId[16]) {
    writeU64BE(aad, chunkNo);
    std::memcpy(aad + 8, fileId, 16);
}

void ContentFormat::sealChunk(const uint8_t fileId[16], uint64_t chunkNo, const uint8_t* nonce,
                       const uint8_t* pt, size_t n, uint8_t* out) const {
    uint8_t aad[24];
    makeAad(aad, chunkNo, fileId);
    std::memcpy(out, nonce, nonceLen_);
    if (cipher_ == GocryptfsCipher::AesSiv) {
        // AD = [blockNo|fileId, nonce]; block = nonce | siv-tag | ciphertext.
        std::vector<std::vector<uint8_t>> ad;
        ad.emplace_back(aad, aad + 24);
        ad.emplace_back(nonce, nonce + nonceLen_);
        if (!siv_encrypt(sivEnc_.data(), sivEnc_.size(), sivMac_.data(), sivMac_.size(), pt, n, ad,
                         out + nonceLen_, 16 + n))
            throw Error(Err::Io, "AES-SIV encryption failed");
        return;
    }
    if (!aead_->seal(nonce, nonceLen_, aad, 24, pt, n, out + nonceLen_))
        throw Error(Err::Io, "chunk encryption failed");
}

void ContentFormat::openChunk(const uint8_t fileId[16], uint64_t chunkNo, const uint8_t* ct, size_t n, uint8_t* out) const {
    if (n < nonceLen_ + 16) throw Error(Err::Auth, "Truncated chunk " + std::to_string(chunkNo));
    // A sparse hole: an all-zero ciphertext block decrypts to zeros (gocryptfs).
    if (n == ciphertextChunk()) {
        bool allZero = true;
        for (size_t i = 0; i < n; i++) if (ct[i]) { allZero = false; break; }
        if (allZero) { std::memset(out, 0, kChunk); return; }
    }
    bool zeroNonce = true;
    for (size_t i = 0; i < nonceLen_; i++) if (ct[i]) { zeroNonce = false; break; }
    if (zeroNonce) throw Error(Err::Auth, "all-zero nonce");
    uint8_t aad[24];
    makeAad(aad, chunkNo, fileId);
    const uint8_t* body = ct + nonceLen_;
    size_t bodyLen = n - nonceLen_;
    bool ok;
    if (cipher_ == GocryptfsCipher::AesSiv) {
        std::vector<std::vector<uint8_t>> ad;
        ad.emplace_back(aad, aad + 24);
        ad.emplace_back(ct, ct + nonceLen_);
        ok = siv_decrypt(sivEnc_.data(), sivEnc_.size(), sivMac_.data(), sivMac_.size(), body, bodyLen, ad, out, bodyLen - 16);
    } else {
        ok = aead_->open(ct, nonceLen_, aad, 24, body, bodyLen, out);
    }
    if (!ok) throw Error(Err::Auth, "Chunk " + std::to_string(chunkNo) + " authentication failed -- wrong key or corrupted/tampered file.");
}

void ContentFormat::encrypt(const FileKey& k, uint64_t first, const uint8_t* in, size_t n, uint8_t* out) const {
    const auto& gk = static_cast<const GFileKey&>(k);
    const size_t nChunks = (n + kChunk - 1) / kChunk;
    const size_t ccs = ciphertextChunk();
    Bytes nonces(nChunks * nonceLen_);
    crypto::randomFast(nonces.data(), nonces.size());
    std::atomic<bool> failed{false};
    bool ok = crypto::parallelRanges(nChunks, 16, [&](size_t s, size_t e) {
        try {
            for (size_t i = s; i < e; i++) {
                size_t len = std::min(kChunk, n - i * kChunk);
                sealChunk(gk.fileId, first + i, nonces.data() + i * nonceLen_, in + i * kChunk, len, out + i * ccs);
            }
            return true;
        } catch (...) { failed = true; return false; }
    });
    if (!ok || failed) throw Error(Err::Io, "chunk encryption failed");
}

void ContentFormat::decrypt(const FileKey& k, uint64_t first, const uint8_t* in, size_t n, uint8_t* out) const {
    const auto& gk = static_cast<const GFileKey&>(k);
    const size_t ccs = ciphertextChunk();
    const size_t nChunks = (n + ccs - 1) / ccs;
    std::atomic<bool> failed{false};
    std::string firstErr;
    std::mutex errMu;
    bool ok = crypto::parallelRanges(nChunks, 16, [&](size_t s, size_t e) {
        try {
            for (size_t i = s; i < e; i++) {
                size_t len = std::min(ccs, n - i * ccs);
                openChunk(gk.fileId, first + i, in + i * ccs, len, out + i * kChunk);
            }
            return true;
        } catch (const std::exception& ex) {
            std::lock_guard<std::mutex> g(errMu);
            if (!failed.exchange(true)) firstErr = ex.what();
            return false;
        }
    });
    if (!ok || failed) throw Error(Err::Auth, firstErr.empty() ? "chunk authentication failed" : firstErr);
}

int64_t ContentFormat::cleartextSize(int64_t physical) const {
    if (physical <= (int64_t)kHeaderLen) return 0;
    int64_t body = physical - (int64_t)kHeaderLen;
    int64_t ccs = (int64_t)ciphertextChunk();
    int64_t full = body / ccs, rem = body % ccs;
    int64_t out = full * (int64_t)kChunk;
    if (rem > 0) out += std::max<int64_t>(0, rem - (int64_t)(nonceLen_ + 16));
    return out;
}

}  // namespace fv::gocryptfs
