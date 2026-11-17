// Test for the mount filesystem layer (ffi/ve_mount_fs.cpp) -- everything an OS mount does, minus the
// kernel: it calls MountFs the way the FUSE glue does and checks the result both through MountFs and
// through the plain ve_* ABI (a mounted vault and the in-app browser must agree).
//
// Runs the same suite on FAT, exFAT, NTFS and ext4 containers and on gocryptfs / Cryptomator / CryFS vaults.
//
// Usage: ve_mount_test [fat] [exfat] [ntfs] [ext4] [gocryptfs] [cryptomator] [cryfs]   (default: all)
//        ve_mount_test --os-mount <fs>    additionally mounts through FUSE and drives it with POSIX calls

#include "ve_engine.h"
#include "ve_mount_fs.h"
#include "ve_mount_internal.h"

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <thread>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

// ── the library keeps ve_internal_vol_traits hidden, so the test supplies its own ─────────────────────
static bool g_fv = false, g_ci = false;
bool ve_internal_vol_traits(int32_t, bool* fv, bool* ci, bool* ro) {
    if (fv) *fv = g_fv;
    if (ci) *ci = g_ci;
    if (ro) *ro = false;
    return true;
}

static int g_failures = 0, g_checks = 0;

#define CHECK(cond)                                                                 \
    do {                                                                            \
        ++g_checks;                                                                 \
        if (!(cond)) {                                                              \
            ++g_failures;                                                           \
            std::fprintf(stderr, "  FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);   \
        }                                                                           \
    } while (0)

#define CHECK_EQ(expr, expected)                                                                   \
    do {                                                                                           \
        ++g_checks;                                                                                \
        const long long got_ = (long long)(expr);                                                  \
        const long long want_ = (long long)(expected);                                             \
        if (got_ != want_) {                                                                       \
            ++g_failures;                                                                          \
            std::fprintf(stderr, "  FAIL %s:%d: %s -> %lld (expected %lld)\n", __FILE__, __LINE__, \
                         #expr, got_, want_);                                                      \
        }                                                                                          \
    } while (0)

using namespace vemount;

static std::string tmp(const std::string& name) {
    const char* t = std::getenv("TMPDIR");
    return std::string(t && *t ? t : "/tmp") + "/" + name;
}

static void sh(const std::string& cmd) {
    if (std::system(cmd.c_str()) != 0) { /* best effort */ }
}

static uint8_t pat(uint64_t i) { return static_cast<uint8_t>((i * 131 + (i >> 8) * 7 + 13) & 0xFF); }

static std::string patBytes(uint64_t from, size_t n) {
    std::string s(n, '\0');
    for (size_t i = 0; i < n; ++i) s[i] = static_cast<char>(pat(from + i));
    return s;
}

// ── tiny client helpers (what a program using the mount would do) ────────────────────────────────────

static int putFile(MountFs& fs, const std::string& path, const std::string& data, size_t piece = 0) {
    uint64_t fh = 0;
    int rc = fs.create(path, kOpenWrite | kOpenTrunc, fh);
    if (rc != 0) return rc;
    const size_t step = piece ? piece : (data.empty() ? 1 : data.size());
    for (size_t off = 0; off < data.size(); off += step) {
        const size_t n = std::min(step, data.size() - off);
        const int w = fs.write(fh, reinterpret_cast<const uint8_t*>(data.data()) + off, n, off);
        if (w != static_cast<int>(n)) { fs.release(fh); return w < 0 ? w : -EIO; }
    }
    rc = fs.flush(fh);
    const int rrc = fs.release(fh);
    return rc != 0 ? rc : rrc;
}

static std::string slurp(MountFs& fs, const std::string& path, int* errOut = nullptr) {
    uint64_t fh = 0;
    int rc = fs.open(path, kOpenRead, fh);
    if (errOut) *errOut = rc;
    if (rc != 0) return "";
    std::string out;
    std::vector<uint8_t> buf(100 * 1000 + 3);
    for (uint64_t off = 0;;) {
        const int n = fs.read(fh, buf.data(), buf.size(), off);
        if (n < 0) { if (errOut) *errOut = n; break; }
        if (n == 0) break;
        out.append(reinterpret_cast<const char*>(buf.data()), static_cast<size_t>(n));
        off += static_cast<uint64_t>(n);
    }
    fs.release(fh);
    return out;
}

static std::vector<std::string> names(MountFs& fs, const std::string& dir) {
    std::vector<DirItem> items;
    std::vector<std::string> out;
    if (fs.readdir(dir, items) == 0) {
        for (auto& i : items) out.push_back(i.name);
    }
    return out;
}

static bool has(const std::vector<std::string>& v, const std::string& n) {
    for (auto& s : v) if (s == n) return true;
    return false;
}

// Same file seen through the plain ABI.
static std::string abiRead(int vol, const char* path) {
    const int64_t size = ve_get_file_size(vol, path);
    if (size <= 0) return "";
    std::string out;
    int64_t off = 0;
    while (off < size) {
        ve_buffer b{};
        const int32_t len = static_cast<int32_t>(std::min<int64_t>(1 << 20, size - off));
        if (ve_read_file_chunk(vol, path, off, len, &b) != VE_OK || b.len == 0) { ve_buffer_free(&b); break; }
        out.append(reinterpret_cast<const char*>(b.data), b.len);
        off += static_cast<int64_t>(b.len);
        ve_buffer_free(&b);
    }
    return out;
}

// ── the suite ────────────────────────────────────────────────────────────────────────────────────────

static void suite(const char* label, int vol, bool fv, bool ci) {
    std::printf("== mount layer on %s ==\n", label);
    g_fv = fv;
    g_ci = ci;
    FsOptions opt;
    MountFs fs(vol, opt);
    Attr a;

    // -- root / empty ------------------------------------------------------------------------------
    CHECK_EQ(fs.getattr("/", a), 0);
    CHECK(a.type == NodeType::Dir);
    CHECK_EQ(fs.getattr("/nope", a), -ENOENT);

    // -- directories ---------------------------------------------------------------------------------
    CHECK_EQ(fs.mkdir("/d"), 0);
    CHECK_EQ(fs.mkdir("/d"), -EEXIST);
    CHECK_EQ(fs.getattr("/d", a), 0);
    CHECK(a.type == NodeType::Dir);
    CHECK(has(names(fs, "/"), "d"));
    CHECK_EQ(fs.mkdir("/missing/child"), -ENOENT);

    // -- create + sequential coalesced write + read back ---------------------------------------------
    {
        uint64_t fh = 0;
        CHECK_EQ(fs.create("/d/a.txt", kOpenWrite | kOpenExcl, fh), 0);
        CHECK(fh != 0);
        CHECK_EQ(fs.write(fh, reinterpret_cast<const uint8_t*>("hello"), 5, 0), 5);
        // visible with its in-flight size before any flush, and in the listing
        CHECK_EQ(fs.getattr("/d/a.txt", a), 0);
        CHECK_EQ(a.size, 5);
        CHECK(has(names(fs, "/d"), "a.txt"));
        CHECK_EQ(fs.write(fh, reinterpret_cast<const uint8_t*>(" world"), 6, 5), 6);
        CHECK_EQ(fs.flush(fh), 0);
        CHECK_EQ(fs.release(fh), 0);
        CHECK_EQ(fs.create("/d/a.txt", kOpenWrite | kOpenExcl, fh), -EEXIST);
    }
    CHECK_EQ(fs.getattr("/d/a.txt", a), 0);
    CHECK_EQ(a.size, 11);
    CHECK(slurp(fs, "/d/a.txt") == "hello world");
    CHECK(abiRead(vol, "/d/a.txt") == "hello world");  // the ABI sees the same bytes
    {
        uint64_t fh = 0;
        CHECK_EQ(fs.open("/d/a.txt", kOpenRead, fh), 0);
        uint8_t b[16];
        CHECK_EQ(fs.read(fh, b, sizeof(b), 6), 5);
        CHECK(std::memcmp(b, "world", 5) == 0);
        CHECK_EQ(fs.read(fh, b, sizeof(b), 11), 0);  // EOF
        CHECK_EQ(fs.read(fh, b, sizeof(b), 5000), 0);
        fs.release(fh);
    }
    {
        uint64_t dh = 0;
        CHECK_EQ(fs.open("/d", kOpenRead, dh), -EISDIR);
    }

    // -- in-place overwrite (no truncate): Direct on containers, Buffered on vaults ------------------
    {
        uint64_t fh = 0;
        CHECK_EQ(fs.open("/d/a.txt", kOpenRead | kOpenWrite, fh), 0);
        CHECK_EQ(fs.write(fh, reinterpret_cast<const uint8_t*>("J"), 1, 0), 1);
        CHECK_EQ(fs.write(fh, reinterpret_cast<const uint8_t*>("W"), 1, 6), 1);
        uint8_t b[16];
        CHECK_EQ(fs.read(fh, b, sizeof(b), 0), 11);  // read-your-writes on the same handle
        CHECK(std::memcmp(b, "Jello World", 11) == 0);
        CHECK_EQ(fs.release(fh), 0);
    }
    CHECK(slurp(fs, "/d/a.txt") == "Jello World");
    CHECK(abiRead(vol, "/d/a.txt") == "Jello World");

    // -- truncate (path based) shrink and grow ------------------------------------------------------
    CHECK_EQ(fs.truncate("/d/a.txt", 4), 0);
    CHECK(slurp(fs, "/d/a.txt") == "Jell");
    CHECK_EQ(fs.truncate("/d/a.txt", 8), 0);
    {
        const std::string s = slurp(fs, "/d/a.txt");
        CHECK_EQ(s.size(), 8);
        CHECK(s.substr(0, 4) == "Jell");
        CHECK(s.substr(4) == std::string(4, '\0'));  // grown space is zeros, never stale data
    }
    CHECK_EQ(fs.truncate("/d/a.txt", 0), 0);
    CHECK_EQ(fs.getattr("/d/a.txt", a), 0);
    CHECK_EQ(a.size, 0);

    // -- O_TRUNC rewrite -----------------------------------------------------------------------------
    CHECK_EQ(putFile(fs, "/d/a.txt", "first version, fairly long"), 0);
    CHECK_EQ(putFile(fs, "/d/a.txt", "xyz"), 0);
    CHECK(slurp(fs, "/d/a.txt") == "xyz");

    // -- big sequential write in FUSE-sized pieces, then a differently sized read ---------------------
    {
        const std::string big = patBytes(0, 3 * 1024 * 1024 + 4567);
        CHECK_EQ(putFile(fs, "/big.bin", big, 128 * 1024), 0);
        CHECK_EQ(fs.getattr("/big.bin", a), 0);
        CHECK_EQ(a.size, big.size());
        CHECK(slurp(fs, "/big.bin") == big);
        CHECK(abiRead(vol, "/big.bin") == big);
    }

    // -- sparse write: a hole reads back as zeros -----------------------------------------------------
    {
        uint64_t fh = 0;
        CHECK_EQ(fs.create("/sparse.bin", kOpenWrite, fh), 0);
        CHECK_EQ(fs.write(fh, reinterpret_cast<const uint8_t*>("Z"), 1, 100000), 1);
        CHECK_EQ(fs.release(fh), 0);
        const std::string s = slurp(fs, "/sparse.bin");
        CHECK_EQ(s.size(), 100001);
        CHECK(s.size() == 100001 && s[100000] == 'Z');
        bool zeros = s.size() == 100001;
        for (size_t i = 0; zeros && i < 100000; ++i) zeros = s[i] == 0;
        CHECK(zeros);
    }

    // -- patching inside the not-yet-sent window of a new file ----------------------------------------
    {
        uint64_t fh = 0;
        CHECK_EQ(fs.create("/patch.bin", kOpenWrite | kOpenRead, fh), 0);
        const std::string base = patBytes(0, 100);
        CHECK_EQ(fs.write(fh, reinterpret_cast<const uint8_t*>(base.data()), base.size(), 0), 100);
        CHECK_EQ(fs.write(fh, reinterpret_cast<const uint8_t*>("PATCH"), 5, 10), 5);
        uint8_t b[100];
        CHECK_EQ(fs.read(fh, b, sizeof(b), 0), 100);  // read-your-writes before any commit
        CHECK(std::memcmp(b + 10, "PATCH", 5) == 0);
        CHECK_EQ(fs.release(fh), 0);
        std::string want = base;
        want.replace(10, 5, "PATCH");
        CHECK(slurp(fs, "/patch.bin") == want);
    }

    // -- a write after the file was already committed (dup'd fd, second flush) ------------------------
    {
        uint64_t fh = 0;
        CHECK_EQ(fs.create("/again.txt", kOpenWrite, fh), 0);
        CHECK_EQ(fs.write(fh, reinterpret_cast<const uint8_t*>("one"), 3, 0), 3);
        CHECK_EQ(fs.flush(fh), 0);
        CHECK(slurp(fs, "/again.txt") == "one");
        CHECK_EQ(fs.write(fh, reinterpret_cast<const uint8_t*>("two"), 3, 3), 3);
        CHECK_EQ(fs.release(fh), 0);
        CHECK(slurp(fs, "/again.txt") == "onetwo");
    }

    // -- rename: plain, replacing, across directories, directory with content -------------------------
    CHECK_EQ(putFile(fs, "/d/r1.txt", "r1"), 0);
    CHECK_EQ(fs.rename("/d/r1.txt", "/d/r2.txt", 0), 0);
    CHECK_EQ(fs.getattr("/d/r1.txt", a), -ENOENT);
    CHECK(slurp(fs, "/d/r2.txt") == "r1");
    CHECK_EQ(putFile(fs, "/d/r3.txt", "r3"), 0);
    CHECK_EQ(fs.rename("/d/r2.txt", "/d/r3.txt", 1), -EEXIST);  // NOREPLACE
    CHECK_EQ(fs.rename("/d/r2.txt", "/d/r3.txt", 0), 0);        // POSIX replace
    CHECK(slurp(fs, "/d/r3.txt") == "r1");
    CHECK_EQ(fs.mkdir("/e"), 0);
    CHECK_EQ(fs.rename("/d/r3.txt", "/e/moved.txt", 0), 0);
    CHECK(slurp(fs, "/e/moved.txt") == "r1");
    CHECK_EQ(fs.rename("/e", "/e2", 0), 0);
    CHECK(slurp(fs, "/e2/moved.txt") == "r1");
    CHECK_EQ(fs.getattr("/e", a), -ENOENT);
    CHECK_EQ(fs.rename("/e2", "/e2/inside", 0), -EINVAL);

    // editor-style save: write a temp file, then rename it over the original
    CHECK_EQ(putFile(fs, "/doc.txt", "old"), 0);
    CHECK_EQ(putFile(fs, "/.doc.txt.tmp", "new contents"), 0);
    CHECK_EQ(fs.rename("/.doc.txt.tmp", "/doc.txt", 0), 0);
    CHECK(slurp(fs, "/doc.txt") == "new contents");

    // -- unlink, including a file that is still open and being written ---------------------------------
    CHECK_EQ(fs.unlink("/doc.txt"), 0);
    CHECK_EQ(fs.getattr("/doc.txt", a), -ENOENT);
    CHECK_EQ(fs.unlink("/doc.txt"), -ENOENT);
    CHECK_EQ(fs.unlink("/d"), -EISDIR);
    {
        uint64_t fh = 0;
        CHECK_EQ(fs.create("/ghost.tmp", kOpenWrite, fh), 0);
        CHECK_EQ(fs.write(fh, reinterpret_cast<const uint8_t*>("data"), 4, 0), 4);
        CHECK_EQ(fs.unlink("/ghost.tmp"), 0);
        CHECK_EQ(fs.write(fh, reinterpret_cast<const uint8_t*>("more"), 4, 4), 4);  // writer carries on
        CHECK_EQ(fs.release(fh), 0);
        CHECK_EQ(fs.getattr("/ghost.tmp", a), -ENOENT);  // and the file does NOT come back
        CHECK(!has(names(fs, "/"), "ghost.tmp"));
    }

    // -- rmdir ---------------------------------------------------------------------------------------
    CHECK_EQ(fs.rmdir("/e2"), -ENOTEMPTY);
    CHECK_EQ(fs.unlink("/e2/moved.txt"), 0);
    CHECK_EQ(fs.rmdir("/e2"), 0);
    CHECK_EQ(fs.getattr("/e2", a), -ENOENT);
    CHECK_EQ(fs.rmdir("/d/a.txt"), -ENOTDIR);

    // -- timestamps ----------------------------------------------------------------------------------
    CHECK_EQ(putFile(fs, "/t.txt", "t"), 0);
    CHECK_EQ(fs.setMtime("/t.txt", 1600000000), 0);
    CHECK_EQ(fs.getattr("/t.txt", a), 0);
    CHECK(a.mtime >= 1599999998 && a.mtime <= 1600000002);  // FAT stores 2 s resolution

    // -- names ---------------------------------------------------------------------------------------
    {
        const std::string uni = "/h\xC3\xA9llo w\xC3\xB6rld.txt";  // héllo wörld.txt
        CHECK_EQ(putFile(fs, uni, "unicode"), 0);
        CHECK(slurp(fs, uni) == "unicode");
        CHECK(has(names(fs, "/"), uni.substr(1)));
    }

    // -- case sensitivity matches the filesystem ---------------------------------------------------------
    CHECK_EQ(putFile(fs, "/Case.txt", "c"), 0);
    if (ci) {
        CHECK_EQ(fs.getattr("/CASE.TXT", a), 0);
    } else {
        CHECK_EQ(fs.getattr("/CASE.TXT", a), -ENOENT);
    }

    // -- symlinks (only where the format supports them) ----------------------------------------------
    {
        const int rc = fs.symlink("t.txt", "/link");
        if (rc == 0) {
            std::string target;
            CHECK_EQ(fs.readlink("/link", target), 0);
            CHECK(target == "t.txt");
            CHECK_EQ(fs.getattr("/link", a), 0);
            CHECK(a.type == NodeType::Symlink);
            CHECK_EQ(fs.unlink("/link"), 0);
        } else {
            std::printf("  (symlinks not supported here: %d)\n", rc);
        }
    }

    // -- statfs --------------------------------------------------------------------------------------
    {
        StatFsInfo info;
        CHECK_EQ(fs.statfs(info), 0);
        CHECK(info.blocks > 0 && info.blocksFree <= info.blocks);
    }

    // -- closeAll commits writes that nobody flushed -------------------------------------------------
    {
        uint64_t fh = 0;
        CHECK_EQ(fs.create("/unflushed.txt", kOpenWrite, fh), 0);
        CHECK_EQ(fs.write(fh, reinterpret_cast<const uint8_t*>("kept"), 4, 0), 4);
        CHECK_EQ(fs.openHandleCount(), 1);
        fs.closeAll();
        CHECK_EQ(fs.openHandleCount(), 0);
        CHECK(abiRead(vol, "/unflushed.txt") == "kept");
    }

    // -- folder vaults only: a stream cannot be rewound, and it must fail loudly --------------------
    if (fv) {
        uint64_t fh = 0;
        CHECK_EQ(fs.create("/rewind.bin", kOpenWrite, fh), 0);
        const std::string chunk = patBytes(0, 1024 * 1024 + 10);
        CHECK_EQ(fs.write(fh, reinterpret_cast<const uint8_t*>(chunk.data()), chunk.size(), 0), (long long)chunk.size());
        CHECK_EQ(fs.write(fh, reinterpret_cast<const uint8_t*>("x"), 1, 0), -EIO);  // already handed to the vault
        fs.release(fh);
        fs.unlink("/rewind.bin");
    }

    // -- read-only handles cannot write ------------------------------------------------------------------
    {
        uint64_t fh = 0;
        CHECK_EQ(fs.open("/t.txt", kOpenRead, fh), 0);
        CHECK_EQ(fs.write(fh, reinterpret_cast<const uint8_t*>("x"), 1, 0), -EBADF);
        fs.release(fh);
    }
    std::printf("  %d checks so far, %d failed\n", g_checks, g_failures);
}

// ── fixtures ─────────────────────────────────────────────────────────────────────────────────────────

static void runContainer(const char* fsName) {
    const std::string path = tmp(std::string("ve_mount_") + fsName + ".hc");
    std::remove(path.c_str());
    const char* pw = "correct horse battery staple";
    const bool small = std::strcmp(fsName, "fat") == 0 || std::strcmp(fsName, "exfat") == 0;
    int fd = ve_create_file(path.c_str());
    CHECK(fd >= 0);
    ve_create_params cp;
    std::memset(&cp, 0, sizeof(cp));
    cp.struct_size = sizeof(cp);
    cp.fd = fd;
    cp.password = reinterpret_cast<const uint8_t*>(pw);
    cp.password_len = static_cast<int32_t>(std::strlen(pw));
    cp.size_bytes = small ? (24ll << 20) : (48ll << 20);
    cp.file_system = fsName;
    cp.cipher_id = 255;
    cp.hash_id = 255;
    cp.quick_format = 1;
    CHECK_EQ(ve_create_container(&cp), VE_OK);

    int ufd = ve_open_file(path.c_str(), 1);
    ve_unlock_params p;
    std::memset(&p, 0, sizeof(p));
    p.struct_size = sizeof(p);
    p.fd = ufd;
    p.password = reinterpret_cast<const uint8_t*>(pw);
    p.password_len = static_cast<int32_t>(std::strlen(pw));
    p.vol_id = 0;
    p.cipher_id = 255;
    p.hash_id = 255;
    CHECK_EQ(ve_unlock(&p), VE_OK);
    const bool ci = std::strcmp(fsName, "fat") == 0 || std::strcmp(fsName, "exfat") == 0 || std::strcmp(fsName, "ntfs") == 0;
    suite(fsName, 0, false, ci);
    ve_lock(0);
    std::remove(path.c_str());
}

static void runVault(int fmt, const char* name) {
    const char* pw = "correct horse battery staple";
    const std::string root = tmp(std::string("ve_mount_fv_") + name);
    const std::string state = tmp("ve_mount_fv_state");
    sh("rm -rf '" + root + "' '" + state + "'");
    sh("mkdir -p '" + root + "' '" + state + "'");
    ve_buffer msg{};
    CHECK_EQ(ve_fv_create(fmt, root.c_str(), (const uint8_t*)pw, (int32_t)std::strlen(pw), 0, 0, 0, 0, 0, nullptr,
                          nullptr, 0, state.c_str(), tmp("").c_str(), &msg),
             VE_OK);
    ve_buffer_free(&msg);
    CHECK_EQ(ve_fv_unlock(2, fmt, root.c_str(), (const uint8_t*)pw, (int32_t)std::strlen(pw), nullptr, 0, 0, 1,
                          state.c_str(), tmp("").c_str(), &msg, nullptr),
             VE_OK);
    ve_buffer_free(&msg);
    suite(name, 2, true, false);
    ve_lock(2);
    sh("rm -rf '" + root + "' '" + state + "'");
}


// ── real kernel mount ────────────────────────────────────────────────────────────────────────────────
//
// Safety: this process is both the FUSE server and (via child processes) the client. Every call that
// touches the mount therefore runs in a child with a hard timeout, so a bug in the mount layer can hang
// a child but never this process; and a watchdog aborts ONLY the kernel connection of the mount under
// test (found in /proc/self/mountinfo) if the whole test overruns.

static std::atomic<int64_t> g_endedMount{0};
static void onMountEvent(int64_t id, int32_t event) {
    if (event == 1) g_endedMount.store(id);
}

static std::atomic<long> g_conn{-1};   // kernel connection id (= minor number of the mount's device)
static std::atomic<bool> g_testDone{false};

static long connectionOf(const std::string& mp) {
    FILE* f = std::fopen("/proc/self/mountinfo", "r");
    if (!f) return -1;
    char line[4096];
    long found = -1;
    while (std::fgets(line, sizeof(line), f)) {
        int id, parent, major, minor;
        char root[1024], mount[1024];
        if (std::sscanf(line, "%d %d %d:%d %1023s %1023s", &id, &parent, &major, &minor, root, mount) == 6 &&
            mp == mount) {
            found = minor;
        }
    }
    std::fclose(f);
    return found;
}

static void abortConnection() {
    const long c = g_conn.load();
    if (c < 0) return;
    const std::string path = "/sys/fs/fuse/connections/" + std::to_string(c) + "/abort";
    if (FILE* f = std::fopen(path.c_str(), "w")) { std::fputs("1", f); std::fclose(f); }
}

static void startWatchdog(int seconds) {
    std::thread([seconds]() {
        for (int i = 0; i < seconds * 10 && !g_testDone.load(); ++i) std::this_thread::sleep_for(std::chrono::milliseconds(100));
        if (g_testDone.load()) return;
        std::fprintf(stderr, "WATCHDOG: test overran %d s -- aborting its FUSE connection\n", seconds);
        abortConnection();
        std::_Exit(3);
    }).detach();
}

// Runs `cmd` in a shell child with a hard timeout; returns its exit status (124/137 = timed out).
static int P(const std::string& cmd) {
    const std::string full = "timeout -s KILL 25 sh -c '" + cmd + "'";
    return std::system(full.c_str());
}
static std::string Pout(const std::string& cmd) {
    std::string out;
    FILE* p = popen(("timeout -s KILL 25 sh -c '" + cmd + "'").c_str(), "r");
    if (!p) return out;
    char b[512];
    while (size_t n = fread(b, 1, sizeof(b), p)) out.append(b, n);
    pclose(p);
    return out;
}
// File contents as a client process would see them.
static std::string cat(const std::string& path) {
    return Pout("cat " + path + " 2>/dev/null || printf \"<missing>\"");
}

static void osMountSuite(const char* label, int vol, bool fv) {
    std::printf("== OS mount (FUSE) on %s ==\n", label);
    char reason[256];
    if (!ve_mount_supported(reason, sizeof(reason))) {
        std::printf("  SKIPPED: %s\n", reason);
        return;
    }
    g_fv = fv;
    const std::string mp = tmp(std::string("ve_osmount_") + label);
    sh("rm -rf '" + mp + "'");
    ve_set_mount_callback(onMountEvent);
    ve_mount_options mo;
    std::memset(&mo, 0, sizeof(mo));
    mo.struct_size = sizeof(mo);
    mo.volume_name = label;
    int64_t id = 0;
    int32_t rc = ve_mount(vol, mp.c_str(), &mo, &id);
    if (rc != VE_OK) {
        char err[256] = {0};
        ve_mount_last_error(err, sizeof(err));
        std::printf("  SKIPPED: ve_mount -> %d (%s)\n", rc, err);
        return;
    }
    g_conn.store(connectionOf(mp));
    std::printf("  mounted at %s (connection %ld)\n", mp.c_str(), g_conn.load());
    CHECK(id > 0);

    CHECK_EQ(P("test -d " + mp), 0);
    ve_buffer lb{};
    CHECK_EQ(ve_list_mounts(&lb), VE_OK);
    CHECK(lb.len > 4);
    ve_buffer_free(&lb);

    // plain shell writes: create/truncate, append, read
    CHECK_EQ(P("printf \"hello mount\" > " + mp + "/hello.txt"), 0);
    CHECK(cat(mp + "/hello.txt") == "hello mount");
    CHECK_EQ(std::atoi(Pout("stat -c %s " + mp + "/hello.txt").c_str()), 11);
    CHECK(abiRead(vol, "/hello.txt") == "hello mount");  // the same bytes through the plain ABI

    // real tools on real data
    CHECK_EQ(P("mkdir " + mp + "/dir && cp /bin/ls " + mp + "/dir/ls.copy"), 0);
    CHECK_EQ(P("cmp /bin/ls " + mp + "/dir/ls.copy"), 0);
    CHECK_EQ(P("head -c 3000000 /dev/urandom > /tmp/ve_os_rand.bin && cp /tmp/ve_os_rand.bin " + mp + "/rand.bin"), 0);
    CHECK_EQ(P("cmp /tmp/ve_os_rand.bin " + mp + "/rand.bin"), 0);
    // in-place edit via temp file + rename (sed -i, most editors)
    CHECK_EQ(P("printf \"one\\ntwo\\nthree\\n\" > " + mp + "/edit.txt && sed -i s/two/TWO/ " + mp + "/edit.txt"), 0);
    CHECK(cat(mp + "/edit.txt") == "one\nTWO\nthree\n");
    // append, then overwrite-in-place without truncating
    CHECK_EQ(P("echo more >> " + mp + "/edit.txt"), 0);
    CHECK(cat(mp + "/edit.txt") == "one\nTWO\nthree\nmore\n");
    CHECK_EQ(P("printf ZZ | dd of=" + mp + "/edit.txt bs=1 seek=1 conv=notrunc 2>/dev/null"), 0);
    CHECK(cat(mp + "/edit.txt") == "oZZ\nTWO\nthree\nmore\n");
    // truncate, rename, list, remove
    CHECK_EQ(P("truncate -s 3 " + mp + "/edit.txt"), 0);
    CHECK(cat(mp + "/edit.txt") == "oZZ");
    CHECK_EQ(P("mv " + mp + "/edit.txt " + mp + "/dir/edited.txt"), 0);
    CHECK(cat(mp + "/dir/edited.txt") == "oZZ");
    const std::string ls = Pout("ls " + mp + " " + mp + "/dir");
    CHECK(ls.find("hello.txt") != std::string::npos && ls.find("ls.copy") != std::string::npos);
    CHECK_EQ(P("rm " + mp + "/dir/edited.txt " + mp + "/dir/ls.copy && rmdir " + mp + "/dir"), 0);
    CHECK(P("test -e " + mp + "/dir") != 0);
    // a tree copy compared byte for byte, like dragging a folder into the file manager
    CHECK_EQ(P("rm -rf /tmp/ve_os_tree && mkdir -p /tmp/ve_os_tree/a/b && echo x > /tmp/ve_os_tree/a/f1 && "
               "echo y > /tmp/ve_os_tree/a/b/f2 && cp -r /tmp/ve_os_tree " + mp + "/tree"), 0);
    CHECK_EQ(P("diff -r /tmp/ve_os_tree " + mp + "/tree"), 0);
    sh("rm -rf /tmp/ve_os_tree /tmp/ve_os_rand.bin");

    // a client that keeps a file open makes a polite unmount refuse; closing it lets it succeed
    sh("(sh -c 'exec 3< " + mp + "/hello.txt; sleep 8' &) ; sleep 0.5");
    CHECK_EQ(ve_unmount(id, 0), VE_ERR_BUSY);
    sh("pkill -f 'sleep 8' 2>/dev/null; sleep 1");
    {   // diagnostic: who still has something open under the mount?
        const std::string who = Pout("for p in /proc/[0-9]*; do if ls -l $p/fd $p/cwd 2>/dev/null | grep -q " + mp +
                                     "; then echo $p $(tr \\\\0 \\\\ \\< $p/cmdline | cut -c1-80); fi; done");
        if (!who.empty()) std::printf("  holders before unmount:\n%s", who.c_str());
    }
    CHECK_EQ(ve_unmount(id, 0), VE_OK);
    CHECK(P("test -e " + mp + "/hello.txt") != 0);        // really gone
    CHECK(abiRead(vol, "/hello.txt") == "hello mount");     // and nothing was lost

    // someone ejects the mount from outside: the app is told, and can reap it
    g_endedMount.store(0);
    CHECK_EQ(ve_mount(vol, mp.c_str(), &mo, &id), VE_OK);
    g_conn.store(connectionOf(mp));
    sh("fusermount3 -u " + mp);
    for (int i = 0; i < 60 && g_endedMount.load() == 0; ++i) std::this_thread::sleep_for(std::chrono::milliseconds(50));
    CHECK_EQ(g_endedMount.load(), id);
    CHECK_EQ(ve_unmount(id, 1), VE_OK);

    // locking while mounted, with a client still holding a file open: the mount goes away first
    CHECK_EQ(ve_mount(vol, mp.c_str(), &mo, &id), VE_OK);
    g_conn.store(connectionOf(mp));
    sh("(sh -c 'exec 3< " + mp + "/hello.txt; sleep 8' &) ; sleep 0.5");
    ve_lock(vol);
    CHECK(P("test -e " + mp + "/hello.txt") != 0);
    sh("pkill -f 'sleep 8' 2>/dev/null");
    ve_buffer lb2{};
    CHECK_EQ(ve_list_mounts(&lb2), VE_OK);
    CHECK(lb2.len == 4);  // no mounts left
    ve_buffer_free(&lb2);
    g_conn.store(-1);
    rmdir(mp.c_str());
    std::printf("  %d checks so far, %d failed\n", g_checks, g_failures);
}

static void osMountContainer(const char* fsName) {
    const std::string path = tmp(std::string("ve_os_") + fsName + ".hc");
    std::remove(path.c_str());
    const char* pw = "correct horse battery staple";
    ve_create_params cp;
    std::memset(&cp, 0, sizeof(cp));
    cp.struct_size = sizeof(cp);
    cp.fd = ve_create_file(path.c_str());
    cp.password = reinterpret_cast<const uint8_t*>(pw);
    cp.password_len = static_cast<int32_t>(std::strlen(pw));
    cp.size_bytes = 48ll << 20;
    cp.file_system = fsName;
    cp.cipher_id = 255;
    cp.hash_id = 255;
    cp.quick_format = 1;
    CHECK_EQ(ve_create_container(&cp), VE_OK);
    ve_unlock_params p;
    std::memset(&p, 0, sizeof(p));
    p.struct_size = sizeof(p);
    p.fd = ve_open_file(path.c_str(), 1);
    p.password = reinterpret_cast<const uint8_t*>(pw);
    p.password_len = static_cast<int32_t>(std::strlen(pw));
    p.vol_id = 0;
    p.cipher_id = 255;
    p.hash_id = 255;
    CHECK_EQ(ve_unlock(&p), VE_OK);
    osMountSuite(fsName, 0, false);
    ve_lock(0);
    std::remove(path.c_str());
}

static void osMountVault(int fmt, const char* name) {
    const char* pw = "correct horse battery staple";
    const std::string root = tmp(std::string("ve_os_fv_") + name);
    const std::string state = tmp("ve_os_fv_state");
    sh("rm -rf '" + root + "' '" + state + "'; mkdir -p '" + root + "' '" + state + "'");
    ve_buffer msg{};
    CHECK_EQ(ve_fv_create(fmt, root.c_str(), (const uint8_t*)pw, (int32_t)std::strlen(pw), 0, 0, 0, 0, 0, nullptr,
                          nullptr, 0, state.c_str(), tmp("").c_str(), &msg), VE_OK);
    ve_buffer_free(&msg);
    CHECK_EQ(ve_fv_unlock(2, fmt, root.c_str(), (const uint8_t*)pw, (int32_t)std::strlen(pw), nullptr, 0, 0, 1,
                          state.c_str(), tmp("").c_str(), &msg, nullptr), VE_OK);
    ve_buffer_free(&msg);
    osMountSuite(name, 2, true);
    ve_lock(2);
    sh("rm -rf '" + root + "' '" + state + "'");
}

int main(int argc, char** argv) {
    if (argc >= 2 && std::strcmp(argv[1], "--os-mount") == 0) {
        startWatchdog(150);
        std::vector<std::string> kinds;
        for (int i = 2; i < argc; ++i) kinds.push_back(argv[i]);
        if (kinds.empty()) kinds = {"fat", "ext4", "gocryptfs"};
        for (auto& k : kinds) {
            if (k == "gocryptfs") osMountVault(VE_FV_GOCRYPTFS, "gocryptfs");
            else if (k == "cryptomator") osMountVault(VE_FV_CRYPTOMATOR, "cryptomator");
            else if (k == "cryfs") osMountVault(VE_FV_CRYFS, "cryfs");
            else osMountContainer(k.c_str());
        }
        g_testDone.store(true);
        std::printf("\n%d checks, %d failed\n", g_checks, g_failures);
        return g_failures == 0 ? 0 : 1;
    }
    std::vector<std::string> want;
    for (int i = 1; i < argc; ++i) want.push_back(argv[i]);
    auto on = [&](const char* n) {
        if (want.empty()) return true;
        for (auto& w : want) if (w == n) return true;
        return false;
    };
    if (on("fat")) runContainer("fat");
    if (on("exfat")) runContainer("exfat");
    if (on("ntfs")) runContainer("ntfs");
    if (on("ext4")) runContainer("ext4");
    if (on("gocryptfs")) runVault(VE_FV_GOCRYPTFS, "gocryptfs");
    if (on("cryptomator")) runVault(VE_FV_CRYPTOMATOR, "cryptomator");
    if (on("cryfs")) runVault(VE_FV_CRYFS, "cryfs");
    std::printf("\n%d checks, %d failed\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
