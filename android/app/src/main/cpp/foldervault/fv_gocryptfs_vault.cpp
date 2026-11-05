// gocryptfs vault: directory tree resolution, the session (fv::Vault) and the
// open / create / change-password entry points.
#include <algorithm>
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
class Tree {
public:
    Tree(Storage& st, const NameCryptor& nc, bool hasDirIv) : st_(st), nc_(nc), hasDirIv_(hasDirIv) {}

    bool hasDirIV() const { return hasDirIv_; }

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

    Bytes dirivFor(const std::string& vdir, const std::string& physicalFolder) {
        if (!hasDirIv_) return Bytes(16, 0);
        {
            std::lock_guard<std::mutex> g(mu_);
            auto it = diriv_.find(vdir);
            if (it != diriv_.end()) return it->second;
        }
        Bytes iv;
        const std::string p = joinPath(physicalFolder, kDirIvName);
        if (!st_.readWhole(p, iv) || iv.size() != 16) {
            st_.invalidate(physicalFolder);   // a stale listing may have hidden it
            if (!st_.readWhole(p, iv) || iv.size() != 16)
                throw Error(Err::Io, "Missing or invalid gocryptfs.diriv in " + (physicalFolder.empty() ? std::string("<root>") : physicalFolder));
        }
        std::lock_guard<std::mutex> g(mu_);
        diriv_[vdir] = iv;
        return iv;
    }
    Bytes dirivFor(const std::string& vdir) { return dirivFor(vdir, physicalFolderFor(vdir)); }

    Bytes createDirIv(const std::string& vdir, const std::string& physicalFolder) {
        Bytes iv(16);
        crypto::randomFast(iv.data(), 16);
        if (!st_.writeWhole(joinPath(physicalFolder, kDirIvName), iv.data(), iv.size()))
            throw Error(Err::Io, "Could not write gocryptfs.diriv");
        std::lock_guard<std::mutex> g(mu_);
        diriv_[vdir] = iv;
        return iv;
    }

    std::vector<Node> list(const std::string& vdirIn) {
        std::string vdir = normalizePath(vdirIn);
        std::string physical = physicalFolderFor(vdir);
        Bytes iv = dirivFor(vdir, physical);
        std::vector<DirEntry> ents;
        if (!st_.list(physical, ents)) throw Error(Err::NotFound, "Folder not found: " + vdir);
        std::unordered_map<std::string, const DirEntry*> byName;
        for (auto& e : ents) byName[e.name] = &e;
        std::vector<Node> out;
        for (auto& e : ents) {
            const std::string& name = e.name;
            if (name == kDirIvName || name == kConfigName || name == kConfigBakName) continue;
            if (endsWith(name, kLongNameSuffix)) continue;
            std::string cipherName = name;
            if (startsWith(name, kLongNamePrefix)) {
                auto side = byName.find(name + kLongNameSuffix);
                if (side == byName.end()) continue;
                Bytes raw;
                if (!st_.readWhole(joinPath(physical, side->second->name), raw)) continue;
                cipherName.assign(raw.begin(), raw.end());
            }
            std::string clear;
            try { clear = nc_.decryptName(cipherName, iv.data()); } catch (const Error&) { continue; }
            Node n;
            n.isDir = e.isDir; n.name = clear; n.physName = name;
            n.physPath = joinPath(physical, name);
            n.size = e.size; n.mtimeMs = e.mtimeMs;
            if (n.isDir) cacheFolder(joinPath(vdir, clear), n.physPath);
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
    void invalidate(const std::string& vdir) {
        st_.invalidate(physicalOfCachedFolder(normalizePath(vdir)));
    }
    void invalidateAll() {
        {
            std::lock_guard<std::mutex> g(mu_);
            folders_.clear();
            diriv_.clear();
        }
        st_.invalidateAll();
    }

    // Physical child lookup by cleartext name: direct stat of the expected
    // encrypted name first, then (as a fallback for stale/odd listings) a scan.
    std::optional<Node> findChild(const std::string& vparent, const std::string& physParent,
                                  const std::string& name, bool wantDir) {
        (void)wantDir;
        Bytes iv = dirivFor(vparent, physParent);
        std::string cipher;
        try { cipher = nc_.encryptName(name, iv.data()); } catch (const Error&) { return std::nullopt; }
        std::string physName = nc_.isOverLongNameLimit(cipher) ? nc_.hashLongName(cipher) : cipher;
        DirEntry de;
        if (st_.stat(joinPath(physParent, physName), de)) {
            Node n;
            n.isDir = de.isDir; n.name = name; n.physName = physName;
            n.physPath = joinPath(physParent, physName);
            n.size = de.size; n.mtimeMs = de.mtimeMs;
            return n;
        }
        std::vector<DirEntry> ents;
        if (!st_.list(physParent, ents)) return std::nullopt;
        std::unordered_map<std::string, const DirEntry*> byName;
        for (auto& e : ents) byName[e.name] = &e;
        for (auto& e : ents) {
            const std::string& pn = e.name;
            if (pn == kDirIvName || pn == kConfigName || pn == kConfigBakName || endsWith(pn, kLongNameSuffix)) continue;
            std::string cn = pn;
            if (startsWith(pn, kLongNamePrefix)) {
                auto side = byName.find(pn + kLongNameSuffix);
                if (side == byName.end()) continue;
                Bytes raw;
                if (!st_.readWhole(joinPath(physParent, side->second->name), raw)) continue;
                cn.assign(raw.begin(), raw.end());
            }
            std::string clear;
            try { clear = nc_.decryptName(cn, iv.data()); } catch (const Error&) { continue; }
            if (clear != name) continue;
            Node n;
            n.isDir = e.isDir; n.name = clear; n.physName = pn;
            n.physPath = joinPath(physParent, pn);
            n.size = e.size; n.mtimeMs = e.mtimeMs;
            return n;
        }
        return std::nullopt;
    }

private:
    std::optional<std::string> cachedFolder(const std::string& v) {
        std::lock_guard<std::mutex> g(mu_);
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
    std::unordered_map<std::string, std::string> folders_;
    std::unordered_map<std::string, Bytes> diriv_;
};

class GocryptfsVault final : public Vault, private EngineHost {
public:
    GocryptfsVault(std::shared_ptr<Storage> st, const Config& cfg, const Secret& masterkey, bool readOnly)
        : st_(std::move(st)), cfg_(cfg), readOnly_(readOnly),
          nameKey_(cfg.plaintextNames ? Secret() : crypto::hkdfSha256(masterkey.data(), masterkey.size(), "EME filename encryption", 32)),
          nc_(nameKey_, cfg.longNameMax, cfg.plaintextNames),
          fmt_(crypto::hkdfSha256(masterkey.data(), masterkey.size(), cipherInfo(cfg.cipher).hkdfInfo, cipherInfo(cfg.cipher).contentKeyLen), cfg.cipher),
          tree_(*st_, nc_, cfg.hasDirIV() && !cfg.plaintextNames),
          engine_(*st_, fmt_, *this, readOnly, batchWrite_) {}

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
                try { tree_.dirivFor(normalized, existing->physPath); }
                catch (const Error&) { tree_.createDirIv(normalized, existing->physPath); }
                return true;
            }
            std::string cipher = nc_.encryptName(name, parentIv.data());
            std::string physName = nc_.isOverLongNameLimit(cipher) ? nc_.hashLongName(cipher) : cipher;
            std::string phys = joinPath(parentPhys, physName);
            if (!st_->mkdir(phys)) return false;
            if (nc_.isOverLongNameLimit(cipher) && !st_->writeWhole(phys + kLongNameSuffix, (const uint8_t*)cipher.data(), cipher.size())) {
                st_->remove(phys);
                return false;
            }
            if (tree_.hasDirIV()) tree_.createDirIv(normalized, phys);
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
            Bytes iv = tree_.dirivFor(newParent, newParentPhys);
            std::string cipher = nc_.encryptName(newName, iv.data());
            bool over = nc_.isOverLongNameLimit(cipher);
            std::string newPhysName = over ? nc_.hashLongName(cipher) : cipher;
            std::string newPhys = joinPath(newParentPhys, newPhysName);
            bool wasLong = startsWith(node->physName, kLongNamePrefix) && !endsWith(node->physName, kLongNameSuffix);
            if (newPhys == node->physPath) return true;   // same name, nothing to do
            if (!st_->rename(node->physPath, newPhys)) return false;
            if (over && !st_->writeWhole(newPhys + kLongNameSuffix, (const uint8_t*)cipher.data(), cipher.size()))
                throw Error(Err::Io, "Could not create .name file");
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
                if (haveParent && startsWith(node->physName, kLongNamePrefix))
                    st_->remove(joinPath(parentPhys, node->physName + kLongNameSuffix));
                tree_.invalidate(parentOf(n));
                return true;
            }
            // Fallback: the listing may know a name the direct lookup missed.
            std::string parentPath = parentOf(n);
            std::string parentPhys;
            try { parentPhys = tree_.physicalFolderFor(parentPath); } catch (const Error&) { return false; }
            std::string target = nameOf(n);
            Bytes iv;
            bool haveIv = true;
            try { iv = tree_.dirivFor(parentPath, parentPhys); } catch (const Error&) { haveIv = false; }
            std::vector<DirEntry> ents;
            if (!st_->list(parentPhys, ents)) return false;
            for (auto& e : ents) {
                bool match = e.name == target;
                if (!match && haveIv) { try { match = nc_.decryptName(e.name, iv.data()) == target; } catch (const Error&) {} }
                if (!match) continue;
                st_->remove(joinPath(parentPhys, e.name));
                if (startsWith(e.name, kLongNamePrefix)) st_->remove(joinPath(parentPhys, e.name + kLongNameSuffix));
                tree_.invalidate(parentPath);
                return true;
            }
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
            else { std::string n = normalizePath(path); tree_.invalidate(n); engine_.invalidateRead(n); }
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
            {InfoItem::Kind::Bool, "readOnly", readOnly_ ? "true" : "false"},
        };
    }

    KeyExport exportKeys() override {
        KeyExport k;
        k.format = VaultFormat::Gocryptfs;
        k.fields.emplace_back("nameKey", nameKey_.bytes());
        k.fields.emplace_back("contentKey", fmt_.contentKey().bytes());
        k.strings.emplace_back("cipher", std::to_string((int)cfg_.cipher));
        k.strings.emplace_back("longNameMax", std::to_string(cfg_.longNameMax));
        k.strings.emplace_back("plaintextNames", cfg_.plaintextNames ? "1" : "0");
        k.strings.emplace_back("hasDirIV", tree_.hasDirIV() ? "1" : "0");
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
        Bytes iv = tree_.dirivFor(parentPath, parentPhys);
        std::string phys;
        if (auto existing = tree_.resolve(n)) {
            if (existing->isDir) throw Error(Err::Exists, "a folder with that name already exists");
            phys = existing->physPath;
        } else {
            std::string cipher = nc_.encryptName(name, iv.data());
            bool over = nc_.isOverLongNameLimit(cipher);
            phys = joinPath(parentPhys, over ? nc_.hashLongName(cipher) : cipher);
            if (!st_->createFile(phys)) throw Error(Err::Io, "Could not create file");
            if (over && !st_->writeWhole(phys + kLongNameSuffix, (const uint8_t*)cipher.data(), cipher.size())) {
                st_->remove(phys);
                throw Error(Err::Io, "Could not create .name file");
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
        if (startsWith(base, kLongNamePrefix)) st_->remove(physical + kLongNameSuffix);
        tree_.invalidate(parentOf(n));
    }

    // ---- helpers ------------------------------------------------------------
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
    Secret nameKey_;
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
        std::vector<DirEntry> existing;
        if (s.list("", existing) && !existing.empty())
            return plainFail(OpenStatus::InvalidVault, "Selected folder is not empty.");

        Config cfg;
        cfg.version = 2;
        cfg.plaintextNames = o.plaintextNames;
        cfg.cipher = o.cipher;
        cfg.scryptN = 1u << 16; cfg.scryptR = 8; cfg.scryptP = 1; cfg.scryptKeyLen = 32;
        cfg.featureFlags.push_back(o.cipher == GocryptfsCipher::XChaCha20Poly1305 ? "XChaCha20Poly1305" : "GCMIV128");
        if (o.cipher == GocryptfsCipher::AesSiv) cfg.featureFlags.push_back("AESSIV");
        cfg.featureFlags.push_back("HKDF");
        if (o.plaintextNames) cfg.featureFlags.push_back("PlaintextNames");
        else for (const char* f : {"Raw64", "DirIV", "EMENames", "LongNames"}) cfg.featureFlags.push_back(f);
        if (o.fido2) {
            cfg.featureFlags.push_back("FIDO2");
            cfg.fido2 = *o.fido2;
        }

        Secret masterkey(crypto::randomKeyBytes(32));
        cfg.scryptSalt = crypto::randomKeyBytes(32);
        cfg.encryptedKey = wrapMasterkey(masterkey, pw, pwLen, cfg.scryptSalt, cfg.scryptN, cfg.scryptR, cfg.scryptP, cfg.scryptKeyLen);

        std::string json = cfg.toJson();
        if (!s.writeWhole(kConfigName, (const uint8_t*)json.data(), json.size()))
            return plainFail(OpenStatus::InvalidVault, "Could not write gocryptfs.conf");
        if (!o.plaintextNames) {
            Bytes iv = crypto::randomKeyBytes(16);
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
    // Upstream gocryptfs doesn't support this either: the wrapping secret is the security
    // key's output, not a password that can be swapped.
    if (cfg.fido2) return plainFail(OpenStatus::InvalidVault, "This vault is protected by a security key; its password can't be changed.");
    try {
        Secret masterkey = unlockMasterkey(cfg, oldPw, oldLen);
        cfg.scryptSalt = crypto::randomKeyBytes(32);
        cfg.encryptedKey = wrapMasterkey(masterkey, newPw, newLen, cfg.scryptSalt, cfg.scryptN, cfg.scryptR, cfg.scryptP, cfg.scryptKeyLen);
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
