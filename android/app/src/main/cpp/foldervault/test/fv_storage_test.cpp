// Storage-level and end-to-end checks for folder vaults on a plain directory (PosixStorage), written to run on
// Windows (fv_storage_win.cpp) and, unchanged, on POSIX (fv_storage.cpp) so both backends are held to the same
// expectations. It follows what a user does: pick an empty folder, create a vault in it, find its config files
// again, unlock it, work in it, lock it and unlock it a second time -- with non-ASCII folder names and paths
// longer than Windows' MAX_PATH.
//
// Build (MinGW or Linux; CMake target foldervault_storage_test): this file + foldervault/*.cpp (the platform's storage) + crypto/{eme,siv,scrypt,
// xchacha20poly1305,cryfs_block_cipher,cryfs_legacy_ciphers}.cpp, linked with mbedcrypto (and bcrypt on Windows).
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <map>
#include <random>
#include <string>
#include <thread>
#include <vector>

#include "../fv_formats.h"
#include "../fv_os.h"
#include "../fv_storage.h"
#include "../fv_vault.h"

using namespace fv;
namespace fs = std::filesystem;

static int g_checks = 0, g_failed = 0;
#define CHECK(cond) do { g_checks++; if (!(cond)) { g_failed++; std::printf("  FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); } } while (0)
#define CHECK_EQ(a, b) do { g_checks++; if (!((a) == (b))) { g_failed++; std::printf("  FAIL %s:%d  %s == %s\n", __FILE__, __LINE__, #a, #b); } } while (0)

static std::string utf8(const fs::path& p) {
    const auto s = p.u8string();
    return std::string(s.begin(), s.end());
}

static Bytes rnd(size_t n, uint32_t seed = 1) {
    std::mt19937 g(seed);
    Bytes b(n);
    for (auto& x : b) x = (uint8_t)g();
    return b;
}

struct MemSource : ByteSource {
    const Bytes& d;
    size_t pos = 0;
    explicit MemSource(const Bytes& b) : d(b) {}
    int64_t read(uint8_t* buf, size_t n) override {
        const size_t k = std::min(n, d.size() - pos);
        if (k) std::memcpy(buf, d.data() + pos, k);
        pos += k;
        return (int64_t)k;
    }
};

static bool put(Vault& v, const std::string& p, const Bytes& d) { MemSource s(d); return v.importStream(p, s, nullptr); }
static std::optional<Bytes> get(Vault& v, const std::string& p) {
    Bytes out;
    int64_t off = 0;
    for (;;) {
        auto c = v.readFileChunk(p, off, 100000);
        if (!c) return std::nullopt;
        if (c->empty()) break;
        out.insert(out.end(), c->begin(), c->end());
        off += (int64_t)c->size();
    }
    return out;
}
static std::vector<std::string> names(Vault& v, const std::string& dir) {
    std::vector<DirEntry> es;
    std::vector<std::string> out;
    if (v.listDirectory(dir, es)) for (auto& e : es) out.push_back((e.isDir ? "D:" : "F:") + e.name);
    std::sort(out.begin(), out.end());
    return out;
}
static bool has(Vault& v, const std::string& dir, const std::string& entry) {
    const auto n = names(v, dir);
    return std::find(n.begin(), n.end(), entry) != n.end();
}
static std::vector<std::string> childNames(Storage& st, const std::string& dir) {
    std::vector<DirEntry> es;
    std::vector<std::string> out;
    if (st.list(dir, es)) for (auto& e : es) out.push_back((e.isDir ? "D:" : "F:") + e.name);
    std::sort(out.begin(), out.end());
    return out;
}
static Bytes slurp(const fs::path& p) {
    std::ifstream f(p, std::ios::binary);
    return Bytes((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}
static void spit(const fs::path& p, const Bytes& d) {
    std::ofstream f(p, std::ios::binary | std::ios::trunc);
    f.write((const char*)d.data(), (std::streamsize)d.size());
}

// ----------------------------------------------------------------- storage --

static void testStorage(const fs::path& base) {
    std::puts("storage");
    const fs::path dir = base / "store";
    fs::create_directories(dir);
    PosixStorage st(utf8(dir));
    const int64_t nowMs = std::chrono::duration_cast<std::chrono::milliseconds>(
                              std::chrono::system_clock::now().time_since_epoch()).count();

    // An empty folder lists as empty, and looks like no vault at all.
    { std::vector<DirEntry> es(3); CHECK(st.list("", es)); CHECK(es.empty()); }
    CHECK(!looksLikeGocryptfs(st));
    CHECK(!looksLikeCryptomator(st));
    CHECK(!looksLikeCryfs(st));
    { std::vector<DirEntry> es; CHECK(!st.list("nope", es)); }
    { DirEntry de; CHECK(st.stat("", de)); CHECK(de.isDir); CHECK(!st.stat("nope", de)); }
    CHECK(st.existsNoFollow(""));
    CHECK(!st.existsNoFollow("nope"));

    // Directories and whole-file I/O.
    CHECK(st.mkdir("a"));
    CHECK(st.mkdir("a/b"));
    CHECK(st.mkdir("a"));            // already there: still true
    CHECK(!st.mkdir("x/y"));         // parent missing
    const Bytes data = rnd(300000, 7);
    CHECK(st.writeWhole("a/f.bin", data.data(), data.size()));
    { Bytes back; CHECK(st.readWhole("a/f.bin", back)); CHECK(back == data); }
    { Bytes back; CHECK(!st.readWhole("a/missing.bin", back)); }
    {
        DirEntry de;
        CHECK(st.stat("a/f.bin", de));
        CHECK_EQ(de.name, "f.bin");
        CHECK(!de.isDir);
        CHECK(!de.isSymlink);
        CHECK_EQ(de.size, (int64_t)data.size());
        CHECK(std::llabs(de.mtimeMs - nowMs) < 10 * 60 * 1000);
        CHECK(st.stat("a", de));
        CHECK(de.isDir);
        CHECK_EQ(de.size, (int64_t)0);
    }
    CHECK((childNames(st, "a") == std::vector<std::string>{"D:b", "F:f.bin"}));

    // Positional reads and in-place writes through FdFile.
    {
        FdFile f = st.openRead("a/f.bin", "");
        CHECK(f.valid());
        CHECK_EQ(f.size(), (int64_t)data.size());
        uint8_t buf[100];
        CHECK_EQ(f.readAt(buf, 100, 1000), (int64_t)100);
        CHECK(std::memcmp(buf, data.data() + 1000, 100) == 0);
        CHECK_EQ(f.readAt(buf, 100, (int64_t)data.size() - 50), (int64_t)50);
        CHECK(std::memcmp(buf, data.data() + data.size() - 50, 50) == 0);
        CHECK_EQ(f.readAt(buf, 100, (int64_t)data.size()), (int64_t)0);
        CHECK_EQ(f.readAt(buf, 100, 5), (int64_t)100);   // reading backwards is fine on a regular file
    }
    CHECK(!st.openRead("a/missing.bin", "").valid());
    {
        FdFile w = st.openWrite("a/f.bin", false);
        CHECK(w.valid());
        const uint8_t patch[16] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};
        CHECK(w.writeAll(patch, 16));
        CHECK(w.sync());
        w.close();
        Bytes back;
        CHECK(st.readWhole("a/f.bin", back));
        CHECK_EQ(back.size(), data.size());
        CHECK(std::memcmp(back.data(), patch, 16) == 0);
        CHECK(std::memcmp(back.data() + 16, data.data() + 16, data.size() - 16) == 0);
    }
    {
        FdFile w = st.openWrite("a/f.bin", true);   // truncate
        CHECK(w.valid());
        const uint8_t ten[10] = {9, 9, 9, 9, 9, 9, 9, 9, 9, 9};
        CHECK(w.writeAll(ten, 10));
        w.close();
        DirEntry de;
        CHECK(st.stat("a/f.bin", de));
        CHECK_EQ(de.size, (int64_t)10);
    }
    CHECK(!st.openWrite("a/missing.bin", false).valid());   // never creates

    // Atomic config writes replace the old content and leave no temp file behind.
    { const Bytes v1 = rnd(100, 1), v2 = rnd(5000, 2); Bytes back;
      CHECK(st.writeWholeAtomic("a/cfg.json", v1.data(), v1.size()));
      CHECK(st.writeWholeAtomic("a/cfg.json", v2.data(), v2.size()));
      CHECK(st.readWhole("a/cfg.json", back)); CHECK(back == v2);
      for (auto& n : childNames(st, "a")) CHECK(n.find(".fvtmp") == std::string::npos); }
    { const Bytes blk = rnd(4096, 3); Bytes back;
      CHECK(st.writeBlock("a/blk", blk.data(), blk.size())); CHECK(st.readWhole("a/blk", back)); CHECK(back == blk); }

    // createFile keeps existing content.
    CHECK(st.createFile("a/empty"));
    { DirEntry de; CHECK(st.stat("a/empty", de)); CHECK_EQ(de.size, (int64_t)0); }
    { const Bytes b = rnd(77, 4); CHECK(st.writeWhole("a/keep", b.data(), b.size()));
      CHECK(st.createFile("a/keep")); DirEntry de; CHECK(st.stat("a/keep", de)); CHECK_EQ(de.size, (int64_t)77); }

    // Renames: onto an existing file (replaced), a directory, across directories.
    { const Bytes s = rnd(1000, 5), d = rnd(2000, 6); Bytes back;
      CHECK(st.writeWhole("a/src.bin", s.data(), s.size())); CHECK(st.writeWhole("a/dst.bin", d.data(), d.size()));
      CHECK(st.rename("a/src.bin", "a/dst.bin"));
      CHECK(st.readWhole("a/dst.bin", back)); CHECK(back == s);
      DirEntry de; CHECK(!st.stat("a/src.bin", de)); }
    CHECK(st.mkdir("d1"));
    CHECK(st.writeWhole("d1/x", data.data(), 100));
    CHECK(st.rename("d1", "d2"));
    { DirEntry de; CHECK(st.stat("d2/x", de)); CHECK(!st.stat("d1", de)); }
    CHECK(st.rename("d2/x", "a/x"));
    CHECK(!st.rename("a/does-not-exist", "a/y"));

    // Timestamps.
    CHECK(st.setMtime("a/x", 1700000000));
    { DirEntry de; CHECK(st.stat("a/x", de)); CHECK_EQ(de.mtimeMs, (int64_t)1700000000000LL); }
    CHECK(st.setMtime("d2", 1600000000));
    { DirEntry de; CHECK(st.stat("d2", de)); CHECK_EQ(de.mtimeMs, (int64_t)1600000000000LL); }
    CHECK(!st.setMtime("nope", 1700000000));

    // Space.
    { int64_t total = 0, free = 0; CHECK(st.spaceInfo(total, free)); CHECK(total > 0); CHECK(free >= 0 && free <= total); }

    // Names that must never reach the OS, whatever platform: they could leave the vault root.
    { const Bytes b = rnd(8, 8);
      CHECK(!st.writeWhole("../evil", b.data(), b.size()));
      CHECK(!st.writeWhole("a/../evil", b.data(), b.size()));
      CHECK(!st.writeWhole("./evil", b.data(), b.size()));
      CHECK(!st.mkdir(".."));
      DirEntry de; CHECK(!st.stat("..", de));
      CHECK(!fs::exists(base / "evil")); CHECK(!fs::exists(dir / "evil")); }
#if defined(_WIN32)
    // ... and on Windows the characters that are separators / stream markers / wildcards there.
    { const Bytes b = rnd(8, 9);
      CHECK(!st.writeWhole("a\\b", b.data(), b.size()));
      CHECK(!st.writeWhole("a/x:stream", b.data(), b.size()));
      CHECK(!st.writeWhole("a/q*r", b.data(), b.size()));
      CHECK(!st.writeWhole("a/q?r", b.data(), b.size())); }
#endif

    // Names Windows would treat as devices are ordinary names here (\\?\ paths), and Unicode survives.
    for (const std::string name : {std::string("NUL"), std::string("CON.txt"), std::string("aux"),
                                   std::string("\xC3\xBCn\xC3\xAF_\xE6\x96\x87\xE4\xBB\xB6_\xF0\x9F\x98\x80.bin")}) {
        const Bytes b = rnd(1234, 10);
        Bytes back;
        CHECK(st.writeWhole("a/" + name, b.data(), b.size()));
        CHECK(st.readWhole("a/" + name, back)); CHECK(back == b);
        DirEntry de; CHECK(st.stat("a/" + name, de)); CHECK_EQ(de.name, name); CHECK_EQ(de.size, (int64_t)1234);
        auto kids = childNames(st, "a");
        CHECK(std::find(kids.begin(), kids.end(), "F:" + name) != kids.end());
        CHECK(st.rename("a/" + name, "a/renamed"));
        CHECK(st.remove("a/renamed"));
    }

    // Paths longer than Windows' MAX_PATH.
    {
        std::string rel;
        for (int i = 0; i < 8; ++i) {
            rel += (rel.empty() ? "" : "/") + std::string(60, (char)('a' + i));
            CHECK(st.mkdir(rel));
        }
        const Bytes b = rnd(5000, 11);
        Bytes back;
        CHECK(st.writeWhole(rel + "/deep.bin", b.data(), b.size()));
        CHECK(st.readWhole(rel + "/deep.bin", back)); CHECK(back == b);
        CHECK_EQ(childNames(st, rel).size(), (size_t)1);
        CHECK(st.remove(std::string(60, 'a')));   // the whole deep tree
        DirEntry de; CHECK(!st.stat(std::string(60, 'a'), de));
    }

    // Parallel use: every method is thread-safe.
    {
        std::atomic<int> bad{0};
        std::vector<std::thread> ts;
        for (int t = 0; t < 4; ++t) ts.emplace_back([&, t] {
            PosixStorage* s = &st;
            for (int i = 0; i < 40; ++i) {
                const std::string n = "a/t" + std::to_string(t) + "_" + std::to_string(i);
                const Bytes b = rnd(1 + (size_t)((t * 7919 + i * 104729) % 70000), (uint32_t)(t * 100 + i));
                Bytes back;
                if (!s->writeWhole(n, b.data(), b.size())) { ++bad; continue; }
                if (!s->readWhole(n, back) || back != b) ++bad;
                if (!s->rename(n, n + ".r")) ++bad;
                if (!s->remove(n + ".r")) ++bad;
            }
        });
        for (auto& th : ts) th.join();
        CHECK_EQ(bad.load(), 0);
    }

    // Removing a tree; the root itself is never removed.
    CHECK(st.remove("a"));
    { DirEntry de; CHECK(!st.stat("a", de)); }
    CHECK(!st.remove(""));
    CHECK(st.remove("never-existed"));   // nothing left == success
    CHECK(st.remove("d2"));
    CHECK(childNames(st, "").empty());
}

// ------------------------------------------------------------ host helpers --

static void testHostFiles(const fs::path& base) {
    std::puts("host file helpers (fv_os.h)");
    const fs::path d = base / fs::path(u8"host_\u00fcn\u00ef_\u6587\u4ef6");
#if defined(_WIN32)
    CHECK(osMkdirs(utf8(d / "x" / "y" / "z")));
    CHECK(osMkdirs(utf8(d / "x" / "y" / "z")));   // already there
#else
    fs::create_directories(d / "x" / "y" / "z");
#endif
    const std::string f = utf8(d / "x" / "y" / "z" / "file.bin");
    int fd = osOpen(f.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    CHECK(fd >= 0);
    const Bytes data = rnd(100000, 12);
    if (fd >= 0) {
        CHECK(osPwrite(fd, data.data() + 5000, 95000, 5000) == 95000);   // out of order on purpose
        CHECK(osPwrite(fd, data.data(), 5000, 0) == 5000);
        CHECK(osFsync(fd) == 0);
        FdFile closer(fd);   // closes it
    }
    CHECK(slurp(f) == data);
    fd = osOpen(f.c_str(), O_RDONLY | O_CLOEXEC, 0);
    CHECK(fd >= 0);
    if (fd >= 0) {
        uint8_t buf[64];
        CHECK(osPread(fd, buf, 64, 777) == 64);
        CHECK(std::memcmp(buf, data.data() + 777, 64) == 0);
        CHECK(osPread(fd, buf, 64, (int64_t)data.size()) == 0);
        FdFile closer(fd);
    }
    // binary-safe: bytes the Windows text mode would mangle (CR LF, 0x1A)
    const Bytes tricky = {'a', '\r', '\n', 'b', 0x1A, 'c', '\n', 0, 1, 2};
    { std::FILE* fp = osFopen((f + ".t").c_str(), "wb"); CHECK(fp != nullptr);
      if (fp) { std::fwrite(tricky.data(), 1, tricky.size(), fp); std::fclose(fp); } }
    CHECK(slurp(f + ".t") == tricky);
    { std::FILE* fp = osFopen((f + ".t").c_str(), "rb"); CHECK(fp != nullptr);
      Bytes back(tricky.size()); if (fp) { CHECK(std::fread(back.data(), 1, back.size(), fp) == back.size()); std::fclose(fp); }
      CHECK(back == tricky); }
    CHECK(osRename((f + ".t").c_str(), (f + ".u").c_str()) == 0);
    CHECK(osRename(f.c_str(), (f + ".u").c_str()) == 0);   // replaces an existing destination
    CHECK(slurp(f + ".u") == data);
    CHECK(osUnlink((f + ".u").c_str()) == 0);
    CHECK(!fs::exists(fs::path(f + ".u")));
#if defined(_WIN32)
    // delete-on-close scratch file: usable as read/write, gone after close
    int sfd = osMakeScratch(utf8(d));
    CHECK(sfd >= 0);
    if (sfd >= 0) {
        CHECK(osPwrite(sfd, data.data(), 1000, 0) == 1000);
        uint8_t buf[10];
        CHECK(osPread(sfd, buf, 10, 500) == 10);
        CHECK(std::memcmp(buf, data.data() + 500, 10) == 0);
        FdFile closer(sfd);
    }
    size_t leftovers = 0;
    for (auto& e : fs::directory_iterator(d)) if (e.path().filename().string().rfind("cryfs_write_", 0) == 0) ++leftovers;
    CHECK_EQ(leftovers, (size_t)0);
#endif
}

// ------------------------------------------------------------ vault flows --

enum class Kind { Gocryptfs, Cryptomator, Cryfs };

static OpenResult openKind(Kind k, std::shared_ptr<Storage> st, const uint8_t* pw, size_t n, const HostEnv& env) {
    switch (k) {
        case Kind::Gocryptfs: return openGocryptfs(st, pw, n, false, env);
        case Kind::Cryptomator: return openCryptomator(st, pw, n, false, env);
        default: return openCryfs(st, pw, n, false, env);
    }
}

static void testVault(Kind kind, const char* label, const fs::path& base) {
    std::printf("vault: %s\n", label);
    const fs::path dir = base / fs::path(std::string("v_") + label);
    fs::create_directories(dir);
    auto st = std::make_shared<PosixStorage>(utf8(dir));
    HostEnv env;
    env.tempDir = utf8(base / "scratch");
    fs::create_directories(base / "scratch");
    // CryFS keeps its integrity state outside the vault: a nested, not-yet-existing, non-ASCII path with mixed separators.
    env.cryfsLocalStateDir = utf8(base / fs::path(u8"cryfs_state_\u00fcn")) + "/nested/dir";
    const uint8_t pw[] = "correct horse";
    const size_t pwn = sizeof pw - 1;

    // 1. "Does this folder contain a vault?" -- not yet; and listing an empty folder works.
    CHECK(!looksLikeGocryptfs(*st)); CHECK(!looksLikeCryptomator(*st)); CHECK(!looksLikeCryfs(*st));
    CHECK(childNames(*st, "").empty());

    // 2. Create in the empty folder.
    PlainResult cr;
    switch (kind) {
        case Kind::Gocryptfs: { GocryptfsCreateOptions o; o.scryptLogN = 10; cr = createGocryptfs(*st, pw, pwn, o); break; }
        case Kind::Cryptomator: cr = createCryptomator(*st, pw, pwn); break;
        default: { CryfsCreateOptions o; o.scryptLogN = 12; o.scryptR = 8; o.scryptP = 1; cr = createCryfs(*st, pw, pwn, o, env); break; }
    }
    CHECK(cr.status == OpenStatus::Ok);
    if (cr.status != OpenStatus::Ok) { std::printf("    create failed: %s\n", cr.message.c_str()); return; }
    CHECK(!childNames(*st, "").empty());

    // 3. The config files are found again; only this format claims the folder.
    CHECK_EQ(looksLikeGocryptfs(*st), kind == Kind::Gocryptfs);
    CHECK_EQ(looksLikeCryptomator(*st), kind == Kind::Cryptomator);
    CHECK_EQ(looksLikeCryfs(*st), kind == Kind::Cryfs);
    if (kind == Kind::Cryptomator) CHECK_EQ(probeCryptomatorFormat(*st), 8);

    // 4. A second create is refused (the folder is no longer empty); a wrong password is rejected.
    {
        PlainResult again;
        switch (kind) {
            case Kind::Gocryptfs: { GocryptfsCreateOptions o; o.scryptLogN = 10; again = createGocryptfs(*st, pw, pwn, o); break; }
            case Kind::Cryptomator: again = createCryptomator(*st, pw, pwn); break;
            default: { CryfsCreateOptions o; o.scryptLogN = 12; o.scryptR = 8; o.scryptP = 1; again = createCryfs(*st, pw, pwn, o, env); break; }
        }
        CHECK(again.status == OpenStatus::InvalidVault);
    }
    CHECK(openKind(kind, st, (const uint8_t*)"wrong", 5, env).status == OpenStatus::WrongPassword);

    // 5. Unlock and work.
    const Bytes small = rnd(1234, 21), big = rnd(1500000, 22), host = rnd(700000, 23), inc1 = rnd(70001, 24), inc2 = rnd(33333, 25);
    const fs::path hostDir = base / fs::path(u8"host_in_\u00fc\u6587");
    fs::create_directories(hostDir);
    spit(hostDir / "in.bin", host);
    {
        OpenResult r = openKind(kind, st, pw, pwn, env);
        CHECK(r.status == OpenStatus::Ok && r.vault);
        if (!r.vault) { std::printf("    open failed: %s\n", r.message.c_str()); return; }
        Vault& v = *r.vault;
        CHECK(!v.readOnly());
        CHECK(names(v, "").empty());
        CHECK(v.createDirectory("docs"));
        CHECK(v.createDirectory("dossiers_\xC3\xA9\xE6\x96\x87"));
        CHECK(put(v, "docs/small.bin", small));
        CHECK(put(v, "docs/big.bin", big));
        CHECK(put(v, "dossiers_\xC3\xA9\xE6\x96\x87/na\xC3\xAFve \xF0\x9F\x98\x80.txt", small));
        CHECK_EQ(v.getFileSize("docs/small.bin"), (int64_t)small.size());
        { auto g = get(v, "docs/small.bin"); CHECK(g && *g == small); }
        { auto g = get(v, "docs/big.bin"); CHECK(g && *g == big); }
        // host file in, host file out (these open the host file by its UTF-8 path)
        CHECK(v.writeBackFile("docs/host.bin", utf8(hostDir / "in.bin"), nullptr));
        CHECK(v.extractFile("docs/host.bin", utf8(hostDir / fs::path(u8"out_\u00fc.bin")), nullptr));
        CHECK(slurp(hostDir / fs::path(u8"out_\u00fc.bin")) == host);
        // incremental writes
        CHECK(v.writeFileChunk("docs/inc.bin", 0, inc1.data(), inc1.size()));
        CHECK(v.writeFileChunk("docs/inc.bin", (int64_t)inc1.size(), inc2.data(), inc2.size()));
        CHECK(v.finishWrite("docs/inc.bin"));
        { Bytes want = inc1; want.insert(want.end(), inc2.begin(), inc2.end()); auto g = get(v, "docs/inc.bin"); CHECK(g && *g == want); }
        // namespace operations
        CHECK(v.renameFile("docs/small.bin", "docs/renamed.bin"));
        CHECK(has(v, "docs", "F:renamed.bin")); CHECK(!has(v, "docs", "F:small.bin"));
        CHECK(v.setLastModifiedTime("docs/renamed.bin", 1700000000));
        CHECK(v.getFolderSize("docs") > 0);
        CHECK(v.deleteFile("docs/big.bin"));
        CHECK(!get(v, "docs/big.bin").has_value());
        int64_t total = 0, free = 0;
        CHECK(v.spaceInfo(total, free));
        v.close();
    }

    // 6. Lock, unlock again: everything is still there, byte for byte.
    {
        OpenResult r = openKind(kind, st, pw, pwn, env);
        CHECK(r.status == OpenStatus::Ok && r.vault);
        if (!r.vault) return;
        Vault& v = *r.vault;
        CHECK((names(v, "") == std::vector<std::string>{"D:docs", std::string("D:dossiers_\xC3\xA9\xE6\x96\x87")}));
        { auto g = get(v, "docs/renamed.bin"); CHECK(g && *g == small); }
        { auto g = get(v, "docs/host.bin"); CHECK(g && *g == host); }
        { Bytes want = inc1; want.insert(want.end(), inc2.begin(), inc2.end()); auto g = get(v, "docs/inc.bin"); CHECK(g && *g == want); }
        { auto g = get(v, "dossiers_\xC3\xA9\xE6\x96\x87/na\xC3\xAFve \xF0\x9F\x98\x80.txt"); CHECK(g && *g == small); }
        { std::vector<DirEntry> es; CHECK(v.listDirectory("docs", es));
          for (auto& e : es) if (e.name == "renamed.bin") CHECK_EQ(e.mtimeMs, (int64_t)1700000000000LL); }
        v.close();
    }
    if (kind == Kind::Cryfs) {   // the integrity state really went to the nested Unicode folder
        CHECK(fs::exists(base / fs::path(u8"cryfs_state_\u00fcn") / "nested" / "dir"));
    }
    std::error_code ec;
    fs::remove_all(dir, ec);
}

int main() {
    const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    fs::path name(u8"fvwin_\u00dcn\u00efc\u00f6d\u00e9_\u6587\u4ef6_");
    name += std::to_string(stamp);
    const fs::path base = fs::temp_directory_path() / name;
    fs::create_directories(base);
    std::printf("temp root: %s\n", utf8(base).c_str());

    testStorage(base);
    testHostFiles(base);
    testVault(Kind::Gocryptfs, "gocryptfs", base);
    testVault(Kind::Cryptomator, "cryptomator", base);
    testVault(Kind::Cryfs, "cryfs", base);

    std::error_code ec;
    fs::remove_all(base, ec);
    std::printf("\n%d checks, %d failed\n", g_checks, g_failed);
    return g_failed ? 1 : 0;
}
