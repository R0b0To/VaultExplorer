// Interop driver around the app's native CryFS core (uses the real fv_cryfs*.cpp).
//   interop_tool create <vault> <state> <cipher> <blocksize>   create + fill a vault, print its manifest
//   interop_tool dump   <vault> <state>                          open read-only, print the manifest
//   interop_tool modify <vault> <state>                          open read-write, change things, print the manifest
// Password is always "mypassword". Manifest lines: D<TAB>path | F<TAB>path<TAB>size<TAB>sha256 | L<TAB>path<TAB>target
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <memory>
#include <random>
#include <string>
#include <sys/stat.h>
#include <vector>
#include <chrono>
#include "foldervault/fv_storage.h"
#include "foldervault/fv_vault.h"
#include "mbedtls/sha256.h"
using namespace fv;

struct MemSource : ByteSource {
    const Bytes& d; size_t pos = 0;
    explicit MemSource(const Bytes& b) : d(b) {}
    int64_t read(uint8_t* buf, size_t n) override {
        size_t k = std::min(n, d.size() - pos);
        if (k) std::memcpy(buf, d.data() + pos, k);
        pos += k;
        return (int64_t)k;
    }
};
static Bytes rnd(size_t n, uint32_t seed) { std::mt19937 g(seed); Bytes b(n); for (auto& x : b) x = (uint8_t)g(); return b; }
static bool put(Vault& v, const std::string& p, const Bytes& d) { MemSource s(d); return v.importStream(p, s, nullptr); }
static std::optional<Bytes> get(Vault& v, const std::string& p) {
    Bytes out; int64_t off = 0;
    for (;;) {
        auto c = v.readFileChunk(p, off, 100000);
        if (!c) return std::nullopt;
        if (c->empty()) break;
        out.insert(out.end(), c->begin(), c->end());
        off += (int64_t)c->size();
    }
    return out;
}
static std::string sha(const Bytes& b) {
    uint8_t h[32]; mbedtls_sha256(b.data(), b.size(), h, 0);
    static const char* d = "0123456789abcdef"; std::string r;
    for (int i = 0; i < 32; i++) { r += d[h[i] >> 4]; r += d[h[i] & 15]; }
    return r;
}
static std::string join(const std::string& dir, const std::string& n) { return dir.empty() ? n : dir + "/" + n; }
static bool g_verbose = getenv("INTEROP_VERBOSE") != nullptr;
static double nowMs() { return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now().time_since_epoch()).count(); }
static long g_n = 0;
static void walk(Vault& v, const std::string& dir, std::vector<std::string>& out) {
    std::vector<DirEntry> es;
    double t0 = nowMs();
    bool okList = v.listDirectory(dir, es);
    if (g_verbose) std::fprintf(stderr, "list %-50s %5zu entries %8.1f ms\n", dir.c_str(), es.size(), nowMs() - t0);
    if (!okList) { out.push_back("ERROR\tlist\t" + dir); return; }
    for (auto& e : es) {
        std::string p = join(dir, e.name);
        if (e.isDir) { out.push_back("D\t" + p); walk(v, p, out); }
        else {
            double t1 = nowMs();
            auto d = get(v, p);
            if (g_verbose && (++g_n % 200 == 0 || nowMs() - t1 > 500)) std::fprintf(stderr, "  file#%ld %-60s %9zu bytes %8.1f ms\n", g_n, p.c_str(), d ? d->size() : 0, nowMs() - t1);
            out.push_back(d ? "F\t" + p + "\t" + std::to_string(d->size()) + "\t" + sha(*d) : "ERROR\tread\t" + p);
        }
    }
    std::vector<DirEntry> ls;
    if (v.listSymlinks(dir, ls)) for (auto& l : ls) { auto t = v.readSymlink(join(dir, l.name)); out.push_back("L\t" + join(dir, l.name) + "\t" + (t ? *t : "<unreadable>")); }
}
static void printManifest(Vault& v) {
    std::vector<std::string> m; walk(v, "", m);
    std::sort(m.begin(), m.end());
    for (auto& l : m) std::printf("%s\n", l.c_str());
}
static const uint8_t kPw[] = "mypassword";
#define MUST(x) do { if (!(x)) { std::fprintf(stderr, "FAILED: %s (line %d)\n", #x, __LINE__); return 2; } } while (0)

int main(int argc, char** argv) {
    if (argc < 4) { std::fprintf(stderr, "usage: interop_tool create|dump|modify <vault> <state> [cipher blocksize]\n"); return 1; }
    std::string cmd = argv[1], root = argv[2], state = argv[3];
    ::mkdir(root.c_str(), 0755); ::mkdir(state.c_str(), 0755);
    HostEnv env; env.cryfsLocalStateDir = state; env.tempDir = state;
    auto st = std::make_shared<PosixStorage>(root);
    if (cmd == "create") {
        CryfsCreateOptions o; o.cipher = argc > 4 ? argv[4] : "xchacha20-poly1305"; o.blocksizeBytes = argc > 5 ? atoi(argv[5]) : 4096;
        o.scryptLogN = 10; o.scryptR = 8; o.scryptP = 1;
        MUST(createCryfs(*st, kPw, 10, o, env).status == OpenStatus::Ok);
        auto r = openCryfs(st, kPw, 10, false, env);
        MUST(r.status == OpenStatus::Ok && r.vault);
        Vault& v = *r.vault;
        for (auto d : {"docs", "docs/sub", "empty", "m\xC3\xBCnchen \xE2\x82\xAC", "many", "links", "move_src", "move_dst", "olddir", "tmp"}) MUST(v.createDirectory(d));
        MUST(put(v, "docs/a.txt", Bytes{'h', 'e', 'l', 'l', 'o', ',', ' ', 'w', 'o', 'r', 'l', 'd', '\n'}));
        MUST(put(v, "empty.bin", Bytes{}));
        // sizes around the leaf capacity (block 4096, xchacha: leaf = 4002) and the depth-1 / depth-2 boundaries
        size_t sizes[] = {1, 4001, 4002, 4003, 8004, 200000, 1000500, 1000501, 1300000};
        for (size_t i = 0; i < sizeof(sizes) / sizeof(*sizes); i++) MUST(put(v, "docs/sub/size_" + std::to_string(sizes[i]) + ".bin", rnd(sizes[i], 100 + (uint32_t)i)));
        MUST(put(v, "m\xC3\xBCnchen \xE2\x82\xAC/\xD1\x84\xD0\xB0\xD0\xB9\xD0\xBB.bin", rnd(777, 7)));
        MUST(put(v, std::string(255, 'n') + ".txt", rnd(10, 8)) || true);   // 255-char name (may be rejected by the app's validator)
        for (int i = 0; i < 300; i++) { char n[32]; std::snprintf(n, sizeof n, "many/f%03d", i); MUST(put(v, n, rnd(1 + (i * 7) % 100, 1000 + i))); }
        MUST(v.createSymlink("links/ln", "../docs/a.txt"));
        MUST(put(v, "move_src/x.bin", rnd(5000, 55)));
        MUST(v.renameFile("move_src/x.bin", "move_dst/x.bin"));          // cross-directory move (parent pointer)
        MUST(put(v, "olddir/inner.txt", rnd(300, 56)));
        MUST(v.renameFile("olddir", "newdir"));                          // directory rename
        MUST(put(v, "tmp/gone.bin", rnd(9000, 57)));
        MUST(v.deleteFile("tmp/gone.bin"));
        MUST(put(v, "docs/a.txt", rnd(6000, 58)));                       // overwrite with a different size
        printManifest(v);
        v.close();
        return 0;
    }
    bool rw = cmd == "modify";
    auto r = openCryfs(st, kPw, 10, !rw, env);
    if (r.status != OpenStatus::Ok || !r.vault) { std::fprintf(stderr, "open failed (%d): %s\n", (int)r.status, r.message.c_str()); return 3; }
    Vault& v = *r.vault;
    if (const char* only = getenv("INTEROP_ONLY")) {
        double t = nowMs(); auto d = get(v, only);
        std::printf("read %s: %s %zu bytes in %.0f ms\n", only, d ? "ok" : "FAILED", d ? d->size() : 0, nowMs() - t);
        v.close(); return d ? 0 : 4;
    }
    if (rw) {
        std::vector<DirEntry> probe;
        const bool upstreamVault = v.listDirectory("somedir1", probe);   // the layout upstream's test fixture creates
        MUST(v.createDirectory("added_by_app"));
        MUST(put(v, "added_by_app/new.bin", rnd(upstreamVault ? 20000 : 123456, 900)));
        if (upstreamVault) {
            const std::string big = "somedir1/somedir4/some_large_dir_2";
            MUST(put(v, big + "/large_file", rnd(30000, 901)));               // overwrite a deep multi-node file with a bigger one
            MUST(v.deleteFile(big + "/large_dir/large_file"));                 // delete a deep file
            MUST(v.renameFile("somedir1/somedir3/somedir5/some_empty_file", "added_by_app/moved_empty"));   // cross-dir move
            MUST(v.deleteFile(big + "/large_dir/large_dir"));                  // recursively delete a huge directory subtree
        } else {
            MUST(put(v, "docs/sub/size_200000.bin", rnd(210000, 901)));      // overwrite a multi-level file
            MUST(v.deleteFile("many/f010"));
            MUST(v.renameFile("many/f011", "added_by_app/f011_moved"));
        }
        MUST(v.createSymlink("added_by_app/ln2", "new.bin"));
    }
    printManifest(v);
    v.close();
    return 0;
}
