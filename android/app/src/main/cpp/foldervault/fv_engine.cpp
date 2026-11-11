#include "fv_engine.h"

#include <algorithm>
#include <cstring>
#include <fcntl.h>
#include <unistd.h>

namespace fv {

static constexpr size_t kBatchBytes = 2 * 1024 * 1024;
static constexpr const char* TAG = "ChunkedFileEngine";

size_t FileFormat::decryptedSize(size_t cipherBytes) const {
    size_t ccs = ciphertextChunk();
    size_t full = cipherBytes / ccs;
    size_t rem = cipherBytes % ccs;
    size_t out = full * cleartextChunk();
    if (rem > 0) {
        if (rem < overhead()) throw Error(Err::Auth, "truncated chunk");
        out += rem - overhead();
    }
    return out;
}

// ---------------------------------------------------------------- locks --

PathLocks::Guard::Guard(PathLocks& l, const std::string& path) : l_(l), path_(path) {
    {
        std::lock_guard<std::mutex> g(l_.mu_);
        auto& e = l_.map_[path_];
        if (!e.m) e.m = std::make_shared<std::mutex>();
        e.refs++;
        m_ = e.m;
    }
    m_->lock();
}

PathLocks::Guard::~Guard() {
    m_->unlock();
    std::lock_guard<std::mutex> g(l_.mu_);
    auto it = l_.map_.find(path_);
    if (it != l_.map_.end() && --it->second.refs == 0) l_.map_.erase(it);
}

// --------------------------------------------------------------- engine --

ChunkedFileEngine::ChunkedFileEngine(Storage& st, const FileFormat& fmt, EngineHost& host,
                                     bool readOnly, const std::atomic<bool>& batch)
    : st_(st), fmt_(fmt), host_(host), readOnly_(readOnly), batch_(batch) {}

ChunkedFileEngine::~ChunkedFileEngine() { close(); }

std::shared_ptr<ChunkedFileEngine::ReadHandle> ChunkedFileEngine::findHandle(const std::string& path) {
    std::lock_guard<std::mutex> g(rmu_);
    auto it = handles_.find(path);
    if (it == handles_.end()) return nullptr;
    lru_.splice(lru_.begin(), lru_, it->second.it);   // most recently used
    return it->second.h;
}

void ChunkedFileEngine::putHandle(const std::string& path, std::shared_ptr<ReadHandle> h) {
    std::lock_guard<std::mutex> g(rmu_);
    auto it = handles_.find(path);
    if (it != handles_.end()) { lru_.erase(it->second.it); handles_.erase(it); }
    lru_.push_front(path);
    handles_[path] = HandleSlot{std::move(h), lru_.begin()};
    // Evicting only drops the map's reference: a thread still reading through
    // that handle keeps its own, and the descriptor closes when it is done.
    while (handles_.size() > kMaxHandles) {
        const std::string& victim = lru_.back();
        handles_.erase(victim);
        lru_.pop_back();
    }
}

void ChunkedFileEngine::dropHandle(const std::string& path) {
    std::lock_guard<std::mutex> g(rmu_);
    auto it = handles_.find(path);
    if (it == handles_.end()) return;
    lru_.erase(it->second.it);
    handles_.erase(it);
}

void ChunkedFileEngine::invalidateRead(const std::string& vpath) {
    std::string path = normalizePath(vpath);
    PathLocks::Guard g(locks_, path);
    dropHandle(path);
    // The path may be a folder that was refreshed because a sync tool changed what is inside it: the cached
    // descriptors, file keys and decrypted chunks of everything below it are stale as well. (A thread that is
    // still reading keeps its own reference; only the cache's is dropped.)
    std::lock_guard<std::mutex> rg(rmu_);
    const std::string prefix = path + "/";
    for (auto it = handles_.begin(); it != handles_.end();) {
        if (it->first.compare(0, prefix.size(), prefix) == 0) {
            lru_.erase(it->second.it);
            it = handles_.erase(it);
        } else {
            ++it;
        }
    }
}

void ChunkedFileEngine::invalidateAll() {
    std::lock_guard<std::mutex> g(rmu_);
    handles_.clear();
    lru_.clear();
}

void ChunkedFileEngine::markWriting(const std::string& path) {
    std::lock_guard<std::mutex> g(wmu_);
    writing_.insert(path);
}
void ChunkedFileEngine::unmarkWriting(const std::string& path) {
    {
        std::lock_guard<std::mutex> g(wmu_);
        writing_.erase(path);
    }
    wcv_.notify_all();
}
void ChunkedFileEngine::waitNotWriting(const std::string& path) {
    std::unique_lock<std::mutex> g(wmu_);
    wcv_.wait(g, [&] { return closed_.load() || !writing_.count(path); });
}

std::shared_ptr<ChunkedFileEngine::ReadHandle> ChunkedFileEngine::openHandle(const std::string& path) {
    std::string physical;
    if (!host_.resolveForRead(path, physical)) throw Error(Err::NotFound, "Path not found");
    FdFile f = st_.openRead(physical, path);
    if (!f.valid()) throw Error(Err::Io, "Could not open file for reading");
    size_t hs = fmt_.headerSize();
    Bytes hdr(hs);
    int64_t n = f.readAt(hdr.data(), hs, 0);
    if (n < 0) throw Error(Err::Io, "header read failed");
    if ((size_t)n < hs) return nullptr;   // empty / header-less file reads as empty
    auto h = std::make_shared<ReadHandle>();
    h->key = fmt_.decodeHeader(hdr.data(), hs);
    h->file = std::move(f);
    return h;
}

std::optional<Bytes> ChunkedFileEngine::readFileChunk(const std::string& vpath, int64_t offset, int length) {
    if (closed_) return std::nullopt;
    std::string path = normalizePath(vpath);
    waitNotWriting(path);
    if (closed_) return std::nullopt;
    PathLocks::Guard g(locks_, path);
    try {
        return readRange(path, offset, length, false);
    } catch (const std::exception& e) {
        logMsg(LogLevel::Debug, TAG, std::string("readFileChunk failed: ") + e.what());
        dropHandle(path);
        return std::nullopt;
    }
}

std::optional<Bytes> ChunkedFileEngine::readRange(const std::string& path, int64_t offset, int length, bool retried) {
    if (offset < 0) return Bytes();
    if (length <= 0) return Bytes();
    const size_t cs = fmt_.cleartextChunk();
    const size_t ccs = fmt_.ciphertextChunk();
    const int64_t hs = (int64_t)fmt_.headerSize();

    auto h = findHandle(path);
    if (!h) {
        h = openHandle(path);
        if (!h) return Bytes();
        putHandle(path, h);
    }

    const int64_t end = offset + length;
    int64_t c = offset / (int64_t)cs;
    const int64_t lastChunk = (end - 1) / (int64_t)cs;
    Bytes out;
    out.reserve((size_t)std::min<int64_t>(length, 4 * 1024 * 1024));
    const size_t maxRun = std::max<size_t>(1, kBatchBytes / ccs);

    auto emit = [&](int64_t chunkIdx, const uint8_t* data, size_t len) {
        int64_t chunkStart = chunkIdx * (int64_t)cs;
        int64_t wantStart = std::max(offset, chunkStart);
        int64_t wantEnd = std::min(end, chunkStart + (int64_t)len);
        if (wantStart < wantEnd) out.insert(out.end(), data + (wantStart - chunkStart), data + (wantEnd - chunkStart));
    };

    while (c <= lastChunk) {
        if (const Bytes* cached = h->cached(c)) {
            emit(c, cached->data(), cached->size());
            if (cached->size() < cs) break;   // short chunk = EOF
            c++;
            continue;
        }
        size_t run = (size_t)std::min<int64_t>(lastChunk - c + 1, (int64_t)maxRun);
        Bytes cipher(run * ccs);
        int64_t n = h->file.readAt(cipher.data(), cipher.size(), hs + c * (int64_t)ccs);
        if (n == FdFile::kNeedsReopen) {
            dropHandle(path);
            if (retried) throw Error(Err::Io, "stream is not seekable");
            return readRange(path, offset, length, true);
        }
        if (n < 0) throw Error(Err::Io, "read failed");
        if (n == 0) break;
        size_t plainLen = fmt_.decryptedSize((size_t)n);
        Bytes plain(plainLen);
        fmt_.decrypt(*h->key, (uint64_t)c, cipher.data(), (size_t)n, plain.data());
        size_t nChunks = (plainLen + cs - 1) / cs;
        for (size_t i = 0; i < nChunks; i++) {
            size_t len = std::min(cs, plainLen - i * cs);
            emit(c + (int64_t)i, plain.data() + i * cs, len);
            if (i + 4 >= nChunks) h->put(c + (int64_t)i, Bytes(plain.begin() + i * cs, plain.begin() + i * cs + len));
        }
        if (plainLen < run * cs) break;   // reached EOF inside this run
        c += (int64_t)run;
    }
    return out;
}

// ---------------------------------------------------------------- writes --

void ChunkedFileEngine::abortWrite(WriteHandle& h) {
    if (h.committed) return;
    h.file.close();
}

void ChunkedFileEngine::flushPending(WriteHandle& h, bool final) {
    const size_t cs = fmt_.cleartextChunk();
    size_t usable = final ? h.pending.size() : (h.pending.size() / cs) * cs;
    if (usable == 0) return;
    Bytes enc(fmt_.encryptedSize(usable));
    fmt_.encrypt(*h.key, h.nextChunk, h.pending.data(), usable, enc.data());
    if (!h.file.writeAll(enc.data(), enc.size())) throw Error(Err::Io, "write failed");
    h.nextChunk += (usable + cs - 1) / cs;
    h.pending.erase(h.pending.begin(), h.pending.begin() + (long)usable);
}

bool ChunkedFileEngine::writeFileChunk(const std::string& vpath, int64_t offset, const uint8_t* data, size_t len) {
    if (readOnly_ || closed_) return false;
    std::string path = normalizePath(vpath);
    markWriting(path);
    std::shared_ptr<WriteHandle> h;
    try {
        PathLocks::Guard g(locks_, path);
        dropHandle(path);
        {
            std::lock_guard<std::mutex> wg(wmu_);
            auto it = openWrites_.find(path);
            if (it != openWrites_.end()) h = it->second;
        }
        if (!h) {
            h = std::make_shared<WriteHandle>();
            h->physical = host_.prepareForWrite(path);
            h->file = st_.openWrite(h->physical, true);
            if (!h->file.valid()) throw Error(Err::Io, "Could not open target for writing");
            Bytes hdr;
            h->key = fmt_.newHeader(hdr);
            if (!h->file.writeAll(hdr.data(), hdr.size())) throw Error(Err::Io, "header write failed");
            std::lock_guard<std::mutex> wg(wmu_);
            openWrites_[path] = h;
        }
        if (offset != h->written) throw Error(Err::Io, "out-of-order write");
        h->pending.insert(h->pending.end(), data, data + len);
        h->written += (int64_t)len;
        flushPending(*h, false);
        return true;
    } catch (const std::exception& e) {
        logMsg(LogLevel::Debug, TAG, std::string("writeFileChunk failed: ") + e.what());
        std::shared_ptr<WriteHandle> dead;
        {
            std::lock_guard<std::mutex> wg(wmu_);
            auto it = openWrites_.find(path);
            if (it != openWrites_.end()) { dead = it->second; openWrites_.erase(it); }
        }
        if (dead) { abortWrite(*dead); host_.abortedWrite(path, dead->physical); }
        unmarkWriting(path);
        return false;
    }
}

bool ChunkedFileEngine::finishWrite(const std::string& vpath) {
    std::string path = normalizePath(vpath);
    struct Unmark { ChunkedFileEngine* e; const std::string& p; ~Unmark() { e->unmarkWriting(p); } } unmark{this, path};
    std::shared_ptr<WriteHandle> h;
    try {
        PathLocks::Guard g(locks_, path);
        dropHandle(path);
        {
            std::lock_guard<std::mutex> wg(wmu_);
            auto it = openWrites_.find(path);
            if (it == openWrites_.end()) return true;
            h = it->second;
            openWrites_.erase(it);
        }
        flushPending(*h, true);
        h->file.close();
        h->committed = true;
        if (!batch_) host_.afterWrite(path, h->physical);
        return true;
    } catch (const std::exception& e) {
        logMsg(LogLevel::Debug, TAG, std::string("finishWrite failed: ") + e.what());
        if (h) { abortWrite(*h); host_.abortedWrite(path, h->physical); }
        return false;
    }
}

bool ChunkedFileEngine::writeFrom(const std::string& vpath, ByteSource& src, Progress* p, bool doSync) {
    if (readOnly_ || closed_) return false;
    std::string path = normalizePath(vpath);
    PathLocks::Guard g(locks_, path);
    // See the Kotlin original: the whole write runs under the path lock so a
    // concurrent reader (e.g. a thumbnailer) can never observe a half-written file.
    dropHandle(path);
    std::shared_ptr<WriteHandle> stale;
    {
        std::lock_guard<std::mutex> wg(wmu_);
        auto it = openWrites_.find(path);
        if (it != openWrites_.end()) { stale = it->second; openWrites_.erase(it); }
    }
    if (stale) { abortWrite(*stale); unmarkWriting(path); }

    std::string physical;
    try {
        physical = host_.prepareForWrite(path);
        FdFile out = st_.openWrite(physical, true);
        if (!out.valid()) throw Error(Err::Io, "Could not open target for writing");
        Bytes hdr;
        auto key = fmt_.newHeader(hdr);
        if (!out.writeAll(hdr.data(), hdr.size())) throw Error(Err::Io, "header write failed");

        const size_t cs = fmt_.cleartextChunk();
        const size_t batchPlain = std::max<size_t>(1, kBatchBytes / cs) * cs;
        Bytes in(batchPlain), enc;
        uint64_t chunkNo = 0;
        for (;;) {
            size_t got = 0;
            while (got < batchPlain) {
                int64_t r = src.read(in.data() + got, batchPlain - got);
                if (r < 0) throw Error(Err::Io, "source read failed");
                if (r == 0) break;
                got += (size_t)r;
            }
            if (got == 0) break;
            enc.resize(fmt_.encryptedSize(got));
            fmt_.encrypt(*key, chunkNo, in.data(), got, enc.data());
            if (!out.writeAll(enc.data(), enc.size())) throw Error(Err::Io, "write failed");
            chunkNo += (got + cs - 1) / cs;
            if (p) {
                p->onWriteBack(got);
                if (p->cancelled()) throw Error(Err::Cancelled, "cancelled");
            }
            if (got < batchPlain) break;
        }
        // Imports run in bursts and are read straight back; making the length
        // durable here closes off the "stat() sees 0 bytes" class of bug the
        // Kotlin version documented.
        if (doSync) out.sync();
        out.close();
        if (!batch_) host_.afterWrite(path, physical);
        return true;
    } catch (const std::exception& e) {
        logMsg(LogLevel::Warn, TAG, std::string("write failed: ") + e.what());
        if (!physical.empty()) host_.abortedWrite(path, physical);
        return false;
    }
}

namespace {
struct FileSource : ByteSource {
    int fd;
    explicit FileSource(int f) : fd(f) {}
    ~FileSource() override { if (fd >= 0) ::close(fd); }
    int64_t read(uint8_t* buf, size_t n) override {
        for (;;) {
            ssize_t r = ::read(fd, buf, n);
            if (r < 0 && errno == EINTR) continue;
            return r;
        }
    }
};
}  // namespace

bool ChunkedFileEngine::writeBackFile(const std::string& vpath, const std::string& sourceFile, Progress* p) {
    int fd = ::open(sourceFile.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) return false;
    FileSource src(fd);
    return writeFrom(vpath, src, p, false);
}

bool ChunkedFileEngine::writeBackStream(const std::string& vpath, ByteSource& src, Progress* p) {
    return writeFrom(vpath, src, p, true);
}

bool ChunkedFileEngine::extractFile(const std::string& vpath, const std::string& destFile, Progress* p) {
    if (closed_) return false;
    try {
        std::string path = normalizePath(vpath);
        std::string physical;
        if (!host_.resolveForRead(path, physical)) return false;
        FdFile in = st_.openRead(physical, path);
        if (!in.valid()) return false;
        FdFile dst(::open(destFile.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600));
        if (!dst.valid()) return false;

        const size_t hs = fmt_.headerSize();
        Bytes hdr(hs);
        int64_t n = in.readAt(hdr.data(), hs, 0);
        if (n < 0) return false;
        if ((size_t)n < hs) return true;   // empty source: empty destination
        auto key = fmt_.decodeHeader(hdr.data(), hs);

        const size_t ccs = fmt_.ciphertextChunk();
        const size_t cs = fmt_.cleartextChunk();
        const size_t batchCipher = std::max<size_t>(1, kBatchBytes / ccs) * ccs;
        Bytes cipher(batchCipher), plain;
        int64_t off = (int64_t)hs;
        uint64_t chunkNo = 0;
        for (;;) {
            if (closed_) return false;
            int64_t r = in.readAt(cipher.data(), batchCipher, off);
            if (r < 0) return false;
            if (r == 0) break;
            size_t plainLen = fmt_.decryptedSize((size_t)r);
            plain.resize(plainLen);
            fmt_.decrypt(*key, chunkNo, cipher.data(), (size_t)r, plain.data());
            if (!dst.writeAll(plain.data(), plainLen)) return false;
            if (p) {
                p->onExtract(plainLen);
                if (p->cancelled()) return false;
            }
            off += r;
            chunkNo += ((size_t)r + ccs - 1) / ccs;
            if ((size_t)r < batchCipher) break;
        }
        (void)cs;
        return true;
    } catch (const std::exception& e) {
        logMsg(LogLevel::Warn, TAG, std::string("extractFile failed: ") + e.what());
        return false;
    }
}

void ChunkedFileEngine::close() {
    if (closed_.exchange(true)) return;
    std::vector<std::pair<std::string, std::shared_ptr<WriteHandle>>> open;
    {
        std::lock_guard<std::mutex> wg(wmu_);
        for (auto& kv : openWrites_) open.emplace_back(kv.first, kv.second);
        openWrites_.clear();
        writing_.clear();
    }
    wcv_.notify_all();
    for (auto& kv : open) { abortWrite(*kv.second); host_.abortedWrite(kv.first, kv.second->physical); }
    invalidateAll();
}

}  // namespace fv
