// Cryptomator vault: directory tree, session (fv::Vault) and the open /
// create / change-password entry points.
#include <cctype>
#include <cstddef>
#include <cstring>
#include <algorithm>
#include <map>
#include <mutex>
#include <optional>
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
constexpr const char* kSymlinkFile = "symlink.c9r";
// cryptofs Constants.MAX_SYMLINK_LENGTH. Official checks it in characters when creating a link but in BYTES when
// reading one back, and a byte is never worth less than a UTF-16 unit -- so the byte count is the binding limit,
// and it is the one we enforce: a link we create is always one official (and we) can read.
constexpr size_t kMaxSymlinkLength = 32767;

struct Node {
    bool isDir = false;
    bool shortened = false;
    std::string name;          // cleartext
    std::string nodePath;      // the .c9r file/folder or the .c9s wrapper folder
    std::string contentsPath;  // file: where the encrypted bytes are; dir: == nodePath
    std::string dirIdFile;     // dir: path of its dir.c9r pointer
    bool isSymlink = false;    // a node folder holding symlink.c9r instead of dir.c9r / contents.c9r
    std::string symlinkFile;   // symlink: path of its symlink.c9r (target, encrypted like file content)
    int64_t size = 0;          // file: physical size of the contents; symlink: physical size of symlink.c9r
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

// A small cleartext (at most one chunk) encrypted like regular file content: header + one chunk.
static bool writeSmallEncryptedFile(Storage& st, const ContentFormat& fmt, const std::string& path,
                                    const std::string& plain) {
    Bytes file;
    auto key = fmt.newHeader(file);
    Bytes enc(fmt.encryptedSize(plain.size()));
    fmt.encrypt(*key, 0, (const uint8_t*)plain.data(), plain.size(), enc.data());
    file.insert(file.end(), enc.begin(), enc.end());
    return st.writeWhole(path, file.data(), file.size());
}

// dirid.c9r = the directory's OWN id encrypted like a regular file (cryptolib DirectoryIdBackup).
static bool writeDirIdBackupFile(Storage& st, const ContentFormat& fmt, const std::string& physFolder,
                                 const std::string& ownDirId) {
    return writeSmallEncryptedFile(st, fmt, joinPath(physFolder, kDirIdBackup), ownDirId);
}

// Inverse of writeSmallEncryptedFile. [maxPlain] bounds the cleartext (the official symlink reader refuses
// anything longer); false on a short/foreign header, an authentication failure or an oversized cleartext.
static bool readSmallEncryptedFile(Storage& st, const ContentFormat& fmt, const std::string& path,
                                   size_t maxPlain, std::string& out) {
    const size_t hdr = fmt.headerSize();
    DirEntry probe;
    if (st.stat(path, probe) && probe.size > (int64_t)(hdr + fmt.encryptedSize(maxPlain))) return false;   // never slurp a huge file
    Bytes enc;
    if (!st.readWhole(path, enc)) return false;
    if (enc.size() < hdr) return false;
    const size_t bodyLen = enc.size() - hdr;
    try {
        const size_t plainLen = fmt.decryptedSize(bodyLen);   // throws on a torn trailing chunk
        if (plainLen > maxPlain) return false;
        auto key = fmt.decodeHeader(enc.data(), enc.size());  // throws unless the header authenticates
        if (!key) return false;
        Bytes plain(plainLen);
        if (plainLen > 0) fmt.decrypt(*key, 0, enc.data() + hdr, bodyLen, plain.data());   // throws on any bad tag
        out.assign(plain.begin(), plain.end());
        return true;
    } catch (const Error&) { return false; }
}

// True if [s] is well-formed UTF-8 (no overlongs, no surrogates, nothing above U+10FFFF).
static bool validUtf8(const std::string& s) {
    size_t i = 0, n = s.size();
    while (i < n) {
        unsigned char c = (unsigned char)s[i];
        size_t len = c < 0x80 ? 1 : (c >= 0xC2 && c <= 0xDF) ? 2 : (c >= 0xE0 && c <= 0xEF) ? 3 : (c >= 0xF0 && c <= 0xF4) ? 4 : 0;
        if (len == 0 || i + len > n) return false;
        for (size_t k = 1; k < len; k++) if (((unsigned char)s[i + k] & 0xC0) != 0x80) return false;
        if (len == 3) {
            unsigned char c1 = (unsigned char)s[i + 1];
            if ((c == 0xE0 && c1 < 0xA0) || (c == 0xED && c1 > 0x9F)) return false;
        } else if (len == 4) {
            unsigned char c1 = (unsigned char)s[i + 1];
            if ((c == 0xF0 && c1 < 0x90) || (c == 0xF4 && c1 > 0x8F)) return false;
        }
        i += len;
    }
    return true;
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

    // Everything in the directory that decodes to a node -- files, folders AND symlinks (callers filter).
    // [hidden], when given, receives the number of physical entries that exist but did not become a node:
    // sync-conflict copies, names that fail authentication, half-synced or broken nodes. Dot-files, the
    // internal dir.c9r/dirid.c9r and foreign files (no .c9r/.c9s suffix) are not counted -- the official
    // client ignores those silently as well.
    std::vector<Node> listByDirId(const std::string& dirId, int* hidden = nullptr) {
        int hid = 0;
        std::vector<Node> out = listByDirIdImpl(dirId, hid);
        {
            std::lock_guard<std::mutex> g(mu_);
            hiddenByDir_[dirId] = hid;
        }
        if (hidden) *hidden = hid;
        return out;
    }

    // Hidden-entry count of the most recent listing of [dirId] (-1 if it was never listed).
    int lastHiddenCount(const std::string& dirId) {
        std::lock_guard<std::mutex> g(mu_);
        auto it = hiddenByDir_.find(dirId);
        return it == hiddenByDir_.end() ? -1 : it->second;
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
                DirEntry ptr, contents, link;
                if (st_.stat(joinPath(nodePath, kDirFile), ptr)) {
                    n.isDir = true; n.dirIdFile = joinPath(nodePath, kDirFile); n.size = 0;
                    return n;
                }
                if (st_.stat(joinPath(nodePath, kSymlinkFile), link)) { markSymlink(n, nodePath, link); return n; }   // official order: dir, symlink, contents
                if (st_.stat(joinPath(nodePath, kContentsFile), contents)) {
                    n.contentsPath = joinPath(nodePath, kContentsFile);
                    n.size = contents.size; n.mtimeMs = contents.mtimeMs;
                    return n;
                }
                return std::nullopt;
            }
            if (de.isDir) {
                DirEntry ptr, link;
                if (st_.stat(joinPath(nodePath, kDirFile), ptr)) {
                    n.isDir = true; n.size = 0; n.dirIdFile = joinPath(nodePath, kDirFile);
                } else if (st_.stat(joinPath(nodePath, kSymlinkFile), link)) {
                    markSymlink(n, nodePath, link);
                } else {
                    return std::nullopt;
                }
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
    // A node folder that holds symlink.c9r: not a file (nothing to read), not a folder (nothing to enter).
    static void markSymlink(Node& n, const std::string& nodePath, const DirEntry& link) {
        n.isDir = false; n.isSymlink = true;
        n.contentsPath = nodePath;
        n.symlinkFile = joinPath(nodePath, kSymlinkFile);
        n.size = link.size; n.mtimeMs = link.mtimeMs;
    }

    std::vector<Node> listByDirIdImpl(const std::string& dirId, int& hidden) {
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
            if (name.empty() || name == kDirFile || name == kDirIdBackup) continue;
            if (name[0] == '.') continue;   // hidden files (.DS_Store, sync temp files, ...) -- ignored like the official client
            const bool isC9s = endsWith(name, kC9s), isC9r = endsWith(name, kC9r);
            if (!isC9s && !isC9r) continue;   // foreign file: not ours, not "hidden"
            try {
                if (isC9s) {
                    if (!c.isDir) { hidden++; continue; }
                    std::string wrapper = joinPath(folder, name);
                    Bytes ln;
                    if (!st_.readWhole(joinPath(wrapper, kNameFile), ln) || ln.empty()) {
                        st_.invalidate(wrapper);
                        if (!st_.readWhole(joinPath(wrapper, kNameFile), ln) || ln.empty()) { hidden++; continue; }
                    }
                    std::string raw(ln.begin(), ln.end());
                    size_t e2 = raw.find_last_not_of(std::string(" \r\n\0", 4));
                    raw = e2 == std::string::npos ? "" : raw.substr(0, e2 + 1);
                    size_t s2 = raw.find_first_not_of(' ');
                    raw = s2 == std::string::npos ? "" : raw.substr(s2);
                    std::string cipher = endsWith(raw, kC9r) ? raw.substr(0, raw.size() - 4) : raw;
                    std::string clear = nc_.decryptFilename(cipher, dirId);
                    if (!usableName(clear)) { hidden++; continue; }
                    DirEntry ptr, link;
                    Node n;
                    n.shortened = true; n.name = clear; n.nodePath = wrapper; n.wrapperMtimeMs = c.mtimeMs;
                    if (st_.stat(joinPath(wrapper, kDirFile), ptr)) {
                        n.isDir = true; n.contentsPath = wrapper; n.dirIdFile = joinPath(wrapper, kDirFile); n.mtimeMs = c.mtimeMs;
                    } else if (st_.stat(joinPath(wrapper, kSymlinkFile), link)) {
                        markSymlink(n, wrapper, link);
                    } else {
                        DirEntry contents;
                        if (!st_.stat(joinPath(wrapper, kContentsFile), contents)) {
                            st_.invalidate(wrapper);
                            if (!st_.stat(joinPath(wrapper, kContentsFile), contents)) {
                                logMsg(LogLevel::Warn, TAG, "Shortened node '" + name + "' has neither dir.c9r, symlink.c9r nor contents.c9r -- skipping");
                                hidden++;
                                continue;
                            }
                        }
                        n.contentsPath = joinPath(wrapper, kContentsFile);
                        n.size = contents.size; n.mtimeMs = contents.mtimeMs;
                    }
                    out.push_back(std::move(n));
                } else {
                    std::string clear = nc_.decryptFilename(name.substr(0, name.size() - 4), dirId);
                    if (!usableName(clear)) { hidden++; continue; }
                    Node n;
                    n.name = clear; n.nodePath = joinPath(folder, name); n.contentsPath = n.nodePath;
                    n.size = c.size; n.mtimeMs = c.mtimeMs;
                    if (c.isDir) {
                        DirEntry ptr, link;
                        if (st_.stat(joinPath(n.nodePath, kDirFile), ptr)) {
                            n.isDir = true; n.size = 0; n.dirIdFile = joinPath(n.nodePath, kDirFile);
                        } else if (st_.stat(joinPath(n.nodePath, kSymlinkFile), link)) {
                            markSymlink(n, n.nodePath, link);
                        } else {
                            logMsg(LogLevel::Warn, TAG, "Directory node '" + name + "' has neither dir.c9r nor symlink.c9r -- skipping");
                            hidden++;
                            continue;
                        }
                    }
                    out.push_back(std::move(n));
                }
            } catch (const Error& e) {
                // Most often a sync-conflict copy ("<name> (1).c9r", "<name>.sync-conflict-....c9r"): its base64
                // part no longer authenticates. Counted so the UI can say "N entries are not shown".
                hidden++;
                logMsg(LogLevel::Debug, TAG, "Skipping unreadable child '" + name + "': " + e.what());
            }
        }
        return out;
    }

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
    std::unordered_map<std::string, int> hiddenByDir_;        // dirId -> hidden entries seen by the last listing
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
            auto resolvedDir = resolveSymlinkPathLocked(normalizePath(path));
            if (!resolvedDir) return false;
            std::string dirId;
            if (!tree_.resolveDirId(*resolvedDir, dirId)) return false;
            out.clear();
            for (Node& n : tree_.listByDirId(dirId)) {
                if (n.isSymlink) continue; // Browser merges links explicitly; scanners/exporters never see them.
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

    // ---- symlinks (cryptofs Symlinks / CiphertextFilePath.getSymlinkFilePath) -----------------------------
    // A symlink is a node folder "<encrypted name>.c9r/" (or the .c9s wrapper for long names) that holds
    // symlink.c9r: the link target, UTF-8, encrypted exactly like file content. Path access follows relative
    // targets within this vault; absolute targets are refused and link-node operations remain no-follow.
    bool listSymlinks(const std::string& path, std::vector<DirEntry>& out) override {
        try {
            Lifecycle::Op op(life_);
            std::shared_lock<std::shared_mutex> ns(ns_);
            auto resolvedDir = resolveSymlinkPathLocked(normalizePath(path));
            if (!resolvedDir) return false;
            std::string dirId;
            if (!tree_.resolveDirId(*resolvedDir, dirId)) return false;
            out.clear();
            for (Node& n : tree_.listByDirId(dirId)) {
                if (!n.isSymlink) continue;
                DirEntry e;
                e.name = n.name; e.isSymlink = true;
                auto targetPath = resolveSymlinkPathLocked(joinPath(*resolvedDir, n.name));
                if (targetPath) {
                    std::string targetDirId;
                    e.isDir = tree_.resolveDirId(*targetPath, targetDirId);
                }
                e.size = e.isDir ? 0 : fmt_.cleartextSize(n.size); // link target length for file/broken links
                e.mtimeMs = n.mtimeMs;
                out.push_back(std::move(e));
            }
            return true;
        } catch (const std::exception& e) {
            logMsg(LogLevel::Debug, TAG, std::string("listSymlinks failed: ") + e.what());
            return false;
        }
    }

    std::optional<std::string> readSymlink(const std::string& path) override {
        try {
            Lifecycle::Op op(life_);
            std::shared_lock<std::shared_mutex> ns(ns_);
            std::string input = normalizePath(path);
            auto parentResolved = resolveSymlinkPathLocked(parentOf(input));
            if (!parentResolved) return std::nullopt;
            auto node = tree_.resolve(joinPath(*parentResolved, nameOf(input)));
            if (!node || !node->isSymlink) return std::nullopt;
            st_->ensureContentReady(node->symlinkFile);
            std::string target;
            if (!readSmallEncryptedFile(*st_, fmt_, node->symlinkFile, kMaxSymlinkLength, target)) return std::nullopt;
            if (!validUtf8(target)) return std::nullopt;   // would not survive the JNI boundary; never hand it out
            return target;
        } catch (const std::exception& e) {
            logMsg(LogLevel::Debug, TAG, std::string("readSymlink failed: ") + e.what());
            return std::nullopt;
        }
    }

    bool createSymlink(const std::string& path, const std::string& target) override {
        if (readOnly_) return false;
        // 1..32767 bytes of valid UTF-8 without NUL. (Official would also store an empty or malformed string, or
        // one that is short in characters but over 32767 bytes, but nothing could read or show it afterwards.)
        if (target.empty() || target.size() > kMaxSymlinkLength || !validUtf8(target) || target.find('\0') != std::string::npos) return false;
        try {
            Lifecycle::Op op(life_);
            std::string input = normalizePath(path);
            if (input.empty()) return false;
            std::unique_lock<std::shared_mutex> ns(ns_);
            auto parentResolved = resolveSymlinkPathLocked(parentOf(input));
            if (!parentResolved) return false;
            std::string n = joinPath(*parentResolved, nameOf(input));
            if (tree_.resolve(n)) return false;   // official assertNonExisting: never overwrite anything
            std::string parentPath = parentOf(n), name = nameOf(n);
            std::string parentId;
            if (!tree_.resolveDirId(parentPath, parentId)) return false;
            std::string parentPhys = tree_.physicalFolderForDirId(parentId);
            ensureDirIdBackup(parentPhys, parentId);
            // Official order: node folder, then symlink.c9r, and only then name.c9s -- until the last step the
            // node is invisible (no type file / no name), so an interrupted sync never shows a half link.
            std::string full = nc_.encryptFilename(name, parentId) + kC9r;
            const bool isShort = (int)full.size() > tree_.shortening();
            std::string nodePath = joinPath(parentPhys, isShort ? shortNameFor(full) : full);
            if (!st_->mkdir(nodePath)) return false;
            if (!writeSmallEncryptedFile(*st_, fmt_, joinPath(nodePath, kSymlinkFile), target) ||
                (isShort && !st_->writeWhole(joinPath(nodePath, kNameFile), (const uint8_t*)full.data(), full.size()))) {
                st_->remove(nodePath);
                tree_.invalidate(parentPath);
                return false;
            }
            tree_.invalidate(parentPath);
            return true;
        } catch (const std::exception& e) {
            logMsg(LogLevel::Warn, TAG, std::string("createSymlink failed: ") + e.what());
            return false;
        }
    }

    int hiddenEntryCount(const std::string& path) override {
        try {
            Lifecycle::Op op(life_);
            std::shared_lock<std::shared_mutex> ns(ns_);
            auto resolvedDir = resolveSymlinkPathLocked(normalizePath(path));
            if (!resolvedDir) return -1;
            std::string dirId;
            if (!tree_.resolveDirId(*resolvedDir, dirId)) return -1;
            int h = tree_.lastHiddenCount(dirId);
            if (h < 0) { tree_.listByDirId(dirId, &h); }
            return h;
        } catch (const std::exception&) { return -1; }
    }

    bool createDirectory(const std::string& path) override {
        if (readOnly_) return false;
        try {
            Lifecycle::Op op(life_);
            std::string n = normalizePath(path);
            std::unique_lock<std::shared_mutex> ns(ns_);
            auto resolved = resolveSymlinkPathLocked(n);
            if (!resolved) return false;
            n = *resolved;
            if (n.empty()) return true; // a shortcut resolving to the vault root
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
            std::string oldInput = normalizePath(from), newInput = normalizePath(to);
            // Do not take engine path locks while holding ns_: readers acquire them in the opposite order.
            engine_.invalidateAll();
            std::unique_lock<std::shared_mutex> ns(ns_);
            auto oldParentResolved = resolveSymlinkPathLocked(parentOf(oldInput));
            auto newParentResolved = resolveSymlinkPathLocked(parentOf(newInput));
            if (!oldParentResolved || !newParentResolved) return false;
            std::string oldN = joinPath(*oldParentResolved, nameOf(oldInput));
            std::string newN = joinPath(*newParentResolved, nameOf(newInput));
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
            } else if (node->isDir || node->isSymlink) {   // a symlink node is a folder too: move it as a whole
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
            remapPending(oldN, newN, oldNodePath, newNodePath, (node->isDir || node->isSymlink) ? std::string() : newContents);
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
            std::string input = normalizePath(path);
            // Clear cached reads before taking ns_ to preserve the engine -> namespace lock order.
            engine_.invalidateAll();
            std::unique_lock<std::shared_mutex> ns(ns_);
            auto parentResolved = resolveSymlinkPathLocked(parentOf(input));
            if (!parentResolved) return false;
            std::string n = joinPath(*parentResolved, nameOf(input));
            auto node = tree_.resolve(n);
            if (!node) return false;
            dropPending(n);
            if (node->isDir) {
                try { deleteDirContents(tree_.readDirId(node->dirIdFile), 0); }
                catch (const std::exception& e) {
                    logMsg(LogLevel::Warn, TAG, std::string("deleteFile: backing directory already missing or unreadable: ") + e.what());
                }
                st_->remove(node->nodePath);
            } else if (node->isSymlink) {
                st_->remove(node->nodePath);   // the node folder incl. symlink.c9r (and name.c9s); the target is never touched
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
            // Follow symlinks in parent components, but not the final component:
            // the timestamp belongs to the link's symlink.c9r, not its target.
            auto parentResolved = resolveSymlinkPathLocked(parentOf(n));
            if (!parentResolved) return false;
            n = joinPath(*parentResolved, nameOf(n));
            auto node = tree_.resolve(n);
            if (!node) return false;
            bool ok;
            if (node->isDir) ok = st_->setMtime(node->nodePath, epochSeconds);
            else if (node->isSymlink) ok = st_->setMtime(node->symlinkFile, epochSeconds);   // official reads a link's mtime from symlink.c9r
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
            auto resolved = resolveSymlinkPathLocked(normalizePath(path));
            if (!resolved) return -1;
            auto node = tree_.resolve(*resolved);
            if (!node || node->isDir || node->isSymlink) return -1;
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
            auto resolved = resolveSymlinkPathLocked(normalizePath(path));
            if (!resolved) return 0;
            std::string dirId;
            if (!tree_.resolveDirId(*resolved, dirId)) return 0;
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
            if (path.empty()) {
                tree_.invalidateAll();
                engine_.invalidateAll();
            } else {
                const std::string n = normalizePath(path);
                // Clear engine handles before taking the namespace lock (readers take them first).
                engine_.invalidateAll();
                std::shared_lock<std::shared_mutex> ns(ns_);
                tree_.invalidate(n);
                if (auto resolved = resolveSymlinkPathLocked(n)) tree_.invalidate(*resolved);
            }
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
        auto resolved = resolveSymlinkPathLocked(vpath);
        if (!resolved) return false;
        auto n = tree_.resolve(*resolved);
        if (!n || n->isDir || n->isSymlink) return false;
        physical = n->contentsPath;
        return true;
    }

    std::string prepareForWrite(const std::string& vpath) override {
        std::unique_lock<std::shared_mutex> ns(ns_);
        std::string original = normalizePath(vpath);
        auto resolved = resolveSymlinkPathLocked(original);
        if (!resolved) throw Error(Err::NotFound, "Shortcut target not found: " + original);
        std::string n = *resolved;
        if (n.empty()) throw Error(Err::NotFound, "A file shortcut cannot target the vault root");
        std::string parentPath = parentOf(n), name = nameOf(n);
        std::string parentId;
        if (!tree_.resolveDirId(parentPath, parentId)) throw Error(Err::NotFound, "Folder not found: " + parentPath);
        std::string parentPhys = tree_.physicalFolderForDirId(parentId);
        ensureDirIdBackup(parentPhys, parentId);
        std::string phys;
        if (auto existing = tree_.resolve(n)) {
            if (existing->isDir) throw Error(Err::Exists, "a folder with that name already exists");
            if (existing->isSymlink) throw Error(Err::Exists, "a symlink with that name already exists");
            phys = existing->contentsPath;
        } else {
            phys = createNewFileNode(parentPhys, nc_.encryptFilename(name, parentId));
        }
        st_->markWritePending(phys);
        { std::lock_guard<std::mutex> g(pmu_); pending_[original] = phys; }
        return phys;
    }

    void afterWrite(const std::string& vpath, const std::string& physical) override {
        std::string n = normalizePath(vpath);
        std::string captured = physical;
        { std::lock_guard<std::mutex> g(pmu_); auto it = pending_.find(n); if (it != pending_.end()) { captured = it->second; pending_.erase(it); } }
        publish(n, captured);
        tree_.invalidateAll();
        engine_.invalidateAll();
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

    // Resolve Cryptomator symlinks like a POSIX path walk, but with the vault root as
    // the boundary. Absolute targets are rejected; relative targets are interpreted
    // from the link's parent. A bounded hop count and visited set prevent cycles.
    // Caller must hold ns_ (shared or exclusive).
    std::optional<std::string> resolveSymlinkPathLocked(const std::string& input) {
        if (!input.empty() && input.front() == '/') return std::nullopt;
        std::vector<std::string> pending = splitSegments(normalizePath(input));
        std::vector<std::string> resolved;
        size_t i = 0;
        int hops = 0;
        while (i < pending.size()) {
            const std::string segment = pending[i++];
            if (segment.empty() || segment == ".") continue;
            if (segment == "..") {
                if (!resolved.empty()) resolved.pop_back(); // clamp at vault root
                continue;
            }
            std::string parent;
            for (const auto& part : resolved) parent = joinPath(parent, part);
            const std::string candidate = joinPath(parent, segment);
            auto node = tree_.resolve(candidate);
            if (!node) {
                if (i == pending.size()) { resolved.push_back(segment); continue; }
                return std::nullopt;
            }
            if (node->isSymlink) {
                if (++hops > 40) return std::nullopt;
                std::string target;
                st_->ensureContentReady(node->symlinkFile);
                if (!readSmallEncryptedFile(*st_, fmt_, node->symlinkFile, kMaxSymlinkLength, target) ||
                    target.empty() || target.front() == '/' || target.find('\0') != std::string::npos || !validUtf8(target)) return std::nullopt;
                auto targetParts = splitSegments(target);
                pending.erase(pending.begin() + static_cast<std::ptrdiff_t>(i - 1));
                pending.insert(pending.begin() + static_cast<std::ptrdiff_t>(i - 1), targetParts.begin(), targetParts.end());
                i--;
                continue;
            }
            if (i < pending.size() && !node->isDir) return std::nullopt;
            resolved.push_back(segment);
        }
        std::string result;
        for (const auto& segment : resolved) result = joinPath(result, segment);
        return result;
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
            if (n.isSymlink) continue;
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

// cryptofs BackupHelper.attemptBackup: "<name>.<first 4 bytes of SHA-256(content), upper-case hex>.bkup".
// Create-new: an existing backup is compared with [content] (and only logged if they differ), never replaced.
// Best effort -- returns false on a write failure, which callers must treat as non-fatal.
static bool attemptBackup(Storage& s, const std::string& name, const Bytes& content) {
    using namespace cryptomator;
    Bytes digest = crypto::hash(crypto::Md::Sha256, content.data(), content.size());
    std::string hex = toHex(digest.data(), 4);
    for (char& c : hex) c = (char)std::toupper((unsigned char)c);   // Guava base16 is upper-case
    const std::string bkup = name + "." + hex + ".bkup";
    DirEntry be;
    if (s.stat(bkup, be)) {
        Bytes existing;
        if (!s.readWhole(bkup, existing) || existing != content)
            logMsg(LogLevel::Warn, TAG, "backup " + bkup + " differs from " + name + "; replace it manually");
        return true;
    }
    if (!s.writeWhole(bkup, content.data(), content.size())) {
        logMsg(LogLevel::Warn, TAG, "could not write " + bkup);
        return false;
    }
    return true;
}

OpenResult openCryptomator(std::shared_ptr<Storage> s, const uint8_t* pw, size_t pwLen, bool readOnly,
                           const HostEnv& env, const StorageFactory& factory) {
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

    // Desktop parity: the key files are backed up on every successful read-write unlock. Never in a read-only
    // session (which must not write at all) and never fatal.
    if (!readOnly && env.backupKeyFilesOnOpen) {
        try {
            attemptBackup(*s, kMasterkeyFile, raw);
            Bytes cfgBytes;
            if (s->stat(kVaultFile, de) && s->readWhole(kVaultFile, cfgBytes)) attemptBackup(*s, kVaultFile, cfgBytes);
        } catch (const std::exception& e) { logMsg(LogLevel::Warn, TAG, std::string("key file backup failed: ") + e.what()); }
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
        attemptBackup(s, kMasterkeyFile, raw);
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

namespace {

// What a vault folder looks like from its files alone (no password, no scrypt). Shared by
// probeCryptomatorFormat and migrateCryptomator7To8 so the two can never disagree about whether a vault is
// migratable. [code] is the probe result (see fv_vault.h); [message] is the reason shown when migration is
// refused; [raw]/[parsed] are filled when the key file was read and parsed (codes 7, -8 and 6).
struct CryptomatorLayout {
    int code = 0;
    std::string message;
    Bytes raw;
    std::optional<cryptomator::MasterkeyFile> parsed;
};

CryptomatorLayout classifyCryptomatorLayout(Storage& s) {
    using namespace cryptomator;
    CryptomatorLayout out;
    DirEntry de;
    if (!s.stat(kMasterkeyFile, de) || de.isDir) {
        out.code = 0;
        out.message = "No masterkey.cryptomator found \xE2\x80\x94 this doesn't look like a Cryptomator vault.";
        return out;
    }
    if (s.stat(kVaultFile, de)) {
        out.code = 8;
        out.message = "This vault already has a vault.cryptomator, so there is nothing to migrate.";
        return out;
    }
    if (!s.readWhole(kMasterkeyFile, out.raw)) {
        out.code = 0;
        out.message = "Could not read masterkey.cryptomator";
        return out;
    }
    try {
        out.parsed = MasterkeyFile::parse(std::string(out.raw.begin(), out.raw.end()));
    } catch (const std::exception& e) {
        out.code = 0;
        out.message = e.what();
        out.parsed.reset();
        return out;
    }
    const int version = out.parsed->version;
    if (version == 7) {
        out.code = 7;
    } else if (version >= 8) {
        out.code = -8;
        out.message = "vault.cryptomator is missing from this format 8 vault. If it is stored with a cloud provider, "
                      "wait for it to finish syncing; do not migrate.";
    } else {
        out.code = 6;
        out.message = "Vault format " + std::to_string(version) +
                      " cannot be migrated here (only 7 can). Open it once in Cryptomator to migrate it.";
    }
    return out;
}

}  // namespace

int probeCryptomatorFormat(Storage& s) {
    try {
        return classifyCryptomatorLayout(s).code;
    } catch (...) {
        return 0;   // a storage that throws is "cannot tell", never a reason to offer the upgrade
    }
}

PlainResult migrateCryptomator7To8(Storage& s, const uint8_t* pw, size_t pwLen) {
    using namespace cryptomator;
    CryptomatorLayout layout = classifyCryptomatorLayout(s);
    if (layout.code != 7 || !layout.parsed) return plainFail(OpenStatus::InvalidVault, layout.message);
    const Bytes& raw = layout.raw;
    try {
        const MasterkeyFile& parsed = *layout.parsed;
        Masterkey mk = unlockMasterkeyCompat(parsed, pw, pwLen);   // proves the password before anything is written
        Secret npw = normalizedPassphrase(pw, pwLen);              // the key file is re-saved with the normalised passphrase
        // 1. back up the old key file -- here a hard requirement, since the upgrade cannot be undone
        if (!attemptBackup(s, kMasterkeyFile, raw))
            return plainFail(OpenStatus::InvalidVault, "Could not back up masterkey.cryptomator; the vault was not changed.");
        // 2. the signed vault config. Written first: with it in place the vault already opens as format 8, so an
        //    interruption before step 3 leaves a perfectly usable vault.
        std::string jwt = createVaultConfig(8, "SIV_CTRMAC", kDefaultShortening, mk, newUuid());
        if (!s.writeWholeAtomic(kVaultFile, (const uint8_t*)jwt.data(), jwt.size()))
            return plainFail(OpenStatus::InvalidVault, "Could not write vault.cryptomator; the vault was not changed.");
        // 3. re-save the key file as version 999 with the library defaults (what official's persist() does)
        std::string json = lockMasterkey(mk, npw.data(), npw.size(), 999);
        if (!s.writeWholeAtomic(kMasterkeyFile, (const uint8_t*)json.data(), json.size()))
            return plainFail(OpenStatus::InvalidVault, "vault.cryptomator was written but masterkey.cryptomator could not be updated; the vault still opens.");
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
