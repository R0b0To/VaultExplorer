// Cryptomator vault: directory tree, session (fv::Vault) and the open /
// create / change-password entry points.
#include <cctype>
#include <cstring>
#include <algorithm>
#include <map>
#include <mutex>
#include <shared_mutex>
#include <unordered_map>

#include "fv_cryptomator.h"
#include "fv_util.h"

namespace fv {
namespace cryptomator {
namespace {

constexpr const char* TAG = "CryptomatorSession";
constexpr const char* kC9r = ".c9r";
constexpr const char* kC9s = ".c9s";
constexpr const char* kDirFile = "dir.c9r";
constexpr const char* kDirIdBackup = "dirid.c9r";
constexpr const char* kNameFile = "name.c9s";
constexpr const char* kContentsFile = "contents.c9r";

struct Node {
    bool isDir = false;
    bool shortened = false;
    std::string name;          // cleartext
    std::string nodePath;      // the .c9r file/folder or the .c9s wrapper folder
    std::string contentsPath;  // file: where the encrypted bytes are; dir: == nodePath
    std::string dirIdFile;     // dir: path of its dir.c9r pointer
    int64_t size = 0;          // file: physical size of the contents
    int64_t mtimeMs = 0;       // file: contents mtime; dir: node folder mtime
    int64_t wrapperMtimeMs = 0;
};

std::string shortNameFor(const std::string& fullName) {
    Bytes h = crypto::hash(crypto::Md::Sha1, (const uint8_t*)fullName.data(), fullName.size());
    return base64Encode(h.data(), h.size(), true, true) + kC9s;
}

std::string newUuid() {
    uint8_t b[16];
    crypto::randomFast(b, 16);
    b[6] = (uint8_t)((b[6] & 0x0F) | 0x40);
    b[8] = (uint8_t)((b[8] & 0x3F) | 0x80);
    std::string h = toHex(b, 16);
    return h.substr(0, 8) + "-" + h.substr(8, 4) + "-" + h.substr(12, 4) + "-" + h.substr(16, 4) + "-" + h.substr(20);
}

bool hasNonAscii(const std::string& s) {
    for (unsigned char c : s) if (c >= 0x80) return true;
    return false;
}

// dirid.c9r = the directory's OWN id encrypted like a regular file (cryptolib DirectoryIdBackup).
static bool writeDirIdBackupFile(Storage& st, const ContentFormat& fmt, const std::string& physFolder,
                                 const std::string& ownDirId) {
    Bytes file;
    auto key = fmt.newHeader(file);
    Bytes enc(fmt.encryptedSize(ownDirId.size()));
    fmt.encrypt(*key, 0, (const uint8_t*)ownDirId.data(), ownDirId.size(), enc.data());
    file.insert(file.end(), enc.begin(), enc.end());
    return st.writeWhole(joinPath(physFolder, kDirIdBackup), file.data(), file.size());
}

class Tree {
public:
    Tree(Storage& st, const NameCryptor& nc, int shortening, bool readOnly = false)
        : st_(st), nc_(nc), shortening_(shortening), readOnly_(readOnly) {
        dirIds_[""] = "";
    }

    std::string dataPathFor(const std::string& dirId) {
        {
            std::lock_guard<std::mutex> g(mu_);
            auto it = dataDirs_.find(dirId);
            if (it != dataDirs_.end()) return it->second;
        }
        std::string h = nc_.hashDirectoryId(dirId);
        return joinPath(joinPath(kDataDir, h.substr(0, 2)), h.substr(2));
    }

    // Auto-heals a missing backing folder (as the Kotlin tree did).
    std::string physicalFolderForDirId(const std::string& dirId) {
        {
            std::lock_guard<std::mutex> g(mu_);
            auto it = dataDirs_.find(dirId);
            if (it != dataDirs_.end()) return it->second;
        }
        std::string p = dataPathFor(dirId);
        DirEntry de;
        if (st_.stat(p, de) && de.isDir) { cacheData(dirId, p); return p; }
        if (readOnly_) {
            // A read-only session must never write to the vault (the folder may simply not have synced yet).
            throw Error(Err::NotFound, "Backing directory for dirId '" + dirId + "' is missing (read-only, not repairing)");
        }
        logMsg(LogLevel::Warn, TAG, "Auto-healing missing backing directory for dirId '" + dirId + "'");
        return createPhysicalFolderForDirId(dirId);
    }

    std::string createPhysicalFolderForDirId(const std::string& dirId) {
        std::string p = dataPathFor(dirId);
        std::string lvl1 = parentOf(p);
        if (!st_.mkdir(kDataDir) || !st_.mkdir(lvl1) || !st_.mkdir(p))
            throw Error(Err::Io, "Could not create backing directory for dirId '" + dirId + "'");
        cacheData(dirId, p);
        return p;
    }

    std::string readDirId(const std::string& dirIdFile) {
        Bytes b;
        if (!st_.readWhole(dirIdFile, b)) throw Error(Err::Io, "Failed to read dirId from " + dirIdFile);
        std::string id(b.begin(), b.end());
        size_t s = id.find_first_not_of(" \t\r\n"), e = id.find_last_not_of(" \t\r\n");
        id = s == std::string::npos ? "" : id.substr(s, e - s + 1);
        if (id.empty()) throw Error(Err::Io, "dir.c9r is empty: " + dirIdFile);
        return id;
    }

    std::vector<Node> listByDirId(const std::string& dirId) {
        std::string folder;
        try { folder = physicalFolderForDirId(dirId); } catch (const Error& e) {
            logMsg(LogLevel::Warn, TAG, std::string("listByDirId: backing folder unavailable: ") + e.what());
            return {};
        }
        std::vector<DirEntry> children;
        if (!st_.list(folder, children)) return {};
        std::vector<Node> out;
        for (const DirEntry& c : children) {
            const std::string& name = c.name;
            try {
                if (name == kDirFile || name == kDirIdBackup) continue;
                if (endsWith(name, kC9s)) {
                    if (!c.isDir) continue;
                    std::string wrapper = joinPath(folder, name);
                    Bytes ln;
                    if (!st_.readWhole(joinPath(wrapper, kNameFile), ln) || ln.empty()) {
                        st_.invalidate(wrapper);
                        if (!st_.readWhole(joinPath(wrapper, kNameFile), ln) || ln.empty()) continue;
                    }
                    std::string raw(ln.begin(), ln.end());
                    size_t e2 = raw.find_last_not_of(std::string(" \r\n\0", 4));
                    raw = e2 == std::string::npos ? "" : raw.substr(0, e2 + 1);
                    size_t s2 = raw.find_first_not_of(' ');
                    raw = s2 == std::string::npos ? "" : raw.substr(s2);
                    std::string cipher = endsWith(raw, kC9r) ? raw.substr(0, raw.size() - 4) : raw;
                    std::string clear = nc_.decryptFilename(cipher, dirId);
                    if (!usableName(clear)) continue;
                    DirEntry ptr;
                    Node n;
                    n.shortened = true; n.name = clear; n.nodePath = wrapper; n.wrapperMtimeMs = c.mtimeMs;
                    if (st_.stat(joinPath(wrapper, kDirFile), ptr)) {
                        n.isDir = true; n.contentsPath = wrapper; n.dirIdFile = joinPath(wrapper, kDirFile); n.mtimeMs = c.mtimeMs;
                    } else {
                        DirEntry contents;
                        if (!st_.stat(joinPath(wrapper, kContentsFile), contents)) {
                            st_.invalidate(wrapper);
                            if (!st_.stat(joinPath(wrapper, kContentsFile), contents)) {
                                logMsg(LogLevel::Warn, TAG, "Shortened node '" + name + "' has neither dir.c9r nor contents.c9r -- skipping");
                                continue;
                            }
                        }
                        n.contentsPath = joinPath(wrapper, kContentsFile);
                        n.size = contents.size; n.mtimeMs = contents.mtimeMs;
                    }
                    out.push_back(std::move(n));
                } else if (endsWith(name, kC9r)) {
                    std::string clear = nc_.decryptFilename(name.substr(0, name.size() - 4), dirId);
                    if (!usableName(clear)) continue;
                    Node n;
                    n.name = clear; n.nodePath = joinPath(folder, name); n.contentsPath = n.nodePath;
                    n.size = c.size; n.mtimeMs = c.mtimeMs;
                    if (c.isDir) {
                        DirEntry ptr;
                        if (!st_.stat(joinPath(n.nodePath, kDirFile), ptr)) {
                            logMsg(LogLevel::Warn, TAG, "Directory node '" + name + "' is missing dir.c9r -- skipping");
                            continue;
                        }
                        n.isDir = true; n.size = 0; n.dirIdFile = joinPath(n.nodePath, kDirFile);
                    }
                    out.push_back(std::move(n));
                }
            } catch (const Error& e) {
                logMsg(LogLevel::Debug, TAG, "Skipping unreadable child '" + name + "': " + e.what());
            }
        }
        return out;
    }

    // Direct lookup of one child by cleartext name (O(1) instead of
    // decrypting the whole directory), with a scan as fallback for names other
    // clients stored in a different Unicode normalisation.
    std::optional<Node> findNode(const std::string& dirId, const std::string& name) {
        std::string folder = physicalFolderForDirId(dirId);
        std::string cipher = nc_.encryptFilename(name, dirId);
        std::string full = cipher + kC9r;
        const bool isShort = (int)full.size() > shortening_;
        std::string nodeName = isShort ? shortNameFor(full) : full;
        std::string nodePath = joinPath(folder, nodeName);
        DirEntry de;
        if (st_.stat(nodePath, de)) {
            Node n;
            n.name = name; n.nodePath = nodePath; n.shortened = isShort; n.contentsPath = nodePath;
            n.mtimeMs = de.mtimeMs; n.size = de.size;
            if (isShort) {
                n.wrapperMtimeMs = de.mtimeMs;
                if (!de.isDir) return std::nullopt;
                DirEntry ptr, contents;
                if (st_.stat(joinPath(nodePath, kDirFile), ptr)) {
                    n.isDir = true; n.dirIdFile = joinPath(nodePath, kDirFile); n.size = 0;
                    return n;
                }
                if (st_.stat(joinPath(nodePath, kContentsFile), contents)) {
                    n.contentsPath = joinPath(nodePath, kContentsFile);
                    n.size = contents.size; n.mtimeMs = contents.mtimeMs;
                    return n;
                }
                return std::nullopt;
            }
            if (de.isDir) {
                DirEntry ptr;
                if (!st_.stat(joinPath(nodePath, kDirFile), ptr)) return std::nullopt;
                n.isDir = true; n.size = 0; n.dirIdFile = joinPath(nodePath, kDirFile);
            }
            return n;
        }
        if (hasNonAscii(name)) {
            for (Node& n : listByDirId(dirId)) if (n.name == name) return std::move(n);
        }
        return std::nullopt;
    }

    // Returns false if some segment does not exist (or is a file).
    bool resolveDirId(const std::string& vdirIn, std::string& dirId) {
        std::string vdir = normalizePath(vdirIn);
        if (vdir.empty()) { dirId.clear(); return true; }
        std::string cur, built;
        for (const std::string& seg : splitSegments(vdir)) {
            std::string next = joinPath(built, seg);
            if (auto c = cachedDirId(next)) { cur = *c; built = next; continue; }
            auto node = findNode(cur, seg);
            if (!node || !node->isDir) return false;
            std::string id;
            try { id = readDirId(node->dirIdFile); } catch (const Error&) { return false; }
            cur = id;
            cacheDirId(next, cur);
            built = next;
        }
        dirId = cur;
        return true;
    }

    std::optional<Node> resolve(const std::string& vpathIn) {
        std::string vpath = normalizePath(vpathIn);
        if (vpath.empty()) return std::nullopt;
        std::string parentId;
        if (!resolveDirId(parentOf(vpath), parentId)) return std::nullopt;
        return findNode(parentId, nameOf(vpath));
    }

    void invalidate(const std::string& vdirIn) {
        std::string n = normalizePath(vdirIn);
        if (n.empty()) { invalidateAll(); return; }
        std::string dirId;
        bool have = false;
        if (auto c = cachedDirId(n)) { dirId = *c; have = true; }
        else if (resolveDirId(n, dirId)) have = true;
        if (have) st_.invalidate(dataPathFor(dirId));
        std::vector<std::string> staleIds;
        {
            std::lock_guard<std::mutex> g(mu_);
            std::string prefix = n + "/";
            for (auto it = dirIds_.begin(); it != dirIds_.end();) {
                if (it->first != "" && (it->first == n || startsWith(it->first, prefix.c_str()))) { staleIds.push_back(it->second); it = dirIds_.erase(it); }
                else ++it;
            }
            for (auto& id : staleIds) dataDirs_.erase(id);
        }
        for (auto& id : staleIds) st_.invalidate(dataPathFor(id));
        std::string parent = parentOf(n);
        if (parent.empty()) st_.invalidate(dataPathFor(""));
        else if (auto pc = cachedDirId(parent)) st_.invalidate(dataPathFor(*pc));
    }

    void invalidateAll() {
        st_.invalidateAll();
        std::lock_guard<std::mutex> g(mu_);
        dirIds_.clear(); dirIds_[""] = "";
        dataDirs_.clear();
    }

    int shortening() const { return shortening_; }

private:
    static bool usableName(const std::string& n) {
        return !n.empty() && n != "." && n != ".." && n.find('/') == std::string::npos && n.find('\0') == std::string::npos;
    }
    std::optional<std::string> cachedDirId(const std::string& v) {
        std::lock_guard<std::mutex> g(mu_);
        auto it = dirIds_.find(v);
        if (it == dirIds_.end()) return std::nullopt;
        return it->second;
    }
    void cacheDirId(const std::string& v, const std::string& id) { std::lock_guard<std::mutex> g(mu_); dirIds_[v] = id; }
    void cacheData(const std::string& id, const std::string& p) { std::lock_guard<std::mutex> g(mu_); dataDirs_[id] = p; }

    Storage& st_;
    const NameCryptor& nc_;
    const int shortening_;
    std::mutex mu_;
    std::unordered_map<std::string, std::string> dirIds_;     // cleartext dir path -> dirId
    std::unordered_map<std::string, std::string> dataDirs_;   // dirId -> d/xx/yyyy
    const bool readOnly_;
};

class CryptomatorVault final : public Vault, private EngineHost {
public:
    CryptomatorVault(std::shared_ptr<Storage> st, Masterkey mk, const VaultConfig& cfg, bool readOnly)
        : st_(std::move(st)), mk_(std::move(mk)), cfg_(cfg), readOnly_(readOnly), nc_(mk_),
          fmt_(mk_, cfg.cipherCombo == "SIV_GCM" ? Combo::SivGcm : Combo::SivCtrMac),
          tree_(*st_, nc_, cfg.shorteningThreshold, readOnly),
          engine_(*st_, fmt_, *this, readOnly, batchWrite_) {}
    ~CryptomatorVault() override { close(); }

    VaultFormat format() const override { return VaultFormat::Cryptomator; }
    bool readOnly() const override { return readOnly_; }

    // ---- namespace --------------------------------------------------------
    bool listDirectory(const std::string& path, std::vector<DirEntry>& out) override {
        try {
            Lifecycle::Op op(life_);
            std::shared_lock<std::shared_mutex> ns(ns_);
            std::string dirId;
            if (!tree_.resolveDirId(normalizePath(path), dirId)) return false;
            out.clear();
            for (Node& n : tree_.listByDirId(dirId)) {
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
            std::string n = normalizePath(path);
            std::unique_lock<std::shared_mutex> ns(ns_);
            if (auto existing = tree_.resolve(n)) return existing->isDir;
            std::string parentPath = parentOf(n), name = nameOf(n);
            std::string parentId;
            if (!tree_.resolveDirId(parentPath, parentId)) return false;
            std::string parentPhys = tree_.physicalFolderForDirId(parentId);
            ensureDirIdBackup(parentPhys, parentId);
            std::string newId = newUuid();
            std::string cipher = nc_.encryptFilename(name, parentId);
            std::string nodePath = createNodeFolder(parentPhys, cipher);
            if (!st_->writeWhole(joinPath(nodePath, kDirFile), (const uint8_t*)newId.data(), newId.size())) {
                st_->remove(nodePath);
                return false;
            }
            std::string newPhys = tree_.createPhysicalFolderForDirId(newId);
            writeDirIdBackup(newPhys, newId);
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
            std::string newParentId;
            if (!tree_.resolveDirId(newParent, newParentId)) return false;
            std::string newParentPhys = tree_.physicalFolderForDirId(newParentId);
            std::string full = nc_.encryptFilename(newName, newParentId) + kC9r;
            const bool newShort = (int)full.size() > tree_.shortening();
            std::string newNodePath = joinPath(newParentPhys, newShort ? shortNameFor(full) : full);
            std::string newContents = newNodePath;
            const std::string oldNodePath = node->nodePath, oldContents = node->contentsPath;

            if (!node->shortened && !newShort) {
                if (oldNodePath != newNodePath && !st_->rename(oldNodePath, newNodePath)) return false;
            } else if (node->isDir) {
                if (node->shortened && !newShort) st_->remove(joinPath(oldNodePath, kNameFile));
                if (oldNodePath != newNodePath && !st_->rename(oldNodePath, newNodePath)) return false;
                if (newShort && !st_->writeWhole(joinPath(newNodePath, kNameFile), (const uint8_t*)full.data(), full.size())) return false;
            } else if (!node->shortened && newShort) {
                if (!st_->mkdir(newNodePath)) return false;
                if (!st_->writeWhole(joinPath(newNodePath, kNameFile), (const uint8_t*)full.data(), full.size())) return false;
                newContents = joinPath(newNodePath, kContentsFile);
                if (!st_->rename(oldNodePath, newContents)) return false;
            } else if (node->shortened && !newShort) {
                if (!st_->rename(oldContents, newNodePath)) return false;
                st_->remove(oldNodePath);
            } else {   // shortened -> shortened
                if (!st_->writeWhole(joinPath(oldNodePath, kNameFile), (const uint8_t*)full.data(), full.size())) return false;
                if (oldNodePath != newNodePath && !st_->rename(oldNodePath, newNodePath)) return false;
                newContents = joinPath(newNodePath, kContentsFile);
            }
            remapPending(oldN, newN, oldNodePath, newNodePath, node->isDir ? std::string() : newContents);
            tree_.invalidate(oldParent);
            tree_.invalidate(newParent);
            if (node->isDir) tree_.invalidate(oldN);
            return true;
        } catch (const std::exception& e) {
            logMsg(LogLevel::Debug, TAG, std::string("renameFile failed: ") + e.what());
            return false;
        }
    }

    bool deleteFile(const std::string& path) override {
        if (readOnly_) return false;
        try {
            Lifecycle::Op op(life_);
            std::string n = normalizePath(path);
            engine_.invalidateRead(n);
            std::unique_lock<std::shared_mutex> ns(ns_);
            auto node = tree_.resolve(n);
            if (!node) return false;
            dropPending(n);
            if (node->isDir) {
                try { deleteDirContents(tree_.readDirId(node->dirIdFile), 0); }
                catch (const std::exception& e) {
                    logMsg(LogLevel::Warn, TAG, std::string("deleteFile: backing directory already missing or unreadable: ") + e.what());
                }
                st_->remove(node->nodePath);
            } else {
                st_->remove(node->shortened ? node->nodePath : node->contentsPath);
            }
            if (!batchDelete_ && !batchWrite_) tree_.invalidate(parentOf(n));
            return true;
        } catch (const std::exception& e) {
            logMsg(LogLevel::Warn, TAG, std::string("deleteFile failed: ") + e.what());
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
            bool ok;
            if (node->isDir) ok = st_->setMtime(node->nodePath, epochSeconds);
            else {
                ok = st_->setMtime(node->contentsPath, epochSeconds);
                if (node->shortened) st_->setMtime(node->nodePath, epochSeconds);
            }
            if (ok) tree_.invalidate(parentOf(n));
            return ok;
        } catch (const std::exception&) { return false; }
    }

    int64_t getFileSize(const std::string& path) override {
        try {
            Lifecycle::Op op(life_);
            std::shared_lock<std::shared_mutex> ns(ns_);
            auto node = tree_.resolve(normalizePath(path));
            if (!node || node->isDir) return -1;
            st_->ensureContentReady(node->contentsPath);
            DirEntry de;
            int64_t phys = st_->stat(node->contentsPath, de) ? de.size : node->size;
            return fmt_.cleartextSize(phys);
        } catch (const std::exception&) { return -1; }
    }

    int64_t getFolderSize(const std::string& path) override {
        try {
            Lifecycle::Op op(life_);
            std::shared_lock<std::shared_mutex> ns(ns_);
            std::string dirId;
            if (!tree_.resolveDirId(normalizePath(path), dirId)) return 0;
            return folderSizeById(dirId, 0);
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
            return engine_.writeBackStream(normalizePath(path), src, p);
        } catch (const std::exception&) { return false; }
    }
    bool extractFile(const std::string& path, const std::string& dest, Progress* p) override {
        try { Lifecycle::Op op(life_); return engine_.extractFile(path, dest, p); }
        catch (const std::exception&) { return false; }
    }

    // ---- batching / caches ------------------------------------------------
    void beginBatchWrite() override { batchWrite_ = true; }
    void endBatchWrite() override {
        batchWrite_ = false;
        std::map<std::string, std::string> writes;
        { std::lock_guard<std::mutex> g(pmu_); writes.swap(pending_); }
        try {
            Lifecycle::Op op(life_);
            for (auto& kv : writes) publish(kv.first, kv.second);
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
        return {
            {InfoItem::Kind::Int, "vaultFormat", std::to_string(cfg_.vaultFormat)},
            {InfoItem::Kind::Str, "cipherCombo", cfg_.cipherCombo},
            {InfoItem::Kind::Int, "shorteningThreshold", std::to_string(cfg_.shorteningThreshold)},
            {InfoItem::Kind::Bool, "readOnly", readOnly_ ? "true" : "false"},
        };
    }

    KeyExport exportKeys() override {
        KeyExport k;
        k.format = VaultFormat::Cryptomator;
        k.fields.emplace_back("masterkey", mk_.raw().bytes());
        k.strings.emplace_back("vaultFormat", std::to_string(cfg_.vaultFormat));
        k.strings.emplace_back("cipherCombo", cfg_.cipherCombo);
        k.strings.emplace_back("shorteningThreshold", std::to_string(cfg_.shorteningThreshold));
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
        physical = n->contentsPath;
        return true;
    }

    std::string prepareForWrite(const std::string& vpath) override {
        std::unique_lock<std::shared_mutex> ns(ns_);
        std::string n = normalizePath(vpath);
        std::string parentPath = parentOf(n), name = nameOf(n);
        std::string parentId;
        if (!tree_.resolveDirId(parentPath, parentId)) throw Error(Err::NotFound, "Folder not found: " + parentPath);
        std::string parentPhys = tree_.physicalFolderForDirId(parentId);
        ensureDirIdBackup(parentPhys, parentId);
        std::string phys;
        if (auto existing = tree_.resolve(n)) {
            if (existing->isDir) throw Error(Err::Exists, "a folder with that name already exists");
            phys = existing->contentsPath;
        } else {
            phys = createNewFileNode(parentPhys, nc_.encryptFilename(name, parentId));
        }
        st_->markWritePending(phys);
        { std::lock_guard<std::mutex> g(pmu_); pending_[n] = phys; }
        return phys;
    }

    void afterWrite(const std::string& vpath, const std::string& physical) override {
        std::string n = normalizePath(vpath);
        std::string captured = physical;
        { std::lock_guard<std::mutex> g(pmu_); auto it = pending_.find(n); if (it != pending_.end()) { captured = it->second; pending_.erase(it); } }
        publish(n, captured);
        tree_.invalidate(parentOf(n));
    }

    void abortedWrite(const std::string& vpath, const std::string& physical) override {
        std::string n = normalizePath(vpath);
        std::unique_lock<std::shared_mutex> ns(ns_);
        { std::lock_guard<std::mutex> g(pmu_); pending_.erase(n); }
        std::string parent = parentOf(physical);
        if (nameOf(physical) == kContentsFile && endsWith(nameOf(parent), kC9s)) st_->remove(parent);
        else st_->remove(physical);
        tree_.invalidate(parentOf(n));
    }

    // ---- helpers ------------------------------------------------------------
    void publish(const std::string& vpath, const std::string& physical) {
        try { st_->publishWrite(physical, endsWith(vpath, ".tmp") && !batchWrite_); }
        catch (const std::exception& e) { logMsg(LogLevel::Warn, TAG, std::string("publish failed: ") + e.what()); }
    }

    std::string createNodeFolder(const std::string& parentPhys, const std::string& cipher) {
        std::string full = cipher + kC9r;
        if ((int)full.size() <= tree_.shortening()) {
            std::string p = joinPath(parentPhys, full);
            if (!st_->mkdir(p)) throw Error(Err::Io, "Could not create " + full);
            return p;
        }
        std::string p = joinPath(parentPhys, shortNameFor(full));
        if (!st_->mkdir(p)) throw Error(Err::Io, "Could not create shortened folder");
        if (!st_->writeWhole(joinPath(p, kNameFile), (const uint8_t*)full.data(), full.size())) throw Error(Err::Io, "Could not create name.c9s");
        return p;
    }

    std::string createNewFileNode(const std::string& parentPhys, const std::string& cipher) {
        std::string full = cipher + kC9r;
        if ((int)full.size() <= tree_.shortening()) {
            std::string p = joinPath(parentPhys, full);
            if (!st_->createFile(p)) throw Error(Err::Io, "Could not create " + full);
            return p;
        }
        std::string wrapper = joinPath(parentPhys, shortNameFor(full));
        if (!st_->mkdir(wrapper)) throw Error(Err::Io, "Could not create shortened folder");
        if (!st_->writeWhole(joinPath(wrapper, kNameFile), (const uint8_t*)full.data(), full.size())) throw Error(Err::Io, "Could not create name.c9s");
        std::string contents = joinPath(wrapper, kContentsFile);
        if (!st_->createFile(contents)) throw Error(Err::Io, "Could not create contents.c9r");
        return contents;
    }

    // dirid.c9r holds the directory's OWN id, encrypted like a regular file
    // (cryptolib DirectoryIdBackup). The Kotlin version stored the parent's id.
    void writeDirIdBackup(const std::string& physFolder, const std::string& ownDirId) {
        try {
            if (!writeDirIdBackupFile(*st_, fmt_, physFolder, ownDirId))
                logMsg(LogLevel::Warn, TAG, "could not write dirid.c9r in " + physFolder);
        } catch (const std::exception& e) {
            logMsg(LogLevel::Warn, TAG, std::string("writeDirIdBackup failed: ") + e.what());
        }
    }
    // The root directory (empty id) gets a backup too, exactly like official cryptofs: a header-only file.
    void ensureDirIdBackup(const std::string& physFolder, const std::string& dirId) {
        DirEntry de;
        if (!st_->stat(joinPath(physFolder, kDirIdBackup), de)) writeDirIdBackup(physFolder, dirId);
    }

    // Removes a directory's backing folder and, recursively, the backing
    // folders of every sub-directory (they live elsewhere under d/, so
    // deleting only the node would orphan them).
    void deleteDirContents(const std::string& dirId, int depth) {
        if (depth > 256) throw Error(Err::InvalidVault, "directory nesting too deep");
        std::string phys = tree_.dataPathFor(dirId);
        std::vector<DirEntry> children;
        if (st_->list(phys, children)) {
            for (const DirEntry& c : children) {
                if (!c.isDir || !(endsWith(c.name, kC9r) || endsWith(c.name, kC9s))) continue;
                std::string ptr = joinPath(joinPath(phys, c.name), kDirFile);
                DirEntry de;
                if (!st_->stat(ptr, de)) continue;
                try { deleteDirContents(tree_.readDirId(ptr), depth + 1); } catch (const std::exception&) {}
            }
        }
        st_->remove(phys);
    }

    int64_t folderSizeById(const std::string& dirId, int depth) {
        if (depth > 256) return 0;
        int64_t total = 0;
        for (Node& n : tree_.listByDirId(dirId)) {
            if (n.isDir) {
                try { total += folderSizeById(tree_.readDirId(n.dirIdFile), depth + 1); } catch (const Error&) {}
            } else total += fmt_.cleartextSize(n.size);
        }
        return total;
    }

    void dropPending(const std::string& n) {
        std::lock_guard<std::mutex> g(pmu_);
        std::string prefix = n + "/";
        for (auto it = pending_.begin(); it != pending_.end();)
            if (it->first == n || startsWith(it->first, prefix.c_str())) it = pending_.erase(it); else ++it;
    }

    void remapPending(const std::string& oldV, const std::string& newV, const std::string& oldNode,
                      const std::string& newNode, const std::string& newFileContents) {
        std::lock_guard<std::mutex> g(pmu_);
        std::map<std::string, std::string> moved;
        std::string prefix = oldV + "/";
        for (auto it = pending_.begin(); it != pending_.end();) {
            bool self = it->first == oldV;
            if (self || startsWith(it->first, prefix.c_str())) {
                std::string key = newV + it->first.substr(oldV.size());
                std::string phys = it->second;
                if (self && !newFileContents.empty()) phys = newFileContents;
                else if (startsWith(phys, oldNode.c_str())) phys = newNode + phys.substr(oldNode.size());
                moved[key] = phys;
                it = pending_.erase(it);
            } else ++it;
        }
        for (auto& kv : moved) pending_[kv.first] = kv.second;
    }

    std::shared_ptr<Storage> st_;
    Masterkey mk_;
    VaultConfig cfg_;
    const bool readOnly_;
    NameCryptor nc_;
    ContentFormat fmt_;
    Tree tree_;
    std::atomic<bool> batchWrite_{false};
    std::atomic<bool> batchDelete_{false};
    ChunkedFileEngine engine_;
    Lifecycle life_;
    std::shared_mutex ns_;
    std::mutex pmu_;
    std::map<std::string, std::string> pending_;   // cleartext path -> physical contents path
};

PlainResult plainFail(OpenStatus s, std::string msg) { PlainResult r; r.status = s; r.message = std::move(msg); return r; }

}  // namespace
}  // namespace cryptomator

// ----------------------------------------------------------- public entry --

bool looksLikeCryptomator(Storage& s) {
    DirEntry de;
    return s.stat(cryptomator::kMasterkeyFile, de) && !de.isDir;
}

OpenResult openCryptomator(std::shared_ptr<Storage> s, const uint8_t* pw, size_t pwLen, bool readOnly,
                           const HostEnv&, const StorageFactory& factory) {
    using namespace cryptomator;
    OpenResult res;
    auto fail = [&](OpenStatus st, std::string msg) { res.status = st; res.message = std::move(msg); return std::move(res); };

    DirEntry de;
    if (!s->stat(kMasterkeyFile, de) || de.isDir)
        return fail(OpenStatus::InvalidVault, "No masterkey.cryptomator found \xE2\x80\x94 this doesn't look like a Cryptomator vault.");
    if (!s->stat(kDataDir, de) || !de.isDir)
        return fail(OpenStatus::InvalidVault, "Vault is missing its 'd' data directory.");
    Bytes raw;
    if (!s->readWhole(kMasterkeyFile, raw)) return fail(OpenStatus::InvalidVault, "Could not read masterkey.cryptomator");

    Masterkey mk;
    MasterkeyFile parsed;
    try {
        parsed = MasterkeyFile::parse(std::string(raw.begin(), raw.end()));
        mk = unlockMasterkeyCompat(parsed, pw, pwLen);
    } catch (const Error& e) {
        if (e.code() == Err::WrongPassword) return fail(OpenStatus::WrongPassword, e.what());
        return fail(OpenStatus::InvalidVault, std::string("Failed to unlock masterkey: ") + e.what());
    } catch (const std::exception& e) {
        return fail(OpenStatus::InvalidVault, std::string("Failed to unlock masterkey: ") + e.what());
    }

    VaultConfig cfg;
    if (s->stat(kVaultFile, de)) {
        Bytes jwt;
        if (!s->readWhole(kVaultFile, jwt)) return fail(OpenStatus::InvalidVault, "Could not read vault.cryptomator");
        try { cfg = verifyVaultConfig(std::string(jwt.begin(), jwt.end()), mk); }
        catch (const Error& e) { return fail(OpenStatus::InvalidVault, e.what()); }
        // A format 7 vault has no vault.cryptomator at all, so a config can only describe format 8.
        if (cfg.vaultFormat < 8)
            return fail(OpenStatus::InvalidVault, "Vault format " + std::to_string(cfg.vaultFormat) + " is not supported (only 7 and 8 are).");
        if (cfg.vaultFormat > 8)
            return fail(OpenStatus::InvalidVault, "Vault format " + std::to_string(cfg.vaultFormat) + " was created by a newer version of Cryptomator and is not supported.");
    } else {
        // No vault.cryptomator: only a genuine format 7 masterkey file may be treated as one. Anything else
        // would be opened with the wrong cipher/layout and writes would corrupt it (official Android applies
        // the same masterkey-version gate: assertLegacyVaultVersionIsSupported).
        if (parsed.version == 7) {
            cfg.vaultFormat = 7; cfg.cipherCombo = "SIV_CTRMAC"; cfg.shorteningThreshold = kDefaultShortening;
        } else if (parsed.version >= 8) {
            return fail(OpenStatus::InvalidVault,
                        "vault.cryptomator is missing. This is a format 8 vault and cannot be opened without it. "
                        "If the vault is stored with a cloud provider, wait for it to finish syncing and try again.");
        } else {
            return fail(OpenStatus::InvalidVault,
                        "Vault format " + std::to_string(parsed.version) + " is not supported (only 7 and 8 are). "
                        "Open it once in Cryptomator to migrate it.");
        }
    }

    std::shared_ptr<Storage> sessionStorage = s;
    try { if (factory) { auto f = factory(); if (f) sessionStorage = std::move(f); } }
    catch (const std::exception& e) { return fail(OpenStatus::InvalidVault, std::string("Could not open vault: ") + e.what()); }
    try {
        res.vault = std::make_unique<CryptomatorVault>(sessionStorage, std::move(mk), cfg, readOnly);
        res.status = OpenStatus::Ok;
        return res;
    } catch (const std::exception& e) {
        if (sessionStorage != s) sessionStorage->close();
        return fail(OpenStatus::InvalidVault, std::string("Could not open vault: ") + e.what());
    }
}

PlainResult createCryptomator(Storage& s, const uint8_t* pw, size_t pwLen) {
    using namespace cryptomator;
    try {
        std::vector<DirEntry> existing;
        if (s.list("", existing) && !existing.empty()) return plainFail(OpenStatus::InvalidVault, "Selected folder is not empty.");
        Masterkey mk(Secret(crypto::randomKeyBytes(64)));
        Secret npw = normalizedPassphrase(pw, pwLen);
        std::string mkJson = lockMasterkey(mk, npw.data(), npw.size(), 999);
        if (!s.writeWhole(kMasterkeyFile, (const uint8_t*)mkJson.data(), mkJson.size()))
            return plainFail(OpenStatus::InvalidVault, "Could not create masterkey.cryptomator");
        std::string jwt = createVaultConfig(kCurrentVaultFormat, kCurrentCipherCombo, kDefaultShortening, mk, newUuid());
        if (!s.writeWhole(kVaultFile, (const uint8_t*)jwt.data(), jwt.size()))
            return plainFail(OpenStatus::InvalidVault, "Could not create vault.cryptomator");
        NameCryptor nc(mk);
        std::string h = nc.hashDirectoryId("");
        if (!s.mkdir(kDataDir)) return plainFail(OpenStatus::InvalidVault, "Could not create 'd' directory");
        std::string lvl1 = joinPath(kDataDir, h.substr(0, 2));
        if (!s.mkdir(lvl1) || !s.mkdir(joinPath(lvl1, h.substr(2))))
            return plainFail(OpenStatus::InvalidVault, "Could not create data subdirectory");
        {
            ContentFormat fmt(mk, kCurrentCipherCombo == std::string("SIV_GCM") ? Combo::SivGcm : Combo::SivCtrMac);
            if (!writeDirIdBackupFile(s, fmt, joinPath(lvl1, h.substr(2)), ""))
                logMsg(LogLevel::Warn, TAG, "could not write the root dirid.c9r");
        }
        PlainResult ok;
        ok.status = OpenStatus::Ok;
        return ok;
    } catch (const std::exception& e) {
        return plainFail(OpenStatus::InvalidVault, std::string("Failed to create vault: ") + e.what());
    }
}

PlainResult changeCryptomatorPassword(Storage& s, const uint8_t* oldPw, size_t oldLen, const uint8_t* newPw, size_t newLen) {
    using namespace cryptomator;
    DirEntry de;
    if (!s.stat(kMasterkeyFile, de) || de.isDir)
        return plainFail(OpenStatus::InvalidVault, "No masterkey.cryptomator found \xE2\x80\x94 this doesn't look like a Cryptomator vault.");
    Bytes raw;
    if (!s.readWhole(kMasterkeyFile, raw)) return plainFail(OpenStatus::InvalidVault, "Could not read masterkey.cryptomator");
    try {
        MasterkeyFile parsed = MasterkeyFile::parse(std::string(raw.begin(), raw.end()));
        Masterkey mk = unlockMasterkeyCompat(parsed, oldPw, oldLen);
        Secret npw = normalizedPassphrase(newPw, newLen);
        // Keep the vault's own scrypt cost (never silently downgrade it), like official changePassphrase.
        std::string json = lockMasterkey(mk, npw.data(), npw.size(), parsed.version,
                                         (uint32_t)parsed.scryptCostParam, (uint32_t)parsed.scryptBlockSize);
        // Official keeps the previous key file as masterkey.cryptomator.<first 4 bytes of its SHA-256, hex>.bkup
        {
            Bytes digest = crypto::hash(crypto::Md::Sha256, raw.data(), raw.size());
            std::string hex = toHex(digest.data(), 4);
            for (char& c : hex) c = (char)std::toupper((unsigned char)c);   // Guava base16 is upper-case
            std::string bkup = std::string(kMasterkeyFile) + "." + hex + ".bkup";
            DirEntry be;
            if (!s.stat(bkup, be) && !s.writeWhole(bkup, raw.data(), raw.size()))
                logMsg(LogLevel::Warn, TAG, "could not write " + bkup);
        }
        if (!s.writeWholeAtomic(kMasterkeyFile, (const uint8_t*)json.data(), json.size()))
            return plainFail(OpenStatus::InvalidVault, "Could not write masterkey.cryptomator");
        PlainResult ok;
        ok.status = OpenStatus::Ok;
        return ok;
    } catch (const Error& e) {
        return plainFail(e.code() == Err::WrongPassword ? OpenStatus::WrongPassword : OpenStatus::InvalidVault, e.what());
    } catch (const std::exception& e) {
        return plainFail(OpenStatus::InvalidVault, e.what());
    }
}

}  // namespace fv
