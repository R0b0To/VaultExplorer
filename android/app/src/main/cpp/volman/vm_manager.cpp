#include "vm_manager.h"

#include <algorithm>
#include <atomic>
#include <cstring>

namespace vm {

void secureZero(void* p, size_t n) {
    volatile unsigned char* q = static_cast<volatile unsigned char*>(p);
    while (n--) *q++ = 0;
    std::atomic_signal_fence(std::memory_order_seq_cst);
}

// ---------------------------------------------------------------- Volume --

bool Volume::importStream(const std::string& path, ByteSource& src, Observer* obs) {
    constexpr size_t kChunk = 1024 * 1024;
    Bytes buf(kChunk);
    struct Wipe {
        Bytes& b;
        ~Wipe() { secureZero(b.data(), b.size()); }
    } wipe{buf};

    int64_t offset = 0;
    for (;;) {
        if (obs && obs->cancelled()) return false;
        const int64_t n = src.read(buf.data(), buf.size());
        if (n < 0) return false;
        if (n == 0) break;
        if (!writeFileChunk(path, offset, buf.data(), static_cast<size_t>(n))) return false;
        offset += n;
        if (obs) obs->onBytes(static_cast<uint64_t>(n));
    }
    // A write at offset 0 creates (or empties) the file, which is all an empty source needs.
    if (offset == 0 && !writeFileChunk(path, 0, nullptr, 0)) return false;
    return finishWrite(path);
}

// --------------------------------------------------------- VolumeManager --

VolumeManager::VolumeManager(int maxVolumes)
    : max_(maxVolumes > 0 ? maxVolumes : kDefaultMaxVolumes), slots_(static_cast<size_t>(max_)) {}

VolumeManager::~VolumeManager() {
    // Close everything, but tell nobody: a listener may hold references that are already gone by
    // the time the manager is destroyed (it usually lives as long as its host).
    {
        std::lock_guard<std::mutex> g(mu_);
        listeners_.clear();
    }
    closeAll();
}

namespace {
struct SlotView {
    int id;
    std::shared_ptr<Volume> vol;
};
}  // namespace

int VolumeManager::reserveSlot() {
    reapDead();
    std::lock_guard<std::mutex> g(mu_);
    for (int i = 0; i < max_; ++i) {
        Slot& s = slots_[static_cast<size_t>(i)];
        if (!s.vol && !s.reserved) {
            s.reserved = true;
            return i;
        }
    }
    return -1;
}

void VolumeManager::releaseSlot(int volId) {
    if (!inRange(volId)) return;
    std::lock_guard<std::mutex> g(mu_);
    Slot& s = slots_[static_cast<size_t>(volId)];
    if (!s.vol) s.reserved = false;
}

bool VolumeManager::attach(int volId, std::shared_ptr<Volume> v, std::string tag) {
    if (!inRange(volId) || !v) return false;
    reapDead();   // a container locked behind our back must not keep its slot
    std::lock_guard<std::mutex> g(mu_);
    Slot& s = slots_[static_cast<size_t>(volId)];
    if (s.vol) return false;
    s.vol = std::move(v);
    s.tag = std::move(tag);
    s.reserved = false;
    return true;
}

int VolumeManager::attach(std::shared_ptr<Volume> v, std::string tag) {
    if (!v) return -1;
    const int id = reserveSlot();
    if (id < 0) return -1;
    if (!attach(id, std::move(v), std::move(tag))) {
        releaseSlot(id);
        return -1;
    }
    return id;
}

std::shared_ptr<Volume> VolumeManager::get(int volId) const {
    if (!inRange(volId)) return nullptr;
    std::lock_guard<std::mutex> g(mu_);
    return slots_[static_cast<size_t>(volId)].vol;
}

// alive() is evaluated outside mu_: it may look at engine state, and the
// manager's own lock must never wait for that.
std::shared_ptr<Volume> VolumeManager::getLive(int volId) const {
    std::shared_ptr<Volume> v = get(volId);
    return (v && v->alive()) ? v : nullptr;
}

bool VolumeManager::isUnlocked(int volId) const { return getLive(volId) != nullptr; }

bool VolumeManager::hasAnyVolume() const { return !unlockedSlots().empty(); }

int VolumeManager::findByTag(const std::string& tag) const {
    std::vector<SlotView> hits;
    {
        std::lock_guard<std::mutex> g(mu_);
        for (int i = 0; i < max_; ++i) {
            const Slot& s = slots_[static_cast<size_t>(i)];
            if (s.vol && s.tag == tag) hits.push_back({i, s.vol});
        }
    }
    for (auto& h : hits)
        if (h.vol->alive()) return h.id;
    return -1;
}

std::string VolumeManager::tagOf(int volId) const {
    if (!inRange(volId)) return {};
    std::lock_guard<std::mutex> g(mu_);
    const Slot& s = slots_[static_cast<size_t>(volId)];
    return s.vol ? s.tag : std::string();
}

std::vector<int> VolumeManager::unlockedSlots() const {
    std::vector<SlotView> all;
    {
        std::lock_guard<std::mutex> g(mu_);
        for (int i = 0; i < max_; ++i)
            if (slots_[static_cast<size_t>(i)].vol) all.push_back({i, slots_[static_cast<size_t>(i)].vol});
    }
    std::vector<int> out;
    for (auto& v : all)
        if (v.vol->alive()) out.push_back(v.id);
    return out;
}

void VolumeManager::reapDead() {
    std::vector<SlotView> all;
    {
        std::lock_guard<std::mutex> g(mu_);
        for (int i = 0; i < max_; ++i)
            if (slots_[static_cast<size_t>(i)].vol) all.push_back({i, slots_[static_cast<size_t>(i)].vol});
    }
    for (auto& v : all)
        if (!v.vol->alive()) detach(v.id, v.vol);
}

bool VolumeManager::detach(int volId, const std::shared_ptr<Volume>& expected) {
    if (!inRange(volId)) return false;
    std::shared_ptr<Volume> v;
    {
        std::lock_guard<std::mutex> g(mu_);
        Slot& s = slots_[static_cast<size_t>(volId)];
        if (!s.vol || (expected && s.vol != expected)) return false;
        v = std::move(s.vol);
        s.tag.clear();
        s.reserved = false;
    }
    finishClose(volId, std::move(v));
    return true;
}

bool VolumeManager::close(int volId) { return detach(volId, nullptr); }

void VolumeManager::finishClose(int volId, std::shared_ptr<Volume> v) {
    // From here on new calls see NotUnlocked. End the streams before the
    // volume goes away so a native handle is never used after close().
    std::vector<Stream> dead;
    {
        std::lock_guard<std::mutex> g(streamMu_);
        for (auto it = streams_.begin(); it != streams_.end();) {
            if (it->second.volId == volId && it->second.vol == v) {
                dead.push_back(std::move(it->second));
                it = streams_.erase(it);
            } else {
                ++it;
            }
        }
    }
    for (Stream& s : dead)
        if (s.inner) s.vol->closeStream(*s.inner);
    dead.clear();

    v->close();   // waits for calls already running

    std::vector<RemovedListener> ls;
    {
        std::lock_guard<std::mutex> g(mu_);
        for (auto& kv : listeners_) ls.push_back(kv.second);
    }
    for (auto& l : ls) l(volId);
}

void VolumeManager::closeAll() {
    for (int i = 0; i < max_; ++i) close(i);
}

int VolumeManager::addRemovedListener(RemovedListener l) {
    std::lock_guard<std::mutex> g(mu_);
    const int token = nextListener_++;
    listeners_[token] = std::move(l);
    return token;
}

void VolumeManager::removeRemovedListener(int token) {
    std::lock_guard<std::mutex> g(mu_);
    listeners_.erase(token);
}

template <class F>
Status VolumeManager::with(int volId, F&& f) {
    std::shared_ptr<Volume> v = getLive(volId);
    if (!v) return Status::NotUnlocked;
    return f(*v) ? Status::Ok : Status::Failed;
}

// ------------------------------------------------------------- forwarding --

Status VolumeManager::listDirectory(int id, const std::string& path, std::vector<std::string>& wire) {
    return with(id, [&](Volume& v) { return v.listDirectory(path, wire); });
}
Status VolumeManager::listSymlinks(int id, const std::string& path, std::vector<std::string>& wire) {
    return with(id, [&](Volume& v) { return v.listSymlinks(path, wire); });
}
Status VolumeManager::readSymlink(int id, const std::string& path, std::string& target) {
    return with(id, [&](Volume& v) {
        auto t = v.readSymlink(path);
        if (!t) return false;
        target = std::move(*t);
        return true;
    });
}
Status VolumeManager::createSymlink(int id, const std::string& path, const std::string& target) {
    return with(id, [&](Volume& v) { return v.createSymlink(path, target); });
}
Status VolumeManager::hiddenEntryCount(int id, const std::string& path, int& count) {
    return with(id, [&](Volume& v) {
        count = v.hiddenEntryCount(path);
        return true;
    });
}
Status VolumeManager::createDirectory(int id, const std::string& path) {
    return with(id, [&](Volume& v) { return v.createDirectory(path); });
}
Status VolumeManager::renameFile(int id, const std::string& from, const std::string& to) {
    return with(id, [&](Volume& v) { return v.renameFile(from, to); });
}
Status VolumeManager::setLastModifiedTime(int id, const std::string& path, int64_t epochSeconds) {
    return with(id, [&](Volume& v) { return v.setLastModifiedTime(path, epochSeconds); });
}
Status VolumeManager::deleteFile(int id, const std::string& path) {
    return with(id, [&](Volume& v) { return v.deleteFile(path); });
}
Status VolumeManager::getFileSize(int id, const std::string& path, int64_t& size) {
    return with(id, [&](Volume& v) {
        size = v.getFileSize(path);
        return size >= 0;
    });
}
Status VolumeManager::getFolderSize(int id, const std::string& path, int64_t& size) {
    return with(id, [&](Volume& v) {
        size = v.getFolderSize(path);
        return size >= 0;
    });
}
Status VolumeManager::readFileChunk(int id, const std::string& path, int64_t offset, size_t length, Bytes& out) {
    return with(id, [&](Volume& v) { return v.readFileChunk(path, offset, length, out); });
}
Status VolumeManager::writeFileChunk(int id, const std::string& path, int64_t offset, const uint8_t* data, size_t len) {
    return with(id, [&](Volume& v) { return v.writeFileChunk(path, offset, data, len); });
}
Status VolumeManager::finishWrite(int id, const std::string& path) {
    return with(id, [&](Volume& v) { return v.finishWrite(path); });
}
Status VolumeManager::importStream(int id, const std::string& path, ByteSource& src, Observer* obs) {
    return with(id, [&](Volume& v) { return v.importStream(path, src, obs); });
}
Status VolumeManager::beginBatchWrite(int id) {
    return with(id, [&](Volume& v) { v.beginBatchWrite(); return true; });
}
Status VolumeManager::endBatchWrite(int id) {
    return with(id, [&](Volume& v) { v.endBatchWrite(); return true; });
}
Status VolumeManager::beginBatchDelete(int id) {
    return with(id, [&](Volume& v) { v.beginBatchDelete(); return true; });
}
Status VolumeManager::endBatchDelete(int id) {
    return with(id, [&](Volume& v) { v.endBatchDelete(); return true; });
}
Status VolumeManager::invalidateCache(int id, const std::string& path) {
    return with(id, [&](Volume& v) { v.invalidateCache(path); return true; });
}
Status VolumeManager::spaceInfo(int id, SpaceInfo& out) {
    return with(id, [&](Volume& v) { return v.spaceInfo(out); });
}
Status VolumeManager::info(int id, std::vector<InfoItem>& out) {
    return with(id, [&](Volume& v) { out = v.info(); return true; });
}

// ---------------------------------------------------------------- streams --

Status VolumeManager::openStream(int volId, const std::string& path, uint64_t& handle) {
    std::shared_ptr<Volume> v = getLive(volId);
    if (!v) return Status::NotUnlocked;

    Stream s;
    s.volId = volId;
    s.vol = v;
    s.path = path;
    if (v->hasNativeStreams()) {
        s.inner = v->openStream(path);
        if (!s.inner) return Status::Failed;
    } else if (v->getFileSize(path) < 0) {
        return Status::Failed;   // missing, or a directory: fail now rather than on the first read
    }

    const uint64_t h = nextStream_.fetch_add(1);
    {
        std::lock_guard<std::mutex> g(streamMu_);
        streams_[h] = s;
    }
    // close() may have emptied the slot between get() and the insert above; it
    // would then have missed this stream. Take it back out.
    if (get(volId) != v) {
        bool removed = false;
        {
            std::lock_guard<std::mutex> g(streamMu_);
            removed = streams_.erase(h) > 0;
        }
        if (removed && s.inner) v->closeStream(*s.inner);
        return Status::NotUnlocked;
    }
    handle = h;
    return Status::Ok;
}

int64_t VolumeManager::readStream(int volId, uint64_t handle, uint64_t offset, uint8_t* dst, size_t n) {
    Stream s;
    {
        std::lock_guard<std::mutex> g(streamMu_);
        auto it = streams_.find(handle);
        if (it == streams_.end() || it->second.volId != volId) return -1;
        s = it->second;
    }
    if (n == 0) return 0;
    if (offset > static_cast<uint64_t>(INT64_MAX)) return -1;
    if (s.inner) return s.vol->readStream(*s.inner, offset, dst, n);

    Bytes tmp;
    if (!s.vol->readFileChunk(s.path, static_cast<int64_t>(offset), n, tmp)) return -1;
    const size_t k = std::min(tmp.size(), n);
    if (k) std::memcpy(dst, tmp.data(), k);
    secureZero(tmp.data(), tmp.size());
    return static_cast<int64_t>(k);
}

void VolumeManager::closeStream(int volId, uint64_t handle) {
    Stream s;
    {
        std::lock_guard<std::mutex> g(streamMu_);
        auto it = streams_.find(handle);
        if (it == streams_.end() || it->second.volId != volId) return;
        s = std::move(it->second);
        streams_.erase(it);
    }
    if (s.inner) s.vol->closeStream(*s.inner);
}

// ------------------------------------------------------------------- copy --

namespace {

// The source half of a copy: hands a volume file to the destination's
// importStream() chunk by chunk, so the decrypted bytes only ever exist in
// heap buffers. A failed or empty read before `total` bytes were delivered is
// an error, not an end of file -- the destination would otherwise be told the
// stream ended cleanly and commit a truncated file as if it were complete.
class CopySource final : public ByteSource {
public:
    CopySource(Volume& vol, std::string path, int64_t total, size_t chunk, Observer* obs)
        : vol_(vol), path_(std::move(path)), total_(total), chunk_(chunk), obs_(obs) {}
    ~CopySource() override { wipe(); }

    int64_t read(uint8_t* buf, size_t n) override {
        if (n == 0) return 0;
        if (pos_ >= total_) return 0;
        if (curPos_ >= cur_.size()) {
            wipe();
            if (obs_ && obs_->cancelled()) {
                cancelled_ = true;
                return -1;
            }
            const size_t want = static_cast<size_t>(std::min<int64_t>(static_cast<int64_t>(chunk_), total_ - pos_));
            if (!vol_.readFileChunk(path_, pos_, want, cur_) || cur_.empty()) {
                failed_ = true;
                wipe();
                return -1;
            }
            // Never let a backend that hands back more than asked push the copy past the source's size.
            if (cur_.size() > want) {
                secureZero(cur_.data() + want, cur_.size() - want);
                cur_.resize(want);
            }
            curPos_ = 0;
        }
        const size_t take = static_cast<size_t>(std::min<int64_t>(
            std::min<int64_t>(static_cast<int64_t>(n), static_cast<int64_t>(cur_.size() - curPos_)), total_ - pos_));
        std::memcpy(buf, cur_.data() + curPos_, take);
        curPos_ += take;
        pos_ += static_cast<int64_t>(take);
        if (obs_) obs_->onBytes(take);
        return static_cast<int64_t>(take);
    }

    int64_t position() const { return pos_; }
    bool wasCancelled() const { return cancelled_; }

private:
    void wipe() {
        if (!cur_.empty()) secureZero(cur_.data(), cur_.size());
        cur_.clear();
        curPos_ = 0;
    }

    Volume& vol_;
    std::string path_;
    const int64_t total_;
    const size_t chunk_;
    Observer* obs_;
    Bytes cur_;
    size_t curPos_ = 0;
    int64_t pos_ = 0;
    bool cancelled_ = false;
    bool failed_ = false;
};

}  // namespace

Status VolumeManager::copyFile(int srcVol, const std::string& srcPath, int dstVol, const std::string& dstPath,
                               Observer* obs, size_t chunkBytes) {
    std::shared_ptr<Volume> src = getLive(srcVol);
    std::shared_ptr<Volume> dst = getLive(dstVol);
    if (!src || !dst) return Status::NotUnlocked;
    if (srcVol == dstVol && srcPath == dstPath) return Status::Failed;   // would delete the source below
    if (dst->readOnly()) return Status::Failed;

    const int64_t total = src->getFileSize(srcPath);
    if (total < 0) return Status::Failed;
    if (chunkBytes == 0) chunkBytes = kCopyChunkBytes;

    CopySource in(*src, srcPath, total, chunkBytes, obs);
    bool written = false;
    try {
        // Cancellation and progress come from `in`; passing `obs` on as well would count every byte twice.
        written = dst->importStream(dstPath, in, nullptr);
    } catch (...) {
        written = false;
    }
    if (written && in.position() == total) return Status::Ok;

    const bool cancelled = in.wasCancelled() || (obs && obs->cancelled());
    try {
        dst->deleteFile(dstPath);
    } catch (...) {
    }
    return cancelled ? Status::Cancelled : Status::Failed;
}

}  // namespace vm
