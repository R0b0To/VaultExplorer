#include "fv_cryptomator.h"

#include <algorithm>
#include <atomic>
#include <cstring>
#include <mutex>

#include "fv_json.h"
#include "crypto/siv.h"

namespace fv::cryptomator {

// ------------------------------------------------------------ masterkey file --

static Bytes b64Field(const json::Value& o, const char* key) {
    const json::Value* v = o.find(key);
    Bytes out;
    if (!v || !v->isString() || !base64Decode(v->asString(), out))
        throw Error(Err::InvalidVault, std::string("masterkey.cryptomator field \"") + key + "\" is missing or not valid base64");
    return out;
}

MasterkeyFile MasterkeyFile::parse(const std::string& text) {
    json::Value root;
    try { root = json::parse(text); }
    catch (const Error& e) { throw Error(Err::InvalidVault, std::string("masterkey.cryptomator is not valid JSON: ") + e.what()); }
    if (!root.isObject()) throw Error(Err::InvalidVault, "masterkey.cryptomator is not valid JSON: not an object");
    MasterkeyFile f;
    const json::Value* ver = root.find("version");
    f.version = ver && ver->isInt() ? (int)ver->asInt() : 999;
    f.scryptSalt = b64Field(root, "scryptSalt");
    const json::Value* cost = root.find("scryptCostParam");
    const json::Value* block = root.find("scryptBlockSize");
    if (!cost || !block) throw Error(Err::InvalidVault, "masterkey.cryptomator is missing its scrypt parameters");
    f.scryptCostParam = (int)cost->asInt();
    f.scryptBlockSize = (int)block->asInt();
    f.primaryMasterKey = b64Field(root, "primaryMasterKey");
    f.hmacMasterKey = b64Field(root, "hmacMasterKey");
    f.versionMac = b64Field(root, "versionMac");
    if (f.scryptCostParam <= 1 || f.scryptBlockSize <= 0)
        throw Error(Err::InvalidVault, "Invalid scrypt parameters in masterkey.cryptomator");
    return f;
}

Masterkey unlockMasterkey(const MasterkeyFile& f, const uint8_t* pw, size_t pwLen) {
    Secret kek = crypto::scrypt(pw, pwLen, f.scryptSalt.data(), f.scryptSalt.size(),
                                (uint32_t)f.scryptCostParam, (uint32_t)f.scryptBlockSize, 1, 32);
    for (const Bytes* w : {&f.primaryMasterKey, &f.hmacMasterKey})
        if (w->size() % 8 != 0 || w->size() < 24) throw Error(Err::InvalidVault, "Wrapped key must be a multiple of 8 bytes, >= 24");
    Secret enc, mac;
    if (!crypto::aesKeyUnwrap(kek.data(), kek.size(), f.primaryMasterKey.data(), f.primaryMasterKey.size(), enc) ||
        !crypto::aesKeyUnwrap(kek.data(), kek.size(), f.hmacMasterKey.data(), f.hmacMasterKey.size(), mac))
        throw Error(Err::WrongPassword, "Wrong password for this vault.");
    if (enc.size() != 32 || mac.size() != 32) throw Error(Err::InvalidVault, "unexpected masterkey length");
    Secret raw(64);
    std::memcpy(raw.data(), enc.data(), 32);
    std::memcpy(raw.data() + 32, mac.data(), 32);
    return Masterkey(std::move(raw));
}

static bool isValidUtf8(const uint8_t* p, size_t n) {
    size_t i = 0;
    while (i < n) {
        uint8_t c = p[i];
        size_t len = c < 0x80 ? 1 : (c >> 5) == 0x6 ? 2 : (c >> 4) == 0xE ? 3 : (c >> 3) == 0x1E ? 4 : 0;
        if (len == 0 || c == 0xC0 || c == 0xC1 || c > 0xF4 || i + len > n) return false;
        for (size_t k = 1; k < len; k++) if ((p[i + k] & 0xC0) != 0x80) return false;
        i += len;
    }
    return true;
}

Secret normalizedPassphrase(const uint8_t* pw, size_t pwLen) {
    bool ascii = true;
    for (size_t i = 0; i < pwLen; i++) if (pw[i] >= 0x80) { ascii = false; break; }
    if (ascii || !isValidUtf8(pw, pwLen)) return Secret(pw, pwLen);
    std::string in((const char*)pw, pwLen);
    std::string out = nfc(in);
    Secret r = out.empty() ? Secret(pw, pwLen) : Secret((const uint8_t*)out.data(), out.size());
    secureZero(in.data(), in.size());
    secureZero(out.data(), out.size());
    return r;
}

Masterkey unlockMasterkeyCompat(const MasterkeyFile& f, const uint8_t* pw, size_t pwLen) {
    Secret norm = normalizedPassphrase(pw, pwLen);
    try {
        return unlockMasterkey(f, norm.data(), norm.size());
    } catch (const Error& e) {
        bool differs = norm.size() != pwLen || (pwLen && std::memcmp(norm.data(), pw, pwLen) != 0);
        if (e.code() != Err::WrongPassword || !differs) throw;
    }
    return unlockMasterkey(f, pw, pwLen);
}

std::string lockMasterkey(const Masterkey& mk, const uint8_t* pw, size_t pwLen, int vaultVersion,
                          uint32_t N, uint32_t R) {
    Bytes salt = crypto::randomKeyBytes(8);
    Secret kek = crypto::scrypt(pw, pwLen, salt.data(), salt.size(), N, R, 1, 32);
    Bytes encWrapped = crypto::aesKeyWrap(kek.data(), kek.size(), mk.enc(), 32);
    Bytes macWrapped = crypto::aesKeyWrap(kek.data(), kek.size(), mk.mac(), 32);
    uint8_t ver[4];
    writeU32BE(ver, (uint32_t)vaultVersion);
    Bytes versionMac = crypto::hmac(crypto::Md::Sha256, mk.mac(), 32, ver, 4);
    auto b64 = [](const Bytes& b) { return json::Value::string(base64Encode(b.data(), b.size(), false, true)); };
    json::Value o = json::Value::object();
    o.set("version", json::Value::integer(vaultVersion));
    o.set("scryptSalt", b64(salt));
    o.set("scryptCostParam", json::Value::integer(N));
    o.set("scryptBlockSize", json::Value::integer(R));
    o.set("primaryMasterKey", b64(encWrapped));
    o.set("hmacMasterKey", b64(macWrapped));
    o.set("versionMac", b64(versionMac));
    return o.dump(2);
}

// ---------------------------------------------------------------- vault.cryptomator --

static json::Value jwtPart(const std::string& seg, const char* what) {
    Bytes raw;
    if (!base64Decode(seg, raw)) throw Error(Err::InvalidVault, std::string("Malformed vault.cryptomator ") + what);
    try { return json::parse(std::string(raw.begin(), raw.end())); }
    catch (const Error&) { throw Error(Err::InvalidVault, std::string("Malformed vault.cryptomator ") + what); }
}

static std::vector<std::string> splitDots(const std::string& s) {
    std::vector<std::string> parts;
    size_t i = 0;
    for (;;) {
        size_t j = s.find('.', i);
        if (j == std::string::npos) { parts.push_back(s.substr(i)); break; }
        parts.push_back(s.substr(i, j - i));
        i = j + 1;
    }
    return parts;
}

VaultConfig verifyVaultConfig(const std::string& jwtRaw, const Masterkey& mk) {
    std::string jwt = jwtRaw;
    while (!jwt.empty() && (jwt.back() == '\n' || jwt.back() == '\r' || jwt.back() == ' ')) jwt.pop_back();
    auto parts = splitDots(jwt);
    if (parts.size() != 3) throw Error(Err::InvalidVault, "Malformed vault.cryptomator (not a JWT)");
    json::Value header = jwtPart(parts[0], "header"), payload = jwtPart(parts[1], "payload");
    const json::Value* alg = header.find("alg");
    std::string a = alg && alg->isString() ? alg->asString() : "";
    crypto::Md md;
    if (a == "HS256") md = crypto::Md::Sha256;
    else if (a == "HS384") md = crypto::Md::Sha384;
    else if (a == "HS512") md = crypto::Md::Sha512;
    else throw Error(Err::InvalidVault, "Unsupported vault.cryptomator signature algorithm: " + a);
    std::string signingInput = parts[0] + "." + parts[1];
    Bytes expected = crypto::hmac(md, mk.raw().data(), mk.raw().size(), (const uint8_t*)signingInput.data(), signingInput.size());
    Bytes actual;
    if (!base64Decode(parts[2], actual) || actual.size() != expected.size() ||
        !([&] { int d = 0; for (size_t i = 0; i < actual.size(); i++) d |= actual[i] ^ expected[i]; return d == 0; })())
        throw Error(Err::InvalidVault, "vault.cryptomator signature verification failed \xE2\x80\x94 wrong password or corrupted vault config.");
    VaultConfig c;
    const json::Value* cc = payload.find("cipherCombo");
    c.cipherCombo = cc && cc->isString() ? cc->asString() : "";
    const json::Value* fm = payload.find("format");
    if (!fm || !fm->isInt()) throw Error(Err::InvalidVault, "vault.cryptomator is missing the 'format' claim");
    c.vaultFormat = (int)fm->asInt();
    const json::Value* st = payload.find("shorteningThreshold");
    if (!st || !st->isInt()) throw Error(Err::InvalidVault, "vault.cryptomator is missing the 'shorteningThreshold' claim");
    c.shorteningThreshold = (int)st->asInt();
    if (c.cipherCombo != "SIV_GCM" && c.cipherCombo != "SIV_CTRMAC")
        throw Error(Err::InvalidVault, "Unsupported cipherCombo: " + c.cipherCombo);
    return c;
}

std::string createVaultConfig(int format, const std::string& combo, int threshold, const Masterkey& mk, const std::string& vaultId) {
    json::Value h = json::Value::object();
    h.set("alg", json::Value::string("HS256"));
    h.set("typ", json::Value::string("JWT"));
    h.set("kid", json::Value::string("masterkeyfile:masterkey.cryptomator"));
    json::Value p = json::Value::object();
    p.set("jti", json::Value::string(vaultId));
    p.set("format", json::Value::integer(format));
    p.set("cipherCombo", json::Value::string(combo));
    p.set("shorteningThreshold", json::Value::integer(threshold));
    std::string hs = h.dump(0), ps = p.dump(0);
    std::string eh = base64Encode((const uint8_t*)hs.data(), hs.size(), true, false);
    std::string ep = base64Encode((const uint8_t*)ps.data(), ps.size(), true, false);
    std::string input = eh + "." + ep;
    Bytes sig = crypto::hmac(crypto::Md::Sha256, mk.raw().data(), mk.raw().size(), (const uint8_t*)input.data(), input.size());
    return input + "." + base64Encode(sig.data(), sig.size(), true, false);
}

// ------------------------------------------------------------------- names --

static Bytes sivEncrypt(const Masterkey& mk, const uint8_t* pt, size_t n, const std::vector<std::vector<uint8_t>>& ad) {
    Bytes out(16 + n);
    if (!siv_encrypt(mk.enc(), 32, mk.mac(), 32, pt, n, ad, out.data(), out.size()))
        throw Error(Err::Io, "AES-SIV encryption failed");
    return out;
}

std::string NameCryptor::hashDirectoryId(const std::string& dirId) const {
    Bytes enc = sivEncrypt(mk_, (const uint8_t*)dirId.data(), dirId.size(), {});
    Bytes digest = crypto::hash(crypto::Md::Sha1, enc.data(), enc.size());
    return base32Encode(digest.data(), digest.size());
}

std::string NameCryptor::encryptFilename(const std::string& cleartext, const std::string& dirId) const {
    std::string norm = nfc(cleartext);
    std::vector<std::vector<uint8_t>> ad;
    ad.emplace_back(dirId.begin(), dirId.end());
    Bytes enc = sivEncrypt(mk_, (const uint8_t*)norm.data(), norm.size(), ad);
    return base64Encode(enc.data(), enc.size(), true, true);
}

std::string NameCryptor::decryptFilename(const std::string& ciphertext, const std::string& dirId) const {
    for (char c : ciphertext) {
        bool ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '=';
        if (!ok) throw Error(Err::Auth, "Malformed ciphertext filename: '" + ciphertext + "'");
    }
    Bytes enc;
    if (!base64Decode(ciphertext, enc) || enc.size() < 16)
        throw Error(Err::Auth, "Malformed ciphertext filename: '" + ciphertext + "'");
    std::vector<std::vector<uint8_t>> ad;
    ad.emplace_back(dirId.begin(), dirId.end());
    Bytes plain(enc.size() - 16);
    if (!siv_decrypt(mk_.enc(), 32, mk_.mac(), 32, enc.data(), enc.size(), ad, plain.data(), plain.size()))
        throw Error(Err::Auth, "Filename decryption failed for '" + ciphertext +
                    "' \xE2\x80\x94 wrong key or the vault's directory structure doesn't match this dirId (moved/corrupted?).");
    return std::string(plain.begin(), plain.end());
}

// ----------------------------------------------------------------- content --

namespace {
struct CFileKey : FileKey {
    Bytes nonce;                           // header nonce (12 or 16 bytes)
    Secret contentKey;                     // 32
    std::unique_ptr<crypto::AeadKey> gcm;  // GCM: per-file key schedule, built once
};
constexpr size_t kReserved = 8, kContentKeyLen = 32;
}  // namespace

ContentFormat::ContentFormat(const Masterkey& mk, Combo combo) : mk_(mk), combo_(combo) {
    if (combo == Combo::SivGcm) {
        nonceLen_ = 12; tagLen_ = 16;
        headerAead_ = std::make_unique<crypto::AeadKey>(crypto::AeadKind::AesGcm, mk.enc(), 32);
    } else {
        nonceLen_ = 16; tagLen_ = 32;
    }
    headerSize_ = nonceLen_ + kReserved + kContentKeyLen + tagLen_;
}

std::shared_ptr<FileKey> ContentFormat::newHeader(Bytes& encoded) const {
    auto k = std::make_shared<CFileKey>();
    k->nonce.resize(nonceLen_);
    crypto::randomFast(k->nonce.data(), nonceLen_);
    k->contentKey = Secret(kContentKeyLen);
    crypto::randomFast(k->contentKey.data(), kContentKeyLen);
    if (combo_ == Combo::SivGcm) k->gcm = std::make_unique<crypto::AeadKey>(crypto::AeadKind::AesGcm, k->contentKey.data(), kContentKeyLen);

    Secret payload(kReserved + kContentKeyLen);
    std::memset(payload.data(), 0xFF, kReserved);   // reserved = -1L, big endian
    std::memcpy(payload.data() + kReserved, k->contentKey.data(), kContentKeyLen);
    encoded.assign(headerSize_, 0);
    std::memcpy(encoded.data(), k->nonce.data(), nonceLen_);
    if (combo_ == Combo::SivGcm) {
        if (!headerAead_->seal(k->nonce.data(), nonceLen_, nullptr, 0, payload.data(), payload.size(), encoded.data() + nonceLen_))
            throw Error(Err::Io, "header encryption failed");
    } else {
        crypto::aesCtr(mk_.enc(), 32, k->nonce.data(), payload.data(), encoded.data() + nonceLen_, payload.size());
        Bytes tag = crypto::hmac(crypto::Md::Sha256, mk_.mac(), 32, encoded.data(), nonceLen_ + payload.size());
        std::memcpy(encoded.data() + nonceLen_ + payload.size(), tag.data(), 32);
    }
    return k;
}

std::shared_ptr<FileKey> ContentFormat::decodeHeader(const uint8_t* p, size_t n) const {
    if (n < headerSize_) throw Error(Err::Auth, "Truncated file header");
    auto k = std::make_shared<CFileKey>();
    k->nonce.assign(p, p + nonceLen_);
    Secret payload(kReserved + kContentKeyLen);
    if (combo_ == Combo::SivGcm) {
        if (!headerAead_->open(p, nonceLen_, nullptr, 0, p + nonceLen_, kReserved + kContentKeyLen + tagLen_, payload.data()))
            throw Error(Err::Auth, "File header tag mismatch \xE2\x80\x94 wrong key or corrupted file.");
    } else {
        Bytes mac = crypto::hmac(crypto::Md::Sha256, mk_.mac(), 32, p, nonceLen_ + kReserved + kContentKeyLen);
        const uint8_t* expected = p + nonceLen_ + kReserved + kContentKeyLen;
        int diff = 0;
        for (size_t i = 0; i < 32; i++) diff |= mac[i] ^ expected[i];
        if (diff) throw Error(Err::Auth, "File header MAC mismatch \xE2\x80\x94 wrong key or corrupted file.");
        crypto::aesCtr(mk_.enc(), 32, p, p + nonceLen_, payload.data(), payload.size());
    }
    k->contentKey = Secret(payload.data() + kReserved, kContentKeyLen);
    if (combo_ == Combo::SivGcm) k->gcm = std::make_unique<crypto::AeadKey>(crypto::AeadKind::AesGcm, k->contentKey.data(), kContentKeyLen);
    return k;
}

static void chunkAad(uint8_t aad[20], uint64_t chunk, const Bytes& headerNonce) {
    writeU64BE(aad, chunk);
    std::memcpy(aad + 8, headerNonce.data(), 12);
}

void ContentFormat::encrypt(const FileKey& fk, uint64_t first, const uint8_t* in, size_t n, uint8_t* out) const {
    const auto& k = static_cast<const CFileKey&>(fk);
    const size_t cs = cleartextChunk(), ccs = ciphertextChunk();
    const size_t nChunks = (n + cs - 1) / cs;
    Bytes nonces(nChunks * nonceLen_);
    crypto::randomFast(nonces.data(), nonces.size());
    std::atomic<bool> failed{false};
    bool ok = crypto::parallelRanges(nChunks, 8, [&](size_t s, size_t e) {
        try {
            for (size_t i = s; i < e; i++) {
                size_t len = std::min(cs, n - i * cs);
                const uint8_t* nonce = nonces.data() + i * nonceLen_;
                uint8_t* o = out + i * ccs;
                std::memcpy(o, nonce, nonceLen_);
                if (combo_ == Combo::SivGcm) {
                    uint8_t aad[20];
                    chunkAad(aad, first + i, k.nonce);
                    if (!k.gcm->seal(nonce, 12, aad, 20, in + i * cs, len, o + 12)) { failed = true; return false; }
                } else {
                    crypto::aesCtr(k.contentKey.data(), 32, nonce, in + i * cs, o + 16, len);
                    crypto::HmacSha256 mac(mk_.mac(), 32);
                    uint8_t num[8];
                    writeU64BE(num, first + i);
                    mac.update(k.nonce.data(), k.nonce.size());
                    mac.update(num, 8);
                    mac.update(o, 16 + len);
                    mac.finish(o + 16 + len);
                }
            }
            return true;
        } catch (...) { failed = true; return false; }
    });
    if (!ok || failed) throw Error(Err::Io, "chunk encryption failed");
}

void ContentFormat::decrypt(const FileKey& fk, uint64_t first, const uint8_t* in, size_t n, uint8_t* out) const {
    const auto& k = static_cast<const CFileKey&>(fk);
    const size_t cs = cleartextChunk(), ccs = ciphertextChunk();
    const size_t nChunks = (n + ccs - 1) / ccs;
    std::atomic<bool> failed{false};
    std::atomic<int64_t> badChunk{-1};
    std::atomic<bool> truncated{false};
    bool ok = crypto::parallelRanges(nChunks, 8, [&](size_t s, size_t e) {
        try {
            for (size_t i = s; i < e; i++) {
                size_t len = std::min(ccs, n - i * ccs);
                const uint8_t* c = in + i * ccs;
                uint8_t* o = out + i * cs;
                if (len < nonceLen_ + tagLen_) { truncated = true; failed = true; return false; }
                size_t bodyLen = len - nonceLen_ - tagLen_;
                bool good;
                if (combo_ == Combo::SivGcm) {
                    uint8_t aad[20];
                    chunkAad(aad, first + i, k.nonce);
                    good = k.gcm->open(c, 12, aad, 20, c + 12, len - 12, o);
                } else {
                    crypto::HmacSha256 mac(mk_.mac(), 32);
                    uint8_t num[8], tag[32];
                    writeU64BE(num, first + i);
                    mac.update(k.nonce.data(), k.nonce.size());
                    mac.update(num, 8);
                    mac.update(c, len - 32);
                    mac.finish(tag);
                    int diff = 0;
                    for (size_t b = 0; b < 32; b++) diff |= tag[b] ^ c[len - 32 + b];
                    good = diff == 0;
                    if (good) crypto::aesCtr(k.contentKey.data(), 32, c, c + 16, o, bodyLen);
                }
                if (!good) { badChunk = (int64_t)(first + i); failed = true; return false; }
            }
            return true;
        } catch (...) { failed = true; return false; }
    });
    if (!ok || failed) {
        if (truncated) throw Error(Err::Auth, "Truncated chunk");
        throw Error(Err::Auth, "Chunk " + std::to_string(badChunk.load()) + " authentication failed \xE2\x80\x94 wrong key or corrupted/tampered file.");
    }
}

int64_t ContentFormat::cleartextSize(int64_t physical) const {
    int64_t without = physical - (int64_t)headerSize_;
    if (without <= 0) return 0;
    int64_t ccs = (int64_t)ciphertextChunk(), cs = (int64_t)cleartextChunk(), over = ccs - cs;
    int64_t full = without / ccs, rem = without % ccs;
    int64_t out = full * cs;
    if (rem > 0) out += std::max<int64_t>(0, rem - over);
    return std::max<int64_t>(0, out);
}

}  // namespace fv::cryptomator
