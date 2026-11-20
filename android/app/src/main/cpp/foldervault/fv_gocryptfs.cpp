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

static int64_t needInt(const json::Value& obj, const char* key) {
    const json::Value& v = need(obj, key);
    if (!v.isInt()) throw Error(Err::InvalidVault, std::string("gocryptfs.conf field \"") + key + "\" is not a number");
    return v.asInt();
}

// Every feature flag gocryptfs knows (internal/configfile/feature_flags.go). A config with any other flag
// is refused by gocryptfs itself, so we refuse it too instead of guessing.
static const std::set<std::string>& knownFlags() {
    static const std::set<std::string> k = {"PlaintextNames", "DirIV", "EMENames", "GCMIV128", "LongNames",
                                            "LongNameMax", "AESSIV", "Raw64", "HKDF", "FIDO2", "XChaCha20Poly1305"};
    return k;
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
    if (const json::Value* cr = root.find("Creator")) if (cr->isString()) c.creator = cr->asString();

    const json::Value& scrypt = need(root, "ScryptObject");
    if (!scrypt.isObject()) throw Error(Err::InvalidVault, "gocryptfs.conf field \"ScryptObject\" is not an object");
    if (const json::Value* ff = root.find("FeatureFlags")) {
        for (const auto& it : ff->items()) {
            if (!it.isString()) throw Error(Err::InvalidVault, "gocryptfs.conf FeatureFlags must be strings");
            if (!c.hasFlag(it.asString())) c.featureFlags.push_back(it.asString());
        }
    }

    c.encryptedKey = needB64(root, "EncryptedKey");
    c.scryptSalt = needB64(scrypt, "Salt");
    int64_t n = needInt(scrypt, "N"), r = needInt(scrypt, "R"), p = needInt(scrypt, "P"), kl = needInt(scrypt, "KeyLen");

    // configfile/scrypt.go validateParams(): refuse parameters that are too weak to mean anything. (gocryptfs
    // would additionally crash on a non-power-of-two N or a KeyLen other than 32; we report them cleanly.)
    if (n < (1 << 10)) throw Error(Err::InvalidVault, "gocryptfs.conf: scrypt N below 1024 (logN 10) is too low to make sense");
    if ((n & (n - 1)) != 0) throw Error(Err::InvalidVault, "gocryptfs.conf: scrypt N is not a power of two");
    // (N is held as uint32_t; the scrypt layer refuses what a device cannot allocate long before this.)
    if (n > ((int64_t)1 << 31)) throw Error(Err::InvalidVault, "gocryptfs.conf: scrypt N is unreasonably large");
    if (r < 8) throw Error(Err::InvalidVault, "gocryptfs.conf: scrypt parameter R below minimum 8");
    if (p < 1) throw Error(Err::InvalidVault, "gocryptfs.conf: scrypt parameter P below minimum 1");
    if (c.scryptSalt.size() < 32) throw Error(Err::InvalidVault, "gocryptfs.conf: scrypt salt shorter than 32 bytes");
    if (kl < 32) throw Error(Err::InvalidVault, "gocryptfs.conf: scrypt KeyLen below minimum 32");
    if (kl != 32) throw Error(Err::InvalidVault, "gocryptfs.conf: scrypt KeyLen other than 32 is not supported");
    if (r > 1024 || p > 1024) throw Error(Err::InvalidVault, "gocryptfs.conf: scrypt R/P out of range");
    c.scryptN = (uint32_t)n; c.scryptR = (uint32_t)r; c.scryptP = (uint32_t)p; c.scryptKeyLen = (uint32_t)kl;

    // "LongNameMax" is a Go uint8.
    if (const json::Value* l = root.find("LongNameMax")) {
        if (!l->isInt() || l->asInt() < 0 || l->asInt() > 255)
            throw Error(Err::InvalidVault, "gocryptfs.conf: LongNameMax must be a number between 0 and 255");
        c.longNameMax = (int)l->asInt();
    }

    bool gcmIv = c.hasFlag("GCMIV128"), xchacha = c.hasFlag("XChaCha20Poly1305");
    bool aessiv = c.hasFlag("AESSIV"), plain = c.hasFlag("PlaintextNames"), hkdf = c.hasFlag("HKDF");

    // The remaining rules are internal/configfile/validate.go, in the same order and with its wording.
    std::vector<std::string> problems;
    std::string unknown;
    for (auto& f : c.featureFlags) if (!knownFlags().count(f)) unknown += (unknown.empty() ? "" : ", ") + f;
    if (!unknown.empty()) problems.push_back("unknown feature flags [" + unknown + "]");

    if (xchacha && aessiv) problems.push_back("can't have both XChaCha20Poly1305 and AESSIV feature flags");
    else if (aessiv && !gcmIv) problems.push_back("AESSIV requires GCMIV128 feature flag");
    else if (xchacha) {
        if (gcmIv) problems.push_back("XChaCha20Poly1305 conflicts with GCMIV128 feature flag");
        if (!hkdf) problems.push_back("XChaCha20Poly1305 requires HKDF feature flag");
    } else if (!aessiv && !gcmIv) problems.push_back("AES-GCM requires GCMIV128 feature flag");

    if (plain) {
        for (const char* f : {"EMENames", "DirIV", "LongNames", "Raw64", "LongNameMax"})
            if (c.hasFlag(f)) problems.push_back(std::string("PlaintextNames conflicts with ") + f + " feature flag");
    }
    if (c.longNameMax != 0 && !c.hasFlag("LongNameMax"))
        problems.push_back("LongNameMax=" + std::to_string(c.longNameMax) + " but the LongNameMax feature flag is NOT set");
    if (c.longNameMax == 0 && c.hasFlag("LongNameMax"))
        problems.push_back("LongNameMax=0 but the LongNameMax feature flag IS set");

    if (!problems.empty()) {
        std::string joined;
        for (size_t i = 0; i < problems.size(); i++) joined += (i ? "; " : "") + problems[i];
        throw Error(Err::InvalidVault, "Unsupported gocryptfs configuration: " + joined +
                    ". This app supports gocryptfs vaults (on-disk format 2) with AES-256-GCM, XChaCha20-Poly1305 or AES-SIV.");
    }
    c.cipher = xchacha ? GocryptfsCipher::XChaCha20Poly1305 : (aessiv ? GocryptfsCipher::AesSiv : GocryptfsCipher::Aes256Gcm);
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
    root.set("Creator", json::Value::string(creator.empty() ? "VaultExplorer" : creator));
    root.set("EncryptedKey", json::Value::string(base64Encode(encryptedKey.data(), encryptedKey.size(), false, true)));
    root.set("ScryptObject", std::move(scrypt));
    root.set("Version", json::Value::integer(2));
    root.set("FeatureFlags", std::move(flags));
    if (longNameMax > 0) root.set("LongNameMax", json::Value::integer(longNameMax));
    return root.dump(2);
}

// --------------------------------------------------------------- masterkey --

static constexpr size_t kTag = 16;

// The config's own key wrap is AES-256-GCM with block number 0 and no file id (contentenc.DecryptBlock(.., 0, nil)).
// With HKDF the scrypt output is first expanded and the nonce is 128 bit; vaults from gocryptfs <= 1.2 use the
// scrypt output directly and a 96-bit nonce.
static size_t mkNonceLen(bool hkdf) { return hkdf ? 16 : 12; }
static Secret mkWrapKey(const Secret& scryptHash, bool hkdf) {
    return hkdf ? crypto::hkdfSha256(scryptHash.data(), scryptHash.size(), "AES-GCM file content encryption", 32) : scryptHash;
}

Secret unlockMasterkey(const Config& cfg, const uint8_t* pw, size_t pwLen) {
    if (cfg.fido2())
        throw Error(Err::Unsupported, "This vault is protected by a FIDO2 security key (gocryptfs -fido2). "
                                      "Unlocking with a hardware token is not supported by this app.");
    const bool hkdf = cfg.hasHkdf();
    const size_t nonceLen = mkNonceLen(hkdf);
    Secret hash = crypto::scrypt(pw, pwLen, cfg.scryptSalt.data(), cfg.scryptSalt.size(), cfg.scryptN, cfg.scryptR,
                                 cfg.scryptP ? cfg.scryptP : 1, cfg.scryptKeyLen);
    Secret gcmKey = mkWrapKey(hash, hkdf);
    const Bytes& blob = cfg.encryptedKey;
    if (blob.size() <= nonceLen + kTag) throw Error(Err::InvalidVault, "EncryptedKey blob too short");
    bool zero = true;
    for (size_t i = 0; i < nonceLen; i++) if (blob[i]) { zero = false; break; }
    if (zero) throw Error(Err::WrongPassword, "Wrong password for this vault.");
    crypto::AeadKey key(crypto::AeadKind::AesGcm, gcmKey.data(), gcmKey.size());
    uint8_t aad[8] = {0};   // block number 0, no file id
    Secret out(blob.size() - nonceLen - kTag);
    if (!key.open(blob.data(), nonceLen, aad, 8, blob.data() + nonceLen, blob.size() - nonceLen, out.data()))
        throw Error(Err::WrongPassword, "Wrong password for this vault.");
    // gocryptfs only ever uses 32-byte master keys (cryptocore.KeyLen) and panics on anything else.
    if (out.size() != 32) throw Error(Err::InvalidVault, "gocryptfs.conf: the master key is not 32 bytes long");
    return out;
}

Bytes wrapMasterkey(const Secret& mk, const uint8_t* pw, size_t pwLen, const Bytes& salt,
                    uint32_t N, uint32_t R, uint32_t P, uint32_t keyLen, bool hkdf) {
    Secret hash = crypto::scrypt(pw, pwLen, salt.data(), salt.size(), N, R, P ? P : 1, keyLen);
    Secret gcmKey = mkWrapKey(hash, hkdf);
    const size_t nonceLen = mkNonceLen(hkdf);
    crypto::AeadKey key(crypto::AeadKind::AesGcm, gcmKey.data(), gcmKey.size());
    Bytes out(nonceLen + mk.size() + kTag);
    crypto::randomKey(out.data(), nonceLen);
    uint8_t aad[8] = {0};
    if (!key.seal(out.data(), nonceLen, aad, 8, mk.data(), mk.size(), out.data() + nonceLen))
        throw Error(Err::Io, "masterkey encryption failed");
    return out;
}

SessionKeys deriveSessionKeys(const Config& cfg, const Secret& mk) {
    SessionKeys k;
    const CipherInfo& ci = cipherInfo(cfg.cipher);
    if (cfg.hasHkdf()) {
        if (!cfg.plaintextNames) k.nameKey = crypto::hkdfSha256(mk.data(), mk.size(), "EME filename encryption", 32);
        k.contentKey = crypto::hkdfSha256(mk.data(), mk.size(), ci.hkdfInfo, ci.contentKeyLen);
        return k;
    }
    // cryptocore.New(.., useHKDF=false): gocryptfs v0.7 .. v1.2 used the master key directly; AES-SIV (v1.1+)
    // needs 64 bytes and takes SHA-512 of it.
    if (!cfg.plaintextNames) k.nameKey = mk;
    if (cfg.cipher == GocryptfsCipher::AesSiv) {
        Bytes d = crypto::hash(crypto::Md::Sha512, mk.data(), mk.size());
        k.contentKey = Secret(d);
        secureZero(d.data(), d.size());
    } else {
        k.contentKey = mk;
    }
    return k;
}

// -------------------------------------------------------------------- names --

NameCryptor::NameCryptor(const Secret& nameKey, int longNameMax, bool plaintext, bool raw64)
    : key_(nameKey), longNameMax_(longNameMax), plaintext_(plaintext), raw64_(raw64) {}

bool NameCryptor::isValidName(std::string_view name) {
    if (name.empty() || name.size() > kNameMax) return false;
    if (name.find('\0') != std::string_view::npos || name.find('/') != std::string_view::npos) return false;
    return name != "." && name != "..";
}

bool NameCryptor::isRepresentableName(std::string_view name) { return isValidName(name) && isValidUtf8(name); }

bool NameCryptor::isLongNameContent(std::string_view n) {
    return n.rfind(kLongNamePrefix, 0) == 0 && !isLongNameFile(n);
}
bool NameCryptor::isLongNameFile(std::string_view n) {
    const std::string_view suf = kLongNameSuffix;
    return n.rfind(kLongNamePrefix, 0) == 0 && n.size() >= suf.size() && n.compare(n.size() - suf.size(), suf.size(), suf) == 0;
}

std::string NameCryptor::encryptName(const std::string& plain, const uint8_t dirIv[16]) const {
    if (!isValidName(plain)) throw Error(Err::Unsupported, "Invalid file name");
    if (plaintext_) return plain;
    size_t pad = 16 - (plain.size() % 16);
    Bytes padded(plain.begin(), plain.end());
    padded.insert(padded.end(), pad, (uint8_t)pad);
    Bytes out(padded.size());
    if (!eme_transform(key_.data(), key_.size(), dirIv, padded.data(), out.data(), padded.size(), true))
        throw Error(Err::Io, "EME encryption failed");
    return base64Encode(out.data(), out.size(), true, !raw64_);
}

std::string NameCryptor::decryptName(const std::string& cipherName, const uint8_t dirIv[16]) const {
    if (plaintext_) return cipherName;
    // URL-safe alphabet only, then insist on the canonical encoding: gocryptfs decodes with
    // base64.Strict(), so a name that merely *decodes* to the same bytes (stray trailing bits, '='
    // where Raw64 has none, an embedded newline) is not one of its names.
    for (char c : cipherName) {
        bool ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '=';
        if (!ok) throw Error(Err::Auth, "Malformed base64 filename: " + cipherName);
    }
    Bytes raw;
    if (!base64Decode(cipherName, raw) || base64Encode(raw.data(), raw.size(), true, !raw64_) != cipherName)
        throw Error(Err::Auth, "Malformed base64 filename: " + cipherName);
    if (raw.empty() || raw.size() % 16 != 0) throw Error(Err::Auth, "Malformed ciphertext filename: " + cipherName);
    Bytes padded(raw.size());
    if (!eme_transform(key_.data(), key_.size(), dirIv, raw.data(), padded.data(), raw.size(), false))
        throw Error(Err::Auth, "EME decryption failed");
    // nametransform.unPad16: PKCS#7, and the padding may not be the whole block (names are never empty).
    uint8_t padLen = padded.back();
    if (padLen == 0 || padLen > 16 || padLen >= padded.size()) throw Error(Err::Auth, "invalid PKCS7 padding");
    for (size_t i = padded.size() - padLen; i < padded.size(); i++)
        if (padded[i] != padLen) throw Error(Err::Auth, "invalid PKCS7 padding");
    std::string clear((const char*)padded.data(), padded.size() - padLen);
    // gocryptfs accepts any byte string that IsValidName allows. Java and Dart strings are UTF-8/UTF-16, so a
    // name that is not well-formed UTF-8 cannot be shown or addressed here; it stays hidden.
    if (!isRepresentableName(clear))
        throw Error(Err::Auth, "Invalid decrypted filename (corrupted ciphertext or wrong diriv): " + cipherName);
    return clear;
}

std::string NameCryptor::hashLongName(const std::string& cipherName) const {
    Bytes d = crypto::hash(crypto::Md::Sha256, (const uint8_t*)cipherName.data(), cipherName.size());
    return std::string(kLongNamePrefix) + base64Encode(d.data(), d.size(), true, !raw64_);
}

bool NameCryptor::isOverLongNameLimit(const std::string& cipherName) const {
    if (plaintext_) return false;
    // names.go: longNameMax defaults to NameMax (255); gocryptfs always has long names enabled on mount.
    size_t max = longNameMax_ > 0 ? (size_t)longNameMax_ : kNameMax;
    return cipherName.size() > max;
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
    // contentenc.ParseHeader: an all-zero header (a hole where the header should be) is corruption, and so
    // is an all-zero file id -- the id is what binds a block to its file.
    bool zeroHeader = true, zeroId = true;
    for (size_t i = 0; i < kHeaderLen; i++) if (p[i]) { zeroHeader = false; if (i >= 2) { zeroId = false; break; } }
    if (zeroHeader) throw Error(Err::Auth, "File header is all-zero");
    uint16_t version = (uint16_t)((p[0] << 8) | p[1]);
    if (version != 2) throw Error(Err::Auth, "Unsupported file format version " + std::to_string(version));
    if (zeroId) throw Error(Err::Auth, "File id is all-zero");
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
