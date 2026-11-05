// CryFS vault: path resolution over directory blobs, the session (fv::Vault)
// and the open / create / change-password entry points.
#include <algorithm>
#include <fcntl.h>
#include <mutex>
#include <shared_mutex>
#include <sys/stat.h>
#include <unistd.h>

#include "fv_cryfs.h"
#include "fv_util.h"

namespace fv {
namespace cryfs {
namespace {

constexpr const char* TAG = "CryfsSession";
constexpr uint32_t kDefaultFileMode = 0x81A4, kDefaultDirMode = 0x41ED;
constexpr int kSliceBytes = 1 << 20;

int64_t nowSec() { return (int64_t)::time(nullptr); }

struct Resolved {
    std::string name;
    std::optional<DirRecord> entry;       // empty = the root directory
    BlockId blob;
    std::optional<BlockId> parentBlob;
    bool isDir() const { return !entry || entry->type == EntryType::Dir; }
};

struct FsHeader { EntryType type; BlockId parent; };

FsHeader parseHeader(const Bytes& raw) {
    if (raw.size() < kFsHeaderSize) throw Error(Err::InvalidVault, "Blob is too short to contain a valid header (" + std::to_string(raw.size()) + " bytes).");
    uint16_t ver = readU16LE(raw.data());
    if (ver != 1) throw Error(Err::InvalidVault, "Blob has format version " + std::to_string(ver) + ", expected 1.");
    if (raw[2] > 2) throw Error(Err::InvalidVault, "Blob has unknown type byte " + std::to_string(raw[2]) + ".");
    FsHeader h;
    h.type = (EntryType)raw[2];
    std::memcpy(h.parent.b.data(), raw.data() + 3, 16);
    return h;
}

class VaultTree {
public:
    VaultTree(DataTree& dt, const BlockId& root) : dt_(dt), root_(root) {}

    std::vector<DirRecord> readDirEntries(const BlockId& dirBlob) {
        {
            std::lock_guard<std::mutex> g(mu_);
            auto it = cache_.find(dirBlob);
            if (it != cache_.end()) return it->second;
        }
        Bytes raw = dt_.readAll(dirBlob);
        FsHeader h = parseHeader(raw);
        if (h.type != EntryType::Dir) throw Error(Err::InvalidVault, "Block " + dirBlob.hex() + " is not a directory blob");
        auto entries = dirParse(Bytes(raw.begin() + kFsHeaderSize, raw.end()));
        std::lock_guard<std::mutex> g(mu_);
        cache_[dirBlob] = entries;
        return entries;
    }

    Resolved rootNode() const { Resolved r; r.blob = root_; return r; }

    // Throws Error(NotFound) if a segment is missing.
    Resolved resolve(const std::string& path) {
        auto segs = splitSegments(path);
        if (segs.empty()) return rootNode();
        BlockId cur = root_;
        std::optional<DirRecord> curEntry;
        std::optional<BlockId> parent;
        for (size_t i = 0; i < segs.size(); i++) {
            if (i > 0 && (!curEntry || curEntry->type != EntryType::Dir))
                throw Error(Err::NotFound, "not a directory: " + segs[i - 1]);
            auto entries = readDirEntries(cur);
            const DirRecord* match = nullptr;
            for (auto& e : entries) if (e.name == segs[i]) { match = &e; break; }
            if (!match) throw Error(Err::NotFound, "Path not found: " + path);
            parent = cur;
            curEntry = *match;
            cur = match->blob;
        }
        Resolved r;
        r.name = segs.back(); r.entry = curEntry; r.blob = cur; r.parentBlob = parent;
        return r;
    }

    std::optional<Resolved> tryResolve(const std::string& path) {
        try { return resolve(path); }
        catch (const Error& e) { if (e.code() != Err::NotFound) logMsg(LogLevel::Debug, TAG, std::string("tryResolve: ") + e.what()); return std::nullopt; }
    }

    // Mutations: call with the session's exclusive lock held.
    void addEntry(const BlockId& parentDir, const DirRecord& entry) {
        auto entries = readDirEntries(parentDir);
        for (auto& e : entries) if (e.name == entry.name) throw Error(Err::Exists, "\"" + entry.name + "\" already exists");
        entries.push_back(entry);
        rewrite(parentDir, entries);
    }
    void removeEntry(const BlockId& parentDir, const std::string& name) {
        auto entries = readDirEntries(parentDir);
        size_t before = entries.size();
        entries.erase(std::remove_if(entries.begin(), entries.end(), [&](const DirRecord& e) { return e.name == name; }), entries.end());
        if (entries.size() == before) throw Error(Err::NotFound, name);
        rewrite(parentDir, entries);
    }
    void replaceEntry(const BlockId& parentDir, const std::string& oldName, const DirRecord& ne) {
        auto entries = readDirEntries(parentDir);
        bool found = false;
        for (auto& e : entries) if (e.name == oldName) { e = ne; found = true; break; }
        if (!found) throw Error(Err::NotFound, oldName);
        rewrite(parentDir, entries);
    }
    void invalidate() { std::lock_guard<std::mutex> g(mu_); cache_.clear(); }

private:
    void rewrite(const BlockId& dirBlob, const std::vector<DirRecord>& entries) {
        FsHeader h = parseHeader(dt_.read(dirBlob, 0, (int)kFsHeaderSize));
        { std::lock_guard<std::mutex> g(mu_); cache_.erase(dirBlob); }
        BlockId scratch = dt_.buildBlob(fsWrap(EntryType::Dir, h.parent, dirSerialize(entries)));
        auto replaced = dt_.replaceRoot(dirBlob, scratch);
        dt_.deleteSubtrees(replaced.oldChildren, replaced.childDepth);
    }
    DataTree& dt_;
    BlockId root_;
    std::mutex mu_;
    std::unordered_map<BlockId, std::vector<DirRecord>, BlockId::Hash> cache_;
};

// Header bytes followed by the real stream: the blob is <fs header><payload>.
struct HeaderedSource : ByteSource {
    Bytes header; size_t pos = 0;
    ByteSource& inner; Progress* prog;
    HeaderedSource(Bytes h, ByteSource& in, Progress* p) : header(std::move(h)), inner(in), prog(p) {}
    int64_t read(uint8_t* buf, size_t n) override {
        if (n == 0) return 0;
        size_t copied = 0;
        if (pos < header.size()) {
            copied = std::min(n, header.size() - pos);
            std::memcpy(buf, header.data() + pos, copied);
            pos += copied;
            if (copied == n) return (int64_t)copied;
        }
        int64_t r = inner.read(buf + copied, n - copied);
        if (r < 0) return r;
        if (r > 0 && prog) {
            prog->onWriteBack((uint64_t)r);
            if (prog->cancelled()) return -1;
        }
        return (int64_t)copied + r;
    }
};

struct FdSource : ByteSource {
    int fd; int64_t off = 0;
    explicit FdSource(int f) : fd(f) {}
    int64_t read(uint8_t* buf, size_t n) override {
        for (;;) {
            ssize_t r = ::pread(fd, buf, n, (off_t)off);
            if (r < 0 && errno == EINTR) continue;
            if (r > 0) off += r;
            return r;
        }
    }
};

class CryfsVault final : public Vault {
public:
    CryfsVault(std::shared_ptr<Storage> st, Config cfg, std::unique_ptr<LocalIntegrityState> integ,
               bool readOnly, const HostEnv& env)
        : st_(std::move(st)), cfg_(std::move(cfg)), readOnly_(readOnly), tempDir_(env.tempDir),
          integrity_(std::move(integ)),
          bs_(*st_, cipherIdOf(cfg_.cipherName), cfg_.key, *integrity_),
          dt_(bs_, virtualBlockSize(cfg_.blocksizeBytes, cfg_.cipherName)),
          tree_(dt_, cfg_.rootBlob) {}
    ~CryfsVault() override { close(); }

    BlockStore& blockStore() { return bs_; }
    const Config& config() const { return cfg_; }

    VaultFormat format() const override { return VaultFormat::Cryfs; }
    bool readOnly() const override { return readOnly_; }

    // ---- namespace --------------------------------------------------------
    bool listDirectory(const std::string& path, std::vector<DirEntry>& out) override {
        try {
            Lifecycle::Op op(life_);
            std::shared_lock<std::shared_mutex> g(tmu_);
            Resolved dir = tree_.resolve(normalizePath(path));
            if (!dir.isDir()) return false;
            out.clear();
            for (auto& e : tree_.readDirEntries(dir.blob)) {
                DirEntry d;
                d.name = e.name;
                d.isDir = e.type == EntryType::Dir;
                d.size = d.isDir ? 0 : payloadSize(e.blob);
                d.mtimeMs = e.mtime * 1000;
                out.push_back(std::move(d));
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
            std::unique_lock<std::shared_mutex> g(tmu_);
            if (auto ex = tree_.tryResolve(n)) return ex->isDir();
            Resolved parent = tree_.resolve(parentOf(n));
            if (!parent.isDir()) return false;
            BlockId blob = dt_.buildBlob(fsWrap(EntryType::Dir, parent.blob, dirSerialize({})));
            tree_.addEntry(parent.blob, newEntry(EntryType::Dir, nameOf(n), blob, kDefaultDirMode));
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
            if (oldN == newN) return true;
            if (startsWith(newN, (oldN + "/").c_str())) return false;   // a folder cannot move into itself
            std::unique_lock<std::shared_mutex> g(tmu_);
            Resolved oldNode = tree_.resolve(oldN);
            if (!oldNode.parentBlob || !oldNode.entry) return false;
            Resolved newParent = tree_.resolve(parentOf(newN));
            if (!newParent.isDir()) return false;
            std::optional<Resolved> dest = tree_.tryResolve(newN);
            std::optional<BlockId> replacedBlob;
            if (dest) {
                // POSIX rename-over: only a file may replace a file.
                if (dest->isDir() || oldNode.isDir()) return false;
                tree_.removeEntry(*dest->parentBlob, dest->entry->name);
                replacedBlob = dest->blob;
            }
            DirRecord updated = *oldNode.entry;
            updated.name = nameOf(newN);
            if (*oldNode.parentBlob == newParent.blob) {
                tree_.replaceEntry(*oldNode.parentBlob, oldNode.entry->name, updated);
            } else {
                tree_.removeEntry(*oldNode.parentBlob, oldNode.entry->name);
                tree_.addEntry(newParent.blob, updated);
                dt_.patchFirstLeafBytes(updated.blob, 3, newParent.blob.b.data(), 16);
            }
            g.unlock();
            if (replacedBlob) dt_.deleteBlob(*replacedBlob);
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
            Resolved node;
            {
                std::unique_lock<std::shared_mutex> g(tmu_);
                auto r = tree_.tryResolve(n);
                if (!r || !r->parentBlob || !r->entry) return false;
                node = *r;
                tree_.removeEntry(*node.parentBlob, node.entry->name);
            }
            dropPending(n);
            if (node.isDir()) freeDirectoryContents(node.blob, 0);
            dt_.deleteBlob(node.blob);
            return true;
        } catch (const std::exception& e) {
            logMsg(LogLevel::Warn, TAG, std::string("deleteFile failed: ") + e.what());
            return false;
        }
    }

    bool setLastModifiedTime(const std::string& path, int64_t epochSeconds) override {
        try {
            Lifecycle::Op op(life_);
            std::unique_lock<std::shared_mutex> g(tmu_);
            Resolved node = tree_.resolve(normalizePath(path));
            if (!node.parentBlob || !node.entry) return true;
            DirRecord e = *node.entry;
            e.mtime = epochSeconds;
            tree_.replaceEntry(*node.parentBlob, e.name, e);
            return true;
        } catch (const std::exception&) { return false; }
    }

    int64_t getFileSize(const std::string& path) override {
        try {
            Lifecycle::Op op(life_);
            std::string n = normalizePath(path);
            {
                std::lock_guard<std::mutex> pg(pmu_);
                auto it = pending_.find(n);
                if (it != pending_.end()) return it->second->size();
            }
            std::shared_lock<std::shared_mutex> g(tmu_);
            Resolved node = tree_.resolve(n);
            return node.isDir() ? -1 : payloadSize(node.blob);
        } catch (const std::exception&) { return -1; }
    }

    int64_t getFolderSize(const std::string& path) override {
        try {
            Lifecycle::Op op(life_);
            return folderSize(normalizePath(path), 0);
        } catch (const std::exception&) { return 0; }
    }

    // ---- content ----------------------------------------------------------
    std::optional<Bytes> readFileChunk(const std::string& path, int64_t offset, int length) override {
        try {
            Lifecycle::Op op(life_);
            std::string n = normalizePath(path);
            {
                std::lock_guard<std::mutex> pg(pmu_);
                auto it = pending_.find(n);
                if (it != pending_.end()) return readScratch(*it->second, offset, length);
            }
            std::shared_lock<std::shared_mutex> g(tmu_);
            Resolved node = tree_.resolve(n);
            if (node.isDir()) return std::nullopt;
            return dt_.read(node.blob, (int64_t)kFsHeaderSize + offset, length);
        } catch (const std::exception&) { return std::nullopt; }
    }

    bool writeFileChunk(const std::string& path, int64_t offset, const uint8_t* data, size_t len) override {
        if (readOnly_) return false;
        try {
            Lifecycle::Op op(life_);
            std::string n = normalizePath(path);
            std::shared_ptr<Scratch> sc;
            {
                std::lock_guard<std::mutex> pg(pmu_);
                auto it = pending_.find(n);
                if (it != pending_.end()) sc = it->second;
            }
            if (!sc) {
                sc = makeScratch();
                std::optional<Resolved> existing;
                { std::shared_lock<std::shared_mutex> g(tmu_); existing = tree_.tryResolve(n); }
                if (existing && !existing->isDir()) {
                    int64_t total, pos = 0;
                    { std::shared_lock<std::shared_mutex> g(tmu_); total = payloadSize(existing->blob); }
                    while (pos < total) {
                        Bytes chunk;
                        { std::shared_lock<std::shared_mutex> g(tmu_);
                          chunk = dt_.read(existing->blob, (int64_t)kFsHeaderSize + pos, (int)std::min<int64_t>(kSliceBytes, total - pos)); }
                        if (chunk.empty()) break;
                        if (!sc->writeAt(chunk.data(), chunk.size(), pos)) return false;
                        pos += (int64_t)chunk.size();
                    }
                }
                std::lock_guard<std::mutex> pg(pmu_);
                auto it = pending_.find(n);
                if (it != pending_.end()) sc = it->second; else pending_[n] = sc;
            }
            return sc->writeAt(data, len, offset);
        } catch (const std::exception&) { return false; }
    }

    bool finishWrite(const std::string& path) override {
        if (readOnly_) return false;
        try {
            Lifecycle::Op op(life_);
            std::string n = normalizePath(path);
            std::shared_ptr<Scratch> sc;
            {
                std::lock_guard<std::mutex> pg(pmu_);
                auto it = pending_.find(n);
                if (it == pending_.end()) return true;
                sc = it->second;
                pending_.erase(it);
            }
            FdSource src(sc->fd());
            commitStream(n, src, nullptr);
            return true;
        } catch (const std::exception& e) {
            logMsg(LogLevel::Warn, TAG, std::string("finishWrite failed: ") + e.what());
            return false;
        }
    }

    bool writeBackFile(const std::string& path, const std::string& src, Progress* p) override {
        if (readOnly_) return false;
        try {
            Lifecycle::Op op(life_);
            int fd = ::open(src.c_str(), O_RDONLY | O_CLOEXEC);
            if (fd < 0) return false;
            FdFile f(fd);
            FdSource s(fd);
            commitStream(normalizePath(path), s, p);
            return true;
        } catch (const std::exception& e) {
            logMsg(LogLevel::Warn, TAG, std::string("writeBackFile failed: ") + e.what());
            return false;
        }
    }

    bool importStream(const std::string& path, ByteSource& src, Progress* p) override {
        if (readOnly_) return false;
        try {
            Lifecycle::Op op(life_);
            commitStream(normalizePath(path), src, p);
            return true;
        } catch (const std::exception& e) {
            logMsg(LogLevel::Warn, TAG, std::string("importStream failed: ") + e.what());
            return false;
        }
    }

    bool extractFile(const std::string& path, const std::string& dest, Progress* p) override {
        try {
            Lifecycle::Op op(life_);
            std::string n = normalizePath(path);
            Resolved node;
            int64_t total;
            {
                std::shared_lock<std::shared_mutex> g(tmu_);
                node = tree_.resolve(n);
                if (node.isDir()) return false;
                total = payloadSize(node.blob);
            }
            FdFile out(::open(dest.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600));
            if (!out.valid()) return false;
            int64_t pos = 0;
            while (pos < total) {
                if (life_.isClosed()) return false;
                Bytes chunk;
                {
                    std::shared_lock<std::shared_mutex> g(tmu_);
                    chunk = dt_.read(node.blob, (int64_t)kFsHeaderSize + pos, (int)std::min<int64_t>(kSliceBytes, total - pos));
                }
                if (chunk.empty()) break;
                if (!out.writeAll(chunk.data(), chunk.size())) return false;
                pos += (int64_t)chunk.size();
                if (p) { p->onExtract(chunk.size()); if (p->cancelled()) return false; }
            }
            return true;
        } catch (const std::exception& e) {
            logMsg(LogLevel::Warn, TAG, std::string("extractFile failed: ") + e.what());
            return false;
        }
    }

    // ---- batching / caches ------------------------------------------------
    void beginBatchWrite() override {}
    void endBatchWrite() override {}
    void beginBatchDelete() override {}
    void endBatchDelete() override {}
    void invalidateCache(const std::string&) override {
        try { Lifecycle::Op op(life_); tree_.invalidate(); bs_.clearCache(); } catch (const std::exception&) {}
    }

    bool spaceInfo(int64_t& total, int64_t& free) override { return st_->spaceInfo(total, free); }

    std::vector<InfoItem> info() override {
        return {
            {InfoItem::Kind::Str, "formatVersion", cfg_.formatVersion},
            {InfoItem::Kind::Str, "blockCipherName", cfg_.cipherName},
            {InfoItem::Kind::Str, "createdWithVersion", cfg_.createdWithVersion},
            {InfoItem::Kind::Str, "lastOpenedWithVersion", cfg_.lastOpenedWithVersion},
            {InfoItem::Kind::Int, "blockSizeBytes", std::to_string(cfg_.blocksizeBytes)},
            {InfoItem::Kind::Bool, "readOnly", readOnly_ ? "true" : "false"},
        };
    }

    KeyExport exportKeys() override {
        KeyExport k;
        k.format = VaultFormat::Cryfs;
        k.fields.emplace_back("key", cfg_.key.bytes());
        k.fields.emplace_back("filesystemId", cfg_.filesystemId);
        k.strings.emplace_back("blockCipherName", cfg_.cipherName);
        k.strings.emplace_back("blocksizeBytes", std::to_string(cfg_.blocksizeBytes));
        k.strings.emplace_back("rootBlobId", cfg_.rootBlob.hex());
        k.strings.emplace_back("formatVersion", cfg_.formatVersion);
        k.strings.emplace_back("createdWithVersion", cfg_.createdWithVersion);
        k.strings.emplace_back("lastOpenedWithVersion", cfg_.lastOpenedWithVersion);
        if (cfg_.exclusiveClientId) k.strings.emplace_back("exclusiveClientId", std::to_string(*cfg_.exclusiveClientId));
        return k;
    }

    void close() override {
        if (!life_.markClosed()) return;
        life_.drain();
        { std::lock_guard<std::mutex> pg(pmu_); pending_.clear(); }
        try { bs_.flushIntegrity(); } catch (...) {}
        st_->close();
    }

private:
    // Scratch file for incremental writes: unlinked right after creation so the
    // plaintext never has a name on disk.
    class Scratch {
    public:
        explicit Scratch(FdFile f) : f_(std::move(f)) {}
        bool writeAt(const uint8_t* d, size_t n, int64_t off) {
            std::lock_guard<std::mutex> g(mu_);
            size_t done = 0;
            while (done < n) {
                ssize_t r = ::pwrite(f_.fd(), d + done, n - done, (off_t)(off + (int64_t)done));
                if (r < 0) { if (errno == EINTR) continue; return false; }
                done += (size_t)r;
            }
            return true;
        }
        int64_t size() { std::lock_guard<std::mutex> g(mu_); return f_.size(); }
        int fd() const { return f_.fd(); }
        Bytes readAt(int64_t off, int len) {
            std::lock_guard<std::mutex> g(mu_);
            Bytes b((size_t)std::max(len, 0));
            int64_t r = f_.readAt(b.data(), b.size(), off);
            b.resize(r > 0 ? (size_t)r : 0);
            return b;
        }
    private:
        FdFile f_;
        std::mutex mu_;
    };

    std::shared_ptr<Scratch> makeScratch() {
        std::string dir = tempDir_.empty() ? "/tmp" : tempDir_;
        std::string tmpl = dir + "/cryfs_write_XXXXXX";
        std::vector<char> buf(tmpl.begin(), tmpl.end());
        buf.push_back(0);
        int fd = ::mkstemp(buf.data());
        if (fd < 0) throw Error(Err::Io, "cannot create scratch file");
        ::unlink(buf.data());
        return std::make_shared<Scratch>(FdFile(fd));
    }

    static Bytes readScratch(Scratch& s, int64_t offset, int length) {
        if (offset < 0 || offset >= s.size()) return Bytes();
        return s.readAt(offset, (int)std::min<int64_t>(length, s.size() - offset));
    }

    void dropPending(const std::string& n) {
        std::lock_guard<std::mutex> g(pmu_);
        pending_.erase(n);
    }

    static DirRecord newEntry(EntryType t, const std::string& name, const BlockId& blob, uint32_t mode) {
        DirRecord e;
        e.type = t; e.name = name; e.blob = blob; e.mode = mode;
        e.atime = e.mtime = e.ctime = nowSec();
        return e;
    }

    int64_t payloadSize(const BlockId& blob) { return std::max<int64_t>(0, dt_.size(blob) - (int64_t)kFsHeaderSize); }

    int64_t folderSize(const std::string& path, int depth) {
        if (depth > 256) return 0;
        std::vector<DirRecord> entries;
        {
            std::shared_lock<std::shared_mutex> g(tmu_);
            Resolved dir = tree_.resolve(path);
            if (!dir.isDir()) return 0;
            entries = tree_.readDirEntries(dir.blob);
        }
        int64_t total = 0;
        for (auto& e : entries) {
            if (life_.isClosed()) break;
            if (e.type == EntryType::Dir) total += folderSize(joinPath(path, e.name), depth + 1);
            else { std::shared_lock<std::shared_mutex> g(tmu_); total += payloadSize(e.blob); }
        }
        return total;
    }

    void freeDirectoryContents(const BlockId& dirBlob, int depth) {
        if (depth > 256) throw Error(Err::InvalidVault, "directory nesting too deep");
        Bytes raw = dt_.readAll(dirBlob);
        for (auto& e : dirParse(Bytes(raw.begin() + std::min(raw.size(), kFsHeaderSize), raw.end()))) {
            if (e.type == EntryType::Dir) freeDirectoryContents(e.blob, depth + 1);
            dt_.deleteBlob(e.blob);
        }
    }

    // Writes [src] as the blob of the file at [n] (creating or replacing it).
    // The block tree is built without any lock (nothing references it yet);
    // only the swap into the directory takes the exclusive lock.
    void commitStream(const std::string& n, ByteSource& src, Progress* prog) {
        std::optional<Resolved> existing;
        BlockId parentBlob;
        {
            std::shared_lock<std::shared_mutex> g(tmu_);
            existing = tree_.tryResolve(n);
            if (existing && existing->isDir()) throw Error(Err::Exists, n + " is a directory");
            parentBlob = existing && existing->parentBlob ? *existing->parentBlob : tree_.resolve(parentOf(n)).blob;
        }
        Bytes header = fsWrap(EntryType::File, parentBlob, Bytes());
        header.resize(kFsHeaderSize);
        HeaderedSource wrapped(std::move(header), src, prog);
        BlockId scratch = dt_.buildBlobStream(wrapped);
        DataTree::Replaced replaced;
        bool replacedExisting = false;
        try {
            std::unique_lock<std::shared_mutex> g(tmu_);
            if (existing) {
                replaced = dt_.replaceRoot(existing->blob, scratch);
                replacedExisting = true;
                DirRecord e = *existing->entry;
                e.mtime = nowSec();
                tree_.replaceEntry(*existing->parentBlob, e.name, e);
            } else {
                tree_.addEntry(parentBlob, newEntry(EntryType::File, nameOf(n), scratch, kDefaultFileMode));
            }
        } catch (...) {
            if (!replacedExisting) { try { dt_.deleteBlob(scratch); } catch (...) {} }
            throw;
        }
        if (replacedExisting) dt_.deleteSubtrees(replaced.oldChildren, replaced.childDepth);
    }

    static CryfsCipherId cipherIdOf(const std::string& n) { return cryfsCipherIdFromName(n.c_str()); }

    std::shared_ptr<Storage> st_;
    Config cfg_;
    const bool readOnly_;
    std::string tempDir_;
    std::unique_ptr<LocalIntegrityState> integrity_;
    BlockStore bs_;
    DataTree dt_;
    VaultTree tree_;
    Lifecycle life_;
    std::shared_mutex tmu_;
    std::mutex pmu_;
    std::map<std::string, std::shared_ptr<Scratch>> pending_;
};

PlainResult plainFail(OpenStatus s, std::string msg) { PlainResult r; r.status = s; r.message = std::move(msg); return r; }

// Shared tail of both open flavours.
OpenResult finishOpen(std::shared_ptr<Storage> s, const Config& cfg, Secret combined, bool readOnly,
                      const HostEnv& env, const StorageFactory& factory) {
    OpenResult res;
    auto fail = [&](OpenStatus st, std::string msg) { res.status = st; res.message = std::move(msg); return std::move(res); };
    if (cryfsCipherIdFromName(cfg.cipherName.c_str()) == CryfsCipherId::kUnknown)
        return fail(OpenStatus::InvalidVault, "Vault uses cipher \"" + cfg.cipherName + "\", which this app does not support.");
    std::shared_ptr<Storage> sessionStorage = s;
    try { if (factory) { auto f = factory(); if (f) sessionStorage = std::move(f); } }
    catch (const std::exception& e) { return fail(OpenStatus::InvalidVault, std::string("Could not open vault: ") + e.what()); }
    try {
        auto integrity = LocalIntegrityState::open(env.cryfsLocalStateDir, cfg.filesystemId);
        auto vault = std::make_unique<CryfsVault>(sessionStorage, cfg, std::move(integrity), readOnly, env);
        if (!vault->blockStore().load(cfg.rootBlob)) {
            auto v = vault->blockStore().lastViolation();
            vault->close();
            if (v) {
                return fail(OpenStatus::InvalidVault,
                    "This vault's root directory looks like it was rolled back to an older version (client " + std::to_string(v->writer) +
                    ": saw version " + std::to_string(v->attempted) + ", but this device already recorded version " + std::to_string(v->known) +
                    "). Refusing to open it to avoid masking possible data loss or tampering -- this is the same protection CryFS's own error 24/25 gives you.");
            }
            return fail(OpenStatus::InvalidVault, "Vault's root directory block is missing or unreadable.");
        }
        res.status = OpenStatus::Ok;
        res.vault = std::move(vault);
        res.derivedKey = std::move(combined);
        return res;
    } catch (const std::exception& e) {
        if (sessionStorage != s) sessionStorage->close();
        return fail(OpenStatus::InvalidVault, std::string("Could not open vault: ") + e.what());
    }
}

}  // namespace
}  // namespace cryfs

// ----------------------------------------------------------- public entry --

bool looksLikeCryfs(Storage& s) {
    DirEntry de;
    return s.stat(cryfs::kConfigName, de) && !de.isDir;
}

OpenResult openCryfs(std::shared_ptr<Storage> s, const uint8_t* pw, size_t pwLen, bool readOnly,
                     const HostEnv& env, const StorageFactory& factory) {
    using namespace cryfs;
    OpenResult res;
    Bytes raw;
    if (!s->readWhole(kConfigName, raw)) {
        res.message = "No cryfs.config found \xE2\x80\x94 this doesn't look like a CryFS vault.";
        return res;
    }
    Secret combined;
    Config cfg;
    try {
        combined = deriveCombinedKey(raw, pw, pwLen);
        cfg = parseWithCombinedKey(raw, combined);
    } catch (const Error& e) {
        res.status = e.code() == Err::WrongPassword ? OpenStatus::WrongPassword : OpenStatus::InvalidVault;
        res.message = e.code() == Err::WrongPassword ? e.what() : (e.code() == Err::Unsupported ? std::string(e.what()) : std::string(e.what()));
        return res;
    } catch (const std::exception& e) {
        res.message = std::string("Key derivation error: ") + e.what();
        return res;
    }
    return finishOpen(std::move(s), cfg, std::move(combined), readOnly, env, factory);
}

OpenResult openCryfsWithCombinedKey(std::shared_ptr<Storage> s, const uint8_t* key, size_t keyLen, bool readOnly,
                                    const HostEnv& env, const StorageFactory& factory) {
    using namespace cryfs;
    OpenResult res;
    Bytes raw;
    if (!s->readWhole(kConfigName, raw)) {
        res.message = "No cryfs.config found \xE2\x80\x94 this doesn't look like a CryFS vault.";
        return res;
    }
    Secret combined(key, keyLen);
    Config cfg;
    try {
        cfg = parseWithCombinedKey(raw, combined);
    } catch (const Error& e) {
        res.status = e.code() == Err::WrongPassword ? OpenStatus::WrongPassword : OpenStatus::InvalidVault;
        res.message = e.what();
        return res;
    }
    return finishOpen(std::move(s), cfg, std::move(combined), readOnly, env, factory);
}

PlainResult createCryfs(Storage& s, const uint8_t* pw, size_t pwLen, const CryfsCreateOptions& o, const HostEnv& env) {
    using namespace cryfs;
    try {
        std::vector<DirEntry> existing;
        if (s.list("", existing) && !existing.empty()) return plainFail(OpenStatus::InvalidVault, "Selected folder is not empty.");
        Config cfg = newVaultConfig(o.cipher, o.blocksizeBytes);
        Bytes cfgBytes = buildConfig(cfg, pw, pwLen);
        if (!s.writeWhole(kConfigName, cfgBytes.data(), cfgBytes.size()))
            return plainFail(OpenStatus::InvalidVault, "Could not create cryfs.config");
        auto integrity = LocalIntegrityState::open(env.cryfsLocalStateDir, cfg.filesystemId);
        BlockStore bs(s, cryfsCipherIdFromName(cfg.cipherName.c_str()), cfg.key, *integrity);
        DataTree dt(bs, virtualBlockSize(cfg.blocksizeBytes, cfg.cipherName));
        BlockId nullParent;
        BlockId scratch = dt.buildBlob(fsWrap(EntryType::Dir, nullParent, dirSerialize({})));
        dt.replaceRoot(cfg.rootBlob, scratch);   // publish under the id the config names
        bs.flushIntegrity();
        PlainResult ok;
        ok.status = OpenStatus::Ok;
        return ok;
    } catch (const std::exception& e) {
        return plainFail(OpenStatus::InvalidVault, std::string("Vault creation failed: ") + e.what());
    }
}

PlainResult changeCryfsPassword(Storage& s, const uint8_t* oldPw, size_t oldLen, const uint8_t* newPw, size_t newLen) {
    using namespace cryfs;
    Bytes raw;
    if (!s.readWhole(kConfigName, raw))
        return plainFail(OpenStatus::InvalidVault, "No cryfs.config found \xE2\x80\x94 this doesn't look like a CryFS vault.");
    try {
        Secret combined = deriveCombinedKey(raw, oldPw, oldLen);
        Config cfg = parseWithCombinedKey(raw, combined);
        Bytes out = buildConfig(cfg, newPw, newLen);
        if (!s.writeWholeAtomic(kConfigName, out.data(), out.size()))
            return plainFail(OpenStatus::InvalidVault, "Could not write cryfs.config");
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
