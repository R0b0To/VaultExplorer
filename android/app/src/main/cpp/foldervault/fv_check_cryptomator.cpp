// Cryptomator (format 7 / 8) Check & Repair. Node classification, name handling and the vault.cryptomator rules
// follow the engine (fv_cryptomator*.cpp) so the tool and the vault agree on what is broken.
#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <memory>
#include <unordered_set>

#include "fv_check_internal.h"
#include "fv_cryptomator.h"
#include "fv_json.h"
#include "fv_util.h"

namespace fv::check::detail {
namespace {

using namespace fv::cryptomator;

constexpr const char* kC9r = ".c9r";
constexpr const char* kC9s = ".c9s";
constexpr const char* kDirFile = "dir.c9r";
constexpr const char* kDirIdBackup = "dirid.c9r";
constexpr const char* kNameFile = "name.c9s";
constexpr const char* kContentsFile = "contents.c9r";
constexpr const char* kSymlinkFile = "symlink.c9r";
constexpr size_t kMaxDirPointer = 1000;   // a dir.c9r holds one directory id (a UUID); anything this long is garbage

// ----------------------------------------------------------------------------------- vault-level preamble --

struct Preamble {
    MasterkeyFile parsed;
    bool hasJwt = false;
    std::string jwt;
};

// masterkey.cryptomator + vault.cryptomator, and the format gate. [msg] is set when this returns false; [issues]
// receives the "no vault.cryptomator, treating this as format 7" warning of a check.
bool readPreamble(Ctx& c, Preamble& pre, bool forRepair, std::string& msg) {
    Storage& st = c.st;
    DirEntry de;
    if (!st.stat(kMasterkeyFile, de) || de.isDir) {
        msg = std::string("No masterkey.cryptomator found ") + kDash + " this doesn't look like a Cryptomator vault.";
        return false;
    }
    Bytes raw;
    if (!st.readWhole(kMasterkeyFile, raw)) { msg = "Could not read masterkey.cryptomator"; return false; }
    try {
        pre.parsed = MasterkeyFile::parse(std::string(raw.begin(), raw.end()));
    } catch (const Error& e) {
        msg = e.what();
        if (msg.empty()) msg = "Malformed masterkey.cryptomator";
        return false;
    }
    c.log("masterkey.cryptomator OK.");

    if (st.stat(kVaultFile, de)) {
        Bytes jwt;
        if (!st.readWhole(kVaultFile, jwt)) { msg = "Could not read vault.cryptomator"; return false; }
        pre.hasJwt = true;
        pre.jwt.assign(jwt.begin(), jwt.end());
        return true;
    }
    // Only a genuine format-7 key file may be treated as a config-less vault; anything else would be scanned with
    // the wrong cipher and layout (the same gate the engine applies when it opens a vault).
    const int v = pre.parsed.version;
    if (v == 7) {
        if (!forRepair) c.add(Severity::Warning, "/", std::string("No vault.cryptomator found ") + kDash + " treating this as a format-7 vault.");
        return true;
    }
    if (v >= 8) {
        msg = std::string("vault.cryptomator is missing. This is a format 8 vault and cannot be ") + (forRepair ? "repaired" : "checked") +
              " without it. If it is stored with a cloud provider, wait for it to finish syncing and try again.";
    } else {
        msg = "Vault format " + std::to_string(v) + " is not supported (only 7 and 8 are). Open it once in Cryptomator to migrate it.";
    }
    return false;
}

// Password-free sanity check of a JWT (three dot-separated base64url parts, the first two JSON objects). The
// signature cannot be verified without the key. Returns the "format" claim, or -1 if it has none.
bool looksLikeJwt(const std::string& jwt, int& format) {
    format = -1;
    size_t d1 = jwt.find('.');
    size_t d2 = d1 == std::string::npos ? std::string::npos : jwt.find('.', d1 + 1);
    if (d2 == std::string::npos || jwt.find('.', d2 + 1) != std::string::npos) return false;
    Bytes header, payload;
    if (!base64Decode(jwt.substr(0, d1), header) || !base64Decode(jwt.substr(d1 + 1, d2 - d1 - 1), payload)) return false;
    try {
        json::Value h = json::parse(std::string(header.begin(), header.end()));
        json::Value p = json::parse(std::string(payload.begin(), payload.end()));
        if (!h.isObject() || !p.isObject()) return false;
        if (const json::Value* f = p.find("format")) format = (int)f->asInt(-1);
    } catch (const Error&) {
        return false;
    }
    return true;
}

bool parseCombo(const std::string& s, Combo& out) {
    if (s == "SIV_GCM") { out = Combo::SivGcm; return true; }
    if (s == "SIV_CTRMAC") { out = Combo::SivCtrMac; return true; }
    return false;
}

// The key material of a run. NameCryptor/ContentFormat keep references to [mk]: never copy or move a Keys.
struct Keys {
    Keys() = default;
    Keys(const Keys&) = delete;
    Keys& operator=(const Keys&) = delete;
    Masterkey mk;
    int shortening = kDefaultShortening;
    bool contentTrusted = false;               // the cipher combo is known and verified
    std::unique_ptr<NameCryptor> names;
    std::unique_ptr<ContentFormat> content;    // null unless contentTrusted
};

// [strict] (repair): the cipher must be verified or the run is refused. Otherwise a vault.cryptomator that does not
// verify becomes a Critical issue and file contents are skipped (names are cipher-independent, so they still scan).
Outcome acquireKeys(Ctx& c, const Preamble& pre, const Credentials& cr, bool strict, Keys& k, std::string& msg) {
    if (cr.session) {
        KeyExport ke = cr.session->exportKeys();
        ExportWipe wipe(ke);
        const Bytes* mk = exportedField(ke, "masterkey");
        const std::string* combo = exportedString(ke, "cipherCombo");
        const std::string* shorten = exportedString(ke, "shorteningThreshold");
        Combo cc;
        if (ke.format != VaultFormat::Cryptomator || !mk || !combo || !parseCombo(*combo, cc)) {
            msg = "The unlocked vault is not a Cryptomator vault.";
            return Outcome::InvalidVault;
        }
        try { k.mk = Masterkey(Secret(*mk)); } catch (const Error& e) { msg = e.what(); return Outcome::InvalidVault; }
        if (shorten) k.shortening = std::atoi(shorten->c_str());
        k.names = std::make_unique<NameCryptor>(k.mk);
        k.content = std::make_unique<ContentFormat>(k.mk, cc);
        k.contentTrusted = true;
        return Outcome::Ok;
    }
    if (!cr.password) {
        if (strict) { msg = "A password is required."; return Outcome::WrongPassword; }
        return Outcome::Ok;
    }
    try {
        k.mk = unlockMasterkeyCompat(pre.parsed, cr.password, cr.passwordLen);
    } catch (const Error& e) {
        msg = e.what();
        return e.code() == Err::WrongPassword ? Outcome::WrongPassword : Outcome::InvalidVault;
    }
    k.names = std::make_unique<NameCryptor>(k.mk);
    Combo combo = Combo::SivCtrMac;   // what a config-less format-7 vault uses
    if (pre.hasJwt) {
        try {
            VaultConfig vc = verifyVaultConfig(pre.jwt, k.mk);
            if (vc.vaultFormat != 8) {
                msg = "Vault format " + std::to_string(vc.vaultFormat) + " is not supported (only 7 and 8 are).";
                return Outcome::InvalidVault;
            }
            if (!parseCombo(vc.cipherCombo, combo)) {
                msg = "Unsupported cipherCombo: " + vc.cipherCombo;
                return Outcome::InvalidVault;
            }
            k.shortening = vc.shorteningThreshold;
            k.contentTrusted = true;
        } catch (const Error& e) {
            if (strict) {
                msg = std::string("vault.cryptomator could not be verified (") + e.what() + "). Refusing to repair with an unknown cipher.";
                return Outcome::InvalidVault;
            }
            c.add(Severity::Critical, reportPath(kVaultFile), e.what()[0] ? e.what() : "vault.cryptomator verification failed.");
        }
    } else {
        k.contentTrusted = true;   // format 7: SIV_CTRMAC by definition
    }
    if (k.contentTrusted) k.content = std::make_unique<ContentFormat>(k.mk, combo);
    return Outcome::Ok;
}

// ----------------------------------------------------------------------------------------- tree reading --

std::string dataPathFor(const NameCryptor& nc, const std::string& dirId) {
    const std::string h = nc.hashDirectoryId(dirId);
    return joinPath(joinPath(kDataDir, h.substr(0, 2)), h.substr(2));
}

std::string trimmed(const Bytes& b) {
    std::string s(b.begin(), b.end());
    const size_t a = s.find_first_not_of(" \t\r\n");
    if (a == std::string::npos) return std::string();
    return s.substr(a, s.find_last_not_of(" \t\r\n") - a + 1);
}

// One physical entry of a directory's backing folder, classified.
struct Entry {
    enum class Type {
        Ignore,    // dir.c9r / dirid.c9r / dot-files: not ours
        Foreign,   // no .c9r / .c9s suffix
        File,
        Dir,
        Symlink,
        Broken,    // a node folder with none of dir.c9r, symlink.c9r (contents.c9r for .c9s)
        NotFolder, // a .c9s entry that is not a folder
    } type = Type::Ignore;
    bool shortened = false;
    bool nameOk = false;
    std::string clear;        // cleartext name when nameOk
    std::string nameError;    // why it did not decrypt
    std::string path;         // physical path of the entry
    std::string contents;     // File: where the encrypted bytes are
    std::string dirFile;      // Dir: path of dir.c9r
    std::string symlinkFile;  // Symlink: path of symlink.c9r
    bool isDir = false;
    int64_t size = 0;
};

Entry classify(Storage& st, const NameCryptor& nc, const std::string& physDir, const DirEntry& e, const std::string& dirId) {
    Entry en;
    const std::string& name = e.name;
    en.isDir = e.isDir;
    en.size = e.size;
    if (name.empty() || name == kDirFile || name == kDirIdBackup || name == kSymlinkFile || name[0] == '.') return en;
    const bool isC9s = endsWith(name, kC9s), isC9r = endsWith(name, kC9r);
    if (!isC9s && !isC9r) { en.type = Entry::Type::Foreign; return en; }
    en.path = joinPath(physDir, name);

    DirEntry probe;
    if (isC9s) {
        en.shortened = true;
        if (!e.isDir) { en.type = Entry::Type::NotFolder; return en; }
        Bytes ln;
        if (!st.readWhole(joinPath(en.path, kNameFile), ln) || ln.empty()) {
            en.nameError = "the node has no readable name.c9s";
        } else {
            std::string raw(ln.begin(), ln.end());
            const size_t e2 = raw.find_last_not_of(std::string(" \r\n\0", 4));
            raw = e2 == std::string::npos ? std::string() : raw.substr(0, e2 + 1);
            const size_t s2 = raw.find_first_not_of(' ');
            raw = s2 == std::string::npos ? std::string() : raw.substr(s2);
            const std::string cipher = endsWith(raw, kC9r) ? raw.substr(0, raw.size() - 4) : raw;
            try { en.clear = nc.decryptFilename(cipher, dirId); en.nameOk = true; } catch (const Error& ex) { en.nameError = ex.what(); }
        }
        if (st.stat(joinPath(en.path, kDirFile), probe)) { en.type = Entry::Type::Dir; en.dirFile = joinPath(en.path, kDirFile); }
        else if (st.stat(joinPath(en.path, kSymlinkFile), probe)) { en.type = Entry::Type::Symlink; en.symlinkFile = joinPath(en.path, kSymlinkFile); }
        else if (st.stat(joinPath(en.path, kContentsFile), probe)) { en.type = Entry::Type::File; en.contents = joinPath(en.path, kContentsFile); en.size = probe.size; }
        else en.type = Entry::Type::Broken;
        return en;
    }

    try { en.clear = nc.decryptFilename(name.substr(0, name.size() - 4), dirId); en.nameOk = true; } catch (const Error& ex) { en.nameError = ex.what(); }
    if (!e.isDir) { en.type = Entry::Type::File; en.contents = en.path; return en; }
    if (st.stat(joinPath(en.path, kDirFile), probe)) { en.type = Entry::Type::Dir; en.dirFile = joinPath(en.path, kDirFile); }
    else if (st.stat(joinPath(en.path, kSymlinkFile), probe)) { en.type = Entry::Type::Symlink; en.symlinkFile = joinPath(en.path, kSymlinkFile); }
    else en.type = Entry::Type::Broken;
    return en;
}

// ---------------------------------------------------------------------------------------------- check --

class Walker {
public:
    Walker(Ctx& c, const Keys& k) : c_(c), k_(k), nc_(*k.names) {}

    int filesScanned() const { return files_; }

    void run() {
        walkDir("", "");
        if (incomplete_) {
            c_.log(std::string("Part of the tree could not be read ") + kDash + " skipping the search for orphaned data folders.");
        } else {
            scanOrphans();
        }
    }

private:
    void walkDir(const std::string& dirId, const std::string& vdir) {
        if (!visited_.insert(dirId).second) {
            c_.add(Severity::Warning, reportPath(vdir), "Directory ID cycle detected. Skipping.");
            return;
        }
        referenced_.insert(nc_.hashDirectoryId(dirId));
        const std::string phys = dataPathFor(nc_, dirId);
        DirEntry de;
        if (!c_.st.stat(phys, de) || !de.isDir) {
            c_.add(Severity::Critical, reportPath(vdir), "Directory storage location missing on disk.");
            return;
        }
        std::vector<DirEntry> ents;
        if (!c_.st.list(phys, ents)) {
            c_.add(Severity::Critical, reportPath(vdir), "This folder cannot be listed.");
            incomplete_ = true;
            return;
        }
        for (const DirEntry& e : ents) {
            Entry en = classify(c_.st, nc_, phys, e, dirId);
            if (en.type == Entry::Type::Ignore) continue;
            if (en.type == Entry::Type::Foreign) {
                DirEntry p;
                if (e.isDir && !c_.st.stat(joinPath(joinPath(phys, e.name), kDirFile), p))
                    c_.add(Severity::Warning, reportPath(vchild(vdir, e.name)), "Foreign directory node is missing dir.c9r.");
                continue;
            }
            const std::string physLabel = vchild(vdir, e.name);
            if (en.type == Entry::Type::NotFolder) {
                c_.add(Severity::Warning, reportPath(physLabel), ".c9s entry should be a folder.");
                continue;
            }
            if (!en.nameOk)
                c_.add(Severity::Critical, reportPath(physLabel), "Filename fails to decrypt: " + en.nameError);
            const std::string childV = vchild(vdir, en.nameOk ? en.clear : e.name);
            switch (en.type) {
                case Entry::Type::Broken:
                    if (en.shortened) c_.add(Severity::Warning, reportPath(childV), "Shortened file node is missing contents.c9r.");
                    else c_.add(Severity::Critical, reportPath(childV), "Directory node is missing dir.c9r.");
                    break;
                case Entry::Type::Dir: descend(en, childV); break;
                case Entry::Type::Symlink: checkSymlink(en, childV); break;
                case Entry::Type::File: files_++; checkFile(en.contents, childV, /*isLink*/ false); break;
                default: break;
            }
        }
    }

    void descend(const Entry& en, const std::string& childV) {
        DirEntry ptr;
        c_.st.stat(en.dirFile, ptr);
        Bytes b;
        if (!c_.st.readWhole(en.dirFile, b)) {
            c_.add(Severity::Critical, reportPath(vchild(childV, kDirFile)), "dir.c9r cannot be read.");
            incomplete_ = true;
            return;
        }
        const std::string id = trimmed(b);
        if (b.empty() || id.empty()) {
            c_.add(Severity::Critical, reportPath(vchild(childV, kDirFile)), std::string("dir.c9r is empty ") + kDash + " the directory's identity is lost.");
            incomplete_ = true;
            return;
        }
        if (b.size() > kMaxDirPointer) {
            c_.add(Severity::Critical, reportPath(vchild(childV, kDirFile)),
                   "dir.c9r is " + std::to_string(b.size()) + " bytes, over Cryptomator's limit.");
            incomplete_ = true;
            return;
        }
        walkDir(id, childV);
    }

    void checkSymlink(const Entry& en, const std::string& childV) {
        if (!k_.contentTrusted) return;
        FileVerdict v = verifyChunkedFile(c_.st, *k_.content, en.symlinkFile, childV);
        const std::string rp = reportPath(childV);
        switch (v.state) {
            case FileState::Ok: break;
            case FileState::Empty: c_.add(Severity::Critical, rp, "The symbolic link's target file is empty."); break;
            case FileState::ShortHeader: c_.add(Severity::Warning, rp, std::string("Symbolic link target shorter than header ") + kDash + " truncated."); break;
            case FileState::HeaderAuth: c_.add(Severity::Critical, rp, "Symbolic link target fails authentication."); break;
            case FileState::ChunkAuth: c_.add(Severity::Critical, rp, "Symbolic link target fails authentication."); break;
            case FileState::Io: c_.add(Severity::Warning, rp, "Error: the symbolic link could not be read."); break;
        }
    }

    void checkFile(const std::string& physPath, const std::string& childV, bool) {
        if (!k_.contentTrusted) return;
        FileVerdict v = verifyChunkedFile(c_.st, *k_.content, physPath, childV);
        const std::string rp = reportPath(childV);
        switch (v.state) {
            case FileState::Ok: case FileState::Empty: break;   // a zero-byte file is left alone, as before
            case FileState::ShortHeader: c_.add(Severity::Warning, rp, std::string("File shorter than header ") + kDash + " truncated."); break;
            case FileState::HeaderAuth: c_.add(Severity::Critical, rp, "File header fails authentication."); break;
            case FileState::ChunkAuth: c_.add(Severity::Critical, rp, "Chunk " + std::to_string(v.badChunk) + " authentication failed."); break;
            case FileState::Io: c_.add(Severity::Warning, rp, "Error: the file could not be read."); break;
        }
    }

    // Backing folders under d/ that no directory points to.
    void scanOrphans() {
        std::vector<DirEntry> l1;
        if (!c_.st.list(kDataDir, l1)) return;
        for (const DirEntry& a : l1) {
            if (!a.isDir || a.name.size() != 2) continue;
            std::vector<DirEntry> l2;
            if (!c_.st.list(joinPath(kDataDir, a.name), l2)) continue;
            for (const DirEntry& b : l2) {
                if (!b.isDir || b.name.size() != 30) continue;
                std::string full = a.name + b.name;
                for (char& ch : full) ch = (char)std::toupper((unsigned char)ch);
                if (referenced_.count(full)) continue;
                const std::string phys = joinPath(joinPath(kDataDir, a.name), b.name);
                std::vector<DirEntry> inner;
                bool hasContent = false;
                if (c_.st.list(phys, inner))
                    for (const DirEntry& i : inner)
                        if (i.name != kDirIdBackup && i.name != kDirFile && i.name != kSymlinkFile) { hasContent = true; break; }
                c_.add(hasContent ? Severity::Warning : Severity::Info, reportPath(phys),
                       hasContent ? "Data folder is not referenced by any directory (orphaned)." : "Empty orphaned data folder.");
            }
        }
    }

    Ctx& c_;
    const Keys& k_;
    const NameCryptor& nc_;
    int files_ = 0;
    bool incomplete_ = false;
    std::unordered_set<std::string> visited_, referenced_;
};

// Counts the backing folders (d/xx/yyyy...) of a vault without any key: all a password-free check can see.
int countBackingFolders(Storage& st) {
    int n = 0;
    std::vector<DirEntry> l1;
    if (!st.list(kDataDir, l1)) return 0;
    for (const DirEntry& a : l1) {
        if (!a.isDir || a.name.size() != 2) continue;
        std::vector<DirEntry> l2;
        if (!st.list(joinPath(kDataDir, a.name), l2)) continue;
        for (const DirEntry& b : l2) if (b.isDir && b.name.size() == 30) n++;
    }
    return n;
}

// ------------------------------------------------------------------------------------------------ repair --

class Repairer {
public:
    Repairer(Ctx& c, const Keys& k) : c_(c), st_(c.st), k_(k), nc_(*k.names) {}

    int fixed = 0, recovered = 0, removed = 0;

    bool run() {
        std::string rootPath;
        if (!ensureDataFolder("", rootPath)) return false;
        c_.log(std::string("Inspecting directory hierarchy") + kEllipsis);
        repairDir("", "");
        if (incomplete_) {
            c_.log(std::string("Part of the tree could not be read ") + kDash + " not touching unreferenced data folders.");
        } else {
            c_.log(std::string("Checking for orphaned data folders in storage") + kEllipsis);
            sweepOrphans();
        }
        return true;
    }

private:
    // ---- small encrypted files (dirid.c9r) -------------------------------------------------------------------
    bool writeDirIdBackup(const std::string& folder, const std::string& ownId) {
        const ContentFormat& fmt = *k_.content;
        Bytes file;
        auto key = fmt.newHeader(file);
        Bytes enc(fmt.encryptedSize(ownId.size()));
        fmt.encrypt(*key, 0, (const uint8_t*)ownId.data(), ownId.size(), enc.data());
        file.insert(file.end(), enc.begin(), enc.end());
        return st_.writeWhole(joinPath(folder, kDirIdBackup), file.data(), file.size());
    }

    bool readDirIdBackup(const std::string& folder, std::string& out) {
        const ContentFormat& fmt = *k_.content;
        Bytes enc;
        if (!st_.readWhole(joinPath(folder, kDirIdBackup), enc)) return false;
        const size_t hdr = fmt.headerSize();
        if (enc.size() < hdr) return false;
        try {
            const size_t body = enc.size() - hdr;
            const size_t plainLen = fmt.decryptedSize(body);
            if (plainLen == 0 || plainLen > kMaxDirPointer) return false;
            auto key = fmt.decodeHeader(enc.data(), enc.size());
            Bytes plain(plainLen);
            fmt.decrypt(*key, 0, enc.data() + hdr, body, plain.data());
            out.assign(plain.begin(), plain.end());
            return true;
        } catch (const Error&) {
            return false;
        }
    }

    // ---- folders ---------------------------------------------------------------------------------------------
    // Creates d/xx/yyyy for [dirId] (and its dirid.c9r, except for the root) if it is not there.
    bool ensureDataFolder(const std::string& dirId, std::string& path) {
        path = dataPathFor(nc_, dirId);
        const std::string lvl1 = parentOf(path);
        DirEntry de;
        if (st_.stat(path, de) && de.isDir) return true;
        if (!st_.mkdir(kDataDir) || !st_.mkdir(lvl1) || !st_.mkdir(path)) return false;
        if (!dirId.empty()) writeDirIdBackup(path, dirId);   // best effort: lets a later repair adopt the folder by itself
        return true;
    }

    // A directory node [clear].c9r under [parentPhys] whose dir.c9r points at [childId]. The name is made unique.
    bool createDirNode(const std::string& parentPhys, const std::string& parentId, const std::string& clear,
                       const std::string& childId, std::string* usedName = nullptr) {
        try {
            for (int n = 0; n < 1000; n++) {
                const std::string name = numberedName(clear, n);
                const std::string full = nc_.encryptFilename(name, parentId) + kC9r;
                if ((int)full.size() > k_.shortening) return false;   // never needed for the short names used here
                const std::string node = joinPath(parentPhys, full);
                if (st_.existsNoFollow(node)) continue;
                if (!st_.mkdir(node)) return false;
                if (!st_.writeWhole(joinPath(node, kDirFile), (const uint8_t*)childId.data(), childId.size())) {
                    st_.remove(node);
                    return false;
                }
                if (usedName) *usedName = name;
                return true;
            }
        } catch (const Error&) {}
        return false;
    }

    // /LOST+FOUND in the root directory: an existing one, or a new one.
    bool lostFound(std::string& id, std::string& phys) {
        if (lfReady_) { id = lfId_; phys = lfPhys_; return true; }
        const std::string rootPhys = dataPathFor(nc_, "");
        std::vector<DirEntry> ents;
        if (st_.list(rootPhys, ents)) {
            for (const DirEntry& e : ents) {
                if (!e.isDir || !endsWith(e.name, kC9r)) continue;
                try {
                    if (nc_.decryptFilename(e.name.substr(0, e.name.size() - 4), "") != "LOST+FOUND") continue;
                } catch (const Error&) { continue; }
                Bytes b;
                if (!st_.readWhole(joinPath(joinPath(rootPhys, e.name), kDirFile), b)) continue;
                const std::string existing = trimmed(b);
                if (existing.empty() || b.size() > kMaxDirPointer) continue;
                std::string p;
                if (!ensureDataFolder(existing, p)) continue;
                lfId_ = existing; lfPhys_ = p; lfReady_ = true;
                referenced_.insert(nc_.hashDirectoryId(lfId_));   // /LOST+FOUND itself is never an orphan
                id = lfId_; phys = lfPhys_;
                return true;
            }
        }
        const std::string newId = newUuid();
        std::string p;
        if (!createDirNode(rootPhys, "", "LOST+FOUND", newId) || !ensureDataFolder(newId, p)) return false;
        lfId_ = newId; lfPhys_ = p; lfReady_ = true;
        referenced_.insert(nc_.hashDirectoryId(lfId_));   // created mid-walk, so the walk never saw it
        id = lfId_; phys = lfPhys_;
        return true;
    }

    // Moves the encrypted file [oldPath] into /LOST+FOUND as a file called [clear] (made unique).
    bool moveFileToLostFound(const std::string& oldPath, const std::string& clear) {
        std::string id, phys;
        if (!lostFound(id, phys)) return false;
        try {
            for (int n = 0; n < 1000; n++) {
                const std::string full = nc_.encryptFilename(numberedName(clear, n), id) + kC9r;
                if ((int)full.size() > k_.shortening) return false;
                const std::string dest = joinPath(phys, full);
                if (st_.existsNoFollow(dest)) continue;
                return st_.rename(oldPath, dest);
            }
        } catch (const Error&) {}
        return false;
    }

    // ---- the walk --------------------------------------------------------------------------------------------
    void repairDir(const std::string& dirId, const std::string& vdir) {
        if (!visited_.insert(dirId).second) return;
        referenced_.insert(nc_.hashDirectoryId(dirId));
        const std::string phys = dataPathFor(nc_, dirId);
        DirEntry de;
        if (!st_.stat(phys, de) || !de.isDir) {
            std::string made;
            if (!ensureDataFolder(dirId, made)) { incomplete_ = true; return; }
            fixed++;
            c_.log("Created the missing storage folder of " + reportPath(vdir));
        }
        std::vector<DirEntry> ents;
        if (!st_.list(phys, ents)) { incomplete_ = true; return; }

        for (const DirEntry& e : ents) {
            Entry en = classify(st_, nc_, phys, e, dirId);
            switch (en.type) {
                case Entry::Type::Dir: repairDirNode(en, e.name, dirId, vdir); break;
                case Entry::Type::File: repairFileNode(en, e.name, vdir); break;
                case Entry::Type::Broken: repairBrokenNode(en, e.name, vdir); break;
                default: break;   // ignored, foreign, symlinks and stray .c9s files are left exactly as they are
            }
        }
    }

    void repairDirNode(const Entry& en, const std::string& physName, const std::string& /*parentId*/, const std::string& vdir) {
        Bytes b;
        if (!st_.readWhole(en.dirFile, b)) {
            c_.log("Could not read dir.c9r in " + reportPath(vchild(vdir, physName)) + "; left alone.");
            incomplete_ = true;
            return;
        }
        std::string id = trimmed(b);
        if (id.empty() || b.size() > kMaxDirPointer) {
            const std::string fresh = newUuid();
            std::string made;
            if (!ensureDataFolder(fresh, made) || !st_.writeWhole(en.dirFile, (const uint8_t*)fresh.data(), fresh.size())) {
                c_.log("Could not repair dir.c9r in " + reportPath(vchild(vdir, physName)));
                incomplete_ = true;
                return;
            }
            id = fresh;
            fixed++;
            c_.log("Fixed corrupt dir.c9r in " + reportPath(vchild(vdir, physName)));
        }
        if (en.nameOk) {
            repairDir(id, vchild(vdir, en.clear));
            return;
        }
        // The directory's name does not decrypt: give it a readable name under /LOST+FOUND (same dir.c9r, so the
        // whole subtree comes along) and drop the old node.
        std::string lfId, lfPhys, used;
        const std::string label = "recovered_dir_" + id.substr(0, 8);
        if (!lostFound(lfId, lfPhys) || !createDirNode(lfPhys, lfId, label, id, &used)) {
            c_.log("Could not move " + reportPath(vchild(vdir, physName)) + " into /LOST+FOUND; left alone.");
            repairDir(id, vchild(vdir, physName));
            return;
        }
        st_.remove(en.path);
        recovered++;
        c_.log("Recovered directory with corrupted name to /LOST+FOUND/" + used);
        repairDir(id, "LOST+FOUND/" + used);
    }

    void repairFileNode(const Entry& en, const std::string& physName, const std::string& vdir) {
        if (en.nameOk) return;
        const std::string tag = physName.substr(0, 8);
        if (en.shortened) {
            // A shortened file node: the contents file is the file, its wrapper carried the unreadable name.
            if (moveFileToLostFound(en.contents, "recovered_file_" + tag + ".bin")) {
                st_.remove(en.path);
                recovered++;
                c_.log("Rescued shortened file with corrupted name to /LOST+FOUND");
            } else {
                c_.log("Could not move " + reportPath(vchild(vdir, physName)) + " into /LOST+FOUND; left alone.");
            }
            return;
        }
        // A .c9r file whose name does not decrypt: worth keeping only if its header authenticates.
        const ContentFormat& fmt = *k_.content;
        bool validHeader = false;
        {
            FdFile f = st_.openRead(en.path, vchild(vdir, physName));
            Bytes hb(fmt.headerSize());
            if (f.valid() && f.readAt(hb.data(), hb.size(), 0) == (int64_t)hb.size()) {
                try { validHeader = fmt.decodeHeader(hb.data(), hb.size()) != nullptr; } catch (const Error&) {}
            }
        }
        if (validHeader) {
            const std::string label = "recovered_file_" + tag + ".bin";
            if (moveFileToLostFound(en.path, label)) {
                recovered++;
                c_.log("Recovered file with damaged filename to /LOST+FOUND/" + label);
            } else {
                c_.log("Could not move " + reportPath(vchild(vdir, physName)) + " into /LOST+FOUND; left alone.");
            }
        } else if (en.size == 0) {
            st_.remove(en.path);
            removed++;
            c_.log("Removed 0-byte corrupt file: " + physName);
        }
    }

    void repairBrokenNode(const Entry& en, const std::string& physName, const std::string& vdir) {
        std::vector<DirEntry> inner;
        if (!st_.list(en.path, inner)) return;
        bool hasContents = false, hasOther = false;
        for (const DirEntry& i : inner) {
            if (i.name == kContentsFile) hasContents = true;
            else if (i.name != kNameFile) hasOther = true;
        }
        if (hasContents) return;   // a file node the engine does not recognise; do not guess
        if (!hasOther) {
            st_.remove(en.path);
            removed++;
            c_.log("Removed empty invalid directory node: " + reportPath(vchild(vdir, physName)));
            return;
        }
        // The node holds something but has lost its dir.c9r: give it a new, empty identity. (If the old directory's
        // storage folder still exists it is picked up as an orphan below.)
        const std::string fresh = newUuid();
        std::string made;
        if (!ensureDataFolder(fresh, made) || !st_.writeWhole(joinPath(en.path, kDirFile), (const uint8_t*)fresh.data(), fresh.size())) {
            c_.log("Could not restore dir.c9r in " + reportPath(vchild(vdir, physName)));
            return;
        }
        fixed++;
        c_.log("Restored missing dir.c9r for directory: " + reportPath(vchild(vdir, physName)));
        repairDir(fresh, vchild(vdir, en.nameOk ? en.clear : physName));
    }

    // Backing folders no directory points to. One whose dirid.c9r proves what directory it was is hooked into
    // /LOST+FOUND with all its names intact; an empty one is deleted; anything else is left where it is (its names
    // are bound to a directory id we cannot recover, so moving it would only hide it).
    void sweepOrphans() {
        std::vector<DirEntry> l1;
        if (!st_.list(kDataDir, l1)) return;
        for (const DirEntry& a : l1) {
            if (!a.isDir || a.name.size() != 2) continue;
            std::vector<DirEntry> l2;
            if (!st_.list(joinPath(kDataDir, a.name), l2)) continue;
            for (const DirEntry& b : l2) {
                if (!b.isDir || b.name.size() != 30) continue;
                std::string full = a.name + b.name;
                for (char& ch : full) ch = (char)std::toupper((unsigned char)ch);
                if (referenced_.count(full)) continue;   // adopting an earlier orphan may have reached this one
                const std::string phys = joinPath(joinPath(kDataDir, a.name), b.name);
                std::vector<DirEntry> inner;
                if (!st_.list(phys, inner)) continue;
                bool hasContent = false;
                for (const DirEntry& i : inner)
                    if (i.name != kDirIdBackup && i.name != kDirFile && i.name != kSymlinkFile) { hasContent = true; break; }
                if (!hasContent) {
                    st_.remove(phys);
                    removed++;
                    c_.log("Removed empty orphaned data folder " + phys);
                    continue;
                }
                std::string id;
                if (!readDirIdBackup(phys, id) || nc_.hashDirectoryId(id) != full) {
                    c_.log("Orphaned data folder " + phys + " has no usable dirid.c9r; left in place.");
                    continue;
                }
                std::string lfId, lfPhys, used;
                if (!lostFound(lfId, lfPhys) || !createDirNode(lfPhys, lfId, "orphan_data_" + full.substr(0, 6), id, &used)) {
                    c_.log("Could not adopt orphaned data folder " + phys + "; left in place.");
                    continue;
                }
                recovered++;
                c_.log("Adopted orphaned storage directory into /LOST+FOUND/" + used);
                repairDir(id, "LOST+FOUND/" + used);
            }
        }
    }

    Ctx& c_;
    Storage& st_;
    const Keys& k_;
    const NameCryptor& nc_;
    std::unordered_set<std::string> visited_, referenced_;
    bool incomplete_ = false;
    bool lfReady_ = false;
    std::string lfId_, lfPhys_;
};

}  // namespace

CheckResult checkCryptomator(Storage& st, const Credentials& cr, const Hooks& hooks) {
    Ctx c(st, hooks);
    CheckResult res;
    c.log(std::string("Reading masterkey.cryptomator") + kEllipsis);
    Preamble pre;
    std::string msg;
    if (!readPreamble(c, pre, /*forRepair*/ false, msg)) { res.message = msg; return res; }
    if (pre.hasJwt) {
        int format = -1;
        if (!looksLikeJwt(pre.jwt, format)) { res.message = "Malformed vault.cryptomator"; return res; }
        c.log("vault.cryptomator OK (format " + (format < 0 ? std::string("?") : std::to_string(format)) +
              ", signature unverified until password given).");
    }
    DirEntry de;
    if (!st.stat(kDataDir, de) || !de.isDir) { res.message = "Vault is missing its 'd' data directory."; return res; }

    res.report.format = VaultFormat::Cryptomator;
    if (!cr.session && !cr.password) {
        c.log("No password given " + std::string(kDash) + " checking the physical storage layout only.");
        res.outcome = Outcome::Ok;
        res.report.filesScanned = countBackingFolders(st);
        res.report.deepScan = false;
        res.report.issues = std::move(c.issues);
        return res;
    }

    auto keys = std::make_unique<Keys>();
    const Outcome o = acquireKeys(c, pre, cr, /*strict*/ false, *keys, msg);
    if (o != Outcome::Ok) { res.outcome = o; res.message = msg; return res; }
    c.log(cr.session ? std::string("Vault is already unlocked ") + kDash + " scanning directory tree with session key" + kEllipsis
                     : std::string("Password verified ") + kDash + " walking directory tree" + kEllipsis);
    Walker w(c, *keys);
    w.run();
    c.log("Scan complete: " + std::to_string(w.filesScanned()) + " file(s) scanned, " + std::to_string(c.issues.size()) + " issue(s) found.");
    res.outcome = Outcome::Ok;
    res.report.filesScanned = w.filesScanned();
    res.report.deepScan = keys->contentTrusted;
    res.report.issues = std::move(c.issues);
    return res;
}

RepairResult repairCryptomator(Storage& st, const Credentials& cr, const Hooks& hooks) {
    Ctx c(st, hooks);
    RepairResult res;
    c.log(std::string("Starting Cryptomator Vault Repair & Recovery") + kEllipsis);
    Preamble pre;
    std::string msg;
    if (!readPreamble(c, pre, /*forRepair*/ true, msg)) { res.message = msg; return res; }

    auto keys = std::make_unique<Keys>();
    const Outcome o = acquireKeys(c, pre, cr, /*strict*/ true, *keys, msg);
    if (o != Outcome::Ok) { res.outcome = o; res.message = msg; return res; }
    if (cr.session) c.log("Using active session key for recovery.");
    DirEntry de;
    if (!st.stat(kDataDir, de) || !de.isDir) { res.message = "Vault missing 'd' data directory."; return res; }

    Repairer rp(c, *keys);
    if (!rp.run()) { res.message = "Could not create the vault's root storage folder."; return res; }

    st.invalidateAll();
    if (cr.session) cr.session->invalidateCache("");

    c.log(std::string("Re-verifying vault after repairs") + kEllipsis);
    Ctx post(st, Hooks{});
    Walker w(post, *keys);
    w.run();

    res.outcome = Outcome::Ok;
    res.report.format = VaultFormat::Cryptomator;
    res.report.fixed = rp.fixed;
    res.report.recovered = rp.recovered;
    res.report.removed = rp.removed;
    res.report.remaining = std::move(post.issues);
    c.log("Repair complete: " + std::to_string(rp.fixed) + " fixed, " + std::to_string(rp.recovered) +
          " recovered to /LOST+FOUND, " + std::to_string(rp.removed) + " cleaned up.");
    return res;
}

}  // namespace fv::check::detail
