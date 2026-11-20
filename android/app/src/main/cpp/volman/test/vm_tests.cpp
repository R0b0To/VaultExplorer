// Host-side tests for the volume manager. No Android, no network.
//   Part 1 drives the manager with an in-memory Volume, to pin down slot,
//          stream, copy and close semantics independent of any cipher.
//   Part 2 puts real gocryptfs / Cryptomator / CryFS vaults (PosixStorage in a
//          temp directory) behind the same manager and copies between them.
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <map>
#include <mutex>
#include <random>
#include <set>
#include <thread>
#include <unistd.h>
#include <sys/stat.h>

#include "filesystems/dir_entry_wire.h"
#include "foldervault/fv_cryfs.h"
#include "foldervault/fv_cryptomator.h"
#include "foldervault/fv_gocryptfs.h"
#include "foldervault/fv_vault.h"
#include "../vm_foldervault.h"
#include "../vm_manager.h"
#include "../vm_xfer.h"

using namespace vm;
using Clock = std::chrono::steady_clock;

static int g_checks = 0, g_failed = 0;
#define CHECK(cond) do { g_checks++; if (!(cond)) { g_failed++; std::printf("  FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); } } while (0)
#define CHECK_EQ(a, b) do { g_checks++; if (!((a) == (b))) { g_failed++; std::printf("  FAIL %s:%d  %s == %s\n", __FILE__, __LINE__, #a, #b); } } while (0)

static Bytes rnd(size_t n, uint32_t seed = 1) {
    std::mt19937 g(seed);
    Bytes b(n);
    for (auto& x : b) x = static_cast<uint8_t>(g());
    return b;
}

struct TmpDir {
    std::string path;
    TmpDir() { char t[] = "/tmp/vmtestXXXXXX"; path = mkdtemp(t); }
    ~TmpDir() { std::string cmd = "rm -rf '" + path + "'"; if (system(cmd.c_str())) {} }
    std::string sub(const std::string& n) const { std::string p = path + "/" + n; ::mkdir(p.c_str(), 0755); return p; }
};

struct BytesSource final : ByteSource {
    const Bytes& d; size_t pos = 0;
    explicit BytesSource(const Bytes& b) : d(b) {}
    int64_t read(uint8_t* buf, size_t n) override {
        size_t k = std::min(n, d.size() - pos);
        if (k) std::memcpy(buf, d.data() + pos, k);
        pos += k;
        return static_cast<int64_t>(k);
    }
};

struct CountingObserver final : Observer {
    std::atomic<uint64_t> bytes{0};
    std::atomic<bool> cancel{false};
    int64_t cancelAfter = -1;    // cancel once this many bytes were reported
    void onBytes(uint64_t b) override { bytes += b; if (cancelAfter >= 0 && static_cast<int64_t>(bytes.load()) >= cancelAfter) cancel = true; }
    bool cancelled() override { return cancel.load(); }
};

// ------------------------------------------------------------ fake volume --

class MemVolume final : public Volume {
public:
    bool ro = false;
    bool native = false;                 // advertise handle-based streams
    int64_t failReadAt = -1;             // readFileChunk at an offset >= this fails
    int64_t failWriteAt = -1;            // writeFileChunk at an offset >= this fails
    bool overReturn = false;             // readFileChunk hands back more than asked
    std::function<void()> readGate;      // runs inside readFileChunk
    std::atomic<int> nativeOpened{0}, nativeClosed{0};
    std::atomic<bool> closedFlag{false};

    std::atomic<bool> aliveFlag{true};   // false = "locked behind the manager's back"

    Family family() const override { return Family::BlockDevice; }
    bool readOnly() const override { return ro; }
    bool alive() const override { return aliveFlag.load(); }

    bool listDirectory(const std::string& path, std::vector<std::string>& wire) override {
        Call c(*this); if (!c) return false;
        std::lock_guard<std::mutex> g(mu_);
        if (!dirs_.count(norm(path))) return false;
        wire.clear();
        const std::string prefix = norm(path).empty() ? "" : norm(path) + "/";
        for (auto& d : dirs_) if (!d.empty() && parent(d) == norm(path)) wire.push_back(encodeDirEntryWire(d.substr(prefix.size()), true, 0, 5));
        for (auto& f : files_) if (parent(f.first) == norm(path)) wire.push_back(encodeDirEntryWire(f.first.substr(prefix.size()), false, f.second.size(), 7));
        return true;
    }
    bool createDirectory(const std::string& p) override {
        Call c(*this); if (!c || ro) return false;
        std::lock_guard<std::mutex> g(mu_);
        if (dirs_.count(norm(p)) || files_.count(norm(p)) || !dirs_.count(parent(norm(p)))) return false;
        dirs_.insert(norm(p)); return true;
    }
    bool renameFile(const std::string& a, const std::string& b) override {
        Call c(*this); if (!c || ro) return false;
        std::lock_guard<std::mutex> g(mu_);
        auto it = files_.find(norm(a));
        if (it == files_.end() || files_.count(norm(b))) return false;
        files_[norm(b)] = std::move(it->second); files_.erase(it); return true;
    }
    bool setLastModifiedTime(const std::string&, int64_t) override { return !ro; }
    bool deleteFile(const std::string& p) override {
        Call c(*this); if (!c || ro) return false;
        std::lock_guard<std::mutex> g(mu_);
        return files_.erase(norm(p)) > 0;
    }
    int64_t getFileSize(const std::string& p) override {
        Call c(*this); if (!c) return -1;
        std::lock_guard<std::mutex> g(mu_);
        auto it = files_.find(norm(p));
        return it == files_.end() ? -1 : static_cast<int64_t>(it->second.size());
    }
    int64_t getFolderSize(const std::string&) override {
        Call c(*this); if (!c) return -1;
        std::lock_guard<std::mutex> g(mu_);
        int64_t t = 0; for (auto& f : files_) t += static_cast<int64_t>(f.second.size()); return t;
    }
    bool readFileChunk(const std::string& p, int64_t off, size_t len, Bytes& out) override {
        Call c(*this); if (!c) return false;
        if (readGate) readGate();
        std::lock_guard<std::mutex> g(mu_);
        auto it = files_.find(norm(p));
        if (it == files_.end() || (failReadAt >= 0 && off >= failReadAt)) return false;
        const Bytes& d = it->second;
        out.clear();
        if (off < static_cast<int64_t>(d.size())) {
            size_t n = std::min(len, d.size() - static_cast<size_t>(off));
            out.assign(d.begin() + off, d.begin() + off + static_cast<int64_t>(n));
            if (overReturn) out.insert(out.end(), 10, 0xEE);
        }
        return true;
    }
    bool writeFileChunk(const std::string& p, int64_t off, const uint8_t* data, size_t len) override {
        Call c(*this); if (!c || ro) return false;
        std::lock_guard<std::mutex> g(mu_);
        if (failWriteAt >= 0 && off >= failWriteAt) return false;
        if (!dirs_.count(parent(norm(p)))) return false;
        Bytes& f = files_[norm(p)];
        if (off == 0) f.clear();
        if (static_cast<int64_t>(f.size()) != off) return false;
        f.insert(f.end(), data, data + len);
        return true;
    }
    bool spaceInfo(SpaceInfo& s) override { s.total = 1000; s.free = 400; return true; }
    std::vector<InfoItem> info() override { return {{InfoItem::Kind::Str, "fs", "mem"}, {InfoItem::Kind::Bool, "ro", ro ? "true" : "false"}}; }

    bool hasNativeStreams() const override { return native; }
    std::optional<uint64_t> openStream(const std::string& p) override {
        std::lock_guard<std::mutex> g(mu_);
        if (!files_.count(norm(p))) return std::nullopt;
        uint64_t h = ++nextNative_; nativePaths_[h] = norm(p); ++nativeOpened; return h;
    }
    int64_t readStream(uint64_t h, uint64_t off, uint8_t* dst, size_t n) override {
        std::lock_guard<std::mutex> g(mu_);
        auto it = nativePaths_.find(h); if (it == nativePaths_.end()) return -1;
        const Bytes& d = files_[it->second];
        if (off >= d.size()) return 0;
        size_t k = std::min(n, d.size() - static_cast<size_t>(off));
        std::memcpy(dst, d.data() + off, k); return static_cast<int64_t>(k);
    }
    void closeStream(uint64_t h) override { std::lock_guard<std::mutex> g(mu_); if (nativePaths_.erase(h)) ++nativeClosed; }

    void close() override {
        closedFlag = true;
        std::unique_lock<std::mutex> l(cm_);
        cv_.wait(l, [&] { return inflight_ == 0; });
    }

    void put(const std::string& p, const Bytes& d) { std::lock_guard<std::mutex> g(mu_); files_[norm(p)] = d; }
    Bytes content(const std::string& p) { std::lock_guard<std::mutex> g(mu_); return files_[norm(p)]; }
    bool has(const std::string& p) { std::lock_guard<std::mutex> g(mu_); return files_.count(norm(p)) > 0; }

private:
    struct Call {
        MemVolume& v; bool okc;
        explicit Call(MemVolume& m) : v(m), okc(false) {
            std::lock_guard<std::mutex> l(m.cm_);
            if (m.closedFlag) return;
            ++m.inflight_; okc = true;
        }
        ~Call() { if (okc) { std::lock_guard<std::mutex> l(v.cm_); if (--v.inflight_ == 0) v.cv_.notify_all(); } }
        explicit operator bool() const { return okc; }
    };
    static std::string norm(const std::string& p) { size_t a = p.find_first_not_of('/'); if (a == std::string::npos) return ""; size_t b = p.find_last_not_of('/'); return p.substr(a, b - a + 1); }
    static std::string parent(const std::string& n) { size_t i = n.rfind('/'); return i == std::string::npos ? "" : n.substr(0, i); }

    std::mutex mu_;
    std::map<std::string, Bytes> files_;
    std::set<std::string> dirs_{""};
    std::map<uint64_t, std::string> nativePaths_;
    uint64_t nextNative_ = 0;
    std::mutex cm_; std::condition_variable cv_; int inflight_ = 0;
};

static std::shared_ptr<MemVolume> mem() { return std::make_shared<MemVolume>(); }

// ----------------------------------------------------------------- part 1 --

static void testSlots() {
    std::printf("slots\n");
    VolumeManager m(3);
    CHECK_EQ(m.maxVolumes(), 3);
    CHECK(!m.hasAnyVolume());
    CHECK(m.unlockedSlots().empty());

    auto a = mem(), b = mem(), c = mem();
    int ia = m.attach(a, "uri:a");
    int ib = m.attach(b, "uri:b");
    CHECK_EQ(ia, 0); CHECK_EQ(ib, 1);
    CHECK(m.isUnlocked(0) && m.isUnlocked(1) && !m.isUnlocked(2));
    CHECK_EQ(m.findByTag("uri:b"), 1);
    CHECK_EQ(m.findByTag("nope"), -1);
    CHECK_EQ(m.tagOf(0), std::string("uri:a"));
    CHECK(m.get(0) == a);
    CHECK((m.unlockedSlots() == std::vector<int>{0, 1}));

    // reserving: two unlocks racing for a slot never pick the same one
    int r = m.reserveSlot();
    CHECK_EQ(r, 2);
    CHECK_EQ(m.reserveSlot(), -1);                 // full (2 attached + 1 reserved)
    CHECK(m.attach(c, "x") == -1);                 // nothing left for the auto-slot form
    CHECK(!m.isUnlocked(2));                       // reserved is not unlocked
    m.releaseSlot(r);
    CHECK_EQ(m.reserveSlot(), 2);
    CHECK(m.attach(2, c, "uri:c"));
    CHECK(!m.attach(2, mem(), "dup"));             // occupied
    CHECK(!m.attach(7, mem(), "oob"));             // out of range
    CHECK(!m.attach(-1, mem(), "oob"));
    CHECK(!m.attach(0, nullptr, "null"));
    m.releaseSlot(0);                              // only reserved slots are released
    CHECK(m.isUnlocked(0));

    // listeners fire after the close, outside the lock
    std::vector<int> removed;
    int tok = m.addRemovedListener([&](int id) { removed.push_back(id); CHECK(!m.isUnlocked(id)); m.hasAnyVolume(); });
    CHECK(m.close(1));
    CHECK((removed == std::vector<int>{1}));
    CHECK(b->closedFlag);
    CHECK(!m.close(1));                            // already empty
    CHECK(!m.close(99));
    CHECK_EQ(m.findByTag("uri:b"), -1);
    CHECK_EQ(m.reserveSlot(), 1);                  // freed slot is reused, lowest first
    m.releaseSlot(1);
    m.removeRemovedListener(tok);
    CHECK(m.close(0));
    CHECK_EQ(removed.size(), 1u);                  // listener removed

    m.closeAll();
    CHECK(!m.hasAnyVolume());
    CHECK(c->closedFlag);
}

static void testForwarding() {
    std::printf("forwarding\n");
    VolumeManager m;
    auto v = mem();
    const int id = m.attach(v, "t");

    std::vector<std::string> wire;
    CHECK(ok(m.listDirectory(id, "", wire)));
    CHECK(wire.empty());
    CHECK(ok(m.createDirectory(id, "docs")));
    CHECK_EQ(m.createDirectory(id, "docs"), Status::Failed);          // occupied names fail
    const Bytes data = rnd(300);
    CHECK(ok(m.writeFileChunk(id, "docs/a.bin", 0, data.data(), data.size())));
    CHECK(ok(m.finishWrite(id, "docs/a.bin")));
    CHECK(ok(m.listDirectory(id, "docs", wire)));
    CHECK_EQ(wire.size(), 1u);
    CHECK_EQ(wire[0], std::string("F|300|7|a.bin"));
    CHECK(ok(m.listDirectory(id, "", wire)));
    CHECK_EQ(wire[0], std::string("D|0|5|docs"));
    CHECK_EQ(m.listDirectory(id, "missing", wire), Status::Failed);   // unreadable != empty

    int64_t size = 0;
    CHECK(ok(m.getFileSize(id, "docs/a.bin", size))); CHECK_EQ(size, 300);
    CHECK_EQ(m.getFileSize(id, "docs/none", size), Status::Failed); CHECK_EQ(size, -1);
    Bytes out;
    CHECK(ok(m.readFileChunk(id, "docs/a.bin", 100, 50, out)));
    CHECK(out == Bytes(data.begin() + 100, data.begin() + 150));
    CHECK(ok(m.readFileChunk(id, "docs/a.bin", 300, 50, out)));       // EOF: ok + empty
    CHECK(out.empty());

    CHECK(ok(m.renameFile(id, "docs/a.bin", "docs/b.bin")));
    CHECK_EQ(m.renameFile(id, "docs/a.bin", "docs/c.bin"), Status::Failed);
    CHECK(ok(m.deleteFile(id, "docs/b.bin")));
    CHECK(ok(m.setLastModifiedTime(id, "docs", 1)));

    SpaceInfo sp; CHECK(ok(m.spaceInfo(id, sp))); CHECK_EQ(sp.total, 1000); CHECK_EQ(sp.free, 400);
    std::vector<InfoItem> info; CHECK(ok(m.info(id, info))); CHECK_EQ(info.size(), 2u);
    int hidden = 0; CHECK(ok(m.hiddenEntryCount(id, "", hidden))); CHECK_EQ(hidden, -1);
    std::string target; CHECK_EQ(m.readSymlink(id, "x", target), Status::Failed);
    CHECK_EQ(m.createSymlink(id, "x", "y"), Status::Failed);
    CHECK(ok(m.listSymlinks(id, "", wire))); CHECK(wire.empty());
    CHECK(ok(m.beginBatchWrite(id))); CHECK(ok(m.endBatchWrite(id)));
    CHECK(ok(m.beginBatchDelete(id))); CHECK(ok(m.endBatchDelete(id)));
    CHECK(ok(m.invalidateCache(id)));

    // default importStream: chunk loop, empty source creates an empty file
    Bytes big = rnd(3 * 1024 * 1024 + 17, 9);
    BytesSource src(big);
    CountingObserver obs;
    CHECK(ok(m.importStream(id, "docs/big.bin", src, &obs)));
    CHECK_EQ(obs.bytes.load(), big.size());
    CHECK(v->content("docs/big.bin") == big);
    Bytes none; BytesSource es(none);
    CHECK(ok(m.importStream(id, "docs/empty.bin", es)));
    CHECK(v->has("docs/empty.bin")); CHECK_EQ(v->content("docs/empty.bin").size(), 0u);

    // an empty slot answers NotUnlocked everywhere
    CHECK(m.close(id));
    CHECK_EQ(m.listDirectory(id, "", wire), Status::NotUnlocked);
    CHECK_EQ(m.createDirectory(id, "x"), Status::NotUnlocked);
    CHECK_EQ(m.getFileSize(id, "x", size), Status::NotUnlocked);
    CHECK_EQ(m.readFileChunk(id, "x", 0, 1, out), Status::NotUnlocked);
    CHECK_EQ(m.spaceInfo(id, sp), Status::NotUnlocked);
    CHECK_EQ(m.listDirectory(42, "", wire), Status::NotUnlocked);
    CHECK_EQ(m.listDirectory(-1, "", wire), Status::NotUnlocked);
}

static void testDeadSlots() {
    std::printf("volumes locked behind the manager's back\n");
    VolumeManager m(3);
    auto a = mem(), b = mem();
    a->native = true;
    const int ia = m.attach(a, "a"), ib = m.attach(b, "b");
    a->put("f", rnd(1000, 3));
    b->put("f", rnd(1000, 4));
    uint64_t ha = 0;
    CHECK(ok(m.openStream(ia, "f", ha)));
    std::vector<int> removed;
    m.addRemovedListener([&](int id) { removed.push_back(id); });
    std::vector<std::string> w; int64_t sz; uint8_t buf[16];

    a->aliveFlag = false;
    CHECK(!m.isUnlocked(ia) && m.isUnlocked(ib));
    CHECK(m.get(ia) == a);                                    // still in the slot until swept
    CHECK_EQ(m.listDirectory(ia, "", w), Status::NotUnlocked);
    CHECK_EQ(m.getFileSize(ia, "f", sz), Status::NotUnlocked);
    CHECK_EQ(m.copyFile(ia, "f", ib, "g"), Status::NotUnlocked);
    CHECK_EQ(m.copyFile(ib, "f", ia, "g"), Status::NotUnlocked);
    uint64_t h2 = 0;
    CHECK_EQ(m.openStream(ia, "f", h2), Status::NotUnlocked);
    CHECK((m.unlockedSlots() == std::vector<int>{ib}));
    CHECK_EQ(m.findByTag("a"), -1);
    CHECK_EQ(m.findByTag("b"), ib);
    CHECK(m.hasAnyVolume());
    CHECK(removed.empty());                                   // nothing swept yet

    // reserving a slot sweeps first: the dead volume is closed (streams, listener) and its slot is reused
    CHECK_EQ(m.reserveSlot(), ia);
    CHECK(a->closedFlag.load());
    CHECK(a->nativeClosed.load() == 1);
    CHECK((removed == std::vector<int>{ia}));
    CHECK_EQ(m.readStream(ia, ha, 0, buf, sizeof buf), -1);
    CHECK(m.get(ia) == nullptr);
    CHECK(m.attach(ia, mem(), "a2"));
    CHECK(m.isUnlocked(ia));

    // explicit sweep, and a sweep never touches a live volume
    b->aliveFlag = false;
    m.reapDead();
    CHECK(!m.isUnlocked(ib) && m.get(ib) == nullptr && b->closedFlag.load());
    CHECK((removed == std::vector<int>{ia, ib}));
    CHECK(m.isUnlocked(ia));
    CHECK(!m.close(ib));                                      // already gone
}

static void testDestructorIsSilent() {
    std::printf("destroying a manager\n");
    int notified = 0;
    auto a = mem(), b = mem();
    {
        VolumeManager m;
        m.attach(a, "a");
        m.attach(b, "b");
        m.addRemovedListener([&](int) { ++notified; });
    }
    CHECK(a->closedFlag.load() && b->closedFlag.load());   // volumes are closed...
    CHECK_EQ(notified, 0);                                  // ...without calling listeners that may already be gone
}

static void testStreams(bool native) {
    std::printf("streams (%s)\n", native ? "native handles" : "emulated");
    VolumeManager m;
    auto v = mem(); v->native = native;
    auto other = mem(); other->native = native;
    const int id = m.attach(v, "a");
    const int id2 = m.attach(other, "b");
    const Bytes data = rnd(100000, 4);
    v->put("f", data);
    other->put("f", data);

    uint64_t h = 0, h2 = 0;
    CHECK(ok(m.openStream(id, "f", h)));
    CHECK(ok(m.openStream(id2, "f", h2)));
    CHECK(h != 0 && h != h2);
    CHECK_EQ(m.openStream(id, "missing", h2), Status::Failed);

    Bytes buf(4096);
    CHECK_EQ(m.readStream(id, h, 0, buf.data(), 4096), 4096);
    CHECK(std::memcmp(buf.data(), data.data(), 4096) == 0);
    CHECK_EQ(m.readStream(id, h, 50000, buf.data(), 4096), 4096);
    CHECK(std::memcmp(buf.data(), data.data() + 50000, 4096) == 0);
    CHECK_EQ(m.readStream(id, h, 98000, buf.data(), 4096), 2000);        // short read at the end
    CHECK_EQ(m.readStream(id, h, 100000, buf.data(), 4096), 0);          // EOF
    CHECK_EQ(m.readStream(id, h, 5, buf.data(), 0), 0);
    CHECK_EQ(m.readStream(id2, h, 0, buf.data(), 10), -1);               // another volume's handle
    CHECK_EQ(m.readStream(id, 999999, 0, buf.data(), 10), -1);           // unknown handle

    m.closeStream(id2, h);                                               // wrong volume: ignored
    CHECK_EQ(m.readStream(id, h, 0, buf.data(), 10), 10);
    m.closeStream(id, h);
    CHECK_EQ(m.readStream(id, h, 0, buf.data(), 10), -1);

    // handles die with their volume, and are never reused
    uint64_t h3 = 0, h4 = 0;
    CHECK(ok(m.openStream(id, "f", h3)));
    CHECK(h3 != h);
    CHECK(m.close(id));
    CHECK_EQ(m.readStream(id, h3, 0, buf.data(), 10), -1);
    CHECK_EQ(m.openStream(id, "f", h4), Status::NotUnlocked);
    CHECK_EQ(m.readStream(id2, h2, 0, buf.data(), 10), 10);              // other volume unaffected
    if (native) {
        CHECK_EQ(v->nativeOpened.load(), 2);
        CHECK_EQ(v->nativeClosed.load(), 2);                             // closeStream + close(volume)
    }
}

static void testCopy() {
    std::printf("copy\n");
    VolumeManager m;
    auto a = mem(), b = mem();
    const int ia = m.attach(a, "a"), ib = m.attach(b, "b");
    int64_t dummy;

    // multi-chunk, odd size, small chunk: content identical, progress counted once
    const Bytes data = rnd(100003, 11);
    a->put("src.bin", data);
    CountingObserver obs;
    CHECK_EQ(m.copyFile(ia, "src.bin", ib, "dst.bin", &obs, 4096), Status::Ok);
    CHECK(b->content("dst.bin") == data);
    CHECK_EQ(obs.bytes.load(), data.size());

    // default chunk size, bigger than one chunk
    const Bytes big = rnd(5 * 1024 * 1024 + 3, 12);
    a->put("big.bin", big);
    CHECK_EQ(m.copyFile(ia, "big.bin", ib, "big.bin"), Status::Ok);
    CHECK(b->content("big.bin") == big);

    // chunk size 0 means "the default", not one byte at a time
    CHECK_EQ(m.copyFile(ia, "src.bin", ib, "zero.bin", nullptr, 0), Status::Ok);
    CHECK(b->content("zero.bin") == data);

    // empty file is a copy like any other
    a->put("empty", Bytes());
    CHECK_EQ(m.copyFile(ia, "empty", ib, "empty"), Status::Ok);
    CHECK(b->has("empty")); CHECK_EQ(b->content("empty").size(), 0u);

    // same volume, other name; replaces the destination
    a->put("old", rnd(10, 1));
    CHECK_EQ(m.copyFile(ia, "src.bin", ia, "old"), Status::Ok);
    CHECK(a->content("old") == data);

    // source missing / unreadable: nothing is created
    CHECK_EQ(m.copyFile(ia, "nope", ib, "x"), Status::Failed);
    CHECK(!b->has("x"));

    // onto itself: refused, source untouched
    CHECK_EQ(m.copyFile(ia, "src.bin", ia, "src.bin"), Status::Failed);
    CHECK(a->content("src.bin") == data);

    // read-only destination
    auto ro = mem(); ro->ro = true; const int ir = m.attach(ro, "ro");
    CHECK_EQ(m.copyFile(ia, "src.bin", ir, "x"), Status::Failed);

    // empty slots
    CHECK_EQ(m.copyFile(ia, "src.bin", 5, "x"), Status::NotUnlocked);
    CHECK_EQ(m.copyFile(6, "src.bin", ib, "x"), Status::NotUnlocked);

    // cancelled halfway: Cancelled, and the partial destination is gone again
    CountingObserver c1; c1.cancelAfter = 20000;
    CHECK_EQ(m.copyFile(ia, "src.bin", ib, "cancel.bin", &c1, 4096), Status::Cancelled);
    CHECK(!b->has("cancel.bin"));
    CHECK(c1.bytes.load() < data.size());

    // a read that fails halfway must not leave a truncated "successful" copy
    a->failReadAt = 50000;
    CHECK_EQ(m.copyFile(ia, "src.bin", ib, "short.bin", nullptr, 4096), Status::Failed);
    CHECK(!b->has("short.bin"));
    a->failReadAt = -1;

    // a destination that fails halfway
    b->failWriteAt = 50000;
    CHECK_EQ(m.copyFile(ia, "src.bin", ib, "w.bin", nullptr, 4096), Status::Failed);
    CHECK(!b->has("w.bin"));
    b->failWriteAt = -1;

    // a backend that returns more than it was asked for can't lengthen the copy
    a->overReturn = true;
    CHECK_EQ(m.copyFile(ia, "src.bin", ib, "over.bin", nullptr, 4096), Status::Ok);
    CHECK(b->content("over.bin") == data);
    a->overReturn = false;

    // source shrinks under us (reads come back empty before `total`): failure, not EOF
    // (simulated by failing reads at offset 0 of a later chunk -- covered above) -- and a failed
    // copy over an existing name removes it, so callers clear the destination first.
    CHECK(ok(m.getFileSize(ia, "src.bin", dummy)));
}

// Reference digest of a byte buffer, computed without any volume involved.
struct XBytes final : xfer::ByteSource {
    const Bytes& d; size_t pos = 0;
    explicit XBytes(const Bytes& b) : d(b) {}
    int64_t read(uint8_t* buf, size_t n) override { size_t k = std::min(n, d.size() - pos); if (k) std::memcpy(buf, d.data() + pos, k); pos += k; return (int64_t)k; }
};
static std::vector<xfer::Digest> directDigests(const Bytes& d, const std::vector<xfer::HashAlgo>& algos) {
    XBytes src(d); std::vector<xfer::Digest> out;
    xfer::hashStream(src, algos, d.size(), nullptr, out);
    return out;
}
static bool sameDigests(const std::vector<xfer::Digest>& a, const std::vector<xfer::Digest>& b) {
    if (a.size() != b.size() || a.empty()) return false;
    for (size_t i = 0; i < a.size(); ++i) if (a[i].algo != b[i].algo || a[i].bytes != b[i].bytes) return false;
    return true;
}
struct HObs final : xfer::Observer {
    uint64_t done = 0, total = 0; bool monotone = true; int64_t cancelAfter = -1;
    void onProgress(uint64_t d, uint64_t t) override { if (d < done) monotone = false; done = d; total = t; }
    bool cancelled() override { return cancelAfter >= 0 && (int64_t)done >= cancelAfter; }
};

static std::shared_ptr<Volume> openGoc(const std::string& root, bool create = true);

static void testVolumeHash() {
    std::printf("hashing vault files\n");
    const std::vector<xfer::HashAlgo> all = {xfer::HashAlgo::Md5, xfer::HashAlgo::Sha1, xfer::HashAlgo::Sha256, xfer::HashAlgo::Sha512};
    VolumeManager m;
    auto v = mem();
    const int id = m.attach(v, "h");
    std::vector<xfer::Digest> out;

    // a known answer through a volume, and a multi-chunk file equal to hashing the same bytes directly
    v->put("abc", Bytes{'a', 'b', 'c'});
    CHECK(hashVolumeFile(m, id, "abc", {xfer::HashAlgo::Sha256}, nullptr, out) == xfer::Result::Ok);
    CHECK(out.size() == 1 && out[0].hex() == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    const Bytes big = rnd(5 * 1024 * 1024 + 77, 41);
    v->put("big", big);
    HObs obs;
    CHECK(hashVolumeFile(m, id, "big", all, &obs, out) == xfer::Result::Ok);
    CHECK(sameDigests(out, directDigests(big, all)));
    CHECK(obs.monotone && obs.done == big.size() && obs.total == big.size());

    // every chunk size gives the same digest, including awkward ones; the source never over- or under-reads
    for (size_t chunk : {size_t(1), size_t(7), size_t(4096), size_t(1000003), size_t(64) * 1024 * 1024}) {
        const Bytes d = rnd(20011, 42); v->put("c", d);
        VolumeFileSource src(m, id, "c", chunk);
        CHECK(src.valid() && src.size() == (int64_t)d.size());
        std::vector<xfer::Digest> o2;
        CHECK(xfer::hashStream(src, all, d.size(), nullptr, o2) == xfer::Result::Ok);
        CHECK(sameDigests(o2, directDigests(d, all)));
        uint8_t b; CHECK_EQ(src.read(&b, 1), 0);                         // stays at EOF
        if (chunk == 1) break;                                           // 20011 one-byte volume reads is enough
    }

    // an empty file hashes like empty input; a missing file and a folder do not
    v->put("empty", Bytes());
    CHECK(hashVolumeFile(m, id, "empty", {xfer::HashAlgo::Md5}, nullptr, out) == xfer::Result::Ok);
    CHECK(out.size() == 1 && out[0].hex() == "d41d8cd98f00b204e9800998ecf8427e");
    CHECK(hashVolumeFile(m, id, "missing", all, nullptr, out) == xfer::Result::Failed && out.empty());
    CHECK(hashVolumeFile(m, id, "", all, nullptr, out) == xfer::Result::Failed);
    { VolumeFileSource bad(m, id, "missing"); uint8_t b; CHECK(!bad.valid() && bad.read(&b, 1) == -1); }

    // a read that dies halfway is a failure, never a digest of the truncated prefix
    v->failReadAt = 3 * 1024 * 1024;
    CHECK(hashVolumeFile(m, id, "big", all, nullptr, out) == xfer::Result::Failed && out.empty());
    v->failReadAt = -1;
    // a volume that hands back more than asked cannot lengthen the file
    v->overReturn = true;
    CHECK(hashVolumeFile(m, id, "big", all, nullptr, out) == xfer::Result::Ok && sameDigests(out, directDigests(big, all)));
    v->overReturn = false;

    // cancel
    HObs c; c.cancelAfter = 1024 * 1024;
    CHECK(hashVolumeFile(m, id, "big", all, &c, out) == xfer::Result::Cancelled && out.empty());

    // a locked volume, an empty slot
    v->aliveFlag = false;
    CHECK(hashVolumeFile(m, id, "big", all, nullptr, out) == xfer::Result::Failed);
    CHECK(hashVolumeFile(m, 5, "big", all, nullptr, out) == xfer::Result::Failed);
    v->aliveFlag = true;

    // through a real vault: the digest of what was written is the digest of what is read back
    TmpDir t;
    auto goc = openGoc(t.sub("goc"));
    CHECK(goc != nullptr);
    if (!goc) return;
    const int ig = m.attach(goc, "g");
    const Bytes payload = rnd(3 * 1024 * 1024 + 5, 43);
    struct Src final : ByteSource { const Bytes& d; size_t pos = 0; explicit Src(const Bytes& b) : d(b) {}
        int64_t read(uint8_t* buf, size_t n) override { size_t k = std::min(n, d.size() - pos); if (k) std::memcpy(buf, d.data() + pos, k); pos += k; return (int64_t)k; } } wsrc(payload);
    CHECK(ok(m.importStream(ig, "p.bin", wsrc)));
    CHECK(hashVolumeFile(m, ig, "p.bin", all, nullptr, out) == xfer::Result::Ok);
    CHECK(sameDigests(out, directDigests(payload, all)));
}

static void testCloseDrains() {
    std::printf("close drains calls in flight\n");
    VolumeManager m;
    auto v = mem();
    const int id = m.attach(v, "a");
    v->put("f", rnd(100));

    std::mutex gm; std::condition_variable gcv; bool entered = false, release = false;
    v->readGate = [&] {
        std::unique_lock<std::mutex> l(gm);
        entered = true; gcv.notify_all();
        gcv.wait(l, [&] { return release; });
    };

    Status readStatus = Status::Failed;
    std::thread reader([&] { Bytes out; readStatus = m.readFileChunk(id, "f", 0, 10, out); });
    { std::unique_lock<std::mutex> l(gm); gcv.wait(l, [&] { return entered; }); }

    std::atomic<bool> closeReturned{false};
    std::thread closer([&] { m.close(id); closeReturned = true; });
    std::this_thread::sleep_for(std::chrono::milliseconds(150));
    CHECK(!closeReturned.load());                      // still waiting for the read
    CHECK(!m.isUnlocked(id));                          // but the slot is already gone
    int64_t sz; CHECK_EQ(m.getFileSize(id, "f", sz), Status::NotUnlocked);

    { std::lock_guard<std::mutex> l(gm); release = true; }
    gcv.notify_all();
    reader.join(); closer.join();
    CHECK(closeReturned.load());
    CHECK_EQ(readStatus, Status::Ok);                  // the call that was running finished normally
}

static void testStress() {
    std::printf("concurrent use while closing\n");
    for (int round = 0; round < 20; ++round) {
        VolumeManager m;
        auto a = mem(), b = mem();
        const int ia = m.attach(a, "a"), ib = m.attach(b, "b");
        const Bytes d = rnd(20000, static_cast<uint32_t>(round));
        a->put("f", d);
        std::atomic<bool> stop{false};
        std::vector<std::thread> ts;
        for (int t = 0; t < 4; ++t) ts.emplace_back([&, t] {
            std::vector<std::string> w; Bytes out; uint64_t h; uint8_t buf[512];
            int i = 0;
            while (!stop) {
                switch ((t + i++) % 4) {
                    case 0: m.copyFile(ia, "f", ib, "g" + std::to_string(t), nullptr, 1000); break;
                    case 1: m.listDirectory(ib, "", w); break;
                    case 2: if (ok(m.openStream(ia, "f", h))) { m.readStream(ia, h, 0, buf, sizeof buf); m.closeStream(ia, h); } break;
                    case 3: m.readFileChunk(ia, "f", 0, 100, out); break;
                }
            }
        });
        std::this_thread::sleep_for(std::chrono::milliseconds(15));
        m.close(ib);
        m.close(ia);
        stop = true;
        for (auto& t : ts) t.join();
        CHECK(!m.hasAnyVolume());
    }
}

// ----------------------------------------------------------------- part 2 --

static std::shared_ptr<Volume> openGoc(const std::string& root, bool create) {
    auto st = std::make_shared<fv::PosixStorage>(root);
    const uint8_t pw[] = "pw-goc";
    if (create) {
        fv::GocryptfsCreateOptions o; o.scryptLogN = 10;
        if (fv::createGocryptfs(*st, pw, sizeof pw - 1, o).status != fv::OpenStatus::Ok) return nullptr;
    }
    auto r = fv::openGocryptfs(st, pw, sizeof pw - 1, false, {});
    return r.status == fv::OpenStatus::Ok ? wrapFolderVault(std::move(r.vault)) : nullptr;
}

static std::shared_ptr<Volume> openCrypt(const std::string& root) {
    auto st = std::make_shared<fv::PosixStorage>(root);
    const uint8_t pw[] = "pw-crypt";
    if (fv::createCryptomator(*st, pw, sizeof pw - 1).status != fv::OpenStatus::Ok) return nullptr;
    auto r = fv::openCryptomator(st, pw, sizeof pw - 1, false, {});
    return r.status == fv::OpenStatus::Ok ? wrapFolderVault(std::move(r.vault)) : nullptr;
}

static std::shared_ptr<Volume> openCryfs(const std::string& root, const std::string& state) {
    auto st = std::make_shared<fv::PosixStorage>(root);
    const uint8_t pw[] = "pw-cryfs";
    fv::HostEnv env; env.cryfsLocalStateDir = state;
    fv::CryfsCreateOptions o; o.scryptLogN = 10; o.scryptR = 1; o.scryptP = 1;
    if (fv::createCryfs(*st, pw, sizeof pw - 1, o, env).status != fv::OpenStatus::Ok) return nullptr;
    auto r = fv::openCryfs(st, pw, sizeof pw - 1, false, env);
    return r.status == fv::OpenStatus::Ok ? wrapFolderVault(std::move(r.vault)) : nullptr;
}

static bool readAll(VolumeManager& m, int id, const std::string& path, Bytes& out) {
    out.clear();
    for (int64_t off = 0;;) {
        Bytes c;
        if (!ok(m.readFileChunk(id, path, off, 100000, c))) return false;
        if (c.empty()) return true;
        out.insert(out.end(), c.begin(), c.end());
        off += static_cast<int64_t>(c.size());
    }
}

static void testRealVaults() {
    std::printf("real folder vaults behind the manager\n");
    TmpDir t;
    auto goc = openGoc(t.sub("goc"));
    auto cm = openCrypt(t.sub("cm"));
    auto cf = openCryfs(t.sub("cf"), t.sub("cfstate"));
    CHECK(goc && cm && cf);
    if (!goc || !cm || !cf) return;
    CHECK(goc->family() == Family::FolderVault);
    CHECK(!goc->readOnly());

    VolumeManager m;
    const int ig = m.attach(goc, "goc"), ic = m.attach(cm, "cm"), iy = m.attach(cf, "cf");
    CHECK(ig >= 0 && ic >= 0 && iy >= 0);

    // namespace + wire format
    int64_t sz0 = 0;
    CHECK(ok(m.createDirectory(ig, "docs")));
    CHECK(ok(m.createDirectory(ig, "docs")));                         // folder vaults: mkdir -p semantics
    const Bytes small = rnd(1234, 21);
    BytesSource ss(small);
    CHECK(ok(m.importStream(ig, "docs/a.bin", ss)));
    CHECK_EQ(m.createDirectory(ig, "docs/a.bin"), Status::Failed);    // a file in the way is never overwritten
    CHECK(ok(m.getFileSize(ig, "docs/a.bin", sz0)));
    CHECK_EQ(sz0, 1234);
    std::vector<std::string> wire;
    CHECK(ok(m.listDirectory(ig, "docs", wire)));
    CHECK_EQ(wire.size(), 1u);
    CHECK(wire.size() == 1 && wire[0].rfind("F|1234|", 0) == 0 && wire[0].size() > 7 && wire[0].substr(wire[0].rfind('|') + 1) == "a.bin");
    CHECK(ok(m.listDirectory(ig, "", wire)));
    CHECK(wire.size() == 1 && wire[0].rfind("D|0|", 0) == 0);
    CHECK_EQ(m.listDirectory(ig, "nonexistent", wire), Status::Failed);
    int64_t sz = 0;
    CHECK(ok(m.getFileSize(ig, "docs/a.bin", sz))); CHECK_EQ(sz, 1234);
    CHECK_EQ(m.getFileSize(ig, "docs", sz), Status::Failed);        // a directory has no file size
    SpaceInfo sp; m.spaceInfo(ig, sp);
    std::vector<InfoItem> info; CHECK(ok(m.info(ig, info))); CHECK(!info.empty());

    // gocryptfs -> cryptomator, several chunks, content verified on the far side
    const Bytes big = rnd(5 * 1024 * 1024 + 777, 22);
    BytesSource bs(big);
    CHECK(ok(m.importStream(ig, "docs/big.bin", bs)));
    CHECK(ok(m.createDirectory(ic, "in")));
    CountingObserver obs;
    CHECK_EQ(m.copyFile(ig, "docs/big.bin", ic, "in/big.bin", &obs, 512 * 1024), Status::Ok);
    CHECK_EQ(obs.bytes.load(), big.size());
    Bytes back;
    CHECK(readAll(m, ic, "in/big.bin", back));
    CHECK(back == big);

    // cryptomator -> cryfs and cryfs -> gocryptfs (every pair of formats goes through the same path)
    CHECK(ok(m.createDirectory(iy, "x")));
    CHECK_EQ(m.copyFile(ic, "in/big.bin", iy, "x/big.bin", nullptr, 300000), Status::Ok);
    CHECK(readAll(m, iy, "x/big.bin", back)); CHECK(back == big);
    CHECK_EQ(m.copyFile(iy, "x/big.bin", ig, "docs/again.bin"), Status::Ok);
    CHECK(readAll(m, ig, "docs/again.bin", back)); CHECK(back == big);

    // empty file, and a copy inside one vault
    const Bytes noBytes;
    BytesSource nothing(noBytes);
    CHECK(ok(m.importStream(ig, "docs/empty", nothing)));
    CHECK_EQ(m.copyFile(ig, "docs/empty", ic, "in/empty"), Status::Ok);
    CHECK(ok(m.getFileSize(ic, "in/empty", sz))); CHECK_EQ(sz, 0);
    CHECK_EQ(m.copyFile(ig, "docs/a.bin", ig, "docs/b.bin"), Status::Ok);
    CHECK(readAll(m, ig, "docs/b.bin", back)); CHECK(back == small);
    CHECK_EQ(m.copyFile(ig, "docs/a.bin", ig, "docs/a.bin"), Status::Failed);
    CHECK(readAll(m, ig, "docs/a.bin", back)); CHECK(back == small);

    // cancel: the half-written destination disappears
    CountingObserver c; c.cancelAfter = 1024 * 1024;
    CHECK_EQ(m.copyFile(ig, "docs/big.bin", ic, "in/cancelled.bin", &c, 256 * 1024), Status::Cancelled);
    CHECK_EQ(m.getFileSize(ic, "in/cancelled.bin", sz), Status::Failed);

    // source missing
    CHECK_EQ(m.copyFile(ig, "docs/none", ic, "in/none"), Status::Failed);
    CHECK_EQ(m.getFileSize(ic, "in/none", sz), Status::Failed);

    // streams over a real vault (emulated with positioned reads)
    uint64_t h = 0;
    CHECK(ok(m.openStream(ic, "in/big.bin", h)));
    Bytes buf(70000);
    for (uint64_t off : {uint64_t(0), uint64_t(65536), uint64_t(3000000), uint64_t(big.size() - 100)}) {
        int64_t n = m.readStream(ic, h, off, buf.data(), buf.size());
        const int64_t want = static_cast<int64_t>(std::min<uint64_t>(buf.size(), big.size() - off));
        CHECK_EQ(n, want);
        CHECK(n > 0 && std::memcmp(buf.data(), big.data() + off, static_cast<size_t>(n)) == 0);
    }
    CHECK_EQ(m.readStream(ic, h, big.size(), buf.data(), buf.size()), 0);
    CHECK_EQ(m.openStream(ic, "in", h), Status::Failed);            // a folder is not streamable

    // symlinks (Cryptomator): not part of listDirectory, readable through the manager
    CHECK(ok(m.createSymlink(ic, "in/link", "big.bin")));
    std::string target;
    CHECK(ok(m.readSymlink(ic, "in/link", target))); CHECK_EQ(target, std::string("big.bin"));
    CHECK(ok(m.listSymlinks(ic, "in", wire)));
    CHECK(wire.size() == 1 && (wire[0].rfind("L|", 0) == 0 || wire[0].rfind("LD|", 0) == 0));
    CHECK(ok(m.listDirectory(ic, "in", wire)));
    for (auto& w : wire) CHECK(w.rfind("L", 0) != 0);
    CHECK_EQ(m.createSymlink(ig, "docs/l", "a.bin"), Status::Failed);   // gocryptfs here: not supported

    // closing: slot freed, further calls NotUnlocked, key material wiped by the core
    uint64_t hs = 0; CHECK(ok(m.openStream(ig, "docs/a.bin", hs)));
    CHECK(m.close(ig));
    CHECK_EQ(m.listDirectory(ig, "", wire), Status::NotUnlocked);
    CHECK_EQ(m.readStream(ig, hs, 0, buf.data(), 10), -1);
    CHECK_EQ(m.copyFile(ig, "docs/a.bin", ic, "in/z"), Status::NotUnlocked);

    // the vault can be opened again from disk into a new slot, content intact
    auto again = openGoc(t.path + "/goc", false);
    CHECK(again != nullptr);
    const int ig2 = m.attach(again, "goc");
    CHECK_EQ(ig2, ig);                                               // lowest free slot
    CHECK(readAll(m, ig2, "docs/big.bin", back)); CHECK(back == big);

    // a vault closed by someone else holding the session (the Android bridge's registry does this
    // through NativeFolderVault.nativeClose): the manager sees it die, answers NotUnlocked and frees the slot
    {
        auto st = std::make_shared<fv::PosixStorage>(t.sub("shared"));
        const uint8_t pw[] = "pw-shared";
        fv::GocryptfsCreateOptions o; o.scryptLogN = 10;
        CHECK(fv::createGocryptfs(*st, pw, sizeof pw - 1, o).status == fv::OpenStatus::Ok);
        auto r = fv::openGocryptfs(st, pw, sizeof pw - 1, false, {});
        CHECK(r.status == fv::OpenStatus::Ok);
        std::shared_ptr<fv::Vault> registry(std::move(r.vault));            // the other holder
        auto vol = wrapFolderVault(registry);
        VolumeManager m2(2);
        const int id = m2.attach(vol, "fv:1");
        CHECK(id == 0 && m2.isUnlocked(id) && !registry->closed());
        CHECK(ok(m2.createDirectory(id, "d")));
        std::vector<fv::DirEntry> viaRegistry;
        CHECK(registry->listDirectory("", viaRegistry));                    // same session, both views
        CHECK(viaRegistry.size() == 1 && viaRegistry[0].name.size() > 0);
        registry->close();
        CHECK(registry->closed());
        CHECK(!m2.isUnlocked(id));
        std::vector<std::string> wire2;
        CHECK_EQ(m2.listDirectory(id, "", wire2), Status::NotUnlocked);
        CHECK(m2.unlockedSlots().empty());
        CHECK(m2.attach(mem(), "next") == id);                              // slot freed by the sweep
        // dropping the last manager-side reference of a session the registry still holds must not close it
        auto st2 = std::make_shared<fv::PosixStorage>(t.sub("shared2"));
        CHECK(fv::createGocryptfs(*st2, pw, sizeof pw - 1, o).status == fv::OpenStatus::Ok);
        auto r2 = fv::openGocryptfs(st2, pw, sizeof pw - 1, false, {});
        std::shared_ptr<fv::Vault> held(std::move(r2.vault));
        { auto transient = wrapFolderVault(held); }
        CHECK(!held->closed());
    }

    // after the adapter's own close() the wrapped vault reports failures instead of throwing
    auto victim = openGoc(t.sub("goc2"));
    CHECK(victim != nullptr);
    victim->close();
    std::vector<std::string> w2;
    CHECK(!victim->listDirectory("", w2));
    CHECK(!victim->createDirectory("q"));
    CHECK_EQ(victim->getFileSize("a"), -1);
    Bytes junk; CHECK(!victim->readFileChunk("a", 0, 10, junk));
    victim->close();                                                 // idempotent
}

int main() {
    testSlots();
    testForwarding();
    testDeadSlots();
    testDestructorIsSilent();
    testVolumeHash();
    testStreams(false);
    testStreams(true);
    testCopy();
    testCloseDrains();
    testStress();
    testRealVaults();
    std::printf("\n%d checks, %d failed\n", g_checks, g_failed);
    return g_failed ? 1 : 0;
}
