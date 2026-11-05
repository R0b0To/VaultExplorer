#include "fv_cryfs.h"

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <deque>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include "fv_json.h"
#include "fv_pool.h"
#include "fv_util.h"

namespace fv::cryfs {

static constexpr const char* TAG = "CryfsBlockStore";

// ------------------------------------------------------------------ ids --

BlockId BlockId::random() {
    BlockId id;
    crypto::randomKey(id.b.data(), 16);
    return id;
}

BlockId BlockId::randomFast() {
    static thread_local uint8_t buf[1024];
    static thread_local size_t pos = sizeof(buf);
    if (pos + 16 > sizeof(buf)) { crypto::randomFast(buf, sizeof(buf)); pos = 0; }
    BlockId id;
    std::memcpy(id.b.data(), buf + pos, 16);
    pos += 16;
    return id;
}

std::string BlockId::hexUpper() const {
    std::string h = hex();
    for (auto& c : h) if (c >= 'a' && c <= 'f') c = (char)(c - 32);
    return h;
}

std::optional<BlockId> BlockId::fromHex(const std::string& in) {
    size_t s = in.find_first_not_of(" \t\r\n"), e = in.find_last_not_of(" \t\r\n");
    std::string t = s == std::string::npos ? "" : in.substr(s, e - s + 1);
    Bytes raw;
    if (t.size() != 32 || !fv::fromHex(t, raw)) return std::nullopt;
    BlockId id;
    std::memcpy(id.b.data(), raw.data(), 16);
    return id;
}

// --------------------------------------------------------------- config --

static constexpr const char* kOuterHeader = "cryfs.config;1;scrypt";
static constexpr const char* kInnerHeader = "cryfs.config.inner;0";
static constexpr size_t kOuterConfigSize = 1024, kInnerConfigSize = 900, kOuterKeySize = 32;
static constexpr uint32_t kScryptN = 1u << 15, kScryptR = 8, kScryptP = 1;

int cipherKeySize(const std::string& n) {
    if (n == "aes-256-gcm" || n == "aes-256-cfb" || n == "xchacha20-poly1305") return 32;
    if (n == "aes-128-gcm" || n == "aes-128-cfb") return 16;
    throw Error(Err::Unsupported, "Vault uses cipher \"" + n + "\", which this app does not support.");
}

static CryfsCipherId cipherId(const std::string& n) {
    CryfsCipherId id = cryfsCipherIdFromName(n.c_str());
    if (id == CryfsCipherId::kUnknown)
        throw Error(Err::Unsupported, "Vault uses cipher \"" + n + "\", which this app does not support.");
    return id;
}

int virtualBlockSize(int physical, const std::string& cipher) {
    int overhead = cipher == "xchacha20-poly1305" ? 40
                 : (cipher == "aes-256-gcm" || cipher == "aes-128-gcm") ? 32
                 : (cipher == "aes-256-cfb" || cipher == "aes-128-cfb") ? 16 : 40;
    return physical - (14 + 2 + overhead + 2 + 16 + 4 + 8);
}

static bool readCString(const Bytes& b, size_t start, std::string& out, size_t& next) {
    size_t i = start;
    while (i < b.size() && b[i] != 0) i++;
    if (i >= b.size()) return false;
    out.assign((const char*)b.data() + start, i - start);
    next = i + 1;
    return true;
}

namespace {
struct Kdf { Bytes salt; uint64_t N; uint32_t r, p; Bytes encryptedInner; };

Kdf readKdf(const Bytes& raw) {
    std::string header;
    size_t pos;
    if (!readCString(raw, 0, header, pos)) throw Error(Err::InvalidVault, "Not a cryfs.config file (missing/unterminated header).");
    if (header != kOuterHeader)
        throw Error(Err::InvalidVault, std::string("Not a cryfs.config file (expected header \"") + kOuterHeader + "\", found \"" + header + "\").");
    if (pos + 8 > raw.size()) throw Error(Err::InvalidVault, "Truncated cryfs.config (missing KDF parameter length).");
    uint64_t kdfLen = readU64LE(raw.data() + pos);
    pos += 8;
    if (kdfLen < 16 || pos + kdfLen > raw.size())
        throw Error(Err::InvalidVault, "Malformed cryfs.config (bad KDF parameter length: " + std::to_string(kdfLen) + ").");
    Kdf k;
    const uint8_t* kp = raw.data() + pos;
    k.N = readU64LE(kp);
    k.r = readU32LE(kp + 8);
    k.p = readU32LE(kp + 12);
    k.salt.assign(kp + 16, kp + kdfLen);
    pos += (size_t)kdfLen;
    k.encryptedInner.assign(raw.begin() + (long)pos, raw.end());
    if (k.N == 0 || k.N > 0x7FFFFFFFull)
        throw Error(Err::InvalidVault, "Unsupported scrypt N parameter: " + std::to_string(k.N));
    return k;
}

Bytes removePadding(const Bytes& d) {
    if (d.size() < 4) throw Error(Err::InvalidVault, "Padded config data is too short.");
    uint32_t len = readU32LE(d.data());
    if ((uint64_t)4 + len > d.size()) throw Error(Err::InvalidVault, "Padded config data claims an invalid length (" + std::to_string(len) + ").");
    return Bytes(d.begin() + 4, d.begin() + 4 + len);
}

Bytes addPadding(const Bytes& d, size_t target) {
    if (d.size() + 4 > target) throw Error(Err::Io, "config payload does not fit its padded slot");
    Bytes out(target);
    writeU32LE(out.data(), (uint32_t)d.size());
    std::memcpy(out.data() + 4, d.data(), d.size());
    crypto::randomKey(out.data() + 4 + d.size(), target - 4 - d.size());
    return out;
}

std::string upperHex(const uint8_t* p, size_t n) {
    std::string h = toHex(p, n);
    for (auto& c : h) if (c >= 'a' && c <= 'f') c = (char)(c - 32);
    return h;
}

Bytes cstr(const std::string& s) { Bytes b(s.begin(), s.end()); b.push_back(0); return b; }

std::string optStr(const json::Value& o, const char* key, const std::string& dflt) {
    const json::Value* v = o.find(key);
    if (!v) return dflt;
    if (v->isString()) return v->asString();
    if (v->isInt()) return std::to_string(v->asInt());
    return dflt;
}
std::optional<int64_t> flexLong(const json::Value& o, const char* key) {
    const json::Value* v = o.find(key);
    if (!v || v->isNull()) return std::nullopt;
    if (v->isInt()) return v->asInt();
    if (v->isString()) {
        const std::string& s = v->asString();
        char* end = nullptr;
        long long n = std::strtoll(s.c_str(), &end, 10);
        if (s.empty() || *end) throw Error(Err::InvalidVault, std::string("cryfs.config field \"") + key + "\" is not a valid number: \"" + s + "\".");
        return n;
    }
    throw Error(Err::InvalidVault, std::string("cryfs.config field \"") + key + "\" has an unexpected JSON type.");
}

Config parsePayload(const std::string& text, const std::string& expectedCipher) {
    json::Value root;
    try { root = json::parse(text); }
    catch (const Error& e) { throw Error(Err::InvalidVault, std::string("cryfs.config payload is not valid JSON: ") + e.what()); }
    const json::Value* j = root.isObject() ? root.find("cryfs") : nullptr;
    if (!j || !j->isObject()) throw Error(Err::InvalidVault, "cryfs.config payload is missing the top-level \"cryfs\" object.");
    std::string cipher = optStr(*j, "cipher", "");
    if (cipher != expectedCipher)
        throw Error(Err::InvalidVault, "Cipher in config JSON (\"" + cipher + "\") doesn't match the inner-layer cipher (\"" + expectedCipher + "\").");
    if (const json::Value* m = j->find("migrations")) {
        auto flag = [&](const char* k) {
            const json::Value* v = m->find(k);
            return v && ((v->isString() && v->asString() == "true") || v->asBool(false));
        };
        if (!flag("hasVersionNumbers") || !flag("hasParentPointers"))
            throw Error(Err::InvalidVault, "cryfs.config has unexpected \"migrations\" flags; this app only supports current-format vaults.");
    }
    Config c;
    c.cipherName = cipher;
    c.formatVersion = optStr(*j, "version", optStr(*j, "formatVersion", "0.10"));
    c.createdWithVersion = optStr(*j, "createdWithVersion", optStr(*j, "created_with_version", "0.10"));
    c.lastOpenedWithVersion = optStr(*j, "lastOpenedWithVersion", optStr(*j, "last_opened_with_version", "0.10"));
    auto bs = flexLong(*j, "blocksizeBytes");
    if (!bs) bs = flexLong(*j, "blocksize");
    if (!bs) throw Error(Err::InvalidVault, "cryfs.config is missing blocksize field.");
    c.blocksizeBytes = (int)*bs;
    c.exclusiveClientId = flexLong(*j, "exclusiveClientId");
    if (!c.exclusiveClientId) c.exclusiveClientId = flexLong(*j, "exclusive_client_id");
    std::string root_ = optStr(*j, "rootblob", optStr(*j, "root_blob", optStr(*j, "rootBlob", "")));
    if (root_.empty()) throw Error(Err::InvalidVault, "cryfs.config is missing the required root blob ID field.");
    auto rid = BlockId::fromHex(root_);
    if (!rid) throw Error(Err::InvalidVault, "cryfs.config has an invalid root blob ID.");
    c.rootBlob = *rid;
    std::string key = optStr(*j, "key", optStr(*j, "enc_key", optStr(*j, "encKey", "")));
    if (key.empty()) throw Error(Err::InvalidVault, "cryfs.config is missing the required encryption key field.");
    Bytes kb;
    if (!fv::fromHex(key, kb)) throw Error(Err::InvalidVault, "cryfs.config encryption key is not valid hex.");
    c.key = Secret(kb);
    secureZero(kb.data(), kb.size());
    std::string fsid = optStr(*j, "filesystemId", optStr(*j, "filesystem_id", ""));
    if (fsid.empty()) throw Error(Err::InvalidVault, "cryfs.config is missing the required filesystem ID field.");
    if (!fv::fromHex(fsid, c.filesystemId)) throw Error(Err::InvalidVault, "cryfs.config filesystem ID is not valid hex.");
    return c;
}
}  // namespace

Secret deriveCombinedKey(const Bytes& raw, const uint8_t* pw, size_t pwLen) {
    Kdf k = readKdf(raw);
    return crypto::scrypt(pw, pwLen, k.salt.data(), k.salt.size(), (uint32_t)k.N, k.r, k.p, kCombinedKeySize);
}

Config parseWithCombinedKey(const Bytes& raw, const Secret& combined) {
    if (combined.size() != kCombinedKeySize) throw Error(Err::WrongPassword, "Wrong password for this vault.");
    Kdf kdf = readKdf(raw);
    Bytes outerPadded;
    if (!cryfsBlockDecrypt(CryfsCipherId::kAes256Gcm, combined.data(), kOuterKeySize,
                           kdf.encryptedInner.data(), kdf.encryptedInner.size(), outerPadded))
        throw Error(Err::WrongPassword, "Wrong password for this vault.");
    Bytes serialized = removePadding(outerPadded);
    secureZero(outerPadded.data(), outerPadded.size());

    std::string header, cipherName;
    size_t pos;
    if (!readCString(serialized, 0, header, pos)) throw Error(Err::InvalidVault, "Malformed inner config (missing/unterminated header).");
    if (header != kInnerHeader)
        throw Error(Err::InvalidVault, std::string("Malformed inner config (expected header \"") + kInnerHeader + "\", found \"" + header + "\").");
    if (!readCString(serialized, pos, cipherName, pos)) throw Error(Err::InvalidVault, "Malformed inner config (missing/unterminated cipher name).");
    Bytes encrypted(serialized.begin() + (long)pos, serialized.end());
    CryfsCipherId cid = cipherId(cipherName);
    int ks = cipherKeySize(cipherName);
    Bytes innerPadded;
    if (!cryfsBlockDecrypt(cid, combined.data() + kOuterKeySize, (size_t)ks, encrypted.data(), encrypted.size(), innerPadded))
        throw Error(Err::WrongPassword, "Wrong password for this vault.");
    Bytes json = removePadding(innerPadded);
    secureZero(innerPadded.data(), innerPadded.size());
    return parsePayload(std::string(json.begin(), json.end()), cipherName);
}

Config newVaultConfig(const std::string& cipher, int blocksizeBytes) {
    Config c;
    c.cipherName = cipher;
    c.key = Secret(crypto::randomKeyBytes((size_t)cipherKeySize(cipher)));
    c.blocksizeBytes = blocksizeBytes;
    c.rootBlob = BlockId::random();
    c.filesystemId = crypto::randomKeyBytes(16);
    c.formatVersion = "0.10";
    c.createdWithVersion = c.lastOpenedWithVersion = "1.0.3";
    return c;
}

Bytes buildConfig(const Config& c, const uint8_t* pw, size_t pwLen) {
    json::Value inner = json::Value::object();
    inner.set("rootblob", json::Value::string(c.rootBlob.hexUpper()));
    inner.set("key", json::Value::string(upperHex(c.key.data(), c.key.size())));
    inner.set("cipher", json::Value::string(c.cipherName));
    inner.set("version", json::Value::string(c.formatVersion));
    inner.set("createdWithVersion", json::Value::string(c.createdWithVersion));
    inner.set("lastOpenedWithVersion", json::Value::string(c.lastOpenedWithVersion));
    inner.set("blocksizeBytes", json::Value::string(std::to_string(c.blocksizeBytes)));
    inner.set("filesystemId", json::Value::string(upperHex(c.filesystemId.data(), c.filesystemId.size())));
    inner.set("exclusiveClientId", c.exclusiveClientId ? json::Value::string(std::to_string(*c.exclusiveClientId)) : json::Value::null());
    json::Value mig = json::Value::object();
    mig.set("hasVersionNumbers", json::Value::string("true"));
    mig.set("hasParentPointers", json::Value::string("true"));
    inner.set("migrations", std::move(mig));
    json::Value root = json::Value::object();
    root.set("cryfs", std::move(inner));
    std::string payloadText = root.dump(0);
    Bytes payload(payloadText.begin(), payloadText.end());

    CryfsCipherId cid = cipherId(c.cipherName);
    int ks = cipherKeySize(c.cipherName);
    Bytes salt = crypto::randomKeyBytes(32);
    Secret combined = crypto::scrypt(pw, pwLen, salt.data(), salt.size(), kScryptN, kScryptR, kScryptP, kCombinedKeySize);

    Bytes padded = addPadding(payload, kInnerConfigSize);
    Bytes encryptedConfig = cryfsBlockEncrypt(cid, combined.data() + kOuterKeySize, (size_t)ks, padded.data(), padded.size());
    if (encryptedConfig.empty()) throw Error(Err::Io, "config encryption failed");
    Bytes layout = cstr(kInnerHeader);
    Bytes cn = cstr(c.cipherName);
    layout.insert(layout.end(), cn.begin(), cn.end());
    layout.insert(layout.end(), encryptedConfig.begin(), encryptedConfig.end());
    Bytes paddedLayout = addPadding(layout, kOuterConfigSize);
    Bytes encryptedInner = cryfsBlockEncrypt(CryfsCipherId::kAes256Gcm, combined.data(), kOuterKeySize, paddedLayout.data(), paddedLayout.size());
    if (encryptedInner.empty()) throw Error(Err::Io, "config encryption failed");

    Bytes kdfParams(16 + salt.size());
    writeU64LE(kdfParams.data(), kScryptN);
    writeU32LE(kdfParams.data() + 8, kScryptR);
    writeU32LE(kdfParams.data() + 12, kScryptP);
    std::memcpy(kdfParams.data() + 16, salt.data(), salt.size());
    Bytes out = cstr(kOuterHeader);
    uint8_t len[8];
    writeU64LE(len, kdfParams.size());
    out.insert(out.end(), len, len + 8);
    out.insert(out.end(), kdfParams.begin(), kdfParams.end());
    out.insert(out.end(), encryptedInner.begin(), encryptedInner.end());
    return out;
}

// ---------------------------------------------------- integrity bookkeeping --

static bool mkdirs(const std::string& path) {
    if (path.empty()) return false;
    std::string cur;
    size_t i = 0;
    if (path[0] == '/') { cur = "/"; i = 1; }
    while (i <= path.size()) {
        size_t j = path.find('/', i);
        if (j == std::string::npos) j = path.size();
        std::string seg = path.substr(i, j - i);
        if (!seg.empty()) {
            cur += seg;
            if (::mkdir(cur.c_str(), 0700) != 0 && errno != EEXIST) return false;
            cur += "/";
        }
        i = j + 1;
    }
    return true;
}

static bool writeFileAtomic(const std::string& target, const std::string& data) {
    std::string tmp = target + ".tmp";
    int fd = ::open(tmp.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    if (fd < 0) return false;
    bool ok;
    {
        FdFile f(fd);
        ok = f.writeAll((const uint8_t*)data.data(), data.size()) && f.sync();
    }
    if (!ok) { ::unlink(tmp.c_str()); return false; }
    if (::rename(tmp.c_str(), target.c_str()) != 0) { ::unlink(target.c_str()); return ::rename(tmp.c_str(), target.c_str()) == 0; }
    return true;
}

static std::string slurpText(const std::string& path, bool& ok) {
    ok = false;
    FILE* f = std::fopen(path.c_str(), "rb");
    if (!f) return {};
    std::string s;
    char buf[8192];
    size_t n;
    while ((n = std::fread(buf, 1, sizeof buf, f)) > 0) s.append(buf, n);
    std::fclose(f);
    ok = true;
    return s;
}

static std::string keyFor(uint64_t client, const BlockId& id) { return std::to_string(client) + ":" + id.hex(); }

std::unique_ptr<LocalIntegrityState> LocalIntegrityState::open(const std::string& baseDir, const Bytes& fsId) {
    if (baseDir.empty()) throw Error(Err::Io, "no directory configured for CryFS local state");
    std::unique_ptr<LocalIntegrityState> s(new LocalIntegrityState());
    s->dir_ = baseDir + "/" + toHex(fsId.data(), fsId.size());
    if (!mkdirs(s->dir_)) throw Error(Err::Io, "cannot create CryFS local state directory");

    bool ok;
    std::string idText = slurpText(s->dir_ + "/myClientId", ok);
    uint64_t id = 0;
    if (ok) { char* e = nullptr; unsigned long long v = std::strtoull(idText.c_str(), &e, 10); if (e != idText.c_str()) id = v; }
    if (id == 0) {
        uint8_t r[4];
        crypto::randomKey(r, 4);
        id = readU32LE(r) & 0x7FFFFFFFu;
        if (id == 0) id = 1;
        if (!writeFileAtomic(s->dir_ + "/myClientId", std::to_string(id))) throw Error(Err::Io, "cannot persist CryFS client id");
    }
    s->myClientId_ = id;

    std::string snap = slurpText(s->dir_ + "/integritydata.snapshot", ok);
    if (ok) {
        try {
            json::Value v = json::parse(snap);
            for (auto& kv : v.members()) {
                const json::Value& x = kv.second;
                s->known_[kv.first] = x.isString() ? std::strtoull(x.asString().c_str(), nullptr, 10) : (uint64_t)x.asInt();
            }
        } catch (const std::exception&) {}
    }
    std::string log = slurpText(s->dir_ + "/integritydata.log", ok);
    if (ok) {
        size_t i = 0;
        while (i < log.size()) {
            size_t j = log.find('\n', i);
            if (j == std::string::npos) j = log.size();
            std::string line = log.substr(i, j - i);
            i = j + 1;
            size_t eq = line.rfind('=');
            if (eq == std::string::npos || eq == 0) continue;
            char* e = nullptr;
            unsigned long long v = std::strtoull(line.c_str() + eq + 1, &e, 10);
            if (e == line.c_str() + eq + 1) continue;
            s->known_[line.substr(0, eq)] = v;
            s->pendingLines_++;
        }
    }
    s->log_ = std::fopen((s->dir_ + "/integritydata.log").c_str(), "ab");
    if (!s->log_) throw Error(Err::Io, "cannot open CryFS integrity log");
    return s;
}

LocalIntegrityState::~LocalIntegrityState() {
    try { flush(); } catch (...) {}
    if (log_) std::fclose(log_);
}

void LocalIntegrityState::append(const std::string& key, uint64_t version, bool durable) {
    std::string line = key + "=" + std::to_string(version) + "\n";
    std::fwrite(line.data(), 1, line.size(), log_);
    std::fflush(log_);
    if (durable) ::fsync(::fileno(log_));
    if (++pendingLines_ >= 200) compact();
}

void LocalIntegrityState::compact() {
    json::Value snap = json::Value::object();
    for (auto& kv : known_) snap.set(kv.first, json::Value::string(std::to_string(kv.second)));
    writeFileAtomic(dir_ + "/integritydata.snapshot", snap.dump(0));
    std::fclose(log_);
    log_ = std::fopen((dir_ + "/integritydata.log").c_str(), "wb");   // truncate
    if (log_) { std::fflush(log_); ::fsync(::fileno(log_)); std::fclose(log_); }
    log_ = std::fopen((dir_ + "/integritydata.log").c_str(), "ab");
    pendingLines_ = 0;
}

void LocalIntegrityState::flush() {
    std::lock_guard<std::mutex> g(mu_);
    if (pendingLines_ > 0 && log_) compact();
}

uint64_t LocalIntegrityState::nextVersionForOwnWrite(const BlockId& id, bool durable) {
    std::lock_guard<std::mutex> g(mu_);
    std::string key = keyFor(myClientId_, id);
    uint64_t next = known_[key] + 1;
    known_[key] = next;
    append(key, next, durable);
    return next;
}

std::optional<uint64_t> LocalIntegrityState::checkAndRecordRead(uint64_t writer, const BlockId& id, uint64_t version) {
    std::lock_guard<std::mutex> g(mu_);
    std::string key = keyFor(writer, id);
    auto it = known_.find(key);
    if (it != known_.end() && version < it->second) return it->second;
    if (it == known_.end() || version > it->second) {
        known_[key] = version;
        append(key, version, false);
    }
    return std::nullopt;
}

// ----------------------------------------------------------- block store --

static const uint8_t kOnDiskHeader[14] = {'c', 'r', 'y', 'f', 's', ';', 'b', 'l', 'o', 'c', 'k', ';', '0', 0};
static const uint8_t kEncLayerHeader[2] = {1, 0};
static constexpr size_t kIntegrityHeader = 2 + 16 + 4 + 8;

BlockStore::BlockStore(Storage& st, CryfsCipherId cipher, const Secret& key, LocalIntegrityState& integ)
    : st_(st), cipher_(cipher), key_(key), integrity_(integ) {}

bool BlockStore::cacheGet(const BlockId& id, Bytes& out) {
    std::lock_guard<std::mutex> g(cmu_);
    auto it = cache_.find(id);
    if (it == cache_.end()) return false;
    lru_.splice(lru_.begin(), lru_, it->second.it);
    out = it->second.data;
    return true;
}

void BlockStore::cachePut(const BlockId& id, const Bytes& payload) {
    std::lock_guard<std::mutex> g(cmu_);
    auto it = cache_.find(id);
    if (it != cache_.end()) { lru_.erase(it->second.it); cache_.erase(it); }
    lru_.push_front(id);
    cache_[id] = Slot{payload, lru_.begin()};
    while (cache_.size() > kCacheEntries) { cache_.erase(lru_.back()); lru_.pop_back(); }
}

void BlockStore::clearCache() {
    { std::lock_guard<std::mutex> g(cmu_); cache_.clear(); lru_.clear(); }
    { std::lock_guard<std::mutex> g(smu_); shards_.clear(); }
    st_.invalidateAll();
}

std::optional<IntegrityViolation> BlockStore::lastViolation() const {
    std::lock_guard<std::mutex> g(vmu_);
    return violation_;
}

std::optional<Bytes> BlockStore::load(const BlockId& id) {
    { std::lock_guard<std::mutex> g(vmu_); violation_.reset(); }
    Bytes cached;
    if (cacheGet(id, cached)) return cached;
    Bytes raw;
    if (!st_.readWhole(id.pathUpper(), raw) && !st_.readWhole(id.pathLower(), raw)) return std::nullopt;
    const size_t prefix = sizeof(kOnDiskHeader) + sizeof(kEncLayerHeader);
    if (raw.size() < prefix) return std::nullopt;
    if (std::memcmp(raw.data(), kOnDiskHeader, sizeof(kOnDiskHeader)) != 0) return std::nullopt;
    if (std::memcmp(raw.data() + sizeof(kOnDiskHeader), kEncLayerHeader, sizeof(kEncLayerHeader)) != 0) return std::nullopt;
    Bytes plain;
    if (!cryfsBlockDecrypt(cipher_, key_.data(), key_.size(), raw.data() + prefix, raw.size() - prefix, plain)) return std::nullopt;
    if (plain.size() < kIntegrityHeader) return std::nullopt;
    if (readU16LE(plain.data()) != 1) return std::nullopt;
    if (std::memcmp(plain.data() + 2, id.b.data(), 16) != 0) return std::nullopt;
    uint64_t writer = readU32LE(plain.data() + 18);
    uint64_t version = readU64LE(plain.data() + 22);
    if (auto known = integrity_.checkAndRecordRead(writer, id, version)) {
        std::lock_guard<std::mutex> g(vmu_);
        violation_ = IntegrityViolation{id, writer, version, *known};
        logMsg(LogLevel::Error, TAG, "Rejecting block " + id.hex() + ": client " + std::to_string(writer) + " claims version " +
               std::to_string(version) + ", lower than the recorded " + std::to_string(*known) + " -- looks like a rollback.");
        return std::nullopt;
    }
    Bytes payload(plain.begin() + kIntegrityHeader, plain.end());
    secureZero(plain.data(), plain.size());
    cachePut(id, payload);
    return payload;
}

void BlockStore::store(const BlockId& id, const Bytes& payload, bool isNew) {
    uint64_t version = integrity_.nextVersionForOwnWrite(id, /*durable*/ !isNew);
    Bytes plain(kIntegrityHeader + payload.size());
    writeU16LE(plain.data(), 1);
    std::memcpy(plain.data() + 2, id.b.data(), 16);
    writeU32LE(plain.data() + 18, (uint32_t)integrity_.myClientId());
    writeU64LE(plain.data() + 22, version);
    std::memcpy(plain.data() + kIntegrityHeader, payload.data(), payload.size());
    Bytes enc = cryfsBlockEncrypt(cipher_, key_.data(), key_.size(), plain.data(), plain.size());
    secureZero(plain.data(), plain.size());
    if (enc.empty()) throw Error(Err::Io, "CryFS block encryption failed");
    const size_t prefix = sizeof(kOnDiskHeader) + sizeof(kEncLayerHeader);
    Bytes onDisk(prefix + enc.size());
    std::memcpy(onDisk.data(), kOnDiskHeader, sizeof(kOnDiskHeader));
    std::memcpy(onDisk.data() + sizeof(kOnDiskHeader), kEncLayerHeader, sizeof(kEncLayerHeader));
    std::memcpy(onDisk.data() + prefix, enc.data(), enc.size());
    // Overwrites keep whichever spelling the existing file has; new blocks use
    // the canonical uppercase one.
    std::string path = id.pathUpper();
    if (!isNew) {
        DirEntry de;
        if (!st_.stat(path, de) && st_.stat(id.pathLower(), de)) path = id.pathLower();
    }
    const std::string shard = parentOf(path);
    bool known;
    { std::lock_guard<std::mutex> g(smu_); known = shards_.count(shard) > 0; }
    if (!known) {
        if (!st_.mkdir(shard)) throw Error(Err::Io, "Could not access shard dir " + shard);
        std::lock_guard<std::mutex> g(smu_);
        shards_[shard] = true;
    }
    if (!st_.writeBlock(path, onDisk.data(), onDisk.size()))
        throw Error(Err::Io, "Could not write block " + id.hex());
    cachePut(id, payload);
}

bool BlockStore::remove(const BlockId& id) {
    { std::lock_guard<std::mutex> g(cmu_); auto it = cache_.find(id); if (it != cache_.end()) { lru_.erase(it->second.it); cache_.erase(it); } }
    bool ok = st_.remove(id.pathUpper());
    DirEntry de;
    if (st_.stat(id.pathLower(), de)) ok = st_.remove(id.pathLower()) && ok;   // legacy spelling
    return ok;
}

// -------------------------------------------------------------- data tree --

std::optional<DataTree::Node> DataTree::loadNode(const BlockId& id) {
    auto raw = bs_.load(id);
    if (!raw || raw->size() < kNodeHeader) return std::nullopt;
    if (readU16LE(raw->data()) != 0) return std::nullopt;
    Node n;
    n.depth = (*raw)[3];
    uint32_t size = readU32LE(raw->data() + 4);
    if (n.depth == 0) {
        size_t end = std::min<size_t>(kNodeHeader + size, raw->size());
        n.leaf.assign(raw->begin() + kNodeHeader, raw->begin() + (long)end);
    } else {
        for (uint32_t i = 0; i < size; i++) {
            size_t off = kNodeHeader + (size_t)i * 16;
            if (off + 16 > raw->size()) break;
            BlockId c;
            std::memcpy(c.b.data(), raw->data() + off, 16);
            n.children.push_back(c);
        }
    }
    return n;
}

int64_t DataTree::capacity(int depth) const {
    int64_t cap = (int64_t)maxLeaf_;
    for (int i = 0; i < depth; i++) cap *= (int64_t)maxChildren_;
    return cap;
}

int64_t DataTree::nodeSize(const Node& n) {
    if (n.depth == 0) return (int64_t)n.leaf.size();
    if (n.children.empty()) return 0;
    int64_t childCap = capacity(n.depth - 1);
    auto last = loadNode(n.children.back());
    int64_t full = (int64_t)(n.children.size() - 1) * childCap;
    if (!last) return full;
    return full + nodeSize(*last);
}

int64_t DataTree::size(const BlockId& root) {
    auto n = loadNode(root);
    return n ? nodeSize(*n) : 0;
}

void DataTree::planRead(const Node& n, int64_t offset, int64_t length,
                        std::vector<std::tuple<BlockId, int64_t, int64_t>>& plan) {
    if (length <= 0 || offset < 0 || n.depth == 0) return;
    int64_t childCap = capacity(n.depth - 1);
    if (childCap <= 0) return;
    size_t idx = (size_t)(offset / childCap);
    int64_t local = offset - (int64_t)idx * childCap;
    int64_t remaining = length;
    while (remaining > 0 && idx < n.children.size()) {
        int64_t take = std::min(remaining, childCap - local);
        if (n.depth - 1 == 0) {
            plan.emplace_back(n.children[idx], local, take);
        } else {
            auto child = loadNode(n.children[idx]);
            if (!child) break;
            planRead(*child, local, take, plan);
        }
        remaining -= take;
        idx++;
        local = 0;
    }
}

Bytes DataTree::read(const BlockId& root, int64_t offset, int length) {
    Bytes out;
    if (length <= 0 || offset < 0) return out;
    auto node = loadNode(root);
    if (!node) return out;
    if (node->depth == 0) {
        if ((size_t)offset >= node->leaf.size()) return out;
        size_t end = (size_t)std::min<int64_t>((int64_t)node->leaf.size(), offset + length);
        out.assign(node->leaf.begin() + offset, node->leaf.begin() + (long)end);
        return out;
    }
    std::vector<std::tuple<BlockId, int64_t, int64_t>> plan;
    planRead(*node, offset, length, plan);
    std::vector<std::optional<Node>> leaves(plan.size());
    // Decrypting a long run of leaves is the hot path of an export: fan it out.
    crypto::parallelRanges(plan.size(), 8, [&](size_t s, size_t e) {
        for (size_t i = s; i < e; i++) leaves[i] = loadNode(std::get<0>(plan[i]));
        return true;
    });
    out.reserve((size_t)length);
    for (size_t i = 0; i < plan.size(); i++) {
        if (!leaves[i]) break;
        int64_t local = std::get<1>(plan[i]), take = std::get<2>(plan[i]);
        const Bytes& p = leaves[i]->leaf;
        if ((size_t)local >= p.size()) break;
        size_t end = (size_t)std::min<int64_t>((int64_t)p.size(), local + take);
        out.insert(out.end(), p.begin() + local, p.begin() + (long)end);
        if ((int64_t)(end - (size_t)local) < take) break;
    }
    return out;
}

Bytes DataTree::readAll(const BlockId& root) {
    int64_t total = size(root);
    return read(root, 0, (int)std::min<int64_t>(total, 0x7FFFFFFF));
}

BlockId DataTree::writeLeaf(const uint8_t* p, size_t n) {
    BlockId id = BlockId::randomFast();
    Bytes raw(nodeBlock_, 0);
    writeU16LE(raw.data(), 0);
    raw[2] = 0; raw[3] = 0;
    writeU32LE(raw.data() + 4, (uint32_t)n);
    if (n) std::memcpy(raw.data() + kNodeHeader, p, n);
    bs_.store(id, raw, true);
    return id;
}

BlockId DataTree::writeInner(int depth, const std::vector<BlockId>& kids, size_t from, size_t to) {
    BlockId id = BlockId::randomFast();
    Bytes raw(nodeBlock_, 0);
    writeU16LE(raw.data(), 0);
    raw[2] = 0; raw[3] = (uint8_t)depth;
    writeU32LE(raw.data() + 4, (uint32_t)(to - from));
    for (size_t i = from; i < to; i++) std::memcpy(raw.data() + kNodeHeader + (i - from) * 16, kids[i].b.data(), 16);
    bs_.store(id, raw, true);
    return id;
}

BlockId DataTree::buildUp(std::vector<BlockId> level) {
    int depth = 1;
    while (level.size() > 1) {
        std::vector<BlockId> next;
        next.reserve((level.size() + maxChildren_ - 1) / maxChildren_);
        for (size_t i = 0; i < level.size(); i += maxChildren_)
            next.push_back(writeInner(depth, level, i, std::min(i + maxChildren_, level.size())));
        level = std::move(next);
        depth++;
    }
    return level[0];
}

BlockId DataTree::buildBlob(const Bytes& content) {
    if (content.size() <= maxLeaf_) return writeLeaf(content.data(), content.size());
    std::vector<BlockId> level;
    std::deque<std::future<BlockId>> futs;
    constexpr size_t kMaxInFlight = 128;
    size_t off = 0;
    while (off < content.size()) {
        size_t end = std::min(off + maxLeaf_, content.size());
        Bytes chunk(content.begin() + (long)off, content.begin() + (long)end);
        if (futs.size() >= kMaxInFlight) { level.push_back(futs.front().get()); futs.pop_front(); }
        futs.push_back(Pool::shared().submit([this, c = std::move(chunk)] { return writeLeaf(c.data(), c.size()); }));
        off = end;
    }
    while (!futs.empty()) { level.push_back(futs.front().get()); futs.pop_front(); }
    return buildUp(std::move(level));
}

BlockId DataTree::buildBlobStream(ByteSource& src) {
    std::vector<BlockId> level;
    std::deque<std::future<BlockId>> futs;
    constexpr size_t kMaxInFlight = 128;
    Bytes buf(maxLeaf_);
    bool any = false;
    try {
        for (;;) {
            size_t got = 0;
            while (got < maxLeaf_) {
                int64_t r = src.read(buf.data() + got, maxLeaf_ - got);
                if (r < 0) throw Error(Err::Io, "source read failed");
                if (r == 0) break;
                got += (size_t)r;
            }
            if (got == 0) break;
            any = true;
            Bytes chunk(buf.begin(), buf.begin() + (long)got);
            if (futs.size() >= kMaxInFlight) { level.push_back(futs.front().get()); futs.pop_front(); }
            futs.push_back(Pool::shared().submit([this, c = std::move(chunk)] { return writeLeaf(c.data(), c.size()); }));
            if (got < maxLeaf_) break;
        }
        if (!any) return writeLeaf(nullptr, 0);
        while (!futs.empty()) { level.push_back(futs.front().get()); futs.pop_front(); }
    } catch (...) {
        // Drain in-flight writes, then clean up what we already wrote.
        std::vector<BlockId> written = level;
        for (auto& f : futs) { try { written.push_back(f.get()); } catch (...) {} }
        for (auto& id : written) bs_.remove(id);
        throw;
    }
    return buildUp(std::move(level));
}

DataTree::Replaced DataTree::replaceRoot(const BlockId& existing, const BlockId& scratch) {
    Replaced r;
    auto old = loadNode(existing);
    if (old) { r.oldChildren = old->children; r.childDepth = old->depth - 1; }
    auto top = bs_.load(scratch);
    if (!top) throw Error(Err::Io, "Failed to build new blob content");
    bs_.store(existing, *top, false);
    bs_.remove(scratch);
    return r;
}

void DataTree::deleteSubtree(const BlockId& id, int depth) {
    if (depth > 0) {
        auto n = loadNode(id);
        if (n) for (auto& c : n->children) deleteSubtree(c, n->depth - 1);
    }
    bs_.remove(id);   // leaves are removed without ever being decrypted
}

void DataTree::deleteSubtrees(const std::vector<BlockId>& kids, int depth) {
    if (kids.empty()) return;
    if (kids.size() == 1 || Pool::insideWorker()) {
        for (auto& k : kids) deleteSubtree(k, depth);
        return;
    }
    std::vector<std::future<void>> futs;
    for (auto& k : kids) futs.push_back(Pool::shared().submit([this, k, depth] { deleteSubtree(k, depth); }));
    std::string firstErr;
    for (auto& f : futs) {
        try { f.get(); } catch (const std::exception& e) { if (firstErr.empty()) firstErr = e.what(); }
    }
    if (!firstErr.empty()) throw Error(Err::Io, "Failed to delete one or more blocks: " + firstErr);
}

void DataTree::deleteBlob(const BlockId& root) {
    auto n = loadNode(root);
    if (!n) { bs_.remove(root); return; }
    if (n->depth > 0) deleteSubtrees(n->children, n->depth - 1);
    bs_.remove(root);
}

void DataTree::patchFirstLeafBytes(const BlockId& root, size_t offset, const uint8_t* bytes, size_t n) {
    BlockId cur = root;
    for (;;) {
        auto node = loadNode(cur);
        if (!node) return;
        if (node->depth == 0) break;
        if (node->children.empty()) return;
        cur = node->children.front();
    }
    auto raw = bs_.load(cur);
    if (!raw) return;
    size_t off = kNodeHeader + offset;
    if (off + n > raw->size()) return;
    std::memcpy(raw->data() + off, bytes, n);
    bs_.store(cur, *raw, false);
}

// ------------------------------------------------------------- dir blobs --

static constexpr size_t kFixedFields = 1 + 4 + 4 + 4 + 12 + 12 + 12;

Bytes dirSerialize(std::vector<DirRecord> entries) {
    std::sort(entries.begin(), entries.end(), [](const DirRecord& a, const DirRecord& b) { return a.blob.b < b.blob.b; });
    Bytes out;
    for (const auto& e : entries) {
        uint8_t fixed[kFixedFields] = {0};
        fixed[0] = (uint8_t)e.type;
        writeU32LE(fixed + 1, e.mode);
        writeU32LE(fixed + 5, e.uid);
        writeU32LE(fixed + 9, e.gid);
        writeU64LE(fixed + 13, (uint64_t)e.atime);
        writeU64LE(fixed + 25, (uint64_t)e.mtime);
        writeU64LE(fixed + 37, (uint64_t)e.ctime);
        out.insert(out.end(), fixed, fixed + kFixedFields);
        out.insert(out.end(), e.name.begin(), e.name.end());
        out.push_back(0);
        out.insert(out.end(), e.blob.b.begin(), e.blob.b.end());
    }
    return out;
}

std::vector<DirRecord> dirParse(const Bytes& b) {
    std::vector<DirRecord> out;
    size_t pos = 0;
    while (pos < b.size()) {
        if (pos + kFixedFields > b.size()) throw Error(Err::InvalidVault, "Truncated directory entry");
        DirRecord e;
        uint8_t t = b[pos];
        if (t > 2) throw Error(Err::InvalidVault, "Unknown directory entry type " + std::to_string(t));
        e.type = (EntryType)t;
        e.mode = readU32LE(&b[pos + 1]);
        e.uid = readU32LE(&b[pos + 5]);
        e.gid = readU32LE(&b[pos + 9]);
        e.atime = (int64_t)readU64LE(&b[pos + 13]);
        e.mtime = (int64_t)readU64LE(&b[pos + 25]);
        e.ctime = (int64_t)readU64LE(&b[pos + 37]);
        pos += kFixedFields;
        size_t ns = pos;
        while (pos < b.size() && b[pos] != 0) pos++;
        if (pos >= b.size()) throw Error(Err::InvalidVault, "Truncated directory entry (unterminated name)");
        e.name.assign((const char*)&b[ns], pos - ns);
        pos++;
        if (pos + 16 > b.size()) throw Error(Err::InvalidVault, "Truncated directory entry (missing blob id)");
        std::memcpy(e.blob.b.data(), &b[pos], 16);
        pos += 16;
        out.push_back(std::move(e));
    }
    return out;
}

Bytes fsWrap(EntryType t, const BlockId& parent, const Bytes& payload) {
    Bytes out(kFsHeaderSize + payload.size());
    writeU16LE(out.data(), 1);
    out[2] = (uint8_t)t;
    std::memcpy(out.data() + 3, parent.b.data(), 16);
    if (!payload.empty()) std::memcpy(out.data() + kFsHeaderSize, payload.data(), payload.size());
    return out;
}

}  // namespace fv::cryfs
