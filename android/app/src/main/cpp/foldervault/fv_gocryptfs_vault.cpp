// gocryptfs vault: directory tree resolution, the session (fv::Vault) and the
// open / create / change-password entry points.
#include <algorithm>
#include <chrono>
#include <map>
#include <mutex>
#include <shared_mutex>
#include <unordered_map>

#include "fv_gocryptfs.h"
#include "fv_util.h"

namespace fv {
namespace gocryptfs {
namespace {

constexpr const char* TAG = "GocryptfsSession";

struct Node {
    bool isDir = false;
    std::string name;       // cleartext
    std::string physName;   // name on storage (cipher name or long-name hash)
    std::string physPath;   // path of that node relative to the vault root
    int64_t size = 0;       // physical size
    int64_t mtimeMs = 0;
};

// Resolves cleartext paths to physical paths. Caches are guarded by mu_ (the
// engine calls resolve() concurrently, without the namespace lock).
//
// Like gocryptfs' own dircache (fusefrontend/dircache.go), the folder and
// diriv caches are dropped periodically (kCacheTtl) so a ciphertext tree that
// another gocryptfs client or a sync tool changes under us is picked up, and
// listing a folder always re-reads that folder's gocryptfs.diriv (gocryptfs does
// the same on every opendir).
class Tree {
public:
    static constexpr std::chrono::seconds kCacheTtl{60};

    Tree(Storage& st, const NameCryptor& nc, bool hasDirIv)
        : st_(st), nc_(nc), hasDirIv_(hasDirIv), lastClear_(std::chrono::steady_clock::now()) {}

    bool hasDirIV() const { return hasDirIv_; }

    // gocryptfs keeps its config in the root of the cipher directory and hides it from the plaintext view.
    // (VaultExplorer's Check & Repair backup of it is hidden too.)
    static bool isConfigFile(const std::string& vdir, const std::string& physName) {
        return vdir.empty() && (physName == kConfigName || physName == kConfigBakName);
    }

    std::string physicalFolderFor(const std::string& vdirIn) {
        std::string vdir = normalizePath(vdirIn);
        if (vdir.empty()) return std::string();
        if (auto c = cachedFolder(vdir)) return *c;
        std::string physical, virt;
        for (const std::string& seg : splitSegments(vdir)) {
            std::string next = joinPath(virt, seg);
            if (auto c = cachedFolder(next)) { physical = *c; virt = next; continue; }
            std::optional<Node> child = findChild(virt, physical, seg, /*wantDir*/ true);
            if (!child || !child->isDir) throw Error(Err::NotFound, "Folder not found: " + next);
            physical = child->physPath;
            virt = next;
            cacheFolder(virt, physical);
        }
        return physical;
    }

    // A valid gocryptfs.diriv is exactly 16 bytes and not all zero (nametransform.fdReadDirIV: an all-zero IV
    // would silently turn the folder into a deterministic one).
    static bool validDirIv(const Bytes& iv) {
        if (iv.size() != kDirIvLen) return false;
        for (uint8_t b : iv) if (b) return true;
        return false;
    }

    // [fresh] bypasses the cache and re-reads the file.
    Bytes dirivFor(const std::string& vdir, const std::string& physicalFolder, bool fresh = false) {
        if (!hasDirIv_) return Bytes(kDirIvLen, 0);   // -deterministic-names: ReadDirIVAt returns the null IV
        if (!fresh) {
            std::lock_guard<std::mutex> g(mu_);
            expireIfDue();
            auto it = diriv_.find(vdir);
            if (it != diriv_.end()) return it->second;
        }
        Bytes iv;
        const std::string p = joinPath(physicalFolder, kDirIvName);
        if (!st_.readWhole(p, iv) || !validDirIv(iv)) {
            st_.invalidate(physicalFolder);   // a stale listing may have hidden it
            if (!st_.readWhole(p, iv) || !validDirIv(iv))
                throw Error(Err::Io, "Missing or invalid gocryptfs.diriv in " + (physicalFolder.empty() ? std::string("<root>") : physicalFolder));
        }
        std::lock_guard<std::mutex> g(mu_);
        diriv_[vdir] = iv;
        return iv;
    }
    Bytes dirivFor(const std::string& vdir) { return dirivFor(vdir, physicalFolderFor(vdir)); }

    Bytes createDirIv(const std::string& vdir, const std::string& physicalFolder) {
        Bytes iv(kDirIvLen);
        do { crypto::randomFast(iv.data(), iv.size()); } while (!validDirIv(iv));
        if (!st_.writeWhole(joinPath(physicalFolder, kDirIvName), iv.data(), iv.size()))
            throw Error(Err::Io, "Could not write gocryptfs.diriv");
        std::lock_guard<std::mutex> g(mu_);
        diriv_[vdir] = iv;
        return iv;
    }

    // Turns one physical directory entry into a cleartext Node. False = the entry is not part of the cleartext
    // view: gocryptfs' own files, long-name sidecars, and names that do not decrypt (gocryptfs skips those too).
    bool decodeEntry(const std::string& vdir, const std::string& physical, const Bytes& iv, const DirEntry& e,
                     const std::unordered_map<std::string, const DirEntry*>& byName, Node& out) {
        const std::string& name = e.name;
        if (isConfigFile(vdir, name)) return false;
        // gocryptfs stores a symlink as a symlink (the target encrypted, or in clear with plaintext names).
        // Android's storage model has none, so they stay in the ciphertext untouched and out of the view.
        if (e.isSymlink) return false;
        std::string clear;
        if (nc_.plaintextNames()) {
            // Plaintext names: the entry names are the names. None of gocryptfs' special files exist
            // (no diriv, no long-name files), so a user file may be called anything.
            if (!NameCryptor::isRepresentableName(name)) return false;
            clear = name;
        } else {
            if (name == kDirIvName || NameCryptor::isLongNameFile(name)) return false;
            std::string cipherName = name;
            if (NameCryptor::isLongNameContent(name)) {
                auto side = byName.find(name + kLongNameSuffix);
                if (side == byName.end()) return false;
                if (side->second->size > (int64_t)kLongNameFileMax) return false;
                Bytes raw;
                if (!st_.readWhole(joinPath(physical, side->second->name), raw)) return false;
                if (raw.empty() || raw.size() > kLongNameFileMax) return false;   // ReadLongNameAt's limits
                cipherName.assign(raw.begin(), raw.end());
            }
            try { clear = nc_.decryptName(cipherName, iv.data()); } catch (const Error&) { return false; }
        }
        out = Node();
        out.isDir = e.isDir; out.name = clear; out.physName = name;
        out.physPath = joinPath(physical, name);
        out.size = e.size; out.mtimeMs = e.mtimeMs;
        return true;
    }

    std::vector<Node> list(const std::string& vdirIn) {
        std::string vdir = normalizePath(vdirIn);
        std::string physical = physicalFolderFor(vdir);
        Bytes iv = nc_.plaintextNames() ? Bytes() : dirivFor(vdir, physical, /*fresh*/ true);
        std::vector<DirEntry> ents;
        if (!st_.list(physical, ents)) throw Error(Err::NotFound, "Folder not found: " + vdir);
        std::unordered_map<std::string, const DirEntry*> byName;
        if (!nc_.plaintextNames()) for (auto& e : ents) byName[e.name] = &e;
        std::vector<Node> out;
        for (auto& e : ents) {
            Node n;
            if (!decodeEntry(vdir, physical, iv, e, byName, n)) continue;
            if (n.isDir) cacheFolder(joinPath(vdir, n.name), n.physPath);
            out.push_back(std::move(n));
        }
        return out;
    }

    std::optional<Node> resolve(const std::string& vpathIn) {
        std::string vpath = normalizePath(vpathIn);
        if (vpath.empty()) return std::nullopt;
        std::string parent = parentOf(vpath);
        std::string physParent;
        try { physParent = physicalFolderFor(parent); } catch (const Error&) { return std::nullopt; }
        return findChild(parent, physParent, nameOf(vpath), /*wantDir*/ false);
    }

    void removeFolder(const std::string& vdirIn) {
        std::string vdir = normalizePath(vdirIn);
        std::lock_guard<std::mutex> g(mu_);
        std::string prefix = vdir + "/";
        for (auto it = folders_.begin(); it != folders_.end();) {
            if (it->first == vdir || startsWith(it->first, prefix.c_str())) it = folders_.erase(it); else ++it;
        }
        for (auto it = diriv_.begin(); it != diriv_.end();) {
            if (it->first == vdir || startsWith(it->first, prefix.c_str())) it = diriv_.erase(it); else ++it;
        }
    }
    // Housekeeping after our own writes: only the storage listing of [vdir] is stale.
    void invalidate(const std::string& vdir) {
        st_.invalidate(physicalOfCachedFolder(normalizePath(vdir)));
    }
    // The user asked for a fresh look at [vdir] (pull to refresh): forget everything cached about the folder
    // chain too -- a sync tool may have replaced a diriv or renamed a parent -- and re-read the listing.
    void invalidateFolder(const std::string& vdirIn) {
        std::string vdir = normalizePath(vdirIn);
        std::string oldPhys = physicalOfCachedFolder(vdir);
        {
            std::lock_guard<std::mutex> g(mu_);
            folders_.clear();
            diriv_.clear();
            lastClear_ = std::chrono::steady_clock::now();
        }
        st_.invalidate(oldPhys);
        std::string fresh = physicalOfCachedFolder(vdir);
        if (fresh != oldPhys) st_.invalidate(fresh);
    }
    void invalidateAll() {
        {
            std::lock_guard<std::mutex> g(mu_);
            folders_.clear();
            diriv_.clear();
            lastClear_ = std::chrono::steady_clock::now();
        }
        st_.invalidateAll();
    }

    // Physical child lookup by cleartext name: direct stat of the expected
    // encrypted name first (what gocryptfs does), then -- as a fallback for
    // stale/odd listings -- a scan.
    std::optional<Node> findChild(const std::string& vparent, const std::string& physParent,
                                  const std::string& name, bool wantDir) {
        (void)wantDir;
        // With plaintext names a user file could be called "gocryptfs.conf"; gocryptfs refuses (EPERM) to
        // touch the config through the plaintext view.
        if (nc_.plaintextNames() && isConfigFile(vparent, name)) return std::nullopt;
        Bytes iv = nc_.plaintextNames() ? Bytes() : dirivFor(vparent, physParent);
        std::string cipher;
        try { cipher = nc_.encryptName(name, iv.data()); } catch (const Error&) { return std::nullopt; }
        std::string physName = nc_.isOverLongNameLimit(cipher) ? nc_.hashLongName(cipher) : cipher;
        DirEntry de;
        if (st_.stat(joinPath(physParent, physName), de)) {
            if (de.isSymlink) return std::nullopt;   // see decodeEntry
            Node n;
            n.isDir = de.isDir; n.name = name; n.physName = physName;
            n.physPath = joinPath(physParent, physName);
            n.size = de.size; n.mtimeMs = de.mtimeMs;
            return n;
        }
        std::vector<DirEntry> ents;
        if (!st_.list(physParent, ents)) return std::nullopt;
        std::unordered_map<std::string, const DirEntry*> byName;
        if (!nc_.plaintextNames()) for (auto& e : ents) byName[e.name] = &e;
        for (auto& e : ents) {
            Node n;
            if (!decodeEntry(vparent, physParent, iv, e, byName, n) || n.name != name) continue;
            return n;
        }
        return std::nullopt;
    }

private:
    // mu_ held. gocryptfs clears its dircache every 60 s; so do we.
    void expireIfDue() {
        auto now = std::chrono::steady_clock::now();
        if (now - lastClear_ >= kCacheTtl) {
            folders_.clear();
            diriv_.clear();
            lastClear_ = now;
        }
    }
    std::optional<std::string> cachedFolder(const std::string& v) {
        std::lock_guard<std::mutex> g(mu_);
        expireIfDue();
        auto it = folders_.find(v);
        if (it == folders_.end()) return std::nullopt;
        return it->second;
    }
    void cacheFolder(const std::string& v, const std::string& p) {
        std::lock_guard<std::mutex> g(mu_);
        folders_[v] = p;
    }
    std::string physicalOfCachedFolder(const std::string& v) {
        if (v.empty()) return std::string();
        if (auto c = cachedFolder(v)) return *c;
        try { return physicalFolderFor(v); } catch (const Error&) { return std::string(); }
    }

    Storage& st_;
    const NameCryptor& nc_;
    const bool hasDirIv_;
    std::mutex mu_;
    std::chrono::steady_clock::time_point lastClear_;
    std::unordered_map<std::string, std::string> folders_;
    std::unordered_map<std::string, Bytes> diriv_;
};

class GocryptfsVault final : public Vault, private EngineHost {
public:
    GocryptfsVault(std::shared_ptr<Storage> st, const Config& cfg, const Secret& masterkey, bool readOnly)
        : st_(std::move(st)), cfg_(cfg), readOnly_(readOnly),
          keys_(deriveSessionKeys(cfg, masterkey)),
          nc_(keys_.nameKey, cfg.longNameMax, cfg.plaintextNames, cfg.raw64()),
          fmt_(keys_.contentKey, cfg.cipher),
          tree_(*st_, nc_, cfg.hasDirIV() && !cfg.plaintextNames),
          engine_(*st_, fmt_, *this, readOnly, batchWrite_) {
        keys_.contentKey.wipe();   // fmt_ holds the only copy it needs
    }

    ~GocryptfsVault() override { close(); }

    // Verifies the root diriv exists (used right after construction).
    void probeRoot() { if (tree_.hasDirIV()) tree_.dirivFor("", ""); }

    VaultFormat format() const override { return VaultFormat::Gocryptfs; }
    bool readOnly() const override { return readOnly_; }

    // ---- namespace --------------------------------------------------------
    bool listDirectory(const std::string& path, std::vector<DirEntry>& out) override {
        try {
            Lifecycle::Op op(life_);
            std::shared_lock<std::shared_mutex> ns(ns_);
            auto nodes = tree_.list(normalizePath(path));
            out.clear();
            for (auto& n : nodes) {
                DirEntry e;
                e.name = n.name; e.isDir = n.isDir;
                e.size = n.isDir ? 0 : fmt_.cleartextSize(n.size);
                e.mtimeMs = n.mtimeMs;
                out.push_back(std::move(e));
            }
            return true;
        } catch (const std::exception& e) {
            logMsg(LogLevel::Debug, TAG, std::string("listDirectory failed: ") + e.what());
            return false;
        }
    }

    bool createDirectory(const std::string& path) override {
        if (readOnly_) return false;
        try {
            Lifecycle::Op op(life_);
            std::string normalized = normalizePath(path);
            std::unique_lock<std::shared_mutex> ns(ns_);
            std::string parentPath = parentOf(normalized), name = nameOf(normalized);
            std::string parentPhys = tree_.physicalFolderFor(parentPath);
            Bytes parentIv = tree_.dirivFor(parentPath, parentPhys);
            if (auto existing = tree_.resolve(normalized)) {
                if (!existing->isDir) return false;
                // The folder is already there. Like gocryptfs we leave it alone: a missing diriv is reported (the
                // call fails) rather than "repaired" with a fresh random one, because with a synchronised
                // ciphertext folder the real diriv may simply not have arrived yet -- and inventing a second one
                // would orphan every name written under the first.
                tree_.dirivFor(normalized, existing->physPath);
                return true;
            }
            checkCreatable(parentPath, name);
            std::string cipher = nc_.encryptName(name, parentIv.data());
            const bool over = nc_.isOverLongNameLimit(cipher);
            std::string physName = over ? nc_.hashLongName(cipher) : cipher;
            std::string phys = joinPath(parentPhys, physName);
            // Something we do not show may already sit there -- a symlink. gocryptfs says EEXIST; so do we (mkdir
            // would otherwise "succeed" on a link to a folder and we would then write a diriv into its target).
            if (st_->existsNoFollow(phys)) throw Error(Err::Exists, "\"" + name + "\" already exists");
            // Same order as gocryptfs' Mkdir: long-name sidecar, directory, diriv -- and every step undone if a
            // later one fails, so a failed mkdir never leaves a folder without its gocryptfs.diriv behind.
            const std::string sidecar = phys + kLongNameSuffix;
            if (over && !st_->writeWhole(sidecar, (const uint8_t*)cipher.data(), cipher.size())) return false;
            if (!st_->mkdir(phys)) {
                if (over) st_->remove(sidecar);
                return false;
            }
            if (tree_.hasDirIV()) {
                try {
                    tree_.createDirIv(normalized, phys);
                } catch (...) {
                    st_->remove(phys);
                    if (over) st_->remove(sidecar);
                    throw;
                }
            }
            tree_.invalidate(parentPath);
            return true;
        } catch (const std::exception& e) {
            logMsg(LogLevel::Warn, TAG, std::string("createDirectory failed: ") + e.what());
            return false;
        }
    }

    bool renameFile(const std::string& from, const std::string& to) override {
        if (readOnly_) return false;
        try {
            Lifecycle::Op op(life_);
            std::string oldN = normalizePath(from), newN = normalizePath(to);
            engine_.invalidateRead(oldN);
            engine_.invalidateRead(newN);
            std::unique_lock<std::shared_mutex> ns(ns_);
            auto node = tree_.resolve(oldN);
            if (!node) return false;
            std::string oldParent = parentOf(oldN), newParent = parentOf(newN), newName = nameOf(newN);
            std::string oldParentPhys = tree_.physicalFolderFor(oldParent);
            std::string newParentPhys = oldParent == newParent ? oldParentPhys : tree_.physicalFolderFor(newParent);
            Bytes iv = nc_.plaintextNames() ? Bytes() : tree_.dirivFor(newParent, newParentPhys);
            checkCreatable(newParent, newName);
            std::string cipher = nc_.encryptName(newName, iv.data());
            bool over = nc_.isOverLongNameLimit(cipher);
            std::string newPhysName = over ? nc_.hashLongName(cipher) : cipher;
            std::string newPhys = joinPath(newParentPhys, newPhysName);
            bool wasLong = hasSidecar(node->physName);
            if (newPhys == node->physPath) return true;   // same name, nothing to do
            // gocryptfs' Rename order: new long-name sidecar first (an existing one is fine), then the rename, and
            // the sidecar we wrote is removed again if the rename fails.
            const std::string newSidecar = newPhys + kLongNameSuffix;
            bool wroteSidecar = false;
            if (over) {
                DirEntry existing;
                if (!st_->stat(newSidecar, existing)) {
                    if (!st_->writeWhole(newSidecar, (const uint8_t*)cipher.data(), cipher.size()))
                        throw Error(Err::Io, "Could not create .name file");
                    wroteSidecar = true;
                }
            }
            if (!st_->rename(node->physPath, newPhys)) {
                if (wroteSidecar) st_->remove(newSidecar);
                return false;
            }
            if (wasLong) st_->remove(joinPath(oldParentPhys, node->physName + kLongNameSuffix));
            remapPending(oldN, newN, node->physPath, newPhys);
            tree_.invalidate(oldParent);
            tree_.invalidate(newParent);
            if (node->isDir) tree_.removeFolder(oldN);
            return true;
        } catch (const std::exception& e) {
            logMsg(LogLevel::Debug, TAG, std::string("renameFile failed: ") + e.what());
            return false;
        }
    }

    bool setLastModifiedTime(const std::string& path, int64_t epochSeconds) override {
        try {
            Lifecycle::Op op(life_);
            std::string n = normalizePath(path);
            std::shared_lock<std::shared_mutex> ns(ns_);
            auto node = tree_.resolve(n);
            if (!node) return false;
            bool ok = st_->setMtime(node->physPath, epochSeconds);
            if (ok) tree_.invalidate(parentOf(n));
            return ok;
        } catch (const std::exception&) { return false; }
    }

    bool deleteFile(const std::string& path) override {
        if (readOnly_) return false;
        try {
            Lifecycle::Op op(life_);
            std::string n = normalizePath(path);
            engine_.invalidateRead(n);
            std::unique_lock<std::shared_mutex> ns(ns_);
            dropPending(n);
            if (auto node = tree_.resolve(n)) {
                std::string parentPhys;
                bool haveParent = true;
                try { parentPhys = tree_.physicalFolderFor(parentOf(n)); } catch (const Error&) { haveParent = false; }
                st_->remove(node->physPath);
                if (node->isDir) tree_.removeFolder(n);
                if (haveParent && hasSidecar(node->physName))
                    st_->remove(joinPath(parentPhys, node->physName + kLongNameSuffix));
                tree_.invalidate(parentOf(n));
                return true;
            }
            // Nothing to delete. (resolve() already falls back to scanning the listing, so there is no
            // second lookup here -- an earlier one compared the *physical* name with the cleartext name,
            // which for an encrypted vault could hit gocryptfs.conf or gocryptfs.diriv.)
            return false;
        } catch (const std::exception& e) {
            logMsg(LogLevel::Warn, TAG, std::string("deleteFile failed: ") + e.what());
            return false;
        }
    }

    int64_t getFileSize(const std::string& path) override {
        try {
            Lifecycle::Op op(life_);
            std::shared_lock<std::shared_mutex> ns(ns_);
            auto node = tree_.resolve(normalizePath(path));
            if (!node || node->isDir) return -1;
            st_->ensureContentReady(node->physPath);
            DirEntry de;
            int64_t phys = st_->stat(node->physPath, de) ? de.size : node->size;
            return fmt_.cleartextSize(phys);
        } catch (const std::exception&) { return -1; }
    }

    int64_t getFolderSize(const std::string& path) override {
        try {
            Lifecycle::Op op(life_);
            std::shared_lock<std::shared_mutex> ns(ns_);
            return folderSize(normalizePath(path));
        } catch (const std::exception&) { return 0; }
    }

    // ---- content ----------------------------------------------------------
    std::optional<Bytes> readFileChunk(const std::string& path, int64_t offset, int length) override {
        try { Lifecycle::Op op(life_); return engine_.readFileChunk(path, offset, length); }
        catch (const std::exception&) { return std::nullopt; }
    }
    bool writeFileChunk(const std::string& path, int64_t offset, const uint8_t* data, size_t len) override {
        try { Lifecycle::Op op(life_); return engine_.writeFileChunk(path, offset, data, len); }
        catch (const std::exception&) { return false; }
    }
    bool finishWrite(const std::string& path) override {
        try {
            Lifecycle::Op op(life_);
            bool ok = engine_.finishWrite(path);
            if (ok) tree_.invalidate(parentOf(normalizePath(path)));
            return ok;
        } catch (const std::exception&) { return false; }
    }
    bool writeBackFile(const std::string& path, const std::string& src, Progress* p) override {
        try {
            Lifecycle::Op op(life_);
            bool ok = engine_.writeBackFile(path, src, p);
            if (ok) tree_.invalidate(parentOf(normalizePath(path)));
            return ok;
        } catch (const std::exception&) { return false; }
    }
    bool importStream(const std::string& path, ByteSource& src, Progress* p) override {
        try {
            Lifecycle::Op op(life_);
            if (readOnly_) return false;
            bool ok = engine_.writeBackStream(path, src, p);
            if (ok) tree_.invalidate(parentOf(normalizePath(path)));
            return ok;
        } catch (const std::exception&) { return false; }
    }
    bool extractFile(const std::string& path, const std::string& dest, Progress* p) override {
        try { Lifecycle::Op op(life_); return engine_.extractFile(path, dest, p); }
        catch (const std::exception&) { return false; }
    }

    // ---- batching / caches -----------------------------------------------
    void beginBatchWrite() override { batchWrite_ = true; }
    void endBatchWrite() override {
        batchWrite_ = false;
        std::map<std::string, std::string> paths;
        { std::lock_guard<std::mutex> g(pmu_); paths.swap(pending_); }
        try {
            Lifecycle::Op op(life_);
            for (auto& kv : paths) publish(kv.first, kv.second);
            tree_.invalidateAll();
        } catch (const std::exception&) {}
    }
    void beginBatchDelete() override { batchDelete_ = true; }
    void endBatchDelete() override {
        batchDelete_ = false;
        try { Lifecycle::Op op(life_); tree_.invalidateAll(); } catch (const std::exception&) {}
    }
    void invalidateCache(const std::string& path) override {
        try {
            Lifecycle::Op op(life_);
            if (path.empty()) { tree_.invalidateAll(); engine_.invalidateAll(); }
            else { std::string n = normalizePath(path); tree_.invalidateFolder(n); engine_.invalidateRead(n); }
        } catch (const std::exception&) {}
    }

    bool spaceInfo(int64_t& total, int64_t& free) override { return st_->spaceInfo(total, free); }

    std::vector<InfoItem> info() override {
        const char* cipher = cfg_.cipher == GocryptfsCipher::XChaCha20Poly1305 ? "XChaCha20-Poly1305"
                           : cfg_.cipher == GocryptfsCipher::AesSiv ? "AES-SIV" : "AES-256-GCM";
        return {
            {InfoItem::Kind::Int, "formatVersion", "2"},
            {InfoItem::Kind::Str, "cipher", cipher},
            {InfoItem::Kind::Bool, "plaintextNames", cfg_.plaintextNames ? "true" : "false"},
            {InfoItem::Kind::Bool, "deterministicNames", cfg_.deterministicNames() ? "true" : "false"},
            {InfoItem::Kind::Int, "longNameMax", std::to_string(cfg_.plaintextNames ? 0 : (cfg_.longNameMax > 0 ? cfg_.longNameMax : (int)kNameMax))},
            {InfoItem::Kind::Bool, "raw64", cfg_.raw64() ? "true" : "false"},
            {InfoItem::Kind::Bool, "hkdf", cfg_.hasHkdf() ? "true" : "false"},
            {InfoItem::Kind::Str, "creator", cfg_.creator},
            {InfoItem::Kind::Bool, "readOnly", readOnly_ ? "true" : "false"},
        };
    }

    KeyExport exportKeys() override {
        KeyExport k;
        k.format = VaultFormat::Gocryptfs;
        k.fields.emplace_back("nameKey", keys_.nameKey.bytes());
        k.fields.emplace_back("contentKey", fmt_.contentKey().bytes());
        k.strings.emplace_back("cipher", std::to_string((int)cfg_.cipher));
        k.strings.emplace_back("longNameMax", std::to_string(cfg_.longNameMax));
        k.strings.emplace_back("plaintextNames", cfg_.plaintextNames ? "1" : "0");
        k.strings.emplace_back("hasDirIV", tree_.hasDirIV() ? "1" : "0");
        k.strings.emplace_back("raw64", cfg_.plaintextNames || cfg_.raw64() ? "1" : "0");
        return k;
    }

    void close() override {
        if (!life_.markClosed()) return;
        engine_.close();
        life_.drain();
        tree_.invalidateAll();
        st_->close();
    }

private:
    // ---- EngineHost -------------------------------------------------------
    bool resolveForRead(const std::string& vpath, std::string& physical) override {
        std::shared_lock<std::shared_mutex> ns(ns_);
        auto n = tree_.resolve(vpath);
        if (!n || n->isDir) return false;
        physical = n->physPath;
        return true;
    }

    std::string prepareForWrite(const std::string& vpath) override {
        std::unique_lock<std::shared_mutex> ns(ns_);
        std::string n = normalizePath(vpath);
        std::string parentPath = parentOf(n), name = nameOf(n);
        std::string parentPhys = tree_.physicalFolderFor(parentPath);
        Bytes iv = nc_.plaintextNames() ? Bytes() : tree_.dirivFor(parentPath, parentPhys);
        std::string phys;
        if (auto existing = tree_.resolve(n)) {
            if (existing->isDir) throw Error(Err::Exists, "a folder with that name already exists");
            phys = existing->physPath;
        } else {
            checkCreatable(parentPath, name);
            std::string cipher = nc_.encryptName(name, iv.data());
            bool over = nc_.isOverLongNameLimit(cipher);
            phys = joinPath(parentPhys, over ? nc_.hashLongName(cipher) : cipher);
            // A symlink (which we neither show nor follow) may sit at that name: refuse, as gocryptfs does (EEXIST),
            // instead of creating the file *through* the link.
            if (st_->existsNoFollow(phys)) throw Error(Err::Exists, "\"" + name + "\" already exists");
            // gocryptfs' Create order: the long-name sidecar first, then the file; the sidecar goes again if the
            // file cannot be created.
            if (over && !st_->writeWhole(phys + kLongNameSuffix, (const uint8_t*)cipher.data(), cipher.size()))
                throw Error(Err::Io, "Could not create .name file");
            if (!st_->createFile(phys)) {
                if (over) st_->remove(phys + kLongNameSuffix);
                throw Error(Err::Io, "Could not create file");
            }
        }
        if (batchWrite_) { std::lock_guard<std::mutex> g(pmu_); pending_[n] = phys; }
        st_->markWritePending(phys);
        return phys;
    }

    void afterWrite(const std::string& vpath, const std::string& physical) override {
        std::string n = normalizePath(vpath);
        publish(n, physical);
        tree_.invalidate(parentOf(n));
    }

    void abortedWrite(const std::string& vpath, const std::string& physical) override {
        std::string n = normalizePath(vpath);
        std::unique_lock<std::shared_mutex> ns(ns_);
        { std::lock_guard<std::mutex> g(pmu_); pending_.erase(n); }
        st_->remove(physical);
        std::string base = nameOf(physical);
        if (hasSidecar(base)) st_->remove(physical + kLongNameSuffix);
        tree_.invalidate(parentOf(n));
    }

    // ---- helpers ------------------------------------------------------------
    // True if the physical entry [physName] has a gocryptfs.longname.*.name sidecar (never with plaintext names).
    bool hasSidecar(const std::string& physName) const {
        return !nc_.plaintextNames() && NameCryptor::isLongNameContent(physName);
    }
    // Refuses names gocryptfs cannot store: not a valid name, or -- with plaintext names -- the config file.
    void checkCreatable(const std::string& parentPath, const std::string& name) const {
        if (!NameCryptor::isValidName(name)) throw Error(Err::Unsupported, "Invalid file name");
        if (nc_.plaintextNames() && Tree::isConfigFile(parentPath, name))
            throw Error(Err::Unsupported, "\"" + name + "\" is reserved: gocryptfs keeps its configuration there");
    }

    void publish(const std::string& vpath, const std::string& physical) {
        try { st_->publishWrite(physical, endsWith(vpath, ".tmp") && !batchWrite_); }
        catch (const std::exception& e) { logMsg(LogLevel::Warn, TAG, std::string("publish failed: ") + e.what()); }
    }

    int64_t folderSize(const std::string& vdir) {
        int64_t total = 0;
        for (auto& n : tree_.list(vdir)) {
            if (n.isDir) total += folderSize(joinPath(vdir, n.name));
            else total += fmt_.cleartextSize(n.size);
        }
        return total;
    }

    void dropPending(const std::string& n) {
        std::lock_guard<std::mutex> g(pmu_);
        std::string prefix = n + "/";
        for (auto it = pending_.begin(); it != pending_.end();)
            if (it->first == n || startsWith(it->first, prefix.c_str())) it = pending_.erase(it); else ++it;
    }

    void remapPending(const std::string& oldV, const std::string& newV, const std::string& oldPhys, const std::string& newPhys) {
        std::lock_guard<std::mutex> g(pmu_);
        std::map<std::string, std::string> moved;
        std::string prefix = oldV + "/";
        for (auto it = pending_.begin(); it != pending_.end();) {
            bool self = it->first == oldV;
            if (self || startsWith(it->first, prefix.c_str())) {
                std::string key = newV + it->first.substr(oldV.size());
                std::string phys = startsWith(it->second, oldPhys.c_str()) ? newPhys + it->second.substr(oldPhys.size()) : it->second;
                moved[key] = phys;
                it = pending_.erase(it);
            } else ++it;
        }
        for (auto& kv : moved) pending_[kv.first] = kv.second;
    }

    std::shared_ptr<Storage> st_;
    Config cfg_;
    const bool readOnly_;
    SessionKeys keys_;
    NameCryptor nc_;
    ContentFormat fmt_;
    Tree tree_;
    std::atomic<bool> batchWrite_{false};
    std::atomic<bool> batchDelete_{false};
    ChunkedFileEngine engine_;
    Lifecycle life_;
    std::shared_mutex ns_;
    std::mutex pmu_;
    std::map<std::string, std::string> pending_;   // cleartext path -> physical path, batch only
};

PlainResult plainFail(OpenStatus s, std::string msg) { PlainResult r; r.status = s; r.message = std::move(msg); return r; }

// Reads + parses gocryptfs.conf, translating errors to results.
bool loadConfig(Storage& s, Config& cfg, std::string& err, OpenStatus& status) {
    Bytes raw;
    if (!s.readWhole(kConfigName, raw)) {
        status = OpenStatus::InvalidVault;
        err = "No gocryptfs.conf found \xE2\x80\x94 this doesn't look like a gocryptfs vault.";
        return false;
    }
    try {
        cfg = Config::parse(std::string(raw.begin(), raw.end()));
    } catch (const Error& e) {
        status = OpenStatus::InvalidVault;
        err = e.what();
        return false;
    }
    return true;
}

}  // namespace
}  // namespace gocryptfs

// ----------------------------------------------------------- public entry --

bool looksLikeGocryptfs(Storage& s) {
    DirEntry de;
    return s.stat(gocryptfs::kConfigName, de) && !de.isDir;
}

OpenResult openGocryptfs(std::shared_ptr<Storage> s, const uint8_t* pw, size_t pwLen, bool readOnly,
                         const HostEnv&, const StorageFactory& factory) {
    using namespace gocryptfs;
    OpenResult res;
    Config cfg;
    if (!loadConfig(*s, cfg, res.message, res.status)) return res;

    Secret masterkey;
    try {
        masterkey = unlockMasterkey(cfg, pw, pwLen);
    } catch (const Error& e) {
        res.status = e.code() == Err::WrongPassword ? OpenStatus::WrongPassword : OpenStatus::InvalidVault;
        res.message = e.code() == Err::WrongPassword ? e.what() : std::string("Failed to unlock masterkey: ") + e.what();
        return res;
    } catch (const std::exception& e) {
        res.status = OpenStatus::InvalidVault;
        res.message = std::string("Failed to unlock masterkey: ") + e.what();
        return res;
    }

    std::shared_ptr<Storage> sessionStorage = s;
    try {
        if (factory) { auto f = factory(); if (f) sessionStorage = std::move(f); }
    } catch (const std::exception& e) {
        res.status = OpenStatus::InvalidVault;
        res.message = std::string("Could not open vault: ") + e.what();
        return res;
    }

    try {
        auto vault = std::make_unique<GocryptfsVault>(sessionStorage, cfg, masterkey, readOnly);
        try {
            vault->probeRoot();
        } catch (const std::exception& e) {
            vault->close();
            res.status = OpenStatus::InvalidVault;
            res.message = std::string("Missing or corrupt gocryptfs.diriv: ") + e.what();
            return res;
        }
        res.status = OpenStatus::Ok;
        res.vault = std::move(vault);
        return res;
    } catch (const std::exception& e) {
        if (sessionStorage != s) sessionStorage->close();
        res.status = OpenStatus::InvalidVault;
        res.message = std::string("Could not open vault: ") + e.what();
        return res;
    }
}

PlainResult createGocryptfs(Storage& s, const uint8_t* pw, size_t pwLen, const GocryptfsCreateOptions& o) {
    using namespace gocryptfs;
    try {
        // The same limits `gocryptfs -init` enforces.
        if (o.longNameMax != 0 && (o.longNameMax < 62 || o.longNameMax > 255))
            return plainFail(OpenStatus::InvalidVault, "longnamemax: value " + std::to_string(o.longNameMax) + " is outside allowed range 62 ... 255");
        if (o.scryptLogN < 10 || o.scryptLogN > 28)
            return plainFail(OpenStatus::InvalidVault, "scryptn: value " + std::to_string(o.scryptLogN) + " is outside allowed range 10 ... 28");

        std::vector<DirEntry> existing;
        if (s.list("", existing) && !existing.empty())
            return plainFail(OpenStatus::InvalidVault, "Selected folder is not empty.");

        Config cfg;
        cfg.version = 2;
        cfg.creator = "VaultExplorer";
        cfg.plaintextNames = o.plaintextNames;
        cfg.cipher = o.cipher;
        cfg.scryptN = 1u << o.scryptLogN; cfg.scryptR = 8; cfg.scryptP = 1; cfg.scryptKeyLen = 32;
        // The flag set and order configfile.Create() writes: HKDF, the content cipher, then either
        // PlaintextNames or [DirIV] [LongNameMax] EMENames LongNames Raw64, and finally AESSIV.
        cfg.featureFlags.push_back("HKDF");
        cfg.featureFlags.push_back(o.cipher == GocryptfsCipher::XChaCha20Poly1305 ? "XChaCha20Poly1305" : "GCMIV128");
        const bool deterministic = !o.plaintextNames && o.deterministicNames;
        if (o.plaintextNames) {
            cfg.featureFlags.push_back("PlaintextNames");
        } else {
            if (!deterministic) cfg.featureFlags.push_back("DirIV");
            if (o.longNameMax != 0 && o.longNameMax != 255) {   // 255 is the default and is not recorded
                cfg.featureFlags.push_back("LongNameMax");
                cfg.longNameMax = o.longNameMax;
            }
            for (const char* f : {"EMENames", "LongNames", "Raw64"}) cfg.featureFlags.push_back(f);
        }
        if (o.cipher == GocryptfsCipher::AesSiv) cfg.featureFlags.push_back("AESSIV");

        Secret masterkey(crypto::randomKeyBytes(32));
        cfg.scryptSalt = crypto::randomKeyBytes(32);
        cfg.encryptedKey = wrapMasterkey(masterkey, pw, pwLen, cfg.scryptSalt, cfg.scryptN, cfg.scryptR, cfg.scryptP, cfg.scryptKeyLen, /*hkdf*/ true);

        std::string json = cfg.toJson();
        if (!s.writeWhole(kConfigName, (const uint8_t*)json.data(), json.size()))
            return plainFail(OpenStatus::InvalidVault, "Could not write gocryptfs.conf");
        // The root needs its gocryptfs.diriv unless names are plaintext or deterministic.
        if (!o.plaintextNames && !deterministic) {
            Bytes iv(kDirIvLen);
            do { crypto::randomKey(iv.data(), iv.size()); } while (!Tree::validDirIv(iv));
            if (!s.writeWhole(kDirIvName, iv.data(), iv.size()))
                return plainFail(OpenStatus::InvalidVault, "Could not write gocryptfs.diriv");
        }
        PlainResult ok;
        ok.status = OpenStatus::Ok;
        return ok;
    } catch (const std::exception& e) {
        return plainFail(OpenStatus::InvalidVault, std::string("Failed to create vault: ") + e.what());
    }
}

PlainResult changeGocryptfsPassword(Storage& s, const uint8_t* oldPw, size_t oldLen, const uint8_t* newPw, size_t newLen) {
    using namespace gocryptfs;
    PlainResult r;
    Config cfg;
    if (!loadConfig(s, cfg, r.message, r.status)) return r;
    try {
        Secret masterkey = unlockMasterkey(cfg, oldPw, oldLen);
        cfg.scryptSalt = crypto::randomKeyBytes(32);
        // Re-wrapped the way the vault's own flags say (a vault without HKDF has a 96-bit nonce and an unexpanded key).
        cfg.encryptedKey = wrapMasterkey(masterkey, newPw, newLen, cfg.scryptSalt, cfg.scryptN, cfg.scryptR, cfg.scryptP, cfg.scryptKeyLen, cfg.hasHkdf());
        std::string json = cfg.toJson();
        if (!s.writeWholeAtomic(kConfigName, (const uint8_t*)json.data(), json.size()))
            return plainFail(OpenStatus::InvalidVault, "Could not write gocryptfs.conf");
        r.status = OpenStatus::Ok;
        return r;
    } catch (const Error& e) {
        return plainFail(e.code() == Err::WrongPassword ? OpenStatus::WrongPassword : OpenStatus::InvalidVault, e.what());
    } catch (const std::exception& e) {
        return plainFail(OpenStatus::InvalidVault, e.what());
    }
}

}  // namespace fv
