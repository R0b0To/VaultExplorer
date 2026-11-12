// Desktop C ABI for folder vaults (gocryptfs / Cryptomator / CryFS); see ve_engine.h and ve_foldervault.h.
//
// This is the desktop twin of jni/foldervault_bridge.cpp: the same fv:: core, the same open/create
// semantics, only with C types instead of JNI ones and PosixStorage as the only storage backend
// (a desktop vault folder is an ordinary directory, so no SAF-style callback storage is needed).
// An unlocked vault is parked in a volume slot so the generic ve_* file calls reach it.

#include "ve_engine.h"
#include "ve_foldervault.h"

#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#if !defined(VE_NO_FOLDERVAULT)

#include <atomic>
#include <exception>
#include <memory>
#include <mutex>
#include <set>

#include "crypto/user_entropy.h"
#include "foldervault/fv_storage.h"
#include "foldervault/fv_vault.h"
#include "jni_callbacks.h"

extern "C" int ve_log_enabled(void);
extern "C" void ve_log_dispatch(int prio, const char* tag, const char* message);

namespace {

// ── slot registry ───────────────────────────────────────────────────────────────────────────
struct Stream {
    std::string path;
};
struct Slot {
    std::shared_ptr<fv::Vault> vault;
    std::set<Stream*> streams;
};

std::mutex g_mu;

std::vector<Slot>& slots() {  // callers hold g_mu
    static std::vector<Slot> s(static_cast<size_t>(ve_max_volumes()));
    return s;
}

bool validVol(int32_t vol) { return vol >= 0 && vol < ve_max_volumes(); }

std::shared_ptr<fv::Vault> vaultOf(int32_t vol) {
    if (!validVol(vol)) return nullptr;
    std::lock_guard<std::mutex> g(g_mu);
    return slots()[static_cast<size_t>(vol)].vault;
}

// ── helpers ─────────────────────────────────────────────────────────────────────────────────
void putU32(std::vector<uint8_t>& out, uint32_t v) {
    for (int i = 0; i < 4; ++i) out.push_back(static_cast<uint8_t>(v >> (8 * i)));
}

bool emitBuffer(const uint8_t* bytes, size_t len, ve_buffer* out) {
    if (!out) return true;
    out->data = nullptr;
    out->len = 0;
    if (len == 0) return true;
    auto* mem = static_cast<uint8_t*>(std::malloc(len));
    if (!mem) return false;
    std::memcpy(mem, bytes, len);
    out->data = mem;
    out->len = len;
    return true;
}

void setMessage(ve_buffer* out, const std::string& msg) {
    if (!out) return;
    emitBuffer(reinterpret_cast<const uint8_t*>(msg.data()), msg.size(), out);
}

// A name decrypted from a vault is attacker-influenced bytes: make it safe to hand to a UTF-8 decoder
// (control characters become '_', every malformed byte '?'). Mirrors what the block-device listing does.
void sanitizeUtf8(std::string& s) {
    std::string out;
    out.reserve(s.size());
    const size_t n = s.size();
    for (size_t i = 0; i < n;) {
        const unsigned char c = static_cast<unsigned char>(s[i]);
        size_t len = 0;
        if (c < 0x80) len = 1;
        else if (c >= 0xC2 && c <= 0xDF) len = 2;
        else if (c >= 0xE0 && c <= 0xEF) len = 3;
        else if (c >= 0xF0 && c <= 0xF4) len = 4;
        bool ok = len != 0 && i + len <= n;
        for (size_t k = 1; ok && k < len; ++k) ok = (static_cast<unsigned char>(s[i + k]) & 0xC0) == 0x80;
        if (ok && len == 3) {  // overlongs and surrogates
            const unsigned char c1 = static_cast<unsigned char>(s[i + 1]);
            if ((c == 0xE0 && c1 < 0xA0) || (c == 0xED && c1 >= 0xA0)) ok = false;
        }
        if (ok && len == 4) {
            const unsigned char c1 = static_cast<unsigned char>(s[i + 1]);
            if ((c == 0xF0 && c1 < 0x90) || (c == 0xF4 && c1 >= 0x90)) ok = false;
        }
        if (!ok) {
            out.push_back('?');
            ++i;
        } else if (len == 1 && (c < 32 || c == 127)) {
            out.push_back('_');
            ++i;
        } else {
            out.append(s, i, len);
            i += len;
        }
    }
    s.swap(out);
}

// Same shape as DirEntryWire.encode(): kind|size|mtimeSeconds|name
std::string wireEntry(const fv::DirEntry& e) {
    std::string name = e.name;
    sanitizeUtf8(name);
    return std::string(e.isSymlink ? "L|" : e.isDir ? "D|" : "F|") + std::to_string(e.isDir ? 0 : e.size) + "|" +
           std::to_string(e.mtimeMs / 1000) + "|" + name;
}

int32_t packEntries(const std::vector<fv::DirEntry>& es, ve_buffer* out) {
    std::vector<uint8_t> packed;
    putU32(packed, static_cast<uint32_t>(es.size()));
    for (const auto& e : es) {
        const std::string w = wireEntry(e);
        putU32(packed, static_cast<uint32_t>(w.size()));
        packed.insert(packed.end(), w.begin(), w.end());
    }
    return emitBuffer(packed.data(), packed.size(), out) ? VE_OK : VE_ERR_FAILED;
}

void fvLog(fv::LogLevel level, const char* tag, const std::string& msg) {
    if (!ve_log_enabled()) return;
    const int prio = level == fv::LogLevel::Debug ? 3 : level == fv::LogLevel::Info ? 4 : level == fv::LogLevel::Warn ? 5 : 6;
    ve_log_dispatch(prio, tag ? tag : "FolderVault", msg.c_str());
}

void ensureInit() {
    static std::once_flag once;
    std::call_once(once, [] { fv::setLogger(fvLog); });
}

fv::HostEnv makeEnv(const char* localState, const char* tempDir) {
    fv::HostEnv e;
    if (localState) e.cryfsLocalStateDir = localState;
    if (tempDir) e.tempDir = tempDir;
    return e;
}

int32_t statusToRc(fv::OpenStatus s) {
    switch (s) {
        case fv::OpenStatus::Ok: return VE_OK;
        case fv::OpenStatus::WrongPassword: return VE_ERR_AUTH_FAILED;
        default: return VE_ERR_FAILED;
    }
}

#define FV_TRY try {
#define FV_CATCH(retval, msgbuf)                                         \
    }                                                                    \
    catch (const std::exception& e) {                                    \
        setMessage((msgbuf), e.what());                                  \
        return (retval);                                                 \
    }                                                                    \
    catch (...) {                                                        \
        setMessage((msgbuf), "unexpected error in the folder-vault core"); \
        return (retval);                                                 \
    }

struct ImportProgress final : fv::Progress {
    explicit ImportProgress(int op) : op_(op) {}
    void onWriteBack(uint64_t bytes) override { if (op_ > 0) reportWriteBackChunkProgress(op_, bytes); }
    bool cancelled() override { return op_ > 0 && isWriteBackCancelled(op_); }
    int op_;
};
struct ExportProgress final : fv::Progress {
    explicit ExportProgress(int op) : op_(op) {}
    void onExtract(uint64_t bytes) override { if (op_ > 0) reportExtractChunkProgress(op_, bytes); }
    bool cancelled() override { return op_ > 0 && isExtractCancelled(op_); }
    int op_;
};

int32_t formatCodeOf(fv::VaultFormat f) {
    switch (f) {
        case fv::VaultFormat::Gocryptfs: return VE_FORMAT_GOCRYPTFS;
        case fv::VaultFormat::Cryptomator: return VE_FORMAT_CRYPTOMATOR;
        default: return VE_FORMAT_CRYFS;
    }
}

}  // namespace

// ════════════════════════════════════════════ internal slot API (ve_foldervault.h) ════════

namespace vefv {

bool isSlot(int32_t vol) { return vaultOf(vol) != nullptr; }

void closeSlot(int32_t vol) {
    if (!validVol(vol)) return;
    std::shared_ptr<fv::Vault> v;
    {
        std::lock_guard<std::mutex> g(g_mu);
        Slot& s = slots()[static_cast<size_t>(vol)];
        v = std::move(s.vault);
        s.vault.reset();
        for (Stream* st : s.streams) delete st;
        s.streams.clear();
    }
    if (v) {
        try { v->close(); } catch (...) {}  // waits for in-flight calls, wipes keys
    }
}

int32_t containerFormat(int32_t vol) {
    auto v = vaultOf(vol);
    return v ? formatCodeOf(v->format()) : -1;
}

bool isReadOnly(int32_t vol) {
    auto v = vaultOf(vol);
    return v && v->readOnly();
}

#define FV_VAULT_OR_RETURN(rc)                  \
    auto v = vaultOf(vol);                      \
    if (!v) return (rc);

int32_t list(int32_t vol, const char* path, ve_buffer* out) {
    FV_VAULT_OR_RETURN(VE_ERR_NOT_UNLOCKED)
    FV_TRY
    std::vector<fv::DirEntry> es;
    if (!v->listDirectory(path, es)) return VE_ERR_FAILED;
    return packEntries(es, out);
    FV_CATCH(VE_ERR_EXCEPTION, nullptr)
}

int64_t fileSize(int32_t vol, const char* path) {
    FV_VAULT_OR_RETURN(-VE_ERR_NOT_UNLOCKED)
    FV_TRY
    return v->getFileSize(path);  // -1 when missing / a directory: the block path's convention too
    FV_CATCH(-VE_ERR_EXCEPTION, nullptr)
}

int64_t folderSize(int32_t vol, const char* path) {
    FV_VAULT_OR_RETURN(-VE_ERR_NOT_UNLOCKED)
    FV_TRY
    return v->getFolderSize(path);
    FV_CATCH(-VE_ERR_EXCEPTION, nullptr)
}

int32_t readChunk(int32_t vol, const char* path, int64_t offset, int32_t length, std::vector<uint8_t>& out) {
    FV_VAULT_OR_RETURN(VE_ERR_NOT_UNLOCKED)
    FV_TRY
    auto r = v->readFileChunk(path, offset, length);
    if (!r) return VE_ERR_FAILED;
    out = std::move(*r);
    return VE_OK;
    FV_CATCH(VE_ERR_EXCEPTION, nullptr)
}

int32_t writeChunk(int32_t vol, const char* path, int64_t offset, const uint8_t* data, size_t len) {
    FV_VAULT_OR_RETURN(VE_ERR_NOT_UNLOCKED)
    if (v->readOnly()) return VE_ERR_READ_ONLY;
    FV_TRY
    static const uint8_t kNone = 0;
    return v->writeFileChunk(path, offset, data ? data : &kNone, len) ? VE_OK : VE_ERR_FAILED;
    FV_CATCH(VE_ERR_EXCEPTION, nullptr)
}

int32_t finishWrite(int32_t vol, const char* path) {
    FV_VAULT_OR_RETURN(VE_ERR_NOT_UNLOCKED)
    if (v->readOnly()) return VE_ERR_READ_ONLY;
    FV_TRY
    return v->finishWrite(path) ? VE_OK : VE_ERR_FAILED;
    FV_CATCH(VE_ERR_EXCEPTION, nullptr)
}

int32_t remove(int32_t vol, const char* path) {
    FV_VAULT_OR_RETURN(VE_ERR_NOT_UNLOCKED)
    if (v->readOnly()) return VE_ERR_READ_ONLY;
    FV_TRY
    return v->deleteFile(path) ? VE_OK : VE_ERR_FAILED;
    FV_CATCH(VE_ERR_EXCEPTION, nullptr)
}

int32_t makeDirectory(int32_t vol, const char* path) {
    FV_VAULT_OR_RETURN(VE_ERR_NOT_UNLOCKED)
    if (v->readOnly()) return VE_ERR_READ_ONLY;
    FV_TRY
    return v->createDirectory(path) ? VE_OK : VE_ERR_FAILED;
    FV_CATCH(VE_ERR_EXCEPTION, nullptr)
}

int32_t rename(int32_t vol, const char* from, const char* to) {
    FV_VAULT_OR_RETURN(VE_ERR_NOT_UNLOCKED)
    if (v->readOnly()) return VE_ERR_READ_ONLY;
    FV_TRY
    return v->renameFile(from, to) ? VE_OK : VE_ERR_FAILED;
    FV_CATCH(VE_ERR_EXCEPTION, nullptr)
}

int32_t setLastModified(int32_t vol, const char* path, int64_t epochSeconds) {
    FV_VAULT_OR_RETURN(VE_ERR_NOT_UNLOCKED)
    if (v->readOnly()) return VE_ERR_READ_ONLY;
    FV_TRY
    return v->setLastModifiedTime(path, epochSeconds) ? VE_OK : VE_ERR_FAILED;
    FV_CATCH(VE_ERR_EXCEPTION, nullptr)
}

int32_t importFile(int32_t vol, const char* vaultPath, const char* hostSource, int32_t opId) {
    FV_VAULT_OR_RETURN(VE_ERR_NOT_UNLOCKED)
    if (v->readOnly()) return VE_ERR_READ_ONLY;
    FV_TRY
    ImportProgress prog(opId);
    return v->writeBackFile(vaultPath, hostSource, &prog) ? VE_OK : VE_ERR_FAILED;
    FV_CATCH(VE_ERR_EXCEPTION, nullptr)
}

int32_t exportFile(int32_t vol, const char* vaultPath, const char* hostDest, int32_t opId) {
    FV_VAULT_OR_RETURN(VE_ERR_NOT_UNLOCKED)
    FV_TRY
    ExportProgress prog(opId);
    return v->extractFile(vaultPath, hostDest, &prog) ? VE_OK : VE_ERR_FAILED;
    FV_CATCH(VE_ERR_EXCEPTION, nullptr)
}

int32_t spaceInfo(int32_t vol, uint64_t* total, uint64_t* freeBytes) {
    FV_VAULT_OR_RETURN(VE_ERR_NOT_UNLOCKED)
    FV_TRY
    int64_t t = 0, f = 0;
    if (!v->spaceInfo(t, f)) return VE_ERR_FAILED;
    *total = t > 0 ? static_cast<uint64_t>(t) : 0;
    *freeBytes = f > 0 ? static_cast<uint64_t>(f) : 0;
    return VE_OK;
    FV_CATCH(VE_ERR_EXCEPTION, nullptr)
}

int32_t vaultInfo(int32_t vol, ve_vault_info* out) {
    FV_VAULT_OR_RETURN(VE_ERR_NOT_UNLOCKED)
    const int32_t size = out->struct_size;
    std::memset(out, 0, sizeof(*out));
    out->struct_size = size;
    out->container_format = formatCodeOf(v->format());
    out->read_only = v->readOnly() ? 1 : 0;
    int64_t t = 0, f = 0;
    try {
        if (v->spaceInfo(t, f) && t > 0) out->volume_size_bytes = t;
    } catch (...) {}
    return VE_OK;
}

int64_t openStream(int32_t vol, const char* path) {
    FV_VAULT_OR_RETURN(0)
    FV_TRY
    if (v->getFileSize(path) < 0) return 0;
    auto* st = new Stream{path};
    std::lock_guard<std::mutex> g(g_mu);
    Slot& s = slots()[static_cast<size_t>(vol)];
    if (s.vault != v) {  // locked/replaced while we were checking
        delete st;
        return 0;
    }
    s.streams.insert(st);
    return static_cast<int64_t>(reinterpret_cast<intptr_t>(st));
    FV_CATCH(0, nullptr)
}

int32_t readStream(int32_t vol, int64_t handle, int64_t offset, uint8_t* dest, int32_t length) {
    if (!validVol(vol) || handle == 0) return -1;
    std::shared_ptr<fv::Vault> v;
    std::string path;
    {
        std::lock_guard<std::mutex> g(g_mu);
        Slot& s = slots()[static_cast<size_t>(vol)];
        auto* st = reinterpret_cast<Stream*>(static_cast<intptr_t>(handle));
        if (!s.vault || s.streams.find(st) == s.streams.end()) return -1;
        v = s.vault;
        path = st->path;
    }
    try {
        auto r = v->readFileChunk(path, offset, length);
        if (!r) return -1;
        const size_t n = r->size() < static_cast<size_t>(length) ? r->size() : static_cast<size_t>(length);
        if (n) std::memcpy(dest, r->data(), n);
        fv::secureZero(r->data(), r->size());
        return static_cast<int32_t>(n);
    } catch (...) {
        return -1;
    }
}

void closeStream(int32_t vol, int64_t handle) {
    if (!validVol(vol) || handle == 0) return;
    std::lock_guard<std::mutex> g(g_mu);
    Slot& s = slots()[static_cast<size_t>(vol)];
    auto* st = reinterpret_cast<Stream*>(static_cast<intptr_t>(handle));
    auto it = s.streams.find(st);
    if (it == s.streams.end()) return;  // already invalidated by a lock
    s.streams.erase(it);
    delete st;
}

}  // namespace vefv

// ════════════════════════════════════════════ exported C ABI ═══════════════════════════════

extern "C" VE_API int32_t ve_fv_supported(void) { return 1; }

extern "C" VE_API int32_t ve_fv_probe(const char* root, int32_t* format_out) {
    if (!root || !format_out) return VE_ERR_INVALID_ARG;
    *format_out = -1;
    FV_TRY
    ensureInit();
    fv::PosixStorage st(root);
    if (fv::looksLikeGocryptfs(st)) *format_out = VE_FV_GOCRYPTFS;
    else if (fv::looksLikeCryptomator(st)) *format_out = VE_FV_CRYPTOMATOR;
    else if (fv::looksLikeCryfs(st)) *format_out = VE_FV_CRYFS;
    return VE_OK;
    FV_CATCH(VE_ERR_EXCEPTION, nullptr)
}

extern "C" VE_API int32_t ve_fv_unlock(int32_t vol_id, int32_t format, const char* root, const uint8_t* password,
                                       int32_t password_len, const uint8_t* combined_key, int32_t combined_key_len,
                                       int32_t read_only, const char* local_state_dir, const char* temp_dir,
                                       ve_buffer* message, ve_buffer* derived_key) {
    if (message) { message->data = nullptr; message->len = 0; }
    if (derived_key) { derived_key->data = nullptr; derived_key->len = 0; }
    if (!validVol(vol_id) || !root || format < 0 || format > 2 || password_len < 0 || combined_key_len < 0 ||
        (password_len > 0 && !password) || (combined_key_len > 0 && !combined_key)) {
        return VE_ERR_INVALID_ARG;
    }
    FV_TRY
    ensureInit();
    {
        std::lock_guard<std::mutex> g(g_mu);
        if (slots()[static_cast<size_t>(vol_id)].vault) {
            setMessage(message, "volume slot already in use");
            return VE_ERR_FAILED;
        }
    }
    auto st = std::make_shared<fv::PosixStorage>(root);
    const fv::HostEnv env = makeEnv(local_state_dir, temp_dir);
    static const uint8_t kNone = 0;
    const uint8_t* pw = password ? password : &kNone;
    const size_t pwLen = static_cast<size_t>(password_len);

    fv::OpenResult r;
    const bool ro = read_only != 0;
    if (format == VE_FV_GOCRYPTFS) r = fv::openGocryptfs(st, pw, pwLen, ro, env);
    else if (format == VE_FV_CRYPTOMATOR) r = fv::openCryptomator(st, pw, pwLen, ro, env);
    else if (combined_key_len > 0) r = fv::openCryfsWithCombinedKey(st, combined_key, static_cast<size_t>(combined_key_len), ro, env);
    else r = fv::openCryfs(st, pw, pwLen, ro, env);

    if (r.status != fv::OpenStatus::Ok || !r.vault) {
        setMessage(message, r.message);
        return r.status == fv::OpenStatus::Ok ? VE_ERR_FAILED : statusToRc(r.status);
    }
    if (derived_key && !r.derivedKey.empty()) emitBuffer(r.derivedKey.data(), r.derivedKey.size(), derived_key);

    std::shared_ptr<fv::Vault> vault(std::move(r.vault));
    {
        std::lock_guard<std::mutex> g(g_mu);
        Slot& s = slots()[static_cast<size_t>(vol_id)];
        if (s.vault) {  // lost a race for the slot
            vault->close();
            setMessage(message, "volume slot already in use");
            return VE_ERR_FAILED;
        }
        s.vault = std::move(vault);
    }
    return VE_OK;
    FV_CATCH(VE_ERR_EXCEPTION, message)
}

extern "C" VE_API int32_t ve_fv_create(int32_t format, const char* root, const uint8_t* password, int32_t password_len,
                                       int32_t cipher, int32_t plaintext_names, int32_t deterministic_names,
                                       int32_t long_name_max, int32_t block_size, const char* cipher_name,
                                       const uint8_t* user_entropy, int32_t user_entropy_len,
                                       const char* local_state_dir, const char* temp_dir, ve_buffer* message) {
    if (message) { message->data = nullptr; message->len = 0; }
    if (!root || format < 0 || format > 2 || password_len < 0 || (password_len > 0 && !password) ||
        user_entropy_len < 0) {
        return VE_ERR_INVALID_ARG;
    }
    FV_TRY
    ensureInit();
    userentropy::Scope entropy(user_entropy, user_entropy && user_entropy_len > 0 ? static_cast<size_t>(user_entropy_len) : 0);
    fv::PosixStorage st(root);
    static const uint8_t kNone = 0;
    const uint8_t* pw = password ? password : &kNone;
    const size_t pwLen = static_cast<size_t>(password_len);

    fv::PlainResult r;
    if (format == VE_FV_GOCRYPTFS) {
        fv::GocryptfsCreateOptions o;
        o.cipher = cipher == 1 ? fv::GocryptfsCipher::XChaCha20Poly1305
                 : cipher == 2 ? fv::GocryptfsCipher::AesSiv
                               : fv::GocryptfsCipher::Aes256Gcm;
        o.plaintextNames = plaintext_names != 0;
        o.deterministicNames = deterministic_names != 0;
        o.longNameMax = long_name_max;
        r = fv::createGocryptfs(st, pw, pwLen, o);
    } else if (format == VE_FV_CRYPTOMATOR) {
        r = fv::createCryptomator(st, pw, pwLen);
    } else {
        fv::CryfsCreateOptions o;
        if (cipher_name && *cipher_name) o.cipher = cipher_name;
        if (block_size > 0) o.blocksizeBytes = block_size;
        r = fv::createCryfs(st, pw, pwLen, o, makeEnv(local_state_dir, temp_dir));
    }
    st.close();
    if (r.status != fv::OpenStatus::Ok) setMessage(message, r.message);
    return statusToRc(r.status);
    FV_CATCH(VE_ERR_EXCEPTION, message)
}

extern "C" VE_API int32_t ve_fv_change_password(int32_t format, const char* root, const uint8_t* old_password,
                                                int32_t old_len, const uint8_t* new_password, int32_t new_len,
                                                ve_buffer* message) {
    if (message) { message->data = nullptr; message->len = 0; }
    if (!root || format < 0 || format > 2 || old_len < 0 || new_len < 0 || (old_len > 0 && !old_password) ||
        (new_len > 0 && !new_password)) {
        return VE_ERR_INVALID_ARG;
    }
    FV_TRY
    ensureInit();
    fv::PosixStorage st(root);
    static const uint8_t kNone = 0;
    const uint8_t* o = old_password ? old_password : &kNone;
    const uint8_t* n = new_password ? new_password : &kNone;
    fv::PlainResult r;
    if (format == VE_FV_GOCRYPTFS) r = fv::changeGocryptfsPassword(st, o, old_len, n, new_len);
    else if (format == VE_FV_CRYPTOMATOR) r = fv::changeCryptomatorPassword(st, o, old_len, n, new_len);
    else r = fv::changeCryfsPassword(st, o, old_len, n, new_len);
    st.close();
    if (r.status != fv::OpenStatus::Ok) setMessage(message, r.message);
    return statusToRc(r.status);
    FV_CATCH(VE_ERR_EXCEPTION, message)
}

extern "C" VE_API int32_t ve_fv_migrate_cryptomator(const char* root, const uint8_t* password, int32_t password_len,
                                                    ve_buffer* message) {
    if (message) { message->data = nullptr; message->len = 0; }
    if (!root || password_len < 0 || (password_len > 0 && !password)) return VE_ERR_INVALID_ARG;
    FV_TRY
    ensureInit();
    fv::PosixStorage st(root);
    static const uint8_t kNone = 0;
    fv::PlainResult r = fv::migrateCryptomator7To8(st, password ? password : &kNone, static_cast<size_t>(password_len));
    st.close();
    if (r.status != fv::OpenStatus::Ok) setMessage(message, r.message);
    return statusToRc(r.status);
    FV_CATCH(VE_ERR_EXCEPTION, message)
}

extern "C" VE_API int32_t ve_fv_info(int32_t vol_id, ve_buffer* out) {
    if (!out) return VE_ERR_INVALID_ARG;
    out->data = nullptr;
    out->len = 0;
    auto v = vaultOf(vol_id);
    if (!v) return VE_ERR_NOT_UNLOCKED;
    FV_TRY
    const auto items = v->info();
    std::vector<uint8_t> packed;
    putU32(packed, static_cast<uint32_t>(items.size()));
    auto putStr = [&](const std::string& s) {
        putU32(packed, static_cast<uint32_t>(s.size()));
        packed.insert(packed.end(), s.begin(), s.end());
    };
    for (const auto& it : items) {
        putStr(it.key);
        putStr(it.kind == fv::InfoItem::Kind::Int ? "i" : it.kind == fv::InfoItem::Kind::Bool ? "b" : "s");
        putStr(it.value);
    }
    return emitBuffer(packed.data(), packed.size(), out) ? VE_OK : VE_ERR_FAILED;
    FV_CATCH(VE_ERR_EXCEPTION, nullptr)
}

extern "C" VE_API int32_t ve_fv_list_symlinks(int32_t vol_id, const char* path, ve_buffer* out) {
    if (!out) return VE_ERR_INVALID_ARG;
    out->data = nullptr;
    out->len = 0;
    if (!path) return VE_ERR_INVALID_ARG;
    auto v = vaultOf(vol_id);
    if (!v) return VE_ERR_NOT_UNLOCKED;
    FV_TRY
    std::vector<fv::DirEntry> es;
    if (!v->listSymlinks(path, es)) return VE_ERR_FAILED;
    return packEntries(es, out);
    FV_CATCH(VE_ERR_EXCEPTION, nullptr)
}

extern "C" VE_API int32_t ve_fv_read_symlink(int32_t vol_id, const char* path, ve_buffer* out) {
    if (!out) return VE_ERR_INVALID_ARG;
    out->data = nullptr;
    out->len = 0;
    if (!path) return VE_ERR_INVALID_ARG;
    auto v = vaultOf(vol_id);
    if (!v) return VE_ERR_NOT_UNLOCKED;
    FV_TRY
    auto t = v->readSymlink(path);
    if (!t) return VE_ERR_FAILED;
    return emitBuffer(reinterpret_cast<const uint8_t*>(t->data()), t->size(), out) ? VE_OK : VE_ERR_FAILED;
    FV_CATCH(VE_ERR_EXCEPTION, nullptr)
}

extern "C" VE_API int32_t ve_fv_hidden_entry_count(int32_t vol_id, const char* path) {
    if (!path) return -VE_ERR_INVALID_ARG;
    auto v = vaultOf(vol_id);
    if (!v) return -VE_ERR_NOT_UNLOCKED;
    FV_TRY
    return v->hiddenEntryCount(path);
    FV_CATCH(-VE_ERR_EXCEPTION, nullptr)
}

extern "C" VE_API int32_t ve_fv_finish_write(int32_t vol_id, const char* path) {
    if (!path) return VE_ERR_INVALID_ARG;
    return vefv::finishWrite(vol_id, path);
}

extern "C" VE_API int32_t ve_fv_batch(int32_t vol_id, int32_t kind, int32_t begin) {
    if (kind != 0 && kind != 1) return VE_ERR_INVALID_ARG;
    auto v = vaultOf(vol_id);
    if (!v) return VE_ERR_NOT_UNLOCKED;
    FV_TRY
    if (kind == 0) { if (begin) v->beginBatchWrite(); else v->endBatchWrite(); }
    else           { if (begin) v->beginBatchDelete(); else v->endBatchDelete(); }
    return VE_OK;
    FV_CATCH(VE_ERR_EXCEPTION, nullptr)
}

#else  // VE_NO_FOLDERVAULT ─────────────────────────────────────────────────────────────────────
// Windows (for now): no folder-vault storage backend. Slots are never folder vaults, and the
// ve_fv_* entry points fail cleanly so the Dart side can say "not supported on this platform".

namespace vefv {
bool isSlot(int32_t) { return false; }
void closeSlot(int32_t) {}
int32_t containerFormat(int32_t) { return -1; }
bool isReadOnly(int32_t) { return false; }
int32_t list(int32_t, const char*, ve_buffer*) { return VE_ERR_NOT_UNLOCKED; }
int64_t fileSize(int32_t, const char*) { return -VE_ERR_NOT_UNLOCKED; }
int64_t folderSize(int32_t, const char*) { return -VE_ERR_NOT_UNLOCKED; }
int32_t readChunk(int32_t, const char*, int64_t, int32_t, std::vector<uint8_t>&) { return VE_ERR_NOT_UNLOCKED; }
int32_t writeChunk(int32_t, const char*, int64_t, const uint8_t*, size_t) { return VE_ERR_NOT_UNLOCKED; }
int32_t finishWrite(int32_t, const char*) { return VE_ERR_NOT_UNLOCKED; }
int32_t remove(int32_t, const char*) { return VE_ERR_NOT_UNLOCKED; }
int32_t makeDirectory(int32_t, const char*) { return VE_ERR_NOT_UNLOCKED; }
int32_t rename(int32_t, const char*, const char*) { return VE_ERR_NOT_UNLOCKED; }
int32_t setLastModified(int32_t, const char*, int64_t) { return VE_ERR_NOT_UNLOCKED; }
int32_t importFile(int32_t, const char*, const char*, int32_t) { return VE_ERR_NOT_UNLOCKED; }
int32_t exportFile(int32_t, const char*, const char*, int32_t) { return VE_ERR_NOT_UNLOCKED; }
int32_t spaceInfo(int32_t, uint64_t*, uint64_t*) { return VE_ERR_NOT_UNLOCKED; }
int32_t vaultInfo(int32_t, ve_vault_info*) { return VE_ERR_NOT_UNLOCKED; }
int64_t openStream(int32_t, const char*) { return 0; }
int32_t readStream(int32_t, int64_t, int64_t, uint8_t*, int32_t) { return -1; }
void closeStream(int32_t, int64_t) {}
}  // namespace vefv

namespace {
void clearBuf(ve_buffer* b) { if (b) { b->data = nullptr; b->len = 0; } }
void unsupported(ve_buffer* message) {
    clearBuf(message);
    if (!message) return;
    static const char kMsg[] = "Folder vaults are not available on Windows yet";
    if (auto* mem = static_cast<uint8_t*>(std::malloc(sizeof(kMsg) - 1))) {
        std::memcpy(mem, kMsg, sizeof(kMsg) - 1);
        message->data = mem;
        message->len = sizeof(kMsg) - 1;
    }
}
}  // namespace

extern "C" VE_API int32_t ve_fv_supported(void) { return 0; }
extern "C" VE_API int32_t ve_fv_probe(const char*, int32_t* format_out) {
    if (format_out) *format_out = -1;
    return VE_OK;
}
extern "C" VE_API int32_t ve_fv_unlock(int32_t, int32_t, const char*, const uint8_t*, int32_t, const uint8_t*,
                                       int32_t, int32_t, const char*, const char*, ve_buffer* message,
                                       ve_buffer* derived_key) {
    clearBuf(derived_key);
    unsupported(message);
    return VE_ERR_FAILED;
}
extern "C" VE_API int32_t ve_fv_create(int32_t, const char*, const uint8_t*, int32_t, int32_t, int32_t, int32_t,
                                       int32_t, int32_t, const char*, const uint8_t*, int32_t, const char*,
                                       const char*, ve_buffer* message) {
    unsupported(message);
    return VE_ERR_FAILED;
}
extern "C" VE_API int32_t ve_fv_change_password(int32_t, const char*, const uint8_t*, int32_t, const uint8_t*,
                                                int32_t, ve_buffer* message) {
    unsupported(message);
    return VE_ERR_FAILED;
}
extern "C" VE_API int32_t ve_fv_migrate_cryptomator(const char*, const uint8_t*, int32_t, ve_buffer* message) {
    unsupported(message);
    return VE_ERR_FAILED;
}
extern "C" VE_API int32_t ve_fv_info(int32_t, ve_buffer* out) { clearBuf(out); return VE_ERR_NOT_UNLOCKED; }
extern "C" VE_API int32_t ve_fv_list_symlinks(int32_t, const char*, ve_buffer* out) { clearBuf(out); return VE_ERR_NOT_UNLOCKED; }
extern "C" VE_API int32_t ve_fv_read_symlink(int32_t, const char*, ve_buffer* out) { clearBuf(out); return VE_ERR_NOT_UNLOCKED; }
extern "C" VE_API int32_t ve_fv_hidden_entry_count(int32_t, const char*) { return -VE_ERR_NOT_UNLOCKED; }
extern "C" VE_API int32_t ve_fv_finish_write(int32_t, const char*) { return VE_ERR_NOT_UNLOCKED; }
extern "C" VE_API int32_t ve_fv_batch(int32_t, int32_t, int32_t) { return VE_ERR_NOT_UNLOCKED; }

#endif  // VE_NO_FOLDERVAULT
