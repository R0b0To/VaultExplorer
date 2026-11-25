// Desktop C ABI for folder vaults (gocryptfs / Cryptomator / CryFS); see ve_engine.h and ve_volumes.h.
//
// This is the desktop twin of jni/foldervault_bridge.cpp: the same fv:: core, the same open/create
// semantics, only with C types instead of JNI ones and PosixStorage as the only storage backend
// (a desktop vault folder is an ordinary directory, so no SAF-style callback storage is needed).
// An unlocked vault is parked in a slot of the engine's vm::VolumeManager (ve_volumes.h) so the generic ve_*
// file calls reach it exactly as they reach a container.

#include "ve_engine.h"
#include "ve_volumes.h"

#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include <atomic>
#include <exception>
#include <memory>
#include <mutex>
#include <set>

#include "crypto/user_entropy.h"
#include "foldervault/fv_check.h"
#include "foldervault/fv_formats.h"
#include "foldervault/fv_storage.h"
#include "foldervault/fv_vault.h"
#include "platform/engine_hooks.h"
#include "volman/vm_foldervault.h"
#include "jni_callbacks.h"

extern "C" int ve_log_enabled(void);
extern "C" void ve_log_dispatch(int prio, const char* tag, const char* message);

namespace {

// ── slots ───────────────────────────────────────────────────────────────────────────────────
// The slot table is the engine's vm::VolumeManager; a folder vault is a vm::FolderVaultVolume in it.

bool validVol(int32_t vol) { return vol >= 0 && vol < ve_max_volumes(); }

// The folder-vault volume in `vol`, or null when the slot is empty, holds a container, or its vault was closed.
std::shared_ptr<vm::FolderVaultVolume> folderVolumeOf(int32_t vol) {
    if (!validVol(vol)) return nullptr;
    auto fvv = std::dynamic_pointer_cast<vm::FolderVaultVolume>(ve_internal_volumes().get(vol));
    return (fvv && fvv->alive()) ? fvv : nullptr;
}

// The vault itself, for the calls that need more than vm::Volume offers. The pointer keeps the volume (and so
// the vault) alive while the caller uses it; fv::Vault::close() still waits for calls in flight.
std::shared_ptr<fv::Vault> vaultOf(int32_t vol) {
    auto fvv = folderVolumeOf(vol);
    return fvv ? std::shared_ptr<fv::Vault>(fvv, &fvv->vault()) : nullptr;
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

// Same shape as DirEntryWire.encode(): kind|size|mtimeSeconds|name (kind: F file, D folder, L symlink, LD symlink to a
// folder -- the link kinds only ever come out of listSymlinks, never out of list)
std::string wireEntry(const fv::DirEntry& e) {
    std::string name = e.name;
    sanitizeUtf8(name);
    return std::string(e.isSymlink ? (e.isDir ? "LD|" : "L|") : e.isDir ? "D|" : "F|") + std::to_string(e.isDir ? 0 : e.size) + "|" +
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

// ════════════════════════════════════════════ internal helpers (ve_volumes.h) ════════

namespace vefv {

int32_t containerFormat(int32_t vol) {
    auto v = vaultOf(vol);
    return v ? formatCodeOf(v->format()) : -1;
}

int32_t importFile(int32_t vol, const char* vaultPath, const char* hostSource, int32_t opId) {
    auto v = vaultOf(vol);
    if (!v) return VE_ERR_NOT_UNLOCKED;
    if (v->readOnly()) return VE_ERR_READ_ONLY;
    FV_TRY
    ImportProgress prog(opId);
    return v->writeBackFile(vaultPath, hostSource, &prog) ? VE_OK : VE_ERR_FAILED;
    FV_CATCH(VE_ERR_EXCEPTION, nullptr)
}

int32_t exportFile(int32_t vol, const char* vaultPath, const char* hostDest, int32_t opId) {
    auto v = vaultOf(vol);
    if (!v) return VE_ERR_NOT_UNLOCKED;
    FV_TRY
    ExportProgress prog(opId);
    return v->extractFile(vaultPath, hostDest, &prog) ? VE_OK : VE_ERR_FAILED;
    FV_CATCH(VE_ERR_EXCEPTION, nullptr)
}

int32_t vaultInfo(int32_t vol, ve_vault_info* out) {
    auto v = vaultOf(vol);
    if (!v) return VE_ERR_NOT_UNLOCKED;
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
                                       int32_t read_only, int32_t backup_key_files, const char* local_state_dir,
                                       const char* temp_dir, ve_buffer* message, ve_buffer* derived_key) {
    if (message) { message->data = nullptr; message->len = 0; }
    if (derived_key) { derived_key->data = nullptr; derived_key->len = 0; }
    if (!validVol(vol_id) || !root || format < 0 || format > 2 || password_len < 0 || combined_key_len < 0 ||
        (password_len > 0 && !password) || (combined_key_len > 0 && !combined_key)) {
        return VE_ERR_INVALID_ARG;
    }
    FV_TRY
    ensureInit();
    // Checked before the (slow) key derivation; attach() below is what actually decides.
    if (ve_internal_volumes().isUnlocked(vol_id)) {
        setMessage(message, "volume slot already in use");
        return VE_ERR_FAILED;
    }
    auto st = std::make_shared<fv::PosixStorage>(root);
    fv::HostEnv env = makeEnv(local_state_dir, temp_dir);
    env.backupKeyFilesOnOpen = backup_key_files != 0;  // only Cryptomator reads it
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
    if (!ve_internal_volumes().attach(vol_id, vm::wrapFolderVault(vault), root)) {  // lost a race for the slot
        vault->close();
        setMessage(message, "volume slot already in use");
        return VE_ERR_FAILED;
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

extern "C" VE_API int32_t ve_fv_probe_cryptomator(const char* root, int32_t* code_out) {
    if (!root || !code_out) return VE_ERR_INVALID_ARG;
    *code_out = 0;
    FV_TRY
    ensureInit();
    fv::PosixStorage st(root);
    *code_out = fv::probeCryptomatorFormat(st);
    st.close();
    return VE_OK;
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
    auto& mgr = ve_internal_volumes();
    vm::VolumeManager::Traits t;
    if (mgr.traits(vol_id, t) != vm::Status::Ok || t.family != vm::Family::FolderVault) return VE_ERR_NOT_UNLOCKED;
    if (t.readOnly) return VE_ERR_READ_ONLY;
    return mgr.finishWrite(vol_id, path) == vm::Status::Ok ? VE_OK : VE_ERR_FAILED;
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

// ── check & repair ─────────────────────────────────────────────────────────────────────────────

namespace {

bool wireToVaultFormat(int32_t wire, fv::VaultFormat& out) {
    switch (wire) {
        case VE_FV_GOCRYPTFS: out = fv::VaultFormat::Gocryptfs; return true;
        case VE_FV_CRYPTOMATOR: out = fv::VaultFormat::Cryptomator; return true;
        case VE_FV_CRYFS: out = fv::VaultFormat::Cryfs; return true;
    }
    return false;
}

void putString(std::vector<uint8_t>& out, const std::string& s) {
    putU32(out, static_cast<uint32_t>(s.size()));
    out.insert(out.end(), s.begin(), s.end());
}

void putIssues(std::vector<uint8_t>& out, const std::vector<fv::check::Issue>& issues) {
    putU32(out, static_cast<uint32_t>(issues.size()));
    for (const auto& i : issues) {
        putU32(out, static_cast<uint32_t>(i.severity));
        putString(out, i.path);
        putString(out, i.message);
    }
}

int32_t outcomeCode(fv::check::Outcome o) {
    return o == fv::check::Outcome::Ok ? 0 : o == fv::check::Outcome::WrongPassword ? 1 : 2;
}

// Shared body of ve_fv_check / ve_fv_repair: build the storage and credentials, run, pack the record.
int32_t checkOrRepair(bool repair, int32_t format, const char* root, const uint8_t* password, int32_t password_len,
                      int32_t session_vol, const char* local_state_dir, const char* temp_dir, int32_t op_id,
                      ve_buffer* out) {
    if (!out) return VE_ERR_INVALID_ARG;
    out->data = nullptr;
    out->len = 0;
    if (!root || password_len < 0 || (password_len > 0 && !password)) return VE_ERR_INVALID_ARG;

    std::vector<uint8_t> rec;
    auto refuse = [&](const std::string& message) {
        putU32(rec, 2);
        putString(rec, message);
        return emitBuffer(rec.data(), rec.size(), out) ? VE_OK : VE_ERR_FAILED;
    };

    fv::VaultFormat vf;
    if (!wireToVaultFormat(format, vf)) return refuse("Unsupported folder vault format.");
    try {
        ensureInit();

        // The unlocked vault of this same folder, when the caller has one: its keys are used inside the process
        // instead of the password. A session of another format is ignored (the password path is used).
        std::shared_ptr<fv::Vault> session;
        if (session_vol >= 0) {
            session = vaultOf(session_vol);
            if (!session) {
                return refuse(repair ? "This vault isn't open anymore -- pick it again and enter its password to repair."
                                     : "This vault isn't open anymore -- pick it again and enter its password for a deep scan.");
            }
            if (session->format() != vf) session.reset();
        }

        fv::PosixStorage st(root);
        fv::check::Credentials cr;
        if (password_len > 0) {
            cr.password = password;
            cr.passwordLen = static_cast<size_t>(password_len);
        }
        cr.session = session.get();
        fv::check::Hooks hooks;
        if (op_id > 0) hooks.log = [op_id](const std::string& m) { reportRepairLog(op_id, m.c_str()); };
        const fv::HostEnv env = makeEnv(local_state_dir, temp_dir);

        if (repair) {
            const fv::check::RepairResult r = fv::check::repairVault(vf, st, cr, env, hooks);
            st.close();
            putU32(rec, static_cast<uint32_t>(outcomeCode(r.outcome)));
            putString(rec, r.message);
            if (r.outcome == fv::check::Outcome::Ok) {
                putU32(rec, static_cast<uint32_t>(r.report.fixed));
                putU32(rec, static_cast<uint32_t>(r.report.recovered));
                putU32(rec, static_cast<uint32_t>(r.report.removed));
                putIssues(rec, r.report.remaining);
            }
        } else {
            const fv::check::CheckResult r = fv::check::checkVault(vf, st, cr, env, hooks);
            st.close();
            putU32(rec, static_cast<uint32_t>(outcomeCode(r.outcome)));
            putString(rec, r.message);
            if (r.outcome == fv::check::Outcome::Ok) {
                putU32(rec, static_cast<uint32_t>(r.report.filesScanned));
                putU32(rec, r.report.deepScan ? 1u : 0u);
                putIssues(rec, r.report.issues);
            }
        }
        return emitBuffer(rec.data(), rec.size(), out) ? VE_OK : VE_ERR_FAILED;
    } catch (const std::exception& e) {
        rec.clear();
        return refuse(e.what());
    } catch (...) {
        rec.clear();
        return refuse("unexpected error in the folder-vault core");
    }
}

}  // namespace

extern "C" VE_API int32_t ve_fv_check(int32_t format, const char* root, const uint8_t* password, int32_t password_len,
                                      int32_t session_vol, const char* local_state_dir, const char* temp_dir,
                                      int32_t op_id, ve_buffer* out) {
    return checkOrRepair(false, format, root, password, password_len, session_vol, local_state_dir, temp_dir, op_id, out);
}

extern "C" VE_API int32_t ve_fv_repair(int32_t format, const char* root, const uint8_t* password, int32_t password_len,
                                       int32_t session_vol, const char* local_state_dir, const char* temp_dir,
                                       int32_t op_id, ve_buffer* out) {
    return checkOrRepair(true, format, root, password, password_len, session_vol, local_state_dir, temp_dir, op_id, out);
}

extern "C" VE_API int32_t ve_fv_config_file_name(int32_t format, ve_buffer* out) {
    if (!out) return VE_ERR_INVALID_ARG;
    out->data = nullptr;
    out->len = 0;
    fv::VaultFormat vf;
    if (!wireToVaultFormat(format, vf)) return VE_ERR_INVALID_ARG;
    const std::string name = fv::configFileName(vf);
    return emitBuffer(reinterpret_cast<const uint8_t*>(name.data()), name.size(), out) ? VE_OK : VE_ERR_FAILED;
}

extern "C" VE_API int32_t ve_fv_validate_config(int32_t format, const uint8_t* bytes, int32_t len, ve_buffer* reason) {
    if (reason) { reason->data = nullptr; reason->len = 0; }
    fv::VaultFormat vf;
    if (!wireToVaultFormat(format, vf) || len < 0 || (len > 0 && !bytes)) return VE_ERR_INVALID_ARG;
    FV_TRY
    std::string why;
    if (fv::validateConfigFile(vf, fv::Bytes(bytes, bytes + len), why)) return VE_OK;
    setMessage(reason, why.empty() ? "This isn't a valid config file for this vault format." : why);
    return VE_ERR_FAILED;
    FV_CATCH(VE_ERR_EXCEPTION, reason)
}
