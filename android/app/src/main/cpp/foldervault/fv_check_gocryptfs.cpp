// gocryptfs Check & Repair. The rules for what is a valid file name, diriv, long-name sidecar and file header are
// the ones the engine (fv_gocryptfs*.cpp) uses, so the tool and the vault can never disagree about what is broken.
#include <algorithm>
#include <cstdlib>
#include <optional>
#include <memory>
#include <unordered_map>
#include <unordered_set>

#include "fv_check_internal.h"
#include "fv_crypto.h"
#include "fv_gocryptfs.h"

namespace fv::check::detail {
namespace {

using namespace fv::gocryptfs;

constexpr const char* TAG = "GocryptfsCheck";

bool validIv(const Bytes& iv) {
    if (iv.size() != kDirIvLen) return false;
    for (uint8_t b : iv) if (b) return true;
    return false;
}

// What a run needs from the vault: the parsed config and, when credentials were given, the two ciphers.
struct Keys {
    Config cfg;
    std::unique_ptr<NameCryptor> names;       // null without credentials
    std::unique_ptr<ContentFormat> content;   // null without credentials
    bool hasDirIv() const { return !cfg.plaintextNames && cfg.hasDirIV(); }
};

// Fills [k] from [cr]. [needKeys]: a missing password is an error (repair) instead of a structure-only run (check).
Outcome acquireKeys(Storage& st, const Config& cfg, const Credentials& cr, bool needKeys, Keys& k, std::string& msg) {
    k.cfg = cfg;
    if (cr.session) {
        KeyExport ke = cr.session->exportKeys();
        ExportWipe wipe(ke);
        const Bytes* nameKey = exportedField(ke, "nameKey");
        const Bytes* contentKey = exportedField(ke, "contentKey");
        const std::string* cipher = exportedString(ke, "cipher");
        const std::string* longMax = exportedString(ke, "longNameMax");
        const std::string* plain = exportedString(ke, "plaintextNames");
        const std::string* raw64 = exportedString(ke, "raw64");
        if (ke.format != VaultFormat::Gocryptfs || !nameKey || !contentKey || !cipher || !longMax || !plain) {
            msg = "The unlocked vault is not a gocryptfs vault.";
            return Outcome::InvalidVault;
        }
        const int cipherNo = std::atoi(cipher->c_str());
        if (cipherNo < 0 || cipherNo > 2) { msg = "The unlocked vault uses an unknown cipher."; return Outcome::InvalidVault; }
        k.names = std::make_unique<NameCryptor>(Secret(*nameKey), std::atoi(longMax->c_str()), *plain == "1", !raw64 || *raw64 != "0");
        k.content = std::make_unique<ContentFormat>(Secret(*contentKey), static_cast<GocryptfsCipher>(cipherNo));
        return Outcome::Ok;
    }
    if (!cr.password) {
        if (needKeys) { msg = "A password is required."; return Outcome::WrongPassword; }
        return Outcome::Ok;
    }
    try {
        Secret mk = unlockMasterkey(cfg, cr.password, cr.passwordLen);
        SessionKeys sk = deriveSessionKeys(cfg, mk);
        k.names = std::make_unique<NameCryptor>(sk.nameKey, cfg.longNameMax, cfg.plaintextNames, cfg.raw64());
        k.content = std::make_unique<ContentFormat>(sk.contentKey, cfg.cipher);
    } catch (const Error& e) {
        if (e.code() == Err::WrongPassword) { msg = e.what(); return Outcome::WrongPassword; }
        msg = e.what();
        return Outcome::InvalidVault;
    }
    (void)st;
    return Outcome::Ok;
}

// ---------------------------------------------------------------------------------------------------- check --

class Checker {
public:
    Checker(Ctx& c, const Keys& k) : c_(c), k_(k), nonceLen_(cipherInfo(k.cfg.cipher).nonceLen) {}

    int filesScanned() const { return files_; }

    void run() { walk("", ""); }

private:
    void walk(const std::string& phys, const std::string& vdir) {
        std::vector<DirEntry> ents;
        if (!c_.st.list(phys, ents)) {
            c_.add(Severity::Critical, reportPath(vdir), "This folder cannot be listed.");
            return;
        }
        std::unordered_map<std::string, const DirEntry*> byName;
        for (const DirEntry& e : ents) byName[e.name] = &e;

        Bytes iv(kDirIvLen, 0);
        bool ivOk = true;
        if (k_.hasDirIv()) {
            auto it = byName.find(kDirIvName);
            Bytes b;
            if (it == byName.end()) {
                c_.add(Severity::Critical, reportPath(vdir), "Missing gocryptfs.diriv.");
                ivOk = false;
            } else if (!c_.st.readWhole(joinPath(phys, kDirIvName), b) || !validIv(b)) {
                // gocryptfs refuses a diriv that is not exactly 16 bytes or that is all zero.
                c_.add(Severity::Critical, reportPath(vchild(vdir, kDirIvName)),
                       "gocryptfs.diriv is invalid (it must be exactly 16 bytes and not all zero).");
                ivOk = false;
            } else {
                iv = b;
            }
        }

        const bool plain = k_.cfg.plaintextNames;
        for (const DirEntry& e : ents) {
            const std::string& physName = e.name;
            // gocryptfs keeps its config in the root only. The diriv and the long-name sidecars exist only with
            // encrypted names; with plaintext names those are ordinary file names.
            if (phys.empty() && (physName == kConfigName || physName == kConfigBakName)) continue;
            if (e.isSymlink) continue;   // symbolic links stay in the ciphertext untouched
            if (!plain) {
                if (physName == kDirIvName) continue;
                if (NameCryptor::isLongNameFile(physName)) {
                    const std::string base = physName.substr(0, physName.size() - std::string(kLongNameSuffix).size());
                    if (!byName.count(base))
                        c_.add(Severity::Info, reportPath(vchild(vdir, physName)),
                               "Orphaned long-name sidecar (its gocryptfs.longname file is missing).");
                    continue;
                }
            }

            std::string cipherName = physName;
            if (!plain && NameCryptor::isLongNameContent(physName)) {
                auto side = byName.find(physName + kLongNameSuffix);
                if (side == byName.end()) {
                    c_.add(Severity::Warning, reportPath(vchild(vdir, physName)), "Long-name file missing .name sidecar.");
                    continue;
                }
                Bytes raw;
                if (side->second->size > (int64_t)kLongNameFileMax || !c_.st.readWhole(joinPath(phys, side->second->name), raw) ||
                    raw.empty() || raw.size() > kLongNameFileMax) {
                    c_.add(Severity::Critical, reportPath(vchild(vdir, physName)), "Filename doesn't decrypt: the .name sidecar is unreadable or invalid.");
                    continue;
                }
                cipherName.assign(raw.begin(), raw.end());
            }

            std::string clear = physName;
            if (!plain && k_.names && ivOk) {
                try {
                    clear = k_.names->decryptName(cipherName, iv.data());
                } catch (const Error& ex) {
                    c_.add(Severity::Critical, reportPath(vchild(vdir, physName)), std::string("Filename doesn't decrypt: ") + ex.what());
                }
            }
            const std::string childV = vchild(vdir, clear);
            const std::string childPhys = joinPath(phys, physName);

            if (e.isDir) {
                walk(childPhys, childV);
                continue;
            }
            files_++;
            checkFile(e, childPhys, childV);
        }
    }

    void checkFile(const DirEntry& e, const std::string& physPath, const std::string& vpath) {
        const int64_t size = e.size;
        const int64_t headerLen = (int64_t)ContentFormat::kHeaderLen;
        const std::string rp = reportPath(vpath);
        if (size == 0) {
            c_.add(Severity::Warning, rp, "0-byte file (missing 18-byte header).");
        } else if (size < headerLen) {
            c_.add(Severity::Warning, rp, "File shorter than header (" + std::to_string(size) + " bytes).");
        } else if (size > headerLen) {
            const int64_t chunk = (int64_t)(nonceLen_ + ContentFormat::kChunk + 16);
            const int64_t rem = (size - headerLen) % chunk;
            if (rem != 0 && rem < (int64_t)(nonceLen_ + 16))
                c_.add(Severity::Warning, rp, "Ciphertext size misaligned with block structure.");
        }
        if (!k_.content || size < headerLen) return;
        FileVerdict v = verifyChunkedFile(c_.st, *k_.content, physPath, vpath);
        switch (v.state) {
            case FileState::Ok: case FileState::Empty: break;
            case FileState::ShortHeader: c_.add(Severity::Warning, rp, "File truncated (shorter than header)."); break;
            case FileState::HeaderAuth: c_.add(Severity::Critical, rp, "File header corrupted: " + v.detail); break;
            case FileState::ChunkAuth:
                c_.add(Severity::Critical, rp, "Chunk " + std::to_string(v.badChunk) + " authentication failed: " + v.detail);
                break;
            case FileState::Io: c_.add(Severity::Warning, rp, "Content error: the file could not be read."); break;
        }
    }

    Ctx& c_;
    const Keys& k_;
    const size_t nonceLen_;
    int files_ = 0;
};

// Reads gocryptfs.conf into [cfg]; on failure fills [msg].
bool readConfig(Storage& st, Config& cfg, std::string& msg, const std::string& missingMsg) {
    Bytes raw;
    if (!st.readWhole(kConfigName, raw)) { msg = missingMsg; return false; }
    try {
        cfg = Config::parse(std::string(raw.begin(), raw.end()));
    } catch (const Error& e) {
        msg = e.what();
        if (msg.empty()) msg = "Malformed gocryptfs.conf";
        return false;
    }
    return true;
}

CheckResult runCheck(Ctx& c, const Config& cfg, const Credentials& cr) {
    CheckResult res;
    Keys keys;
    std::string msg;
    const Outcome o = acquireKeys(c.st, cfg, cr, /*needKeys*/ false, keys, msg);
    if (o != Outcome::Ok) { res.outcome = o; res.message = msg; return res; }
    if (keys.content) c.log(cr.session ? std::string("Scanning file contents with session key") + kEllipsis : std::string("Password verified ") + kDash + " scanning file contents" + kEllipsis);
    else c.log(std::string("No password given ") + kDash + " checking structure only.");
    Checker ck(c, keys);
    ck.run();
    res.outcome = Outcome::Ok;
    res.report.format = VaultFormat::Gocryptfs;
    res.report.filesScanned = ck.filesScanned();
    res.report.deepScan = keys.content != nullptr;
    res.report.issues = std::move(c.issues);
    return res;
}

// -------------------------------------------------------------------------------------------------- repair --

class Repairer {
public:
    Repairer(Ctx& c, const Keys& k) : c_(c), st_(c.st), k_(k) {}

    int fixed = 0, recovered = 0, removed = 0;

    // False: the root diriv could not even be read, so nothing below it can be judged.
    bool run() {
        if (k_.hasDirIv()) {
            auto iv = ensureIv("", "/");
            if (!iv) return false;
            rootIv_ = *iv;
        } else {
            rootIv_.assign(kDirIvLen, 0);
        }
        c_.log(std::string("Scanning directory tree and repairing corruptions") + kEllipsis);
        repairDirectory("", "");
        return true;
    }

private:
    bool plain() const { return k_.cfg.plaintextNames; }

    Bytes freshIv() {
        Bytes iv(kDirIvLen);
        do { crypto::randomKey(iv.data(), iv.size()); } while (!validIv(iv));
        return iv;
    }

    // The folder's diriv: the existing one if it is valid; a new one only when the file is missing or its content is
    // invalid. A diriv that exists but cannot be read right now is NEVER replaced (the read may just have failed).
    // nullopt = could not be read, leave the folder alone.
    std::optional<Bytes> ensureIv(const std::string& physDir, const std::string& vdir) {
        const std::string p = joinPath(physDir, kDirIvName);
        DirEntry de;
        const bool exists = st_.stat(p, de);
        Bytes b;
        if (exists) {
            if (!st_.readWhole(p, b)) {
                c_.log("Could not read gocryptfs.diriv in " + reportPath(vdir) + "; leaving that folder alone.");
                return std::nullopt;
            }
            if (validIv(b)) return b;
        }
        Bytes fresh = freshIv();
        if (!st_.writeWhole(p, fresh.data(), fresh.size())) {
            c_.log("Could not write gocryptfs.diriv in " + reportPath(vdir) + "; leaving that folder alone.");
            return std::nullopt;
        }
        fixed++;
        c_.log(std::string(exists ? "Replaced the invalid" : "Restored the missing") + " gocryptfs.diriv in " + reportPath(vdir));
        return fresh;
    }

    // /LOST+FOUND at the vault root, created on demand. Its own diriv is created if it has none.
    bool lostFound(std::string& phys, Bytes& iv) {
        if (lfReady_) { phys = lfPhys_; iv = lfIv_; return true; }
        try {
            for (int n = 0; n < 100; n++) {
                const std::string clear = n == 0 ? "LOST+FOUND" : "LOST+FOUND_" + std::to_string(n);
                const std::string physName = plain() ? clear : k_.names->encryptName(clear, rootIv_.data());
                const std::string p = physName;   // the root is the parent
                DirEntry de;
                if (st_.stat(p, de)) {
                    if (!de.isDir) continue;
                } else if (!st_.mkdir(p)) {
                    return false;
                }
                Bytes lfIv(kDirIvLen, 0);
                if (k_.hasDirIv()) {
                    Bytes b;
                    if (st_.readWhole(joinPath(p, kDirIvName), b) && validIv(b)) {
                        lfIv = b;
                    } else {
                        lfIv = freshIv();
                        if (!st_.writeWhole(joinPath(p, kDirIvName), lfIv.data(), lfIv.size())) return false;
                    }
                }
                lfPhys_ = p; lfIv_ = lfIv; lfReady_ = true;
                phys = lfPhys_; iv = lfIv_;
                return true;
            }
        } catch (const Error&) {}
        return false;
    }

    // Moves the entry at [oldPhys] into /LOST+FOUND under the cleartext name [base] (made unique if taken), written
    // the way the vault itself would write it, so it shows up in the vault afterwards. [oldIsLongName]: the old
    // physical name has a .name sidecar that goes away with it. [newPhys] receives the new physical path.
    bool moveAndLocate(const std::string& oldPhys, bool oldIsLongName, const std::string& base, std::string& newPhys) {
        std::string lfPhys; Bytes lfIv;
        if (!lostFound(lfPhys, lfIv)) return false;
        try {
            for (int n = 0; n < 1000; n++) {
                const std::string clear = numberedName(base, n);
                std::string cipher = plain() ? clear : k_.names->encryptName(clear, lfIv.data());
                const bool isLong = !plain() && k_.names->isOverLongNameLimit(cipher);
                const std::string physName = isLong ? k_.names->hashLongName(cipher) : cipher;
                const std::string dest = joinPath(lfPhys, physName);
                if (st_.existsNoFollow(dest)) continue;
                // Sidecar first, then the entry; undone if the move fails, so no orphan sidecar is left behind.
                if (isLong && !st_.writeWhole(dest + kLongNameSuffix, (const uint8_t*)cipher.data(), cipher.size())) return false;
                if (!st_.rename(oldPhys, dest)) {
                    if (isLong) st_.remove(dest + kLongNameSuffix);
                    return false;
                }
                if (oldIsLongName) st_.remove(oldPhys + kLongNameSuffix);
                newPhys = dest;
                return true;
            }
        } catch (const Error&) {}
        return false;
    }
    bool moveToLostFound(const std::string& oldPhys, bool oldIsLongName, const std::string& base) {
        std::string ignored;
        return moveAndLocate(oldPhys, oldIsLongName, base, ignored);
    }

    // First eight characters of a physical name, as a label for rescued entries.
    static std::string tagOf(const std::string& physName) {
        std::string s = physName;
        if (NameCryptor::isLongNameContent(s)) s = s.substr(std::string(kLongNamePrefix).size());
        return s.substr(0, 8);
    }

    void removeEntry(const std::string& physPath, bool isLongName) {
        st_.remove(physPath);
        if (isLongName) st_.remove(physPath + kLongNameSuffix);
        removed++;
    }

    void repairDirectory(const std::string& physDir, const std::string& vdir) {
        if (!visited_.insert(physDir).second) return;
        Bytes iv = rootIv_;
        if (k_.hasDirIv() && !physDir.empty()) {
            auto got = ensureIv(physDir, vdir);
            if (!got) return;
            iv = *got;
        }

        std::vector<DirEntry> ents;
        if (!st_.list(physDir, ents)) return;
        std::unordered_map<std::string, const DirEntry*> byName;
        for (const DirEntry& e : ents) byName[e.name] = &e;

        for (const DirEntry& e : ents) {
            const std::string& physName = e.name;
            if (physDir.empty() && (physName == kConfigName || physName == kConfigBakName)) continue;
            if (e.isSymlink) continue;
            if (!plain()) {
                if (physName == kDirIvName) continue;
                if (NameCryptor::isLongNameFile(physName)) {
                    const std::string base = physName.substr(0, physName.size() - std::string(kLongNameSuffix).size());
                    if (!byName.count(base)) {
                        removeEntry(joinPath(physDir, physName), false);
                        c_.log("Removed orphaned .name sidecar: " + physName + " in " + reportPath(vdir));
                    }
                    continue;
                }
            }

            const bool isLong = !plain() && NameCryptor::isLongNameContent(physName);
            const std::string physPath = joinPath(physDir, physName);
            std::string cipherName = physName, clear = physName;
            bool nameBad = false;
            if (!plain()) {
                if (isLong) {
                    auto side = byName.find(physName + kLongNameSuffix);
                    Bytes raw;
                    if (side == byName.end() || side->second->size > (int64_t)kLongNameFileMax ||
                        !st_.readWhole(joinPath(physDir, side->second->name), raw) || raw.empty() || raw.size() > kLongNameFileMax)
                        nameBad = true;
                    else
                        cipherName.assign(raw.begin(), raw.end());
                }
                if (!nameBad) {
                    try { clear = k_.names->decryptName(cipherName, iv.data()); } catch (const Error&) { nameBad = true; }
                }
            }

            if (e.isDir) {
                if (!nameBad) { repairDirectory(physPath, vchild(vdir, clear)); continue; }
                repairUnreadableDirectory(physPath, physName, isLong, vdir);
            } else {
                repairFile(e, physPath, physName, isLong, nameBad, clear, vdir);
            }
        }
    }

    // A sub-folder whose name does not decrypt. Its own diriv travels with it, so everything inside stays readable.
    void repairUnreadableDirectory(const std::string& physPath, const std::string& physName, bool isLong, const std::string& vdir) {
        std::vector<DirEntry> inner;
        const bool listed = st_.list(physPath, inner);
        bool empty = listed;
        for (const DirEntry& i : inner) if (i.name != kDirIvName) { empty = false; break; }
        if (empty) {
            removeEntry(physPath, isLong);
            c_.log("Removed empty unreadable directory: " + physName + " in " + reportPath(vdir));
            return;
        }
        const std::string label = "recovered_dir_" + tagOf(physName);
        // Find where it will live first, so the recursion below can walk it at its new place.
        std::string lfPhys; Bytes lfIv;
        if (!lostFound(lfPhys, lfIv)) { c_.log("Could not create /LOST+FOUND; left " + physName + " in place."); return; }
        std::string newPhys;
        if (!moveAndLocate(physPath, isLong, label, newPhys)) { c_.log("Could not move " + physName + " into /LOST+FOUND."); return; }
        recovered++;
        c_.log("Rescued directory with damaged name to /LOST+FOUND/" + label);
        repairDirectory(newPhys, "LOST+FOUND/" + label);
    }

    void repairFile(const DirEntry& e, const std::string& physPath, const std::string& physName, bool isLong,
                    bool nameBad, const std::string& clear, const std::string& vdir) {
        const int64_t size = e.size;
        const std::string where = nameBad ? physName : clear;
        if (size < (int64_t)ContentFormat::kHeaderLen) {
            if (nameBad) {
                removeEntry(physPath, isLong);
                c_.log(std::string(size == 0 ? "Removed 0-byte corrupt file" : "Removed truncated file (< 18 bytes) with corrupt name") +
                       " with unreadable name in " + reportPath(vdir));
            } else {
                Bytes header;
                k_.content->newHeader(header);
                if (st_.writeWhole(physPath, header.data(), header.size())) {
                    fixed++;
                    c_.log(std::string(size == 0 ? "Fixed 0-byte file: " : "Reset truncated file (< 18 bytes) to empty: ") +
                           reportPath(vchild(vdir, clear)));
                }
            }
            return;
        }

        uint8_t h[ContentFormat::kHeaderLen];
        {
            FdFile f = st_.openRead(physPath, vchild(vdir, clear));
            if (!f.valid() || f.readAt(h, sizeof h, 0) != (int64_t)sizeof h) {
                c_.log("Could not read the header of " + where + " in " + reportPath(vdir));
                return;
            }
        }
        const int version = (h[0] << 8) | h[1];
        if (version != 2) {
            // Keep the readable name when there is one: it is what lets the user tell what the file was.
            const std::string tag = tagOf(physName);
            const std::string v = std::to_string(version);
            const std::string byTag = "corrupt_version_" + v + "_" + tag + ".bin";
            const std::string byName = nameBad ? byTag : "corrupt_version_" + v + "_" + truncUtf8(clear, 100);
            if (moveToLostFound(physPath, isLong, byName) || (byName != byTag && moveToLostFound(physPath, isLong, byTag))) {
                recovered++;
                c_.log("Rescued file with unsupported version (" + v + ") to /LOST+FOUND: " + where);
            } else {
                c_.log("Could not move " + where + " into /LOST+FOUND.");
            }
            return;
        }
        if (!nameBad) return;
        try {
            k_.content->decodeHeader(h, sizeof h);
        } catch (const Error&) {
            return;   // no usable file id: leave it alone, nothing is gained by moving it
        }
        const std::string label = "recovered_file_" + toHex(h + 2, 4) + ".bin";
        if (moveToLostFound(physPath, isLong, label)) {
            recovered++;
            c_.log("Rescued file with damaged name to /LOST+FOUND/" + label);
        } else {
            c_.log("Could not move " + physName + " into /LOST+FOUND.");
        }
    }

    Ctx& c_;
    Storage& st_;
    const Keys& k_;
    Bytes rootIv_;
    std::unordered_set<std::string> visited_;
    bool lfReady_ = false;
    std::string lfPhys_;
    Bytes lfIv_;
};

}  // namespace

CheckResult checkGocryptfs(Storage& st, const Credentials& cr, const Hooks& hooks) {
    Ctx c(st, hooks);
    c.log(std::string("Reading gocryptfs.conf") + kEllipsis);
    Config cfg;
    std::string msg;
    if (!readConfig(st, cfg, msg, "No gocryptfs.conf found.")) {
        CheckResult r;
        r.outcome = Outcome::InvalidVault;
        r.message = msg;
        return r;
    }
    return runCheck(c, cfg, cr);
}

RepairResult repairGocryptfs(Storage& st, const Credentials& cr, const Hooks& hooks) {
    Ctx c(st, hooks);
    RepairResult res;
    c.log(std::string("Starting gocryptfs Vault Repair & Recovery") + kEllipsis);
    int fixedConfig = 0;

    // 1. gocryptfs.conf, restored from gocryptfs.conf.bak if it is gone.
    DirEntry de;
    if (!st.stat(kConfigName, de)) {
        Bytes bak;
        if (st.stat(kConfigBakName, de) && st.readWhole(kConfigBakName, bak)) {
            c.log(std::string("gocryptfs.conf missing; restoring from gocryptfs.conf.bak") + kEllipsis);
            try {
                (void)Config::parse(std::string(bak.begin(), bak.end()));   // never put a broken file in place of the config
            } catch (const Error& e) {
                res.message = std::string("gocryptfs.conf is missing and gocryptfs.conf.bak is not a valid config: ") + e.what();
                return res;
            }
            if (!st.writeWholeAtomic(kConfigName, bak.data(), bak.size())) {
                res.message = "Could not restore gocryptfs.conf from gocryptfs.conf.bak.";
                return res;
            }
            fixedConfig++;
            c.log("Restored gocryptfs.conf from backup.");
        } else {
            res.message = "Missing gocryptfs.conf and no backup found.";
            return res;
        }
    }
    Config cfg;
    std::string msg;
    if (!readConfig(st, cfg, msg, "Could not read gocryptfs.conf")) { res.message = msg; return res; }

    // 2. Keys (password or the live session's).
    Keys keys;
    const Outcome o = acquireKeys(st, cfg, cr, /*needKeys*/ true, keys, msg);
    if (o != Outcome::Ok) { res.outcome = o; res.message = msg; return res; }
    if (cr.session) c.log("Using active session keys for repair.");

    // 3. Directory tree.
    Repairer rp(c, keys);
    if (!rp.run()) {
        res.message = "The root gocryptfs.diriv exists but cannot be read; nothing was changed below it.";
        return res;
    }

    st.invalidateAll();
    if (cr.session) cr.session->invalidateCache("");

    // 4. Verify with the keys we already have (no second scrypt run).
    c.log(std::string("Re-verifying vault consistency") + kEllipsis);
    Ctx post(st, Hooks{});
    Checker ck(post, keys);
    ck.run();

    res.outcome = Outcome::Ok;
    res.report.format = VaultFormat::Gocryptfs;
    res.report.fixed = rp.fixed + fixedConfig;
    res.report.recovered = rp.recovered;
    res.report.removed = rp.removed;
    res.report.remaining = std::move(post.issues);
    c.log("gocryptfs repair complete: " + std::to_string(res.report.fixed) + " fixed, " + std::to_string(res.report.recovered) +
          " recovered to /LOST+FOUND, " + std::to_string(res.report.removed) + " cleaned up.");
    return res;
}

}  // namespace fv::check::detail
