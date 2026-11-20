// See ve_mount_fs.h for the model. Everything here goes through the public C ABI (ve_*), exactly as a
// Dart caller would, so a mounted vault and the in-app browser can never disagree about semantics.

#include "ve_mount_fs.h"

#include <algorithm>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <ctime>

#include <mbedtls/platform_util.h>

#include "ve_engine.h"
#include "ve_mount_internal.h"

namespace vemount {

namespace {

constexpr auto kDirTtl = std::chrono::milliseconds(1500);
constexpr size_t kMaxCachedDirs = 64;
constexpr size_t kCoalesceFlush = 1u << 20;      // flush a write buffer at 1 MiB
constexpr size_t kStreamChunk = 4u << 20;        // bulk chunk sent to a vault in one call
constexpr size_t kReadChunkMax = 8u << 20;       // never ask the engine for more than this per call
constexpr size_t kNameMax = 255;

void wipe(std::vector<uint8_t>& v) {
    if (!v.empty()) mbedtls_platform_zeroize(v.data(), v.size());
    v.clear();
    v.shrink_to_fit();
}

int64_t nowSecs() { return static_cast<int64_t>(std::time(nullptr)); }

std::string lowerAscii(const std::string& s) {
    std::string out = s;
    for (char& c : out) {
        if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
    }
    return out;
}

bool startsWithPath(const std::string& path, const std::string& prefix) {
    return path.size() > prefix.size() && path.compare(0, prefix.size(), prefix) == 0 &&
           path[prefix.size()] == '/';
}

uint32_t getU32(const uint8_t* p) {
    return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}

// Parses the ve_list_* wire format ("<F|D|L|LD>|<size>|<mtime>|<name>") into `out`.
bool parseWire(const ve_buffer& buf, std::vector<DirItem>& out) {
    if (!buf.data || buf.len == 0) return true;
    if (buf.len < 4) return false;
    const uint8_t* p = buf.data;
    const uint8_t* end = buf.data + buf.len;
    const uint32_t count = getU32(p);
    p += 4;
    for (uint32_t i = 0; i < count; ++i) {
        if (end - p < 4) return false;
        const uint32_t len = getU32(p);
        p += 4;
        if (static_cast<size_t>(end - p) < len) return false;
        const std::string entry(reinterpret_cast<const char*>(p), len);
        p += len;
        // type|size|mtime|name -- the name is the remainder after the third '|', never split further.
        const size_t a = entry.find('|');
        if (a == std::string::npos) continue;
        const size_t b = entry.find('|', a + 1);
        if (b == std::string::npos) continue;
        const size_t c = entry.find('|', b + 1);
        if (c == std::string::npos) continue;
        DirItem item;
        const std::string type = entry.substr(0, a);
        item.attr.type = type == "D" ? NodeType::Dir : (type == "F" ? NodeType::File : NodeType::Symlink);
        if (type == "LD") item.attr.type = NodeType::Symlink;
        item.attr.size = std::strtoull(entry.c_str() + a + 1, nullptr, 10);
        item.attr.mtime = std::strtoll(entry.c_str() + b + 1, nullptr, 10);
        item.name = entry.substr(c + 1);
        if (item.name.empty() || item.name == "." || item.name == "..") continue;
        out.push_back(std::move(item));
    }
    return true;
}

}  // namespace

// ── handle ───────────────────────────────────────────────────────────────────────────────────────────

enum class HMode : uint8_t { Idle, Direct, Stream, Buffered };

struct MountFs::Handle {
    uint64_t id = 0;
    std::string path;
    bool canRead = false;
    bool canWrite = false;
    HMode mode = HMode::Idle;
    bool orphan = false;      // the path was unlinked / replaced; further data is discarded
    uint64_t size = 0;        // logical size as this handle sees it
    int pendingErr = 0;       // deferred write error, reported by the next write/flush
    // Direct (block containers) and Stream (folder vaults): coalesced, not yet sent bytes.
    std::vector<uint8_t> wbuf;
    uint64_t wbufStart = 0;   // Direct: file offset of wbuf[0]. Stream: always == streamSent
    // Stream
    uint64_t streamSent = 0;
    bool streamDirty = false; // a commit (finish_write) is owed
    bool committed = false;   // the stream was finished; any further write must rewrite the file
    // Buffered
    std::vector<uint8_t> mem;
    bool memLoaded = false;
    bool memDirty = false;

    ~Handle() {
        wipe(wbuf);
        wipe(mem);
    }
};

// ── construction ─────────────────────────────────────────────────────────────────────────────────────

MountFs::MountFs(int32_t vol, FsOptions options) : vol_(vol), opt_(std::move(options)) {
    bool ro = false;
    ve_internal_vol_traits(vol_, &folderVault_, &caseInsensitive_, &ro);
    cryfs_ = folderVault_ && ve_get_container_format(vol_) == VE_FORMAT_CRYFS;
    // A read-only slot stays read-only whatever the caller asked for.
    opt_.readOnly = opt_.readOnly || ro;
}

MountFs::~MountFs() { closeAll(); }

// ── paths ────────────────────────────────────────────────────────────────────────────────────────────

std::string MountFs::enginePath(const std::string& mountPath) const {
    std::string root = opt_.root;
    while (!root.empty() && root.back() == '/') root.pop_back();
    std::string full = isRoot(mountPath) ? (root.empty() ? "/" : root) : root + mountPath;
    if (!folderVault_) {
        // Block-container backends build "/" + path themselves; a leading slash here becomes "//x", which
        // ntfs-3g's inode cache then fails to match. Folder vaults take rooted paths.
        while (!full.empty() && full.front() == '/') full.erase(0, 1);
    }
    return full;
}

std::string MountFs::parentOf(const std::string& path) {
    const size_t i = path.rfind('/');
    if (i == std::string::npos || i == 0) return "/";
    return path.substr(0, i);
}

std::string MountFs::leafOf(const std::string& path) {
    const size_t i = path.rfind('/');
    return i == std::string::npos ? path : path.substr(i + 1);
}

// ── errors ───────────────────────────────────────────────────────────────────────────────────────────

int MountFs::engineErr(int32_t rc, int fallbackErrno) const {
    switch (rc) {
        case VE_OK: return 0;
        case VE_ERR_READ_ONLY: return -EROFS;
        case VE_ERR_INVALID_ARG: return -EINVAL;
        case VE_ERR_NOT_UNLOCKED: return -EIO;
        default: return fallbackErrno;
    }
}

int MountFs::writeFailureErrno(size_t len) {
    uint64_t total = 0, freeBytes = 0;
    if (ve_get_space_info(vol_, &total, &freeBytes) == VE_OK && total > 0 && freeBytes < len) return -ENOSPC;
    return -EIO;
}

// ── directory cache ──────────────────────────────────────────────────────────────────────────────────

int MountFs::loadDirLocked(const std::string& dir, bool force, DirCache** out) {
    const auto now = std::chrono::steady_clock::now();
    auto it = dirs_.find(dir);
    if (!force && it != dirs_.end() && now - it->second.stamp < kDirTtl) {
        *out = &it->second;
        return 0;
    }
    const std::string ep = enginePath(dir);
    std::vector<DirItem> items;
    ve_buffer buf{nullptr, 0};
    int32_t rc = ve_list_directory(vol_, ep.c_str(), &buf);
    if (rc != VE_OK) {
        ve_buffer_free(&buf);
        return engineErr(rc, -EIO);
    }
    const bool ok = parseWire(buf, items);
    ve_buffer_free(&buf);
    if (!ok) return -EIO;
    // Links are listed separately; failing to list them must not hide the real entries.
    ve_buffer lbuf{nullptr, 0};
    if (ve_list_symlinks(vol_, ep.c_str(), &lbuf) == VE_OK) parseWire(lbuf, items);
    ve_buffer_free(&lbuf);

    if (dirs_.size() >= kMaxCachedDirs && it == dirs_.end()) {
        // Drop expired directories first, then the oldest one.
        for (auto d = dirs_.begin(); d != dirs_.end();) {
            d = (now - d->second.stamp >= kDirTtl) ? dirs_.erase(d) : std::next(d);
        }
        if (dirs_.size() >= kMaxCachedDirs) {
            auto oldest = dirs_.begin();
            for (auto d = dirs_.begin(); d != dirs_.end(); ++d) {
                if (d->second.stamp < oldest->second.stamp) oldest = d;
            }
            dirs_.erase(oldest);
        }
    }
    DirCache& dc = dirs_[dir];
    dc.stamp = now;
    dc.entries.clear();
    dc.folded.clear();
    for (auto& item : items) {
        if (caseInsensitive_) dc.folded[lowerAscii(item.name)] = item.name;
        dc.entries[item.name] = item.attr;
    }
    *out = &dc;
    return 0;
}

int MountFs::lookupLocked(const std::string& path, Attr& out) {
    if (isRoot(path)) {
        out = Attr{NodeType::Dir, 0, nowSecs()};
        return 0;
    }
    DirCache* dc = nullptr;
    int rc = loadDirLocked(parentOf(path), false, &dc);
    if (rc != 0) return rc;
    const std::string name = leafOf(path);
    auto it = dc->entries.find(name);
    if (it == dc->entries.end() && caseInsensitive_) {
        auto f = dc->folded.find(lowerAscii(name));
        if (f != dc->folded.end()) it = dc->entries.find(f->second);
    }
    if (it == dc->entries.end()) return -ENOENT;
    out = it->second;
    return 0;
}

int MountFs::statLocked(const std::string& path, Attr& out) {
    int rc = lookupLocked(path, out);
    // Files that are being written (and, for folder vaults, may not exist in the vault yet) are visible
    // with their in-flight size, like any filesystem with a write-back cache.
    bool pending = false;
    uint64_t pendingSize = 0;
    for (auto& kv : handles_) {
        const Handle& h = *kv.second;
        if (!h.canWrite || h.orphan || h.path != path) continue;
        if (h.mode == HMode::Idle) continue;
        pending = true;
        pendingSize = std::max(pendingSize, h.size);
    }
    if (pending) {
        if (rc == -ENOENT) {
            out = Attr{NodeType::File, pendingSize, nowSecs()};
            return 0;
        }
        if (rc == 0 && out.type == NodeType::File) {
            out.size = pendingSize;
            out.mtime = std::max<int64_t>(out.mtime, nowSecs());
        }
    }
    return rc;
}

void MountFs::cachePutLocked(const std::string& path, const Attr& attr) {
    if (isRoot(path)) return;
    auto it = dirs_.find(parentOf(path));
    if (it == dirs_.end()) return;
    const std::string name = leafOf(path);
    it->second.entries[name] = attr;
    if (caseInsensitive_) it->second.folded[lowerAscii(name)] = name;
}

void MountFs::cacheEraseLocked(const std::string& path) {
    if (isRoot(path)) return;
    auto it = dirs_.find(parentOf(path));
    if (it == dirs_.end()) return;
    const std::string name = leafOf(path);
    it->second.entries.erase(name);
    if (caseInsensitive_) it->second.folded.erase(lowerAscii(name));
}

void MountFs::cacheDropTreeLocked(const std::string& path) {
    for (auto it = dirs_.begin(); it != dirs_.end();) {
        if (it->first == path || startsWithPath(it->first, path)) {
            it = dirs_.erase(it);
        } else {
            ++it;
        }
    }
}

int MountFs::nonEmptyDirLocked(const std::string& path) {
    DirCache* dc = nullptr;
    int rc = loadDirLocked(path, true, &dc);
    if (rc != 0) return rc;
    if (!dc->entries.empty()) return -ENOTEMPTY;
    for (auto& kv : handles_) {
        const Handle& h = *kv.second;
        if (!h.orphan && h.canWrite && h.mode != HMode::Idle && parentOf(h.path) == path) return -ENOTEMPTY;
    }
    return 0;
}

// ── metadata ─────────────────────────────────────────────────────────────────────────────────────────

int MountFs::getattr(const std::string& path, Attr& out) {
    std::lock_guard<std::mutex> g(mu_);
    return statLocked(path, out);
}

int MountFs::readdir(const std::string& path, std::vector<DirItem>& out) {
    std::lock_guard<std::mutex> g(mu_);
    out.clear();
    Attr a;
    int rc = statLocked(path, a);
    if (rc != 0) return rc;
    if (a.type != NodeType::Dir) return -ENOTDIR;
    DirCache* dc = nullptr;
    rc = loadDirLocked(path, true, &dc);
    if (rc != 0) return rc;
    out.reserve(dc->entries.size());
    for (auto& kv : dc->entries) out.push_back(DirItem{kv.first, kv.second});
    // Files that are mid-write and not yet in the vault listing.
    for (auto& kv : handles_) {
        const Handle& h = *kv.second;
        if (!h.canWrite || h.orphan || h.mode == HMode::Idle || parentOf(h.path) != path) continue;
        const std::string name = leafOf(h.path);
        auto existing = std::find_if(out.begin(), out.end(), [&](const DirItem& d) { return d.name == name; });
        if (existing == out.end()) {
            out.push_back(DirItem{name, Attr{NodeType::File, h.size, nowSecs()}});
        } else if (existing->attr.type == NodeType::File) {
            existing->attr.size = std::max(existing->attr.size, h.size);
        }
    }
    return 0;
}

int MountFs::statfs(StatFsInfo& out) {
    std::lock_guard<std::mutex> g(mu_);
    uint64_t total = 0, freeBytes = 0;
    const int32_t rc = ve_get_space_info(vol_, &total, &freeBytes);
    if (rc != VE_OK) return engineErr(rc, -EIO);
    out.blockSize = 4096;
    out.blocks = total / out.blockSize;
    out.blocksFree = freeBytes / out.blockSize;
    out.nameMax = kNameMax;
    return 0;
}

int MountFs::readlink(const std::string& path, std::string& target) {
    std::lock_guard<std::mutex> g(mu_);
    Attr a;
    int rc = lookupLocked(path, a);
    if (rc != 0) return rc;
    if (a.type != NodeType::Symlink) return -EINVAL;
    ve_buffer buf{nullptr, 0};
    const std::string ep = enginePath(path);
    const int32_t erc = ve_read_symlink(vol_, ep.c_str(), &buf);
    if (erc != VE_OK) {
        ve_buffer_free(&buf);
        return engineErr(erc, -EIO);
    }
    target.assign(reinterpret_cast<const char*>(buf.data), buf.len);
    ve_buffer_free(&buf);
    return 0;
}

// ── namespace ────────────────────────────────────────────────────────────────────────────────────────

int MountFs::mkdir(const std::string& path) {
    std::lock_guard<std::mutex> g(mu_);
    if (opt_.readOnly) return -EROFS;
    if (isRoot(path)) return -EEXIST;
    if (leafOf(path).size() > kNameMax) return -ENAMETOOLONG;
    Attr a;
    if (statLocked(path, a) == 0) return -EEXIST;
    int rc = statLocked(parentOf(path), a);
    if (rc != 0) return rc;
    if (a.type != NodeType::Dir) return -ENOTDIR;
    const std::string ep = enginePath(path);
    const int32_t erc = ve_create_directory(vol_, ep.c_str());
    if (erc != VE_OK) return engineErr(erc, writeFailureErrno(4096));
    cachePutLocked(path, Attr{NodeType::Dir, 0, nowSecs()});
    return 0;
}

int MountFs::rmdir(const std::string& path) {
    std::lock_guard<std::mutex> g(mu_);
    if (opt_.readOnly) return -EROFS;
    if (isRoot(path)) return -EBUSY;
    Attr a;
    int rc = statLocked(path, a);
    if (rc != 0) return rc;
    if (a.type != NodeType::Dir) return -ENOTDIR;
    rc = nonEmptyDirLocked(path);
    if (rc != 0) return rc;
    const std::string ep = enginePath(path);
    const int32_t erc = ve_delete_file(vol_, ep.c_str());
    if (erc != VE_OK) return engineErr(erc, -EIO);
    cacheDropTreeLocked(path);
    cacheEraseLocked(path);
    return 0;
}

void MountFs::orphanHandlesLocked(const std::string& path, bool subtree) {
    for (auto& kv : handles_) {
        Handle& h = *kv.second;
        if (h.path == path || (subtree && startsWithPath(h.path, path))) {
            h.orphan = true;
            wipe(h.wbuf);
            wipe(h.mem);
            h.memDirty = false;
            h.streamDirty = false;
        }
    }
}

void MountFs::retargetHandlesLocked(const std::string& from, const std::string& to) {
    for (auto& kv : handles_) {
        Handle& h = *kv.second;
        if (h.path == from) {
            h.path = to;
        } else if (startsWithPath(h.path, from)) {
            h.path = to + h.path.substr(from.size());
        }
    }
}

int MountFs::unlink(const std::string& path) {
    std::lock_guard<std::mutex> g(mu_);
    if (opt_.readOnly) return -EROFS;
    Attr a;
    int rc = statLocked(path, a);
    if (rc != 0) return rc;
    if (a.type == NodeType::Dir) return -EISDIR;
    Attr engineView;
    const bool inEngine = lookupLocked(path, engineView) == 0;
    orphanHandlesLocked(path, false);
    if (inEngine) {
        const std::string ep = enginePath(path);
        const int32_t erc = ve_delete_file(vol_, ep.c_str());
        if (erc != VE_OK) return engineErr(erc, -EIO);
    }
    cacheEraseLocked(path);
    return 0;
}

int MountFs::rename(const std::string& from, const std::string& to, unsigned flags) {
    std::lock_guard<std::mutex> g(mu_);
    if (opt_.readOnly) return -EROFS;
    if (flags & ~1u) return -EINVAL;  // RENAME_EXCHANGE and friends are not supported
    if (isRoot(from) || isRoot(to)) return -EBUSY;
    if (from == to) return 0;
    if (startsWithPath(to, from)) return -EINVAL;  // into its own subtree
    if (leafOf(to).size() > kNameMax) return -ENAMETOOLONG;

    Attr src;
    int rc = statLocked(from, src);
    if (rc != 0) return rc;
    // Commit anything still being written under `from` so the engine sees it before we move it.
    rc = flushPathLocked(from, true);
    if (rc != 0) return rc;
    rc = lookupLocked(from, src);
    if (rc != 0) return rc;

    Attr parent;
    rc = statLocked(parentOf(to), parent);
    if (rc != 0) return rc;
    if (parent.type != NodeType::Dir) return -ENOTDIR;

    Attr dst;
    if (statLocked(to, dst) == 0) {
        if (flags & 1u) return -EEXIST;
        const bool srcDir = src.type == NodeType::Dir, dstDir = dst.type == NodeType::Dir;
        if (srcDir && !dstDir) return -ENOTDIR;
        if (!srcDir && dstDir) return -EISDIR;
        if (dstDir) {
            rc = nonEmptyDirLocked(to);
            if (rc != 0) return rc;
        }
        // POSIX rename replaces the target atomically; the engines cannot, so remove it first.
        Attr dstEngine;
        const bool inEngine = lookupLocked(to, dstEngine) == 0;
        orphanHandlesLocked(to, dstDir);
        if (inEngine) {
            const std::string dep = enginePath(to);
            const int32_t drc = ve_delete_file(vol_, dep.c_str());
            if (drc != VE_OK) return engineErr(drc, -EIO);
        }
        cacheDropTreeLocked(to);
        cacheEraseLocked(to);
    }
    const std::string fromEp = enginePath(from), toEp = enginePath(to);
    const int32_t erc = ve_rename_file(vol_, fromEp.c_str(), toEp.c_str());
    if (erc != VE_OK) return engineErr(erc, -EIO);
    if (src.type == NodeType::Dir) cacheDropTreeLocked(from);
    cacheEraseLocked(from);
    cachePutLocked(to, src);
    retargetHandlesLocked(from, to);
    return 0;
}

int MountFs::symlink(const std::string& target, const std::string& linkPath) {
    std::lock_guard<std::mutex> g(mu_);
    if (opt_.readOnly) return -EROFS;
    if (leafOf(linkPath).size() > kNameMax) return -ENAMETOOLONG;
    Attr a;
    if (statLocked(linkPath, a) == 0) return -EEXIST;
    int rc = statLocked(parentOf(linkPath), a);
    if (rc != 0) return rc;
    if (a.type != NodeType::Dir) return -ENOTDIR;
    const std::string ep = enginePath(linkPath);
    const int32_t erc = ve_create_symlink(vol_, ep.c_str(), target.c_str());
    if (erc != VE_OK) return engineErr(erc, -EPERM);  // absolute / unsupported targets are refused by the engine
    cachePutLocked(linkPath, Attr{NodeType::Symlink, target.size(), nowSecs()});
    return 0;
}

int MountFs::setMtime(const std::string& path, int64_t epochSeconds) {
    std::lock_guard<std::mutex> g(mu_);
    if (opt_.readOnly) return -EROFS;
    Attr a;
    int rc = statLocked(path, a);
    if (rc != 0) return rc;
    if (a.type == NodeType::Symlink) return 0;
    rc = flushPathLocked(path, false);
    if (rc != 0) return rc;
    const std::string ep = enginePath(path);
    const int32_t erc = ve_set_last_modified(vol_, ep.c_str(), epochSeconds < 0 ? 0 : epochSeconds);
    if (erc != VE_OK) {
        // Directory timestamps are best effort (cp -a / rsync set them); not every filesystem can.
        if (a.type == NodeType::Dir) return 0;
        return engineErr(erc, -EIO);
    }
    Attr cur;
    if (lookupLocked(path, cur) == 0) {
        cur.mtime = epochSeconds;
        cachePutLocked(path, cur);
    }
    return 0;
}

// ── handles ──────────────────────────────────────────────────────────────────────────────────────────

MountFs::Handle* MountFs::handleLocked(uint64_t fh) {
    auto it = handles_.find(fh);
    return it == handles_.end() ? nullptr : it->second.get();
}

size_t MountFs::openHandleCount() {
    std::lock_guard<std::mutex> g(mu_);
    return handles_.size();
}

int MountFs::openLocked(const std::string& path, int flags, bool created, uint64_t& fh) {
    const bool wantWrite = (flags & kOpenWrite) != 0;
    if (wantWrite && opt_.readOnly) return -EROFS;
    Attr a;
    int rc = created ? 0 : statLocked(path, a);
    if (rc != 0) return rc;
    if (!created) {
        if (a.type == NodeType::Dir) return -EISDIR;
        if (a.type == NodeType::Symlink) return -ELOOP;
    } else {
        a = Attr{NodeType::File, 0, nowSecs()};
    }
    auto h = std::make_unique<Handle>();
    h->id = nextFh_++;
    h->path = path;
    h->canRead = (flags & kOpenRead) != 0;
    h->canWrite = wantWrite;
    h->size = a.size;

    if (wantWrite) {
        const bool truncating = created || (flags & kOpenTrunc) != 0;
        // Commit anything another handle still owes for this file before we start modifying it.
        if (!created) {
            rc = flushPathLocked(path, false);
            if (rc != 0) return rc;
            Attr fresh;
            if (lookupLocked(path, fresh) == 0) { a = fresh; h->size = a.size; }
        }
        if (!folderVault_) {
            h->mode = HMode::Direct;
            const std::string ep = enginePath(path);
            if (created) {
                const int32_t erc = ve_create_empty_file(vol_, ep.c_str());
                if (erc != VE_OK) return engineErr(erc, writeFailureErrno(4096));
            } else if ((flags & kOpenTrunc) != 0 && a.size != 0) {
                const int32_t erc = ve_truncate(vol_, ep.c_str(), 0);
                if (erc != VE_OK) return engineErr(erc, -EIO);
            }
            if (truncating) {
                h->size = 0;
                cachePutLocked(path, Attr{NodeType::File, 0, nowSecs()});
            }
        } else if (truncating) {
            h->mode = HMode::Stream;
            h->streamDirty = true;  // an (at least empty) file must exist after close
            h->size = 0;
            if (!created) {
                // O_TRUNC empties the file now. (A new file is NOT put in the cache: it is not in the vault
                // until its stream is finished, and getattr/readdir show it from the open handle instead.)
                rc = prepareReplaceLocked(path);
                if (rc != 0) return rc;
                if (!cryfs_) cachePutLocked(path, Attr{NodeType::File, 0, nowSecs()});
            }
        }
        // Folder vault opened for writing without truncation stays Idle until the first write decides
        // between Stream (empty file) and Buffered (modify in place).
    }
    fh = h->id;
    handles_[fh] = std::move(h);
    return 0;
}

int MountFs::open(const std::string& path, int flags, uint64_t& fh) {
    std::lock_guard<std::mutex> g(mu_);
    return openLocked(path, flags, false, fh);
}

int MountFs::create(const std::string& path, int flags, uint64_t& fh) {
    std::lock_guard<std::mutex> g(mu_);
    if (opt_.readOnly) return -EROFS;
    if (isRoot(path)) return -EISDIR;
    if (leafOf(path).size() > kNameMax) return -ENAMETOOLONG;
    Attr a;
    if (statLocked(path, a) == 0) {
        if (flags & kOpenExcl) return -EEXIST;
        if (a.type == NodeType::Dir) return -EISDIR;
        return openLocked(path, flags | kOpenWrite, false, fh);
    }
    int rc = statLocked(parentOf(path), a);
    if (rc != 0) return rc;
    if (a.type != NodeType::Dir) return -ENOTDIR;
    return openLocked(path, flags | kOpenWrite, true, fh);
}

// ── write paths ──────────────────────────────────────────────────────────────────────────────────────

int MountFs::sendStreamChunkLocked(Handle& h, const uint8_t* data, size_t len) {
    const std::string ep = enginePath(h.path);
    size_t done = 0;
    while (done < len || (len == 0 && done == 0)) {
        const size_t n = std::min(kStreamChunk, len - done);
        const int32_t rc = ve_write_file_chunk(vol_, ep.c_str(), static_cast<int64_t>(h.streamSent), data + done, n);
        if (rc != VE_OK) return engineErr(rc, writeFailureErrno(n));
        h.streamSent += n;
        done += n;
        if (len == 0) break;
    }
    return 0;
}

int MountFs::finishStreamLocked(Handle& h) {
    int rc = 0;
    if (!h.wbuf.empty()) {
        rc = sendStreamChunkLocked(h, h.wbuf.data(), h.wbuf.size());
        wipe(h.wbuf);
        if (rc != 0) return rc;
    }
    // A truncate-to-larger left a logical tail that was never written: it reads back as zeros.
    if (h.size > h.streamSent) {
        std::vector<uint8_t> zeros(static_cast<size_t>(std::min<uint64_t>(kStreamChunk, h.size - h.streamSent)), 0);
        while (h.size > h.streamSent) {
            const size_t n = static_cast<size_t>(std::min<uint64_t>(zeros.size(), h.size - h.streamSent));
            rc = sendStreamChunkLocked(h, zeros.data(), n);
            if (rc != 0) return rc;
        }
    }
    if (h.streamSent == 0) {
        rc = sendStreamChunkLocked(h, nullptr, 0);  // starts (and so can commit) an empty file
        if (rc != 0) return rc;
    }
    const std::string ep = enginePath(h.path);
    const int32_t frc = ve_fv_finish_write(vol_, ep.c_str());
    if (frc != VE_OK) return engineErr(frc, writeFailureErrno(0));
    h.streamDirty = false;
    h.committed = true;
    h.size = h.streamSent;
    h.streamSent = 0;  // a later write rewrites the file from scratch (see Buffered)
    cachePutLocked(h.path, Attr{NodeType::File, h.size, nowSecs()});
    return 0;
}

int MountFs::loadBufferedLocked(Handle& h) {
    if (h.memLoaded) {
        h.mode = HMode::Buffered;
        return 0;
    }
    Attr a;
    int rc = lookupLocked(h.path, a);
    uint64_t size = 0;
    if (rc == 0 && a.type == NodeType::File) size = a.size;
    else if (rc != 0 && rc != -ENOENT) return rc;
    if (h.committed) size = h.size;  // the file we just committed
    if (size > opt_.maxBufferBytes) return -EFBIG;
    h.mem.assign(static_cast<size_t>(size), 0);
    const std::string ep = enginePath(h.path);
    uint64_t off = 0;
    while (off < size) {
        const int32_t len = static_cast<int32_t>(std::min<uint64_t>(kReadChunkMax, size - off));
        ve_buffer buf{nullptr, 0};
        const int32_t erc = ve_read_file_chunk(vol_, ep.c_str(), static_cast<int64_t>(off), len, &buf);
        if (erc != VE_OK || buf.len == 0) {
            ve_buffer_free(&buf);
            wipe(h.mem);
            return engineErr(erc, -EIO);
        }
        std::memcpy(h.mem.data() + off, buf.data, buf.len);
        off += buf.len;
        ve_buffer_free(&buf);
    }
    h.memLoaded = true;
    h.mode = HMode::Buffered;
    h.size = size;
    return 0;
}

// gocryptfs and Cryptomator start a fresh file when a write begins at offset 0. CryFS instead lays new
// chunks over the existing content (keeping any longer tail), so a replacement or a shrink must remove the
// old file first -- which is exactly what POSIX O_TRUNC means anyway. No-op for the other formats.
int MountFs::prepareReplaceLocked(const std::string& path) {
    if (!cryfs_) return 0;
    Attr cur;
    if (lookupLocked(path, cur) != 0 || cur.type != NodeType::File) return 0;
    const std::string ep = enginePath(path);
    const int32_t rc = ve_delete_file(vol_, ep.c_str());
    if (rc != VE_OK) return engineErr(rc, -EIO);
    cacheEraseLocked(path);
    return 0;
}

int MountFs::commitBufferedLocked(Handle& h) {
    int prc = prepareReplaceLocked(h.path);
    if (prc != 0) return prc;
    const std::string ep = enginePath(h.path);
    uint64_t off = 0;
    if (h.mem.empty()) {
        const int32_t rc = ve_write_file_chunk(vol_, ep.c_str(), 0, nullptr, 0);
        if (rc != VE_OK) return engineErr(rc, writeFailureErrno(0));
    }
    while (off < h.mem.size()) {
        const size_t n = std::min<size_t>(kStreamChunk, h.mem.size() - static_cast<size_t>(off));
        const int32_t rc = ve_write_file_chunk(vol_, ep.c_str(), static_cast<int64_t>(off), h.mem.data() + off, n);
        if (rc != VE_OK) return engineErr(rc, writeFailureErrno(n));
        off += n;
    }
    const int32_t frc = ve_fv_finish_write(vol_, ep.c_str());
    if (frc != VE_OK) return engineErr(frc, writeFailureErrno(0));
    h.memDirty = false;
    h.size = h.mem.size();
    cachePutLocked(h.path, Attr{NodeType::File, h.size, nowSecs()});
    return 0;
}

int MountFs::flushHandleLocked(Handle& h) {
    if (h.orphan) {
        wipe(h.wbuf);
        h.pendingErr = 0;
        return 0;
    }
    int rc = 0;
    switch (h.mode) {
        case HMode::Direct:
            if (!h.wbuf.empty()) {
                const std::string ep = enginePath(h.path);
                const int32_t erc = ve_write_file_at(vol_, ep.c_str(), static_cast<int64_t>(h.wbufStart),
                                                     h.wbuf.data(), h.wbuf.size());
                rc = erc == VE_OK ? 0 : engineErr(erc, writeFailureErrno(h.wbuf.size()));
                wipe(h.wbuf);
                if (rc == 0) cachePutLocked(h.path, Attr{NodeType::File, h.size, nowSecs()});
            }
            break;
        case HMode::Stream:
            if (h.streamDirty) rc = finishStreamLocked(h);
            break;
        case HMode::Buffered:
            if (h.memDirty) rc = commitBufferedLocked(h);
            break;
        case HMode::Idle: break;
    }
    if (rc == 0 && h.pendingErr != 0) rc = h.pendingErr;
    h.pendingErr = 0;
    return rc;
}

int MountFs::flushPathLocked(const std::string& path, bool includeSubtree, bool directOnly) {
    int first = 0;
    for (auto& kv : handles_) {
        Handle& h = *kv.second;
        if (!h.canWrite) continue;
        // directOnly: only make coalesced container writes visible; never finish a vault stream (that
        // would force a whole-file rewrite the next time its writer continues).
        if (directOnly && h.mode != HMode::Direct) continue;
        if (h.path == path || (includeSubtree && startsWithPath(h.path, path))) {
            const int rc = flushHandleLocked(h);
            if (rc != 0 && first == 0) first = rc;
        }
    }
    return first;
}

int MountFs::writeDirectLocked(Handle& h, const uint8_t* buf, size_t size, uint64_t offset) {
    const std::string ep = enginePath(h.path);
    if (offset > h.size) {
        // A hole: grow the file first so the gap is real zeros (never stale cluster data).
        if (!h.wbuf.empty()) {
            int rc = flushHandleLocked(h);
            if (rc != 0) return rc;
        }
        const int32_t erc = ve_truncate(vol_, ep.c_str(), static_cast<int64_t>(offset));
        if (erc != VE_OK) return engineErr(erc, writeFailureErrno(static_cast<size_t>(offset - h.size)));
        h.size = offset;
    }
    if (!h.wbuf.empty() && offset != h.wbufStart + h.wbuf.size()) {
        int rc = flushHandleLocked(h);
        if (rc != 0) return rc;
    }
    if (h.wbuf.empty()) h.wbufStart = offset;
    h.wbuf.insert(h.wbuf.end(), buf, buf + size);
    h.size = std::max<uint64_t>(h.size, offset + size);
    if (h.wbuf.size() >= kCoalesceFlush) {
        int rc = flushHandleLocked(h);
        if (rc != 0) return rc;
    }
    return 0;
}

int MountFs::writeStreamLocked(Handle& h, const uint8_t* buf, size_t size, uint64_t offset) {
    if (h.committed) {
        // The file was already finished; adding to it means rewriting it, which is what Buffered does.
        return -EAGAIN;  // caller switches to Buffered
    }
    const uint64_t end = h.streamSent + h.wbuf.size();
    if (offset > end) {
        // Zero-fill the gap through the stream, in bounded pieces.
        std::vector<uint8_t> zeros(static_cast<size_t>(std::min<uint64_t>(kCoalesceFlush, offset - end)), 0);
        uint64_t gap = offset - end;
        while (gap > 0) {
            const size_t n = static_cast<size_t>(std::min<uint64_t>(zeros.size(), gap));
            h.wbuf.insert(h.wbuf.end(), zeros.begin(), zeros.begin() + n);
            gap -= n;
            if (h.wbuf.size() >= kCoalesceFlush) {
                int rc = sendStreamChunkLocked(h, h.wbuf.data(), h.wbuf.size());
                wipe(h.wbuf);
                if (rc != 0) return rc;
            }
        }
    } else if (offset < end) {
        if (offset < h.streamSent) {
            // Already handed to the vault; a vault stream cannot be rewound.
            return -EIO;
        }
        // Patch inside the not-yet-sent window.
        const size_t rel = static_cast<size_t>(offset - h.streamSent);
        const size_t overlap = std::min(size, h.wbuf.size() - rel);
        std::memcpy(h.wbuf.data() + rel, buf, overlap);
        buf += overlap;
        size -= overlap;
        offset += overlap;
    }
    if (size > 0) h.wbuf.insert(h.wbuf.end(), buf, buf + size);
    h.size = std::max<uint64_t>(h.size, h.streamSent + h.wbuf.size());
    h.streamDirty = true;
    if (h.wbuf.size() >= kCoalesceFlush) {
        int rc = sendStreamChunkLocked(h, h.wbuf.data(), h.wbuf.size());
        wipe(h.wbuf);
        if (rc != 0) return rc;
    }
    h.wbufStart = h.streamSent;
    return 0;
}

int MountFs::writeBufferedLocked(Handle& h, const uint8_t* buf, size_t size, uint64_t offset) {
    int rc = loadBufferedLocked(h);
    if (rc != 0) return rc;
    if (offset + size > opt_.maxBufferBytes) return -EFBIG;
    if (offset + size > h.mem.size()) h.mem.resize(static_cast<size_t>(offset + size), 0);
    if (size > 0) std::memcpy(h.mem.data() + offset, buf, size);
    h.memDirty = true;
    h.size = h.mem.size();
    return 0;
}

int MountFs::write(uint64_t fh, const uint8_t* buf, size_t size, uint64_t offset) {
    std::lock_guard<std::mutex> g(mu_);
    Handle* h = handleLocked(fh);
    if (!h || !h->canWrite) return -EBADF;
    if (opt_.readOnly) return -EROFS;
    if (h->orphan) return static_cast<int>(size);  // the file was unlinked; POSIX lets the writer carry on
    if (h->pendingErr != 0) {
        const int e = h->pendingErr;
        h->pendingErr = 0;
        return e;
    }
    if (size == 0) return 0;
    int rc = 0;
    if (h->mode == HMode::Direct) {
        rc = writeDirectLocked(*h, buf, size, offset);
    } else {
        if (h->mode == HMode::Idle) {
            Attr a;
            const int lrc = lookupLocked(h->path, a);
            const bool emptyOrNew = lrc == -ENOENT || (lrc == 0 && a.size == 0);
            h->mode = emptyOrNew ? HMode::Stream : HMode::Buffered;
        }
        if (h->mode == HMode::Stream) {
            rc = writeStreamLocked(*h, buf, size, offset);
            if (rc == -EAGAIN) {
                h->mode = HMode::Buffered;
                rc = writeBufferedLocked(*h, buf, size, offset);
            }
        } else {
            rc = writeBufferedLocked(*h, buf, size, offset);
        }
    }
    if (rc != 0) return rc;
    return static_cast<int>(size);
}

int MountFs::flush(uint64_t fh) {
    std::lock_guard<std::mutex> g(mu_);
    Handle* h = handleLocked(fh);
    if (!h) return -EBADF;
    return flushHandleLocked(*h);
}

int MountFs::release(uint64_t fh) {
    std::lock_guard<std::mutex> g(mu_);
    auto it = handles_.find(fh);
    if (it == handles_.end()) return -EBADF;
    const int rc = flushHandleLocked(*it->second);
    handles_.erase(it);
    return rc;
}

void MountFs::closeAll() {
    std::lock_guard<std::mutex> g(mu_);
    for (auto& kv : handles_) flushHandleLocked(*kv.second);
    handles_.clear();
    dirs_.clear();
}

// ── read ─────────────────────────────────────────────────────────────────────────────────────────────

int MountFs::read(uint64_t fh, uint8_t* buf, size_t size, uint64_t offset) {
    std::lock_guard<std::mutex> g(mu_);
    Handle* h = handleLocked(fh);
    if (!h || !h->canRead) return -EBADF;
    if (size == 0) return 0;

    if (h->mode == HMode::Buffered && h->memLoaded) {
        if (offset >= h->mem.size()) return 0;
        const size_t n = std::min<size_t>(size, h->mem.size() - static_cast<size_t>(offset));
        std::memcpy(buf, h->mem.data() + offset, n);
        return static_cast<int>(n);
    }
    if (h->mode == HMode::Stream) {
        // Only the unsent tail is readable back through a stream that has not been committed yet.
        if (offset >= h->size) return 0;
        if (offset >= h->streamSent && offset - h->streamSent < h->wbuf.size()) {
            const size_t rel = static_cast<size_t>(offset - h->streamSent);
            const size_t n = std::min(size, h->wbuf.size() - rel);
            std::memcpy(buf, h->wbuf.data() + rel, n);
            return static_cast<int>(n);
        }
        if (!h->committed) return -EIO;
    }
    if (h->mode == HMode::Direct && !h->wbuf.empty()) {
        const int rc = flushHandleLocked(*h);  // read-your-writes
        if (rc != 0) return rc;
    }
    // Another handle may still owe this file data; make it visible first.
    int frc = flushPathLocked(h->path, false, true);
    if (frc != 0) return frc;

    Attr a;
    int rc = lookupLocked(h->path, a);
    if (rc != 0) return rc;
    if (offset + size > a.size) {
        // The cached size can be stale (written by another route); refresh once before trusting it.
        DirCache* dc = nullptr;
        if (loadDirLocked(parentOf(h->path), true, &dc) == 0) lookupLocked(h->path, a);
    }
    if (offset >= a.size) return 0;
    const size_t want = static_cast<size_t>(std::min<uint64_t>(
        {static_cast<uint64_t>(size), a.size - offset, static_cast<uint64_t>(kReadChunkMax)}));
    ve_buffer out{nullptr, 0};
    const std::string ep = enginePath(h->path);
    const int32_t erc = ve_read_file_chunk(vol_, ep.c_str(), static_cast<int64_t>(offset), static_cast<int32_t>(want), &out);
    if (erc != VE_OK) {
        ve_buffer_free(&out);
        return engineErr(erc, -EIO);
    }
    const size_t n = std::min(want, out.len);
    if (n > 0) std::memcpy(buf, out.data, n);
    ve_buffer_free(&out);
    return static_cast<int>(n);
}

// ── truncate ─────────────────────────────────────────────────────────────────────────────────────────

int MountFs::truncateLocked(const std::string& path, uint64_t size) {
    if (opt_.readOnly) return -EROFS;
    Attr a;
    int rc = statLocked(path, a);
    if (rc != 0) return rc;
    if (a.type == NodeType::Dir) return -EISDIR;
    rc = flushPathLocked(path, false);
    if (rc != 0) return rc;
    Attr cur;
    rc = lookupLocked(path, cur);
    if (rc != 0) return rc;
    if (cur.size == size) return 0;
    const std::string ep = enginePath(path);

    if (!folderVault_) {
        const int32_t erc = ve_truncate(vol_, ep.c_str(), static_cast<int64_t>(size));
        if (erc != VE_OK) return engineErr(erc, writeFailureErrno(static_cast<size_t>(size > cur.size ? size - cur.size : 0)));
    } else {
        // A vault cannot resize in place: rewrite the file at its new size.
        if (size == 0) {
            rc = prepareReplaceLocked(path);
            if (rc != 0) return rc;
            int32_t erc = ve_write_file_chunk(vol_, ep.c_str(), 0, nullptr, 0);
            if (erc == VE_OK) erc = ve_fv_finish_write(vol_, ep.c_str());
            if (erc != VE_OK) return engineErr(erc, -EIO);
        } else {
            if (size > opt_.maxBufferBytes) return -EFBIG;
            Handle tmp;
            tmp.path = path;
            tmp.size = cur.size;
            rc = loadBufferedLocked(tmp);
            if (rc != 0) return rc;
            tmp.mem.resize(static_cast<size_t>(size), 0);
            rc = commitBufferedLocked(tmp);
            if (rc != 0) return rc;
        }
    }
    cachePutLocked(path, Attr{NodeType::File, size, nowSecs()});
    // Write handles that remain open see the new size.
    for (auto& kv : handles_) {
        Handle& h = *kv.second;
        if (h.path == path && !h.orphan && h.canWrite) {
            h.size = size;
            if (h.memLoaded) { h.mem.resize(static_cast<size_t>(size), 0); }
        }
    }
    return 0;
}

int MountFs::truncate(const std::string& path, uint64_t size) {
    std::lock_guard<std::mutex> g(mu_);
    return truncateLocked(path, size);
}

int MountFs::ftruncateLocked(Handle& h, uint64_t size) {
    if (opt_.readOnly) return -EROFS;
    if (!h.canWrite) return -EBADF;
    if (h.orphan) return 0;
    if (h.mode == HMode::Direct) {
        int rc = flushHandleLocked(h);
        if (rc != 0) return rc;
        const std::string ep = enginePath(h.path);
        const int32_t erc = ve_truncate(vol_, ep.c_str(), static_cast<int64_t>(size));
        if (erc != VE_OK) return engineErr(erc, writeFailureErrno(static_cast<size_t>(size > h.size ? size - h.size : 0)));
        h.size = size;
        cachePutLocked(h.path, Attr{NodeType::File, size, nowSecs()});
        return 0;
    }
    if (h.mode == HMode::Idle) {
        Attr a;
        const int lrc = lookupLocked(h.path, a);
        h.mode = (lrc == -ENOENT || (lrc == 0 && a.size == 0)) ? HMode::Stream : HMode::Buffered;
    }
    if (h.mode == HMode::Stream && h.committed) h.mode = HMode::Buffered;
    if (h.mode == HMode::Stream) {
        const uint64_t end = h.streamSent + h.wbuf.size();
        if (size >= h.size) {
            h.size = size;  // zero tail is written lazily when the stream is finished
        } else if (size >= h.streamSent) {
            h.wbuf.resize(static_cast<size_t>(std::min<uint64_t>(size, end) - h.streamSent));
            h.size = size;
        } else {
            return -EIO;  // would have to un-send data already given to the vault
        }
        h.streamDirty = true;
        return 0;
    }
    int rc = loadBufferedLocked(h);
    if (rc != 0) return rc;
    if (size > opt_.maxBufferBytes) return -EFBIG;
    h.mem.resize(static_cast<size_t>(size), 0);
    h.memDirty = true;
    h.size = size;
    return 0;
}

int MountFs::ftruncate(uint64_t fh, uint64_t size) {
    std::lock_guard<std::mutex> g(mu_);
    Handle* h = handleLocked(fh);
    if (!h) return -EBADF;
    return ftruncateLocked(*h, size);
}

}  // namespace vemount
