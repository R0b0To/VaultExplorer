// Host-side tests for vm::BlockVolume (vm_block_volume.cpp), the adapter that
// puts an engine-mounted block-device volume behind vm::Volume.
//
// The real adapter runs against the real VolumeState table (volumes[]) and the
// real fs_ops.h / io/virtual_block_device.h declarations; only the *bottom* is
// replaced: ensureMounted() and the fsXxx() functions are an in-memory
// filesystem defined here at link time (the technique filesystems/test uses).
// So what is tested is the adapter's own behaviour -- locking, "still unlocked"
// checks, read-only refusal, end-of-file vs failure, streams, close() draining --
// and how a VolumeManager holding block volumes *and* real gocryptfs/Cryptomator
// vaults copies between them. What it cannot show is the real FAT/NTFS/ext code
// underneath; that has its own tests (filesystems/test).
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
#include <shared_mutex>
#include <thread>
#include <unistd.h>
#include <sys/stat.h>

#include "bitlocker_backend.h"
#include "block_io.h"
#include "containers/vhd_image.h"
#include "containers/vhdx_image.h"
#include "crypto/cascade.h"
#include "filesystems/dir_entry_wire.h"
#include "filesystems/fs_ops.h"
#include "foldervault/fv_cryptomator.h"
#include "foldervault/fv_gocryptfs.h"
#include "foldervault/fv_vault.h"
#include "io/virtual_block_device.h"
#include "session/volume_state.h"
#include "../vm_block_volume.h"
#include "../vm_foldervault.h"
#include "../vm_manager.h"

// ---- the pieces of the app this test stands in for ----------------------------------
VolumeState volumes[FF_VOLUMES];
std::mutex slotAllocMutex;
bool CompositeBlockDevice::sync() { return true; }
bool VhdImage::pread(uint64_t, unsigned char*, size_t) { return false; }
bool VhdImage::pwrite(uint64_t, const unsigned char*, size_t) { return false; }
bool VhdxImage::pread(uint64_t, unsigned char*, size_t) { return false; }
bool VhdxImage::pwrite(uint64_t, const unsigned char*, size_t) { return false; }
bool bitlockerRead(int, uint64_t, unsigned char*, size_t) { return false; }
bool bitlockerWrite(int, uint64_t, const unsigned char*, size_t) { return false; }
void cascadeEncryptSector(const CascadeContext&, uint64_t, const unsigned char*, unsigned char*) {}
void cascadeDecryptSector(const CascadeContext&, uint64_t, const unsigned char*, unsigned char*) {}
bool luksCipherCrypt(const LuksCipherContext&, bool, uint64_t, uint32_t, const unsigned char*, unsigned char*, size_t) { return false; }
void blockCipherEncryptBlock(const BlockCipherContext&, const unsigned char*, unsigned char*) {}
void blockCipherDecryptBlock(const BlockCipherContext&, const unsigned char*, unsigned char*) {}
bool usbFlushAndSync(int) { return true; }

using namespace vm;

static int g_checks = 0, g_failed = 0;
#define CHECK(cond) do { g_checks++; if (!(cond)) { g_failed++; std::printf("  FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); } } while (0)
#define CHECK_EQ(a, b) do { g_checks++; if (!((a) == (b))) { g_failed++; std::printf("  FAIL %s:%d  %s == %s\n", __FILE__, __LINE__, #a, #b); } } while (0)

// ---- fake engine: one in-memory filesystem per volume id ---------------------------
namespace fake {
struct Fs {
    std::mutex mu;                       // the engine's own data; volumes[id].mutex is the adapter's
    std::map<std::string, std::vector<uint8_t>> files;
    std::set<std::string> dirs{""};
    std::map<std::string, std::string> links;
    bool mountable = true;
    std::atomic<int> mountCalls{0};
    std::atomic<int> maxInside{0}, inside{0};       // detects two calls inside the engine at once
    int64_t failReadAt = -1;
    std::function<void()> readGate;
    std::map<uintptr_t, std::string> streams;
    uintptr_t nextStream = 0x1000;
    uint64_t total = 1 << 20, free = 1 << 19;
    std::string label = "FakeFS";
    uint64_t mtime = 1700000000;
};
Fs g_fs[FF_VOLUMES];

std::string norm(const std::string& p) {
    size_t a = p.find_first_not_of('/');
    if (a == std::string::npos) return "";
    size_t b = p.find_last_not_of('/');
    return p.substr(a, b - a + 1);
}
std::string parent(const std::string& n) { size_t i = n.rfind('/'); return i == std::string::npos ? "" : n.substr(0, i); }

struct Inside {
    Fs& f;
    explicit Inside(Fs& x) : f(x) {
        int n = ++f.inside;
        int m = f.maxInside.load();
        while (n > m && !f.maxInside.compare_exchange_weak(m, n)) {}
    }
    ~Inside() { --f.inside; }
};
}  // namespace fake

bool ensureMounted(int id) { ++fake::g_fs[id].mountCalls; return fake::g_fs[id].mountable; }

bool fsListDirectory(int id, const std::string& path, std::vector<std::string>& out) {
    auto& f = fake::g_fs[id]; fake::Inside in(f); std::lock_guard<std::mutex> g(f.mu);
    const std::string d = fake::norm(path);
    if (!f.dirs.count(d)) return false;
    out.clear();
    const std::string pre = d.empty() ? "" : d + "/";
    for (auto& x : f.dirs) if (!x.empty() && fake::parent(x) == d) out.push_back(encodeDirEntryWire(x.substr(pre.size()), true, 0, f.mtime));
    for (auto& x : f.files) if (fake::parent(x.first) == d) out.push_back(encodeDirEntryWire(x.first.substr(pre.size()), false, x.second.size(), f.mtime));
    return true;
}
void fsListSymlinks(int id, const std::string& path, std::vector<std::string>& out) {
    auto& f = fake::g_fs[id]; std::lock_guard<std::mutex> g(f.mu);
    out.clear();
    for (auto& l : f.links) if (fake::parent(l.first) == fake::norm(path)) out.push_back(encodeSymlinkEntryWire(l.first.substr(l.first.rfind('/') + 1), 0, f.mtime, false));
}
bool fsReadSymlink(int id, const std::string& p, std::string& t) {
    auto& f = fake::g_fs[id]; std::lock_guard<std::mutex> g(f.mu);
    auto it = f.links.find(fake::norm(p)); if (it == f.links.end()) return false; t = it->second; return true;
}
bool fsCreateSymlink(int id, const std::string& p, const std::string& t) {
    auto& f = fake::g_fs[id]; std::lock_guard<std::mutex> g(f.mu); f.links[fake::norm(p)] = t; return true;
}
int64_t fsGetFileSize(int id, const std::string& p) {
    auto& f = fake::g_fs[id]; std::lock_guard<std::mutex> g(f.mu);
    auto it = f.files.find(fake::norm(p)); return it == f.files.end() ? -1 : (int64_t)it->second.size();
}
uint64_t fsGetFolderSize(int id, const std::string&) {
    auto& f = fake::g_fs[id]; std::lock_guard<std::mutex> g(f.mu);
    uint64_t t = 0; for (auto& x : f.files) t += x.second.size(); return t;
}
bool fsReadFileChunk(int id, const std::string& p, uint64_t off, size_t len, std::vector<uint8_t>& out) {
    auto& f = fake::g_fs[id]; fake::Inside in(f);
    if (f.readGate) f.readGate();
    std::lock_guard<std::mutex> g(f.mu);
    out.clear();
    auto it = f.files.find(fake::norm(p));
    if (it == f.files.end() || (f.failReadAt >= 0 && (int64_t)off >= f.failReadAt)) return false;
    const auto& d = it->second;
    if (off >= d.size()) return false;                   // "zero bytes read" is reported as false, as in the real backends
    size_t n = (std::min)(len, d.size() - (size_t)off);
    out.assign(d.begin() + off, d.begin() + off + n);
    return true;
}
bool fsWriteFileChunk(int id, const std::string& p, uint64_t off, const uint8_t* data, size_t len) {
    auto& f = fake::g_fs[id]; fake::Inside in(f); std::lock_guard<std::mutex> g(f.mu);
    const std::string n = fake::norm(p);
    if (!f.dirs.count(fake::parent(n))) return false;
    auto& file = f.files[n];
    if (off == 0) file.clear();                          // truncate-on-offset-0, as documented in fs_ops.h
    if (file.size() != off) return false;
    file.insert(file.end(), data, data + len);
    return true;
}
bool fsDeleteFile(int id, const std::string& p) { auto& f = fake::g_fs[id]; std::lock_guard<std::mutex> g(f.mu); return f.files.erase(fake::norm(p)) > 0; }
bool fsCreateDirectory(int id, const std::string& p) {
    auto& f = fake::g_fs[id]; std::lock_guard<std::mutex> g(f.mu);
    const std::string n = fake::norm(p);
    if (f.files.count(n) || !f.dirs.count(fake::parent(n))) return false;
    f.dirs.insert(n); return true;
}
bool fsRenameFile(int id, const std::string& a, const std::string& b) {
    auto& f = fake::g_fs[id]; std::lock_guard<std::mutex> g(f.mu);
    auto it = f.files.find(fake::norm(a)); if (it == f.files.end() || f.files.count(fake::norm(b))) return false;
    f.files[fake::norm(b)] = std::move(it->second); f.files.erase(fake::norm(a)); return true;
}
bool fsSetLastModifiedTime(int id, const std::string&, uint64_t t) { fake::g_fs[id].mtime = t; return true; }
void fsGetSpaceInfo(int id, uint64_t& t, uint64_t& fr) { t = fake::g_fs[id].total; fr = fake::g_fs[id].free; }
std::string fsGetFilesystemLabel(int id) { return fake::g_fs[id].label; }
void* fsOpenStream(int id, const std::string& p) {
    auto& f = fake::g_fs[id]; std::lock_guard<std::mutex> g(f.mu);
    if (!f.files.count(fake::norm(p))) return nullptr;
    uintptr_t h = f.nextStream++; f.streams[h] = fake::norm(p); return reinterpret_cast<void*>(h);
}
int32_t fsReadStream(int id, void* handle, uint64_t off, uint8_t* dst, size_t n) {
    auto& f = fake::g_fs[id]; std::lock_guard<std::mutex> g(f.mu);
    auto it = f.streams.find(reinterpret_cast<uintptr_t>(handle)); if (it == f.streams.end()) return -1;
    const auto& d = f.files[it->second];
    if (off >= d.size()) return 0;
    size_t k = (std::min)(n, d.size() - (size_t)off); std::memcpy(dst, d.data() + off, k); return (int32_t)k;
}
void fsCloseStream(int id, void* handle) { auto& f = fake::g_fs[id]; std::lock_guard<std::mutex> g(f.mu); f.streams.erase(reinterpret_cast<uintptr_t>(handle)); }

// ---- helpers -------------------------------------------------------------------------
static Bytes rnd(size_t n, uint32_t seed = 1) { std::mt19937 g(seed); Bytes b(n); for (auto& x : b) x = (uint8_t)g(); return b; }

// What the session layer does when it unlocks / locks a container.
static void unlockEngine(int id, bool readOnly = false) {
    fake::Fs fresh;                       // (Fs is not movable; reset field by field)
    auto& f = fake::g_fs[id];
    { std::lock_guard<std::mutex> g(f.mu); f.files.clear(); f.dirs = {""}; f.links.clear(); f.streams.clear(); f.mountable = true; f.failReadAt = -1; f.readGate = nullptr; f.total = 1 << 20; f.free = 1 << 19; f.label = "FakeFS"; }
    std::unique_lock<std::shared_mutex> lk(volumes[id].mutex);
    volumes[id].dataCtxInitialized = true;
    volumes[id].fd = 7;
    volumes[id].readOnly = readOnly;
}
static void lockEngine(int id) {
    std::unique_lock<std::shared_mutex> lk(volumes[id].mutex);
    ++volumes[id].sessionEpoch;           // VolumeState::reset() does this on every teardown
    volumes[id].dataCtxInitialized = false;
    volumes[id].fd = -1;
    std::lock_guard<std::mutex> g(fake::g_fs[id].mu);
    fake::g_fs[id].streams.clear();       // the engine force-closes every stream on lock
}

struct TmpDir {
    std::string path;
    TmpDir() { char t[] = "/tmp/vmbtestXXXXXX"; path = mkdtemp(t); }
    ~TmpDir() { std::string cmd = "rm -rf '" + path + "'"; if (system(cmd.c_str())) {} }
    std::string sub(const std::string& n) const { std::string p = path + "/" + n; ::mkdir(p.c_str(), 0755); return p; }
};
struct CountingObserver final : Observer {
    std::atomic<uint64_t> bytes{0}; std::atomic<bool> cancel{false}; int64_t cancelAfter = -1;
    void onBytes(uint64_t b) override { bytes += b; if (cancelAfter >= 0 && (int64_t)bytes.load() >= cancelAfter) cancel = true; }
    bool cancelled() override { return cancel.load(); }
};
struct BytesSource final : ByteSource {
    const Bytes& d; size_t pos = 0;
    explicit BytesSource(const Bytes& b) : d(b) {}
    int64_t read(uint8_t* buf, size_t n) override { size_t k = (std::min)(n, d.size() - pos); if (k) std::memcpy(buf, d.data() + pos, k); pos += k; return (int64_t)k; }
};
static std::shared_ptr<Volume> openGoc(const std::string& root) {
    auto st = std::make_shared<fv::PosixStorage>(root);
    const uint8_t pw[] = "pw";
    fv::GocryptfsCreateOptions o; o.scryptLogN = 10;
    if (fv::createGocryptfs(*st, pw, 2, o).status != fv::OpenStatus::Ok) return nullptr;
    auto r = fv::openGocryptfs(st, pw, 2, false, {});
    return r.status == fv::OpenStatus::Ok ? wrapFolderVault(std::move(r.vault)) : nullptr;
}
static std::shared_ptr<Volume> openCrypt(const std::string& root) {
    auto st = std::make_shared<fv::PosixStorage>(root);
    const uint8_t pw[] = "pw";
    if (fv::createCryptomator(*st, pw, 2).status != fv::OpenStatus::Ok) return nullptr;
    auto r = fv::openCryptomator(st, pw, 2, false, {});
    return r.status == fv::OpenStatus::Ok ? wrapFolderVault(std::move(r.vault)) : nullptr;
}

// ---- tests ---------------------------------------------------------------------------
static void testActivity() {
    std::printf("activity and refusal\n");
    // never unlocked: every call fails, alive() is false, nothing reaches the engine
    for (int i = 0; i < FF_VOLUMES; ++i) { volumes[i].dataCtxInitialized = false; volumes[i].fd = -1; }
    auto v = wrapBlockVolume(0);
    CHECK(v != nullptr);
    CHECK(!wrapBlockVolume(-1) && !wrapBlockVolume(FF_VOLUMES));
    CHECK(!v->alive());
    std::vector<std::string> w; Bytes out;
    CHECK(!v->listDirectory("", w));
    CHECK_EQ(v->getFileSize("x"), -1);
    CHECK_EQ(v->getFolderSize(""), -1);
    CHECK(!v->readFileChunk("x", 0, 10, out));
    CHECK(!v->createDirectory("d"));
    SpaceInfo sp; CHECK(!v->spaceInfo(sp));
    CHECK(v->info().empty());
    CHECK(!v->openStream("x").has_value());
    CHECK_EQ(fake::g_fs[0].mountCalls.load(), 0);

    unlockEngine(0);
    CHECK(v->alive());
    CHECK(v->family() == Family::BlockDevice);
    CHECK(!v->readOnly());

    // read-only volume: reads work, every mutation is refused
    unlockEngine(1, /*readOnly=*/true);
    fake::g_fs[1].files["f"] = rnd(100);
    auto ro = wrapBlockVolume(1);
    CHECK(ro->readOnly() && ro->alive());
    CHECK(ro->listDirectory("", w) && w.size() == 1);
    CHECK(ro->readFileChunk("f", 0, 50, out) && out.size() == 50);
    CHECK(!ro->createDirectory("d"));
    CHECK(!ro->writeFileChunk("g", 0, out.data(), out.size()));
    CHECK(!ro->renameFile("f", "g"));
    CHECK(!ro->deleteFile("f"));
    CHECK(!ro->setLastModifiedTime("f", 5));
    CHECK(!ro->createSymlink("l", "f"));
    CHECK(fake::g_fs[1].files.count("f") == 1 && !fake::g_fs[1].files.count("g"));

    // unmountable filesystem: a failure, not a crash or an empty listing
    unlockEngine(2);
    fake::g_fs[2].mountable = false;
    auto nm = wrapBlockVolume(2);
    CHECK(nm->alive());                          // unlocked; only the filesystem is unusable
    CHECK(!nm->listDirectory("", w));
    CHECK_EQ(nm->getFileSize("x"), -1);
    CHECK(nm->info().empty());
}

static void testOperations() {
    std::printf("operations\n");
    unlockEngine(0);
    auto v = wrapBlockVolume(0);
    std::vector<std::string> w; Bytes out; SpaceInfo sp;

    CHECK(v->createDirectory("docs"));
    CHECK(!v->createDirectory("nowhere/sub"));                 // parent missing: engine says no
    const Bytes data = rnd(1000, 5);
    CHECK(v->writeFileChunk("docs/a", 0, data.data(), 600));
    CHECK(v->writeFileChunk("docs/a", 600, data.data() + 600, 400));
    CHECK(!v->writeFileChunk("docs/a", 5000, data.data(), 10));   // gap
    CHECK(v->finishWrite("docs/a"));                              // default: nothing to commit
    CHECK_EQ(v->getFileSize("docs/a"), 1000);
    CHECK_EQ(v->getFileSize("docs"), -1);
    CHECK(v->listDirectory("docs", w) && w.size() == 1 && w[0] == "F|1000|1700000000|a");
    CHECK(v->listDirectory("", w) && w.size() == 1 && w[0].rfind("D|0|", 0) == 0);
    CHECK(!v->listDirectory("missing", w));
    CHECK_EQ(v->getFolderSize(""), 1000);

    // end of file is not a failure; a missing file is
    CHECK(v->readFileChunk("docs/a", 100, 200, out) && out == Bytes(data.begin() + 100, data.begin() + 300));
    CHECK(v->readFileChunk("docs/a", 900, 500, out) && out.size() == 100);   // short read at the end
    CHECK(v->readFileChunk("docs/a", 1000, 10, out) && out.empty());         // exactly at EOF
    CHECK(v->readFileChunk("docs/a", 5000, 10, out) && out.empty());         // past EOF
    CHECK(!v->readFileChunk("docs/none", 0, 10, out));
    CHECK(!v->readFileChunk("docs/a", -1, 10, out));
    CHECK(v->readFileChunk("docs/a", 0, 0, out) && out.empty());
    fake::g_fs[0].failReadAt = 500;
    CHECK(!v->readFileChunk("docs/a", 600, 10, out));                        // a real read error stays an error
    fake::g_fs[0].failReadAt = -1;

    // a zero-length write at offset 0 creates the (empty) file -- with null or non-null data
    CHECK(v->writeFileChunk("docs/empty", 0, nullptr, 0));
    CHECK_EQ(v->getFileSize("docs/empty"), 0);
    CHECK(v->writeFileChunk("docs/a", 0, nullptr, 0));                        // and truncates an existing one
    CHECK_EQ(v->getFileSize("docs/a"), 0);
    CHECK(!v->writeFileChunk("docs/x", -1, data.data(), 1));
    CHECK(!v->writeFileChunk("docs/x", 0, data.data(), (size_t)64 * 1024 * 1024 + 1));   // over the chunk cap

    CHECK(v->renameFile("docs/empty", "docs/e2"));
    CHECK(!v->renameFile("docs/empty", "docs/e3"));
    CHECK(v->setLastModifiedTime("docs", 1234));
    CHECK(!v->setLastModifiedTime("docs", -1));
    CHECK(v->deleteFile("docs/e2"));
    CHECK(!v->deleteFile("docs/e2"));

    // symlinks
    CHECK(v->createSymlink("docs/l", "a"));
    auto t = v->readSymlink("docs/l"); CHECK(t && *t == "a");
    CHECK(!v->readSymlink("docs/none").has_value());
    CHECK(v->listSymlinks("docs", w) && w.size() == 1 && w[0].rfind("L|", 0) == 0);

    // space and info
    CHECK(v->spaceInfo(sp)); CHECK_EQ(sp.total, 1 << 20); CHECK_EQ(sp.free, 1 << 19);
    fake::g_fs[0].total = 0;                                                  // query failed in the engine
    CHECK(!v->spaceInfo(sp));
    fake::g_fs[0].total = 1 << 20;
    auto info = v->info(); CHECK(info.size() == 1 && info[0].key == "fileSystem" && info[0].value == "FakeFS");
    fake::g_fs[0].label.clear();
    CHECK(v->info().empty());
    CHECK_EQ(v->hiddenEntryCount(""), -1);
}

static void testStreams() {
    std::printf("streams\n");
    unlockEngine(0);
    auto v = wrapBlockVolume(0);
    const Bytes data = rnd(50000, 6);
    fake::g_fs[0].files["f"] = data;
    CHECK(v->hasNativeStreams());
    auto h = v->openStream("f");
    CHECK(h.has_value() && *h != 0);
    CHECK(!v->openStream("missing").has_value());
    Bytes buf(4096);
    CHECK_EQ(v->readStream(*h, 10000, buf.data(), 4096), 4096);
    CHECK(std::memcmp(buf.data(), data.data() + 10000, 4096) == 0);
    CHECK_EQ(v->readStream(*h, 48000, buf.data(), 4096), 2000);
    CHECK_EQ(v->readStream(*h, 50000, buf.data(), 4096), 0);
    CHECK_EQ(v->readStream(0, 0, buf.data(), 10), -1);
    CHECK_EQ(v->readStream(*h + 1, 0, buf.data(), 10), -1);                   // not a handle of this volume
    v->closeStream(*h);
    CHECK_EQ(v->readStream(*h, 0, buf.data(), 10), -1);
    v->closeStream(*h);                                                       // double close is harmless
    v->closeStream(0);

    // a container locked by the session layer takes its streams with it
    auto h2 = v->openStream("f"); CHECK(h2.has_value());
    lockEngine(0);
    CHECK_EQ(v->readStream(*h2, 0, buf.data(), 10), -1);
    v->closeStream(*h2);                                                      // must not touch the dead engine state
    CHECK(!v->alive());
}

static void testManagerBothFamilies() {
    std::printf("manager over block + folder vaults\n");
    TmpDir t;
    unlockEngine(0);
    unlockEngine(1);
    auto goc = openGoc(t.sub("goc"));
    auto cm = openCrypt(t.sub("cm"));
    CHECK(goc && cm);
    if (!goc || !cm) return;

    VolumeManager m;
    const int ib0 = m.attach(0, wrapBlockVolume(0), "block0") ? 0 : -1;
    const int ib1 = m.attach(1, wrapBlockVolume(1), "block1") ? 1 : -1;
    const int ig = m.attach(goc, "goc");
    const int ic = m.attach(cm, "cm");
    CHECK(ib0 == 0 && ib1 == 1 && ig == 2 && ic == 3);

    CHECK(ok(m.createDirectory(ib0, "docs")));
    CHECK(ok(m.createDirectory(ib1, "in")));
    CHECK(ok(m.createDirectory(ig, "x")));
    CHECK(ok(m.createDirectory(ic, "y")));
    const Bytes big = rnd(3 * 1024 * 1024 + 321, 31);
    BytesSource bs(big);
    CHECK(ok(m.importStream(ib0, "docs/big.bin", bs)));            // default chunk loop onto a block volume
    CHECK(fake::g_fs[0].files["docs/big.bin"] == big);

    // block -> folder vault, folder vault -> folder vault, folder vault -> block, block -> block
    CountingObserver obs;
    CHECK_EQ(m.copyFile(ib0, "docs/big.bin", ig, "x/big.bin", &obs, 512 * 1024), Status::Ok);
    CHECK_EQ(obs.bytes.load(), big.size());
    CHECK_EQ(m.copyFile(ig, "x/big.bin", ic, "y/big.bin"), Status::Ok);
    CHECK_EQ(m.copyFile(ic, "y/big.bin", ib1, "in/back.bin"), Status::Ok);
    CHECK(fake::g_fs[1].files["in/back.bin"] == big);                // identical after crossing three formats
    CHECK_EQ(m.copyFile(ib1, "in/back.bin", ib0, "docs/again.bin"), Status::Ok);
    CHECK(fake::g_fs[0].files["docs/again.bin"] == big);

    // empty file onto and off a block volume
    fake::g_fs[0].files["docs/empty"] = {};
    CHECK_EQ(m.copyFile(ib0, "docs/empty", ig, "x/empty"), Status::Ok);
    CHECK_EQ(m.copyFile(ig, "x/empty", ib1, "in/empty"), Status::Ok);
    CHECK(fake::g_fs[1].files.count("in/empty") == 1 && fake::g_fs[1].files["in/empty"].empty());

    // cancelled / failing copies leave nothing behind on a block destination
    CountingObserver c; c.cancelAfter = 1024 * 1024;
    CHECK_EQ(m.copyFile(ig, "x/big.bin", ib1, "in/cancel.bin", &c, 256 * 1024), Status::Cancelled);
    CHECK(!fake::g_fs[1].files.count("in/cancel.bin"));
    fake::g_fs[0].failReadAt = 1000000;
    CHECK_EQ(m.copyFile(ib0, "docs/big.bin", ic, "y/short.bin", nullptr, 256 * 1024), Status::Failed);
    int64_t shortSize = 0;
    CHECK_EQ(m.getFileSize(ic, "y/short.bin", shortSize), Status::Failed);
    fake::g_fs[0].failReadAt = -1;
    CHECK_EQ(m.copyFile(ib0, "docs/big.bin", ib0, "docs/big.bin"), Status::Failed);   // onto itself
    CHECK(fake::g_fs[0].files["docs/big.bin"] == big);

    // read-only block destination
    unlockEngine(4, /*readOnly=*/true);
    const int ir = m.attach(4, wrapBlockVolume(4), "ro") ? 4 : -1;
    CHECK_EQ(m.copyFile(ig, "x/big.bin", ir, "nope"), Status::Failed);

    // streams of a block volume are native; those of a vault are emulated -- same API
    uint64_t hb = 0, hg = 0;
    CHECK(ok(m.openStream(ib0, "docs/big.bin", hb)));
    CHECK(ok(m.openStream(ig, "x/big.bin", hg)));
    Bytes b1(5000), b2(5000);
    CHECK_EQ(m.readStream(ib0, hb, 123456, b1.data(), 5000), 5000);
    CHECK_EQ(m.readStream(ig, hg, 123456, b2.data(), 5000), 5000);
    CHECK(b1 == b2);
    CHECK_EQ(m.readStream(ig, hb, 0, b1.data(), 10), -1);            // a handle only works on its own volume

    // the container is locked by the session layer behind the manager's back
    std::vector<int> removed;
    m.addRemovedListener([&](int id) { removed.push_back(id); });
    lockEngine(0);
    CHECK(!m.isUnlocked(0));
    CHECK(m.isUnlocked(2));
    std::vector<std::string> wire;
    CHECK_EQ(m.listDirectory(0, "", wire), Status::NotUnlocked);
    CHECK_EQ(m.copyFile(0, "docs/big.bin", ig, "x/z"), Status::NotUnlocked);
    CHECK_EQ(m.copyFile(ig, "x/big.bin", 0, "docs/z"), Status::NotUnlocked);
    CHECK_EQ(m.readStream(ib0, hb, 0, b1.data(), 10), -1);
    CHECK((m.unlockedSlots() == std::vector<int>{1, 2, 3, 4}));
    CHECK_EQ(m.findByTag("block0"), -1);
    CHECK(m.hasAnyVolume());

    // ANOTHER container is now unlocked into the same engine slot. The adapter made for the
    // old session must stay dead -- it must not start serving the new container's files
    // under the old container's name.
    auto stale = m.get(0);
    unlockEngine(0);
    fake::g_fs[0].files["secret-of-the-new-container"] = rnd(64, 77);
    fake::g_fs[0].dirs.insert("newdir");
    CHECK(stale != nullptr && !stale->alive());
    CHECK(!m.isUnlocked(0));
    CHECK_EQ(m.listDirectory(0, "", wire), Status::NotUnlocked);
    Bytes leak; CHECK(!stale->readFileChunk("secret-of-the-new-container", 0, 10, leak) && leak.empty());
    CHECK(!stale->listDirectory("", wire));
    CHECK_EQ(stale->getFileSize("secret-of-the-new-container"), -1);
    CHECK(!stale->createDirectory("planted"));
    CHECK(!fake::g_fs[0].dirs.count("planted"));
    CHECK(!stale->openStream("secret-of-the-new-container").has_value());
    CHECK(!wrapBlockVolume(0)->alive() == false);                       // a fresh adapter for the new session is alive

    // its slot is reusable: attach sweeps the dead volume (listener, streams) and takes the slot
    unlockEngine(0);
    CHECK(m.attach(0, wrapBlockVolume(0), "block0-again"));
    CHECK((removed == std::vector<int>{0}));
    CHECK(m.isUnlocked(0));
    CHECK_EQ(m.listDirectory(0, "", wire), Status::Ok);
    CHECK(wire.empty());                                             // a fresh filesystem, not the old one
    CHECK_EQ(m.readStream(ib0, hb, 0, b1.data(), 10), -1);           // the old stream stays dead

    // closing a slot detaches the adapter; the container itself is the session layer's to lock
    CHECK(m.close(1));
    CHECK(volumes[1].dataCtxInitialized);
    CHECK(volumes[1].fd == 7);
    CHECK(!m.isUnlocked(1));
    CHECK_EQ(m.listDirectory(1, "", wire), Status::NotUnlocked);
    m.closeAll();
    CHECK(!m.hasAnyVolume());
}

static void testCloseDrains() {
    std::printf("close drains calls in flight\n");
    unlockEngine(0);
    auto v = wrapBlockVolume(0);
    fake::g_fs[0].files["f"] = rnd(100);

    std::mutex gm; std::condition_variable gcv; bool entered = false, release = false;
    fake::g_fs[0].readGate = [&] {
        std::unique_lock<std::mutex> l(gm); entered = true; gcv.notify_all(); gcv.wait(l, [&] { return release; });
    };
    bool readOk = false;
    std::thread reader([&] { Bytes out; readOk = v->readFileChunk("f", 0, 10, out); });
    { std::unique_lock<std::mutex> l(gm); gcv.wait(l, [&] { return entered; }); }

    std::atomic<bool> closeReturned{false};
    std::thread closer([&] { v->close(); closeReturned = true; });
    std::this_thread::sleep_for(std::chrono::milliseconds(150));
    CHECK(!closeReturned.load());                       // waiting for the read that holds the volume
    { std::lock_guard<std::mutex> l(gm); release = true; }
    gcv.notify_all();
    reader.join(); closer.join();
    CHECK(closeReturned.load());
    CHECK(readOk);                                      // the call that was running finished normally
    CHECK(!v->alive());
    Bytes out; CHECK(!v->readFileChunk("f", 0, 10, out));
    CHECK(volumes[0].dataCtxInitialized);               // the container is still unlocked
    v->close();                                         // idempotent
    fake::g_fs[0].readGate = nullptr;
}

static void testStress() {
    std::printf("concurrent use while locking and closing\n");
    for (int round = 0; round < 15; ++round) {
        unlockEngine(0); unlockEngine(1);
        TmpDir t;
        auto goc = openGoc(t.sub("g"));
        fake::g_fs[0].files["f"] = rnd(30000, (uint32_t)round);
        fake::g_fs[1].dirs.insert("d");
        VolumeManager m;
        m.attach(0, wrapBlockVolume(0), "b0"); m.attach(1, wrapBlockVolume(1), "b1");
        const int ig = m.attach(goc, "g");
        m.createDirectory(ig, "d");
        std::atomic<bool> stop{false};
        std::vector<std::thread> ts;
        for (int th = 0; th < 4; ++th) ts.emplace_back([&, th] {
            std::vector<std::string> w; Bytes out; uint64_t h; uint8_t buf[256]; int i = 0;
            while (!stop) {
                switch ((th + i++) % 5) {
                    case 0: m.copyFile(0, "f", 1, "d/f" + std::to_string(th), nullptr, 2000); break;
                    case 1: m.copyFile(0, "f", ig, "d/f" + std::to_string(th), nullptr, 2000); break;
                    case 2: m.listDirectory(1, "d", w); break;
                    case 3: if (ok(m.openStream(0, "f", h))) { m.readStream(0, h, 0, buf, sizeof buf); m.closeStream(0, h); } break;
                    case 4: m.readFileChunk(ig, "d/f0", 0, 100, out); break;
                }
            }
        });
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
        lockEngine(0);                       // the session layer locks one container...
        m.reapDead();
        m.close(2);                          // ...and the manager closes a vault, mid-flight
        m.close(1);
        stop = true;
        for (auto& t2 : ts) t2.join();
        CHECK(!m.hasAnyVolume());
        CHECK(fake::g_fs[0].maxInside.load() <= 1);          // the adapter never lets two calls into one engine volume at once
    }
}

int main() {
    testActivity();
    testOperations();
    testStreams();
    testManagerBothFamilies();
    testCloseDrains();
    testStress();
    std::printf("\n%d checks, %d failed\n", g_checks, g_failed);
    return g_failed ? 1 : 0;
}
